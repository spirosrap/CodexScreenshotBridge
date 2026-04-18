import AppKit
import Foundation

final class ClipboardWatcher: @unchecked Sendable, ClipboardWatching {
    package typealias ClipboardImageEvent = ClipboardWatchEvent

    var onClipboardImage: ((ClipboardImageEvent) -> Void)?

    private var timer: Timer?
    private var state = ClipboardWatcherState(initialChangeCount: NSPasteboard.general.changeCount)

    func start() {
        stop()

        state = ClipboardWatcherState(initialChangeCount: NSPasteboard.general.changeCount)
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        state.reset(currentChangeCount: NSPasteboard.general.changeCount)
    }

    func ignore(changeCount: Int) {
        state.ignore(changeCount: changeCount)
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let event = state.processPoll(
            currentChangeCount: pasteboard.changeCount,
            hasImage: NSImage(pasteboard: pasteboard) != nil,
            types: (pasteboard.types ?? []).map(\.rawValue)
        )

        if let event {
            onClipboardImage?(event)
        }
    }
}
