import AppKit
import SwiftUI

package struct ContentView: View {
    @EnvironmentObject private var controller: BridgeController

    package init() {}

    package var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codex Screenshot Bridge")
                .font(.headline)

            Text(controller.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Toggle("Bridge Enabled", isOn: $controller.bridgeEnabled)

            Toggle("Auto-paste into Codex", isOn: $controller.autoPasteEnabled)
                .disabled(!controller.bridgeEnabled)

            Toggle("Handle clipboard screenshot shortcut", isOn: $controller.listenClipboardImages)
                .disabled(!controller.bridgeEnabled)

            VStack(alignment: .leading, spacing: 5) {
                Text("Screenshot Folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(controller.screenshotDirectoryPath)
                    .font(.caption2)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button("Choose Folder") {
                    controller.chooseScreenshotFolder()
                }

                Button("Restart Watcher") {
                    controller.restartWatching()
                }
                .disabled(!controller.bridgeEnabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Codex bundle ID (optional)", text: $controller.codexBundleIdentifier)
                    .textFieldStyle(.roundedBorder)

                Text("Leave blank to auto-detect a running app named Codex.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            permissionSection

            Divider()

            Text("Recent Events")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if controller.recentEvents.isEmpty {
                        Text("No events yet.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(controller.recentEvents, id: \.self) { event in
                            Text(event)
                                .font(.caption2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .frame(height: 120)

            Divider()

            Button("Quit Codex Screenshot Bridge") {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 430)
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Text("Permission Status")
                .font(.caption)
                .foregroundStyle(.secondary)

            permissionStatusRow(
                title: "Accessibility",
                isGranted: controller.accessibilityPermissionGranted
            )

            permissionStatusRow(
                title: "Screen Recording",
                isGranted: controller.screenRecordingPermissionGranted
            )

            HStack(spacing: 8) {
                Button("Request Accessibility") {
                    controller.requestAccessibilityAccess()
                }

                Button("Request Screen Recording") {
                    controller.requestScreenRecordingAccess()
                }
            }

            HStack(spacing: 8) {
                Button("Refresh Permission Status") {
                    controller.refreshPermissionStatus()
                }
            }

            Text("Screen Recording is only used for the one-shot startup-screen check.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func permissionStatusRow(title: String, isGranted: Bool) -> some View {
        HStack {
            Text(title)
                .font(.caption)
            Spacer()
            Text(isGranted ? "Granted" : "Not Granted")
                .font(.caption2)
                .foregroundStyle(isGranted ? .green : .secondary)
        }
    }
}
