import Foundation

final class ScreenshotWatcher: @unchecked Sendable, ScreenshotWatching {
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
    private let scanDebounceDelay: DispatchTimeInterval = .milliseconds(5)

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
        seenFileNames = Set((try? ScreenshotDirectoryScanner.listCandidateFiles(in: standardizedDirectory)
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
        queue.asyncAfter(deadline: .now() + scanDebounceDelay, execute: workItem)
    }

    private func scanForNewScreenshotsOnQueue() {
        guard let watchedDirectoryURL else {
            return
        }

        guard let candidates = try? ScreenshotDirectoryScanner.listCandidateFiles(in: watchedDirectoryURL) else {
            return
        }

        let newCandidates = candidates.filter { candidate in
            !seenFileNames.contains(candidate.lastPathComponent)
        }
        let sortedCandidates = ScreenshotDirectoryScanner.sortCandidatesByCreationDate(newCandidates)

        for candidate in sortedCandidates {
            let fileName = candidate.lastPathComponent
            seenFileNames.insert(fileName)

            guard ScreenshotDirectoryScanner.waitUntilReadable(candidate) else {
                continue
            }

            onNewScreenshot?(candidate)
        }
    }
}
