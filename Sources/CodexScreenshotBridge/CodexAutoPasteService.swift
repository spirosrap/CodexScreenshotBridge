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

        let runningApp = try await activateCodexApp(bundleIdentifier: codexBundleIdentifier)
        runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        try await Task.sleep(for: .milliseconds(260))

        try sendCommandV()
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
        let runningApps = NSWorkspace.shared.runningApplications

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return runningApps.first { $0.bundleIdentifier == bundleIdentifier }
        }

        if let exactNameMatch = runningApps.first(where: {
            $0.localizedName?.caseInsensitiveCompare("Codex") == .orderedSame
        }) {
            return exactNameMatch
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
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("Codex.app", isDirectory: true),
        ]

        return candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
    }

    private func sendCommandV() throws {
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
}
