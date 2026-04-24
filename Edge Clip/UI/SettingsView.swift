import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case interaction
    case preferences
    case panel
    case general
    case blacklist
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .interaction:
            return AppLocalization.localized("交互")
        case .preferences:
            return AppLocalization.localized("使用偏好")
        case .panel:
            return AppLocalization.localized("剪贴面板")
        case .general:
            return AppLocalization.localized("通用")
        case .blacklist:
            return AppLocalization.localized("应用例外")
        case .about:
            return AppLocalization.localized("关于")
        }
    }

    var icon: String {
        switch self {
        case .interaction:
            return "cursorarrow.motionlines"
        case .preferences:
            return "slider.horizontal.below.rectangle"
        case .panel:
            return "rectangle.grid.1x2"
        case .general:
            return "switch.2"
        case .blacklist:
            return "hand.raised"
        case .about:
            return "info.circle"
        }
    }
}

private enum AuxiliaryDropdownTarget: Hashable {
    case pattern(UUID)
    case action(UUID)
}

private enum ClipboardCaptureRuleTarget {
    case blacklist

    var openPanelMessage: String {
        switch self {
        case .blacklist:
            return AppLocalization.localized("选择要停止记录历史的 App。")
        }
    }
}

private enum GlobalHotkeyRecorderTarget: Equatable {
    case panel
    case favorites
}

struct SettingsView: View {
    @EnvironmentObject private var services: AppServices
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    let section: SettingsSection

    @State private var recordingGestureID: UUID?
    @State private var recordingGlobalHotkeyTarget: GlobalHotkeyRecorderTarget?
    @FocusState private var focusedAuxiliaryNoteID: UUID?
    @State private var activeAuxiliaryDropdown: AuxiliaryDropdownTarget?
    @State private var isOpenSourceCreditsPresented = false
    @State private var isPanelTagDetailsExpanded = false
    @State private var isStackGuideExpanded = false
    @State private var edgeCustomPositionDraft: Double?
    @State private var isAdjustingEdgeCustomPosition = false
    @State private var edgeCustomPositionDragPointerOffset: CGFloat?

    private let historyLimitAccessoryWidth: CGFloat = 180
    private let auxiliaryGestureColumnWidth: CGFloat = 108
    private let auxiliaryActionColumnWidth: CGFloat = 92
    private let auxiliaryPayloadColumnWidth: CGFloat = 146
    private let auxiliaryDeleteColumnWidth: CGFloat = 36
    private let auxiliaryControlHeight: CGFloat = 36
    private let globalHotkeyRecorderMinWidth: CGFloat = 176
    private let globalHotkeyRecorderMaxWidth: CGFloat = 260
    private let globalHotkeyRecorderHeight: CGFloat = 30
    private let pageHorizontalPadding: CGFloat = 24
    private let edgeClipWebsiteURL = EdgeClipExternalLinks.websiteURL
    private let edgeClipPrivacyPolicyURL = EdgeClipExternalLinks.privacyPolicyURL

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key)
    }

    var body: some View {
        detailContent
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedAuxiliaryNoteID = nil
                activeAuxiliaryDropdown = nil
            }
        )
        .background(
            settingsPageBackground
        )
        .sheet(isPresented: $isOpenSourceCreditsPresented) {
            OpenSourceCreditsSheetView()
        }
        .onChange(of: appState.settings.edgeActivationEnabled) { _, isEnabled in
            if !isEnabled {
                dismissEdgeActivationPreviewAdjustments()
            }
        }
        .onChange(of: appState.settings.edgeActivationPlacementMode) { _, mode in
            if mode != .custom {
                dismissEdgeActivationPreviewAdjustments()
            }
        }
        .onChange(of: appState.settings.edgeActivationSide) { _, _ in
            dismissEdgeActivationPreviewAdjustments()
        }
        .onChange(of: appState.settings.hotkeyTriggerMode) { _, mode in
            if mode != .keyCombination {
                recordingGlobalHotkeyTarget = nil
            }
        }
        .onDisappear {
            recordingGlobalHotkeyTarget = nil
            dismissEdgeActivationPreviewAdjustments()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch section {
        case .interaction:
            interactionSection
        case .preferences:
            preferencesSection
        case .panel:
            panelSection
        case .general:
            generalSection
        case .blacklist:
            blacklistSection
        case .about:
            aboutSection
        }
    }

    private var interactionSection: some View {
        sectionPage(
            title: "交互",
            subtitle: interactionSectionSubtitle,
            subtitleColor: interactionSectionSubtitleColor
        ) {
            settingsCard(
                title: "边缘唤出",
                subtitle: "鼠标移到所选屏幕边缘即可打开面板，适合单手操作。",
                headerAccessory: {
                    Toggle("", isOn: settingsBinding(\.edgeActivationEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            ) {
                VStack(spacing: 0) {
                    settingRowWithNote(
                        title: "选择边缘",
                        note: "决定边缘唤出监听屏幕左侧还是右侧。默认使用屏幕右侧。"
                    ) {
                        Picker(localized("选择边缘"), selection: edgeActivationSideBinding) {
                            ForEach(EdgeActivationSide.allCases, id: \.self) { side in
                                Text(side.title).tag(side)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .disabled(!appState.settings.edgeActivationEnabled)
                    .opacity(appState.settings.edgeActivationEnabled ? 1 : 0.45)

                    settingsDivider(opacity: 0.4)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(localized("出现位置"))
                            Spacer()
                            Text(appState.settings.edgeActivationPlacementMode.title)
                                .foregroundStyle(.secondary)
                        }

                        Picker(localized("出现位置"), selection: edgeActivationPlacementModeBinding) {
                            ForEach(EdgeActivationPlacementMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(appState.settings.edgeActivationPlacementMode.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 10)
                    .disabled(!appState.settings.edgeActivationEnabled)
                    .opacity(appState.settings.edgeActivationEnabled ? 1 : 0.45)

                    if appState.settings.edgeActivationPlacementMode == .custom {
                        settingsDivider(opacity: 0.4)

                        edgeCustomPositionControl
                            .padding(.vertical, 10)
                            .disabled(!appState.settings.edgeActivationEnabled)
                            .opacity(appState.settings.edgeActivationEnabled ? 1 : 0.45)
                    }

                    settingsDivider(opacity: 0.4)

                    settingControlBlock(
                        title: "边缘触发阈值",
                        description: "控制鼠标要多贴近所选边缘，才开始等待展开。数值越大越容易触发，数值越小越不容易误碰。",
                        value: {
                            Text("\(Int(appState.settings.edgeThreshold)) px")
                                .foregroundStyle(.secondary)
                        },
                        control: {
                            Slider(value: settingsBinding(\.edgeThreshold), in: 1...10, step: 1)
                        }
                    )
                    .padding(.vertical, 10)
                    .disabled(!appState.settings.edgeActivationEnabled)
                    .opacity(appState.settings.edgeActivationEnabled ? 1 : 0.45)

                    settingsDivider(opacity: 0.4)

                    let isZeroDelay = appState.settings.edgeActivationDelayMS == 0

                    settingControlBlock(
                        title: "边缘触发延迟",
                        description: "控制鼠标进入所选边缘热区后，要停留多久才展开面板。",
                        value: {
                            Text("\(appState.settings.edgeActivationDelayMS) ms")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        },
                        control: {
                            Slider(
                                value: Binding(
                                    get: { Double(appState.settings.edgeActivationDelayMS) },
                                    set: { newValue in
                                        appState.updateSettings { settings in
                                            settings.edgeActivationDelayMS = Int(newValue.rounded())
                                        }
                                    }
                                ),
                                in: 0...1000,
                                step: 10
                            )
                        },
                        footer: {
                            if isZeroDelay {
                                Text(localized("已设为 0 ms：响应最快，也更容易误触发。"))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    )
                    .padding(.vertical, 10)
                    .disabled(!appState.settings.edgeActivationEnabled)
                    .opacity(appState.settings.edgeActivationEnabled ? 1 : 0.45)

                    settingsDivider(opacity: 0.4)

                    let isZeroCollapseDistance = appState.settings.edgePanelAutoCollapseDistance == 0

                    settingControlBlock(
                        title: "鼠标离开面板的收起距离",
                        description: "控制鼠标离开面板多远后才自动收起面板。数值越大越不容易误收起，数值越小则收起更干脆但不易点击到位于边缘的按钮。",
                        value: {
                            Text("\(Int(appState.settings.edgePanelAutoCollapseDistance)) px")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        },
                        control: {
                            Slider(
                                value: settingsBinding(\.edgePanelAutoCollapseDistance),
                                in: 0...80,
                                step: 1
                            )
                        },
                        footer: {
                            if isZeroCollapseDistance {
                                Text(localized("已设为 0 px：鼠标一离开面板，就会更快自动收回。"))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    )
                    .padding(.vertical, 10)
                    .disabled(!appState.settings.edgeActivationEnabled)
                    .opacity(appState.settings.edgeActivationEnabled ? 1 : 0.45)
                }
            }

            settingsCard(
                title: "快捷键唤出",
                subtitle: "可设置按键方式，以及快捷键唤出时的面板位置。",
                headerAccessory: {
                    Toggle("", isOn: settingsBinding(\.globalHotkeyEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            ) {
                VStack(spacing: 0) {
                    settingRowWithNote(
                        title: "面板位置",
                        note: appState.settings.hotkeyPanelPlacementMode.detail
                    ) {
                        Picker(localized("面板位置"), selection: settingsBinding(\.hotkeyPanelPlacementMode)) {
                            ForEach(HotkeyPanelPlacementMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .disabled(!appState.settings.globalHotkeyEnabled)
                    .opacity(appState.settings.globalHotkeyEnabled ? 1 : 0.45)

                    settingsDivider(opacity: 0.4)

                    settingRowWithNote(
                        title: "按键方式",
                        note: "双击修饰键适合只用修饰键唤出；组合按键可录入完整快捷键。",
                    ) {
                        Picker(localized("按键方式"), selection: settingsBinding(\.hotkeyTriggerMode)) {
                            ForEach(GlobalHotkeyTriggerMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 180, alignment: .trailing)
                    }
                    .padding(.vertical, 10)
                    .disabled(!appState.settings.globalHotkeyEnabled)
                    .opacity(appState.settings.globalHotkeyEnabled ? 1 : 0.45)

                    settingsDivider(opacity: 0.4)

                    if appState.settings.hotkeyTriggerMode == .doubleModifier {
                        settingRowWithNote(
                            title: "双击修饰键打开剪贴面板",
                            note: "",
                            supplementaryNote: appState.settings.hotkeyPanelModifier == .shift ? "可能与中英切换冲突。" : nil,
                            supplementaryNoteColor: .orange
                        ) {
                            Picker(localized("双击修饰键打开剪贴面板"), selection: hotkeyPanelModifierBinding) {
                                ForEach(HotkeyModifier.allCases, id: \.self) { key in
                                    Text(key.title).tag(key)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 180, alignment: .trailing)
                        }
                        .padding(.vertical, 10)
                        .disabled(!appState.settings.globalHotkeyEnabled)
                        .opacity(appState.settings.globalHotkeyEnabled ? 1 : 0.45)

                        settingsDivider(opacity: 0.4)

                        settingRowWithNote(
                            title: "双击修饰键打开收藏标签",
                            note: "",
                            supplementaryNote: appState.settings.hotkeyFavoritesModifier == .shift ? "可能与中英切换冲突。" : nil,
                            supplementaryNoteColor: .orange
                        ) {
                            Picker(localized("双击修饰键打开收藏标签"), selection: hotkeyFavoritesModifierBinding) {
                                Text(localized("不启用")).tag(nil as HotkeyModifier?)
                                ForEach(HotkeyModifier.allCases, id: \.self) { key in
                                    Text(key.title).tag(Optional(key))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: 180, alignment: .trailing)
                        }
                        .padding(.vertical, 10)
                        .disabled(!appState.settings.globalHotkeyEnabled)
                        .opacity(appState.settings.globalHotkeyEnabled ? 1 : 0.45)
                    } else {
                        settingRowWithNote(
                            title: "组合按键打开剪贴面板",
                            note: ""
                        ) {
                            ShortcutRecorderField(
                                displayText: hotkeyShortcutDisplayText(for: .panel),
                                isRecording: recordingGlobalHotkeyTarget == .panel,
                                height: globalHotkeyRecorderHeight,
                                textAlignment: .center,
                                usesContentDrivenWidth: true,
                                minimumWidth: globalHotkeyRecorderMinWidth,
                                maximumWidth: globalHotkeyRecorderMaxWidth,
                                fontSize: NSFont.systemFontSize,
                                fontWeight: .regular,
                                onBeginRecording: {
                                    recordingGlobalHotkeyTarget = .panel
                                },
                                onCancelRecording: {
                                    if recordingGlobalHotkeyTarget == .panel {
                                        recordingGlobalHotkeyTarget = nil
                                    }
                                },
                                onClear: {
                                    appState.updateSettings { settings in
                                        settings.hotkeyPanelShortcut = .defaultPanelTrigger
                                    }
                                    if recordingGlobalHotkeyTarget == .panel {
                                        recordingGlobalHotkeyTarget = nil
                                    }
                                },
                                onRecord: { event in
                                    recordHotkeyShortcut(from: event, target: .panel)
                                }
                            )
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.vertical, 10)
                        .disabled(!appState.settings.globalHotkeyEnabled)
                        .opacity(appState.settings.globalHotkeyEnabled ? 1 : 0.45)

                        settingsDivider(opacity: 0.4)

                        settingRowWithNote(
                            title: "组合按键打开收藏标签",
                            note: ""
                        ) {
                            ShortcutRecorderField(
                                displayText: hotkeyShortcutDisplayText(for: .favorites),
                                isRecording: recordingGlobalHotkeyTarget == .favorites,
                                height: globalHotkeyRecorderHeight,
                                textAlignment: .center,
                                usesContentDrivenWidth: true,
                                minimumWidth: globalHotkeyRecorderMinWidth,
                                maximumWidth: globalHotkeyRecorderMaxWidth,
                                fontSize: NSFont.systemFontSize,
                                fontWeight: .regular,
                                showsHoverClearButton: true,
                                canClear: !appState.settings.hotkeyFavoritesShortcut.isEmpty,
                                onBeginRecording: {
                                    recordingGlobalHotkeyTarget = .favorites
                                },
                                onCancelRecording: {
                                    if recordingGlobalHotkeyTarget == .favorites {
                                        recordingGlobalHotkeyTarget = nil
                                    }
                                },
                                onClear: {
                                    appState.updateSettings { settings in
                                        settings.hotkeyFavoritesShortcut = KeyboardShortcut()
                                    }
                                    if recordingGlobalHotkeyTarget == .favorites {
                                        recordingGlobalHotkeyTarget = nil
                                    }
                                },
                                onRecord: { event in
                                    recordHotkeyShortcut(from: event, target: .favorites)
                                }
                            )
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.vertical, 10)
                        .disabled(!appState.settings.globalHotkeyEnabled)
                        .opacity(appState.settings.globalHotkeyEnabled ? 1 : 0.45)
                    }
                }
            }

            settingsCard(
                title: "菜单栏唤出",
                subtitle: "打开后，点击菜单栏图标可以显示面板。",
                headerAccessory: {
                    Toggle("", isOn: menuBarActivationBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            ) {
                VStack(spacing: 0) {
                    settingRowWithNote(
                        title: "菜单栏显示最新一条内容",
                        note: "打开后，会在图标右侧显示最新一条记录；关闭后只保留图标。"
                    ) {
                        Toggle("", isOn: menuBarLatestPreviewBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 10)
                    .disabled(!appState.settings.menuBarStatusItemVisible)
                    .opacity(appState.settings.menuBarStatusItemVisible ? 1 : 0.45)
                }
            }

            settingsCard(
                title: "按住右键滑出",
                subtitle: "按住右键向右拖动即可打开面板，继续上下移动可切换记录，松手即可粘贴；启用前需要辅助功能权限。",
                headerAccessory: {
                    Toggle("", isOn: rightMouseDragActivationBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            ) {
                VStack(spacing: 0) {
                    settingControlBlock(
                        title: "横向触发距离",
                        description: "控制按住右键后，向右拖多远才展开面板。",
                        value: {
                            Text("\(Int(appState.settings.rightMouseDragTriggerDistance)) px")
                                .foregroundStyle(.secondary)
                        },
                        control: {
                            Slider(
                                value: settingsBinding(\.rightMouseDragTriggerDistance),
                                in: 24...160,
                                step: 4
                            )
                        }
                    )
                    .padding(.vertical, 10)
                    .disabled(!appState.settings.rightMouseDragActivationEnabled)
                    .opacity(appState.settings.rightMouseDragActivationEnabled ? 1 : 0.45)

                    if appState.settings.rightMouseDragActivationEnabled {
                        settingsDivider(opacity: 0.4)

                        if !appState.rightDragConflictNoticeDismissed {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(localized("会占用右键拖动操作"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.orange)

                                    Text(localized("开启后会接管按住右键后的拖动操作，可能与 BetterTouchTool 等手势软件冲突。只保留少量常用动作时，可以直接在下方配置附加手势。"))
                                        .font(.caption)
                                        .foregroundStyle(.orange.opacity(0.88))
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)

                                Button {
                                    appState.rightDragConflictNoticeDismissed = true
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.orange.opacity(0.9))
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)

                            settingsDivider(opacity: 0.4)
                        }

                        settingRow(title: "附加手势") {
                            Toggle("", isOn: Binding(
                                get: { auxiliaryGesturesEnabled },
                                set: { isEnabled in
                                    appState.updateSettings { settings in
                                        if settings.rightMouseAuxiliaryGestures.isEmpty && isEnabled {
                                            settings.rightMouseAuxiliaryGestures = [.default()]
                                        } else {
                                            for index in settings.rightMouseAuxiliaryGestures.indices {
                                                settings.rightMouseAuxiliaryGestures[index].enabled = isEnabled
                                            }
                                        }
                                    }
                                }
                            ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        if auxiliaryGesturesEnabled || !appState.settings.rightMouseAuxiliaryGestures.isEmpty {
                            settingsDivider(opacity: 0.4)

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .center) {
                                    Text(localized("附加手势列表"))
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Button(localized("添加手势")) {
                                        activeAuxiliaryDropdown = nil
                                        focusedAuxiliaryNoteID = nil
                                        addAuxiliaryGestureRow()
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    auxiliaryGestureHeaderRow

                                    if appState.settings.rightMouseAuxiliaryGestures.isEmpty {
                                        Text(localized("暂无附加手势。点击“添加手势”创建第一条规则。"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.vertical, 8)
                                    } else {
                                        ForEach(appState.settings.rightMouseAuxiliaryGestures) { gesture in
                                            auxiliaryGestureRow(gesture)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 12)
                            .disabled(!auxiliaryGesturesEnabled)
                            .opacity(auxiliaryGesturesEnabled ? 1 : 0.45)
                        }
                    }
                }
            }
        }
    }

    private var preferencesSection: some View {
        sectionPage(
            title: "使用偏好",
            subtitle: "调整粘贴方式、历史清理规则和完整预览方式。"
        ) {
            settingsCard(
                title: "粘贴方式",
                subtitle: "决定选中记录后如何回到原应用，以及已使用记录是否自动置顶。"
            ) {
                VStack(spacing: 0) {
                    settingRow(title: "自动粘贴（需要辅助功能权限）") {
                        Toggle("", isOn: settingsBinding(\.autoPasteEnabled))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }

                    settingsDivider(opacity: 0.4)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(localized("粘贴后记录位置"))
                            Spacer()
                            Picker(localized("粘贴后记录位置"), selection: settingsBinding(\.pastedItemPlacement)) {
                                ForEach(PastedItemPlacement.allCases, id: \.self) { placement in
                                    Text(placement.title).tag(placement)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(width: AppLocalization.isEnglish ? 170 : 140, alignment: .trailing)
                        }

                        Text(localized("可选择保持原位置，或在粘贴后将该条记录自动置顶。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                }
            }

            settingsCard(
                title: "数据存储",
                subtitle: "统一管理存储位置、记录数量、保存时长和磁盘占用。"
            ) {
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "externaldrive")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(localized("存储位置"))

                                Text(services.dataStorageLocationCompactDisplayPath)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(services.dataStorageLocationDisplayPath)
                            }

                            Spacer(minLength: 12)

                            VStack(alignment: .trailing, spacing: 8) {
                                Button(localized("修改…")) {
                                    services.chooseDataStorageLocation()
                                }

                                HStack(spacing: 12) {
                                    Button(localized("在访达中显示")) {
                                        services.revealDataStorageLocationInFinder()
                                    }
                                    .buttonStyle(.borderless)

                                    if !services.isUsingDefaultDataStorageLocation {
                                        Button(localized("恢复默认")) {
                                            services.resetDataStorageLocationToDefault()
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                            .disabled(services.isDataStorageMigrationInProgress)
                        }

                        if services.isDataStorageMigrationInProgress {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .controlSize(.small)

                                Text(services.dataStorageMigrationStatusText ?? "正在迁移数据…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 6)

                    settingsDivider(opacity: 0.35)

                    historyLimitRow(
                        icon: "internaldrive",
                        title: "占用磁盘空间上限",
                        subtitle: "当前约 \(formattedByteCount(appState.historyDiskUsageBytes))"
                    ) {
                        Stepper(value: settingsBinding(\.maxHistoryDiskUsageMB), in: 128...8192, step: 128) {
                            Text(formattedDiskLimitMB(appState.settings.maxHistoryDiskUsageMB))
                                .font(.body.monospacedDigit())
                        }
                        .frame(width: historyLimitAccessoryWidth, alignment: .trailing)
                    }

                    settingsDivider(opacity: 0.35)

                    historyLimitRow(
                        icon: "list.number",
                        title: "最大历史记录条数",
                        subtitle: "超过后自动清理最旧且未收藏的记录"
                    ) {
                        Stepper(value: settingsBinding(\.maxHistoryCount), in: 50...5000, step: 50) {
                            Text(
                                AppLocalization.isEnglish
                                    ? "\(appState.settings.maxHistoryCount)"
                                    : "\(appState.settings.maxHistoryCount) 条"
                            )
                                .font(.body.monospacedDigit())
                        }
                        .frame(width: historyLimitAccessoryWidth, alignment: .trailing)
                    }

                    settingsDivider(opacity: 0.35)

                    historyLimitRow(
                        icon: "clock.arrow.circlepath",
                        title: "存储时间限制",
                        subtitle: appState.settings.historyRetentionPreset.description
                    ) {
                        Picker("", selection: settingsBinding(\.historyRetentionPreset)) {
                            ForEach(HistoryRetentionPreset.allCases, id: \.self) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: historyLimitAccessoryWidth, alignment: .trailing)
                    }
                }
            }

            settingsCard(
                title: "完整预览",
                subtitle: "控制按空格查看内容的方式。中大文本默认只显示部分内容，不会展开全文。"
            ) {
                VStack(spacing: 0) {
                    settingRowWithNote(
                        title: "按空格预览",
                        note: "按空格查看当前记录的预览内容；中大文本只会显示部分内容。"
                    ) {
                        Toggle("", isOn: filePreviewEnabledBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 10)

                    settingsDivider(opacity: 0.35)

                    settingRowWithNote(
                        title: "连续预览",
                        note: "打开完整预览后，停留在其他可预览记录上会继续切换。"
                    ) {
                        Toggle("", isOn: continuousFilePreviewEnabledBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 10)
                    .disabled(!appState.settings.filePreviewEnabled)
                    .opacity(appState.settings.filePreviewEnabled ? 1 : 0.45)
                }
            }
        }
    }

    private var panelSection: some View {
        sectionPage(
            title: "剪贴面板",
            subtitle: "把常用标签放到前面，也可以在这里了解连续粘贴怎么用。"
        ) {
            settingsCard(
                title: "顶部标签",
                subtitle: "根据使用习惯个性化调整剪贴面板上的标签。",
                titleFont: .title2.weight(.bold)
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    panelGuidanceList

                    panelTabConfigurator
                        .padding(.vertical, 2)

                    settingRowWithNote(
                        title: "标签切换方式",
                        note: "默认鼠标悬停到标签上就会切换，也可以改成点击标签后再切换。",
                        supplementaryNote: appState.settings.panelTabSwitchMode == .click
                            ? "“按住右键滑出”的交互方式仅支持鼠标悬停切换标签。"
                            : nil,
                        supplementaryNoteColor: .orange
                    ) {
                        Picker("", selection: settingsBinding(\.panelTabSwitchMode)) {
                            ForEach(PanelTabSwitchMode.allCases, id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 128, alignment: .trailing)
                    }

                    panelTagDetailsDisclosure
                        .padding(.top, 2)
                }
            }

            settingsCard(
                title: "堆栈（连续粘贴）",
                subtitle: "把多条文字先放进待贴清单里，再按顺序一条条使用，适合填表、批量录入和重复操作。",
                titleFont: .title2.weight(.bold)
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    stackEntryIllustration
                    stackGuideDisclosure
                }
            }

            settingsCard(
                title: "常显时空闲透明度",
                subtitle: "仅在开启面板常显后，鼠标移出面板并点击外部时生效；回到面板内或打开子面板时会恢复不透明。",
                titleFont: .title2.weight(.bold)
            ) {
                let transparencyPercent = appState.settings.pinnedPanelIdleTransparencyPercent

                settingControlBlock(
                    title: "透明度",
                    description: "0% 表示保持不透明，相当于关闭空闲降透明；90% 表示非常透明，不提供完全透明。",
                    value: {
                        Text("\(transparencyPercent)%")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    },
                    control: {
                        Slider(
                            value: Binding(
                                get: { Double(appState.settings.pinnedPanelIdleTransparencyPercent) },
                                set: { newValue in
                                    appState.updateSettings { settings in
                                        settings.pinnedPanelIdleTransparencyPercent = Int(newValue.rounded())
                                    }
                                }
                            ),
                            in: 0...90,
                            step: 1
                        )
                    },
                    footer: {
                        if transparencyPercent == 0 {
                            Text(localized("已设为 0%：开启面板常显后，点击外部也会保持不透明。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if transparencyPercent >= 80 {
                            Text(localized("当前透明度较高：面板会更不挡视线，但列表内容可读性也会明显下降。"))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                )
                .padding(.vertical, 10)
            }
        }
    }

    private var generalSection: some View {
        sectionPage(
            title: "通用",
            subtitle: "管理系统权限、启动行为、界面外观和其他通用设置。"
        ) {
            settingsCard(
                title: "辅助功能权限",
                subtitle: "授权后可自动回到原应用并粘贴，也可使用按住右键滑出和附加手势；未授权时仍可复制后手动粘贴。"
            ) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized(appState.permissionGranted ? "已授权" : "未授权"))
                            .font(.headline)
                            .foregroundStyle(appState.permissionGranted ? .green : .orange)

                        Text(
                            localized(
                                appState.permissionGranted
                                ? "已授权后，选择记录会自动回到原应用并粘贴，也可以使用按住右键滑出和附加手势。"
                                : "未授权时，会先复制内容并回到原应用，由你手动粘贴；按住右键滑出和附加手势也不可用。"
                            )
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(localized(appState.permissionGranted ? "刷新状态" : "立即授权")) {
                        if appState.permissionGranted {
                            services.refreshPermissionStatus()
                        } else {
                            services.requestAccessibilityPermission()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 6)
            }

            settingsCard(
                title: "开机自动启动",
                subtitle: launchAtLoginSubtitle,
                contentTopSpacing: 0,
                headerAccessory: {
                    Toggle("", isOn: settingsBinding(\.launchAtLoginEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            ) {
                EmptyView()
            }

            settingsCard(
                title: "界面外观",
                subtitle: "设置窗口和剪贴面板的显示风格。",
                contentTopSpacing: 0,
                headerAccessory: {
                    Picker("", selection: settingsBinding(\.appearanceMode)) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: historyLimitAccessoryWidth, alignment: .trailing)
                }
            ) {
                EmptyView()
            }

            settingsCard(
                title: "语言",
                subtitle: "默认跟随系统；如果系统语言不是英语或中文，则自动使用 English。",
                contentTopSpacing: 0,
                headerAccessory: {
                    Picker("", selection: settingsBinding(\.language)) {
                        ForEach(AppLanguage.allCases, id: \.self) { language in
                            Text(language.optionTitle).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: historyLimitAccessoryWidth, alignment: .trailing)
                }
            ) {
                EmptyView()
            }

            settingsCard(
                title: "应用可见性",
                subtitle: "菜单栏图标和程序坞显示方式会统一放在这里管理。"
            ) {
                VStack(spacing: 0) {
                    settingRowWithNote(
                        title: "菜单栏图标",
                        note: "关闭后不会在菜单栏显示图标、右键菜单和最新一条内容摘要。"
                    ) {
                        Toggle("", isOn: menuBarStatusItemVisibilityBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 10)

                    settingsDivider(opacity: 0.35)

                    settingRowWithNote(
                        title: "程序坞图标",
                        note: "关闭后只会在设置面板打开时暂时显示，关闭设置面板后会从程序坞隐藏。"
                    ) {
                        Toggle("", isOn: dockIconVisibilityBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private var blacklistSection: some View {
        sectionPage(
            title: "应用例外",
            subtitle: "加入列表后，这些应用中的复制内容不会写入历史。"
        ) {
            applicationRuleCard(
                title: "不记录历史的应用",
                subtitle: "适合密码管理器、银行类工具等敏感应用。",
                emptyText: "还没有添加应用",
                bundleIDs: Array(appState.settings.blacklistedBundleIDs).sorted()
            ) {
                chooseApplications(for: .blacklist)
            } onRemove: { bundleID in
                appState.removeBlacklistBundleID(bundleID)
            }
        }
    }

    private var aboutSection: some View {
        sectionPage(
            title: "关于",
            subtitle: "了解 Edge Clip 的使用方式、数据保存方式和开源鸣谢。"
        ) {
            aboutHeroCard
            aboutCapabilitiesCard
            aboutPrivacyCard
            aboutOpenSourceCard
        }
    }

    private var launchAtLoginSubtitle: String {
        appState.settings.launchAtLoginEnabled
            ? localized("Edge Clip 会跟随系统自动启动。")
            : localized("系统重启后需要手动启动 Edge Clip。")
    }

    private var aboutHeroCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 18) {
                aboutAppIcon
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("Edge Clip")
                            .font(.system(size: 30, weight: .bold, design: .rounded))

                        Text("v\(appVersion)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                            )
                    }

                    Text(localized("边缘唤出的 macOS 剪贴板工具"))
                        .font(.system(size: 17, weight: .semibold))

                    Text(localized("把最近复制过的文本、图片和文件收进一个随手可开的侧边面板里，方便继续查找、预览和回贴。"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Link(destination: edgeClipWebsiteURL) {
                            Label(localized("访问官网"), systemImage: "arrow.up.forward.app")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.bordered)

                        Button {
                            appState.requestOnboardingPresentation()
                        } label: {
                            Label(localized("查看欢迎引导"), systemImage: "sparkles")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            aboutHighlightGrid
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settingsCardBackground(cornerRadius: 18, tintOpacity: colorScheme == .dark ? 0.08 : 0.42))
    }

    private var aboutCapabilitiesCard: some View {
        settingsCard(
            title: "日常使用",
            subtitle: "从打开、定位到回贴，尽量减少打断和重复操作。",
            showsLeadingAccentMarker: false
        ) {
            VStack(spacing: 0) {
                aboutFeatureRow(
                    icon: "cursorarrow.motionlines",
                    title: "就近打开面板",
                    detail: "支持边缘唤出、快捷键、菜单栏和右键滑出几种方式，方便在不同使用习惯下快速唤出。"
                )
                settingsDivider(opacity: 0.35)
                aboutFeatureRow(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "快速定位内容",
                    detail: "统一整理文本、图片和文件历史，支持分类筛选、关键词搜索和收藏。"
                )
                settingsDivider(opacity: 0.35)
                aboutFeatureRow(
                    icon: "rectangle.and.text.magnifyingglass",
                    title: "预览后再决定",
                    detail: "可以先查看内容，再决定是否回贴、收藏，或继续整理成堆栈。"
                )
                settingsDivider(opacity: 0.35)
                aboutFeatureRow(
                    icon: "square.stack.3d.up",
                    title: "连续回贴更顺手",
                    detail: "支持 1-9 快捷编号和剪贴板堆栈，适合批量录入、表单填写和重复操作。"
                )
            }
        }
    }

    private var aboutPrivacyCard: some View {
        settingsCard(
            title: "数据与隐私",
            subtitle: "默认本地保存，按需授权，并明确说明默认敏感应用保护与可能的网络访问。",
            showsLeadingAccentMarker: false,
            headerAccessory: {
            Link(destination: edgeClipPrivacyPolicyURL) {
                Text(localized("查看详细的数据与隐私声明"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
        ) {
            VStack(spacing: 0) {
                aboutFeatureRow(
                    icon: "internaldrive",
                    title: "历史记录保存在本机",
                    detail: "文本、图片和文件历史默认只保存在这台 Mac 上，不依赖账号体系或云端同步。"
                )
                settingsDivider(opacity: 0.35)
                aboutFeatureRow(
                    icon: "hand.raised",
                    title: "权限按需开启",
                    detail: "只有全局唤出、自动粘贴和部分快捷操作需要额外系统授权，未授权时仍可正常记录基础历史。"
                )
                settingsDivider(opacity: 0.35)
                aboutFeatureRow(
                    icon: "shield.lefthalf.filled",
                    title: "默认敏感应用会优先保护",
                    detail: "新安装时会默认把 Apple Passwords、Keychain Access、1Password 和 Bitwarden 加入应用例外；你也可以自行增删。"
                )
                settingsDivider(opacity: 0.35)
                aboutFeatureRow(
                    icon: "network",
                    title: "可能的网络访问",
                    detail: "应用本身不做账号同步或后台上传；只有在剪贴板内容本身带有远程图片地址，且需要把它落成图片记录时，才可能访问对应地址。"
                )
            }
        }
    }

    private var aboutOpenSourceCard: some View {
        settingsCard(
            title: "开源鸣谢",
            subtitle: "Edge Clip 在交互思路和体验打磨上，参考了多款优秀的开源项目。",
            showsLeadingAccentMarker: false
        ) {
            Button {
                isOpenSourceCreditsPresented = true
            } label: {
                Label(localized("查看清单"), systemImage: "arrow.up.forward.app")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text(localized("你可以在这里查看项目来源、对应仓库，以及它们帮助改进的使用体验。"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: 10, alignment: .leading)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(OpenSourceProjectReference.currentMITProjects) { project in
                        aboutSourceChip(project.name)
                    }
                }
            }
        }
    }

    private func sectionPage<Content: View>(
        title: String,
        subtitle: String,
        subtitleColor: Color = .secondary,
        @ViewBuilder content: () -> Content
    ) -> some View {
        sectionPage(
            title: title,
            subtitle: subtitle,
            subtitleColor: subtitleColor,
            content: content,
            footer: { EmptyView() }
        )
    }

    private func sectionPage<Content: View, Footer: View>(
        title: String,
        subtitle: String,
        subtitleColor: Color = .secondary,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(spacing: 0) {
            settingsStickyHeader(
                title: title,
                subtitle: subtitle,
                subtitleColor: subtitleColor
            )
            .padding(.horizontal, pageHorizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(settingsHeaderBackground)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    settingsDivider(opacity: 0.18)
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.03),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 8)
                }
                .allowsHitTesting(false)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    content()
                }
                .padding(.horizontal, pageHorizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func settingsStickyHeader(
        title: String,
        subtitle: String,
        subtitleColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized(title))
                .font(.system(size: 30, weight: .bold, design: .rounded))

            Text(localized(subtitle))
                .font(.subheadline)
                .foregroundStyle(subtitleColor)
        }
    }

    private var interactionSectionSubtitle: String {
        if interactionMethodsAreAllDisabled {
            return localized("请至少保留一种唤出方式，否则无法快速打开剪贴面板。")
        }

        return localized("选择一种顺手的唤出方式，再按需要调整触发条件。")
    }

    private var interactionSectionSubtitleColor: Color {
        if interactionMethodsAreAllDisabled {
            return .red
        }

        return .secondary
    }

    private var interactionMethodsAreAllDisabled: Bool {
        !appState.settings.edgeActivationEnabled &&
        !appState.settings.globalHotkeyEnabled &&
        !appState.settings.menuBarActivationEnabled &&
        !appState.settings.rightMouseDragActivationEnabled
    }

    private var edgeActivationPlacementModeBinding: Binding<EdgeActivationPlacementMode> {
        Binding(
            get: { appState.settings.edgeActivationPlacementMode },
            set: { newMode in
                DispatchQueue.main.async {
                    appState.updateSettings { settings in
                        settings.edgeActivationPlacementMode = newMode
                    }
                }
            }
        )
    }

    private var edgeActivationSideBinding: Binding<EdgeActivationSide> {
        Binding(
            get: { appState.settings.edgeActivationSide },
            set: { newSide in
                DispatchQueue.main.async {
                    appState.updateSettings { settings in
                        settings.edgeActivationSide = newSide
                    }
                }
            }
        )
    }

    private var edgeCustomPositionDisplayValue: Double {
        edgeCustomPositionDraft ?? appState.settings.edgeActivationCustomVerticalPosition
    }

    private var edgeCustomPositionPreviewLayout: EdgePanelController.EdgeActivationLayout? {
        services.edgeActivationPreviewLayout(customVerticalPosition: edgeCustomPositionDisplayValue)
    }

    private var edgeCustomPositionControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("边缘激活位置"))

                    Text(localized("拖动蓝条调整面板出现高度。所选边缘会同步显示实际激活区域，松手后生效。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                Text(edgeCustomPositionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let metrics = edgeCustomPositionScrubberMetrics(trackWidth: proxy.size.width)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))

                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05), lineWidth: 1)

                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.accentColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.55), lineWidth: 1)
                        )
                        .frame(width: metrics.handleWidth, height: 22)
                        .shadow(
                            color: Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.14),
                            radius: 8,
                            y: 2
                        )
                        .offset(x: metrics.handleOffset)
                }
                .frame(height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateEdgeCustomPositionDrag(
                                locationX: value.location.x,
                                trackWidth: proxy.size.width,
                                handleWidth: metrics.handleWidth,
                                currentHandleOffset: metrics.handleOffset
                            )
                        }
                        .onEnded { value in
                            finishEdgeCustomPositionDrag(
                                locationX: value.location.x,
                                trackWidth: proxy.size.width,
                                handleWidth: metrics.handleWidth,
                                currentHandleOffset: metrics.handleOffset
                            )
                        }
                )
            }
            .frame(height: 28)

            HStack {
                Text(localized("靠下"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(localized("靠上"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var edgeCustomPositionSummary: String {
        let position = edgeCustomPositionDisplayValue
        switch position {
        case ..<0.25:
            return localized("当前靠上")
        case ..<0.75:
            return localized("当前居中")
        default:
            return localized("当前靠下")
        }
    }

    private func edgeCustomPositionScrubberMetrics(trackWidth: CGFloat) -> EdgeCustomPositionScrubberMetrics {
        let safeTrackWidth = max(trackWidth, 1)

        guard let layout = edgeCustomPositionPreviewLayout else {
            let fallbackHandleWidth = safeTrackWidth * 0.72
            return EdgeCustomPositionScrubberMetrics(
                handleWidth: fallbackHandleWidth,
                handleOffset: (safeTrackWidth - fallbackHandleWidth) * CGFloat(1 - edgeCustomPositionDisplayValue)
            )
        }

        let guideHeight = max(layout.guideFrame.height, layout.panelFrame.height, 1)
        let handleWidth = safeTrackWidth * (layout.panelFrame.height / guideHeight)
        let bottomBlankHeight = max(0, layout.panelFrame.minY - layout.guideFrame.minY)
        let handleOffset = min(
            max(0, safeTrackWidth * (bottomBlankHeight / guideHeight)),
            max(0, safeTrackWidth - handleWidth)
        )

        return EdgeCustomPositionScrubberMetrics(
            handleWidth: handleWidth,
            handleOffset: handleOffset
        )
    }

    private func updateEdgeCustomPositionDrag(
        locationX: CGFloat,
        trackWidth: CGFloat,
        handleWidth: CGFloat,
        currentHandleOffset: CGFloat
    ) {
        guard appState.settings.edgeActivationEnabled else { return }

        if !isAdjustingEdgeCustomPosition {
            isAdjustingEdgeCustomPosition = true
        }

        if edgeCustomPositionDragPointerOffset == nil {
            edgeCustomPositionDragPointerOffset = min(
                max(0, locationX - currentHandleOffset),
                handleWidth
            )
        }

        let travelWidth = max(1, trackWidth - handleWidth)
        let pointerOffset = min(
            max(0, edgeCustomPositionDragPointerOffset ?? handleWidth / 2),
            handleWidth
        )
        let leading = min(
            max(0, locationX - pointerOffset),
            travelWidth
        )
        let position = Double(1 - (leading / travelWidth))
        edgeCustomPositionDraft = position
        services.previewEdgeActivationCustomPosition(position)
    }

    private func finishEdgeCustomPositionDrag(
        locationX: CGFloat,
        trackWidth: CGFloat,
        handleWidth: CGFloat,
        currentHandleOffset: CGFloat
    ) {
        updateEdgeCustomPositionDrag(
            locationX: locationX,
            trackWidth: trackWidth,
            handleWidth: handleWidth,
            currentHandleOffset: currentHandleOffset
        )

        let finalValue = edgeCustomPositionDisplayValue
        isAdjustingEdgeCustomPosition = false
        edgeCustomPositionDragPointerOffset = nil
        services.hideEdgeActivationPreview()

        DispatchQueue.main.async {
            appState.updateSettings { settings in
                settings.edgeActivationCustomVerticalPosition = finalValue
            }
            if edgeCustomPositionDraft == finalValue {
                edgeCustomPositionDraft = nil
            }
        }
    }

    private func dismissEdgeActivationPreviewAdjustments() {
        isAdjustingEdgeCustomPosition = false
        edgeCustomPositionDraft = nil
        edgeCustomPositionDragPointerOffset = nil
        services.hideEdgeActivationPreview()
    }

    private struct EdgeCustomPositionScrubberMetrics {
        let handleWidth: CGFloat
        let handleOffset: CGFloat
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { appState.settings[keyPath: keyPath] },
            set: { newValue in
                appState.updateSettings { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var hotkeyPanelModifierBinding: Binding<HotkeyModifier> {
        Binding(
            get: { appState.settings.hotkeyPanelModifier },
            set: { newValue in
                guard appState.settings.hotkeyFavoritesModifier != newValue else {
                    services.showTransientNotice(localized("双击修饰键不能重复；请为收藏标签选择其他修饰键。"))
                    return
                }
                appState.updateSettings { settings in
                    settings.hotkeyPanelModifier = newValue
                }
            }
        )
    }

    private var hotkeyFavoritesModifierBinding: Binding<HotkeyModifier?> {
        Binding(
            get: { appState.settings.hotkeyFavoritesModifier },
            set: { newValue in
                guard newValue != appState.settings.hotkeyPanelModifier else {
                    services.showTransientNotice(localized("双击修饰键不能重复；请为收藏标签选择其他修饰键。"))
                    return
                }
                appState.updateSettings { settings in
                    settings.hotkeyFavoritesModifier = newValue
                }
            }
        )
    }

    private func hotkeyShortcutDisplayText(for target: GlobalHotkeyRecorderTarget) -> String {
        if recordingGlobalHotkeyTarget == target {
            return localized("请录入快捷键")
        }

        let shortcut: KeyboardShortcut
        switch target {
        case .panel:
            shortcut = appState.settings.hotkeyPanelShortcut
        case .favorites:
            shortcut = appState.settings.hotkeyFavoritesShortcut
        }
        return shortcut.isEmpty ? localized("点击录制") : shortcut.fullDisplayText
    }

    private func recordHotkeyShortcut(from event: NSEvent, target: GlobalHotkeyRecorderTarget) {
        guard let shortcut = KeyboardShortcut.from(event: event) else { return }
        guard shortcut.hasAnyModifier else {
            services.showTransientNotice(localized("组合按键至少需要一个修饰键。"))
            return
        }

        let conflictingShortcut = target == .panel
            ? appState.settings.hotkeyFavoritesShortcut
            : appState.settings.hotkeyPanelShortcut
        guard !shortcut.conflicts(with: conflictingShortcut) else {
            services.showTransientNotice(localized("组合按键不能重复；请为两个动作录入不同快捷键。"))
            return
        }

        appState.updateSettings { settings in
            switch target {
            case .panel:
                settings.hotkeyPanelShortcut = shortcut
            case .favorites:
                settings.hotkeyFavoritesShortcut = shortcut
            }
        }
        if recordingGlobalHotkeyTarget == target {
            recordingGlobalHotkeyTarget = nil
        }
    }

    private var menuBarStatusItemVisibilityBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.menuBarStatusItemVisible },
            set: { isVisible in
                let shouldDisableMenuBarActivation = !isVisible && appState.settings.menuBarActivationEnabled

                appState.updateSettings { settings in
                    settings.menuBarStatusItemVisible = isVisible
                    if shouldDisableMenuBarActivation {
                        settings.menuBarActivationEnabled = false
                    }
                }
                services.refreshMenuBarStatusItem()

                if shouldDisableMenuBarActivation {
                    services.showTransientNotice(
                        localized("这将同时关闭菜单栏唤出剪贴面板的功能。"),
                        tone: .warning,
                        duration: 5
                    )
                }
            }
        )
    }

    private var dockIconVisibilityBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.dockIconVisible },
            set: { isVisible in
                appState.updateSettings { settings in
                    settings.dockIconVisible = isVisible
                }

                guard !isVisible else { return }

                let noticeMessage = appState.settings.menuBarStatusItemVisible
                    ? localized("下次请从菜单栏或者访达的应用程序入口打开设置面板")
                    : localized("下次请从访达的应用程序入口打开设置面板")
                services.showTransientNotice(
                    noticeMessage,
                    tone: .info,
                    duration: 5
                )
            }
        )
    }

    private var menuBarActivationBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.menuBarActivationEnabled },
            set: { isEnabled in
                let shouldEnableMenuBarIcon = isEnabled && !appState.settings.menuBarStatusItemVisible

                appState.updateSettings { settings in
                    if shouldEnableMenuBarIcon {
                        settings.menuBarStatusItemVisible = true
                    }
                    settings.menuBarActivationEnabled = isEnabled
                }
                services.refreshMenuBarStatusItem()

                if shouldEnableMenuBarIcon {
                    services.showTransientNotice(
                        localized("这将同时开启菜单栏图标。"),
                        tone: .info,
                        duration: 5
                    )
                }
            }
        )
    }

    private var menuBarLatestPreviewBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.menuBarShowsLatestPreview },
            set: { isEnabled in
                appState.updateSettings { settings in
                    settings.menuBarShowsLatestPreview = isEnabled
                }
                services.refreshMenuBarStatusItem()
            }
        )
    }

    private var filePreviewEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.filePreviewEnabled },
            set: { isEnabled in
                appState.updateSettings { settings in
                    settings.filePreviewEnabled = isEnabled
                }
            }
        )
    }

    private var continuousFilePreviewEnabledBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.continuousFilePreviewEnabled },
            set: { isEnabled in
                let wasEnabled = appState.settings.continuousFilePreviewEnabled
                appState.updateSettings { settings in
                    settings.continuousFilePreviewEnabled = isEnabled
                }

                if isEnabled && !wasEnabled {
                    services.showTransientNotice(
                        localized("连续预览会占用更多性能，遇到大文件或大量历史记录时建议按需开启。"),
                        tone: .info,
                        duration: 5
                    )
                }
            }
        )
    }

    private var rightMouseDragActivationBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.rightMouseDragActivationEnabled },
            set: { isEnabled in
                if isEnabled {
                    services.refreshPermissionStatus()
                    guard appState.permissionGranted else {
                        services.showTransientNotice(
                            localized("按住右键滑出需要辅助功能权限，正在为你发起系统授权申请。"),
                            tone: .warning,
                            duration: 3.4
                        )
                        services.requestAccessibilityPermission()
                        return
                    }
                }

                let wasEnabled = appState.settings.rightMouseDragActivationEnabled
                appState.updateSettings { settings in
                    settings.rightMouseDragActivationEnabled = isEnabled
                }
                if isEnabled && !wasEnabled {
                    appState.rightDragConflictNoticeDismissed = false
                }
            }
        )
    }

    private var auxiliaryGesturesEnabled: Bool {
        appState.settings.rightMouseAuxiliaryGestures.contains(where: \.enabled)
    }

    private func auxiliaryGestureBinding<Value>(
        gestureID: UUID,
        _ keyPath: WritableKeyPath<RightMouseAuxiliaryGestureSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                appState.settings.rightMouseAuxiliaryGestures.first(where: { $0.id == gestureID })?[keyPath: keyPath]
                ?? RightMouseAuxiliaryGestureSettings.default()[keyPath: keyPath]
            },
            set: { newValue in
                appState.updateSettings { settings in
                    guard let index = settings.rightMouseAuxiliaryGestures.firstIndex(where: { $0.id == gestureID }) else { return }
                    settings.rightMouseAuxiliaryGestures[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func settingsCard<Content: View, HeaderAccessory: View>(
        title: String,
        subtitle: String? = nil,
        titleFont: Font = .title3.weight(.bold),
        showsLeadingAccentMarker: Bool = true,
        contentTopSpacing: CGFloat = 12,
        @ViewBuilder headerAccessory: () -> HeaderAccessory = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized(title))
                        .font(titleFont)

                    if let subtitle, !subtitle.isEmpty {
                        Text(localized(subtitle))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)
                headerAccessory()
            }

            content()
                .padding(.top, contentTopSpacing)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(settingsCardBackground(cornerRadius: 16))
        .overlay(alignment: .topLeading) {
            if showsLeadingAccentMarker {
                settingsCardAccentMarker(hasSubtitle: subtitle?.isEmpty == false)
                    .padding(.leading, 0)
                    .padding(.top, 20)
                    .allowsHitTesting(false)
            }
        }
    }

    private func settingsCardAccentMarker(hasSubtitle: Bool) -> some View {
        let fullWidth: CGFloat = 8
        let visibleWidth: CGFloat = 4
        let markerHeight: CGFloat = hasSubtitle ? 36 : 22

        return RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(Color.accentColor)
            .frame(width: fullWidth, height: markerHeight)
            .frame(width: visibleWidth, height: markerHeight, alignment: .trailing)
            .clipped()
    }

    private func settingsDivider(opacity: Double = 0.35) -> some View {
        Divider()
            .opacity(opacity)
            .allowsHitTesting(false)
    }

    private var settingsPageBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ]
                : [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var settingsHeaderBackground: some View {
        Rectangle()
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.02 : 0.16))
            )
    }

    private func settingsCardBackground(
        cornerRadius: CGFloat,
        tintOpacity: Double? = nil
    ) -> some View {
        let overlayOpacity = tintOpacity ?? (colorScheme == .dark ? 0.04 : 0.82)
        let baseFill = colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.92)
            : Color.white.opacity(0.90)

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseFill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(overlayOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.04),
                radius: colorScheme == .dark ? 10 : 14,
                y: 4
            )
    }

    private var aboutHighlightGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                aboutHighlightTile(
                    icon: "square.stack.3d.up",
                    title: "多类型历史",
                    detail: "文本、图片和文件都能在同一个面板里快速找到。"
                )
                aboutHighlightTile(
                    icon: "text.magnifyingglass",
                    title: "先看再贴",
                    detail: "支持搜索、预览和收藏，减少误贴和反复切换。"
                )
            }

            HStack(alignment: .top, spacing: 12) {
                aboutHighlightTile(
                    icon: "keyboard",
                    title: "快速回贴",
                    detail: "支持按下数字键粘贴和堆栈顺序粘贴，适合高频录入。"
                )
                aboutHighlightTile(
                    icon: "internaldrive",
                    title: "本地优先",
                    detail: "历史记录默认保存在本机，数据掌握在你自己手里。"
                )
            }
        }
    }

    private func aboutHighlightTile(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(localized(title))
                    .font(.system(size: 15, weight: .semibold))

                Text(localized(detail))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(settingsCardBackground(cornerRadius: 14, tintOpacity: colorScheme == .dark ? 0.06 : 0.36))
    }

    private func aboutSourceChip(_ title: String) -> some View {
        Text(localized(title))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.84))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func aboutFeatureRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(localized(title))
                    .font(.body.weight(.semibold))

                Text(localized(detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private func applicationRuleCard(
        title: String,
        subtitle: String,
        emptyText: String,
        bundleIDs: [String],
        onSelect: @escaping () -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        settingsCard(
            title: title,
            subtitle: subtitle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Button(localized("添加应用")) {
                    focusedAuxiliaryNoteID = nil
                    activeAuxiliaryDropdown = nil
                    onSelect()
                }
                .buttonStyle(.borderedProminent)

                settingsDivider(opacity: 0.4)

                applicationRuleList(
                    bundleIDs: bundleIDs,
                    emptyText: emptyText,
                    onRemove: onRemove
                )
            }
        }
    }

    private func settingRow<Content: View>(
        title: String,
        titleFont: Font = .body,
        @ViewBuilder accessory: () -> Content
    ) -> some View {
        HStack {
            Text(localized(title))
                .font(titleFont)

            Spacer()
            accessory()
        }
        .padding(.vertical, 10)
    }

    private func settingRowWithNote<Content: View>(
        title: String,
        note: String,
        supplementaryNote: String? = nil,
        supplementaryNoteColor: Color = .secondary,
        @ViewBuilder accessory: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(localized(title))
                Spacer()
                accessory()
                    .fixedSize(horizontal: true, vertical: false)
            }

            if !note.isEmpty {
                Text(localized(note))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let supplementaryNote, !supplementaryNote.isEmpty {
                Text(localized(supplementaryNote))
                    .font(.caption)
                    .foregroundStyle(supplementaryNoteColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func settingControlBlock<Value: View, Control: View>(
        title: String,
        description: String,
        @ViewBuilder value: () -> Value,
        @ViewBuilder control: () -> Control
    ) -> some View {
        settingControlBlock(
            title: title,
            description: description,
            value: value,
            control: control,
            footer: { EmptyView() }
        )
    }

    private func settingControlBlock<Value: View, Control: View, Footer: View>(
        title: String,
        description: String,
        @ViewBuilder value: () -> Value,
        @ViewBuilder control: () -> Control,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(localized(title))

                Spacer(minLength: 12)

                value()
            }

            Text(localized(description))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            control()
            footer()
        }
    }

    private var panelGuidanceRows: [(symbol: String, title: String)] {
        [
            (
                symbol: "hand.tap",
                title: "按住蓝色标签可拖动排序"
            ),
            (
                symbol: "arrow.left.arrow.right.circle",
                title: "按住末尾的灰色标签并拖动到蓝色标签区域可替换"
            ),
            (
                symbol: "lock.fill",
                title: "“全部”和“收藏”不可被替换和移动位置"
            )
        ]
    }

    private var panelGuidanceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(panelGuidanceRows, id: \.title) { item in
                panelGuidanceRow(symbol: item.symbol, title: item.title)
            }
        }
    }

    private func panelGuidanceRow(symbol: String, title: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.10))
                )

            Text(localized(title))
                .font(.system(size: 14.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var panelTagDescriptionRows: [(title: String, detail: String)] {
        [
            ("全部", "查看所有历史记录。"),
            ("收藏", "只看你标记为收藏的内容。"),
            ("文本", "句子、段落、聊天内容等普通文字。"),
            ("图片", "截图、照片和其他图片内容。"),
            ("文件", "文档、附件、文件夹等项目。"),
            ("代码", "像代码的内容会集中放在这里，找起来更快。"),
            ("网址", "复制的链接或网页地址会出现在这里。")
        ]
    }

    private var panelTagDetailsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isPanelTagDetailsExpanded.toggle()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Text(localized("查看每个标签会显示什么"))
                        .font(.subheadline)

                    Spacer(minLength: 12)

                    Image(systemName: isPanelTagDetailsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPanelTagDetailsExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(panelTagDescriptionRows, id: \.title) { item in
                        panelTagDescriptionRow(title: item.title, detail: item.detail)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func panelTagDescriptionRow(title: String, detail: String) -> some View {
        Text("\(localized(title))：\(localized(detail))")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 3)
    }

    private var stackGuideDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                isStackGuideExpanded.toggle()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Text(localized("详细了解堆栈（连续粘贴）功能如何使用"))
                        .font(.subheadline)

                    Spacer(minLength: 12)

                    Image(systemName: isStackGuideExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isStackGuideExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    stackGuideRow(
                        number: 1,
                        title: "先找到入口",
                        detail: "打开剪贴面板后，点击右上角高亮的堆叠图标就会进入堆栈。按空格查看完整预览时，右上角也有同样的入口。"
                    )

                    settingsDivider(opacity: 0.35)

                    stackGuideRow(
                        number: 2,
                        title: "把内容放进去",
                        detail: "进入后，在其他应用里继续复制文字，新的内容会加入待贴清单。查看可完整预览的文本时，也可以直接把当前内容带进堆栈。想把一整段内容拆成多条时，也可以点右上角的“数据处理”来整理。"
                    )

                    settingsDivider(opacity: 0.35)

                    stackGuideRow(
                        number: 3,
                        title: "按你的顺序整理",
                        detail: "可以拖动调整顺序，也可以删掉暂时不用的内容。最上面会标出“下一条”，方便你一眼看清接下来会先用哪一项。"
                    )

                    settingsDivider(opacity: 0.35)

                    stackGuideRow(
                        number: 4,
                        title: "想贴哪条就用哪条",
                        detail: "每一条左侧都有插入按钮。点哪一条，就会把哪一条直接送回当前输入框；用掉之后，下面的内容会自动补上来。"
                    )

                    settingsDivider(opacity: 0.35)

                    stackGuideRow(
                        number: 5,
                        title: "也可以顺着一直贴下去",
                        detail: "如果你更习惯键盘，回到目标位置后继续按 Command + V，Edge Clip 会按当前顺序一条条送出内容，适合连续填写多项信息。"
                    )

                    settingsDivider(opacity: 0.35)

                    stackPermissionNotice
                        .padding(.top, 12)
                }
                .padding(.top, 2)
            }
        }
    }

    private var panelTabConfigurator: some View {
        HStack(spacing: 6) {
            ForEach(Array(panelTabPreviewItems.enumerated()), id: \.offset) { index, item in
                switch item.role {
                case .fixed:
                    fixedPanelTabChip(item.tab)
                case .active(let slotIndex):
                    replaceablePanelTabSlot(index: slotIndex, tab: item.tab)
                case .standby:
                    standbyPanelTabChip(item.tab)
                }

                if index == 4 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: 20)
                        .padding(.horizontal, 2)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.4, dash: [6, 6]))
                .foregroundStyle(Color.primary.opacity(0.18))
        )
    }

    private var standbyPanelTabs: [PanelTab] {
        let activeTabs = PanelTab.sanitizedReplaceableSlots(from: appState.settings.panelReplaceableTabs)
        return PanelTab.replaceableChoices.filter { !activeTabs.contains($0) }
    }

    private var panelTabPreviewItems: [(tab: PanelTab, role: PanelPreviewRole)] {
        let activeTabs = Array(PanelTab.sanitizedReplaceableSlots(from: appState.settings.panelReplaceableTabs).prefix(3))
        let standbyTabs = PanelTab.replaceableChoices.filter { !activeTabs.contains($0) }

        var items: [(PanelTab, PanelPreviewRole)] = [
            (.all, .fixed),
            (.favorites, .fixed)
        ]
        items.append(contentsOf: activeTabs.enumerated().map { ($0.element, .active($0.offset)) })
        items.append(contentsOf: standbyTabs.map { ($0, .standby) })
        return items
    }

    private enum PanelPreviewRole {
        case fixed
        case active(Int)
        case standby
    }

    private func fixedPanelTabChip(_ tab: PanelTab) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 10, weight: .semibold))
            Text(tab.title)
                .font(.system(size: 12, weight: .semibold))
            Image(systemName: "lock.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.blue.opacity(0.07))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    private func replaceablePanelTabSlot(index: Int, tab: PanelTab) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 10, weight: .semibold))
            Text(tab.title)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.blue.opacity(0.07))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .onDrag {
            NSItemProvider(object: tab.rawValue as NSString)
        }
        .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
            handlePanelTabDrop(providers: providers, toSlot: index)
        }
    }

    private func standbyPanelTabChip(_ tab: PanelTab) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 10, weight: .semibold))

            Text(tab.title)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Capsule(style: .continuous))
        .fixedSize(horizontal: true, vertical: false)
        .onDrag {
            return NSItemProvider(object: tab.rawValue as NSString)
        }
    }

    private func handlePanelTabDrop(providers: [NSItemProvider], toSlot index: Int) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let rawValue = (object as? NSString) as String?,
                  let tab = PanelTab(rawValue: rawValue)
            else {
                return
            }

            DispatchQueue.main.async {
                appState.updateSettings { settings in
                    var slots = PanelTab.sanitizedReplaceableSlots(from: settings.panelReplaceableTabs)
                    guard slots.indices.contains(index),
                          PanelTab.replaceableChoices.contains(tab) else {
                        return
                    }

                    if let currentIndex = slots.firstIndex(of: tab) {
                        slots.swapAt(currentIndex, index)
                    } else {
                        slots[index] = tab
                    }

                    settings.panelReplaceableTabs = slots
                }
            }
        }

        return true
    }

    private var stackEntryIllustration: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                stackSpotlightPanel(for: .panel)
                stackSpotlightPanel(for: .preview)
            }
        }
    }

    private func stackSpotlightPanel(for variant: StackSpotlightVariant) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(variant.title)
                .font(.system(size: 14, weight: .semibold))

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: variant == .panel ? 14 : 8) {
                    stackSpotlightHeader(for: variant)
                    stackSpotlightBody(for: variant)
                }
                .padding(12)
                .opacity(0.34)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                stackSpotlightToolbar(for: variant)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .frame(height: variant.frameHeight)

            Text(variant.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func stackSpotlightHeader(for variant: StackSpotlightVariant) -> some View {
        switch variant {
        case .panel:
            HStack(alignment: .center) {
                dimmedCircleToolbarButton(symbol: "xmark")
                Spacer()
                Color.clear
                    .frame(width: 96, height: 28)
            }
        case .preview:
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    dimmedBar(width: 88, height: 10)
                    dimmedBar(width: 62, height: 7)
                }

                Spacer()

                Color.clear
                    .frame(width: 62, height: 24)
            }
        }
    }

    @ViewBuilder
    private func stackSpotlightBody(for variant: StackSpotlightVariant) -> some View {
        switch variant {
        case .panel:
            HStack(spacing: 8) {
                spotlightDimmedTabChip(.all, isSelected: true)
                spotlightDimmedTabChip(.favorites)
                spotlightDimmedTabChip(.image)
                spotlightDimmedTabChip(.text)
            }
        case .preview:
            VStack(alignment: .leading, spacing: 6) {
                dimmedBar(width: 122, height: 8)

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                    .frame(height: 18)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                        .frame(width: 60, height: 14)

                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                        .frame(width: 74, height: 14)
                }
            }
        }
    }

    @ViewBuilder
    private func stackSpotlightToolbar(for variant: StackSpotlightVariant) -> some View {
        switch variant {
        case .panel:
            HStack(spacing: 10) {
                dimmedCircleToolbarButton(symbol: "magnifyingglass")
                dimmedCircleToolbarButton(symbol: "plus")
                spotlightStackToolbarButton
                dimmedCircleToolbarButton(symbol: "pin")
            }
        case .preview:
            HStack(spacing: 10) {
                spotlightStackToolbarButton
                dimmedCircleToolbarButton(symbol: "xmark")
            }
        }
    }

    private func dimmedCircleToolbarButton(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.78))
            .frame(width: 28, height: 28)
            .background(
                Circle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
            )
            .overlay(
                Circle()
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
            )
    }

    private var spotlightStackToolbarButton: some View {
        StackGlyphIcon(isSelected: true)
            .frame(width: 14, height: 14)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.94))
            )
            .overlay(
                Circle()
                    .stroke(Color.accentColor.opacity(0.88), lineWidth: 2)
            )
            .shadow(
                color: Color.accentColor.opacity(colorScheme == .dark ? 0.42 : 0.22),
                radius: 10,
                y: 4
            )
    }

    private func spotlightDimmedTabChip(_ tab: PanelTab, isSelected: Bool = false) -> some View {
        HStack(spacing: 6) {
            Image(systemName: tab.symbolName)
                .font(.system(size: 9, weight: .semibold))

            Text(tab.title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(Color.primary.opacity(0.84))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(isSelected ? (colorScheme == .dark ? 0.18 : 0.12) : (colorScheme == .dark ? 0.12 : 0.06)))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 1)
        )
    }

    private func dimmedBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10))
            .frame(width: width, height: height)
    }

    private func stackGuideRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(localized(title))
                    .font(.body.weight(.semibold))

                Text(localized(detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var stackPermissionNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "keyboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.10))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(localized("想直接用复制和粘贴快捷键连续操作？"))
                    .font(.system(size: 14, weight: .semibold))

                Text(localized("如果你想直接用 Command + C 和 Command + V 连续收集和粘贴，请先在“通用”里打开辅助功能权限。未开启时，堆栈仍然可以手动整理、查看和继续使用。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private enum StackSpotlightVariant {
        case panel
        case preview

        var title: String {
            switch self {
            case .panel:
                return AppLocalization.localized("从剪贴面板打开")
            case .preview:
                return AppLocalization.localized("从完整预览开始")
            }
        }

        var detail: String {
            switch self {
            case .panel:
                return AppLocalization.localized("右上角这个按钮就是堆栈入口。")
            case .preview:
                return AppLocalization.localized("这里会把当前文本带进堆栈。")
            }
        }

        var frameHeight: CGFloat {
            switch self {
            case .panel:
                return 110
            case .preview:
                return 110
            }
        }
    }

    private func applicationRuleList(
        bundleIDs: [String],
        emptyText: String,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if bundleIDs.isEmpty {
                Text(localized(emptyText))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(bundleIDs, id: \.self) { bundleID in
                    applicationRuleRow(bundleID: bundleID) {
                        onRemove(bundleID)
                    }

                    if bundleID != bundleIDs.last {
                        settingsDivider(opacity: 0.3)
                    }
                }
            }
        }
    }

    private func applicationRuleRow(
        bundleID: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let icon = services.applicationIcon(forBundleID: bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "app")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(services.applicationDisplayName(forBundleID: bundleID))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Text(bundleID)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 12)

            Button(localized("移除"), role: .destructive, action: onRemove)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 8)
    }

    private func historyLimitRow<Accessory: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(localized(title))
                Text(localized(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)
            accessory()
                .frame(width: historyLimitAccessoryWidth, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var aboutAppIcon: Image {
        if NSImage(named: "AboutAppIcon") != nil {
            return Image("AboutAppIcon")
        }

        return Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
    }

    private func formattedDiskLimitMB(_ mb: Int) -> String {
        if mb >= 1024 {
            let gb = Double(mb) / 1024.0
            return String(format: "%.1f GB", gb)
        }

        return "\(mb) MB"
    }

    private func formattedByteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var auxiliaryGestureHeaderRow: some View {
        HStack(spacing: 10) {
            auxiliaryHeaderCell("方向序列", width: auxiliaryGestureColumnWidth)
            auxiliaryHeaderCell("触发动作", width: auxiliaryActionColumnWidth)
            auxiliaryHeaderCell("执行内容", width: auxiliaryPayloadColumnWidth)
            auxiliaryHeaderCell("备注")
            auxiliaryHeaderCell("", width: auxiliaryDeleteColumnWidth)
        }
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func auxiliaryHeaderCell(_ title: String, width: CGFloat? = nil) -> some View {
        Group {
            if let width {
                Text(localized(title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: width, alignment: .leading)
            } else {
                Text(localized(title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func auxiliaryGestureRow(_ gesture: RightMouseAuxiliaryGestureSettings) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                auxiliaryPatternPicker(gesture)
                    .frame(width: auxiliaryGestureColumnWidth, alignment: .leading)

                auxiliaryActionPicker(gesture)
                    .frame(width: auxiliaryActionColumnWidth, alignment: .leading)

                auxiliaryPayloadCell(gesture)
                    .frame(width: auxiliaryPayloadColumnWidth, alignment: .leading)

                auxiliaryNoteField(gesture)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    activeAuxiliaryDropdown = nil
                    focusedAuxiliaryNoteID = nil
                    removeAuxiliaryGestureRow(id: gesture.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .frame(width: auxiliaryDeleteColumnWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let conflictMessage = auxiliaryConflictMessage(for: gesture) {
                Text(localized(conflictMessage))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.leading, auxiliaryGestureColumnWidth + auxiliaryActionColumnWidth + 20)
            }
        }
    }

    private func auxiliaryPayloadCell(_ gesture: RightMouseAuxiliaryGestureSettings) -> some View {
        Group {
            if gesture.actionType == .shortcut {
                auxiliaryShortcutCell(gesture)
            } else {
                auxiliaryApplicationCell(gesture)
            }
        }
    }

    private func auxiliaryShortcutCell(_ gesture: RightMouseAuxiliaryGestureSettings) -> some View {
        ShortcutRecorderField(
            displayText: formattedShortcutDisplay(for: gesture),
            isRecording: recordingGestureID == gesture.id,
            onBeginRecording: {
                recordingGestureID = gesture.id
            },
            onCancelRecording: {
                if recordingGestureID == gesture.id {
                    recordingGestureID = nil
                }
            },
            onClear: {
                appState.updateSettings { settings in
                    guard let index = settings.rightMouseAuxiliaryGestures.firstIndex(where: { $0.id == gesture.id }) else { return }
                    settings.rightMouseAuxiliaryGestures[index].shortcutUsesCommand = false
                    settings.rightMouseAuxiliaryGestures[index].shortcutUsesOption = false
                    settings.rightMouseAuxiliaryGestures[index].shortcutUsesControl = false
                    settings.rightMouseAuxiliaryGestures[index].shortcutUsesShift = false
                    settings.rightMouseAuxiliaryGestures[index].shortcutKey = ""
                }
                recordingGestureID = nil
            },
            onRecord: { event in
                guard let recordedShortcut = KeyboardShortcut.from(event: event) else { return }
                appState.updateSettings { settings in
                    guard let index = settings.rightMouseAuxiliaryGestures.firstIndex(where: { $0.id == gesture.id }) else { return }
                    settings.rightMouseAuxiliaryGestures[index].shortcutUsesCommand = recordedShortcut.usesCommand
                    settings.rightMouseAuxiliaryGestures[index].shortcutUsesOption = recordedShortcut.usesOption
                    settings.rightMouseAuxiliaryGestures[index].shortcutUsesControl = recordedShortcut.usesControl
                    settings.rightMouseAuxiliaryGestures[index].shortcutUsesShift = recordedShortcut.usesShift
                    settings.rightMouseAuxiliaryGestures[index].shortcutKey = recordedShortcut.normalizedKey
                }
                recordingGestureID = nil
            }
        )
    }

    private func auxiliaryApplicationCell(_ gesture: RightMouseAuxiliaryGestureSettings) -> some View {
        Button {
            focusedAuxiliaryNoteID = nil
            activeAuxiliaryDropdown = nil
            chooseAuxiliaryGestureApplication(for: gesture.id)
        } label: {
            HStack(spacing: 8) {
                if let icon = auxiliaryApplicationIcon(for: gesture) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(auxiliaryApplicationLabel(for: gesture))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: auxiliaryControlHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(auxiliaryControlFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(auxiliaryControlBorderShape)
        }
        .buttonStyle(.plain)
    }

    private func auxiliaryPatternPicker(_ gesture: RightMouseAuxiliaryGestureSettings) -> some View {
        auxiliaryDropdownField(
            title: gesture.pattern.title,
            isPresented: Binding(
                get: { activeAuxiliaryDropdown == .pattern(gesture.id) },
                set: { isPresented in
                    activeAuxiliaryDropdown = isPresented ? .pattern(gesture.id) : nil
                }
            ),
            options: RightMouseAuxiliaryGesturePattern.allCases.map { ($0.title, $0.rawValue) },
            selectedValue: gesture.pattern.rawValue
        ) { selectedRawValue in
            guard let pattern = RightMouseAuxiliaryGesturePattern(rawValue: selectedRawValue) else { return }
            auxiliaryGestureBinding(gestureID: gesture.id, \.pattern).wrappedValue = pattern
        }
    }

    private func auxiliaryActionPicker(_ gesture: RightMouseAuxiliaryGestureSettings) -> some View {
        auxiliaryDropdownField(
            title: gesture.actionType.title,
            isPresented: Binding(
                get: { activeAuxiliaryDropdown == .action(gesture.id) },
                set: { isPresented in
                    activeAuxiliaryDropdown = isPresented ? .action(gesture.id) : nil
                }
            ),
            options: RightMouseAuxiliaryActionType.allCases.map { ($0.title, $0.rawValue) },
            selectedValue: gesture.actionType.rawValue
        ) { selectedRawValue in
            guard let action = RightMouseAuxiliaryActionType(rawValue: selectedRawValue) else { return }
            auxiliaryGestureBinding(gestureID: gesture.id, \.actionType).wrappedValue = action
        }
    }

    private func auxiliaryNoteField(_ gesture: RightMouseAuxiliaryGestureSettings) -> some View {
        TextField("选填备注", text: auxiliaryGestureBinding(gestureID: gesture.id, \.note))
            .textFieldStyle(.plain)
            .focused($focusedAuxiliaryNoteID, equals: gesture.id)
            .padding(.horizontal, 12)
            .frame(height: auxiliaryControlHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(auxiliaryControlFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        focusedAuxiliaryNoteID == gesture.id
                        ? Color.accentColor.opacity(0.9)
                        : Color(nsColor: .separatorColor).opacity(0.18),
                        lineWidth: focusedAuxiliaryNoteID == gesture.id ? 2 : 1
                    )
            )
            .onTapGesture {
                focusedAuxiliaryNoteID = gesture.id
                activeAuxiliaryDropdown = nil
            }
    }

    private func auxiliaryDropdownField(
        title: String,
        isPresented: Binding<Bool>,
        options: [(title: String, value: String)],
        selectedValue: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        let optionRows = Array(options.enumerated())

        return Button {
            focusedAuxiliaryNoteID = nil
            isPresented.wrappedValue.toggle()
        } label: {
            auxiliaryMenuLabel(title)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            auxiliaryDropdownPopover(
                optionRows: optionRows,
                selectedValue: selectedValue,
                onSelect: onSelect
            )
        }
    }

    private func auxiliaryDropdownPopover(
        optionRows: [(offset: Int, element: (title: String, value: String))],
        selectedValue: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(optionRows, id: \.offset) { _, option in
                auxiliaryDropdownOption(
                    title: option.title,
                    value: option.value,
                    isSelected: option.value == selectedValue,
                    onSelect: onSelect
                )
            }
        }
        .padding(8)
        .frame(width: 164)
    }

    private func auxiliaryDropdownOption(
        title: String,
        value: String,
        isSelected: Bool,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Button {
            onSelect(value)
            activeAuxiliaryDropdown = nil
        } label: {
            HStack(spacing: 8) {
                Text(localized(title))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? auxiliaryControlFillColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var auxiliaryControlBorderShape: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
    }

    private func auxiliaryMenuLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(localized(title))
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: auxiliaryControlHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(auxiliaryControlFillColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(auxiliaryControlBorderShape)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var auxiliaryControlFillColor: Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark
                    ? NSColor.white.withAlphaComponent(0.12)
                    : NSColor(calibratedWhite: 0.88, alpha: 1)
            }
        )
    }

    private func auxiliaryApplicationLabel(for gesture: RightMouseAuxiliaryGestureSettings) -> String {
        guard !gesture.applicationPath.isEmpty else {
            return localized("选择 App")
        }
        return URL(fileURLWithPath: gesture.applicationPath)
            .deletingPathExtension()
            .lastPathComponent
    }

    private func auxiliaryApplicationIcon(for gesture: RightMouseAuxiliaryGestureSettings) -> NSImage? {
        guard !gesture.applicationPath.isEmpty else { return nil }
        return NSWorkspace.shared.icon(forFile: gesture.applicationPath)
    }

    private func auxiliaryConflictMessage(for gesture: RightMouseAuxiliaryGestureSettings) -> String? {
        if gesture.pattern == .unconfigured {
            return localized("请先选择手势方向。")
        }

        if duplicateAuxiliaryPatternIDs.contains(gesture.id) {
            return localized("该方向序列已被其他规则使用。")
        }

        if duplicateAuxiliaryActionIDs.contains(gesture.id) {
            return localized("该执行内容已存在于其他规则中。")
        }

        return nil
    }

    private var duplicateAuxiliaryPatternIDs: Set<UUID> {
        duplicateGestureIDs { gesture in
            guard gesture.enabled, gesture.pattern != .unconfigured else { return nil }
            return "pattern:\(gesture.pattern.rawValue)"
        }
    }

    private var duplicateAuxiliaryActionIDs: Set<UUID> {
        duplicateGestureIDs { gesture in
            guard gesture.enabled else { return nil }
            switch gesture.actionType {
            case .shortcut:
                let shortcut = formattedShortcutStorage(for: gesture)
                return shortcut.isEmpty ? nil : "shortcut:\(shortcut)"
            case .openApplication:
                return gesture.applicationPath.isEmpty ? nil : "app:\(gesture.applicationPath)"
            }
        }
    }

    private func duplicateGestureIDs(
        _ keyFor: (RightMouseAuxiliaryGestureSettings) -> String?
    ) -> Set<UUID> {
        let configured = appState.settings.rightMouseAuxiliaryGestures.compactMap { gesture in
            keyFor(gesture).map { ($0, gesture.id) }
        }
        let grouped = Dictionary(grouping: configured, by: \.0)

        return Set(
            grouped
                .filter { _, gestures in
                    gestures.count > 1
                }
                .flatMap { $0.value.map(\.1) }
        )
    }

    private func formattedShortcutStorage(for gesture: RightMouseAuxiliaryGestureSettings) -> String {
        let modifiers = [
            gesture.shortcutUsesCommand ? "cmd" : nil,
            gesture.shortcutUsesOption ? "opt" : nil,
            gesture.shortcutUsesControl ? "ctrl" : nil,
            gesture.shortcutUsesShift ? "shift" : nil
        ]
        .compactMap { $0 }
        .joined(separator: "+")
        let key = gesture.shortcutKey.uppercased()
        if modifiers.isEmpty { return key }
        if key.isEmpty { return modifiers }
        return "\(modifiers)+\(key)"
    }

    private func formattedShortcutDisplay(for gesture: RightMouseAuxiliaryGestureSettings) -> String {
        if recordingGestureID == gesture.id {
            return localized("请按下快捷键")
        }

        var modifiers = ""
        if gesture.shortcutUsesCommand { modifiers += "⌘" }
        if gesture.shortcutUsesOption { modifiers += "⌥" }
        if gesture.shortcutUsesControl { modifiers += "⌃" }
        if gesture.shortcutUsesShift { modifiers += "⇧" }
        let key = gesture.shortcutKey.uppercased()
        return modifiers.isEmpty && key.isEmpty ? "点击录制" : modifiers + key
    }

    private func addAuxiliaryGestureRow() {
        appState.updateSettings { settings in
            settings.rightMouseAuxiliaryGestures.append(.default())
        }
    }

    private func removeAuxiliaryGestureRow(id: UUID) {
        appState.updateSettings { settings in
            settings.rightMouseAuxiliaryGestures.removeAll { $0.id == id }
        }
    }

    private func chooseAuxiliaryGestureApplication(for gestureID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.prompt = "选择"
        panel.message = "选择附加手势要打开的 App。"

        if panel.runModal() == .OK, let url = panel.url {
            appState.updateSettings { settings in
                guard let index = settings.rightMouseAuxiliaryGestures.firstIndex(where: { $0.id == gestureID }) else { return }
                settings.rightMouseAuxiliaryGestures[index].applicationPath = url.path
            }
        }
    }

    private func chooseApplications(for target: ClipboardCaptureRuleTarget) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.application]
        panel.prompt = "选择"
        panel.message = target.openPanelMessage

        guard panel.runModal() == .OK else { return }

        var resolvedBundleIDs: [String] = []
        var invalidSelectionCount = 0

        for url in panel.urls {
            let bundleID = Bundle(url: url)?.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if bundleID.isEmpty {
                invalidSelectionCount += 1
                continue
            }
            resolvedBundleIDs.append(bundleID)
        }

        let uniqueBundleIDs = Array(Set(resolvedBundleIDs)).sorted()
        if !uniqueBundleIDs.isEmpty {
            switch target {
            case .blacklist:
                appState.addBlacklistBundleIDs(uniqueBundleIDs)
            }
        }

        if invalidSelectionCount > 0 {
            appState.lastErrorMessage = nil
            services.showTransientNotice(localized(uniqueBundleIDs.isEmpty
                ? "所选应用缺少应用标识，已跳过"
                : "部分应用缺少应用标识，已跳过"))
        } else if !uniqueBundleIDs.isEmpty {
            appState.lastErrorMessage = nil
        }
    }
}

private struct ShortcutRecorderField: NSViewRepresentable {
    let displayText: String
    let isRecording: Bool
    var width: CGFloat? = nil
    var height: CGFloat = 34
    var textAlignment: NSTextAlignment = .right
    var usesContentDrivenWidth: Bool = false
    var minimumWidth: CGFloat? = nil
    var maximumWidth: CGFloat? = nil
    var fontSize: CGFloat = 12
    var fontWeight: NSFont.Weight = .medium
    var showsHoverClearButton: Bool = false
    var canClear: Bool = false
    let onBeginRecording: () -> Void
    let onCancelRecording: () -> Void
    let onClear: () -> Void
    let onRecord: (NSEvent) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.recorderWidth = width
        view.recorderHeight = height
        view.labelAlignment = textAlignment
        view.usesContentDrivenWidth = usesContentDrivenWidth
        view.minimumRecorderWidth = minimumWidth
        view.maximumRecorderWidth = maximumWidth
        view.labelFontSize = fontSize
        view.labelFontWeight = fontWeight
        view.showsHoverClearButton = showsHoverClearButton
        view.canClear = canClear
        view.onBeginRecording = onBeginRecording
        view.onCancelRecording = onCancelRecording
        view.onClear = onClear
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.displayText = displayText
        nsView.isRecording = isRecording
        nsView.recorderWidth = width
        nsView.recorderHeight = height
        nsView.labelAlignment = textAlignment
        nsView.usesContentDrivenWidth = usesContentDrivenWidth
        nsView.minimumRecorderWidth = minimumWidth
        nsView.maximumRecorderWidth = maximumWidth
        nsView.labelFontSize = fontSize
        nsView.labelFontWeight = fontWeight
        nsView.showsHoverClearButton = showsHoverClearButton
        nsView.canClear = canClear
        nsView.onBeginRecording = onBeginRecording
        nsView.onCancelRecording = onCancelRecording
        nsView.onClear = onClear
        nsView.onRecord = onRecord

        if isRecording, nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: ShortcutRecorderNSView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: nsView.resolvedWidth,
            height: height
        )
    }
}

private struct AuxiliaryNoteField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeNSView(context: Context) -> AuxiliaryNoteFieldNSView {
        let view = AuxiliaryNoteFieldNSView()
        view.onTextChanged = { newValue in
            if text != newValue {
                text = newValue
            }
        }
        return view
    }

    func updateNSView(_ nsView: AuxiliaryNoteFieldNSView, context: Context) {
        nsView.placeholder = placeholder
        nsView.text = text
        nsView.onTextChanged = { newValue in
            if text != newValue {
                text = newValue
            }
        }
    }
}

private final class ShortcutRecorderNSView: NSView {
    private let horizontalPadding: CGFloat = 12
    private let hoverClearButtonSize: CGFloat = 14
    private let hoverClearButtonSpacing: CGFloat = 8

    var onBeginRecording: (() -> Void)?
    var onCancelRecording: (() -> Void)?
    var onClear: (() -> Void)?
    var onRecord: ((NSEvent) -> Void)?

    var displayText: String = "" {
        didSet {
            label.stringValue = displayText
            updateSizeConstraints()
        }
    }

    var isRecording: Bool = false {
        didSet {
            if isRecording {
                startOutsideClickMonitoring()
            } else {
                stopOutsideClickMonitoring()
            }
            updateAppearance()
        }
    }

    var recorderWidth: CGFloat? {
        didSet { updateSizeConstraints() }
    }

    var recorderHeight: CGFloat = 34 {
        didSet { updateSizeConstraints() }
    }

    var labelAlignment: NSTextAlignment = .right {
        didSet { label.alignment = labelAlignment }
    }

    var usesContentDrivenWidth: Bool = false {
        didSet { updateSizeConstraints() }
    }

    var minimumRecorderWidth: CGFloat? {
        didSet { updateSizeConstraints() }
    }

    var maximumRecorderWidth: CGFloat? {
        didSet { updateSizeConstraints() }
    }

    var labelFontSize: CGFloat = 12 {
        didSet { updateAppearance() }
    }

    var labelFontWeight: NSFont.Weight = .medium {
        didSet { updateAppearance() }
    }

    var showsHoverClearButton: Bool = false {
        didSet { updateHoverClearButtonVisibility() }
    }

    var canClear: Bool = false {
        didSet { updateHoverClearButtonVisibility() }
    }

    private let label = NSTextField(labelWithString: "")
    private let hoverClearButton = NSButton()
    private var localMonitor: Any?
    private var trackingAreaRef: NSTrackingArea?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var labelTrailingConstraint: NSLayoutConstraint?
    private var isHovering = false {
        didSet { updateHoverClearButtonVisibility() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1

        translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.alignment = labelAlignment
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        hoverClearButton.translatesAutoresizingMaskIntoConstraints = false
        hoverClearButton.isBordered = false
        hoverClearButton.bezelStyle = .regularSquare
        hoverClearButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "清空快捷键")
        hoverClearButton.imagePosition = .imageOnly
        hoverClearButton.contentTintColor = .systemRed
        hoverClearButton.target = self
        hoverClearButton.action = #selector(handleHoverClearButton)
        hoverClearButton.isHidden = true
        addSubview(hoverClearButton)

        let labelTrailingConstraint = label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding)
        self.labelTrailingConstraint = labelTrailingConstraint

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
            labelTrailingConstraint,
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            hoverClearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalPadding),
            hoverClearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            hoverClearButton.widthAnchor.constraint(equalToConstant: hoverClearButtonSize),
            hoverClearButton.heightAnchor.constraint(equalToConstant: hoverClearButtonSize)
        ])

        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        updateSizeConstraints()
        updateAppearance()
        updateHoverClearButtonVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopOutsideClickMonitoring()
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingAreaRef = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: resolvedWidth,
            height: recorderHeight
        )
    }

    var resolvedWidth: CGFloat {
        if let recorderWidth {
            return recorderWidth
        }

        let measuredWidth = ceil(label.intrinsicContentSize.width) + horizontalPadding * 2
        let minimumWidth = minimumRecorderWidth ?? 0
        let maximumWidth = maximumRecorderWidth ?? CGFloat.greatestFiniteMagnitude

        if usesContentDrivenWidth {
            return min(max(measuredWidth, minimumWidth), maximumWidth)
        }

        return max(measuredWidth, minimumWidth)
    }

    override func mouseDown(with event: NSEvent) {
        onBeginRecording?()
        window?.makeFirstResponder(self)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            onCancelRecording?()
        }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        handle(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isRecording {
            handle(event)
            return true
        }
        return false
    }

    private func handle(_ event: NSEvent) {
        guard isRecording else { return }

        switch event.keyCode {
        case 53:
            onCancelRecording?()
        case 51, 117:
            onClear?()
        default:
            onRecord?(event)
        }
    }

    private func updateAppearance() {
        label.stringValue = displayText
        label.font = .systemFont(ofSize: labelFontSize, weight: labelFontWeight)
        label.textColor = isRecording ? .controlAccentColor : .labelColor
        layer?.backgroundColor = auxiliaryDynamicFillColor().cgColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.clear).cgColor
        hoverClearButton.contentTintColor = canClear ? .systemRed : NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        updateHoverClearButtonVisibility()
        updateSizeConstraints()
    }

    private func updateHoverClearButtonVisibility() {
        let shouldShowButton = showsHoverClearButton && canClear && isHovering && !isRecording
        hoverClearButton.isHidden = !shouldShowButton
        labelTrailingConstraint?.constant = shouldShowButton
            ? -(horizontalPadding + hoverClearButtonSize + hoverClearButtonSpacing)
            : -horizontalPadding
    }

    @objc
    private func handleHoverClearButton() {
        guard showsHoverClearButton, canClear else { return }
        onClear?()
    }

    private func updateSizeConstraints() {
        invalidateIntrinsicContentSize()

        if let widthConstraint {
            widthConstraint.isActive = false
            self.widthConstraint = nil
        }

        let widthConstraint = widthAnchor.constraint(equalToConstant: resolvedWidth)
        widthConstraint.isActive = true
        self.widthConstraint = widthConstraint

        if let heightConstraint {
            heightConstraint.isActive = false
            self.heightConstraint = nil
        }

        let heightConstraint = heightAnchor.constraint(equalToConstant: recorderHeight)
        heightConstraint.isActive = true
        self.heightConstraint = heightConstraint
    }

    private func startOutsideClickMonitoring() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            guard self.isRecording, let window = self.window, event.window === window else { return event }
            let localPoint = self.convert(event.locationInWindow, from: nil)
            if !self.bounds.contains(localPoint) {
                self.onCancelRecording?()
                DispatchQueue.main.async {
                    window.makeFirstResponder(nil)
                }
            }
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func auxiliaryDynamicFillColor() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor(calibratedWhite: 0.88, alpha: 1)
        }
    }
}

private final class AuxiliaryNoteFieldNSView: NSView, NSTextFieldDelegate {
    var onTextChanged: ((String) -> Void)?

    var text: String = "" {
        didSet {
            if textField.stringValue != text {
                textField.stringValue = text
            }
        }
    }

    var placeholder: String = "" {
        didSet {
            textField.placeholderString = placeholder
        }
    }

    private let textField = NSTextField()
    private var localMonitor: Any?
    private var isEditing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        layer?.cornerRadius = 10
        layer?.borderWidth = 1

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.isEditable = false
        textField.isSelectable = false
        textField.delegate = self
        addSubview(textField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance(isFocused: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopOutsideClickMonitoring()
    }

    override func mouseDown(with event: NSEvent) {
        beginEditing()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance(isFocused: isEditing)
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        startOutsideClickMonitoring()
        isEditing = true
        updateAppearance(isFocused: true)
    }

    func controlTextDidChange(_ obj: Notification) {
        onTextChanged?(textField.stringValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        stopOutsideClickMonitoring()
        onTextChanged?(textField.stringValue)
        isEditing = false
        textField.isEditable = false
        textField.isSelectable = false
        updateAppearance(isFocused: false)
    }

    private func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        textField.isEditable = true
        textField.isSelectable = true
        updateAppearance(isFocused: true)
        window?.makeFirstResponder(textField)
    }

    private func endEditing() {
        guard isEditing else { return }
        textField.abortEditing()
        window?.endEditing(for: textField)
        textField.isEditable = false
        textField.isSelectable = false
        isEditing = false
        updateAppearance(isFocused: false)
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(nil)
        }
    }

    private func startOutsideClickMonitoring() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            let pointInWindow = event.locationInWindow
            let pointInSelf = self.convert(pointInWindow, from: nil)
            if !self.bounds.contains(pointInSelf) {
                self.endEditing()
            }
            return event
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func updateAppearance(isFocused: Bool) {
        layer?.backgroundColor = auxiliaryDynamicFillColor().cgColor
        layer?.borderColor = (isFocused ? NSColor.controlAccentColor : NSColor.clear).cgColor
        if let editor = textField.currentEditor() as? NSTextView {
            editor.insertionPointColor = isFocused ? .controlAccentColor : .clear
        }
    }

    private func auxiliaryDynamicFillColor() -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor(calibratedWhite: 0.88, alpha: 1)
        }
    }
}

private struct OpenSourceProjectReference: Identifiable {
    let id: String
    let name: String
    let repositoryURL: URL
    let usageTitle: String
    let usageDetail: String

    static let currentMITProjects: [OpenSourceProjectReference] = [
        .init(
            id: "maccy",
            name: "Maccy",
            repositoryURL: URL(string: "https://github.com/p0deje/Maccy")!,
            usageTitle: "列表层级与快速搜索",
            usageDetail: "用于参考轻量历史列表、去重方式和键盘优先的搜索节奏。"
        ),
        .init(
            id: "clipy",
            name: "Clipy",
            repositoryURL: URL(string: "https://github.com/Clipy/Clipy")!,
            usageTitle: "菜单栏入口与偏好项组织",
            usageDetail: "用于参考菜单栏剪贴板工具的入口组织方式，以及偏好设置的分组结构。"
        ),
        .init(
            id: "flycut",
            name: "Flycut",
            repositoryURL: URL(string: "https://github.com/TermiT/Flycut")!,
            usageTitle: "连续粘贴与轻量堆栈",
            usageDetail: "用于参考连续粘贴、剪贴板堆栈和高频录入场景下的交互取舍。"
        ),
        .init(
            id: "jumpcut",
            name: "Jumpcut",
            repositoryURL: URL(string: "https://github.com/snark/jumpcut")!,
            usageTitle: "简洁的剪贴板工作流",
            usageDetail: "用于参考早期 macOS 剪贴板工具的轻量实现边界和基础工作流。"
        )
    ]
}

private struct OpenSourceCreditsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private let projects = OpenSourceProjectReference.currentMITProjects

    private func localized(_ key: String) -> String {
        AppLocalization.localized(key)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("开源鸣谢"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))

                    Text(localized("以下项目为 Edge Clip 提供了交互灵感或实现参考。点击 GitHub 可查看对应仓库。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button(localized("关闭")) {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(sheetHeaderBackground)

            Divider()
                .opacity(0.35)
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(projects) { project in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.name)
                                        .font(.system(size: 16, weight: .semibold))

                                    Text(localized(project.usageTitle))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(Color.accentColor.opacity(0.10))
                                        )
                                }

                                Spacer(minLength: 12)

                                Link(destination: project.repositoryURL) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "link")
                                        Text("GitHub")
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                            }

                            Text(localized(project.usageDetail))
                                .font(.system(size: 13))
                                .foregroundStyle(Color.primary.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)

                            Text(project.repositoryURL.absoluteString)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(sheetCardBackground(cornerRadius: 14))
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
        .background(sheetBackground)
    }

    private var sheetBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ]
                : [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var sheetHeaderBackground: some View {
        Rectangle()
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.02 : 0.16))
            )
    }

    private func sheetCardBackground(cornerRadius: CGFloat) -> some View {
        let baseFill = colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.92)
            : Color.white.opacity(0.90)

        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseFill)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.36))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.04),
                radius: colorScheme == .dark ? 10 : 14,
                y: 4
            )
    }
}
