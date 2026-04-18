import Foundation
import CodexScreenshotBridgeCore

enum ScreenshotDirectoryScannerTests {
    static let all: [CodexTestCase] = [
        CodexTestCase(name: "ScreenshotFileClassifier matches expected names and extensions") {
            try expect(ScreenshotFileClassifier.isLikelyScreenshotName("Screenshot 2026-04-18"), "Screenshot name should match")
            try expect(ScreenshotFileClassifier.isLikelyScreenshotName("Screen Shot 2026-04-18 at 10.00.00"), "Screen Shot name should match")
            try expect(!ScreenshotFileClassifier.isLikelyScreenshotName("holiday-photo"), "Unrelated name should not match")
            try expect(ScreenshotFileClassifier.isSupportedImageExtension("PNG"), "PNG extension should match case-insensitively")
            try expect(ScreenshotFileClassifier.isSupportedImageExtension("pdf"), "PDF should be supported")
            try expect(!ScreenshotFileClassifier.isSupportedImageExtension("gif"), "GIF should not be supported")
        },
        CodexTestCase(name: "ScreenshotDirectoryScanner filters non-screenshot files") {
            let directory = try makeTemporaryDirectory()
            try Data([0x01]).write(to: directory.appendingPathComponent("Screenshot 1.png"))
            try Data([0x02]).write(to: directory.appendingPathComponent("Screen Shot 2.jpg"))
            try Data([0x03]).write(to: directory.appendingPathComponent("notes.png"))
            try Data([0x04]).write(to: directory.appendingPathComponent("Screenshot 3.txt"))

            let candidates = try ScreenshotDirectoryScanner.listCandidateFiles(in: directory)
            let names = Set(candidates.map(\.lastPathComponent))

            try expect(names == ["Screenshot 1.png", "Screen Shot 2.jpg"], "Scanner should keep only supported screenshot files")
        },
        CodexTestCase(name: "ScreenshotDirectoryScanner sorts candidates by creation date") {
            let directory = try makeTemporaryDirectory()
            let older = directory.appendingPathComponent("Screenshot older.png")
            let newer = directory.appendingPathComponent("Screenshot newer.png")
            try Data([0x01]).write(to: older)
            try Data([0x02]).write(to: newer)

            let fileManager = FileManager.default
            try fileManager.setAttributes(
                [.creationDate: Date(timeIntervalSince1970: 100)],
                ofItemAtPath: older.path
            )
            try fileManager.setAttributes(
                [.creationDate: Date(timeIntervalSince1970: 200)],
                ofItemAtPath: newer.path
            )

            let sorted = ScreenshotDirectoryScanner.sortCandidatesByCreationDate([newer, older])
            try expect(sorted.map(\.lastPathComponent) == ["Screenshot older.png", "Screenshot newer.png"], "Older screenshot should sort first")
        },
        CodexTestCase(name: "ScreenshotDirectoryScanner waitUntilReadable succeeds for readable file") {
            let directory = try makeTemporaryDirectory()
            let fileURL = directory.appendingPathComponent("Screenshot readable.png")
            try Data([0xFF]).write(to: fileURL)

            var sleepCalls = 0
            let result = ScreenshotDirectoryScanner.waitUntilReadable(fileURL) { _ in
                sleepCalls += 1
            }

            try expect(result, "Readable file should be reported as readable")
            try expect(sleepCalls == 0, "Readable file should not require retries")
        },
        CodexTestCase(name: "ScreenshotDirectoryScanner waitUntilReadable fails after retries for missing file") {
            let directory = try makeTemporaryDirectory()
            let fileURL = directory.appendingPathComponent("Screenshot missing.png")

            var sleepCalls = 0
            let result = ScreenshotDirectoryScanner.waitUntilReadable(fileURL) { _ in
                sleepCalls += 1
            }

            try expect(!result, "Missing file should not become readable")
            try expect(sleepCalls == 8, "Missing file should use the full retry budget")
        },
    ]

    private static func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
