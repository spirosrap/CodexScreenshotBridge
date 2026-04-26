import AppKit
import Foundation

package protocol PasteboardWriting {
    var changeCount: Int { get }
    func clearContents()
    func write(image: NSImage) -> Bool
    func write(fileURL: URL) -> Bool
    func data(forType rawType: String) -> Data?
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

    func data(forType rawType: String) -> Data? {
        NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(rawType))
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
        case temporaryFileWriteFailed(String)

        package var errorDescription: String? {
            switch self {
            case let .imageLoadFailed(fileName):
                return "Could not load image data from \(fileName)."
            case .pasteboardWriteFailed:
                return "Could not write image to clipboard."
            case let .temporaryFileWriteFailed(message):
                return "Could not prepare clipboard image file: \(message)"
            }
        }
    }

    private let pasteboard: PasteboardWriting
    private let imageLoader: ImageLoading
    private let temporaryDirectoryProvider: () throws -> URL

    package init(
        pasteboard: PasteboardWriting = SystemPasteboardWriter(),
        imageLoader: ImageLoading = NSImageLoader(),
        temporaryDirectoryProvider: @escaping () throws -> URL = {
            let baseURL = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory

            return baseURL
                .appendingPathComponent("CodexScreenshotBridge", isDirectory: true)
                .appendingPathComponent("ClipboardScreenshots", isDirectory: true)
        }
    ) {
        self.pasteboard = pasteboard
        self.imageLoader = imageLoader
        self.temporaryDirectoryProvider = temporaryDirectoryProvider
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

    @discardableResult
    package func copyFileURL(at url: URL) throws -> Int {
        pasteboard.clearContents()

        guard pasteboard.write(fileURL: url) else {
            throw ClipboardError.pasteboardWriteFailed
        }

        return pasteboard.changeCount
    }

    @discardableResult
    package func replaceClipboardImageWithTemporaryFile(types: [String]) throws -> Int? {
        guard let imageData = clipboardImageData(preferredTypes: types) else {
            return nil
        }

        let directoryURL: URL
        do {
            directoryURL = try temporaryDirectoryProvider()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw ClipboardError.temporaryFileWriteFailed(error.localizedDescription)
        }

        let fileURL = directoryURL.appendingPathComponent(
            "Clipboard-Screenshot-\(Self.fileNameTimestamp()).\(imageData.fileExtension)"
        )

        do {
            try imageData.data.write(to: fileURL, options: .atomic)
        } catch {
            throw ClipboardError.temporaryFileWriteFailed(error.localizedDescription)
        }

        pasteboard.clearContents()

        guard pasteboard.write(fileURL: fileURL) else {
            throw ClipboardError.pasteboardWriteFailed
        }

        return pasteboard.changeCount
    }

    private func clipboardImageData(preferredTypes: [String]) -> ClipboardImageData? {
        let candidates = Self.imageDataTypeCandidates(preferredTypes: preferredTypes)

        for candidate in candidates {
            guard let data = pasteboard.data(forType: candidate.rawType),
                  !data.isEmpty else {
                continue
            }

            return ClipboardImageData(
                data: data,
                fileExtension: candidate.fileExtension
            )
        }

        return nil
    }

    private static func imageDataTypeCandidates(preferredTypes: [String]) -> [ImageDataTypeCandidate] {
        let allCandidates = [
            ImageDataTypeCandidate(rawType: "public.png", fileExtension: "png"),
            ImageDataTypeCandidate(rawType: "Apple PNG pasteboard type", fileExtension: "png"),
            ImageDataTypeCandidate(rawType: "public.tiff", fileExtension: "tiff"),
            ImageDataTypeCandidate(rawType: "NeXT TIFF v4.0 pasteboard type", fileExtension: "tiff"),
            ImageDataTypeCandidate(rawType: "public.jpeg", fileExtension: "jpg"),
            ImageDataTypeCandidate(rawType: "public.heic", fileExtension: "heic"),
        ]

        let preferred = allCandidates.filter { preferredTypes.contains($0.rawType) }
        let remaining = allCandidates.filter { !preferredTypes.contains($0.rawType) }
        return preferred + remaining
    }

    private static func fileNameTimestamp() -> String {
        String(Int(Date().timeIntervalSince1970 * 1_000))
    }

    private struct ClipboardImageData {
        let data: Data
        let fileExtension: String
    }

    private struct ImageDataTypeCandidate {
        let rawType: String
        let fileExtension: String
    }
}
