import AppKit
import SwiftUI

enum AppWindowID {
    static let settings = "edgeclip.settings"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onReopenRequested: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            onReopenRequested?()
        }
        return true
    }
}

@main
struct Edge_ClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var services = AppServices()

    var body: some Scene {
        Window("Edge Clip", id: AppWindowID.settings) {
            ContentView()
                .environmentObject(services)
                .environmentObject(services.appState)
                .preferredColorScheme(services.preferredColorScheme)
                .onAppear {
                    appDelegate.onReopenRequested = {
                        services.openSettingsWindow()
                    }
                }
        }
    }
}
