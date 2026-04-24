import Foundation
import CoreGraphics
import AppKit

enum AppearanceMode: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system:
            return AppLocalization.localized("跟随系统")
        case .light:
            return AppLocalization.localized("浅色")
        case .dark:
            return AppLocalization.localized("深色")
        }
    }
}

enum HotkeyModifier: String, Codable, CaseIterable {
    case command
    case option
    case control
    case shift

    var title: String {
        switch self {
        case .command:
            return "Command"
        case .option:
            return "Option"
        case .control:
            return "Control"
        case .shift:
            return "Shift"
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .command:
            return .command
        case .option:
            return .option
        case .control:
            return .control
        case .shift:
            return .shift
        }
    }

    var keyCodes: Set<UInt16> {
        switch self {
        case .command:
            return [54, 55]
        case .option:
            return [58, 61]
        case .control:
            return [59, 62]
        case .shift:
            return [56, 60]
        }
    }
}

enum GlobalHotkeyTriggerMode: String, Codable, CaseIterable {
    case doubleModifier
    case keyCombination

    var title: String {
        switch self {
        case .doubleModifier:
            return AppLocalization.localized("双击修饰键")
        case .keyCombination:
            return AppLocalization.localized("组合按键")
        }
    }
}

enum GlobalHotkeyAction: String, Codable, CaseIterable {
    case clipboardPanel
    case favoritesTab

    var title: String {
        switch self {
        case .clipboardPanel:
            return AppLocalization.localized("剪贴面板")
        case .favoritesTab:
            return AppLocalization.localized("收藏标签")
        }
    }

    var registrationID: UInt32 {
        switch self {
        case .clipboardPanel:
            return 1
        case .favoritesTab:
            return 2
        }
    }
}

enum HotkeyPanelPlacementMode: String, Codable, CaseIterable {
    case followPointer
    case lastClosedPosition

    var title: String {
        switch self {
        case .followPointer:
            return AppLocalization.localized("跟随鼠标")
        case .lastClosedPosition:
            return AppLocalization.localized("上次关闭的位置")
        }
    }

    var detail: String {
        switch self {
        case .followPointer:
            return AppLocalization.localized("面板会尽量跟着当前鼠标位置出现，方便直接点到前几条记录。")
        case .lastClosedPosition:
            return AppLocalization.localized("面板会记住你上次关闭时的位置；拖动后再次用快捷键唤出，也会回到那里。")
        }
    }
}

struct PersistedPanelOrigin: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat

    init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct KeyboardShortcut: Codable, Equatable {
    var usesCommand: Bool = false
    var usesOption: Bool = false
    var usesControl: Bool = false
    var usesShift: Bool = false
    var key: String = ""

    static let defaultPanelTrigger = KeyboardShortcut(
        usesCommand: true,
        usesOption: false,
        usesControl: false,
        usesShift: true,
        key: "V"
    )

    private static let keyCodeMap: [String: UInt16] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05,
        "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C,
        "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10, "T": 0x11, "1": 0x12,
        "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E,
        "O": 0x1F, "U": 0x20, "[": 0x21, "I": 0x22, "P": 0x23, "ENTER": 0x24,
        "L": 0x25, "J": 0x26, "'": 0x27, "K": 0x28, ";": 0x29, "\\": 0x2A,
        ",": 0x2B, "/": 0x2C, "N": 0x2D, "M": 0x2E, ".": 0x2F, "TAB": 0x30,
        "SPACE": 0x31, "`": 0x32, "DELETE": 0x33, "ESC": 0x35
    ]

    private static let reverseKeyCodeMap: [UInt16: String] = {
        Dictionary(uniqueKeysWithValues: keyCodeMap.map { ($1, $0) })
    }()

    var normalizedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var hasAnyModifier: Bool {
        usesCommand || usesOption || usesControl || usesShift
    }

    var isEmpty: Bool {
        !hasAnyModifier && normalizedKey.isEmpty
    }

    var isConfigured: Bool {
        hasAnyModifier && keyCode != nil
    }

    var keyCode: UInt16? {
        Self.keyCode(for: key)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if usesCommand { flags.insert(.command) }
        if usesOption { flags.insert(.option) }
        if usesControl { flags.insert(.control) }
        if usesShift { flags.insert(.shift) }
        return flags
    }

    var displayText: String {
        let modifiers = [
            usesCommand ? "⌘" : nil,
            usesOption ? "⌥" : nil,
            usesControl ? "⌃" : nil,
            usesShift ? "⇧" : nil
        ]
        .compactMap { $0 }
        .joined()
        let key = normalizedKey
        return modifiers.isEmpty && key.isEmpty ? AppLocalization.localized("点击录制") : modifiers + key
    }

    var fullDisplayText: String {
        let modifiers = [
            usesCommand ? "Command" : nil,
            usesOption ? "Option" : nil,
            usesControl ? "Control" : nil,
            usesShift ? "Shift" : nil
        ]
        .compactMap { $0 }
        let key = normalizedKey

        if modifiers.isEmpty { return key }
        if key.isEmpty { return modifiers.joined(separator: "+") }
        return (modifiers + [key]).joined(separator: "+")
    }

    mutating func normalize() {
        key = normalizedKey
    }

    func conflicts(with other: KeyboardShortcut) -> Bool {
        guard !isEmpty, !other.isEmpty else { return false }
        return usesCommand == other.usesCommand &&
            usesOption == other.usesOption &&
            usesControl == other.usesControl &&
            usesShift == other.usesShift &&
            normalizedKey == other.normalizedKey
    }

    static func from(event: NSEvent) -> KeyboardShortcut? {
        guard let key = shortcutKey(from: event.keyCode) else { return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return KeyboardShortcut(
            usesCommand: flags.contains(.command),
            usesOption: flags.contains(.option),
            usesControl: flags.contains(.control),
            usesShift: flags.contains(.shift),
            key: key
        )
    }

    static func shortcutKey(from keyCode: UInt16) -> String? {
        reverseKeyCodeMap[keyCode]
    }

    static func keyCode(for key: String) -> UInt16? {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        return keyCodeMap[normalized]
    }
}

enum HistoryRetentionPreset: String, Codable, CaseIterable {
    case day
    case week
    case month
    case quarter
    case halfYear
    case year
    case unlimited

    var title: String {
        switch self {
        case .day:
            return AppLocalization.localized("天")
        case .week:
            return AppLocalization.localized("周")
        case .month:
            return AppLocalization.localized("月")
        case .quarter:
            return AppLocalization.localized("季度")
        case .halfYear:
            return AppLocalization.localized("半年")
        case .year:
            return AppLocalization.localized("年")
        case .unlimited:
            return AppLocalization.localized("无限制")
        }
    }

    var description: String {
        switch self {
        case .day:
            return AppLocalization.localized("仅保留最近 1 天")
        case .week:
            return AppLocalization.localized("仅保留最近 7 天")
        case .month:
            return AppLocalization.localized("仅保留最近 30 天")
        case .quarter:
            return AppLocalization.localized("仅保留最近 90 天")
        case .halfYear:
            return AppLocalization.localized("仅保留最近 180 天")
        case .year:
            return AppLocalization.localized("仅保留最近 365 天")
        case .unlimited:
            return AppLocalization.localized("不按时间清理")
        }
    }

    var days: Int? {
        switch self {
        case .day:
            return 1
        case .week:
            return 7
        case .month:
            return 30
        case .quarter:
            return 90
        case .halfYear:
            return 180
        case .year:
            return 365
        case .unlimited:
            return nil
        }
    }

    static func fromLegacy(days: Int) -> HistoryRetentionPreset {
        switch days {
        case ..<2:
            return .day
        case ..<14:
            return .week
        case ..<60:
            return .month
        case ..<120:
            return .quarter
        case ..<270:
            return .halfYear
        case ..<500:
            return .year
        default:
            return .unlimited
        }
    }
}

enum PastedItemPlacement: String, Codable, CaseIterable {
    case keepOriginal
    case moveToTop

    var title: String {
        switch self {
        case .keepOriginal:
            return AppLocalization.localized("保留原位")
        case .moveToTop:
            return AppLocalization.localized("自动置顶")
        }
    }
}

enum PanelTabSwitchMode: String, Codable, CaseIterable {
    case hover
    case click

    var title: String {
        switch self {
        case .hover:
            return AppLocalization.localized("鼠标悬停")
        case .click:
            return AppLocalization.localized("鼠标点击")
        }
    }
}

enum EdgeActivationPlacementMode: String, Codable, CaseIterable {
    case followPointer
    case centered
    case custom

    var title: String {
        switch self {
        case .followPointer:
            return AppLocalization.localized("跟随鼠标")
        case .centered:
            return AppLocalization.localized("固定居中")
        case .custom:
            return AppLocalization.localized("自定义位置")
        }
    }

    var detail: String {
        switch self {
        case .followPointer:
            return AppLocalization.localized("面板会跟着鼠标高度出现，方便直接点到前几条记录。")
        case .centered:
            return AppLocalization.localized("面板固定在所选边缘的中间，位置更稳定，也更容易形成习惯。")
        case .custom:
            return AppLocalization.localized("面板固定在你指定的高度。拖动下方位置条时，所选边缘会同步显示预览。")
        }
    }
}

enum EdgeActivationSide: String, Codable, CaseIterable {
    case right
    case left

    var title: String {
        switch self {
        case .right:
            return AppLocalization.localized("屏幕右侧")
        case .left:
            return AppLocalization.localized("屏幕左侧")
        }
    }
}

enum MouseGestureDirection: String, Codable, CaseIterable {
    case up
    case down
    case left
    case right

    var title: String {
        switch self {
        case .up:
            return AppLocalization.localized("上")
        case .down:
            return AppLocalization.localized("下")
        case .left:
            return AppLocalization.localized("左")
        case .right:
            return AppLocalization.localized("右")
        }
    }
}

enum RightMouseAuxiliaryActionType: String, Codable, CaseIterable {
    case shortcut
    case openApplication

    var title: String {
        switch self {
        case .shortcut:
            return AppLocalization.localized("快捷键")
        case .openApplication:
            return "App"
        }
    }
}

enum RightMouseAuxiliaryGesturePattern: String, Codable, CaseIterable {
    case unconfigured
    case downThenRight
    case downThenLeft
    case downThenUp
    case upThenRight
    case upThenLeft
    case upThenDown
    case leftThenUp
    case leftThenDown
    case leftThenRight
    case down
    case up
    case left

    var title: String {
        switch self {
        case .unconfigured:
            return AppLocalization.localized("选择手势")
        case .downThenRight:
            return AppLocalization.localized("下 -> 右")
        case .downThenLeft:
            return AppLocalization.localized("下 -> 左")
        case .downThenUp:
            return AppLocalization.localized("下 -> 上")
        case .upThenRight:
            return AppLocalization.localized("上 -> 右")
        case .upThenLeft:
            return AppLocalization.localized("上 -> 左")
        case .upThenDown:
            return AppLocalization.localized("上 -> 下")
        case .leftThenUp:
            return AppLocalization.localized("左 -> 上")
        case .leftThenDown:
            return AppLocalization.localized("左 -> 下")
        case .leftThenRight:
            return AppLocalization.localized("左 -> 右")
        case .down:
            return AppLocalization.localized("下")
        case .up:
            return AppLocalization.localized("上")
        case .left:
            return AppLocalization.localized("左")
        }
    }

    var directions: [MouseGestureDirection] {
        switch self {
        case .unconfigured:
            return []
        case .downThenRight:
            return [.down, .right]
        case .downThenLeft:
            return [.down, .left]
        case .downThenUp:
            return [.down, .up]
        case .upThenRight:
            return [.up, .right]
        case .upThenLeft:
            return [.up, .left]
        case .upThenDown:
            return [.up, .down]
        case .leftThenUp:
            return [.left, .up]
        case .leftThenDown:
            return [.left, .down]
        case .leftThenRight:
            return [.left, .right]
        case .down:
            return [.down]
        case .up:
            return [.up]
        case .left:
            return [.left]
        }
    }

    static func fromLegacy(
        firstDirection: MouseGestureDirection,
        secondDirection: MouseGestureDirection
    ) -> RightMouseAuxiliaryGesturePattern {
        switch (firstDirection, secondDirection) {
        case (.down, .right):
            return .downThenRight
        case (.down, .left):
            return .downThenLeft
        case (.down, .up):
            return .downThenUp
        case (.up, .right):
            return .upThenRight
        case (.up, .left):
            return .upThenLeft
        case (.up, .down):
            return .upThenDown
        case (.left, .up):
            return .leftThenUp
        case (.left, .down):
            return .leftThenDown
        case (.left, .right):
            return .leftThenRight
        case (.down, _):
            return .down
        case (.up, _):
            return .up
        case (.left, _):
            return .left
        case (.right, _):
            return .downThenRight
        }
    }
}

struct RightMouseAuxiliaryGestureSettings: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var enabled: Bool = true
    var pattern: RightMouseAuxiliaryGesturePattern = .unconfigured
    var actionType: RightMouseAuxiliaryActionType = .shortcut
    var shortcutUsesCommand: Bool = false
    var shortcutUsesOption: Bool = false
    var shortcutUsesControl: Bool = false
    var shortcutUsesShift: Bool = false
    var shortcutKey: String = ""
    var applicationPath: String = ""
    var note: String = ""

    static func `default`() -> RightMouseAuxiliaryGestureSettings {
        RightMouseAuxiliaryGestureSettings()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case enabled
        case pattern
        case firstDirection
        case secondDirection
        case actionType
        case shortcutUsesCommand
        case shortcutUsesOption
        case shortcutUsesControl
        case shortcutUsesShift
        case shortcutKey
        case applicationPath
        case note
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        if let decodedPattern = try container.decodeIfPresent(RightMouseAuxiliaryGesturePattern.self, forKey: .pattern) {
            pattern = decodedPattern
        } else {
            let firstDirection = try container.decodeIfPresent(MouseGestureDirection.self, forKey: .firstDirection) ?? .down
            let secondDirection = try container.decodeIfPresent(MouseGestureDirection.self, forKey: .secondDirection) ?? .right
            pattern = .fromLegacy(firstDirection: firstDirection, secondDirection: secondDirection)
        }
        actionType = try container.decodeIfPresent(RightMouseAuxiliaryActionType.self, forKey: .actionType) ?? .shortcut
        shortcutUsesCommand = try container.decodeIfPresent(Bool.self, forKey: .shortcutUsesCommand) ?? false
        shortcutUsesOption = try container.decodeIfPresent(Bool.self, forKey: .shortcutUsesOption) ?? false
        shortcutUsesControl = try container.decodeIfPresent(Bool.self, forKey: .shortcutUsesControl) ?? false
        shortcutUsesShift = try container.decodeIfPresent(Bool.self, forKey: .shortcutUsesShift) ?? false
        shortcutKey = try container.decodeIfPresent(String.self, forKey: .shortcutKey) ?? ""
        applicationPath = try container.decodeIfPresent(String.self, forKey: .applicationPath) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(pattern, forKey: .pattern)
        try container.encode(actionType, forKey: .actionType)
        try container.encode(shortcutUsesCommand, forKey: .shortcutUsesCommand)
        try container.encode(shortcutUsesOption, forKey: .shortcutUsesOption)
        try container.encode(shortcutUsesControl, forKey: .shortcutUsesControl)
        try container.encode(shortcutUsesShift, forKey: .shortcutUsesShift)
        try container.encode(shortcutKey, forKey: .shortcutKey)
        try container.encode(applicationPath, forKey: .applicationPath)
        try container.encode(note, forKey: .note)
    }
}

struct AppSettings: Codable {
    static let legacyDefaultBlacklistedBundleIDs: Set<String> = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword",
        "com.1password.1password"
    ]
    static let defaultSensitiveBlacklistedBundleIDs: Set<String> = [
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword",
        "com.1password.1password",
        "com.bitwarden.desktop"
    ]

    var maxHistoryCount: Int = 200
    var maxHistoryDiskUsageMB: Int = 1024
    var historyRetentionPreset: HistoryRetentionPreset = .month
    var dataStorageCustomDirectoryPath: String?
    var dataStorageCustomDirectoryBookmark: Data?

    var hasCompletedOnboarding: Bool = false
    var autoPasteEnabled: Bool = true
    var launchAtLoginEnabled: Bool = false
    var recordImageClipboardEnabled: Bool = true
    var recordFileClipboardEnabled: Bool = true
    var filePreviewEnabled: Bool = true
    var continuousFilePreviewEnabled: Bool = false
    var pastedItemPlacement: PastedItemPlacement = .moveToTop
    var panelReplaceableTabs: [PanelTab] = PanelTab.defaultReplaceableSlots
    var panelTabSwitchMode: PanelTabSwitchMode = .hover
    var pinnedPanelIdleTransparencyPercent: Int = 35

    var globalHotkeyEnabled: Bool = true
    var hotkeyTriggerMode: GlobalHotkeyTriggerMode = .doubleModifier
    var hotkeyPanelModifier: HotkeyModifier = .command
    var hotkeyFavoritesModifier: HotkeyModifier?
    var hotkeyDoublePressInterval: Double = 0.36
    var hotkeyPanelShortcut: KeyboardShortcut = .defaultPanelTrigger
    var hotkeyFavoritesShortcut: KeyboardShortcut = KeyboardShortcut()
    var hotkeyPanelPlacementMode: HotkeyPanelPlacementMode = .followPointer
    var hotkeyPanelLastFrameOrigin: PersistedPanelOrigin?
    var dockIconVisible: Bool = true
    var menuBarStatusItemVisible: Bool = true
    var menuBarActivationEnabled: Bool = true
    var menuBarShowsLatestPreview: Bool = false
    var rightMouseDragActivationEnabled: Bool = false
    var rightMouseDragTriggerDistance: CGFloat = 72
    var rightMouseAuxiliaryGestures: [RightMouseAuxiliaryGestureSettings] = [RightMouseAuxiliaryGestureSettings.default()]

    var appearanceMode: AppearanceMode = .system
    var language: AppLanguage = .system
    var edgeActivationEnabled: Bool = true
    var edgeActivationSide: EdgeActivationSide = .right
    var edgeActivationPlacementMode: EdgeActivationPlacementMode = .followPointer
    // 0...1, where 0 is near the top of the allowed range and 1 is near the bottom.
    var edgeActivationCustomVerticalPosition: Double = 0.5
    var edgeThreshold: CGFloat = 2
    var edgeActivationDelayMS: Int = 200
    var edgePanelAutoCollapseDistance: CGFloat = 22

    var blacklistedBundleIDs: Set<String> = Self.defaultSensitiveBlacklistedBundleIDs

    var historyRetentionDays: Int? {
        historyRetentionPreset.days
    }

    private enum CodingKeys: String, CodingKey {
        case maxHistoryCount
        case maxHistoryDiskUsageMB
        case historyRetentionPreset
        case historyRetentionDays
        case dataStorageCustomDirectoryPath
        case dataStorageCustomDirectoryBookmark
        case hasCompletedOnboarding
        case autoPasteEnabled
        case launchAtLoginEnabled
        case recordImageClipboardEnabled
        case recordFileClipboardEnabled
        case filePreviewEnabled
        case continuousFilePreviewEnabled
        case pastedItemPlacement
        case panelReplaceableTabs
        case panelTabSwitchMode
        case pinnedPanelIdleTransparencyPercent
        case enabledPanelTabs
        case globalHotkeyEnabled
        case hotkeyTriggerMode
        case hotkeyPanelModifier
        case hotkeyFavoritesModifier
        case hotkeyDoublePressInterval
        case hotkeyPanelShortcut
        case hotkeyFavoritesShortcut
        case hotkeyPanelPlacementMode
        case hotkeyPanelLastFrameOrigin
        case hotkeyModifier
        case hotkeyShortcut
        case dockIconVisible
        case menuBarStatusItemVisible
        case menuBarActivationEnabled
        case menuBarShowsLatestPreview
        case rightMouseDragActivationEnabled
        case rightMouseDragTriggerDistance
        case rightMouseAuxiliaryGesture
        case rightMouseAuxiliaryGestures
        case appearanceMode
        case language
        case edgeActivationEnabled
        case edgeActivationSide
        case edgeActivationPlacementMode
        case edgeActivationCustomVerticalPosition
        case edgeThreshold
        case edgeActivationDelayMS
        case edgePanelAutoCollapseDistance
        case blacklistedBundleIDs
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        maxHistoryCount = try container.decodeIfPresent(Int.self, forKey: .maxHistoryCount) ?? 200
        maxHistoryDiskUsageMB = try container.decodeIfPresent(Int.self, forKey: .maxHistoryDiskUsageMB) ?? 1024
        dataStorageCustomDirectoryPath = try container.decodeIfPresent(String.self, forKey: .dataStorageCustomDirectoryPath)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if dataStorageCustomDirectoryPath?.isEmpty == true {
            dataStorageCustomDirectoryPath = nil
        }
        dataStorageCustomDirectoryBookmark = try container.decodeIfPresent(Data.self, forKey: .dataStorageCustomDirectoryBookmark)

        if let preset = try container.decodeIfPresent(HistoryRetentionPreset.self, forKey: .historyRetentionPreset) {
            historyRetentionPreset = preset
        } else if let legacyDays = try container.decodeIfPresent(Int.self, forKey: .historyRetentionDays) {
            historyRetentionPreset = HistoryRetentionPreset.fromLegacy(days: legacyDays)
        } else {
            historyRetentionPreset = .month
        }

        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? true
        autoPasteEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoPasteEnabled) ?? true
        launchAtLoginEnabled = try container.decodeIfPresent(Bool.self, forKey: .launchAtLoginEnabled) ?? false
        recordImageClipboardEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordImageClipboardEnabled) ?? true
        recordFileClipboardEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordFileClipboardEnabled) ?? true
        filePreviewEnabled = try container.decodeIfPresent(Bool.self, forKey: .filePreviewEnabled) ?? true
        continuousFilePreviewEnabled = try container.decodeIfPresent(Bool.self, forKey: .continuousFilePreviewEnabled) ?? false
        pastedItemPlacement = try container.decodeIfPresent(PastedItemPlacement.self, forKey: .pastedItemPlacement) ?? .moveToTop
        if let storedSlots = try container.decodeIfPresent([PanelTab].self, forKey: .panelReplaceableTabs) {
            panelReplaceableTabs = PanelTab.sanitizedReplaceableSlots(from: storedSlots)
        } else {
            let legacyVisibleTabs = try container.decodeIfPresent([PanelTab].self, forKey: .enabledPanelTabs) ?? []
            let legacyReplaceable = legacyVisibleTabs.filter { PanelTab.replaceableChoices.contains($0) }
            panelReplaceableTabs = PanelTab.sanitizedReplaceableSlots(from: legacyReplaceable)
        }
        panelTabSwitchMode = try container.decodeIfPresent(PanelTabSwitchMode.self, forKey: .panelTabSwitchMode) ?? .hover
        pinnedPanelIdleTransparencyPercent = min(
            90,
            max(
                0,
                try container.decodeIfPresent(Int.self, forKey: .pinnedPanelIdleTransparencyPercent) ?? 35
            )
        )

        globalHotkeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalHotkeyEnabled) ?? true
        hotkeyTriggerMode = try container.decodeIfPresent(GlobalHotkeyTriggerMode.self, forKey: .hotkeyTriggerMode) ?? .doubleModifier
        let decodedPanelModifier = try container.decodeIfPresent(HotkeyModifier.self, forKey: .hotkeyPanelModifier)
        let legacyPanelModifier = try container.decodeIfPresent(HotkeyModifier.self, forKey: .hotkeyModifier)
        hotkeyPanelModifier = decodedPanelModifier ?? legacyPanelModifier ?? .command
        hotkeyFavoritesModifier = try container.decodeIfPresent(HotkeyModifier.self, forKey: .hotkeyFavoritesModifier)
        hotkeyDoublePressInterval = try container.decodeIfPresent(Double.self, forKey: .hotkeyDoublePressInterval) ?? 0.36
        let decodedPanelShortcut = try container.decodeIfPresent(KeyboardShortcut.self, forKey: .hotkeyPanelShortcut)
        let legacyPanelShortcut = try container.decodeIfPresent(KeyboardShortcut.self, forKey: .hotkeyShortcut)
        hotkeyPanelShortcut = decodedPanelShortcut ?? legacyPanelShortcut ?? .defaultPanelTrigger
        hotkeyPanelShortcut.normalize()
        hotkeyFavoritesShortcut = try container.decodeIfPresent(KeyboardShortcut.self, forKey: .hotkeyFavoritesShortcut) ?? KeyboardShortcut()
        hotkeyFavoritesShortcut.normalize()
        if !hotkeyPanelShortcut.isConfigured {
            hotkeyPanelShortcut = .defaultPanelTrigger
        }
        if hotkeyFavoritesModifier == hotkeyPanelModifier {
            hotkeyFavoritesModifier = nil
        }
        if hotkeyFavoritesShortcut.conflicts(with: hotkeyPanelShortcut) {
            hotkeyFavoritesShortcut = KeyboardShortcut()
        }
        hotkeyPanelPlacementMode = try container.decodeIfPresent(HotkeyPanelPlacementMode.self, forKey: .hotkeyPanelPlacementMode) ?? .followPointer
        hotkeyPanelLastFrameOrigin = try container.decodeIfPresent(PersistedPanelOrigin.self, forKey: .hotkeyPanelLastFrameOrigin)
        dockIconVisible = try container.decodeIfPresent(Bool.self, forKey: .dockIconVisible) ?? true
        menuBarStatusItemVisible = try container.decodeIfPresent(Bool.self, forKey: .menuBarStatusItemVisible) ?? true
        menuBarActivationEnabled = try container.decodeIfPresent(Bool.self, forKey: .menuBarActivationEnabled) ?? true
        menuBarShowsLatestPreview = try container.decodeIfPresent(Bool.self, forKey: .menuBarShowsLatestPreview) ?? false
        rightMouseDragActivationEnabled = try container.decodeIfPresent(Bool.self, forKey: .rightMouseDragActivationEnabled) ?? false
        rightMouseDragTriggerDistance = try container.decodeIfPresent(CGFloat.self, forKey: .rightMouseDragTriggerDistance) ?? 72
        if let gestures = try container.decodeIfPresent([RightMouseAuxiliaryGestureSettings].self, forKey: .rightMouseAuxiliaryGestures) {
            rightMouseAuxiliaryGestures = gestures
        } else if let legacyGesture = try container.decodeIfPresent(RightMouseAuxiliaryGestureSettings.self, forKey: .rightMouseAuxiliaryGesture) {
            rightMouseAuxiliaryGestures = [legacyGesture]
        } else {
            rightMouseAuxiliaryGestures = [RightMouseAuxiliaryGestureSettings.default()]
        }

        appearanceMode = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode) ?? .system
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        edgeActivationEnabled = try container.decodeIfPresent(Bool.self, forKey: .edgeActivationEnabled) ?? true
        edgeActivationSide = try container.decodeIfPresent(EdgeActivationSide.self, forKey: .edgeActivationSide) ?? .right
        edgeActivationPlacementMode = try container.decodeIfPresent(EdgeActivationPlacementMode.self, forKey: .edgeActivationPlacementMode) ?? .followPointer
        edgeActivationCustomVerticalPosition = min(
            1,
            max(
                0,
                try container.decodeIfPresent(Double.self, forKey: .edgeActivationCustomVerticalPosition) ?? 0.5
            )
        )
        edgeThreshold = try container.decodeIfPresent(CGFloat.self, forKey: .edgeThreshold) ?? 2
        edgeActivationDelayMS = try container.decodeIfPresent(Int.self, forKey: .edgeActivationDelayMS) ?? 200
        edgePanelAutoCollapseDistance = max(
            0,
            try container.decodeIfPresent(CGFloat.self, forKey: .edgePanelAutoCollapseDistance) ?? 22
        )

        blacklistedBundleIDs = try container.decodeIfPresent(Set<String>.self, forKey: .blacklistedBundleIDs) ?? Self.defaultSensitiveBlacklistedBundleIDs
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(maxHistoryCount, forKey: .maxHistoryCount)
        try container.encode(maxHistoryDiskUsageMB, forKey: .maxHistoryDiskUsageMB)
        try container.encode(historyRetentionPreset, forKey: .historyRetentionPreset)
        try container.encodeIfPresent(dataStorageCustomDirectoryPath, forKey: .dataStorageCustomDirectoryPath)
        try container.encodeIfPresent(dataStorageCustomDirectoryBookmark, forKey: .dataStorageCustomDirectoryBookmark)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(autoPasteEnabled, forKey: .autoPasteEnabled)
        try container.encode(launchAtLoginEnabled, forKey: .launchAtLoginEnabled)
        try container.encode(recordImageClipboardEnabled, forKey: .recordImageClipboardEnabled)
        try container.encode(recordFileClipboardEnabled, forKey: .recordFileClipboardEnabled)
        try container.encode(filePreviewEnabled, forKey: .filePreviewEnabled)
        try container.encode(continuousFilePreviewEnabled, forKey: .continuousFilePreviewEnabled)
        try container.encode(pastedItemPlacement, forKey: .pastedItemPlacement)
        try container.encode(PanelTab.sanitizedReplaceableSlots(from: panelReplaceableTabs), forKey: .panelReplaceableTabs)
        try container.encode(panelTabSwitchMode, forKey: .panelTabSwitchMode)
        try container.encode(pinnedPanelIdleTransparencyPercent, forKey: .pinnedPanelIdleTransparencyPercent)
        try container.encode(globalHotkeyEnabled, forKey: .globalHotkeyEnabled)
        try container.encode(hotkeyTriggerMode, forKey: .hotkeyTriggerMode)
        try container.encode(hotkeyPanelModifier, forKey: .hotkeyPanelModifier)
        try container.encodeIfPresent(hotkeyFavoritesModifier, forKey: .hotkeyFavoritesModifier)
        try container.encode(hotkeyDoublePressInterval, forKey: .hotkeyDoublePressInterval)
        try container.encode(hotkeyPanelShortcut, forKey: .hotkeyPanelShortcut)
        try container.encode(hotkeyFavoritesShortcut, forKey: .hotkeyFavoritesShortcut)
        try container.encode(hotkeyPanelPlacementMode, forKey: .hotkeyPanelPlacementMode)
        try container.encodeIfPresent(hotkeyPanelLastFrameOrigin, forKey: .hotkeyPanelLastFrameOrigin)
        try container.encode(dockIconVisible, forKey: .dockIconVisible)
        try container.encode(menuBarStatusItemVisible, forKey: .menuBarStatusItemVisible)
        try container.encode(menuBarActivationEnabled, forKey: .menuBarActivationEnabled)
        try container.encode(menuBarShowsLatestPreview, forKey: .menuBarShowsLatestPreview)
        try container.encode(rightMouseDragActivationEnabled, forKey: .rightMouseDragActivationEnabled)
        try container.encode(rightMouseDragTriggerDistance, forKey: .rightMouseDragTriggerDistance)
        try container.encode(rightMouseAuxiliaryGestures, forKey: .rightMouseAuxiliaryGestures)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(language, forKey: .language)
        try container.encode(edgeActivationEnabled, forKey: .edgeActivationEnabled)
        try container.encode(edgeActivationSide, forKey: .edgeActivationSide)
        try container.encode(edgeActivationPlacementMode, forKey: .edgeActivationPlacementMode)
        try container.encode(edgeActivationCustomVerticalPosition, forKey: .edgeActivationCustomVerticalPosition)
        try container.encode(edgeThreshold, forKey: .edgeThreshold)
        try container.encode(edgeActivationDelayMS, forKey: .edgeActivationDelayMS)
        try container.encode(edgePanelAutoCollapseDistance, forKey: .edgePanelAutoCollapseDistance)
        try container.encode(blacklistedBundleIDs, forKey: .blacklistedBundleIDs)
    }
}
