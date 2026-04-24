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

    private func configureWindowIfNeeded(from view: NSView, coordinator: Coordinator) {
        guard let window = view.window else { return }
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = false
        window.contentMinSize = minContentSize
        window.minSize = minContentSize
        window.collectionBehavior.remove(.fullScreenPrimary)
        window.collectionBehavior.remove(.fullScreenAllowsTiling)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        if window.delegate !== coordinator {
            window.delegate = coordinator
        }
        coordinator.attach(to: window)
        switch appearanceMode {
        case .system:
            window.appearance = nil
        case .light:
            window.appearance = NSAppearance(named: .aqua)
        case .dark:
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var userResizeMinWidth: CGFloat
        var onWindowVisibilityChanged: (Bool) -> Void
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
