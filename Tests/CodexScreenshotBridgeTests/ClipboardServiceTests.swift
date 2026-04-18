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
    ]
}
