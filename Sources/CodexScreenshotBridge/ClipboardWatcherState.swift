import Foundation
import UniformTypeIdentifiers

package struct ClipboardWatchEvent: Equatable {
    package let changeCount: Int
    package let types: [String]
    package let detectedAtUptimeNanoseconds: UInt64

    package init(
        changeCount: Int,
        types: [String],
        detectedAtUptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        self.changeCount = changeCount
        self.types = types
        self.detectedAtUptimeNanoseconds = detectedAtUptimeNanoseconds
    }
}

package struct ClipboardWatcherState {
    package private(set) var lastChangeCount: Int
    package private(set) var ignoredChangeCounts: Set<Int> = []
    package private(set) var pendingChangeCount: Int?
    package private(set) var pendingDetectedAtUptimeNanoseconds: UInt64?
    package private(set) var pendingRetryCount = 0
    package let maxImageResolutionRetries: Int

    package init(initialChangeCount: Int, maxImageResolutionRetries: Int = 14) {
        self.lastChangeCount = initialChangeCount
        self.maxImageResolutionRetries = maxImageResolutionRetries
    }

    package mutating func reset(currentChangeCount: Int) {
        ignoredChangeCounts.removeAll()
        pendingChangeCount = nil
        pendingDetectedAtUptimeNanoseconds = nil
        pendingRetryCount = 0
        lastChangeCount = currentChangeCount
    }

    package mutating func ignore(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    package mutating func processPoll(
        currentChangeCount: Int,
        hasImage: Bool,
        types: [String],
        nowUptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> ClipboardWatchEvent? {
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            pendingChangeCount = currentChangeCount
            pendingDetectedAtUptimeNanoseconds = nowUptimeNanoseconds
            pendingRetryCount = 0
        }

        guard let changeCount = pendingChangeCount else {
            return nil
        }

        if ignoredChangeCounts.remove(changeCount) != nil {
            pendingChangeCount = nil
            pendingDetectedAtUptimeNanoseconds = nil
            pendingRetryCount = 0
            return nil
        }

        guard hasImage else {
            if pendingRetryCount < maxImageResolutionRetries {
                pendingRetryCount += 1
            } else {
                pendingChangeCount = nil
                pendingDetectedAtUptimeNanoseconds = nil
                pendingRetryCount = 0
            }
            return nil
        }

        pendingChangeCount = nil
        let detectedAtUptimeNanoseconds = pendingDetectedAtUptimeNanoseconds ?? nowUptimeNanoseconds
        pendingDetectedAtUptimeNanoseconds = nil
        pendingRetryCount = 0
        return ClipboardWatchEvent(
            changeCount: changeCount,
            types: types,
            detectedAtUptimeNanoseconds: detectedAtUptimeNanoseconds
        )
    }
}

package enum ClipboardImageTypeClassifier {
    package static func hasImageType(_ rawTypes: [String]) -> Bool {
        rawTypes.contains { rawType in
            if let uniformType = UTType(rawType), uniformType.conforms(to: .image) {
                return true
            }

            switch rawType.lowercased() {
            case "public.png",
                 "apple png pasteboard type",
                 "public.tiff",
                 "next tiff v4.0 pasteboard type",
                 "nstiffpboardtype",
                 "public.jpeg",
                 "public.heic",
                 "com.compuserve.gif":
                return true
            default:
                return false
            }
        }
    }
}
