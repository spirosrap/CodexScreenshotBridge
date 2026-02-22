import AppKit
import ApplicationServices
import Foundation

@MainActor
final class CodexAutoPasteService {
    enum AutoPasteError: LocalizedError {
        case accessibilityPermissionMissing
        case codexNotFound
        case keyInjectionFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionMissing:
                return "Accessibility permission is required for auto-paste."
            case .codexNotFound:
                return "Could not find the Codex app. Launch it first or set bundle ID."
            case .keyInjectionFailed:
                return "Could not synthesize Cmd+V keyboard event."
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
        let runningApp = try await activateCodexApp(bundleIdentifier: codexBundleIdentifier)
        await bringAppToFront(runningApp)
        try await Task.sleep(for: .milliseconds(150))
        try sendCommandV(targetProcessID: runningApp.processIdentifier)
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

    private func sendCommandV(targetProcessID: pid_t) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw AutoPasteError.keyInjectionFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(targetProcessID)
        keyUp.postToPid(targetProcessID)
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

        for _ in 0..<30 {
            let anyDown = modifierKeys.contains {
                CGEventSource.keyState(.combinedSessionState, key: $0)
            }

            if !anyDown {
                return
            }

            try await Task.sleep(for: .milliseconds(40))
        }
    }
}
