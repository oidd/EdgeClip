import AppKit
import SwiftUI

enum AppWindowID {
    static let settings = "edgeclip.settings"
}

private enum LaunchSettingsWindowControl {
    static let userDefaultsKey = "edgeclip.launch.hasShownSettingsWindowOnce"

    static var hasShownBefore: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onReopenRequested: (() -> Void)?
    private var hasFinishedInitialLaunchSetup = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            onReopenRequested?()
        }
        return true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        prepareInitialLaunchVisibility()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        finalizeInitialLaunchVisibility()
    }

    /// SwiftUI 的单 `Window` Scene 默认会在启动时自动展示。
    /// 我们希望除了"首次安装"之外，应用都以后台方式启动，不出现一闪即收的设置窗口。
    /// 这里在 `applicationWillFinishLaunching` 阶段尽早把候选窗口隐藏。
    private func prepareInitialLaunchVisibility() {
        guard LaunchSettingsWindowControl.hasShownBefore else {
            // 首次安装：保留默认行为，让设置窗口正常出现 + 触发 Onboarding。
            return
        }
        hideAutoShownSettingsWindows()
    }

    private func finalizeInitialLaunchVisibility() {
        defer { hasFinishedInitialLaunchSetup = true }

        guard !hasFinishedInitialLaunchSetup else { return }

        if LaunchSettingsWindowControl.hasShownBefore {
            // 第二次及之后启动：再做一次兜底隐藏，覆盖系统在 will/did launch 之间的窗口动画。
            hideAutoShownSettingsWindows()
            DispatchQueue.main.async { [weak self] in
                self?.hideAutoShownSettingsWindows()
            }
        } else {
            // 首次安装：标记一次，下次启动起改走后台模式。
            LaunchSettingsWindowControl.markShown()
        }
    }

    private func hideAutoShownSettingsWindows() {
        for window in NSApp.windows {
            guard window.identifier?.rawValue == AppWindowID.settings else { continue }
            window.orderOut(nil)
        }
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
                    LaunchSettingsWindowControl.markShown()
                    appDelegate.onReopenRequested = {
                        services.openSettingsWindow()
                    }
                }
        }
    }
}
