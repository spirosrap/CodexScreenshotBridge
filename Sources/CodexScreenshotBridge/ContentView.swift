import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var controller: BridgeController

    var body: some View {
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

            Button("Request Accessibility Permission") {
                controller.requestAccessibilityAccess()
            }
            .disabled(!controller.bridgeEnabled || !controller.autoPasteEnabled)

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
        }
        .padding(14)
        .frame(width: 430)
    }
}
