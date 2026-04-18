import Foundation

let tests = BridgeControllerTests.all +
    ClipboardServiceTests.all +
    ClipboardWatcherStateTests.all +
    CodexAutoPasteSupportTests.all +
    ScreenshotDirectoryScannerTests.all

Task {
    var failedTests: [(name: String, message: String)] = []

    for test in tests {
        do {
            try await test.run()
            print("PASS \(test.name)")
        } catch {
            let message: String
            if let failure = error as? TestFailure {
                message = failure.description
            } else {
                message = String(describing: error)
            }

            failedTests.append((test.name, message))
            print("FAIL \(test.name): \(message)")
        }
    }

    print("")
    print("Executed \(tests.count) tests")

    if failedTests.isEmpty {
        print("All tests passed")
        exit(0)
    }

    print("\(failedTests.count) tests failed")
    for failedTest in failedTests {
        print("- \(failedTest.name): \(failedTest.message)")
    }

    exit(1)
}

dispatchMain()
