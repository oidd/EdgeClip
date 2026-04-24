import AppKit
import SwiftUI

private enum EdgeTriggeredPlacementMetrics {
    static let panelVerticalPadding: CGFloat = 0
    static let firstRowCenterOffsetFromTop: CGFloat = 160
    static let firstRowHeight: CGFloat = 86
    static let activationIndicatorWidth: CGFloat = 7
    static let activationIndicatorHorizontalInset: CGFloat = 4
    // Keep some space for macOS hot corners at the top-right and bottom-right.
    static let cornerProtectionLength: CGFloat = 72
}

@MainActor
final class EdgePanelController: NSObject, NSWindowDelegate {
    struct EdgeActivationLayout {
        let screen: NSScreen
        let guideFrame: NSRect
        let panelFrame: NSRect
        let weakBandFrame: NSRect
        let strongBandFrame: NSRect
        let activationVerticalRange: ClosedRange<CGFloat>
    }

    enum PresentationMode {
        case edgeTriggered
        case manual
        case hotkey
        case rightDrag
        case menuBar

        var requiresTabHoverUnlock: Bool {
            switch self {
            case .hotkey, .rightDrag, .menuBar:
                return true
            case .edgeTriggered, .manual:
                return false
            }
        }
    }

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var autoCollapseTimer: Timer?
    private(set) var presentationMode: PresentationMode = .edgeTriggered
    private var hasPointerEnteredPanel = false
    private var requiresPointerReentryBeforeCollapse = false
    private var edgeActivationSide: EdgeActivationSide = .right
    private var edgeActivationPlacementMode: EdgeActivationPlacementMode = .followPointer
    private var edgeActivationCustomVerticalPosition: Double = 0.5
    private var hotkeyPanelPlacementMode: HotkeyPanelPlacementMode = .followPointer
    private var hotkeyPanelLastFrameOrigin: CGPoint?
    private var hoverSafetyPadding: CGFloat = 22
    // Hotkey-triggered panel should place the pointer near the visual center
    // of the first row instead of mixing mouse Y with focused-field X.
    private let hotkeyFirstRowCenterOffsetFromTop: CGFloat = 154
    private let hotkeyFirstRowCenterOffsetFromLeft: CGFloat = 220
    private let rightDragFirstRowCenterOffsetFromTop: CGFloat = 154
    private let rightDragPointerOffsetFromLeft: CGFloat = 176
    private let rightDragSelectionHorizontalPadding: CGFloat = 64
    private var pinnedIdleDimmedAlpha: CGFloat = 0.65
    private let menuBarPanelHorizontalPadding: CGFloat = 12
    private let menuBarPanelBottomPadding: CGFloat = 12
    private let menuBarPanelTopSpacing: CGFloat = 2

    var onVisibilityChanged: ((Bool) -> Void)?
    var onFrameChanged: (() -> Void)?
    var isPinnedProvider: () -> Bool = { false }
    var additionalActiveRegionProvider: (CGPoint) -> Bool = { _ in false }
    var isVisible: Bool { panel?.isVisible == true }
    var isKeyWindow: Bool { panel?.isKeyWindow == true }
    var currentMode: PresentationMode { presentationMode }
    var frame: NSRect? { panel?.frame }
    var previewAnchorFrame: NSRect? {
        guard let panel else { return nil }
        let titlebarInset = max(0, panel.frame.height - panel.contentLayoutRect.height)
        return NSRect(
            x: panel.frame.minX,
            y: panel.frame.minY,
            width: panel.frame.width,
            height: max(0, panel.frame.height - titlebarInset)
        )
    }

    func show<Content: View>(
        mode: PresentationMode,
        appearanceMode: AppearanceMode,
        size: NSSize,
        edgeActivationSide: EdgeActivationSide = .right,
        edgeActivationPlacementMode: EdgeActivationPlacementMode = .followPointer,
        edgeActivationCustomVerticalPosition: Double = 0.5,
        pointerOverride: CGPoint? = nil,
        statusItemAnchorRect: CGRect? = nil,
        @ViewBuilder content: () -> Content
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel
        presentationMode = mode
        hasPointerEnteredPanel = false
        requiresPointerReentryBeforeCollapse = false
        self.edgeActivationSide = edgeActivationSide
        self.edgeActivationPlacementMode = edgeActivationPlacementMode
        self.edgeActivationCustomVerticalPosition = min(1, max(0, edgeActivationCustomVerticalPosition))
        let triggerPointer = pointerOverride ?? NSEvent.mouseLocation

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
            hostedView.layer?.cornerRadius = 16
            panel.contentView = hostedView
            hostingView = hostedView
        }

        applyAppearance(mode: appearanceMode, to: panel)
        panel.alphaValue = 1
        position(
            panel: panel,
            mode: mode,
            size: size,
            pointer: triggerPointer,
            statusItemAnchorRect: statusItemAnchorRect
        )
        panel.makeKeyAndOrderFront(nil)
        onVisibilityChanged?(true)
        startAutoCollapseIfNeeded(panel: panel)
    }

    func hide() {
        stopAutoCollapseMonitoring()
        requiresPointerReentryBeforeCollapse = false
        panel?.alphaValue = 1
        panel?.orderOut(nil)
        onVisibilityChanged?(false)
    }

    func suspendAutoCollapseUntilPointerReenters() {
        guard panel?.isVisible == true else { return }
        requiresPointerReentryBeforeCollapse = true
    }

    func hasFocusedTextInput() -> Bool {
        guard let panel else { return false }
        return panel.firstResponder is NSTextView
    }

    func prepareForTextInput() {
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func updateAppearance(mode: AppearanceMode) {
        guard let panel else { return }
        applyAppearance(mode: mode, to: panel)
    }

    func updateEdgeActivationPlacement(
        side: EdgeActivationSide,
        mode: EdgeActivationPlacementMode,
        customVerticalPosition: Double
    ) {
        edgeActivationSide = side
        edgeActivationPlacementMode = mode
        edgeActivationCustomVerticalPosition = min(1, max(0, customVerticalPosition))
    }

    func updateHotkeyPlacement(
        mode: HotkeyPanelPlacementMode,
        lastFrameOrigin: CGPoint?
    ) {
        hotkeyPanelPlacementMode = mode
        hotkeyPanelLastFrameOrigin = lastFrameOrigin
    }

    func updateEdgeAutoCollapseDistance(_ distance: CGFloat) {
        hoverSafetyPadding = max(0, distance)
    }

    func updateSize(_ size: NSSize) {
        guard let panel else { return }
        position(panel: panel, mode: presentationMode, size: size, pointer: NSEvent.mouseLocation)
    }

    func updatePinnedIdleTransparencyPercent(_ transparencyPercent: Int) {
        let clampedTransparency = min(90, max(0, transparencyPercent))
        pinnedIdleDimmedAlpha = 1 - CGFloat(clampedTransparency) / 100

        guard let panel, panel.alphaValue < 0.999 else { return }
        panel.alphaValue = pinnedIdleDimmedAlpha
    }

    func setPinnedIdleDimmed(_ isDimmed: Bool, animated: Bool = true) {
        guard let panel else { return }
        let targetAlpha = isDimmed ? pinnedIdleDimmedAlpha : 1.0
        guard abs(panel.alphaValue - targetAlpha) > 0.01 else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = targetAlpha
            }
        } else {
            panel.alphaValue = targetAlpha
        }
    }

    static func edgeTriggeredLayout(
        on screen: NSScreen,
        size: NSSize,
        pointer: CGPoint?,
        side: EdgeActivationSide,
        placementMode: EdgeActivationPlacementMode,
        customVerticalPosition: Double
    ) -> EdgeActivationLayout {
        let visibleFrame = screen.visibleFrame
        let minY = visibleFrame.minY + EdgeTriggeredPlacementMetrics.panelVerticalPadding
        let maxY = max(
            minY,
            visibleFrame.maxY - size.height - EdgeTriggeredPlacementMetrics.panelVerticalPadding
        )

        let panelY: CGFloat
        switch placementMode {
        case .followPointer:
            let pointerY = pointer?.y ?? visibleFrame.midY
            panelY = pointerY - size.height + EdgeTriggeredPlacementMetrics.firstRowCenterOffsetFromTop
        case .centered:
            panelY = minY + (maxY - minY) / 2
        case .custom:
            let clampedPosition = min(1, max(0, customVerticalPosition))
            panelY = maxY - (maxY - minY) * CGFloat(clampedPosition)
        }

        let clampedPanelY = min(max(panelY, minY), maxY)
        let indicatorX: CGFloat
        let panelX: CGFloat
        switch side {
        case .right:
            indicatorX = screen.frame.maxX -
                EdgeTriggeredPlacementMetrics.activationIndicatorHorizontalInset -
                EdgeTriggeredPlacementMetrics.activationIndicatorWidth
            panelX = visibleFrame.maxX - size.width
        case .left:
            indicatorX = screen.frame.minX + EdgeTriggeredPlacementMetrics.activationIndicatorHorizontalInset
            panelX = visibleFrame.minX
        }
        let guideFrame = NSRect(
            x: indicatorX,
            y: minY,
            width: EdgeTriggeredPlacementMetrics.activationIndicatorWidth,
            height: maxY - minY + size.height
        )
        let panelFrame = NSRect(
            x: panelX,
            y: clampedPanelY,
            width: size.width,
            height: size.height
        )

        let firstRowTopInset = max(
            0,
            EdgeTriggeredPlacementMetrics.firstRowCenterOffsetFromTop - EdgeTriggeredPlacementMetrics.firstRowHeight / 2
        )
        let weakBandFrame = NSRect(
            x: indicatorX,
            y: panelFrame.maxY - firstRowTopInset,
            width: EdgeTriggeredPlacementMetrics.activationIndicatorWidth,
            height: firstRowTopInset
        )
        let strongBandFrame = NSRect(
            x: indicatorX,
            y: panelFrame.minY,
            width: EdgeTriggeredPlacementMetrics.activationIndicatorWidth,
            height: max(0, panelFrame.height - firstRowTopInset)
        )
        let cornerSafeRange = protectedActivationVerticalRange(on: screen)
        let clippedWeakBandFrame = clippedActivationBand(weakBandFrame, to: cornerSafeRange)
        let clippedStrongBandFrame = clippedActivationBand(strongBandFrame, to: cornerSafeRange)
        let activationRange = clampedActivationVerticalRange(
            for: panelFrame,
            safeRange: cornerSafeRange
        )

        return EdgeActivationLayout(
            screen: screen,
            guideFrame: guideFrame,
            panelFrame: panelFrame,
            weakBandFrame: clippedWeakBandFrame,
            strongBandFrame: clippedStrongBandFrame,
            activationVerticalRange: activationRange
        )
    }

    private static func protectedActivationVerticalRange(on screen: NSScreen) -> ClosedRange<CGFloat> {
        let inset = min(
            EdgeTriggeredPlacementMetrics.cornerProtectionLength,
            max(0, screen.frame.height / 2)
        )
        let lowerBound = screen.frame.minY + inset
        let upperBound = screen.frame.maxY - inset
        guard lowerBound <= upperBound else {
            return screen.frame.midY...screen.frame.midY
        }
        return lowerBound...upperBound
    }

    private static func clampedActivationVerticalRange(
        for panelFrame: NSRect,
        safeRange: ClosedRange<CGFloat>
    ) -> ClosedRange<CGFloat> {
        let lowerBound = min(
            max(panelFrame.minY, safeRange.lowerBound),
            safeRange.upperBound
        )
        let upperBound = max(
            min(panelFrame.maxY, safeRange.upperBound),
            safeRange.lowerBound
        )
        if lowerBound <= upperBound {
            return lowerBound...upperBound
        }
        return lowerBound...lowerBound
    }

    private static func clippedActivationBand(
        _ rect: NSRect,
        to safeRange: ClosedRange<CGFloat>
    ) -> NSRect {
        guard !rect.isEmpty else { return .zero }

        let clippedMinY = max(rect.minY, safeRange.lowerBound)
        let clippedMaxY = min(rect.maxY, safeRange.upperBound)
        guard clippedMinY < clippedMaxY else { return .zero }

        return NSRect(
            x: rect.minX,
            y: clippedMinY,
            width: rect.width,
            height: clippedMaxY - clippedMinY
        )
    }

    func contains(point: CGPoint) -> Bool {
        guard let panel else { return false }
        return panel.frame.contains(point)
    }

    func panelLocalPoint(fromScreen point: CGPoint) -> CGPoint? {
        guard let panel, let contentView = panel.contentView else { return nil }

        let windowPoint = panel.convertPoint(fromScreen: point)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        guard contentView.bounds.contains(contentPoint) else { return nil }
        let topInset = max(0, contentView.safeAreaInsets.top)

        if contentView.isFlipped {
            return CGPoint(
                x: contentPoint.x,
                y: max(0, contentPoint.y - topInset)
            )
        }

        return CGPoint(
            x: contentPoint.x,
            y: max(0, contentView.bounds.height - contentPoint.y - topInset)
        )
    }

    private func makePanel() -> NSPanel {
        let panel = EdgeClipPanel(
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 700),
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.delegate = self

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

    private func position(
        panel: NSPanel,
        mode: PresentationMode,
        size: NSSize,
        pointer: CGPoint,
        statusItemAnchorRect: CGRect? = nil
    ) {
        switch mode {
        case .edgeTriggered:
            let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
            guard let screen else { return }
            let layout = Self.edgeTriggeredLayout(
                on: screen,
                size: size,
                pointer: pointer,
                side: edgeActivationSide,
                placementMode: edgeActivationPlacementMode,
                customVerticalPosition: edgeActivationCustomVerticalPosition
            )
            panel.setFrame(layout.panelFrame, display: true, animate: false)
        case .manual:
            guard let screen = NSScreen.main else { return }
            let y = screen.visibleFrame.midY - size.height / 2
            let x = screen.visibleFrame.maxX - size.width
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: true)
        case .hotkey:
            let frame: NSRect
            if hotkeyPanelPlacementMode == .lastClosedPosition,
               let storedOrigin = hotkeyPanelLastFrameOrigin {
                let screen = screenContaining(frame: NSRect(origin: storedOrigin, size: size)) ?? NSScreen.main
                guard let screen else { return }
                frame = clampedFloatingFrame(
                    origin: storedOrigin,
                    size: size,
                    on: screen
                )
            } else {
                let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
                guard let screen else { return }
                let targetX = pointer.x - hotkeyFirstRowCenterOffsetFromLeft
                let targetY = pointer.y - size.height + hotkeyFirstRowCenterOffsetFromTop
                frame = clampedFloatingFrame(
                    origin: CGPoint(x: targetX, y: targetY),
                    size: size,
                    on: screen
                )
            }
            // Hotkey-triggered presentation should feel immediate after the second tap.
            // Keeping AppKit window animation here makes the panel appear late.
            panel.setFrame(frame, display: true, animate: false)
        case .rightDrag:
            let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
            guard let screen else { return }
            let targetX = pointer.x - rightDragPointerOffsetFromLeft
            let targetY = pointer.y - size.height + rightDragFirstRowCenterOffsetFromTop
            panel.setFrame(
                clampedFloatingFrame(
                    origin: CGPoint(x: targetX, y: targetY),
                    size: size,
                    on: screen
                ),
                display: true,
                animate: false
            )
        case .menuBar:
            guard let statusItemAnchorRect else { return }
            let anchorPoint = CGPoint(x: statusItemAnchorRect.midX, y: statusItemAnchorRect.midY)
            let screen = NSScreen.screens.first { $0.frame.contains(anchorPoint) } ?? NSScreen.main
            guard let screen else { return }

            let targetX = statusItemAnchorRect.midX - size.width / 2
            let x = min(
                max(screen.visibleFrame.minX + menuBarPanelHorizontalPadding, targetX),
                screen.visibleFrame.maxX - size.width - menuBarPanelHorizontalPadding
            )
            let targetY = statusItemAnchorRect.minY - size.height - menuBarPanelTopSpacing
            let y = min(
                max(screen.visibleFrame.minY + menuBarPanelBottomPadding, targetY),
                screen.visibleFrame.maxY - size.height - menuBarPanelTopSpacing
            )
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: false)
        }
    }

    private func startAutoCollapseIfNeeded(panel: NSPanel) {
        stopAutoCollapseMonitoring()

        autoCollapseTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                let pointer = NSEvent.mouseLocation
                if shouldCollapse(panel: panel, pointer: pointer) {
                    hide()
                }
            }
        }
    }

    private func stopAutoCollapseMonitoring() {
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
    }

    private func shouldCollapse(panel: NSPanel, pointer: CGPoint) -> Bool {
        if isPinnedProvider() {
            return false
        }

        if additionalActiveRegionProvider(pointer) {
            return false
        }

        if panel.frame.contains(pointer) {
            hasPointerEnteredPanel = true
            requiresPointerReentryBeforeCollapse = false
            return false
        }

        let extendedHoverRegion = panel.frame.insetBy(dx: -hoverSafetyPadding, dy: -hoverSafetyPadding)
        if extendedHoverRegion.contains(pointer) {
            hasPointerEnteredPanel = true
            requiresPointerReentryBeforeCollapse = false
            return false
        }

        if requiresPointerReentryBeforeCollapse {
            return false
        }

        if presentationMode == .manual, !hasPointerEnteredPanel {
            // Manual opening from main window should not disappear immediately.
            return false
        }

        guard let screen = screenContaining(pointer: pointer) else {
            return true
        }

        switch presentationMode {
        case .edgeTriggered:
            guard isPanelDockedToConfiguredEdge(panel, on: screen) else {
                // If the user dragged the panel away from edge, do not auto-collapse.
                return false
            }
            let edgeThreshold: CGFloat = 2
            guard isPointerOnConfiguredEdge(pointer, on: screen, threshold: edgeThreshold) else {
                return true
            }

            let layout = Self.edgeTriggeredLayout(
                on: screen,
                size: panel.frame.size,
                pointer: pointer,
                side: edgeActivationSide,
                placementMode: edgeActivationPlacementMode,
                customVerticalPosition: edgeActivationCustomVerticalPosition
            )
            return !layout.activationVerticalRange.contains(pointer.y)
        case .manual:
            return false
        case .hotkey:
            // Hotkey mode should stay visible while user continues keyboard selection.
            return false
        case .rightDrag:
            return false
        case .menuBar:
            return false
        }
    }

    func rightDragRowIndex(at point: CGPoint, rowHeight: CGFloat) -> Int? {
        guard let panel else { return nil }

        let expandedSelectionFrame = panel.frame.insetBy(dx: -rightDragSelectionHorizontalPadding, dy: 0)
        guard expandedSelectionFrame.contains(point) else { return nil }

        let firstRowTopOffset = rightDragFirstRowCenterOffsetFromTop - rowHeight / 2
        let clampedY = min(max(point.y, panel.frame.minY + 1), panel.frame.maxY - 1)
        let distanceFromTop = panel.frame.maxY - clampedY
        let rowIndex = Int(floor((distanceFromTop - firstRowTopOffset) / rowHeight))
        guard rowIndex >= 0 else { return nil }
        return rowIndex
    }

    func rightDragRowIndex(
        at point: CGPoint,
        rowHeight: CGFloat,
        scrollOffset: CGFloat
    ) -> Int? {
        guard let panel else { return nil }

        let expandedSelectionFrame = panel.frame.insetBy(dx: -rightDragSelectionHorizontalPadding, dy: 0)
        guard expandedSelectionFrame.contains(point) else { return nil }

        let firstRowTopOffset = rightDragFirstRowCenterOffsetFromTop - rowHeight / 2
        let clampedY = min(max(point.y, panel.frame.minY + 1), panel.frame.maxY - 1)
        let distanceFromTop = panel.frame.maxY - clampedY + max(0, scrollOffset)
        let rowIndex = Int(floor((distanceFromTop - firstRowTopOffset) / rowHeight))
        guard rowIndex >= 0 else {
            return nil
        }
        return rowIndex
    }

    func rightDragRowIndex(documentY: CGFloat, rowHeight: CGFloat) -> Int? {
        let firstRowTopOffset = rightDragFirstRowCenterOffsetFromTop - rowHeight / 2
        let rowIndex = Int(floor((documentY - firstRowTopOffset) / rowHeight))
        guard rowIndex >= 0 else {
            return nil
        }
        return rowIndex
    }

    private func isPanelDockedToConfiguredEdge(_ panel: NSPanel, on screen: NSScreen) -> Bool {
        switch edgeActivationSide {
        case .right:
            return abs(panel.frame.maxX - screen.visibleFrame.maxX) <= 4
        case .left:
            return abs(panel.frame.minX - screen.visibleFrame.minX) <= 4
        }
    }

    private func isPointerOnConfiguredEdge(
        _ pointer: CGPoint,
        on screen: NSScreen,
        threshold: CGFloat
    ) -> Bool {
        switch edgeActivationSide {
        case .right:
            return pointer.x >= (screen.frame.maxX - threshold)
        case .left:
            return pointer.x <= (screen.frame.minX + threshold)
        }
    }

    private func clampedFloatingFrame(
        origin: CGPoint,
        size: NSSize,
        on screen: NSScreen,
        inset: CGFloat = 12
    ) -> NSRect {
        let x = min(
            max(screen.visibleFrame.minX + inset, origin.x),
            screen.visibleFrame.maxX - size.width - inset
        )
        let y = min(
            max(screen.visibleFrame.minY + inset, origin.y),
            screen.visibleFrame.maxY - size.height - inset
        )
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func screenContaining(pointer: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(pointer) }
    }

    private func screenContaining(frame: NSRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.visibleFrame.contains(center) } ??
            NSScreen.screens.first { $0.visibleFrame.intersects(frame) }
    }

    func windowDidMove(_ notification: Notification) {
        onFrameChanged?()
    }

    func windowDidResize(_ notification: Notification) {
        onFrameChanged?()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        onFrameChanged?()
    }
}

private final class EdgeClipPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class MouseGestureTrailOverlayController {
    private var panel: NSPanel?
    private var overlayView: MouseGestureTrailOverlayView?

    var isVisible: Bool { panel?.isVisible == true }

    func update(
        previewState: RightMouseDragGestureService.GesturePreviewState?,
        appearanceMode: AppearanceMode
    ) {
        guard let previewState,
              let referencePoint = previewState.points.last ?? previewState.points.first,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(referencePoint) }) ?? NSScreen.main
        else {
            hide()
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        applyAppearance(mode: appearanceMode, to: panel)

        let screenFrame = screen.frame
        if panel.frame != screenFrame {
            panel.setFrame(screenFrame, display: false)
        }

        let overlayView = overlayView ?? MouseGestureTrailOverlayView(frame: NSRect(origin: .zero, size: screenFrame.size))
        overlayView.frame = NSRect(origin: .zero, size: screenFrame.size)
        panel.contentView = overlayView
        self.overlayView = overlayView

        let localPoints = previewState.points.map {
            CGPoint(x: $0.x - screenFrame.minX, y: $0.y - screenFrame.minY)
        }
        overlayView.update(
            points: localPoints,
            directions: previewState.directions,
            matchedNote: previewState.matchedNote,
            isMatched: previewState.isMatched,
            suppressLabel: previewState.suppressLabel
        )

        if !panel.isVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderFront(nil)
        }
    }

    func hide() {
        overlayView?.reset()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false

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
}

@MainActor
final class RightEdgeActivationPreviewController {
    private var panel: NSPanel?
    private var overlayView: RightEdgeActivationPreviewView?

    var isVisible: Bool { panel?.isVisible == true }

    func update(
        layout: EdgePanelController.EdgeActivationLayout?,
        appearanceMode: AppearanceMode
    ) {
        guard let layout else {
            hide()
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        applyAppearance(mode: appearanceMode, to: panel)

        let screenFrame = layout.screen.frame
        if panel.frame != screenFrame {
            panel.setFrame(screenFrame, display: false)
        }

        let overlayView = overlayView ?? RightEdgeActivationPreviewView(frame: NSRect(origin: .zero, size: screenFrame.size))
        overlayView.frame = NSRect(origin: .zero, size: screenFrame.size)
        panel.contentView = overlayView
        self.overlayView = overlayView
        overlayView.update(layout: layout)

        if !panel.isVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderFront(nil)
        }
    }

    func hide() {
        overlayView?.reset()
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false

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
}

private final class MouseGestureTrailOverlayView: NSView {
    private var points: [CGPoint] = []
    private var directions: [MouseGestureDirection] = []
    private var matchedNote: String?
    private var isMatched = false
    private var suppressLabel = false

    override var isOpaque: Bool { false }

    func update(
        points: [CGPoint],
        directions: [MouseGestureDirection],
        matchedNote: String?,
        isMatched: Bool,
        suppressLabel: Bool
    ) {
        self.points = points
        self.directions = directions
        self.matchedNote = matchedNote
        self.isMatched = isMatched
        self.suppressLabel = suppressLabel
        needsDisplay = true
    }

    func reset() {
        points = []
        directions = []
        matchedNote = nil
        isMatched = false
        suppressLabel = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !points.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        if points.count > 1 {
            let outerPath = NSBezierPath()
            outerPath.lineCapStyle = .round
            outerPath.lineJoinStyle = .round
            outerPath.lineWidth = 10
            outerPath.move(to: points[0])
            for point in points.dropFirst() {
                outerPath.line(to: point)
            }
            NSColor.systemBlue.withAlphaComponent(0.24).setStroke()
            outerPath.stroke()

            let innerPath = NSBezierPath()
            innerPath.lineCapStyle = .round
            innerPath.lineJoinStyle = .round
            innerPath.lineWidth = 4
            innerPath.move(to: points[0])
            for point in points.dropFirst() {
                innerPath.line(to: point)
            }
            NSColor.systemBlue.withAlphaComponent(0.68).setStroke()
            innerPath.stroke()
        }

        if let originPoint = points.first {
            drawDot(at: originPoint, diameter: 12, fillColor: NSColor.white.withAlphaComponent(0.92))
            drawDot(at: originPoint, diameter: 7, fillColor: NSColor.systemBlue.withAlphaComponent(0.82))
        }

        if let currentPoint = points.last {
            drawDot(at: currentPoint, diameter: 20, fillColor: NSColor.systemBlue.withAlphaComponent(0.18))
            drawDot(at: currentPoint, diameter: 12, fillColor: NSColor.white.withAlphaComponent(0.94))
            drawDot(at: currentPoint, diameter: 7, fillColor: NSColor.systemBlue.withAlphaComponent(0.9))
            if let labelText {
                drawLabel(near: currentPoint, text: labelText)
            }
        }
    }

    private func drawDot(at point: CGPoint, diameter: CGFloat, fillColor: NSColor) {
        let rect = CGRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        fillColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }

    private var labelText: String? {
        if suppressLabel {
            return nil
        }

        if isMatched {
            return matchedNote
        }

        if directions.isEmpty {
            return "手势中"
        }

        return "手势: " + directions.map(\.title).joined(separator: " -> ")
    }

    private func drawLabel(near point: CGPoint, text: String) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let textSize = (text as NSString).size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 8
        let labelWidth = textSize.width + horizontalPadding * 2
        let labelHeight = textSize.height + verticalPadding * 2
        let preferredX = point.x + 18
        let preferredY = point.y + 22
        let clampedX = min(max(12, preferredX), max(12, bounds.width - labelWidth - 12))
        let clampedY = min(max(12, preferredY), max(12, bounds.height - labelHeight - 12))
        let labelRect = CGRect(x: clampedX, y: clampedY, width: labelWidth, height: labelHeight)

        NSColor(calibratedWhite: 0.08, alpha: 0.78).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 14, yRadius: 14).fill()

        NSColor.systemBlue.withAlphaComponent(isMatched ? 0.42 : 0.26).setStroke()
        let borderPath = NSBezierPath(roundedRect: labelRect, xRadius: 14, yRadius: 14)
        borderPath.lineWidth = 1
        borderPath.stroke()

        let textRect = CGRect(
            x: labelRect.minX + horizontalPadding,
            y: labelRect.minY + verticalPadding,
            width: textSize.width,
            height: textSize.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }
}

private final class RightEdgeActivationPreviewView: NSView {
    private var guideRect: NSRect = .zero
    private var weakBandRect: NSRect = .zero
    private var strongBandRect: NSRect = .zero

    override var isOpaque: Bool { false }

    func update(layout: EdgePanelController.EdgeActivationLayout) {
        let screenFrame = layout.screen.frame
        guideRect = layout.guideFrame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        weakBandRect = layout.weakBandFrame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        strongBandRect = layout.strongBandFrame.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        needsDisplay = true
    }

    func reset() {
        guideRect = .zero
        weakBandRect = .zero
        strongBandRect = .zero
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !guideRect.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        drawGuide(
            in: guideRect,
            fillColor: NSColor.controlAccentColor.withAlphaComponent(0.08),
            strokeColor: NSColor.controlAccentColor.withAlphaComponent(0.22)
        )

        if let activeBandRect = activeBandRect {
            drawGlow(
                in: activeBandRect.insetBy(dx: -4, dy: -4),
                color: NSColor.controlAccentColor.withAlphaComponent(0.18)
            )
        }

        if !weakBandRect.isEmpty {
            drawFill(
                in: weakBandRect,
                color: NSColor.controlAccentColor.withAlphaComponent(0.9)
            )
        }

        if !strongBandRect.isEmpty {
            drawFill(
                in: strongBandRect,
                color: NSColor.controlAccentColor.withAlphaComponent(0.9)
            )
        }

        if let activeBandRect = activeBandRect {
            drawInnerHighlight(in: activeBandRect)
        }
    }

    private var activeBandRect: NSRect? {
        if weakBandRect.isEmpty {
            return strongBandRect.isEmpty ? nil : strongBandRect
        }
        if strongBandRect.isEmpty {
            return weakBandRect
        }
        return weakBandRect.union(strongBandRect)
    }

    private func drawGuide(in rect: NSRect, fillColor: NSColor, strokeColor: NSColor) {
        let path = roundedPath(in: rect)
        fillColor.setFill()
        path.fill()

        strokeColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawGlow(in rect: NSRect, color: NSColor) {
        let path = roundedPath(in: rect)
        color.setFill()
        path.fill()
    }

    private func drawFill(in rect: NSRect, color: NSColor) {
        let path = roundedPath(in: rect)
        color.setFill()
        path.fill()
    }

    private func drawInnerHighlight(in rect: NSRect) {
        let highlightRect = rect.insetBy(dx: 1.5, dy: 5)
        guard highlightRect.width > 0, highlightRect.height > 0 else { return }
        let path = roundedPath(in: highlightRect)
        NSColor.white.withAlphaComponent(0.22).setFill()
        path.fill()
    }

    private func roundedPath(in rect: NSRect) -> NSBezierPath {
        let radius = min(rect.width, rect.height) / 2
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}
