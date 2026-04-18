import AppKit
import Foundation

package protocol PasteboardWriting {
    var changeCount: Int { get }
    func clearContents()
    func write(image: NSImage) -> Bool
    func write(fileURL: URL) -> Bool
}

package protocol ImageLoading {
    func loadImage(at url: URL) -> NSImage?
}

struct SystemPasteboardWriter: PasteboardWriting {
    var changeCount: Int { NSPasteboard.general.changeCount }

    func clearContents() {
        NSPasteboard.general.clearContents()
    }

    func write(image: NSImage) -> Bool {
        NSPasteboard.general.writeObjects([image])
    }

    func write(fileURL: URL) -> Bool {
        NSPasteboard.general.writeObjects([fileURL as NSURL])
    }
}

struct NSImageLoader: ImageLoading {
    func loadImage(at url: URL) -> NSImage? {
        NSImage(contentsOf: url)
    }
}

@MainActor
package final class ClipboardService: ClipboardServicing {
    package enum ClipboardError: LocalizedError {
        case imageLoadFailed(String)
        case pasteboardWriteFailed

        package var errorDescription: String? {
            switch self {
            case let .imageLoadFailed(fileName):
                return "Could not load image data from \(fileName)."
            case .pasteboardWriteFailed:
                return "Could not write image to clipboard."
            }
        }
    }

    private let pasteboard: PasteboardWriting
    private let imageLoader: ImageLoading

    package init(
        pasteboard: PasteboardWriting = SystemPasteboardWriter(),
        imageLoader: ImageLoading = NSImageLoader()
    ) {
        self.pasteboard = pasteboard
        self.imageLoader = imageLoader
    }

    @discardableResult
    package func copyImage(at url: URL) throws -> Int {
        guard let image = imageLoader.loadImage(at: url) else {
            throw ClipboardError.imageLoadFailed(url.lastPathComponent)
        }

        pasteboard.clearContents()

        if pasteboard.write(image: image) {
            return pasteboard.changeCount
        }

        if pasteboard.write(fileURL: url) {
            return pasteboard.changeCount
        }

        throw ClipboardError.pasteboardWriteFailed
    }
}
