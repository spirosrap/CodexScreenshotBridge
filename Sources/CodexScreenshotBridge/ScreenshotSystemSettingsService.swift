import Foundation

package final class ScreenshotSystemSettingsService: ScreenshotSystemSettingsServicing {
    package enum SettingsError: LocalizedError {
        case preferencesWriteFailed
        case systemUIServerRestartFailed(Int32)

        package var errorDescription: String? {
            switch self {
            case .preferencesWriteFailed:
                return "Could not update macOS screenshot settings."
            case let .systemUIServerRestartFailed(status):
                return "Could not restart SystemUIServer after updating screenshot settings (status \(status))."
            }
        }
    }

    private let preferencesDomain = "com.apple.screencapture" as CFString
    private let showThumbnailKey = "show-thumbnail" as CFString

    package init() {}

    package func floatingThumbnailState() -> ScreenshotFloatingThumbnailState {
        guard let value = CFPreferencesCopyAppValue(showThumbnailKey, preferencesDomain) else {
            return .enabled
        }

        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean)) ? .enabled : .disabled
        }

        if let number = value as? NSNumber {
            return number.boolValue ? .enabled : .disabled
        }

        return .unknown
    }

    package func disableFloatingThumbnail() throws {
        CFPreferencesSetAppValue(showThumbnailKey, kCFBooleanFalse, preferencesDomain)

        guard CFPreferencesAppSynchronize(preferencesDomain) else {
            throw SettingsError.preferencesWriteFailed
        }

        try restartSystemUIServer()
    }

    private func restartSystemUIServer() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["SystemUIServer"]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SettingsError.systemUIServerRestartFailed(process.terminationStatus)
        }
    }
}
