import Foundation
import CodexScreenshotBridgeCore

enum BridgeControllerTests {
    static let all: [CodexTestCase] = [
        CodexTestCase(name: "BridgeController initializer starts watcher and refreshes permissions") {
            try await MainActor.run {
                let defaults = makeTestDefaults()
                let watcher = FakeScreenshotWatcher()
                let clipboardWatcher = FakeClipboardWatcher()
                let clipboardService = FakeClipboardService()
                let autoPasteService = FakeAutoPasteService()
                autoPasteService.accessibilityPermissionGranted = true
                autoPasteService.screenRecordingPermissionGranted = true

                let controller = BridgeController(
                    defaults: defaults,
                    watcher: watcher,
                    clipboardWatcher: clipboardWatcher,
                    clipboardService: clipboardService,
                    screenshotCaptureService: FakeScreenshotCaptureService(),
                    screenshotSystemSettingsService: FakeScreenshotSystemSettingsService(),
                    autoPasteService: autoPasteService,
                    defaultScreenshotDirectoryProvider: { _ in "/tmp/screenshots" }
                )

                try expect(watcher.startedDirectories.map(\.path) == ["/tmp/screenshots"], "Initializer should start screenshot watcher")
                try expect(clipboardWatcher.startCallCount == 1, "Initializer should start clipboard watcher")
                try expect(controller.isWatching, "Controller should report active watcher")
                try expect(controller.accessibilityPermissionGranted, "Accessibility permission should refresh from auto-paste service")
                try expect(controller.screenRecordingPermissionGranted, "Screen Recording permission should refresh from auto-paste service")
                try expect(controller.screenshotFloatingThumbnailState == .enabled, "Screenshot system settings should refresh on init")
                try expect(controller.recentEvents.contains(where: { $0.contains("Watching /tmp/screenshots.") }), "Screenshot watch log should be recorded")
                try expect(controller.statusMessage == "Watching clipboard for screenshot copies.", "Clipboard watcher log should become the current status")
            }
        },
        CodexTestCase(name: "BridgeController honors disabled bridge setting on init") {
            try await MainActor.run {
                let defaults = makeTestDefaults()
                defaults.set(false, forKey: BridgeController.DefaultsKeys.bridgeEnabled)

                let watcher = FakeScreenshotWatcher()
                let clipboardWatcher = FakeClipboardWatcher()
                let controller = BridgeController(
                    defaults: defaults,
                    watcher: watcher,
                    clipboardWatcher: clipboardWatcher,
                    clipboardService: FakeClipboardService(),
                    screenshotCaptureService: FakeScreenshotCaptureService(),
                    screenshotSystemSettingsService: FakeScreenshotSystemSettingsService(),
                    autoPasteService: FakeAutoPasteService(),
                    defaultScreenshotDirectoryProvider: { _ in "/tmp/screenshots" }
                )

                try expect(watcher.startedDirectories.isEmpty, "Disabled bridge should not start screenshot watcher")
                try expect(clipboardWatcher.startCallCount == 0, "Disabled bridge should not start clipboard watcher")
                try expect(controller.statusMessage == "Bridge is disabled.", "Disabled bridge should log disabled state")
            }
        },
        CodexTestCase(name: "BridgeController permission requests refresh state and log outcome") {
            try await MainActor.run {
                let parts = makeController()
                let controller = parts.controller
                let autoPasteService = parts.autoPasteService

                autoPasteService.accessibilityPermissionGranted = false
                controller.requestAccessibilityAccess()
                try expect(!controller.accessibilityPermissionGranted, "Accessibility refresh should reflect service state")
                try expect(controller.statusMessage.contains("Allow Accessibility"), "Accessibility failure should log instructions")

                autoPasteService.requestScreenRecordingResult = true
                controller.requestScreenRecordingAccess()
                try expect(controller.screenRecordingPermissionGranted, "Screen Recording refresh should reflect granted state")
                try expect(controller.statusMessage == "Screen Recording permission is enabled.", "Screen Recording success should log enabled message")
            }
        },
        CodexTestCase(name: "BridgeController disables screenshot floating thumbnail and refreshes state") {
            try await MainActor.run {
                let parts = makeController()

                parts.controller.disableScreenshotFloatingThumbnail()

                try expect(parts.screenshotSystemSettingsService.disableCallCount == 1, "Disable action should update screenshot system settings")
                try expect(parts.controller.screenshotFloatingThumbnailState == .disabled, "Disable action should refresh screenshot system settings")
                try expect(parts.controller.statusMessage == "Disabled macOS screenshot floating thumbnail.", "Disable action should log success")
            }
        },
        CodexTestCase(name: "BridgeController logs screenshot floating thumbnail disable failure") {
            try await MainActor.run {
                let parts = makeController()
                parts.screenshotSystemSettingsService.disableError = FakeLocalizedError(message: "settings failed")

                parts.controller.disableScreenshotFloatingThumbnail()

                try expect(parts.controller.screenshotFloatingThumbnailState == .enabled, "Failure should leave refreshed state visible")
                try expect(parts.controller.statusMessage.contains("settings failed"), "Failure should log settings error")
            }
        },
        CodexTestCase(name: "BridgeController handles screenshot copy and auto-paste flow") {
            let parts = await MainActor.run { makeController() }
            await MainActor.run {
                parts.controller.codexBundleIdentifier = "  com.example.codex  "
                parts.clipboardService.nextChangeCount = 44
                parts.watcher.emit(URL(fileURLWithPath: "/tmp/Screenshot 1.png"))
            }
            let didAutoPaste = await waitUntil {
                parts.autoPasteService.activateCalls == ["com.example.codex"]
            }

            try await MainActor.run {
                try expect(parts.clipboardService.copiedURLs == [URL(fileURLWithPath: "/tmp/Screenshot 1.png")], "Screenshot file URL should be copied to clipboard service")
                try expect(parts.clipboardWatcher.ignoredChangeCounts == [44], "Controller should ignore its own pasteboard write")
                try expect(didAutoPaste, "Auto-paste should receive trimmed bundle identifier")
                try expect(parts.autoPasteService.detectInitialPromptScreenCalls == [false], "Startup-screen detector should be off by default for normal conversation speed")
                try expect(parts.controller.recentEvents.contains(where: { $0.contains("Prepared Screenshot 1.png for file paste.") }), "File paste log should be recorded")
                try expect(parts.controller.recentEvents.contains(where: {
                    $0.contains("Sent Cmd+V to Codex (file screenshot) in 1ms: fake 1ms.")
                }), "Auto-paste log should be recorded")
            }
        },
        CodexTestCase(name: "BridgeController can turn on startup-screen detection") {
            let parts = await MainActor.run {
                let defaults = makeTestDefaults()
                defaults.set(true, forKey: BridgeController.DefaultsKeys.detectInitialPromptScreen)
                return makeController(defaults: defaults)
            }

            await MainActor.run {
                parts.watcher.emit(URL(fileURLWithPath: "/tmp/Screenshot startup.png"))
            }
            let didPassStartupDetectionFlag = await waitUntil {
                parts.autoPasteService.detectInitialPromptScreenCalls == [true]
            }

            try await MainActor.run {
                try expect(didPassStartupDetectionFlag, "Persisted startup-screen detector setting should be passed to auto-paste")
            }
        },
        CodexTestCase(name: "BridgeController logs screenshot copy failure without auto-paste") {
            let parts = await MainActor.run { makeController() }
            await MainActor.run {
                parts.clipboardService.copyError = FakeLocalizedError(message: "copy failed")
                parts.watcher.emit(URL(fileURLWithPath: "/tmp/Screenshot 2.png"))
            }
            await drainAsyncTasks()

            try await MainActor.run {
                try expect(parts.controller.statusMessage.contains("Copy failed: copy failed"), "Copy failure should be logged")
                try expect(parts.autoPasteService.activateCalls.isEmpty, "Copy failure should skip auto-paste")
            }
        },
        CodexTestCase(name: "BridgeController clipboard events paste only while listening is enabled") {
            let parts = await MainActor.run { makeController() }
            await MainActor.run {
                parts.clipboardWatcher.emit(changeCount: 9, types: ["public.png", "public.tiff"])
            }
            let didPasteClipboardImage = await waitUntil {
                parts.autoPasteService.activateCalls.count == 1
            }

            try await MainActor.run {
                try expect(didPasteClipboardImage, "Clipboard image should trigger one paste")
                try expect(parts.clipboardService.clipboardReplacementTypes.isEmpty, "Clipboard image should remain on the pasteboard for raw paste")
                try expect(parts.controller.recentEvents.contains(where: {
                    $0.contains("Detected clipboard image (public.png, public.tiff).")
                }), "Clipboard detection should be logged")

                parts.controller.listenClipboardImages = false
            }
            await drainAsyncTasks()

            let previousCount = await MainActor.run { parts.autoPasteService.activateCalls.count }
            await MainActor.run {
                parts.clipboardWatcher.emit(changeCount: 10, types: ["public.png"])
            }
            await drainAsyncTasks()

            try await MainActor.run {
                try expect(previousCount == parts.autoPasteService.activateCalls.count, "Disabled clipboard listening should block further pastes")
                try expect(parts.clipboardWatcher.stopCallCount == 1, "Disabling clipboard listening should stop watcher")
                try expect(parts.controller.recentEvents.contains(where: { $0.contains("Clipboard watcher paused.") }), "Pause log should be recorded")
            }
        },
        CodexTestCase(name: "BridgeController preserves clipboard image without pasteboard rewrite") {
            let parts = await MainActor.run { makeController() }
            await MainActor.run {
                parts.clipboardService.clipboardReplacementChangeCount = 99
                parts.clipboardWatcher.emit(changeCount: 12, types: ["public.png"])
            }
            let didAutoPaste = await waitUntil {
                parts.autoPasteService.activateCalls.count == 1
            }

            try await MainActor.run {
                try expect(didAutoPaste, "Prepared clipboard screenshot should still trigger auto-paste")
                try expect(parts.clipboardService.clipboardReplacementTypes.isEmpty, "Clipboard paste should not rewrite image data into a file URL")
                try expect(parts.clipboardWatcher.ignoredChangeCounts.isEmpty, "No pasteboard rewrite should be ignored for clipboard image paste")
            }
        },
        CodexTestCase(name: "BridgeController bridge toggle stops and restarts watchers") {
            let parts = await MainActor.run { makeController() }
            await MainActor.run {
                parts.controller.bridgeEnabled = false
            }
            await drainAsyncTasks()

            try await MainActor.run {
                try expect(parts.watcher.stopCallCount == 1, "Disabling bridge should stop screenshot watcher")
                try expect(parts.clipboardWatcher.stopCallCount == 1, "Disabling bridge should stop clipboard watcher")
                try expect(!parts.controller.isWatching, "Controller should report stopped watcher")
                try expect(parts.controller.statusMessage == "Bridge disabled.", "Disable action should log state")
                parts.controller.bridgeEnabled = true
            }
            await drainAsyncTasks()

            try await MainActor.run {
                try expect(parts.watcher.startedDirectories.count == 2, "Re-enabling bridge should restart screenshot watcher")
                try expect(parts.clipboardWatcher.startCallCount == 2, "Re-enabling bridge should restart clipboard watcher")
                try expect(parts.controller.isWatching, "Controller should report active watcher again")
                try expect(parts.controller.recentEvents.contains(where: { $0.contains("Bridge enabled.") }), "Enable log should be recorded")
            }
        },
        CodexTestCase(name: "BridgeController restartWatching warns when bridge is disabled") {
            try await MainActor.run {
                let defaults = makeTestDefaults()
                defaults.set(false, forKey: BridgeController.DefaultsKeys.bridgeEnabled)

                let watcher = FakeScreenshotWatcher()
                let clipboardWatcher = FakeClipboardWatcher()
                let controller = BridgeController(
                    defaults: defaults,
                    watcher: watcher,
                    clipboardWatcher: clipboardWatcher,
                    clipboardService: FakeClipboardService(),
                    screenshotCaptureService: FakeScreenshotCaptureService(),
                    screenshotSystemSettingsService: FakeScreenshotSystemSettingsService(),
                    autoPasteService: FakeAutoPasteService(),
                    defaultScreenshotDirectoryProvider: { _ in "/tmp/screenshots" }
                )

                controller.restartWatching()

                try expect(controller.statusMessage == "Bridge is disabled. Enable it first.", "Restart should prompt user to enable bridge first")
                try expect(watcher.startedDirectories.isEmpty, "Restart should not touch watcher while disabled")
            }
        },
        CodexTestCase(name: "BridgeController caps recent events at fourteen entries") {
            try await MainActor.run {
                let parts = makeController()
                parts.controller.autoPasteEnabled = false

                for _ in 0..<20 {
                    parts.controller.requestAccessibilityAccess()
                }

                try expect(parts.controller.recentEvents.count == 14, "Recent events should retain only the newest fourteen entries")
            }
        },
        CodexTestCase(name: "BridgeController default screenshot directory respects capture location defaults") {
            let defaults = makeTestDefaults()
            defaults.setPersistentDomain(
                ["location": "~/Screenshots"],
                forName: "com.apple.screencapture"
            )

            let path = BridgeController.defaultScreenshotDirectoryPath(defaults: defaults)
            try expect(path == NSString(string: "~/Screenshots").expandingTildeInPath, "Configured screenshot location should be expanded from defaults")
        },
        CodexTestCase(name: "BridgeController direct capture writes file URL and auto-pastes") {
            let parts = await MainActor.run { makeController() }
            await MainActor.run {
                parts.screenshotCaptureService.capturedURL = URL(fileURLWithPath: "/tmp/Bridge-Capture.png")
                parts.clipboardService.nextChangeCount = 77
                parts.controller.captureAreaAndPaste()
            }
            let didAutoPaste = await waitUntil {
                parts.autoPasteService.activateCalls.count == 1
            }

            try await MainActor.run {
                try expect(didAutoPaste, "Direct capture should trigger auto-paste")
                try expect(parts.screenshotCaptureService.captureCallCount == 1, "Direct capture service should be invoked")
                try expect(parts.clipboardService.copiedURLs == [URL(fileURLWithPath: "/tmp/Bridge-Capture.png")], "Direct capture file URL should be copied")
                try expect(parts.clipboardWatcher.ignoredChangeCounts == [77], "Direct capture pasteboard write should be ignored")
                try expect(parts.controller.recentEvents.contains(where: {
                    $0.contains("Captured Bridge-Capture.png for direct paste.")
                }), "Direct capture should be logged")
            }
        },
        CodexTestCase(name: "BridgeController direct capture cancellation does not paste") {
            let parts = await MainActor.run { makeController() }
            await MainActor.run {
                parts.screenshotCaptureService.capturedURL = nil
                parts.controller.captureAreaAndPaste()
            }
            await drainAsyncTasks()

            try await MainActor.run {
                try expect(parts.screenshotCaptureService.captureCallCount == 1, "Direct capture service should be invoked")
                try expect(parts.autoPasteService.activateCalls.isEmpty, "Canceled direct capture should not paste")
                try expect(parts.controller.recentEvents.contains(where: {
                    $0.contains("Direct capture canceled.")
                }), "Cancellation should be logged")
            }
        },
    ]

    @MainActor
    private static func makeController(
        defaults: UserDefaults = makeTestDefaults()
    ) -> (
        controller: BridgeController,
        watcher: FakeScreenshotWatcher,
        clipboardWatcher: FakeClipboardWatcher,
        clipboardService: FakeClipboardService,
        screenshotCaptureService: FakeScreenshotCaptureService,
        screenshotSystemSettingsService: FakeScreenshotSystemSettingsService,
        autoPasteService: FakeAutoPasteService
    ) {
        let watcher = FakeScreenshotWatcher()
        let clipboardWatcher = FakeClipboardWatcher()
        let clipboardService = FakeClipboardService()
        let screenshotCaptureService = FakeScreenshotCaptureService()
        let screenshotSystemSettingsService = FakeScreenshotSystemSettingsService()
        let autoPasteService = FakeAutoPasteService()
        autoPasteService.accessibilityPermissionGranted = true
        autoPasteService.screenRecordingPermissionGranted = false

        let controller = BridgeController(
            defaults: defaults,
            watcher: watcher,
            clipboardWatcher: clipboardWatcher,
            clipboardService: clipboardService,
            screenshotCaptureService: screenshotCaptureService,
            screenshotSystemSettingsService: screenshotSystemSettingsService,
            autoPasteService: autoPasteService,
            defaultScreenshotDirectoryProvider: { _ in "/tmp/screenshots" }
        )

        return (controller, watcher, clipboardWatcher, clipboardService, screenshotCaptureService, screenshotSystemSettingsService, autoPasteService)
    }
}
