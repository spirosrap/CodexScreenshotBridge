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

func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return true
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    return await condition()
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
    var clipboardReplacementTypes: [[String]] = []
    var clipboardReplacementChangeCount: Int?
    var clipboardReplacementError: Error?

    func copyImage(at url: URL) throws -> Int {
        copiedURLs.append(url)
        if let copyError {
            throw copyError
        }

        return nextChangeCount
    }

    func copyFileURL(at url: URL) throws -> Int {
        copiedURLs.append(url)
        if let copyError {
            throw copyError
        }

        return nextChangeCount
    }

    func replaceClipboardImageWithTemporaryFile(types: [String]) throws -> Int? {
        clipboardReplacementTypes.append(types)
        if let clipboardReplacementError {
            throw clipboardReplacementError
        }

        return clipboardReplacementChangeCount
    }
}

@MainActor
final class FakeScreenshotCaptureService: ScreenshotCaptureServicing {
    var capturedURL: URL?
    var captureError: Error?
    var captureCallCount = 0

    func captureInteractiveScreenshot() async throws -> URL? {
        captureCallCount += 1
        if let captureError {
            throw captureError
        }

        return capturedURL
    }
}

final class FakeScreenshotSystemSettingsService: ScreenshotSystemSettingsServicing {
    var state: ScreenshotFloatingThumbnailState = .enabled
    var disableCallCount = 0
    var disableError: Error?

    func floatingThumbnailState() -> ScreenshotFloatingThumbnailState {
        state
    }

    func disableFloatingThumbnail() throws {
        disableCallCount += 1
        if let disableError {
            throw disableError
        }

        state = .disabled
    }
}

@MainActor
final class FakeAutoPasteService: CodexAutoPasteServing {
    var accessibilityPermissionGranted = true
    var screenRecordingPermissionGranted = false
    var accessibilityPromptRequests: [Bool] = []
    var activateCalls: [String?] = []
    var detectInitialPromptScreenCalls: [Bool] = []
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

    func activateCodexAndPaste(
        codexBundleIdentifier: String?,
        detectInitialPromptScreen: Bool
    ) async throws -> CodexAutoPasteReport {
        activateCalls.append(codexBundleIdentifier)
        detectInitialPromptScreenCalls.append(detectInitialPromptScreen)
        if let activationError {
            throw activationError
        }

        return CodexAutoPasteReport(
            stages: [
                AutoPasteStageTiming(name: "fake", milliseconds: 1),
            ]
        )
    }
}

final class FakePasteboardWriter: PasteboardWriting {
    var changeCount: Int
    var clearContentsCallCount = 0
    var wroteImageCount = 0
    var wroteFileURLCount = 0
    var writtenFileURLs: [URL] = []
    var dataByType: [String: Data] = [:]
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
        writtenFileURLs.append(fileURL)
        return fileURLWriteResult
    }

    func data(forType rawType: String) -> Data? {
        dataByType[rawType]
    }
}

struct FakeImageLoader: ImageLoading {
    var image: NSImage?

    func loadImage(at url: URL) -> NSImage? {
        image
    }
}
