import Foundation

@MainActor
package final class ScreenshotCaptureService: ScreenshotCaptureServicing {
    package enum CaptureError: LocalizedError {
        case launchFailed
        case captureFailed(Int32)

        package var errorDescription: String? {
            switch self {
            case .launchFailed:
                return "Could not start macOS screenshot capture."
            case let .captureFailed(status):
                return "macOS screenshot capture failed with exit status \(status)."
            }
        }
    }

    private let outputDirectoryProvider: () throws -> URL

    package init(
        outputDirectoryProvider: @escaping () throws -> URL = {
            let baseURL = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory

            return baseURL
                .appendingPathComponent("CodexScreenshotBridge", isDirectory: true)
                .appendingPathComponent("DirectCaptures", isDirectory: true)
        }
    ) {
        self.outputDirectoryProvider = outputDirectoryProvider
    }

    package func captureInteractiveScreenshot() async throws -> URL? {
        let directoryURL = try outputDirectoryProvider()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let outputURL = directoryURL.appendingPathComponent(
            "Bridge-Capture-\(Self.fileNameTimestamp()).png"
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", outputURL.path]

        do {
            try process.run()
        } catch {
            throw CaptureError.launchFailed
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume()
            }
        }

        guard process.terminationStatus == 0 else {
            if !FileManager.default.fileExists(atPath: outputURL.path) {
                return nil
            }

            throw CaptureError.captureFailed(process.terminationStatus)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return nil
        }

        return outputURL
    }

    private static func fileNameTimestamp() -> String {
        String(Int(Date().timeIntervalSince1970 * 1_000))
    }
}
