import ApplicationServices
import AppKit
import Carbon
import Foundation

final class GlobalHotkeyService {
    private struct DoubleModifierBinding {
        let action: GlobalHotkeyAction
        let modifier: HotkeyModifier
        var lastCompletedTapDate: Date = .distantPast
        var isPressed = false
        var currentTapIsPure = true
    }

    enum RegistrationError: LocalizedError {
        case missingModifier
        case missingKey
        case installHandlerFailed(OSStatus)
        case registerHotKeyFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missingModifier:
                return "组合按键至少需要一个修饰键。"
            case .missingKey:
                return "组合按键缺少主按键。"
            case .installHandlerFailed(let status):
                return "安装组合按键监听失败（\(status)）。"
            case .registerHotKeyFailed(let status):
                if status == eventHotKeyExistsErr {
                    return "组合按键已被系统或其他应用占用。"
                }
                return "注册组合按键失败（\(status)）。"
            }
        }
    }

    var onAction: ((GlobalHotkeyAction) -> Void)?

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var localKeyDownMonitor: Any?

    private var doublePressInterval: TimeInterval = 0.36
    private var doubleModifierBindings: [GlobalHotkeyAction: DoubleModifierBinding] = [:]

    private var hotKeyRefs: [GlobalHotkeyAction: EventHotKeyRef] = [:]
    private var hotKeyHandlerRef: EventHandlerRef?

    private let hotKeySignature: OSType = 0x45434C50 // ECLP

    func updateRegistration(
        enabled: Bool,
        triggerMode: GlobalHotkeyTriggerMode,
        panelModifier: HotkeyModifier,
        favoritesModifier: HotkeyModifier?,
        interval: Double,
        panelShortcut: KeyboardShortcut,
        favoritesShortcut: KeyboardShortcut
    ) throws {
        doublePressInterval = max(0.20, min(interval, 0.80))
        resetDoubleModifierState()
        doubleModifierBindings.removeAll()

        unregisterHotKey()
        removeMonitors()

        guard enabled else { return }

        switch triggerMode {
        case .doubleModifier:
            doubleModifierBindings[.clipboardPanel] = DoubleModifierBinding(
                action: .clipboardPanel,
                modifier: panelModifier
            )
            if let favoritesModifier, favoritesModifier != panelModifier {
                doubleModifierBindings[.favoritesTab] = DoubleModifierBinding(
                    action: .favoritesTab,
                    modifier: favoritesModifier
                )
            }
            installDoubleModifierMonitorsIfNeeded()
        case .keyCombination:
            do {
                try registerHotKey(panelShortcut, action: .clipboardPanel)
                if favoritesShortcut.isConfigured {
                    try registerHotKey(favoritesShortcut, action: .favoritesTab)
                }
            } catch {
                unregisterHotKey()
                throw error
            }
        }
    }

    deinit {
        removeMonitors()
        unregisterHotKey()
    }

    private func installDoubleModifierMonitorsIfNeeded() {
        if globalFlagsMonitor == nil {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
            }
        }

        if localFlagsMonitor == nil {
            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
                return event
            }
        }

        if globalKeyDownMonitor == nil {
            globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event)
            }
        }

        if localKeyDownMonitor == nil {
            localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyDown(event)
                return event
            }
        }
    }

    private func removeMonitors() {
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }

        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }

        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
            self.globalKeyDownMonitor = nil
        }

        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }

        resetDoubleModifierState()
    }

    private func unregisterHotKey() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()

        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
    }

    private func registerHotKey(_ shortcut: KeyboardShortcut, action: GlobalHotkeyAction) throws {
        guard shortcut.hasAnyModifier else {
            throw RegistrationError.missingModifier
        }
        guard let keyCode = shortcut.keyCode else {
            throw RegistrationError.missingKey
        }

        try installHotKeyHandlerIfNeeded()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: action.registrationID)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifierFlags(for: shortcut),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            throw RegistrationError.registerHotKeyFailed(status)
        }
        if let hotKeyRef {
            hotKeyRefs[action] = hotKeyRef
        }
    }

    private func installHotKeyHandlerIfNeeded() throws {
        guard hotKeyHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotkeyCarbonEventHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyHandlerRef
        )

        guard status == noErr else {
            hotKeyHandlerRef = nil
            throw RegistrationError.installHandlerFailed(status)
        }
    }

    private func carbonModifierFlags(for shortcut: KeyboardShortcut) -> UInt32 {
        var flags: UInt32 = 0
        if shortcut.usesCommand { flags |= UInt32(cmdKey) }
        if shortcut.usesOption { flags |= UInt32(optionKey) }
        if shortcut.usesControl { flags |= UInt32(controlKey) }
        if shortcut.usesShift { flags |= UInt32(shiftKey) }
        return flags
    }

    private func resetDoubleModifierState() {
        for action in Array(doubleModifierBindings.keys) {
            updateDoubleModifierBinding(action) { binding in
                binding.isPressed = false
                binding.currentTapIsPure = true
                binding.lastCompletedTapDate = .distantPast
            }
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let activeModifiers = flags.intersection([.command, .control, .option, .shift])

        let matchedActions = doubleModifierBindings.compactMap { action, binding in
            binding.modifier.keyCodes.contains(event.keyCode) ? action : nil
        }

        guard !matchedActions.isEmpty else {
            for action in Array(doubleModifierBindings.keys) {
                updateDoubleModifierBinding(action) { binding in
                    if binding.isPressed {
                        binding.currentTapIsPure = false
                    } else if !activeModifiers.isEmpty {
                        binding.lastCompletedTapDate = .distantPast
                    }
                }
            }
            return
        }

        for action in matchedActions {
            guard let binding = doubleModifierBindings[action] else { continue }

            for otherAction in Array(doubleModifierBindings.keys) where otherAction != action {
                updateDoubleModifierBinding(otherAction) { otherBinding in
                    if otherBinding.isPressed {
                        otherBinding.currentTapIsPure = false
                    }
                }
            }

            let targetFlag = binding.modifier.modifierFlag
            let targetPressed = flags.contains(targetFlag)
            var otherModifiers = activeModifiers
            otherModifiers.remove(targetFlag)

            if targetPressed {
                updateDoubleModifierBinding(action) { currentBinding in
                    if !currentBinding.isPressed {
                        currentBinding.isPressed = true
                        currentBinding.currentTapIsPure = otherModifiers.isEmpty
                    } else if !otherModifiers.isEmpty {
                        currentBinding.currentTapIsPure = false
                    }
                }
                continue
            }

            guard binding.isPressed else { continue }

            let shouldTrigger = binding.currentTapIsPure && otherModifiers.isEmpty
            let previousTapDate = binding.lastCompletedTapDate
            updateDoubleModifierBinding(action) { currentBinding in
                currentBinding.isPressed = false
            }

            guard shouldTrigger else {
                updateDoubleModifierBinding(action) { currentBinding in
                    currentBinding.currentTapIsPure = true
                    currentBinding.lastCompletedTapDate = .distantPast
                }
                continue
            }

            let now = Date()
            if now.timeIntervalSince(previousTapDate) <= doublePressInterval {
                resetDoubleModifierState()
                onAction?(action)
            } else {
                updateDoubleModifierBinding(action) { currentBinding in
                    currentBinding.lastCompletedTapDate = now
                    currentBinding.currentTapIsPure = true
                }
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if isModifierKeyCode(event.keyCode) {
            return
        }

        for action in Array(doubleModifierBindings.keys) {
            updateDoubleModifierBinding(action) { binding in
                if binding.isPressed {
                    binding.currentTapIsPure = false
                }
                if binding.lastCompletedTapDate != .distantPast {
                    binding.lastCompletedTapDate = .distantPast
                }
            }
        }
    }

    private func updateDoubleModifierBinding(
        _ action: GlobalHotkeyAction,
        _ mutate: (inout DoubleModifierBinding) -> Void
    ) {
        guard var binding = doubleModifierBindings[action] else { return }
        mutate(&binding)
        doubleModifierBindings[action] = binding
    }

    private func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 58, 61, 59, 62, 56, 60, 57, 63:
            return true
        default:
            return false
        }
    }

    fileprivate func handleRegisteredHotKey(event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        guard hotKeyID.signature == hotKeySignature,
              let action = GlobalHotkeyAction.allCases.first(where: { $0.registrationID == hotKeyID.id }) else {
            return OSStatus(eventNotHandledErr)
        }

        onAction?(action)
        return noErr
    }
}

private func globalHotkeyCarbonEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let service = Unmanaged<GlobalHotkeyService>
        .fromOpaque(userData)
        .takeUnretainedValue()
    return service.handleRegisteredHotKey(event: event)
}

final class PanelPreviewHotkeyBridgeService {
    enum Action {
        case togglePreview
        case closePreview
        case showPrevious
        case showNext
    }

    var shouldBypassEvents: (() -> Bool)?
    var onAction: ((Action) -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func updateBridgeActive(_ isActive: Bool) -> Bool {
        if isActive {
            return startBridgeIfNeeded()
        }

        stopBridge()
        return true
    }

    func stopBridge() {
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
        stopBridge()
    }

    private func startBridgeIfNeeded() -> Bool {
        if eventTap != nil {
            return true
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: panelPreviewHotkeyBridgeEventTapCallback,
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

    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        if shouldBypassEvents?() == true {
            return Unmanaged.passUnretained(event)
        }

        let blockedFlags: CGEventFlags = [
            .maskCommand,
            .maskControl,
            .maskAlternate,
            .maskShift,
            .maskAlphaShift,
            .maskSecondaryFn
        ]
        guard event.flags.intersection(blockedFlags).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        let action: Action?
        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case 49:
            action = .togglePreview
        case 53:
            action = .closePreview
        case 123:
            action = .showPrevious
        case 124:
            action = .showNext
        default:
            action = nil
        }

        guard let action else {
            return Unmanaged.passUnretained(event)
        }

        let handled = onAction?(action) ?? false
        return handled ? nil : Unmanaged.passUnretained(event)
    }
}

private func panelPreviewHotkeyBridgeEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<PanelPreviewHotkeyBridgeService>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return service.handleEvent(type: type, event: event)
}
