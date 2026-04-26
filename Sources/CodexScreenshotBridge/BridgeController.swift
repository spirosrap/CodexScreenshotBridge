import AppKit
import Foundation

@MainActor
package final class BridgeController: ObservableObject {
    package enum DefaultsKeys {
        package static let bridgeEnabled = "bridgeEnabled"
        package static let autoPasteEnabled = "autoPasteEnabled"
        package static let listenClipboardImages = "listenClipboardImages"
        package static let detectInitialPromptScreen = "detectInitialPromptScreen"
        package static let screenshotDirectoryPath = "screenshotDirectoryPath"
        package static let codexBundleIdentifier = "codexBundleIdentifier"
    }

    @Published package var bridgeEnabled: Bool {
        didSet {
            defaults.set(bridgeEnabled, forKey: DefaultsKeys.bridgeEnabled)
            bridgeEnabledDidChange()
        }
    }

    @Published package var autoPasteEnabled: Bool {
        didSet {
            defaults.set(autoPasteEnabled, forKey: DefaultsKeys.autoPasteEnabled)
        }
    }

    @Published package var listenClipboardImages: Bool {
        didSet {
            defaults.set(listenClipboardImages, forKey: DefaultsKeys.listenClipboardImages)
            syncClipboardWatcherState()
        }
    }

    @Published package var detectInitialPromptScreen: Bool {
        didSet {
            defaults.set(detectInitialPromptScreen, forKey: DefaultsKeys.detectInitialPromptScreen)
        }
    }

    @Published package var codexBundleIdentifier: String {
        didSet {
            defaults.set(codexBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                         forKey: DefaultsKeys.codexBundleIdentifier)
        }
    }

    @Published package private(set) var screenshotDirectoryPath: String
    @Published package private(set) var isWatching = false
    @Published package private(set) var statusMessage = "Starting..."
    @Published package private(set) var recentEvents: [String] = []
    @Published package private(set) var accessibilityPermissionGranted = false
    @Published package private(set) var screenRecordingPermissionGranted = false

    private let defaults: UserDefaults
    private let watcher: any ScreenshotWatching
    private let clipboardWatcher: any ClipboardWatching
    private let clipboardService: any ClipboardServicing
    private let screenshotCaptureService: any ScreenshotCaptureServicing
    private let autoPasteService: any CodexAutoPasteServing
    private let defaultScreenshotDirectoryProvider: (UserDefaults) -> String
    private var isClipboardWatcherRunning = false

    package init(
        defaults: UserDefaults,
        watcher: any ScreenshotWatching,
        clipboardWatcher: any ClipboardWatching,
        clipboardService: any ClipboardServicing,
        screenshotCaptureService: any ScreenshotCaptureServicing,
        autoPasteService: any CodexAutoPasteServing,
        defaultScreenshotDirectoryProvider: @escaping (UserDefaults) -> String
    ) {
        self.defaults = defaults
        self.watcher = watcher
        self.clipboardWatcher = clipboardWatcher
        self.clipboardService = clipboardService
        self.screenshotCaptureService = screenshotCaptureService
        self.autoPasteService = autoPasteService
        self.defaultScreenshotDirectoryProvider = defaultScreenshotDirectoryProvider

        screenshotDirectoryPath = defaults.string(forKey: DefaultsKeys.screenshotDirectoryPath)
            ?? defaultScreenshotDirectoryProvider(defaults)
        bridgeEnabled = defaults.object(forKey: DefaultsKeys.bridgeEnabled) as? Bool ?? true
        autoPasteEnabled = defaults.object(forKey: DefaultsKeys.autoPasteEnabled) as? Bool ?? true
        listenClipboardImages = defaults.object(forKey: DefaultsKeys.listenClipboardImages) as? Bool ?? true
        detectInitialPromptScreen = defaults.object(forKey: DefaultsKeys.detectInitialPromptScreen) as? Bool ?? false
        codexBundleIdentifier = defaults.string(forKey: DefaultsKeys.codexBundleIdentifier) ?? ""

        configureWatcherCallback()
        configureClipboardWatcherCallback()
        refreshPermissionStatus()

        if bridgeEnabled {
            startWatching()
            syncClipboardWatcherState()
        } else {
            addLog("Bridge is disabled.")
        }
    }

    package convenience init() {
        self.init(
            defaults: .standard,
            watcher: ScreenshotWatcher(),
            clipboardWatcher: ClipboardWatcher(),
            clipboardService: ClipboardService(),
            screenshotCaptureService: ScreenshotCaptureService(),
            autoPasteService: CodexAutoPasteService(),
            defaultScreenshotDirectoryProvider: { defaults in
                BridgeController.defaultScreenshotDirectoryPath(defaults: defaults)
            }
        )
    }

    package func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose Screenshot Folder"
        panel.directoryURL = URL(fileURLWithPath: screenshotDirectoryPath, isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        screenshotDirectoryPath = url.path
        defaults.set(url.path, forKey: DefaultsKeys.screenshotDirectoryPath)
        addLog("Screenshot folder updated.")

        if bridgeEnabled {
            startWatching()
        }
    }

    package func restartWatching() {
        guard bridgeEnabled else {
            addLog("Bridge is disabled. Enable it first.")
            return
        }

        startWatching()
    }

    package func captureAreaAndPaste() {
        guard bridgeEnabled else {
            addLog("Bridge is disabled. Enable it first.")
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            addLog("Select area for direct capture.")

            do {
                guard let url = try await screenshotCaptureService.captureInteractiveScreenshot() else {
                    addLog("Direct capture canceled.")
                    return
                }

                let changeCount = try clipboardService.copyFileURL(at: url)
                clipboardWatcher.ignore(changeCount: changeCount)
                addLog("Captured \(url.lastPathComponent) for direct paste.")
                autoPasteIntoCodexIfEnabled(source: "direct capture")
            } catch {
                addLog("Direct capture failed: \(error.localizedDescription)")
            }
        }
    }

    package func requestAccessibilityAccess() {
        let granted = autoPasteService.ensureAccessibilityPermission(prompt: true)
        refreshPermissionStatus()
        if granted {
            addLog("Accessibility permission is enabled.")
        } else {
            addLog("Allow Accessibility for this app to enable auto-paste.")
        }
    }

    package func requestScreenRecordingAccess() {
        let granted = autoPasteService.requestScreenRecordingPermission()
        refreshPermissionStatus()
        if granted {
            addLog("Screen Recording permission is enabled.")
        } else {
            addLog("Allow Screen Recording for reliable startup-screen detection.")
        }
    }

    package func refreshPermissionStatus() {
        accessibilityPermissionGranted = autoPasteService.hasAccessibilityPermission()
        screenRecordingPermissionGranted = autoPasteService.hasScreenRecordingPermission()
    }

    private func bridgeEnabledDidChange() {
        if bridgeEnabled {
            addLog("Bridge enabled.")
            startWatching()
            syncClipboardWatcherState()
        } else {
            watcher.stopWatching()
            clipboardWatcher.stop()
            isClipboardWatcherRunning = false
            isWatching = false
            addLog("Bridge disabled.")
        }
    }

    private func configureWatcherCallback() {
        watcher.onNewScreenshot = { [weak self] url in
            Task { @MainActor in
                self?.handleNewScreenshot(url)
            }
        }
    }

    private func configureClipboardWatcherCallback() {
        clipboardWatcher.onClipboardImage = { [weak self] event in
            Task { @MainActor in
                self?.handleClipboardImageEvent(event)
            }
        }
    }

    private func startWatching() {
        do {
            let directoryURL = URL(fileURLWithPath: screenshotDirectoryPath, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try watcher.startWatching(directoryURL: directoryURL)
            isWatching = true
            addLog("Watching \(directoryURL.path).")
        } catch {
            isWatching = false
            addLog("Failed to watch folder: \(error.localizedDescription)")
        }

        syncClipboardWatcherState()
    }

    private func handleNewScreenshot(_ url: URL) {
        guard bridgeEnabled else {
            return
        }

        let eventStartedAtUptimeNanoseconds = Self.currentUptimeNanoseconds()
        do {
            let changeCount = try clipboardService.copyFileURL(at: url)
            clipboardWatcher.ignore(changeCount: changeCount)
            addLog("Prepared \(url.lastPathComponent) for file paste.")
        } catch {
            addLog("Copy failed: \(error.localizedDescription)")
            return
        }

        autoPasteIntoCodexIfEnabled(
            source: "file screenshot",
            eventStartedAtUptimeNanoseconds: eventStartedAtUptimeNanoseconds
        )
    }

    private func handleClipboardImageEvent(_ event: ClipboardWatchEvent) {
        guard bridgeEnabled, listenClipboardImages else {
            return
        }

        let types = event.types.joined(separator: ", ")
        addLog(
            "Detected clipboard image (\(types)). Image-ready \(Self.elapsedMilliseconds(since: event.detectedAtUptimeNanoseconds))ms."
        )
        autoPasteIntoCodexIfEnabled(
            source: "clipboard screenshot",
            eventStartedAtUptimeNanoseconds: event.detectedAtUptimeNanoseconds
        )
    }

    private func autoPasteIntoCodexIfEnabled(
        source: String,
        eventStartedAtUptimeNanoseconds: UInt64? = nil
    ) {
        guard autoPasteEnabled else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let report = try await autoPasteService.activateCodexAndPaste(
                    codexBundleIdentifier: normalizedCodexBundleIdentifier,
                    detectInitialPromptScreen: detectInitialPromptScreen
                )
                let totalSuffix = eventStartedAtUptimeNanoseconds.map {
                    " Event-to-paste \(Self.elapsedMilliseconds(since: $0))ms."
                } ?? ""
                addLog(
                    "Sent Cmd+V to Codex (\(source)) in \(report.elapsedMilliseconds)ms: \(report.summary).\(totalSuffix)"
                )
            } catch {
                addLog("Auto-paste failed: \(error.localizedDescription)")
            }
        }
    }

    private func syncClipboardWatcherState() {
        let shouldRun = bridgeEnabled && listenClipboardImages

        if shouldRun, !isClipboardWatcherRunning {
            clipboardWatcher.start()
            isClipboardWatcherRunning = true
            addLog("Watching clipboard for screenshot copies.")
            return
        }

        if !shouldRun, isClipboardWatcherRunning {
            clipboardWatcher.stop()
            isClipboardWatcherRunning = false
            if bridgeEnabled {
                addLog("Clipboard watcher paused.")
            }
        }
    }

    private var normalizedCodexBundleIdentifier: String? {
        let value = codexBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func addLog(_ message: String) {
        statusMessage = message
        let timestamp = Self.logFormatter.string(from: Date())
        recentEvents.insert("[\(timestamp)] \(message)", at: 0)

        if recentEvents.count > 14 {
            recentEvents.removeLast(recentEvents.count - 14)
        }
    }

    package nonisolated static func defaultScreenshotDirectoryPath(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> String {
        if let domain = defaults.persistentDomain(forName: "com.apple.screencapture"),
           let location = domain["location"] as? String,
           !location.isEmpty {
            return NSString(string: location).expandingTildeInPath
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .path
    }

    private static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static func currentUptimeNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func elapsedMilliseconds(since startUptimeNanoseconds: UInt64) -> Int {
        let elapsedNanoseconds = currentUptimeNanoseconds().saturatingSubtracting(startUptimeNanoseconds)
        return Int((Double(elapsedNanoseconds) / 1_000_000).rounded())
    }
}

private extension UInt64 {
    func saturatingSubtracting(_ other: UInt64) -> UInt64 {
        self >= other ? self - other : 0
    }
}
