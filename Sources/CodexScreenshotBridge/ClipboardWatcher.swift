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

    func start() {
        stop()

        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.22, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        ignoredChangeCounts.removeAll()
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func ignore(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = changeCount

        if ignoredChangeCounts.remove(changeCount) != nil {
            return
        }

        guard NSImage(pasteboard: pasteboard) != nil else {
            return
        }

        let types = (pasteboard.types ?? []).map(\.rawValue)
        let event = ClipboardImageEvent(changeCount: changeCount, types: types)
        onClipboardImage?(event)
    }
}
