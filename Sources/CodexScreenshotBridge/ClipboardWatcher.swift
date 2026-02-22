import AppKit
import Foundation

final class ClipboardWatcher: @unchecked Sendable {
    struct ClipboardImageEvent {
        let changeCount: Int
        let types: [String]
    }

    var onClipboardImage: ((ClipboardImageEvent) -> Void)?

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var ignoredChangeCounts: Set<Int> = []
    private var pendingChangeCount: Int?
    private var pendingRetryCount = 0
    private let maxImageResolutionRetries = 14

    func start() {
        stop()

        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        ignoredChangeCounts.removeAll()
        pendingChangeCount = nil
        pendingRetryCount = 0
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func ignore(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount

        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            pendingChangeCount = currentChangeCount
            pendingRetryCount = 0
        }

        guard let changeCount = pendingChangeCount else {
            return
        }

        if ignoredChangeCounts.remove(changeCount) != nil {
            pendingChangeCount = nil
            pendingRetryCount = 0
            return
        }

        guard NSImage(pasteboard: pasteboard) != nil else {
            if pendingRetryCount < maxImageResolutionRetries {
                pendingRetryCount += 1
            } else {
                pendingChangeCount = nil
                pendingRetryCount = 0
            }
            return
        }

        let types = (pasteboard.types ?? []).map(\.rawValue)
        let event = ClipboardImageEvent(changeCount: changeCount, types: types)
        onClipboardImage?(event)
        pendingChangeCount = nil
        pendingRetryCount = 0
    }
}
