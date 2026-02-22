import AppKit
import ApplicationServices
import Foundation

@MainActor
final class CodexAutoPasteService {
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
        try await Task.sleep(for: .milliseconds(120))

        clickLikelyComposerArea(in: runningApp)
        try await Task.sleep(for: .milliseconds(90))

        try sendCommandVGlobal()

        // If focused element is still not a likely text receiver, run one fallback attempt.
        if focusedElementKind(expectedPID: runningApp.processIdentifier) == .other {
            try await Task.sleep(for: .milliseconds(260))
            await bringAppToFront(runningApp)
            clickLikelyComposerArea(in: runningApp)
            try await Task.sleep(for: .milliseconds(90))
            try sendCommandVGlobal()
        }
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

    private func clickLikelyComposerArea(in app: NSRunningApplication) {
        guard let bounds = focusedWindowBounds(for: app.processIdentifier),
              let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        // Codex composer is near the lower section of the main content area.
        let clickPoint = CGPoint(
            x: bounds.midX,
            y: bounds.maxY - min(92.0, max(54.0, bounds.height * 0.12))
        )

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

    private enum FocusedElementKind {
        case textLike
        case other
        case unavailable
    }

    private func focusedElementKind(expectedPID: pid_t) -> FocusedElementKind {
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
             "AXWebArea",
             "AXComboBox":
            return .textLike
        default:
            return .other
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
}
