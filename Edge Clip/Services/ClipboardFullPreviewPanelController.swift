import AppKit
import SwiftUI

@MainActor
final class ClipboardFullPreviewPanelController: NSObject, NSWindowDelegate {
    private let minimumPanelSize = NSSize(width: 420, height: 320)
    private let horizontalGap: CGFloat = 10
    private let edgeInset: CGFloat = 12

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?

    var onClose: (() -> Void)?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    var frame: NSRect? {
        panel?.frame
    }

    func show<Content: View>(
        anchoredTo anchorFrame: NSRect,
        appearanceMode: AppearanceMode,
        initialSize: NSSize,
        @ViewBuilder content: () -> Content
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let root = AnyView(content())
        if let hostingView {
            hostingView.rootView = root
            if panel.contentView !== hostingView {
                panel.contentView = hostingView
            }
        } else {
            let hostedView = NSHostingView(rootView: root)
            hostedView.wantsLayer = true
            hostedView.layer?.masksToBounds = true
            hostedView.layer?.cornerRadius = 18
            panel.contentView = hostedView
            hostingView = hostedView
        }

        applyAppearance(mode: appearanceMode, to: panel)
        position(panel: panel, anchoredTo: anchorFrame, size: initialSize)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func contains(point: CGPoint) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.contains(point)
    }

    func updateAppearance(mode: AppearanceMode) {
        guard let panel else { return }
        applyAppearance(mode: mode, to: panel)
    }

    func updatePosition(anchoredTo anchorFrame: NSRect, size: NSSize) {
        guard let panel, panel.isVisible else { return }
        position(panel: panel, anchoredTo: anchorFrame, size: size)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func makePanel() -> NSPanel {
        let panel = EdgeClipFullPreviewPanel(
            contentRect: NSRect(origin: .zero, size: minimumPanelSize),
            styleMask: [.borderless, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.minSize = minimumPanelSize
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        return panel
    }

    private func applyAppearance(mode: AppearanceMode, to panel: NSPanel) {
        switch mode {
        case .system:
            panel.appearance = nil
        case .light:
            panel.appearance = NSAppearance(named: .aqua)
        case .dark:
            panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func position(panel: NSPanel, anchoredTo anchorFrame: NSRect, size: NSSize) {
        let frame = positionedFrame(anchoredTo: anchorFrame, size: size)
        panel.setFrame(frame, display: true, animate: false)
    }

    private func positionedFrame(anchoredTo anchorFrame: NSRect, size: NSSize) -> NSRect {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(anchorFrame) } ?? NSScreen.main
        guard let screen else {
            return NSRect(origin: .zero, size: size)
        }

        let maxWidth = max(minimumPanelSize.width, screen.visibleFrame.width - edgeInset * 2)
        let maxHeight = max(minimumPanelSize.height, screen.visibleFrame.height - edgeInset * 2)
        let clampedSize = NSSize(
            width: min(max(size.width, minimumPanelSize.width), maxWidth),
            height: min(max(size.height, minimumPanelSize.height), maxHeight)
        )

        let minX = screen.visibleFrame.minX + edgeInset
        let maxX = screen.visibleFrame.maxX - clampedSize.width - edgeInset
        let minY = screen.visibleFrame.minY + edgeInset
        let maxY = screen.visibleFrame.maxY - clampedSize.height - edgeInset

        let preferredLeftX = anchorFrame.minX - clampedSize.width - horizontalGap
        let preferredRightX = anchorFrame.maxX + horizontalGap
        let leftFits = preferredLeftX >= minX
        let rightFits = preferredRightX <= maxX

        let x: CGFloat
        if leftFits {
            x = preferredLeftX
        } else if rightFits {
            x = preferredRightX
        } else {
            let leftAvailableWidth = max(0, anchorFrame.minX - horizontalGap - minX)
            let rightAvailableWidth = max(0, maxX - anchorFrame.maxX - horizontalGap)
            if leftAvailableWidth >= rightAvailableWidth {
                x = min(max(preferredLeftX, minX), maxX)
            } else {
                x = min(max(preferredRightX, minX), maxX)
            }
        }

        let preferredY = anchorFrame.maxY - clampedSize.height
        let y = min(max(preferredY, minY), maxY)

        return NSRect(x: x, y: y, width: clampedSize.width, height: clampedSize.height)
    }
}

private final class EdgeClipFullPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
