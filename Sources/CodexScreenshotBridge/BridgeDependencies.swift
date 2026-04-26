import AppKit
import Foundation

package protocol ScreenshotWatching: AnyObject {
    var onNewScreenshot: ((URL) -> Void)? { get set }
    func startWatching(directoryURL: URL) throws
    func stopWatching()
}

package protocol ClipboardWatching: AnyObject {
    var onClipboardImage: ((ClipboardWatchEvent) -> Void)? { get set }
    func start()
    func stop()
    func ignore(changeCount: Int)
}

@MainActor
package protocol ClipboardServicing: AnyObject {
    @discardableResult
    func copyImage(at url: URL) throws -> Int
    @discardableResult
    func copyFileURL(at url: URL) throws -> Int
    @discardableResult
    func replaceClipboardImageWithTemporaryFile(types: [String]) throws -> Int?
}

@MainActor
package protocol ScreenshotCaptureServicing: AnyObject {
    func captureInteractiveScreenshot() async throws -> URL?
}

package struct AutoPasteStageTiming: Equatable {
    package let name: String
    package let milliseconds: Int

    package init(name: String, milliseconds: Int) {
        self.name = name
        self.milliseconds = milliseconds
    }
}

package struct CodexAutoPasteReport: Equatable {
    package let stages: [AutoPasteStageTiming]

    package init(stages: [AutoPasteStageTiming]) {
        self.stages = stages
    }

    package var elapsedMilliseconds: Int {
        stages.reduce(0) { total, stage in
            total + stage.milliseconds
        }
    }

    package var summary: String {
        stages.map { stage in
            "\(stage.name) \(stage.milliseconds)ms"
        }.joined(separator: ", ")
    }
}

@MainActor
package protocol CodexAutoPasteServing: AnyObject {
    func ensureAccessibilityPermission(prompt: Bool) -> Bool
    func hasAccessibilityPermission() -> Bool
    func hasScreenRecordingPermission() -> Bool
    func requestScreenRecordingPermission() -> Bool
    func activateCodexAndPaste(
        codexBundleIdentifier: String?,
        detectInitialPromptScreen: Bool
    ) async throws -> CodexAutoPasteReport
}
