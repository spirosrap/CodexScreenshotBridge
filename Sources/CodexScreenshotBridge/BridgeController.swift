import AppKit
import Foundation

@MainActor
final class BridgeController: ObservableObject {
    private enum DefaultsKeys {
        static let bridgeEnabled = "bridgeEnabled"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let listenClipboardImages = "listenClipboardImages"
        static let screenshotDirectoryPath = "screenshotDirectoryPath"
        static let codexBundleIdentifier = "codexBundleIdentifier"
    }

    @Published var bridgeEnabled: Bool {
        didSet {
            defaults.set(bridgeEnabled, forKey: DefaultsKeys.bridgeEnabled)
            bridgeEnabledDidChange()
        }
    }

    @Published var autoPasteEnabled: Bool {
        didSet {
            defaults.set(autoPasteEnabled, forKey: DefaultsKeys.autoPasteEnabled)
        }
    }

    @Published var listenClipboardImages: Bool {
        didSet {
            defaults.set(listenClipboardImages, forKey: DefaultsKeys.listenClipboardImages)
            syncClipboardWatcherState()
        }
    }

    @Published var codexBundleIdentifier: String {
        didSet {
            defaults.set(codexBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                         forKey: DefaultsKeys.codexBundleIdentifier)
        }
    }

    @Published private(set) var screenshotDirectoryPath: String
    @Published private(set) var isWatching = false
    @Published private(set) var statusMessage = "Starting..."
    @Published private(set) var recentEvents: [String] = []

    private let defaults: UserDefaults
    private let watcher: ScreenshotWatcher
    private let clipboardWatcher: ClipboardWatcher
    private let clipboardService: ClipboardService
    private let autoPasteService: CodexAutoPasteService
    private var isClipboardWatcherRunning = false

    init() {
        defaults = .standard
        watcher = ScreenshotWatcher()
        clipboardWatcher = ClipboardWatcher()
        clipboardService = ClipboardService()
        autoPasteService = CodexAutoPasteService()

        screenshotDirectoryPath = defaults.string(forKey: DefaultsKeys.screenshotDirectoryPath)
            ?? Self.defaultScreenshotDirectoryPath()
        bridgeEnabled = defaults.object(forKey: DefaultsKeys.bridgeEnabled) as? Bool ?? true
        autoPasteEnabled = defaults.object(forKey: DefaultsKeys.autoPasteEnabled) as? Bool ?? true
        listenClipboardImages = defaults.object(forKey: DefaultsKeys.listenClipboardImages) as? Bool ?? true
        codexBundleIdentifier = defaults.string(forKey: DefaultsKeys.codexBundleIdentifier) ?? ""

        configureWatcherCallback()
        configureClipboardWatcherCallback()

        if bridgeEnabled {
            startWatching()
            syncClipboardWatcherState()
        } else {
            addLog("Bridge is disabled.")
        }
    }

    func chooseScreenshotFolder() {
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

    func restartWatching() {
        guard bridgeEnabled else {
            addLog("Bridge is disabled. Enable it first.")
            return
        }

        startWatching()
    }

    func requestAccessibilityAccess() {
        let granted = autoPasteService.ensureAccessibilityPermission(prompt: true)
        if granted {
            addLog("Accessibility permission is enabled.")
        } else {
            addLog("Allow Accessibility for this app to enable auto-paste.")
        }
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

        do {
            let changeCount = try clipboardService.copyImage(at: url)
            clipboardWatcher.ignore(changeCount: changeCount)
            addLog("Copied \(url.lastPathComponent) to clipboard.")
        } catch {
            addLog("Copy failed: \(error.localizedDescription)")
            return
        }

        autoPasteIntoCodexIfEnabled(source: "file screenshot")
    }

    private func handleClipboardImageEvent(_ event: ClipboardWatcher.ClipboardImageEvent) {
        guard bridgeEnabled, listenClipboardImages else {
            return
        }

        let types = event.types.joined(separator: ", ")
        addLog("Detected clipboard image (\(types)).")
        autoPasteIntoCodexIfEnabled(source: "clipboard screenshot")
    }

    private func autoPasteIntoCodexIfEnabled(source: String) {
        guard autoPasteEnabled else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await autoPasteService.activateCodexAndPaste(
                    codexBundleIdentifier: normalizedCodexBundleIdentifier
                )
                addLog("Sent Cmd+V to Codex (\(source)).")
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

    private static func defaultScreenshotDirectoryPath() -> String {
        if let domain = UserDefaults.standard.persistentDomain(forName: "com.apple.screencapture"),
           let location = domain["location"] as? String,
           !location.isEmpty {
            return NSString(string: location).expandingTildeInPath
        }

        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .path
    }

    private static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
