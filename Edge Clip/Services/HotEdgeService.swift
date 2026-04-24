import AppKit
import Foundation

@MainActor
final class HotEdgeService {
    var onTriggered: (() -> Void)?

    private var timer: Timer?
    private var activationDelay: TimeInterval = 0.2
    private var threshold: CGFloat = 2
    private var side: EdgeActivationSide = .right
    private var activationVerticalRangeProvider: ((NSScreen, CGPoint) -> ClosedRange<CGFloat>?)?
    private var isArmed = true
    private var edgeEnteredAt: Date?
    private var lastMouseDownAt: Date?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var localMotionMonitor: Any?
    private var globalMotionMonitor: Any?

    func start(
        side: EdgeActivationSide,
        threshold: CGFloat,
        activationDelay: TimeInterval,
        activationVerticalRangeProvider: ((NSScreen, CGPoint) -> ClosedRange<CGFloat>?)? = nil
    ) {
        stop()
        self.side = side
        self.threshold = max(0, threshold)
        self.activationDelay = max(0, activationDelay)
        self.activationVerticalRangeProvider = activationVerticalRangeProvider
        isArmed = true
        edgeEnteredAt = nil
        lastMouseDownAt = nil
        installClickMonitors()
        installMotionMonitors()

        // Timer is kept as a fallback so delayed activation still fires even
        // when the pointer is stationary on the edge.
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollMouseLocation()
            }
        }

        // Evaluate once immediately so entering with pointer already on edge triggers without waiting for first tick.
        pollMouseLocation()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activationVerticalRangeProvider = nil
        edgeEnteredAt = nil
        lastMouseDownAt = nil
        removeClickMonitors()
        removeMotionMonitors()
    }

    private func pollMouseLocation() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else {
            return
        }
        evaluate(pointer: pointer, on: screen)
    }

    private func evaluate(pointer: CGPoint, on screen: NSScreen) {
        let onSelectedEdge = isPointer(pointer, on: side, within: threshold, of: screen)
        let fullHeightRange = screen.frame.minY...screen.frame.maxY
        let activeRange = activationVerticalRangeProvider?(screen, pointer) ?? fullHeightRange
        let insideVerticalRange = activeRange.contains(pointer.y)

        if onSelectedEdge, insideVerticalRange {
            if isAnyMouseButtonDown() {
                cancelPendingEdgeActivation()
                return
            }

            if let edgeEnteredAt, let lastMouseDownAt, lastMouseDownAt >= edgeEnteredAt {
                cancelPendingEdgeActivation()
                return
            }

            if activationDelay == 0 {
                guard isArmed else { return }
                isArmed = false
                edgeEnteredAt = nil
                onTriggered?()
                return
            }

            if edgeEnteredAt == nil {
                edgeEnteredAt = Date()
            }

            let elapsed = Date().timeIntervalSince(edgeEnteredAt ?? Date())
            if isArmed, elapsed >= activationDelay {
                isArmed = false
                edgeEnteredAt = nil
                onTriggered?()
            }
        } else {
            isArmed = true
            edgeEnteredAt = nil
        }
    }

    private func installClickMonitors() {
        removeClickMonitors()

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.recordMouseDown()
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.recordMouseDown()
        }
    }

    private func removeClickMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func installMotionMonitors() {
        removeMotionMonitors()

        localMotionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] event in
            self?.pollMouseLocation()
            return event
        }

        globalMotionMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in
            self?.pollMouseLocation()
        }
    }

    private func removeMotionMonitors() {
        if let localMotionMonitor {
            NSEvent.removeMonitor(localMotionMonitor)
            self.localMotionMonitor = nil
        }
        if let globalMotionMonitor {
            NSEvent.removeMonitor(globalMotionMonitor)
            self.globalMotionMonitor = nil
        }
    }

    private func cancelPendingEdgeActivation() {
        edgeEnteredAt = nil

        // User clicked during the waiting period: require leaving edge before re-arming.
        if isPointerOnSelectedEdge() {
            isArmed = false
        } else {
            isArmed = true
        }
    }

    private func recordMouseDown() {
        lastMouseDownAt = Date()
        cancelPendingEdgeActivation()
    }

    private func isAnyMouseButtonDown() -> Bool {
        return NSEvent.pressedMouseButtons != 0
    }

    private func isPointerOnSelectedEdge() -> Bool {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else {
            return false
        }
        return isPointer(pointer, on: side, within: threshold, of: screen)
    }

    private func isPointer(
        _ pointer: CGPoint,
        on side: EdgeActivationSide,
        within threshold: CGFloat,
        of screen: NSScreen
    ) -> Bool {
        switch side {
        case .right:
            return pointer.x >= (screen.frame.maxX - threshold)
        case .left:
            return pointer.x <= (screen.frame.minX + threshold)
        }
    }
}
