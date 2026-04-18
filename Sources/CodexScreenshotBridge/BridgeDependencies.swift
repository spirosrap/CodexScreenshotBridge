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
}

@MainActor
package protocol CodexAutoPasteServing: AnyObject {
    func ensureAccessibilityPermission(prompt: Bool) -> Bool
    func hasAccessibilityPermission() -> Bool
    func hasScreenRecordingPermission() -> Bool
    func requestScreenRecordingPermission() -> Bool
    func activateCodexAndPaste(codexBundleIdentifier: String?) async throws
}
