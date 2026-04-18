import CodexScreenshotBridgeCore

enum ClipboardWatcherStateTests {
    static let all: [CodexTestCase] = [
        CodexTestCase(name: "ClipboardWatcherState suppresses ignored change count") {
            var state = ClipboardWatcherState(initialChangeCount: 4)
            state.ignore(changeCount: 5)

            let event = state.processPoll(
                currentChangeCount: 5,
                hasImage: true,
                types: ["public.png"]
            )

            try expect(event == nil, "Ignored change count should not emit an event")
            try expect(state.pendingChangeCount == nil, "Ignored event should clear pending change count")
            try expect(state.pendingRetryCount == 0, "Ignored event should reset retry count")
        },
        CodexTestCase(name: "ClipboardWatcherState emits event when image is ready") {
            var state = ClipboardWatcherState(initialChangeCount: 1)

            let event = state.processPoll(
                currentChangeCount: 2,
                hasImage: true,
                types: ["public.png", "public.tiff"]
            )

            try expectEqual(
                event,
                ClipboardWatchEvent(changeCount: 2, types: ["public.png", "public.tiff"]),
                "Ready image should emit event"
            )
            try expect(state.pendingChangeCount == nil, "Event emission should clear pending state")
        },
        CodexTestCase(name: "ClipboardWatcherState retries until image becomes available") {
            var state = ClipboardWatcherState(initialChangeCount: 7, maxImageResolutionRetries: 2)

            try expect(state.processPoll(currentChangeCount: 8, hasImage: false, types: []) == nil, "First missing image should not emit event")
            try expect(state.pendingRetryCount == 1, "First retry should increment retry count")

            try expect(state.processPoll(currentChangeCount: 8, hasImage: false, types: []) == nil, "Second missing image should not emit event")
            try expect(state.pendingRetryCount == 2, "Second retry should increment retry count")

            let event = state.processPoll(currentChangeCount: 8, hasImage: true, types: ["public.png"])
            try expectEqual(event, ClipboardWatchEvent(changeCount: 8, types: ["public.png"]), "Delayed image should emit once ready")
            try expect(state.pendingRetryCount == 0, "Successful event should reset retry count")
            try expect(state.pendingChangeCount == nil, "Successful event should clear pending change count")
        },
        CodexTestCase(name: "ClipboardWatcherState drops pending change after max retries") {
            var state = ClipboardWatcherState(initialChangeCount: 10, maxImageResolutionRetries: 1)

            try expect(state.processPoll(currentChangeCount: 11, hasImage: false, types: []) == nil, "First missing image should not emit event")
            try expect(state.pendingRetryCount == 1, "Retry count should increment")

            try expect(state.processPoll(currentChangeCount: 11, hasImage: false, types: []) == nil, "Exhausted retry should not emit event")
            try expect(state.pendingRetryCount == 0, "Exhausted retry should reset retry count")
            try expect(state.pendingChangeCount == nil, "Exhausted retry should clear pending change")
        },
        CodexTestCase(name: "ClipboardWatcherState reset clears internal state") {
            var state = ClipboardWatcherState(initialChangeCount: 3)
            state.ignore(changeCount: 4)
            _ = state.processPoll(currentChangeCount: 4, hasImage: false, types: [])

            state.reset(currentChangeCount: 9)

            try expect(state.lastChangeCount == 9, "Reset should update last change count")
            try expect(state.ignoredChangeCounts.isEmpty, "Reset should clear ignored change counts")
            try expect(state.pendingChangeCount == nil, "Reset should clear pending change count")
            try expect(state.pendingRetryCount == 0, "Reset should clear retry count")
        },
    ]
}
