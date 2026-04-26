import Foundation

package enum ScreenshotFileClassifier {
    package static func isLikelyScreenshotName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("screenshot") || lowered.contains("screen shot")
    }

    package static func isSupportedImageExtension(_ ext: String) -> Bool {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "heic", "tiff", "pdf":
            return true
        default:
            return false
        }
    }

    package static func matches(_ url: URL) -> Bool {
        isLikelyScreenshotName(url.deletingPathExtension().lastPathComponent) &&
            isSupportedImageExtension(url.pathExtension)
    }
}

package enum ScreenshotDirectoryScanner {
    package static let readableRetryCount = 20
    package static let readableRetryInterval: TimeInterval = 0.005

    package static func listCandidateFiles(
        in directoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .nameKey]
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]

        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: options
        ).filter { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                return false
            }

            return ScreenshotFileClassifier.matches(url)
        }
    }

    package static func sortCandidatesByCreationDate(_ candidates: [URL]) -> [URL] {
        candidates.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return lhsDate < rhsDate
        }
    }

    package static func waitUntilReadable(
        _ url: URL,
        fileManager: FileManager = .default,
        sleep: (TimeInterval) -> Void = Thread.sleep
    ) -> Bool {
        for _ in 0..<readableRetryCount {
            if fileManager.isReadableFile(atPath: url.path),
               let attributes = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? NSNumber,
               size.intValue > 0 {
                return true
            }

            sleep(readableRetryInterval)
        }

        return fileManager.isReadableFile(atPath: url.path)
    }
}
