import Foundation

package struct ClipboardWatchEvent: Equatable {
    package let changeCount: Int
    package let types: [String]

    package init(changeCount: Int, types: [String]) {
        self.changeCount = changeCount
        self.types = types
    }
}

package struct ClipboardWatcherState {
    package private(set) var lastChangeCount: Int
    package private(set) var ignoredChangeCounts: Set<Int> = []
    package private(set) var pendingChangeCount: Int?
    package private(set) var pendingRetryCount = 0
    package let maxImageResolutionRetries: Int

    package init(initialChangeCount: Int, maxImageResolutionRetries: Int = 14) {
        self.lastChangeCount = initialChangeCount
        self.maxImageResolutionRetries = maxImageResolutionRetries
    }

    package mutating func reset(currentChangeCount: Int) {
        ignoredChangeCounts.removeAll()
        pendingChangeCount = nil
        pendingRetryCount = 0
        lastChangeCount = currentChangeCount
    }

    package mutating func ignore(changeCount: Int) {
        ignoredChangeCounts.insert(changeCount)
    }

    package mutating func processPoll(
        currentChangeCount: Int,
        hasImage: Bool,
        types: [String]
    ) -> ClipboardWatchEvent? {
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            pendingChangeCount = currentChangeCount
            pendingRetryCount = 0
        }

        guard let changeCount = pendingChangeCount else {
            return nil
        }

        if ignoredChangeCounts.remove(changeCount) != nil {
            pendingChangeCount = nil
            pendingRetryCount = 0
            return nil
        }

        guard hasImage else {
            if pendingRetryCount < maxImageResolutionRetries {
                pendingRetryCount += 1
            } else {
                pendingChangeCount = nil
                pendingRetryCount = 0
            }
            return nil
        }

        pendingChangeCount = nil
        pendingRetryCount = 0
        return ClipboardWatchEvent(changeCount: changeCount, types: types)
    }
}
