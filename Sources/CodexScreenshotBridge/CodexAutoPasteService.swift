import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit
import Vision

@MainActor
final class CodexAutoPasteService {
    private enum ComposerLayout {
        case conversation
        case firstPrompt
    }

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

    func activateCodexAndPaste(codexBundleIdentifier: String?) async throws {
        guard ensureAccessibilityPermission(prompt: true) else {
            throw AutoPasteError.accessibilityPermissionMissing
        }

        try await waitForScreenshotModifiersToRelease()
        try await waitForScreenshotUIToClose()
        let runningApp = try await activateCodexApp(bundleIdentifier: codexBundleIdentifier)
        await bringAppToFront(runningApp)
        try await Task.sleep(for: .milliseconds(60))

        let layout = await composerLayout(for: runningApp.processIdentifier)

        clickLikelyComposerArea(in: runningApp, layout: layout)
        try await Task.sleep(for: .milliseconds(50))

        try sendCommandVGlobal()
        try await reinforceComposerFocus(in: runningApp, layout: layout)
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
        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != currentPID else {
                return false
            }

            if let ownBundleIdentifier, app.bundleIdentifier == ownBundleIdentifier {
                return false
            }

            // Ignore helper/process wrappers that cannot receive paste into UI.
            if let bundle = app.bundleIdentifier?.lowercased() {
                if bundle.hasPrefix("com.apple.") {
                    return false
                }
                if bundle.contains("webkit") {
                    return false
                }
            }

            return true
        }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return runningApps.first { $0.bundleIdentifier == bundleIdentifier }
        }

        if let exactCodexBundle = runningApps.first(where: { $0.bundleIdentifier == "com.openai.codex" }) {
            return exactCodexBundle
        }

        if let exactChatGPTBundle = runningApps.first(where: { $0.bundleIdentifier == "com.openai.chat" }) {
            return exactChatGPTBundle
        }

        if let exactNameMatch = runningApps.first(where: {
            $0.localizedName?.caseInsensitiveCompare("Codex") == .orderedSame
        }) {
            return exactNameMatch
        }

        if let openAINameMatch = runningApps.first(where: {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains("chatgpt")
        }) {
            return openAINameMatch
        }

        return runningApps.first(where: {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains("codex") ||
                ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains("codex")
        })
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
        let candidates = [
            URL(fileURLWithPath: "/Applications/Codex.app"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("Codex.app", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("ChatGPT.app", isDirectory: true),
        ]

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private func sendCommandVGlobal() throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw AutoPasteError.keyInjectionFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func bringAppToFront(_ app: NSRunningApplication) async {
        for _ in 0..<20 {
            app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                return
            }

            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    private func waitForScreenshotModifiersToRelease() async throws {
        let modifierKeys: [CGKeyCode] = [
            54, 55, // command
            56, 60, // shift
            58, 61, // option
            59, 62, // control
        ]

        for _ in 0..<250 {
            let anyDown = modifierKeys.contains {
                CGEventSource.keyState(.combinedSessionState, key: $0)
            }

            if !anyDown {
                return
            }

            try await Task.sleep(for: .milliseconds(40))
        }

        throw AutoPasteError.screenshotGestureStillActive
    }

    private func waitForScreenshotUIToClose() async throws {
        for _ in 0..<160 {
            let frontmost = NSWorkspace.shared.frontmostApplication
            let bundleID = frontmost?.bundleIdentifier?.lowercased() ?? ""
            let appName = frontmost?.localizedName?.lowercased() ?? ""

            let screenshotActive = bundleID == "com.apple.screenshot" ||
                appName.contains("screenshot")

            if !screenshotActive {
                return
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        throw AutoPasteError.screenshotGestureStillActive
    }

    private func clickLikelyComposerArea(in app: NSRunningApplication, layout: ComposerLayout) {
        guard let bounds = focusedWindowBounds(for: app.processIdentifier),
              let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        for clickPoint in composerClickPoints(in: bounds, layout: layout) {
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

    private func reinforceComposerFocus(in app: NSRunningApplication, layout: ComposerLayout) async throws {
        try await Task.sleep(for: .milliseconds(60))
        await bringAppToFront(app)

        clickLikelyComposerArea(in: app, layout: layout)
    }

    private func composerLayout(for processID: pid_t) async -> ComposerLayout {
        if await initialPromptScreenIsVisible(for: processID) {
            return .firstPrompt
        }

        return .conversation
    }

    private func composerClickPoints(in bounds: CGRect, layout: ComposerLayout) -> [CGPoint] {
        switch layout {
        case .conversation:
            return makePoints(
                in: bounds,
                xFractions: [0.5],
                yFractions: [0.91]
            )
        case .firstPrompt:
            // Fresh projects use the centered "What should we work on?" composer.
            return makePoints(
                in: bounds,
                xFractions: [0.42, 0.54, 0.66],
                yFractions: [0.39, 0.43]
            )
        }
    }

    private func makePoints(
        in bounds: CGRect,
        xFractions: [CGFloat],
        yFractions: [CGFloat]
    ) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(xFractions.count * yFractions.count)

        for yFraction in yFractions {
            let y = bounds.minY + (bounds.height * yFraction)
            for xFraction in xFractions {
                points.append(
                    CGPoint(
                        x: bounds.minX + (bounds.width * xFraction),
                        y: y
                    )
                )
            }
        }

        return points
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

    private func initialPromptScreenIsVisible(for processID: pid_t) async -> Bool {
        guard #available(macOS 14.0, *) else {
            return false
        }

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            return false
        }

        do {
            guard let image = try await captureFocusedWindowImage(for: processID),
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
    private func captureFocusedWindowImage(for processID: pid_t) async throws -> CGImage? {
        guard let focusedBounds = focusedWindowBounds(for: processID) else {
            return nil
        }

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
        configuration.width = max(Int(window.frame.width), 1)
        configuration.height = max(Int(window.frame.height), 1)
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
        request.regionOfInterest = CGRect(x: 0.30, y: 0.52, width: 0.68, height: 0.22)

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
}
