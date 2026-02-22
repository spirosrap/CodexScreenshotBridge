import Foundation

final class ScreenshotWatcher: @unchecked Sendable {
    enum WatcherError: LocalizedError {
        case directoryMissing(String)
        case cannotOpenDirectory(String)

        var errorDescription: String? {
            switch self {
            case let .directoryMissing(path):
                return "Folder not found: \(path)"
            case let .cannotOpenDirectory(path):
                return "Could not open folder for watch events: \(path)"
            }
        }
    }

    var onNewScreenshot: ((URL) -> Void)?

    private let queue = DispatchQueue(label: "CodexScreenshotBridge.WatcherQueue")
    private var source: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: CInt = -1
    private var watchedDirectoryURL: URL?
    private var seenFileNames: Set<String> = []
    private var pendingScanWorkItem: DispatchWorkItem?

    func startWatching(directoryURL: URL) throws {
        try queue.sync {
            try startWatchingOnQueue(directoryURL: directoryURL)
        }
    }

    func stopWatching() {
        queue.sync {
            stopWatchingOnQueue()
        }
    }

    private func startWatchingOnQueue(directoryURL: URL) throws {
        stopWatchingOnQueue()

        let standardizedDirectory = directoryURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardizedDirectory.path) else {
            throw WatcherError.directoryMissing(standardizedDirectory.path)
        }

        watchedDirectoryURL = standardizedDirectory
        seenFileNames = Set((try? Self.listCandidateFiles(in: standardizedDirectory)
            .map(\.lastPathComponent)) ?? [])

        directoryFileDescriptor = open(standardizedDirectory.path, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else {
            throw WatcherError.cannotOpenDirectory(standardizedDirectory.path)
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename, .link, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleScanOnQueue()
        }

        source.setCancelHandler { [weak self] in
            guard let self else {
                return
            }

            if self.directoryFileDescriptor >= 0 {
                close(self.directoryFileDescriptor)
                self.directoryFileDescriptor = -1
            }
        }

        self.source = source
        source.resume()
    }

    private func stopWatchingOnQueue() {
        pendingScanWorkItem?.cancel()
        pendingScanWorkItem = nil

        if let source {
            self.source = nil
            source.cancel()
        } else if directoryFileDescriptor >= 0 {
            close(directoryFileDescriptor)
            directoryFileDescriptor = -1
        }

        watchedDirectoryURL = nil
        seenFileNames.removeAll()
    }

    private func scheduleScanOnQueue() {
        pendingScanWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.scanForNewScreenshotsOnQueue()
        }

        pendingScanWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func scanForNewScreenshotsOnQueue() {
        guard let watchedDirectoryURL else {
            return
        }

        guard let candidates = try? Self.listCandidateFiles(in: watchedDirectoryURL) else {
            return
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return lhsDate < rhsDate
        }

        for candidate in sortedCandidates {
            let fileName = candidate.lastPathComponent
            if seenFileNames.contains(fileName) {
                continue
            }

            seenFileNames.insert(fileName)

            guard Self.waitUntilReadable(candidate) else {
                continue
            }

            onNewScreenshot?(candidate)
        }
    }

    private static func listCandidateFiles(in directoryURL: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .nameKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: options
        ).filter { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                return false
            }

            return isLikelyScreenshotName(url.deletingPathExtension().lastPathComponent) &&
                isSupportedImageExtension(url.pathExtension)
        }
    }

    private static func isLikelyScreenshotName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("screenshot") || lowered.contains("screen shot")
    }

    private static func isSupportedImageExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "heic", "tiff", "pdf":
            return true
        default:
            return false
        }
    }

    private static func waitUntilReadable(_ url: URL) -> Bool {
        for _ in 0..<8 {
            if FileManager.default.isReadableFile(atPath: url.path),
               let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? NSNumber,
               size.intValue > 0 {
                return true
            }

            Thread.sleep(forTimeInterval: 0.08)
        }

        return FileManager.default.isReadableFile(atPath: url.path)
    }
}
