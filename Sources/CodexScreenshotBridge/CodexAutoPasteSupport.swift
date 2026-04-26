import Foundation

package enum CodexComposerLayout {
    case conversation
    case firstPrompt
}

package struct CodexRunningAppDescriptor: Equatable {
    package let processIdentifier: pid_t
    package let bundleIdentifier: String?
    package let localizedName: String?

    package init(processIdentifier: pid_t, bundleIdentifier: String?, localizedName: String?) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
    }
}

package enum CodexAppMatcher {
    package static func bestMatch(
        bundleIdentifier: String?,
        currentPID: pid_t,
        ownBundleIdentifier: String?,
        candidates: [CodexRunningAppDescriptor]
    ) -> CodexRunningAppDescriptor? {
        let filteredApps = candidates.filter { app in
            guard app.processIdentifier != currentPID else {
                return false
            }

            if let ownBundleIdentifier, app.bundleIdentifier == ownBundleIdentifier {
                return false
            }

            if let bundle = app.bundleIdentifier?.lowercased() {
                if bundle.hasPrefix("com.apple.") {
                    return false
                }
                if bundle.contains("webkit") {
                    return false
                }
            }

            return true
        }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return filteredApps.first { $0.bundleIdentifier == bundleIdentifier }
        }

        if let exactCodexBundle = filteredApps.first(where: { $0.bundleIdentifier == "com.openai.codex" }) {
            return exactCodexBundle
        }

        if let exactChatGPTBundle = filteredApps.first(where: { $0.bundleIdentifier == "com.openai.chat" }) {
            return exactChatGPTBundle
        }

        if let exactNameMatch = filteredApps.first(where: {
            $0.localizedName?.caseInsensitiveCompare("Codex") == .orderedSame
        }) {
            return exactNameMatch
        }

        if let openAINameMatch = filteredApps.first(where: {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains("chatgpt")
        }) {
            return openAINameMatch
        }

        return filteredApps.first(where: {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains("codex") ||
                ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains("codex")
        })
    }

    package static func fallbackApplicationURLs(homeDirectory: URL) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications/Codex.app"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            homeDirectory
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("Codex.app", isDirectory: true),
            homeDirectory
                .appendingPathComponent("Applications", isDirectory: true)
                .appendingPathComponent("ChatGPT.app", isDirectory: true),
        ]
    }
}

package enum ComposerPointCalculator {
    package static func activationPoints(in bounds: CGRect, layout: CodexComposerLayout) -> [CGPoint] {
        switch layout {
        case .conversation:
            return makePoints(
                in: bounds,
                xFractions: [0.5],
                yFractions: [0.91]
            )
        case .firstPrompt:
            return makePoints(
                in: bounds,
                xFractions: [0.42, 0.54, 0.66],
                yFractions: [0.39, 0.43]
            )
        }
    }

    package static func editorFocusPoints(in bounds: CGRect, layout: CodexComposerLayout) -> [CGPoint] {
        switch layout {
        case .conversation:
            return activationPoints(in: bounds, layout: layout)
        case .firstPrompt:
            return makePoints(
                in: bounds,
                xFractions: [0.10, 0.14],
                yFractions: [0.398]
            )
        }
    }

    package static func makePoints(
        in bounds: CGRect,
        xFractions: [CGFloat],
        yFractions: [CGFloat]
    ) -> [CGPoint] {
        var points: [CGPoint] = []
        points.reserveCapacity(xFractions.count * yFractions.count)

        for yFraction in yFractions {
            let y = bounds.minY + (bounds.height * yFraction)
            for xFraction in xFractions {
                points.append(
                    CGPoint(
                        x: bounds.minX + (bounds.width * xFraction),
                        y: y
                    )
                )
            }
        }

        return points
    }
}

package enum CodexWindowCaptureSizer {
    package static let defaultMaxDimension: CGFloat = 1_200

    package static func outputSize(
        for frame: CGRect,
        maxDimension: CGFloat = defaultMaxDimension
    ) -> CGSize {
        let sourceWidth = max(frame.width, 1)
        let sourceHeight = max(frame.height, 1)
        let scale = min(1, maxDimension / max(sourceWidth, sourceHeight))

        return CGSize(
            width: max((sourceWidth * scale).rounded(.toNearestOrAwayFromZero), 1),
            height: max((sourceHeight * scale).rounded(.toNearestOrAwayFromZero), 1)
        )
    }
}
