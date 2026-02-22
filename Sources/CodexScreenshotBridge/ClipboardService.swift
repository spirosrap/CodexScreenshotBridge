import AppKit
import Foundation

@MainActor
final class ClipboardService {
    enum ClipboardError: LocalizedError {
        case imageLoadFailed(String)
        case pasteboardWriteFailed

        var errorDescription: String? {
            switch self {
            case let .imageLoadFailed(fileName):
                return "Could not load image data from \(fileName)."
            case .pasteboardWriteFailed:
                return "Could not write image to clipboard."
            }
        }
    }

    @discardableResult
    func copyImage(at url: URL) throws -> Int {
        guard let image = NSImage(contentsOf: url) else {
            throw ClipboardError.imageLoadFailed(url.lastPathComponent)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if pasteboard.writeObjects([image]) {
            return pasteboard.changeCount
        }

        if pasteboard.writeObjects([url as NSURL]) {
            return pasteboard.changeCount
        }

        throw ClipboardError.pasteboardWriteFailed
    }
}
