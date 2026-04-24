import ApplicationServices
import CoreGraphics
import Foundation

final class RightMouseDragGestureService {
    struct AuxiliaryGestureConfiguration: Equatable {
        var id: UUID
        var pattern: RightMouseAuxiliaryGesturePattern
        var note: String
    }

    struct GesturePreviewState: Equatable {
        var points: [CGPoint]
        var directions: [MouseGestureDirection]
        var matchedNote: String?
        var isMatched: Bool
        var suppressLabel: Bool
    }

    var shouldBeginGesture: (() -> Bool)?
    var onGestureStarted: ((CGPoint) -> Void)?
    var onGestureMoved: ((CGPoint) -> Void)?
    var onGestureEnded: (() -> Void)?
    var onScroll: ((CGFloat, CGPoint) -> Void)?
    var onAuxiliaryGestureTriggered: ((UUID) -> Void)?
    var onGesturePreviewChanged: ((GesturePreviewState?) -> Void)?

    private struct GestureSegment {
        let direction: MouseGestureDirection
        var distance: CGFloat
    }

    private struct TrackingSession {
        let origin: CGPoint
        let syntheticClickLocation: CGPoint
        var latestLocation: CGPoint
        var hasTriggeredGesture: Bool
        var mainGestureFailed: Bool
        var lastSamplePoint: CGPoint
        var currentDirection: MouseGestureDirection?
        var currentDirectionDistance: CGFloat
        var committedSegments: [GestureSegment]
        var pathPoints: [CGPoint]
        var matchedAuxiliaryGesture: AuxiliaryGestureConfiguration?
        var hasMatchedAuxiliaryGestureDuringSession: Bool
    }

    private let syntheticEventTag: Int64 = 0x45444745434C4950
    private let preTriggerVerticalTolerance: CGFloat = 24
    private let sampleStepDistance: CGFloat = 6
    private let directionDominanceRatio: CGFloat = 1.35
    private let minimumCommittedSegmentDistance: CGFloat = 20
    private let auxiliarySingleSegmentDistance: CGFloat = 32
    private let auxiliaryFirstSegmentDistance: CGFloat = 32
    private let auxiliarySecondSegmentDistance: CGFloat = 20

    private var horizontalTriggerDistance: CGFloat = 72
    private var auxiliaryGestureConfigurations: [AuxiliaryGestureConfiguration] = []
    private var trackingSession: TrackingSession?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start(
        horizontalTriggerDistance: CGFloat,
        auxiliaryGestureConfigurations: [AuxiliaryGestureConfiguration]
    ) -> Bool {
        self.horizontalTriggerDistance = max(24, horizontalTriggerDistance)
        self.auxiliaryGestureConfigurations = auxiliaryGestureConfigurations
        if !shouldShowGesturePreview {
            dispatchGesturePreview(nil)
        } else if let trackingSession {
            updateGesturePreview(with: trackingSession)
        }

        if eventTap != nil {
            return true
        }

        let eventMask = mask(for: [.rightMouseDown, .rightMouseDragged, .rightMouseUp, .scrollWheel])
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: rightMouseDragEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        return true
    }

    func stop() {
        trackingSession = nil
        dispatchGesturePreview(nil)

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    deinit {
        stop()
    }

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventTag {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .rightMouseDown:
            guard shouldBeginGesture?() ?? true else {
                return Unmanaged.passUnretained(event)
            }

            let location = event.unflippedLocation
            trackingSession = TrackingSession(
                origin: location,
                syntheticClickLocation: event.location,
                latestLocation: location,
                hasTriggeredGesture: false,
                mainGestureFailed: false,
                lastSamplePoint: location,
                currentDirection: nil,
                currentDirectionDistance: 0,
                committedSegments: [],
                pathPoints: [location],
                matchedAuxiliaryGesture: nil,
                hasMatchedAuxiliaryGestureDuringSession: false
            )
            dispatchGesturePreview(nil)
            return nil

        case .rightMouseDragged:
            guard var trackingSession else {
                return Unmanaged.passUnretained(event)
            }

            let location = event.unflippedLocation
            trackingSession.latestLocation = location
            appendMovement(to: &trackingSession, location: location)
            refreshMatchedAuxiliaryGesture(in: &trackingSession)

            if !trackingSession.hasTriggeredGesture {
                let deltaX = location.x - trackingSession.origin.x
                let deltaY = location.y - trackingSession.origin.y

                if trackingSession.hasMatchedAuxiliaryGestureDuringSession {
                    self.trackingSession = trackingSession
                    updateGesturePreview(with: trackingSession)
                    return nil
                }

                if trackingSession.mainGestureFailed {
                    self.trackingSession = trackingSession
                    updateGesturePreview(with: trackingSession)
                    return nil
                }

                if abs(deltaY) > preTriggerVerticalTolerance && deltaX < horizontalTriggerDistance {
                    trackingSession.mainGestureFailed = true
                    self.trackingSession = trackingSession
                    updateGesturePreview(with: trackingSession)
                    return nil
                }

                if hasNonRightCommittedSegment(in: trackingSession) {
                    trackingSession.mainGestureFailed = true
                    self.trackingSession = trackingSession
                    updateGesturePreview(with: trackingSession)
                    return nil
                }

                if deltaX >= horizontalTriggerDistance {
                    trackingSession.hasTriggeredGesture = true
                    self.trackingSession = trackingSession
                    dispatchGesturePreview(nil)
                    onGestureStarted?(location)
                    onGestureMoved?(location)
                    return nil
                }
            } else {
                self.trackingSession = trackingSession
                dispatchGesturePreview(nil)
                onGestureMoved?(location)
                return nil
            }

            self.trackingSession = trackingSession
            updateGesturePreview(with: trackingSession)
            return nil

        case .rightMouseUp:
            guard let trackingSession else {
                return Unmanaged.passUnretained(event)
            }

            self.trackingSession = nil
            dispatchGesturePreview(nil)

            if trackingSession.hasTriggeredGesture {
                onGestureEnded?()
                return nil
            }

            if let matchedGestureID = trackingSession.matchedAuxiliaryGesture?.id ?? matchedAuxiliaryGesture(in: trackingSession)?.id {
                DispatchQueue.main.async { [onAuxiliaryGestureTriggered] in
                    onAuxiliaryGestureTriggered?(matchedGestureID)
                }
                return nil
            }

            if trackingSession.hasMatchedAuxiliaryGestureDuringSession {
                return nil
            }

            postSyntheticRightClick(at: trackingSession.syntheticClickLocation)
            return nil

        case .scrollWheel:
            guard let trackingSession, trackingSession.hasTriggeredGesture else {
                return Unmanaged.passUnretained(event)
            }

            let deltaY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            if deltaY != 0 {
                onScroll?(CGFloat(deltaY), event.unflippedLocation)
            }
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func postSyntheticRightClick(at location: CGPoint) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        guard
            let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .rightMouseDown,
                mouseCursorPosition: location,
                mouseButton: .right
            ),
            let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: .rightMouseUp,
                mouseCursorPosition: location,
                mouseButton: .right
            )
        else {
            return
        }

        mouseDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        mouseUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
    }

    private func mask(for eventTypes: [CGEventType]) -> CGEventMask {
        eventTypes.reduce(into: 0) { partialResult, eventType in
            partialResult |= (1 << CGEventMask(eventType.rawValue))
        }
    }

    private func appendMovement(to trackingSession: inout TrackingSession, location: CGPoint) {
        let dx = location.x - trackingSession.lastSamplePoint.x
        let dy = location.y - trackingSession.lastSamplePoint.y
        let distance = hypot(dx, dy)
        guard distance >= sampleStepDistance else { return }

        trackingSession.lastSamplePoint = location
        trackingSession.pathPoints.append(location)

        guard let direction = quantizeDirection(dx: dx, dy: dy) else { return }

        if trackingSession.currentDirection == direction {
            trackingSession.currentDirectionDistance += distance
            return
        }

        commitCurrentSegment(into: &trackingSession)
        trackingSession.currentDirection = direction
        trackingSession.currentDirectionDistance = distance
    }

    private func quantizeDirection(dx: CGFloat, dy: CGFloat) -> MouseGestureDirection? {
        let absX = abs(dx)
        let absY = abs(dy)

        if absX >= absY * directionDominanceRatio {
            return dx >= 0 ? .right : .left
        }

        if absY >= absX * directionDominanceRatio {
            return dy >= 0 ? .up : .down
        }

        return nil
    }

    private func commitCurrentSegment(into trackingSession: inout TrackingSession) {
        guard let direction = trackingSession.currentDirection else { return }
        let distance = trackingSession.currentDirectionDistance
        guard distance >= minimumCommittedSegmentDistance else {
            trackingSession.currentDirection = nil
            trackingSession.currentDirectionDistance = 0
            return
        }

        if let lastIndex = trackingSession.committedSegments.indices.last,
           trackingSession.committedSegments[lastIndex].direction == direction {
            trackingSession.committedSegments[lastIndex].distance += distance
        } else {
            trackingSession.committedSegments.append(
                GestureSegment(direction: direction, distance: distance)
            )
        }

        trackingSession.currentDirection = nil
        trackingSession.currentDirectionDistance = 0
    }

    private func finalizedSegments(from trackingSession: TrackingSession) -> [GestureSegment] {
        var finalized = trackingSession
        commitCurrentSegment(into: &finalized)
        return finalized.committedSegments
    }

    private func hasNonRightCommittedSegment(in trackingSession: TrackingSession) -> Bool {
        let segments = finalizedSegments(from: trackingSession)
        return segments.contains { $0.direction != .right }
    }

    private func matchedAuxiliaryGesture(in trackingSession: TrackingSession) -> AuxiliaryGestureConfiguration? {
        let segments = finalizedSegments(from: trackingSession)
        guard !segments.isEmpty else { return nil }

        return auxiliaryGestureConfigurations.first { configuration in
            let directions = configuration.pattern.directions
            guard !directions.isEmpty else { return false }
            guard segments.count >= directions.count else { return false }

            for (index, direction) in directions.enumerated() {
                guard segments[index].direction == direction else { return false }

                let requiredDistance = index == 0
                    ? (directions.count == 1 ? auxiliarySingleSegmentDistance : auxiliaryFirstSegmentDistance)
                    : auxiliarySecondSegmentDistance
                guard segments[index].distance >= requiredDistance else { return false }
            }

            if segments.count > directions.count {
                let trailingDistance = segments.dropFirst(directions.count).reduce(CGFloat.zero) { $0 + $1.distance }
                if trailingDistance > minimumCommittedSegmentDistance {
                    return false
                }
            }

            return true
        }
    }

    private var shouldShowGesturePreview: Bool {
        auxiliaryGestureConfigurations.contains { !$0.pattern.directions.isEmpty }
    }

    private func updateGesturePreview(with trackingSession: TrackingSession) {
        guard shouldShowGesturePreview else {
            dispatchGesturePreview(nil)
            return
        }

        guard trackingSession.pathPoints.count > 1 else {
            dispatchGesturePreview(nil)
            return
        }

        let previewState = GesturePreviewState(
            points: trackingSession.pathPoints,
            directions: previewDirections(from: trackingSession),
            matchedNote: trackingSession.matchedAuxiliaryGesture?.displayNote,
            isMatched: trackingSession.matchedAuxiliaryGesture != nil,
            suppressLabel: trackingSession.hasMatchedAuxiliaryGestureDuringSession && trackingSession.matchedAuxiliaryGesture == nil
        )
        dispatchGesturePreview(previewState)
    }

    private func previewDirections(from trackingSession: TrackingSession) -> [MouseGestureDirection] {
        if let matchedGesture = trackingSession.matchedAuxiliaryGesture {
            return matchedGesture.pattern.directions
        }

        if trackingSession.hasMatchedAuxiliaryGestureDuringSession {
            return []
        }

        var directions = trackingSession.committedSegments.map(\.direction)

        if let currentDirection = trackingSession.currentDirection,
           trackingSession.currentDirectionDistance >= sampleStepDistance,
           directions.last != currentDirection {
            directions.append(currentDirection)
        }

        return directions
    }

    private func refreshMatchedAuxiliaryGesture(in trackingSession: inout TrackingSession) {
        trackingSession.matchedAuxiliaryGesture = matchedAuxiliaryGesture(in: trackingSession)
        if trackingSession.matchedAuxiliaryGesture != nil {
            trackingSession.hasMatchedAuxiliaryGestureDuringSession = true
        }
    }

    private func dispatchGesturePreview(_ previewState: GesturePreviewState?) {
        DispatchQueue.main.async { [onGesturePreviewChanged] in
            onGesturePreviewChanged?(previewState)
        }
    }
}

private extension RightMouseDragGestureService.AuxiliaryGestureConfiguration {
    var displayNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private func rightMouseDragEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<RightMouseDragGestureService>.fromOpaque(userInfo).takeUnretainedValue()
    return service.handleEvent(type: type, event: event)
}
