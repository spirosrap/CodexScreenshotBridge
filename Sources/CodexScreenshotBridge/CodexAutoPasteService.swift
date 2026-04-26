import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit
import Vision

@MainActor
final class CodexAutoPasteService: CodexAutoPasteServing {
    private static let initialScreenMarkers = [
        "what should we",
        "think of a suitable starter task",
        "connect your favorite apps to codex",
    ]

    enum AutoPasteError: LocalizedError {
        case accessibilityPermissionMissing
        case codexNotFound
        case keyInjectionFailed
        case screenshotGestureStillActive

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionMissing:
                return "Accessibility permission is required for auto-paste."
            case .codexNotFound:
                return "Could not find the Codex app. Launch it first or set bundle ID."
            case .keyInjectionFailed:
                return "Could not synthesize Cmd+V keyboard event."
            case .screenshotGestureStillActive:
                return "Screenshot gesture/UI still active. Try again after capture completes."
            }
        }
    }

    func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        let optionKey = "AXTrustedCheckOptionPrompt"
        let options = [optionKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func hasAccessibilityPermission() -> Bool {
        ensureAccessibilityPermission(prompt: false)
    }

    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func requestScreenRecordingPermission() -> Bool {
        hasScreenRecordingPermission() || CGRequestScreenCaptureAccess()
    }

    private let pasteKey: CGKeyCode = 9
    private let conversationLayoutCacheLifetime: TimeInterval = 600
    private let firstPromptLayoutCacheLifetime: TimeInterval = 12
    private let postStartupConversationCooldown: TimeInterval = 45
    private var cachedComposerLayout: CachedComposerLayout?
    private var startupFallbackConsumedProcessID: pid_t?
    private var forceConversationLayoutUntil: Date?

    func activateCodexAndPaste(
        codexBundleIdentifier: String?,
        detectInitialPromptScreen: Bool
    ) async throws -> CodexAutoPasteReport {
        let timing = AutoPasteTimingRecorder()

        guard ensureAccessibilityPermission(prompt: true) else {
            throw AutoPasteError.accessibilityPermissionMissing
        }
        timing.mark("permission")

        let runningApp = try await activateCodexApp(bundleIdentifier: codexBundleIdentifier)
        timing.mark("find-app")

        try await waitForScreenshotModifiersToRelease(
            maxChecks: 120,
            interval: .milliseconds(5),
            failOnTimeout: false
        )
        timing.mark("modifiers")

        if !detectInitialPromptScreen {
            if !isFrontmost(runningApp) {
                await bringAppToFront(
                    runningApp,
                    maxAttempts: 4,
                    interval: .milliseconds(5)
                )
                try await Task.sleep(for: .milliseconds(3))
                timing.mark("activate")
            }

            await bringAppToFront(
                runningApp,
                maxAttempts: 1,
                interval: .milliseconds(1)
            )

            let didConfirmFocus = try await focusConversationComposerIfPossible(
                processID: runningApp.processIdentifier
            )
            timing.mark(didConfirmFocus ? "focus-conversation" : "focus-unconfirmed")

            try sendCommandVGlobal()
            timing.mark("paste-direct")
            return timing.report()
        }

        if !isFrontmost(runningApp) {
            await bringAppToFront(
                runningApp,
                maxAttempts: 4,
                interval: .milliseconds(5)
            )
            try await Task.sleep(for: .milliseconds(3))
            timing.mark("activate")
        }

        if try await focusConversationComposerIfPossible(processID: runningApp.processIdentifier) {
            timing.mark("focus-conversation-fast")
            try sendCommandVGlobal()
            timing.mark("paste-fast")
            return timing.report()
        }
        timing.mark("focus-conversation-miss")

        let layout = await composerLayout(for: runningApp.processIdentifier)
        timing.mark(layout == .firstPrompt ? "layout-startup" : "layout-conversation")
        var usedStartupComposerPath = layout == .firstPrompt

        clickPoints(
            composerActivationPoints(in: runningApp.processIdentifier, layout: layout)
        )
        try await Task.sleep(for: .milliseconds(18))
        timing.mark("focus")

        if layout == .firstPrompt {
            clickPoints(
                composerEditorFocusPoints(in: runningApp.processIdentifier, layout: layout)
            )
            try await Task.sleep(for: .milliseconds(60))
            timing.mark("startup-editor")
        } else if startupFallbackIsAvailable(for: runningApp.processIdentifier),
                  focusedElementKind(expectedPID: runningApp.processIdentifier, allowWebArea: false) != .textLike {
            clickPoints(
                composerActivationPoints(in: runningApp.processIdentifier, layout: .firstPrompt)
            )
            try await Task.sleep(for: .milliseconds(18))
            clickPoints(
                composerEditorFocusPoints(in: runningApp.processIdentifier, layout: .firstPrompt)
            )
            try await Task.sleep(for: .milliseconds(60))
            usedStartupComposerPath = true
            timing.mark("startup-fallback")
        }

        try sendCommandVGlobal()
        timing.mark("paste-detected")
        if usedStartupComposerPath {
            markStartupComposerPathUsed(for: runningApp.processIdentifier)
        }
        return timing.report()
    }

    private func activateCodexApp(bundleIdentifier: String?) async throws -> NSRunningApplication {
        if let running = findRunningCodex(bundleIdentifier: bundleIdentifier) {
            return running
        }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                throw AutoPasteError.codexNotFound
            }
            return try await openApplication(at: appURL)
        }

        if let codexURL = fallbackCodexAppURL() {
            return try await openApplication(at: codexURL)
        }

        throw AutoPasteError.codexNotFound
    }

    private func findRunningCodex(bundleIdentifier: String?) -> NSRunningApplication? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let runningApps = NSWorkspace.shared.runningApplications
        let descriptors = runningApps.map {
            CodexRunningAppDescriptor(
                processIdentifier: $0.processIdentifier,
                bundleIdentifier: $0.bundleIdentifier,
                localizedName: $0.localizedName
            )
        }

        guard let match = CodexAppMatcher.bestMatch(
            bundleIdentifier: bundleIdentifier,
            currentPID: currentPID,
            ownBundleIdentifier: ownBundleIdentifier,
            candidates: descriptors
        ) else {
            return nil
        }

        return runningApps.first { $0.processIdentifier == match.processIdentifier }
    }

    private func openApplication(at url: URL) async throws -> NSRunningApplication {
        try await withCheckedThrowingContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true

            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
                if let app {
                    continuation.resume(returning: app)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(throwing: AutoPasteError.codexNotFound)
            }
        }
    }

    private func fallbackCodexAppURL() -> URL? {
        let fileManager = FileManager.default
        let candidates = CodexAppMatcher.fallbackApplicationURLs(
            homeDirectory: fileManager.homeDirectoryForCurrentUser
        )

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private func sendCommandVGlobal() throws {
        try sendKeyGlobal(pasteKey, flags: .maskCommand)
    }

    private func sendKeyGlobal(_ keyCode: CGKeyCode, flags: CGEventFlags = []) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw AutoPasteError.keyInjectionFailed
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func bringAppToFront(
        _ app: NSRunningApplication,
        maxAttempts: Int = 20,
        interval: Duration = .milliseconds(80)
    ) async {
        for _ in 0..<maxAttempts {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return
            }

            try? await Task.sleep(for: interval)
        }
    }

    private func isFrontmost(_ app: NSRunningApplication) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private enum FocusedElementKind {
        case textLike
        case other
        case unavailable
    }

    private func focusedElementKind(expectedPID: pid_t, allowWebArea: Bool) -> FocusedElementKind {
        let systemElement = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        ) == .success,
        let focusedObject else {
            return .unavailable
        }

        let focusedElement = focusedObject as! AXUIElement
        var focusedPID: pid_t = 0
        AXUIElementGetPid(focusedElement, &focusedPID)

        guard focusedPID == expectedPID else {
            return .other
        }

        var roleObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXRoleAttribute as CFString,
            &roleObject
        ) == .success,
        let role = roleObject as? String else {
            return .other
        }

        switch role {
        case "AXTextArea",
             "AXTextField",
             "AXSearchField",
             "AXComboBox":
            return .textLike
        case "AXWebArea":
            return allowWebArea ? .textLike : .other
        default:
            return .other
        }
    }

    private func waitForScreenshotModifiersToRelease(
        maxChecks: Int = 250,
        interval: Duration = .milliseconds(40),
        failOnTimeout: Bool = true
    ) async throws {
        let modifierKeys: [CGKeyCode] = [
            54, 55, // command
            56, 60, // shift
            58, 61, // option
            59, 62, // control
        ]

        for _ in 0..<maxChecks {
            let anyDown = modifierKeys.contains {
                CGEventSource.keyState(.combinedSessionState, key: $0)
            }

            if !anyDown {
                return
            }

            try await Task.sleep(for: interval)
        }

        if failOnTimeout {
            throw AutoPasteError.screenshotGestureStillActive
        }
    }

    private func clickPoints(_ points: [CGPoint]) {
        guard !points.isEmpty,
              let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        for clickPoint in points {
            let move = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: clickPoint,
                mouseButton: .left
            )
            let down = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: clickPoint,
                mouseButton: .left
            )
            let up = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: clickPoint,
                mouseButton: .left
            )

            move?.post(tap: .cghidEventTap)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func composerActivationPoints(in processID: pid_t, layout: CodexComposerLayout) -> [CGPoint] {
        guard let bounds = focusedWindowBounds(for: processID) else {
            return []
        }

        return ComposerPointCalculator.activationPoints(in: bounds, layout: layout)
    }

    private func composerEditorFocusPoints(in processID: pid_t, layout: CodexComposerLayout) -> [CGPoint] {
        guard let bounds = focusedWindowBounds(for: processID) else {
            return []
        }

        return ComposerPointCalculator.editorFocusPoints(in: bounds, layout: layout)
    }

    private func focusConversationComposerIfPossible(processID: pid_t) async throws -> Bool {
        if focusedElementKind(expectedPID: processID, allowWebArea: false) == .textLike {
            return true
        }

        for _ in 0..<2 {
            clickPoints(
                composerActivationPoints(in: processID, layout: .conversation)
            )

            if try await waitForTextFocus(processID: processID) {
                return true
            }
        }

        return false
    }

    private func waitForTextFocus(
        processID: pid_t,
        maxChecks: Int = 12,
        interval: Duration = .milliseconds(15)
    ) async throws -> Bool {
        for _ in 0..<maxChecks {
            if focusedElementKind(expectedPID: processID, allowWebArea: false) == .textLike {
                return true
            }

            try await Task.sleep(for: interval)
        }

        return focusedElementKind(expectedPID: processID, allowWebArea: false) == .textLike
    }

    private func composerLayout(for processID: pid_t) async -> CodexComposerLayout {
        let focusedBounds = focusedWindowBounds(for: processID)
        let now = Date()

        if let forceConversationLayoutUntil {
            if now < forceConversationLayoutUntil {
                return .conversation
            }

            self.forceConversationLayoutUntil = nil
        }

        if let focusedBounds,
           let cachedComposerLayout,
           cachedComposerLayout.matches(
               processID: processID,
               focusedBounds: focusedBounds,
               now: now,
               lifetime: cacheLifetime(for: cachedComposerLayout.layout)
           ) {
            return cachedComposerLayout.layout
        }

        let layout: CodexComposerLayout
        if await initialPromptScreenIsVisible(for: processID, focusedBounds: focusedBounds) {
            layout = .firstPrompt
        } else {
            layout = .conversation
        }

        if let focusedBounds {
            cachedComposerLayout = CachedComposerLayout(
                processID: processID,
                focusedBounds: focusedBounds,
                layout: layout,
                createdAt: now
            )
        }

        return layout
    }

    private func startupFallbackIsAvailable(for processID: pid_t) -> Bool {
        startupFallbackConsumedProcessID != processID
    }

    private func markStartupComposerPathUsed(for processID: pid_t) {
        startupFallbackConsumedProcessID = processID
        forceConversationLayoutUntil = Date().addingTimeInterval(postStartupConversationCooldown)
        cachedComposerLayout = nil
    }

    private func cacheLifetime(for layout: CodexComposerLayout) -> TimeInterval {
        switch layout {
        case .conversation:
            return conversationLayoutCacheLifetime
        case .firstPrompt:
            return firstPromptLayoutCacheLifetime
        }
    }

    private func focusedWindowBounds(for processID: pid_t) -> CGRect? {
        let appElement = AXUIElementCreateApplication(processID)
        var windowObject: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowObject
        ) == .success,
        let windowObject else {
            return nil
        }

        let windowElement = windowObject as! AXUIElement
        var positionObject: CFTypeRef?
        var sizeObject: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            windowElement,
            kAXPositionAttribute as CFString,
            &positionObject
        ) == .success,
        AXUIElementCopyAttributeValue(
            windowElement,
            kAXSizeAttribute as CFString,
            &sizeObject
        ) == .success,
        let positionObject,
        let sizeObject else {
            return nil
        }

        let positionValue = positionObject as! AXValue
        let sizeValue = sizeObject as! AXValue

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetType(positionValue) == .cgPoint,
              AXValueGetType(sizeValue) == .cgSize,
              AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private func initialPromptScreenIsVisible(for processID: pid_t, focusedBounds: CGRect?) async -> Bool {
        guard #available(macOS 14.0, *) else {
            return false
        }

        guard CGPreflightScreenCaptureAccess() else {
            return false
        }

        do {
            guard let focusedBounds,
                  let image = try await captureFocusedWindowImage(for: processID, focusedBounds: focusedBounds),
                  let recognizedText = recognizeInitialScreenText(in: image) else {
                return false
            }

            let normalizedText = recognizedText.lowercased()
            return Self.initialScreenMarkers.contains(where: normalizedText.contains)
        } catch {
            return false
        }
    }

    @available(macOS 14.0, *)
    private func captureFocusedWindowImage(for processID: pid_t, focusedBounds: CGRect) async throws -> CGImage? {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        let candidates = shareableContent.windows.filter { window in
            window.owningApplication?.processID == processID &&
                window.windowLayer == 0
        }

        guard let window = candidates.min(by: { lhs, rhs in
            windowMatchScore(lhs.frame, target: focusedBounds) <
                windowMatchScore(rhs.frame, target: focusedBounds)
        }) else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let outputSize = CodexWindowCaptureSizer.outputSize(for: window.frame)
        configuration.width = Int(outputSize.width)
        configuration.height = Int(outputSize.height)
        configuration.scalesToFit = true

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) { image, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }

                continuation.resume(
                    throwing: error ?? AutoPasteError.codexNotFound
                )
            }
        }
    }

    private func windowMatchScore(_ candidate: CGRect, target: CGRect) -> CGFloat {
        abs(candidate.minX - target.minX) +
            abs(candidate.minY - target.minY) +
            abs(candidate.width - target.width) +
            abs(candidate.height - target.height)
    }

    private func recognizeInitialScreenText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.regionOfInterest = CGRect(x: 0.08, y: 0.18, width: 0.84, height: 0.72)

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let lines = (request.results ?? []).compactMap { result in
            result.topCandidates(1).first?.string
        }

        guard !lines.isEmpty else {
            return nil
        }

        return lines.joined(separator: "\n")
    }

    private struct CachedComposerLayout {
        let processID: pid_t
        let focusedBounds: CGRect
        let layout: CodexComposerLayout
        let createdAt: Date

        func matches(
            processID: pid_t,
            focusedBounds: CGRect,
            now: Date,
            lifetime: TimeInterval
        ) -> Bool {
            self.processID == processID &&
                now.timeIntervalSince(createdAt) <= lifetime &&
                self.focusedBounds.isApproximatelyEqual(to: focusedBounds, tolerance: 2)
        }
    }

    private final class AutoPasteTimingRecorder {
        private var stages: [AutoPasteStageTiming] = []
        private var lastMark = Date()

        func mark(_ name: String) {
            let now = Date()
            stages.append(
                AutoPasteStageTiming(
                    name: name,
                    milliseconds: max(Int((now.timeIntervalSince(lastMark) * 1_000).rounded()), 0)
                )
            )
            lastMark = now
        }

        func report() -> CodexAutoPasteReport {
            CodexAutoPasteReport(stages: stages)
        }
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance &&
            abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}
