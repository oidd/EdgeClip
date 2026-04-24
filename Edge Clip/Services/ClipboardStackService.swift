import ApplicationServices
import AppKit
import Foundation

final class ClipboardStackService {
    var shouldBypassHotkeys: (() -> Bool)?
    var onCopyCommand: ((Int) -> Void)?
    var onPasteCommand: (() -> Bool)?

    private let copyKeyCode: Int64 = 0x08
    private let pasteKeyCode: Int64 = 0x09
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

    func normalizeStackText(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard !ClipboardItem.exceedsStoredTextLimit(normalized) else { return nil }
        return normalized
    }

    func prependManualEntry(
        _ text: String,
        to entries: [ClipboardItem.StackEntry],
        orderMode: StackOrderMode
    ) -> [ClipboardItem.StackEntry] {
        makeEntries(from: [text], orderMode: orderMode, source: .manual) + entries
    }

    func makeEntries(
        from texts: [String],
        orderMode: StackOrderMode,
        source: ClipboardItem.StackEntry.Source
    ) -> [ClipboardItem.StackEntry] {
        let normalizedTexts = normalizeSegments(texts)
        guard !normalizedTexts.isEmpty else {
            return []
        }

        let orderedTexts: [String]
        switch orderMode {
        case .sequential:
            orderedTexts = normalizedTexts
        case .reverse:
            orderedTexts = normalizedTexts.reversed()
        }

        return orderedTexts.map {
            ClipboardItem.StackEntry(text: $0, source: source)
        }
    }

    func splitDraft(
        _ draft: String,
        delimiters: Set<StackDelimiterOption>,
        customDelimiter: String
    ) -> [String] {
        guard !draft.isEmpty else { return [] }

        var patterns: [String] = []
        if delimiters.contains(.newline) {
            patterns.append(#"\R+"#)
        }
        if delimiters.contains(.whitespace) {
            patterns.append(#"[ \t]+"#)
        }
        if delimiters.contains(.comma) {
            patterns.append(#"[，,]+"#)
        }
        if delimiters.contains(.period) {
            patterns.append(#"[。\.]+"#)
        }
        if delimiters.contains(.custom) {
            let trimmedCustom = customDelimiter.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedCustom.isEmpty {
                patterns.append(NSRegularExpression.escapedPattern(for: trimmedCustom))
            }
        }

        guard !patterns.isEmpty else {
            return normalizeSegments([draft])
        }

        let separatorPattern = patterns.joined(separator: "|")
        guard let regex = try? NSRegularExpression(pattern: separatorPattern) else {
            return normalizeSegments([draft])
        }

        let nsDraft = draft as NSString
        let fullRange = NSRange(location: 0, length: nsDraft.length)
        let matches = regex.matches(in: draft, options: [], range: fullRange)
        guard !matches.isEmpty else {
            return normalizeSegments([draft])
        }

        var segments: [String] = []
        var cursor = 0

        for match in matches {
            let segmentRange = NSRange(location: cursor, length: max(0, match.range.location - cursor))
            if segmentRange.length > 0 {
                segments.append(nsDraft.substring(with: segmentRange))
            } else {
                segments.append("")
            }
            cursor = match.range.location + match.range.length
        }

        let trailingLength = max(0, nsDraft.length - cursor)
        if trailingLength > 0 {
            segments.append(nsDraft.substring(with: NSRange(location: cursor, length: trailingLength)))
        } else if cursor == nsDraft.length {
            segments.append("")
        }

        return normalizeSegments(segments)
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
            callback: clipboardStackEventTapCallback,
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

        if shouldBypassHotkeys?() == true {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        guard flags.contains(.maskCommand) else {
            return Unmanaged.passUnretained(event)
        }
        let blockedFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskSecondaryFn]
        guard flags.intersection(blockedFlags).isEmpty else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == copyKeyCode {
            let baselineChangeCount = NSPasteboard.general.changeCount
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.onCopyCommand?(baselineChangeCount)
            }
            return Unmanaged.passUnretained(event)
        }

        if keyCode == pasteKeyCode {
            let shouldAllowPaste = onPasteCommand?() ?? false
            return shouldAllowPaste ? Unmanaged.passUnretained(event) : nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func normalizeSegments(_ segments: [String]) -> [String] {
        segments.compactMap(normalizeStackText(_:))
    }
}

private func clipboardStackEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<ClipboardStackService>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return service.handleEvent(type: type, event: event)
}
