import AppKit
import SwiftUI

struct WindowChromeConfigurator: NSViewRepresentable {
    let appearanceMode: AppearanceMode
    let minContentSize: NSSize
    let userResizeMinWidth: CGFloat
    let onWindowVisibilityChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            userResizeMinWidth: userResizeMinWidth,
            onWindowVisibilityChanged: onWindowVisibilityChanged
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configureWindowIfNeeded(from: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.userResizeMinWidth = userResizeMinWidth
        context.coordinator.onWindowVisibilityChanged = onWindowVisibilityChanged
        DispatchQueue.main.async {
            configureWindowIfNeeded(from: nsView, coordinator: context.coordinator)
        }
    }

    /// 把窗口配置拆成两部分做幂等保护：
    ///
    /// 1. **一次性属性**（title / styleMask / isOpaque / backgroundColor /
    ///    collectionBehavior / zoom button / delegate 等）只在第一次配置时
    ///    写入，后续不再重复设置。这些属性反复写入会让 AppKit 在已经
    ///    在 layout 的窗口上再次触发 layout，控制台报
    ///    `_NSDetectedLayoutRecursion` / "It's not legal to call
    ///    -layoutSubtreeIfNeeded on a view which is already being laid out"。
    ///
    /// 2. **可变属性**（appearance、contentMinSize、minSize）每次比对当前
    ///    值再决定是否写入，相同就跳过。`NSAppearance(named:)` 每次都会
    ///    生成新实例，必须按 `name` 比对而不是引用比对。
    private func configureWindowIfNeeded(from view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }

        // attach() 必须在 didPerformInitialSetup 检查之前调用：当 view 第一次
        // 绑定到 NSWindow（或后续换到不同的 NSWindow）时，attach() 会把
        // didPerformInitialSetup / appliedAppearanceName 等缓存重置为初始
        // 状态。如果先做一次性初始化再 attach，第一次调用会经历"跑一遍初始
        // 化 → attach 把标志拨回 false → 下次更新时又跑一遍"，让"一次性"
        // 设置实际上跑了两次。
        coordinator.attach(to: window)

        if !coordinator.didPerformInitialSetup {
            coordinator.didPerformInitialSetup = true
            window.title = ""
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = false
            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.remove(.fullScreenAllowsTiling)
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            if window.delegate !== coordinator {
                window.delegate = coordinator
            }
        }

        if window.contentMinSize != minContentSize {
            window.contentMinSize = minContentSize
        }
        if window.minSize != minContentSize {
            window.minSize = minContentSize
        }

        let targetAppearanceName: NSAppearance.Name?
        switch appearanceMode {
        case .system:
            targetAppearanceName = nil
        case .light:
            targetAppearanceName = .aqua
        case .dark:
            targetAppearanceName = .darkAqua
        }

        if coordinator.appliedAppearanceName != targetAppearanceName {
            coordinator.appliedAppearanceName = targetAppearanceName
            window.appearance = targetAppearanceName.flatMap { NSAppearance(named: $0) }
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var userResizeMinWidth: CGFloat
        var onWindowVisibilityChanged: (Bool) -> Void
        var didPerformInitialSetup = false
        /// 记录最近一次写入的 appearance name。`NSWindow.appearance` 默认就是
        /// nil（跟随系统），所以这里也用 nil 作为初始值；当 `appearanceMode`
        /// 是 `.system` 且初始值就是 nil 时，会正确地跳过冗余写入。
        var appliedAppearanceName: NSAppearance.Name?
        private weak var observedWindow: NSWindow?
        private var hasReportedVisible = false

        init(
            userResizeMinWidth: CGFloat,
            onWindowVisibilityChanged: @escaping (Bool) -> Void
        ) {
            self.userResizeMinWidth = userResizeMinWidth
            self.onWindowVisibilityChanged = onWindowVisibilityChanged
        }

        func attach(to window: NSWindow) {
            if observedWindow !== window {
                observedWindow = window
                hasReportedVisible = false
                didPerformInitialSetup = false
                appliedAppearanceName = nil
            }

            guard window.isVisible, !hasReportedVisible else { return }
            hasReportedVisible = true
            onWindowVisibilityChanged(true)
        }

        func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
            guard sender.inLiveResize else { return frameSize }
            return NSSize(width: max(frameSize.width, userResizeMinWidth), height: frameSize.height)
        }

        func windowWillClose(_ notification: Notification) {
            hasReportedVisible = false
            onWindowVisibilityChanged(false)
        }
    }
}
