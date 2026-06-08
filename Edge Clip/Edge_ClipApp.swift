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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 应用核心服务由 AppDelegate 直接持有，确保启动流程不依赖 SwiftUI 设置窗口
    /// 何时被实例化。开机静默自启场景下，设置窗口会被立即 `orderOut`，导致
    /// SwiftUI 的 `Window` Scene 不会构造 ContentView，从而 `.task` 永远不被
    /// 调度。如果 `services.start()` 绑定在 ContentView 上，应用就会变成
    /// "Dock 有图标但所有服务都没起来"的空壳状态。
    let services = AppServices()

    private var hasFinishedInitialLaunchSetup = false
    private var hasStartedServices = false

    nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            services.openSettingsWindow()
        }
        return true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        prepareInitialLaunchVisibility()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        finalizeInitialLaunchVisibility()
        startServicesIfNeeded()
    }

    private func startServicesIfNeeded() {
        guard !hasStartedServices else { return }
        hasStartedServices = true

        // 先装一个 AppKit 兜底的"打开设置窗口"动作。即使 SwiftUI 还没构造
        // ContentView（比如开机静默启动后用户从未点过 Dock 图标），菜单栏
        // 状态项的"打开设置"或 Reopen 也能正确把窗口拉起来。
        // ContentView 一旦挂载，会用 SwiftUI 的 `openWindow` 动作覆盖这里
        // 的兜底实现，从而支持窗口已被完全关闭后重新创建的场景。
        services.configureOpenSettingsWindowAction { [weak self] in
            self?.fallbackOpenSettingsWindow()
        }
        services.start()
    }

    private func fallbackOpenSettingsWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == AppWindowID.settings }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            LaunchSettingsWindowControl.markShown()
            return
        }
        // 兜底再兜底：找不到设置窗口对象时至少把应用激活，避免静默失败。
        NSApp.activate(ignoringOtherApps: true)
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

    var body: some Scene {
        Window("Edge Clip", id: AppWindowID.settings) {
            ContentView()
                .environmentObject(appDelegate.services)
                .environmentObject(appDelegate.services.appState)
        }
    }
}
