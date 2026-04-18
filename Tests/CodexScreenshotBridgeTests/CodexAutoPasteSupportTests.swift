import Foundation
import CodexScreenshotBridgeCore

enum CodexAutoPasteSupportTests {
    static let all: [CodexTestCase] = [
        CodexTestCase(name: "CodexAppMatcher respects explicit bundle identifier") {
            let candidates = [
                CodexRunningAppDescriptor(processIdentifier: 10, bundleIdentifier: "com.openai.chat", localizedName: "ChatGPT"),
                CodexRunningAppDescriptor(processIdentifier: 11, bundleIdentifier: "com.example.other", localizedName: "Other"),
            ]

            let match = CodexAppMatcher.bestMatch(
                bundleIdentifier: "com.openai.chat",
                currentPID: 1,
                ownBundleIdentifier: "com.spirosraptis.CodexScreenshotBridge",
                candidates: candidates
            )

            try expect(match?.processIdentifier == 10, "Explicit bundle identifier should win")
        },
        CodexTestCase(name: "CodexAppMatcher prefers Codex bundle over ChatGPT bundle") {
            let candidates = [
                CodexRunningAppDescriptor(processIdentifier: 20, bundleIdentifier: "com.openai.chat", localizedName: "ChatGPT"),
                CodexRunningAppDescriptor(processIdentifier: 21, bundleIdentifier: "com.openai.codex", localizedName: "Codex"),
            ]

            let match = CodexAppMatcher.bestMatch(
                bundleIdentifier: nil,
                currentPID: 1,
                ownBundleIdentifier: nil,
                candidates: candidates
            )

            try expect(match?.processIdentifier == 21, "Exact Codex bundle should beat ChatGPT fallback")
        },
        CodexTestCase(name: "CodexAppMatcher filters self, Apple, and WebKit processes") {
            let candidates = [
                CodexRunningAppDescriptor(processIdentifier: 1, bundleIdentifier: "com.example.self", localizedName: "Self"),
                CodexRunningAppDescriptor(processIdentifier: 2, bundleIdentifier: "com.apple.finder", localizedName: "Finder"),
                CodexRunningAppDescriptor(processIdentifier: 3, bundleIdentifier: "com.example.webkit.helper", localizedName: "WebKit Helper"),
                CodexRunningAppDescriptor(processIdentifier: 4, bundleIdentifier: "com.example.codex-helper", localizedName: "My Codex Helper"),
            ]

            let match = CodexAppMatcher.bestMatch(
                bundleIdentifier: nil,
                currentPID: 1,
                ownBundleIdentifier: "com.example.self",
                candidates: candidates
            )

            try expect(match?.processIdentifier == 4, "Only valid Codex-like app should remain after filtering")
        },
        CodexTestCase(name: "CodexAppMatcher fallback application URLs prefer system then home apps") {
            let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
            let urls = CodexAppMatcher.fallbackApplicationURLs(homeDirectory: home)

            try expect(urls.map(\.path) == [
                "/Applications/Codex.app",
                "/Applications/ChatGPT.app",
                "/Users/example/Applications/Codex.app",
                "/Users/example/Applications/ChatGPT.app",
            ], "Fallback URLs should prefer system apps before home directory apps")
        },
        CodexTestCase(name: "ComposerPointCalculator computes conversation activation point") {
            let bounds = CGRect(x: 100, y: 200, width: 300, height: 400)
            let points = ComposerPointCalculator.activationPoints(in: bounds, layout: .conversation)

            try expect(points == [CGPoint(x: 250, y: 564)], "Conversation layout should click bottom-center composer")
        },
        CodexTestCase(name: "ComposerPointCalculator uses dedicated first-prompt focus points") {
            let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
            let activationPoints = ComposerPointCalculator.activationPoints(in: bounds, layout: .firstPrompt)
            let focusPoints = ComposerPointCalculator.editorFocusPoints(in: bounds, layout: .firstPrompt)

            try expect(activationPoints == [
                CGPoint(x: 420, y: 195),
                CGPoint(x: 540, y: 195),
                CGPoint(x: 660, y: 195),
                CGPoint(x: 420, y: 215),
                CGPoint(x: 540, y: 215),
                CGPoint(x: 660, y: 215),
            ], "First prompt activation points should span the centered composer")
            try expect(focusPoints == [CGPoint(x: 100, y: 199), CGPoint(x: 140, y: 199)], "First prompt focus points should target the editor line")
        },
    ]
}
