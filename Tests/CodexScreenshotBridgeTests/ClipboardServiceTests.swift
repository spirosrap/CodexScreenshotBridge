import Foundation
import CodexScreenshotBridgeCore

enum ClipboardServiceTests {
    static let all: [CodexTestCase] = [
        CodexTestCase(name: "ClipboardService writes image to pasteboard when available") {
            try await MainActor.run {
                let pasteboard = FakePasteboardWriter(changeCount: 17)
                let service = ClipboardService(
                    pasteboard: pasteboard,
                    imageLoader: FakeImageLoader(image: makeTestImage())
                )
                let url = URL(fileURLWithPath: "/tmp/example.png")

                let changeCount = try service.copyImage(at: url)

                try expect(changeCount == 17, "Image write should return pasteboard change count")
                try expect(pasteboard.clearContentsCallCount == 1, "Clipboard should be cleared before writing")
                try expect(pasteboard.wroteImageCount == 1, "Clipboard should attempt image write first")
                try expect(pasteboard.wroteFileURLCount == 0, "Clipboard should not fall back to file URL when image write succeeds")
            }
        },
        CodexTestCase(name: "ClipboardService falls back to file URL when image write fails") {
            try await MainActor.run {
                let pasteboard = FakePasteboardWriter(changeCount: 23)
                pasteboard.imageWriteResult = false
                pasteboard.fileURLWriteResult = true

                let service = ClipboardService(
                    pasteboard: pasteboard,
                    imageLoader: FakeImageLoader(image: makeTestImage())
                )
                let url = URL(fileURLWithPath: "/tmp/example.png")

                let changeCount = try service.copyImage(at: url)

                try expect(changeCount == 23, "Fallback write should return pasteboard change count")
                try expect(pasteboard.wroteImageCount == 1, "Clipboard should attempt image write first")
                try expect(pasteboard.wroteFileURLCount == 1, "Clipboard should fall back to file URL")
            }
        },
        CodexTestCase(name: "ClipboardService throws imageLoadFailed when image cannot load") {
            try await MainActor.run {
                let service = ClipboardService(
                    pasteboard: FakePasteboardWriter(),
                    imageLoader: FakeImageLoader(image: nil)
                )
                let url = URL(fileURLWithPath: "/tmp/missing.png")

                do {
                    _ = try service.copyImage(at: url)
                    try fail("Expected imageLoadFailed error")
                } catch {
                    guard case ClipboardService.ClipboardError.imageLoadFailed("missing.png") = error else {
                        try fail("Unexpected error: \(error)")
                    }
                }
            }
        },
        CodexTestCase(name: "ClipboardService throws pasteboardWriteFailed when all writes fail") {
            try await MainActor.run {
                let pasteboard = FakePasteboardWriter()
                pasteboard.imageWriteResult = false
                pasteboard.fileURLWriteResult = false

                let service = ClipboardService(
                    pasteboard: pasteboard,
                    imageLoader: FakeImageLoader(image: makeTestImage())
                )
                let url = URL(fileURLWithPath: "/tmp/example.png")

                do {
                    _ = try service.copyImage(at: url)
                    try fail("Expected pasteboardWriteFailed error")
                } catch {
                    guard case ClipboardService.ClipboardError.pasteboardWriteFailed = error else {
                        try fail("Unexpected error: \(error)")
                    }
                }
            }
        },
        CodexTestCase(name: "ClipboardService replaces clipboard PNG with temporary file URL") {
            try await MainActor.run {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                let pasteboard = FakePasteboardWriter(changeCount: 31)
                pasteboard.dataByType["public.png"] = Data([0x89, 0x50, 0x4E, 0x47])
                pasteboard.fileURLWriteResult = true

                let service = ClipboardService(
                    pasteboard: pasteboard,
                    imageLoader: FakeImageLoader(image: nil),
                    temporaryDirectoryProvider: { directory }
                )

                let changeCount = try service.replaceClipboardImageWithTemporaryFile(
                    types: ["public.png", "public.tiff"]
                )

                try expect(changeCount == 31, "Replacement should return pasteboard change count")
                try expect(pasteboard.clearContentsCallCount == 1, "Clipboard should be cleared before file URL write")
                try expect(pasteboard.wroteFileURLCount == 1, "Clipboard should receive generated file URL")
                guard let writtenURL = pasteboard.writtenFileURLs.first else {
                    try fail("Expected generated file URL")
                }
                try expect(writtenURL.pathExtension == "png", "PNG data should be exported as a PNG file")
                try expect(FileManager.default.fileExists(atPath: writtenURL.path), "Generated clipboard image file should exist")
                try? FileManager.default.removeItem(at: directory)
            }
        },
        CodexTestCase(name: "ClipboardService skips replacement when no raw image data is available") {
            try await MainActor.run {
                let pasteboard = FakePasteboardWriter(changeCount: 42)
                let service = ClipboardService(
                    pasteboard: pasteboard,
                    imageLoader: FakeImageLoader(image: nil)
                )

                let changeCount = try service.replaceClipboardImageWithTemporaryFile(
                    types: ["public.png"]
                )

                try expect(changeCount == nil, "Missing raw image data should leave pasteboard unchanged")
                try expect(pasteboard.clearContentsCallCount == 0, "Clipboard should not be cleared when no replacement is possible")
                try expect(pasteboard.wroteFileURLCount == 0, "Clipboard should not receive a file URL")
            }
        },
    ]
}
