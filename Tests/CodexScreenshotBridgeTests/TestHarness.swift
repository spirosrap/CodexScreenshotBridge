import AppKit
import Foundation
import CodexScreenshotBridgeCore

struct CodexTestCase {
    let name: String
    let run: () async throws -> Void
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

func fail(_ message: String) throws -> Never {
    throw TestFailure(description: message)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String) throws {
    if !condition() {
        throw TestFailure(description: message())
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) throws {
    try expect(actual == expected, "\(message) Expected \(expected), got \(actual)")
}

func makeTestDefaults(file: StaticString = #filePath, line: UInt = #line) -> UserDefaults {
    let suiteName = "CodexScreenshotBridgeTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fatalError("Failed to create test defaults at \(file):\(line)")
    }

    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

func makeTestImage() -> NSImage {
    NSImage(size: NSSize(width: 2, height: 2))
}

func drainAsyncTasks(_ count: Int = 8) async {
    for _ in 0..<count {
        await Task.yield()
    }
}

struct FakeLocalizedError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

final class FakeScreenshotWatcher: ScreenshotWatching {
    var onNewScreenshot: ((URL) -> Void)?
    var startedDirectories: [URL] = []
    var stopCallCount = 0
    var startError: Error?

    func startWatching(directoryURL: URL) throws {
        startedDirectories.append(directoryURL)
        if let startError {
            throw startError
        }
    }

    func stopWatching() {
        stopCallCount += 1
    }

    func emit(_ url: URL) {
        onNewScreenshot?(url)
    }
}

final class FakeClipboardWatcher: ClipboardWatching {
    var onClipboardImage: ((ClipboardWatchEvent) -> Void)?
    var startCallCount = 0
    var stopCallCount = 0
    var ignoredChangeCounts: [Int] = []

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func ignore(changeCount: Int) {
        ignoredChangeCounts.append(changeCount)
    }

    func emit(changeCount: Int = 1, types: [String] = ["public.png"]) {
        onClipboardImage?(ClipboardWatchEvent(changeCount: changeCount, types: types))
    }
}

@MainActor
final class FakeClipboardService: ClipboardServicing {
    var copiedURLs: [URL] = []
    var nextChangeCount = 1
    var copyError: Error?

    func copyImage(at url: URL) throws -> Int {
        copiedURLs.append(url)
        if let copyError {
            throw copyError
        }

        return nextChangeCount
    }
}

@MainActor
final class FakeAutoPasteService: CodexAutoPasteServing {
    var accessibilityPermissionGranted = true
    var screenRecordingPermissionGranted = false
    var accessibilityPromptRequests: [Bool] = []
    var activateCalls: [String?] = []
    var activationError: Error?
    var requestScreenRecordingResult = false

    func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        accessibilityPromptRequests.append(prompt)
        return accessibilityPermissionGranted
    }

    func hasAccessibilityPermission() -> Bool {
        accessibilityPermissionGranted
    }

    func hasScreenRecordingPermission() -> Bool {
        screenRecordingPermissionGranted
    }

    func requestScreenRecordingPermission() -> Bool {
        screenRecordingPermissionGranted = requestScreenRecordingResult
        return requestScreenRecordingResult
    }

    func activateCodexAndPaste(codexBundleIdentifier: String?) async throws {
        activateCalls.append(codexBundleIdentifier)
        if let activationError {
            throw activationError
        }
    }
}

final class FakePasteboardWriter: PasteboardWriting {
    var changeCount: Int
    var clearContentsCallCount = 0
    var wroteImageCount = 0
    var wroteFileURLCount = 0
    var imageWriteResult = true
    var fileURLWriteResult = false

    init(changeCount: Int = 1) {
        self.changeCount = changeCount
    }

    func clearContents() {
        clearContentsCallCount += 1
    }

    func write(image: NSImage) -> Bool {
        wroteImageCount += 1
        return imageWriteResult
    }

    func write(fileURL: URL) -> Bool {
        wroteFileURLCount += 1
        return fileURLWriteResult
    }
}

struct FakeImageLoader: ImageLoading {
    var image: NSImage?

    func loadImage(at url: URL) -> NSImage? {
        image
    }
}
