import AppKit
import SwiftUI
import CodexScreenshotBridgeCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct CodexScreenshotBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = BridgeController()

    var body: some Scene {
        MenuBarExtra("Codex Bridge", systemImage: "camera.on.rectangle") {
            ContentView()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.window)
    }
}
