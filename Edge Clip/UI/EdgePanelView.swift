import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum EdgePanelLocalizationSupport {
    static func localized(_ key: String) -> String {
        AppLocalization.localized(key)
    }

    static func stackItemCount(_ count: Int) -> String {
        if AppLocalization.isEnglish {
            return count == 1 ? "1 item" : "\(count) items"
        }
        return "\(count) 项"
    }

    static func pendingPasteCount(_ count: Int) -> String {
        if AppLocalization.isEnglish {
            return count == 1 ? "1 pending paste" : "\(count) pending pastes"
        }
        return "\(count) 条待粘贴"
    }

    static func indexedStackEntryTitle(_ index: Int) -> String {
        if AppLocalization.isEnglish {
            return "Item \(index)"
        }
        return "第 \(index) 条"
    }

    static func relativeTimestamp(for date: Date) -> String {
        let now = Date()
        if Calendar.current.isDateInToday(date) {
            let elapsedMinutes = max(1, Int(now.timeIntervalSince(date) / 60))
            if elapsedMinutes < 60 {
                if AppLocalization.isEnglish {
                    return "\(elapsedMinutes) min ago"
                }
                return "\(elapsedMinutes)分钟前"
            }
            return makeTimeFormatter().string(from: date)
        }

        return makeDayFormatter().string(from: date)
    }

    private static func makeTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentLocale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static func makeDayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentLocale
        formatter.setLocalizedDateFormatFromTemplate(AppLocalization.isEnglish ? "MMM d" : "M月d日")
        return formatter
    }
}

struct EdgePanelView: View {
    @ObservedObject var services: AppServices
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    @State private var isCloseHovered = false
    @State private var scrollResetToken = 0
    @State private var visibleRowStartIndex = 0
    @State private var hiddenTopRowIndex: Int?
    @State private var isSearchExpanded = false
    @State private var isTabHoverUnlocked = true
    @State private var tabFrames: [PanelTab: CGRect] = [:]
    @State private var cachedHistoryByTab: [PanelTab: [ClipboardItem]] = [:]
    @State private var hoveredHistoryRowID: ClipboardItem.ID?
    @State private var hoverPreviewTab: PanelTab?
    @State private var isFilterBarPointerInside = false
    @State private var areRowAssetsDeferred = false
    @State private var rememberedRowPreviewImages: [ClipboardItem.ID: NSImage] = [:]
    @State private var continuousPreviewHoverTask: Task<Void, Never>?
    @State private var filterBarCommitTask: Task<Void, Never>?
    @State private var pendingFilterBarCommitTab: PanelTab?
    @State private var rowAssetResumeTask: Task<Void, Never>?
    @State private var historyPresentationSyncTask: Task<Void, Never>?
    @State private var draggedStackEntryID: ClipboardItem.StackEntry.ID?
    @State private var hoveredStackEntryID: ClipboardItem.StackEntry.ID?
    @State private var draggedFavoriteEntryKey: FavoriteEntryOrderKey?
    @State private var draggedFavoriteGroupID: FavoriteGroup.ID?
    @State private var hoveredHeaderTooltipID: HeaderTooltipID?
    @State private var headerTooltipFrames: [HeaderTooltipID: CGRect] = [:]
    @State private var headerTooltipBubbleSize: CGSize = .zero
    @State private var hoveredFavoriteHandleTooltipItemID: ClipboardItem.ID?
    @State private var hoveredFavoriteHandleTooltipSnippetID: FavoriteSnippet.ID?
    @State private var hoveredFavoriteGroupID: FavoriteGroup.ID?
    @State private var editingFavoriteGroupID: FavoriteGroup.ID?
    @State private var favoriteGroupNameDraft = ""
    @State private var favoriteReorderAutoScrollToken = 0
    @State private var favoriteReorderAutoScrollDelta: CGFloat = 0
    @State private var favoriteReorderAutoScrollDirection: FavoriteReorderAutoScrollDirection?
    @State private var favoriteEntryDragMonitorTask: Task<Void, Never>?
    @State private var favoriteEntryDropIndex: Int?
    @State private var favoriteEntryDragPreviewImage: NSImage?
    @State private var favoriteEntryDragPreviewLocation: CGPoint?
    @State private var panelPointerBridge = PanelPointerBridge()
    @FocusState private var isSearchFieldFocused: Bool
    @FocusState private var focusedFavoriteGroupID: FavoriteGroup.ID?

    private let rowStride: CGFloat = 86
    private let rowWindowOverscanCount = 12
    private let continuousPreviewHoverDelay: Duration = .milliseconds(240)
    private let filterBarCommitDelay: Duration = .milliseconds(40)
    private let rowAssetResumeDelay: Duration = .milliseconds(140)
    private let favoriteReorderAutoScrollPageOverlapRows: CGFloat = 0.88
    private let favoriteReorderAutoScrollActivationFraction: CGFloat = 0.18
    private let favoriteReorderAutoScrollKeepFraction: CGFloat = 0.28
    private let favoriteReorderAutoScrollInterval: Duration = .milliseconds(48)
    private let filterBarCoordinateSpace = "EdgePanelFilterBarSpace"
    private let panelCoordinateSpace = "EdgePanelPanelSpace"

    private func localized(_ key: String) -> String {
        EdgePanelLocalizationSupport.localized(key)
    }

    var body: some View {
        buildBodyView()
    }

    private func buildBodyView() -> AnyView {
        let base = makeBasePanelView()
        let chrome = makeChromePanelView(base)
        let lifecycle = makeLifecyclePanelView(chrome)
        let changes = makeStateChangePanelView(lifecycle)
        return makePreferencePanelView(changes)
    }

    private func makeBasePanelView() -> AnyView {
        AnyView(
            rootBaseContent
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: panelCoordinateSpace)
            .background(panelBackground)
        )
    }

    private func makeChromePanelView(_ base: AnyView) -> AnyView {
        AnyView(
            base
            .overlay(alignment: .top) {
                topWindowDragStrip
            }
            .animation(.spring(response: 0.24, dampingFraction: 0.88), value: appState.panelMode)
            .overlay(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    headerTooltipOverlay
                    favoriteEntryDragPreviewOverlay
                }
            }
            .overlay {
                PanelPointerSpaceView(bridge: panelPointerBridge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            .onHover { hovering in
                services.handleMainPanelHoverChanged(hovering)
            }
            .overlay(alignment: .bottom) {
                noticeOverlay
            }
        )
    }

    private func makeLifecyclePanelView(_ base: AnyView) -> AnyView {
        AnyView(
            base
            .onAppear {
                resetPresentationState()
            }
            .onDisappear {
                cancelContinuousPreviewHoverTask()
                cancelFilterBarCommitTask()
                cancelRowAssetResumeTask()
                cancelHistoryPresentationSyncTask()
                stopFavoriteReorderAutoScroll()
                commitFavoriteGroupEditingIfNeeded()
                endFavoriteReorderDrag()
                rememberedRowPreviewImages.removeAll()
                hoverPreviewTab = nil
                isFilterBarPointerInside = false
                hoveredHeaderTooltipID = nil
                hoveredFavoriteHandleTooltipItemID = nil
                hoveredFavoriteGroupID = nil
                hoveredStackEntryID = nil
                setHoveredHistoryRow(nil)
                favoriteEntryDragPreviewImage = nil
                favoriteEntryDragPreviewLocation = nil
            }
        )
    }

    private func makeStateChangePanelView(_ base: AnyView) -> AnyView {
        AnyView(
            base
            .onChange(of: appState.panelPresentationID) { _, _ in
                resetPresentationState()
            }
            .onChange(of: appState.activeTab) { _, newTab in
                if newTab != .favorites {
                    commitFavoriteGroupEditingIfNeeded()
                }
                if newTab != .favorites {
                    endFavoriteReorderDrag()
                }
                hoveredFavoriteHandleTooltipItemID = nil
                hoveredFavoriteGroupID = nil
                if !isFilterBarPointerInside || hoverPreviewTab == newTab {
                    hoverPreviewTab = nil
                }
                scheduleRowAssetResumeAfterTabSwitch()
                resetListPosition()
            }
            .onChange(of: appState.settings.panelTabSwitchMode) { _, _ in
                cancelFilterBarCommitTask()
                hoverPreviewTab = nil
            }
            .onChange(of: appState.panelMode) { _, panelMode in
                if panelMode != .history {
                    endFavoriteReorderDrag()
                }
                hoveredHeaderTooltipID = nil
                hoveredFavoriteHandleTooltipItemID = nil
                hoveredFavoriteGroupID = nil
                if panelMode == .stack {
                    collapseSearchForDismissal()
                    setHoveredHistoryRow(nil)
                } else {
                    hoveredStackEntryID = nil
                    rebuildHistoryCache()
                    resetListPosition()
                }
            }
            .onChange(of: appState.isFavoriteEditorPresented) { _, isPresented in
                guard isPresented else { return }
                if appState.activeTab != .favorites {
                    appState.activeTab = .favorites
                }
                cancelFilterBarCommitTask()
                hoverPreviewTab = nil
            }
            .onChange(of: appState.favoriteGroupRenameRequestToken) { _, _ in
                guard let groupID = appState.pendingFavoriteGroupRenameID else { return }
                beginFavoriteGroupEditing(groupID)
            }
            .onChange(of: focusedFavoriteGroupID) { oldValue, newValue in
                guard let oldValue, oldValue != newValue else { return }
                commitFavoriteGroupEditing(oldValue)
            }
            .onChange(of: appState.searchQuery) { _, _ in
                if !isFavoriteEntryReorderEnabled && !isFavoriteGroupReorderEnabled {
                    endFavoriteReorderDrag()
                }
                hoveredFavoriteHandleTooltipItemID = nil
                hoveredFavoriteHandleTooltipSnippetID = nil
                hoveredFavoriteGroupID = nil
                rebuildHistoryCache()
                resetListPosition()
            }
            .onChange(of: appState.activeFavoriteGroupID) { _, _ in
                if !isFavoriteEntryReorderEnabled && !isFavoriteGroupReorderEnabled {
                    endFavoriteReorderDrag()
                }
                hoveredFavoriteHandleTooltipItemID = nil
                hoveredFavoriteHandleTooltipSnippetID = nil
                hoveredFavoriteGroupID = nil
                rebuildHistoryCache()
                resetListPosition()
            }
            .onChange(of: appState.favoriteGroups) { _, groups in
                if let editingFavoriteGroupID,
                   !groups.contains(where: { $0.id == editingFavoriteGroupID }) {
                    self.editingFavoriteGroupID = nil
                    if focusedFavoriteGroupID == editingFavoriteGroupID {
                        focusedFavoriteGroupID = nil
                    }
                    favoriteGroupNameDraft = ""
                }
                if let draggedFavoriteGroupID,
                   !groups.contains(where: { $0.id == draggedFavoriteGroupID }) {
                    self.draggedFavoriteGroupID = nil
                }
                if let hoveredFavoriteGroupID,
                   !groups.contains(where: { $0.id == hoveredFavoriteGroupID }) {
                    self.hoveredFavoriteGroupID = nil
                }
            }
            .onChange(of: appState.history) { _, _ in
                scheduleHistoryPresentationSync()
            }
            .onChange(of: appState.searchRevealRequestToken) { oldValue, newValue in
                guard newValue > oldValue else { return }
                openSearchIfNeeded()
            }
            .onChange(of: appState.rightDragHighlightedRowID) { _, _ in
                guard isRightDragPanelInteractionActive else { return }
            }
            .onChange(of: appState.rightDragHeaderTarget) { _, headerTarget in
                guard isRightDragPanelInteractionActive else { return }
                hoveredHeaderTooltipID = headerTooltipID(for: headerTarget)
            }
            .onChange(of: services.isPanelVisible) { _, isVisible in
                guard !isVisible else { return }
                collapseSearchForDismissal()
                cancelFilterBarCommitTask()
                cancelRowAssetResumeTask()
                stopFavoriteReorderAutoScroll()
                rememberedRowPreviewImages.removeAll()
                hoverPreviewTab = nil
                isFilterBarPointerInside = false
                hoveredHeaderTooltipID = nil
                hoveredFavoriteHandleTooltipItemID = nil
                hoveredFavoriteGroupID = nil
                hoveredStackEntryID = nil
                setHoveredHistoryRow(nil)
                favoriteEntryDragPreviewImage = nil
                favoriteEntryDragPreviewLocation = nil
            }
        )
    }

    private func makePreferencePanelView(_ base: AnyView) -> AnyView {
        AnyView(
            base
                .onPreferenceChange(HistoryListFramePreferenceKey.self) { value in
                    appState.panelHistoryListFrame = value
                }
                .onPreferenceChange(FavoriteGroupFramePreferenceKey.self) { value in
                    appState.panelFavoriteGroupFrames = value
                }
                .onPreferenceChange(HeaderTooltipFramePreferenceKey.self) { value in
                    headerTooltipFrames = value
                }
        )
    }

    private var panelBodySpacing: CGFloat {
        appState.panelMode == .stack ? 10 : 10
    }

    private var panelBodyContent: AnyView {
        if appState.panelMode == .stack {
            return AnyView(
                stackModePanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            )
        } else {
            return AnyView(
                VStack(alignment: .leading, spacing: panelBodySpacing) {
                    filterBar
                        .transition(.move(edge: .top).combined(with: .opacity))
                    historyList
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            )
        }
    }

    private var rootBaseContent: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: panelBodySpacing) {
                headerBar
                panelBodyContent
            }
        )
    }

    @ViewBuilder
    private var favoriteEntryDragPreviewOverlay: some View {
        if let image = favoriteEntryDragPreviewImage,
           let location = favoriteEntryDragPreviewLocation,
           draggedFavoriteEntryKey != nil {
            let targetWidth: CGFloat = 236
            let scale = image.size.width > 0 ? min(1, targetWidth / image.size.width) : 1
            Image(nsImage: image)
                .interpolation(.high)
                .frame(width: image.size.width, height: image.size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(
                    x: location.x + 18,
                    y: location.y - (image.size.height * 0.24 * scale)
                )
                .opacity(0.98)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.09), radius: 10, y: 4)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var noticeOverlay: some View {
        if services.isPanelVisible,
           appState.transientNotice != nil || appState.lastErrorMessage != nil {
            NoticeOverlayView(
                transientNotice: appState.transientNotice,
                persistentMessage: appState.lastErrorMessage,
                onDismissPersistent: {
                    appState.lastErrorMessage = nil
                }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var headerBar: some View {
        if appState.panelMode == .stack {
            return AnyView(stackHeaderBar)
        }

        return AnyView(historyHeaderBar)
    }

    private var historyHeaderBar: some View {
        let closeButtonHighlighted = isCloseHovered || (appState.isRightDragSelecting && appState.rightDragHeaderTarget == .close)
        let searchButtonHighlighted = isSearchExpanded || (appState.isRightDragSelecting && appState.rightDragHeaderTarget == .search)
        let favoriteAddButtonHighlighted = appState.isRightDragSelecting && appState.rightDragHeaderTarget == .favoriteAdd
        let stackButtonHighlighted = appState.isRightDragSelecting && appState.rightDragHeaderTarget == .stack
        let pinButtonHighlighted = appState.isPanelPinned || (appState.isRightDragSelecting && appState.rightDragHeaderTarget == .pin)

        return HStack(alignment: .center) {
            headerTooltipHost(.historyClose, onHover: { hovering in
                isCloseHovered = hovering
            }) {
                chromeHeaderButton(action: {
                    services.hidePanel()
                }, isHighlighted: closeButtonHighlighted) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .opacity(closeButtonHighlighted ? 1 : 0.88)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HeaderControlFramePreferenceKey.self,
                            value: [.close: proxy.frame(in: .named(panelCoordinateSpace))]
                        )
                    }
                )
            }

            headerWindowDragBand

            if isSearchExpanded {
                searchField
                    .frame(width: 172)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            headerTooltipHost(.search) {
                Button {
                    toggleSearch()
                } label: {
                    Image(systemName: isSearchExpanded ? "xmark" : "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(searchButtonHighlighted ? Color.primary : Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(searchButtonHighlighted ? (colorScheme == .dark ? 0.22 : 0.12) : (colorScheme == .dark ? 0.14 : 0.06)))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HeaderControlFramePreferenceKey.self,
                            value: [.search: proxy.frame(in: .named(panelCoordinateSpace))]
                        )
                    }
                )
            }

            if showsFavoriteAddButton {
                headerTooltipHost(.favoriteAdd) {
                    chromeHeaderButton(action: {
                        services.openNewFavoriteSnippetEditor()
                    }, isHighlighted: favoriteAddButtonHighlighted) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(favoriteAddButtonHighlighted ? Color.primary : Color.secondary)
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HeaderControlFramePreferenceKey.self,
                                value: [.favoriteAdd: proxy.frame(in: .named(panelCoordinateSpace))]
                            )
                        }
                    )
                }
            }

            headerTooltipHost(.stack) {
                chromeHeaderButton(action: {
                    services.toggleStackMode()
                }, isHighlighted: stackButtonHighlighted) {
                    StackGlyphIcon(isSelected: stackButtonHighlighted)
                        .frame(width: StackGlyphIcon.toolbarSize, height: StackGlyphIcon.toolbarSize)
                }
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HeaderControlFramePreferenceKey.self,
                            value: [.stack: proxy.frame(in: .named(panelCoordinateSpace))]
                        )
                    }
                )
            }

            headerTooltipHost(.pin) {
                Button {
                    appState.isPanelPinned.toggle()
                } label: {
                    Image(systemName: appState.isPanelPinned ? "pin.fill" : "pin")
                        .font(.system(size: 14, weight: .semibold))
                        .rotationEffect(.degrees(appState.isPanelPinned ? 0 : 45))
                        .foregroundStyle(pinButtonHighlighted ? Color.primary : Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(pinButtonHighlighted ? (colorScheme == .dark ? 0.22 : 0.12) : (colorScheme == .dark ? 0.14 : 0.06)))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: HeaderControlFramePreferenceKey.self,
                            value: [.pin: proxy.frame(in: .named(panelCoordinateSpace))]
                        )
                    }
                )
            }
        }
            .padding(.top, 1)
        .animation(.easeInOut(duration: 0.16), value: isSearchExpanded)
        .onPreferenceChange(HeaderControlFramePreferenceKey.self) { value in
            appState.panelCloseButtonFrame = value[.close]
            appState.panelSearchButtonFrame = value[.search]
            appState.panelFavoriteAddButtonFrame = value[.favoriteAdd]
            appState.panelStackButtonFrame = value[.stack]
            appState.panelPinButtonFrame = value[.pin]
        }
    }

    private var stackHeaderBar: some View {
        HStack(alignment: .center, spacing: 8) {
            headerTooltipHost(.stackBack) {
                chromeHeaderButton(action: {
                    services.leaveStackModeToHistory()
                }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(localized("堆栈"))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Text(EdgePanelLocalizationSupport.stackItemCount(services.stackEntryCount))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(3)

            headerWindowDragBand

            stackOrderModeControl

            headerTooltipHost(.stackProcessor) {
                Button {
                    services.toggleStackProcessorPanel()
                } label: {
                    Text(localized("数据处理"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appState.isStackProcessorPresented ? selectedControlForegroundColor : defaultControlForegroundColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .frame(height: stackHeaderControlHeight)
                        .background(
                            RoundedRectangle(cornerRadius: stackHeaderControlCornerRadius, style: .continuous)
                                .fill(
                                    appState.isStackProcessorPresented
                                        ? selectedControlFillColor
                                        : defaultControlFillColor
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: stackHeaderControlCornerRadius, style: .continuous)
                                .stroke(
                                    appState.isStackProcessorPresented
                                        ? selectedControlStrokeColor
                                        : defaultControlStrokeColor,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
            }

            headerTooltipHost(.stackClose) {
                chromeHeaderButton(action: {
                    services.hidePanel()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
            }
        }
            .padding(.top, 1)
    }

    private var stackOrderModeControl: some View {
        HStack(spacing: 4) {
            ForEach(StackOrderMode.allCases, id: \.self) { mode in
                stackOrderModeButton(mode)
            }
        }
        .padding(3)
        .frame(width: 118, height: stackHeaderControlHeight)
        .background(
            RoundedRectangle(cornerRadius: stackHeaderControlCornerRadius, style: .continuous)
                .fill(defaultControlFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: stackHeaderControlCornerRadius, style: .continuous)
                .stroke(defaultControlStrokeColor, lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    private func stackOrderModeButton(_ mode: StackOrderMode) -> some View {
        let isSelected = services.currentStackOrderMode == mode

        return headerTooltipHost(mode == .sequential ? .stackSequential : .stackReverse) {
            Button {
                services.updateStackOrderMode(mode)
            } label: {
                Text(mode.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? selectedControlForegroundColor : defaultControlForegroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity)
                    .frame(height: stackHeaderControlHeight - 6)
                    .background(
                        RoundedRectangle(cornerRadius: stackHeaderSegmentCornerRadius, style: .continuous)
                            .fill(isSelected ? selectedControlFillColor : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: stackHeaderSegmentCornerRadius, style: .continuous)
                            .stroke(isSelected ? selectedControlStrokeColor : Color.clear, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: stackHeaderSegmentCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var filterBar: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(appState.visiblePanelTabs, id: \.self) { tab in
                tabButton(tab)
            }

            Spacer(minLength: 0)
        }
        .coordinateSpace(name: filterBarCoordinateSpace)
        .onPreferenceChange(TabFramePreferenceKey.self) { value in
            tabFrames = value
        }
        .onPreferenceChange(PanelTabFramePreferenceKey.self) { value in
            appState.panelTabFrames = value
        }
        .overlay {
            if !isFavoriteEditorTabLocked {
                FilterBarTrackingView(
                    onMove: { location in
                        handleFilterBarPointerMove(location)
                    },
                    onExit: {
                        isFilterBarPointerInside = false
                        cancelFilterBarCommitTask()
                        hoverPreviewTab = nil
                    }
                )
            }
        }
        .allowsHitTesting(!isFavoriteEditorTabLocked)
    }

    @ViewBuilder
    private var historyList: some View {
        if appState.activeTab == .favorites {
            let entries = displayedFavoriteEntries

            HStack(spacing: 10) {
                favoriteGroupSidebar
                favoriteEntriesListPanel(entries: entries)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onHover { hovering in
                if hovering {
                    unlockTabHoverIfNeeded()
                }
            }
        } else {
            let items = displayedHistory

            ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(listBackgroundColor)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.09), lineWidth: 1)

            if items.isEmpty {
                emptyState
                    .padding(.horizontal, 24)
            } else {
                GeometryReader { proxy in
                    let viewportHeight = max(proxy.size.height, rowStride)

                    PanelScrollView(
                        resetToken: scrollResetToken,
                        externalScrollToken: activeExternalHistoryScrollToken,
                        externalScrollDelta: activeExternalHistoryScrollDelta,
                        documentHeight: CGFloat(items.count) * rowStride,
                        onScroll: { offset, pointerDocumentY in
                            appState.panelScrollOffset = offset
                            let start = Int(floor(offset / rowStride))
                            let offsetInRow = offset - (CGFloat(start) * rowStride)
                            let hasPartiallyVisibleTopRow = offset > 0.5 && offsetInRow > 0.5
                            let displayStart = start + (hasPartiallyVisibleTopRow ? 1 : 0)
                            let maxStart = max(0, items.count - 1)
                            let nextStart = min(max(0, displayStart), maxStart)
                            if visibleRowStartIndex != nextStart {
                                visibleRowStartIndex = nextStart
                            }
                            let hiddenTopIndex = hasPartiallyVisibleTopRow ? start : nil
                            if hiddenTopRowIndex != hiddenTopIndex {
                                hiddenTopRowIndex = hiddenTopIndex
                            }
                            if appState.panelVisibleStartIndex != nextStart {
                                appState.panelVisibleStartIndex = nextStart
                            }
                            if appState.panelHiddenTopIndex != hiddenTopIndex {
                                appState.panelHiddenTopIndex = hiddenTopIndex
                            }
                            if appState.isRightDragSelecting {
                                services.refreshRightDragSelectionAfterScroll(documentY: nil)
                            } else {
                                updateHoveredHistoryRow(documentY: pointerDocumentY, items: items)
                            }
                        }
                    ) {
                        historyContent(items: items, viewportHeight: viewportHeight)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .overlay {
                        HistoryListTrackingView(
                            onMove: { location in
                                handleHistoryPointerMove(location, items: items)
                            },
                            onExit: {
                                guard !appState.isRightDragSelecting else { return }
                                setHoveredHistoryRow(nil)
                            }
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HistoryListFramePreferenceKey.self,
                    value: proxy.frame(in: .named(panelCoordinateSpace))
                )
            }
        )
        .onHover { hovering in
            if hovering {
                unlockTabHoverIfNeeded()
            }
        }
        }
    }

    private var stackModePanel: some View {
        let entries = services.activeStackEntries

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(listBackgroundColor)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.09), lineWidth: 1)

            if entries.isEmpty {
                stackEmptyState
                    .padding(.horizontal, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            stackRow(entry: entry, index: index, isLast: index == entries.count - 1)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stackEmptyState: some View {
        VStack(spacing: 10) {
            StackGlyphIcon(isSelected: false)
                .frame(width: StackGlyphIcon.emptyStateSize, height: StackGlyphIcon.emptyStateSize)

            Text(localized("堆栈里还没有内容"))
                .font(.headline)

            Text(localized("在外部应用按 Cmd+C，或打开左侧数据处理面板导入文本。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stackRow(entry: ClipboardItem.StackEntry, index: Int, isLast: Bool) -> some View {
        let isRowHovered = hoveredStackEntryID == entry.id
        let isDeleteVisible = isRowHovered || draggedStackEntryID == entry.id

        return VStack(alignment: .leading, spacing: index == 0 ? 4 : 0) {
            if index == 0 {
                Text(localized("下一条"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 36)
            }

            HStack(alignment: .center, spacing: 12) {
                Button {
                    services.pasteStackEntry(id: entry.id)
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.82 : 0.72))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                        )
                }
                .buttonStyle(.plain)
                .help(localized("把这一条插入到前台输入框"))
                .opacity(isRowHovered ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: isRowHovered)
                .allowsHitTesting(isRowHovered)

                HStack(alignment: .center, spacing: 12) {
                    Text(entry.text)
                        .font(.system(size: 13, weight: index == 0 ? .semibold : .regular))
                        .foregroundStyle(Color.primary.opacity(0.96))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(
                            minWidth: 0,
                            maxWidth: .infinity,
                            minHeight: stackRowTextBlockMinHeight,
                            alignment: .leading
                        )

                    Spacer(minLength: 8)
                }
                .frame(
                    minWidth: 0,
                    maxWidth: .infinity,
                    minHeight: stackRowTextBlockMinHeight,
                    alignment: .leading
                )
                .contentShape(Rectangle())
                .onDrag({
                    draggedStackEntryID = entry.id
                    return NSItemProvider(object: entry.id.uuidString as NSString)
                })

                Button {
                    services.removeStackEntry(id: entry.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.88))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(colorScheme == .dark ? 0.12 : 0.08))
                        )
                }
                .buttonStyle(.plain)
                .opacity(isDeleteVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: isDeleteVisible)
                .allowsHitTesting(isDeleteVisible)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            Group {
                if index == 0 {
                    rowHoverColor.opacity(isRowHovered ? 0.86 : 0.72)
                } else if isRowHovered {
                    rowHoverColor.opacity(0.6)
                } else {
                    Color.clear
                }
            }
        )
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    .frame(height: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoveredStackEntryID = entry.id
            } else if hoveredStackEntryID == entry.id {
                hoveredStackEntryID = nil
            }
        }
        .onDrop(of: [UTType.plainText], delegate: StackEntryDropDelegate(
            targetEntryID: entry.id,
            entries: services.activeStackEntries,
            draggedEntryID: $draggedStackEntryID,
            move: { from, to in
                services.moveStackEntries(fromOffsets: IndexSet(integer: from), toOffset: to)
            }
        ))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text(emptyStateTitle)
                .font(.headline)

            Text(emptyStateDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if !appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localized("没有匹配结果")
        }

        if appState.activeTab == .favorites {
            return localized("收藏中还没有内容")
        }

        if appState.history.isEmpty {
            return localized("还没有剪切板记录")
        }

        if AppLocalization.isEnglish {
            return "No items in \(appState.activeTab.title) yet"
        }
        return "\(appState.activeTab.title)中还没有内容"
    }

    private var emptyStateDescription: String {
        if !appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localized("试试缩短关键词，或切换到其他分类查看。")
        }

        if appState.activeTab == .favorites {
            return localized("点右上角加号手动新增，或把常用文本加入收藏。")
        }

        if appState.history.isEmpty {
            return localized("复制文本、图片或文件后，这里会自动出现对应记录。")
        }

        return localized("切换到其他标签，或者继续复制新的内容。")
    }

    private func tabButton(_ tab: PanelTab) -> some View {
        let visuallySelectedTab = isRightDragPanelInteractionActive
            ? (appState.rightDragHoveredTab ?? appState.activeTab)
            : (usesHoverTabSwitching ? (hoverPreviewTab ?? appState.activeTab) : appState.activeTab)
        let isSelected = visuallySelectedTab == tab

        return Button {
            commitTabSelectionImmediately(tab)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 11, weight: .semibold))

                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(isSelected ? selectedTabTextColor : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 32)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? selectedControlFillColor : defaultTabFillColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? selectedControlStrokeColor : defaultTabStrokeColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(nil, value: isSelected)
        .allowsHitTesting(!isFavoriteEditorTabLocked)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: TabFramePreferenceKey.self,
                        value: [tab: proxy.frame(in: .named(filterBarCoordinateSpace))]
                    )
                    .preference(
                        key: PanelTabFramePreferenceKey.self,
                        value: [tab: proxy.frame(in: .named(panelCoordinateSpace))]
                    )
            }
        )
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(localized("搜索当前分类"), text: $appState.searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    isSearchFieldFocused = false
                }

            if !appState.searchQuery.isEmpty {
                Button {
                    appState.searchQuery = ""
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
        )
    }

    private func historyRow(item: ClipboardItem, index: Int, isLast: Bool) -> some View {
        HistoryRowView(
            services: services,
            appState: appState,
            item: item,
            isLast: isLast,
            badgeState: badgeState(for: index),
            isFavorited: services.isItemFavorited(item),
            isHovered: activeRowHighlightID == item.id || draggedFavoriteEntryKey == .historyItem(item.id),
            actionsVisible: activeRowHighlightID == item.id && !appState.isRightDragSelecting && draggedFavoriteEntryKey == nil,
            showsFavoriteMoveToTopAction: appState.activeTab == .favorites && item.isFavorite && isFavoriteEntryReorderEnabled && index > 0,
            showsFavoriteReorderHandle: isFavoriteEntryReorderEnabled && item.isFavorite,
            isFavoriteReorderHandleVisible: (isFavoriteEntryReorderEnabled && item.isFavorite) && (activeRowHighlightID == item.id || draggedFavoriteEntryKey == .historyItem(item.id)),
            isFavoriteBeingDragged: draggedFavoriteEntryKey == .historyItem(item.id),
            showsFavoriteReorderTooltip: hoveredFavoriteHandleTooltipItemID == item.id && hoveredHeaderTooltipID == nil,
            rowStride: rowStride,
            deferAssetLoading: areRowAssetsDeferred,
            rememberedPreviewImage: rememberedRowPreviewImages[item.id],
            colorScheme: colorScheme,
            onBeforePrimaryAction: {
                commitFavoriteGroupEditingIfNeeded()
            },
            onFavoriteMoveToTop: {
                services.moveFavoriteItemToTop(item.id)
            },
            onRememberedPreviewImage: { image in
                rememberedRowPreviewImages[item.id] = image
            },
            onFavoriteReorderHandleHoverChanged: { hovering in
                if hovering, draggedFavoriteEntryKey == nil {
                    hoveredHeaderTooltipID = nil
                    hoveredFavoriteHandleTooltipItemID = item.id
                } else if hoveredFavoriteHandleTooltipItemID == item.id {
                    hoveredFavoriteHandleTooltipItemID = nil
                }
            },
            onFavoriteReorderStarted: { previewImage in
                beginFavoriteEntryDrag(
                    .historyItem(item.id),
                    previewImage: previewImage
                )
                hoveredFavoriteHandleTooltipItemID = nil
            },
            onFavoriteReorderEnded: {
                updateFavoriteEntryDragState()
                commitFavoriteEntryDragIfNeeded()
                endFavoriteReorderDrag()
                hoveredFavoriteHandleTooltipItemID = nil
            }
        )
        .equatable()
    }

    private func badgeState(for index: Int) -> HistoryRowBadgeState {
        if hiddenTopRowIndex == index {
            return .hiddenTop
        }

        let relativeIndex = index - visibleRowStartIndex + 1
        if (1...9).contains(relativeIndex) {
            return .active(relativeIndex)
        }

        return .inactive
    }

    private func rowTimestamp(for date: Date) -> String {
        EdgePanelLocalizationSupport.relativeTimestamp(for: date)
    }

    private func historyContent(items: [ClipboardItem], viewportHeight: CGFloat) -> some View {
        let range = renderedHistoryRange(itemsCount: items.count, viewportHeight: viewportHeight)
        let topSpacerHeight = CGFloat(range.lowerBound) * rowStride
        let bottomSpacerHeight = CGFloat(items.count - range.upperBound) * rowStride

        return VStack(spacing: 0) {
            if topSpacerHeight > 0 {
                Color.clear.frame(height: topSpacerHeight)
            }

            ForEach(Array(items[range].enumerated()), id: \.element.id) { offset, item in
                let index = range.lowerBound + offset
                historyRow(item: item, index: index, isLast: index == items.count - 1)
            }

            if bottomSpacerHeight > 0 {
                Color.clear.frame(height: bottomSpacerHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func renderedHistoryRange(itemsCount: Int, viewportHeight: CGFloat) -> Range<Int> {
        guard itemsCount > 0 else { return 0..<0 }

        let visibleRowCount = max(1, Int(ceil(max(viewportHeight, rowStride) / rowStride)))
        let overscan = max(rowWindowOverscanCount, visibleRowCount * 2)
        let maxStart = max(0, itemsCount - 1)
        let effectiveVisibleStart = min(max(0, visibleRowStartIndex), maxStart)
        let lowerBound = max(0, effectiveVisibleStart - overscan)
        let upperBound = min(itemsCount, max(lowerBound + 1, effectiveVisibleStart + visibleRowCount + overscan))

        return lowerBound..<upperBound
    }

    private func resetListPosition(force: Bool = false) {
        setHoveredHistoryRow(nil)
        let shouldResetScrollView = force || appState.panelScrollOffset > 0.5 || visibleRowStartIndex != 0 || hiddenTopRowIndex != nil
        visibleRowStartIndex = 0
        hiddenTopRowIndex = nil
        appState.panelVisibleStartIndex = 0
        appState.panelHiddenTopIndex = nil
        if shouldResetScrollView {
            appState.panelScrollOffset = 0
            scrollResetToken += 1
        }
    }

    private func resetPresentationState() {
        cancelFilterBarCommitTask()
        cancelRowAssetResumeTask()
        cancelHistoryPresentationSyncTask()
        editingFavoriteGroupID = nil
        focusedFavoriteGroupID = nil
        favoriteGroupNameDraft = ""
        endFavoriteReorderDrag()
        areRowAssetsDeferred = false
        rememberedRowPreviewImages.removeAll()
        isSearchExpanded = false
        isSearchFieldFocused = false
        isTabHoverUnlocked = appState.isPanelTabHoverUnlocked
        hoverPreviewTab = nil
        isFilterBarPointerInside = false
        rebuildHistoryCache()
        resetListPosition(force: true)
    }

    private func beginFavoriteGroupEditing(_ groupID: FavoriteGroup.ID) {
        commitFavoriteGroupEditingIfNeeded(excluding: groupID)
        guard let group = appState.favoriteGroup(withID: groupID) else { return }
        appState.activeTab = .favorites
        appState.activeFavoriteGroupID = groupID
        favoriteGroupNameDraft = FavoriteGroup.clampedUserInputName(group.name)
        editingFavoriteGroupID = groupID
        appState.clearFavoriteGroupRenameRequest()
        DispatchQueue.main.async {
            focusedFavoriteGroupID = groupID
        }
    }

    private func commitFavoriteGroupEditingIfNeeded(excluding excludedGroupID: FavoriteGroup.ID? = nil) {
        guard let editingFavoriteGroupID, editingFavoriteGroupID != excludedGroupID else { return }
        commitFavoriteGroupEditing(editingFavoriteGroupID)
    }

    private func commitFavoriteGroupEditing(_ groupID: FavoriteGroup.ID) {
        guard editingFavoriteGroupID == groupID else { return }
        services.renameFavoriteGroup(groupID, to: favoriteGroupNameDraft)
        editingFavoriteGroupID = nil
        if focusedFavoriteGroupID == groupID {
            focusedFavoriteGroupID = nil
        }
        favoriteGroupNameDraft = ""
        appState.clearFavoriteGroupRenameRequest()
    }

    private var displayedHistory: [ClipboardItem] {
        cachedHistoryByTab[appState.activeTab] ?? appState.filteredHistory(for: appState.activeTab)
    }

    private var displayedFavoriteEntries: [FavoritePanelEntry] {
        services.favoritePanelEntries()
    }

    private var currentFavoriteReorderEntries: [FavoritePanelEntry] {
        appState.favoritePanelEntries(in: appState.activeFavoriteGroupID, matching: nil)
    }

    private var currentFavoriteReorderGroups: [FavoriteGroup] {
        appState.favoriteGroups
    }

    private var isFavoriteReorderDragActive: Bool {
        draggedFavoriteEntryKey != nil || draggedFavoriteGroupID != nil
    }

    private var isFavoriteEntryLocalDragActive: Bool {
        draggedFavoriteEntryKey != nil
    }

    private var isFavoriteEntryReorderEnabled: Bool {
        appState.panelMode == .history &&
        appState.activeTab == .favorites &&
        appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        currentFavoriteReorderEntries.count > 1 &&
        !appState.isRightDragSelecting &&
        !appState.isFavoriteEditorPresented
    }

    private var isFavoriteGroupReorderEnabled: Bool {
        appState.panelMode == .history &&
        appState.activeTab == .favorites &&
        currentFavoriteReorderGroups.count > 1 &&
        !appState.isRightDragSelecting &&
        !appState.isFavoriteEditorPresented &&
        editingFavoriteGroupID == nil
    }

    private var showsFavoriteAddButton: Bool {
        appState.panelMode == .history
    }

    private var activeExternalHistoryScrollToken: Int {
        if isFavoriteEntryLocalDragActive {
            return favoriteReorderAutoScrollToken
        }
        return appState.isRightDragSelecting ? appState.rightDragScrollCommandToken : 0
    }

    private var activeExternalHistoryScrollDelta: CGFloat {
        if isFavoriteEntryLocalDragActive {
            return favoriteReorderAutoScrollDelta
        }
        return appState.isRightDragSelecting ? appState.rightDragScrollDelta : 0
    }

    private func pruneRememberedRowPreviewImages() {
        let retainedIDs = Set(appState.history.map(\.id))
        rememberedRowPreviewImages = rememberedRowPreviewImages.filter { retainedIDs.contains($0.key) }
    }

    private var headerWindowDragBand: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .overlay {
                PanelWindowDragRegion()
            }
            .layoutPriority(-1)
    }

    private var topWindowDragStrip: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .overlay {
                PanelWindowDragRegion()
            }
            .contentShape(Rectangle())
    }

    private var headerTooltipOverlay: some View {
        GeometryReader { proxy in
            if let tooltipID = hoveredHeaderTooltipID,
               let frame = headerTooltipFrames[tooltipID],
               let text = headerTooltipText(for: tooltipID) {
                let horizontalPadding: CGFloat = 8
                let verticalGap: CGFloat = 6
                let bubbleWidth = max(headerTooltipBubbleSize.width, 1)
                let bubbleHeight = max(headerTooltipBubbleSize.height, 1)
                let originX = min(
                    max(horizontalPadding, frame.midX - (bubbleWidth / 2)),
                    max(horizontalPadding, proxy.size.width - bubbleWidth - horizontalPadding)
                )
                let originY = frame.minY - bubbleHeight - verticalGap

                headerTooltipBubble(text)
                    .measureSize { headerTooltipBubbleSize = $0 }
                    .offset(x: originX, y: originY)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                    .allowsHitTesting(false)
            }
        }
    }

    private func favoriteEntriesContent(entries: [FavoritePanelEntry], viewportHeight: CGFloat) -> some View {
        let range = renderedHistoryRange(itemsCount: entries.count, viewportHeight: viewportHeight)
        let topSpacerHeight = CGFloat(range.lowerBound) * rowStride
        let bottomSpacerHeight = CGFloat(entries.count - range.upperBound) * rowStride

        return VStack(spacing: 0) {
            if topSpacerHeight > 0 {
                Color.clear.frame(height: topSpacerHeight)
            }

            ForEach(Array(entries[range].enumerated()), id: \.element.id) { offset, entry in
                let index = range.lowerBound + offset
                favoriteEntryRow(entry: entry, index: index, isLast: index == entries.count - 1)
            }

            if bottomSpacerHeight > 0 {
                Color.clear.frame(height: bottomSpacerHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func favoriteEntriesListPanel(entries: [FavoritePanelEntry]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(listBackgroundColor)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.09), lineWidth: 1)

            if entries.isEmpty {
                emptyState
                    .padding(.horizontal, 24)
            } else {
                GeometryReader { proxy in
                    let viewportHeight = max(proxy.size.height, rowStride)

                    PanelScrollView(
                        resetToken: scrollResetToken,
                        externalScrollToken: activeExternalHistoryScrollToken,
                        externalScrollDelta: activeExternalHistoryScrollDelta,
                        documentHeight: CGFloat(entries.count) * rowStride,
                        onScroll: { offset, pointerDocumentY in
                            appState.panelScrollOffset = offset
                            let start = Int(floor(offset / rowStride))
                            let offsetInRow = offset - (CGFloat(start) * rowStride)
                            let hasPartiallyVisibleTopRow = offset > 0.5 && offsetInRow > 0.5
                            let displayStart = start + (hasPartiallyVisibleTopRow ? 1 : 0)
                            let maxStart = max(0, entries.count - 1)
                            let nextStart = min(max(0, displayStart), maxStart)
                            if visibleRowStartIndex != nextStart {
                                visibleRowStartIndex = nextStart
                            }
                            let hiddenTopIndex = hasPartiallyVisibleTopRow ? start : nil
                            if hiddenTopRowIndex != hiddenTopIndex {
                                hiddenTopRowIndex = hiddenTopIndex
                            }
                            if appState.panelVisibleStartIndex != nextStart {
                                appState.panelVisibleStartIndex = nextStart
                            }
                            if appState.panelHiddenTopIndex != hiddenTopIndex {
                                appState.panelHiddenTopIndex = hiddenTopIndex
                            }
                            if appState.isRightDragSelecting {
                                services.refreshRightDragSelectionAfterScroll(documentY: nil)
                            } else {
                                updateHoveredFavoriteEntry(documentY: pointerDocumentY, entries: entries)
                            }
                        }
                    ) {
                        favoriteEntriesContent(entries: entries, viewportHeight: viewportHeight)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .overlay {
                        HistoryListTrackingView(
                            onMove: { location in
                                handleFavoritePointerMove(location, entries: entries)
                            },
                            onExit: {
                                guard !appState.isRightDragSelecting else { return }
                                setHoveredHistoryRow(nil)
                            }
                        )
                    }
                    .overlay(alignment: .topLeading) {
                        if let indicatorY = favoriteEntryDropIndicatorY(viewportHeight: viewportHeight) {
                            favoriteEntryDropIndicator(width: proxy.size.width, y: indicatorY)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HistoryListFramePreferenceKey.self,
                    value: proxy.frame(in: .named(panelCoordinateSpace))
                )
            }
        )
    }

    private var favoriteGroupSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            favoriteGroupButton(
                title: localized("全部收藏"),
                groupID: nil,
                isEditing: false,
                isSelected: appState.activeFavoriteGroupID == nil,
                isSystemGroup: true,
                showsReorderHandle: false,
                isReorderHandleVisible: false,
                isBeingDragged: false,
                onReorderStarted: {},
                onReorderEnded: {}
            )

            ForEach(appState.favoriteGroups) { group in
                favoriteGroupButton(
                    title: group.name,
                    groupID: group.id,
                    isEditing: editingFavoriteGroupID == group.id,
                    isSelected: appState.activeFavoriteGroupID == group.id,
                    isSystemGroup: false,
                    showsReorderHandle: isFavoriteGroupReorderEnabled,
                    isReorderHandleVisible: hoveredFavoriteGroupID == group.id || draggedFavoriteGroupID == group.id,
                    isBeingDragged: draggedFavoriteGroupID == group.id,
                    onReorderStarted: {
                        lockTabHoverForFavoriteReorder()
                        draggedFavoriteGroupID = group.id
                        hoveredFavoriteGroupID = nil
                    },
                    onReorderEnded: {
                        stopFavoriteReorderAutoScroll()
                        draggedFavoriteGroupID = nil
                    }
                )
                .contextMenu {
                    Button(localized("重命名")) {
                        beginFavoriteGroupEditing(group.id)
                    }

                    Button(role: .destructive) {
                        commitFavoriteGroupEditingIfNeeded()
                        services.removeFavoriteGroup(group.id)
                    } label: {
                        Text(localized("移除分组"))
                    }
                }
                .onDrop(
                    of: isFavoriteGroupReorderEnabled ? [UTType.plainText] : [],
                    delegate: FavoriteGroupDropDelegate(
                        targetGroupID: group.id,
                        groups: currentFavoriteReorderGroups,
                        draggedGroupID: $draggedFavoriteGroupID,
                        move: { from, to in
                            services.moveFavoriteGroups(fromOffsets: IndexSet(integer: from), toOffset: to)
                        }
                    )
                )
            }

            Button {
                commitFavoriteGroupEditingIfNeeded()
                let group = services.createFavoriteGroup(selecting: true, requestRename: true)
                beginFavoriteGroupEditing(group.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .background(favoriteGroupButtonBackground(isSelected: false))
                    .overlay(favoriteGroupButtonBorder(isSelected: false))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(width: 88, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 1)
        )
    }

    private func favoriteGroupButton(
        title: String,
        groupID: FavoriteGroup.ID?,
        isEditing: Bool,
        isSelected: Bool,
        isSystemGroup: Bool,
        showsReorderHandle: Bool,
        isReorderHandleVisible: Bool,
        isBeingDragged: Bool,
        onReorderStarted: @escaping () -> Void,
        onReorderEnded: @escaping () -> Void
    ) -> some View {
        let suffixReserveWidth: CGFloat = isSystemGroup ? 0 : 12
        let target: PanelFavoriteGroupTarget = groupID.map(PanelFavoriteGroupTarget.group) ?? .all
        return Group {
            if isEditing, let groupID {
                TextField("", text: $favoriteGroupNameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .focused($focusedFavoriteGroupID, equals: groupID)
                    .onSubmit {
                        commitFavoriteGroupEditing(groupID)
                    }
                    .onChange(of: favoriteGroupNameDraft) { _, newValue in
                        let clamped = FavoriteGroup.clampedUserInputName(newValue)
                        if clamped != newValue {
                            favoriteGroupNameDraft = clamped
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .center)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .background(favoriteGroupButtonBackground(isSelected: true))
                    .overlay(favoriteGroupButtonBorder(isSelected: true))
            } else {
                let selectionAction = {
                    commitFavoriteGroupEditingIfNeeded()
                    services.selectFavoriteGroup(groupID)
                }

                let label = HStack(spacing: 0) {
                    Spacer(minLength: suffixReserveWidth / 2)
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary.opacity(0.96) : Color.primary.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(isSystemGroup ? 0.86 : 0.76)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer(minLength: suffixReserveWidth / 2)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .background(favoriteGroupButtonBackground(isSelected: isSelected))
                .overlay(favoriteGroupButtonBorder(isSelected: isSelected))

                ZStack {
                    if showsReorderHandle, let groupID {
                        label
                            .overlay {
                                FavoriteReorderDragSource(
                                    dragIdentifier: groupID.uuidString,
                                    previewImageProvider: { makeFavoriteGroupDragPreviewImage(title: title, isSelected: isSelected) },
                                    onHoverChanged: { hovering in
                                        handleFavoriteGroupHoverChanged(hovering, groupID: groupID)
                                    },
                                    onDragStarted: onReorderStarted,
                                    onDragEnded: onReorderEnded,
                                    onClick: selectionAction
                                )
                            }
                    } else {
                        Button(action: selectionAction) {
                            label
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onHover { hovering in
                    guard showsReorderHandle, let groupID else {
                        handleFavoriteGroupHoverChanged(hovering, groupID: groupID)
                        return
                    }
                    handleFavoriteGroupHoverChanged(hovering, groupID: groupID)
                }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: FavoriteGroupFramePreferenceKey.self,
                    value: [target: proxy.frame(in: .named(panelCoordinateSpace))]
                )
            }
        )
    }

    private func makeFavoriteGroupDragPreviewImage(title: String, isSelected: Bool) -> NSImage? {
        let renderer = ImageRenderer(
            content:
                Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.96))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10)
                                : Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
                )
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage
    }

    private func favoriteGroupButtonBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                isSelected
                    ? Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10)
                    : Color.clear
            )
    }

    private func favoriteGroupButtonBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(
                Color.primary.opacity(
                    isSelected
                        ? (colorScheme == .dark ? 0.18 : 0.10)
                        : (colorScheme == .dark ? 0.10 : 0.05)
                ),
                lineWidth: 1
            )
    }

    @ViewBuilder
    private func favoriteEntryRow(entry: FavoritePanelEntry, index: Int, isLast: Bool) -> some View {
        switch entry {
        case .snippet(let snippet):
            FavoriteSnippetRowView(
                services: services,
                appState: appState,
                snippet: snippet,
                isLast: isLast,
                badgeState: badgeState(for: index),
                isPrimaryActionEnabled: !appState.isFavoriteEditorPresented,
                isCurrentlyEditing: appState.isFavoriteEditorPresented && appState.activeFavoriteSnippetID == snippet.id,
                isHovered: activeRowHighlightID == snippet.id || draggedFavoriteEntryKey == .snippet(snippet.id),
                actionsVisible: activeRowHighlightID == snippet.id &&
                    !appState.isRightDragSelecting &&
                    draggedFavoriteEntryKey == nil &&
                    !(appState.isFavoriteEditorPresented && appState.activeFavoriteSnippetID == snippet.id),
                showsMoveToTopAction: isFavoriteEntryReorderEnabled && index > 0,
                showsReorderHandle: isFavoriteEntryReorderEnabled,
                isReorderHandleVisible: isFavoriteEntryReorderEnabled && (activeRowHighlightID == snippet.id || draggedFavoriteEntryKey == .snippet(snippet.id)),
                isBeingDragged: draggedFavoriteEntryKey == .snippet(snippet.id),
                showsReorderTooltip: hoveredFavoriteHandleTooltipSnippetID == snippet.id && hoveredHeaderTooltipID == nil,
                rowStride: rowStride,
                colorScheme: colorScheme,
                onBeforePrimaryAction: {
                    commitFavoriteGroupEditingIfNeeded()
                },
                onMoveToTop: {
                    services.moveFavoriteSnippetToTop(snippet.id)
                },
                onReorderHandleHoverChanged: { hovering in
                    if hovering, draggedFavoriteEntryKey == nil {
                        hoveredHeaderTooltipID = nil
                        hoveredFavoriteHandleTooltipSnippetID = snippet.id
                    } else if hoveredFavoriteHandleTooltipSnippetID == snippet.id {
                        hoveredFavoriteHandleTooltipSnippetID = nil
                    }
                },
                onReorderStarted: { previewImage in
                    beginFavoriteEntryDrag(
                        .snippet(snippet.id),
                        previewImage: previewImage
                    )
                    hoveredFavoriteHandleTooltipSnippetID = nil
                },
                onReorderEnded: {
                    updateFavoriteEntryDragState()
                    commitFavoriteEntryDragIfNeeded()
                    endFavoriteReorderDrag()
                    hoveredFavoriteHandleTooltipSnippetID = nil
                }
            )
        case .historyItem(let item):
            historyRow(item: item, index: index, isLast: isLast)
        }
    }

    private func headerTooltipText(for id: HeaderTooltipID) -> String? {
        switch id {
        case .historyClose, .stackClose:
            return localized("关闭面板")
        case .search:
            return localized(isSearchExpanded ? "收起搜索" : "打开搜索")
        case .favoriteAdd:
            return localized("新增收藏")
        case .stack:
            return localized("进入堆栈")
        case .pin:
            return localized(appState.isPanelPinned ? "取消面板常显" : "开启面板常显")
        case .stackBack:
            return localized("返回历史记录")
        case .stackSequential:
            return localized("按顺序粘贴")
        case .stackReverse:
            return localized("按倒序粘贴")
        case .stackProcessor:
            return localized(appState.isStackProcessorPresented ? "收起数据处理" : "打开数据处理")
        }
    }

    private func headerTooltipID(for target: RightDragHeaderTarget?) -> HeaderTooltipID? {
        switch target {
        case .close:
            return .historyClose
        case .search:
            return .search
        case .favoriteAdd:
            return .favoriteAdd
        case .stack:
            return .stack
        case .pin:
            return .pin
        case nil:
            return nil
        }
    }

    private func rebuildHistoryCache() {
        var nextCache: [PanelTab: [ClipboardItem]] = [:]
        for tab in PanelTab.allCases {
            nextCache[tab] = appState.filteredHistory(for: tab)
        }
        cachedHistoryByTab = nextCache
    }

    private func clampListPosition() {
        let itemsCount = appState.activeTab == .favorites ? displayedFavoriteEntries.count : displayedHistory.count
        let maxStart = max(0, itemsCount - 1)
        let clampedStart = min(max(0, visibleRowStartIndex), maxStart)
        if visibleRowStartIndex != clampedStart {
            visibleRowStartIndex = clampedStart
        }
        if appState.panelVisibleStartIndex != clampedStart {
            appState.panelVisibleStartIndex = clampedStart
        }

        let clampedHiddenTop: Int?
        if let hiddenTopRowIndex, (0..<itemsCount).contains(hiddenTopRowIndex) {
            clampedHiddenTop = hiddenTopRowIndex
        } else {
            clampedHiddenTop = nil
        }

        if hiddenTopRowIndex != clampedHiddenTop {
            hiddenTopRowIndex = clampedHiddenTop
        }
        if appState.panelHiddenTopIndex != clampedHiddenTop {
            appState.panelHiddenTopIndex = clampedHiddenTop
        }
    }

    private func unlockTabHoverIfNeeded() {
        guard services.currentPanelRequiresTabHoverUnlock else { return }
        guard !isTabHoverUnlocked else { return }
        isTabHoverUnlocked = true
        appState.isPanelTabHoverUnlocked = true
    }

    private func lockTabHoverForFavoriteReorder() {
        cancelFilterBarCommitTask()
        hoverPreviewTab = nil
    }

    private func handleFavoriteGroupHoverChanged(_ hovering: Bool, groupID: FavoriteGroup.ID?) {
        if hovering {
            if let groupID, draggedFavoriteGroupID == nil {
                hoveredFavoriteGroupID = groupID
            }
            guard !isFavoriteReorderDragActive else { return }
            guard appState.activeFavoriteGroupID != groupID else { return }
            commitFavoriteGroupEditingIfNeeded()
            services.selectFavoriteGroup(groupID)
        } else if hoveredFavoriteGroupID == groupID {
            hoveredFavoriteGroupID = nil
        }
    }

    private func updateFavoriteEntryDragState() {
        guard isFavoriteEntryLocalDragActive,
              let point = panelPointerBridge.currentPointerLocation(),
              let listFrame = appState.panelHistoryListFrame else {
            favoriteEntryDropIndex = nil
            favoriteReorderAutoScrollDirection = nil
            favoriteReorderAutoScrollDelta = 0
            favoriteEntryDragPreviewLocation = nil
            return
        }

        favoriteEntryDragPreviewLocation = point

        let horizontalInset: CGFloat = 64
        let acceptsHorizontalTracking = point.x >= listFrame.minX - horizontalInset && point.x <= listFrame.maxX + horizontalInset
        let clampedLocalY = max(0, min(listFrame.height, point.y - listFrame.minY))

        if acceptsHorizontalTracking {
            let documentY = appState.panelScrollOffset + clampedLocalY
            let slot = Int(floor((documentY + (rowStride * 0.5)) / rowStride))
            favoriteEntryDropIndex = min(max(0, slot), currentFavoriteReorderEntries.count)
        }

        updateFavoriteEntryAutoScroll(localY: clampedLocalY, viewportHeight: listFrame.height, isHorizontallyTracked: acceptsHorizontalTracking)
    }

    private func updateFavoriteEntryAutoScroll(localY: CGFloat, viewportHeight: CGFloat, isHorizontallyTracked: Bool) {
        guard isHorizontallyTracked, viewportHeight > 1 else {
            favoriteReorderAutoScrollDirection = nil
            favoriteReorderAutoScrollDelta = 0
            return
        }

        let keepHeight = min(viewportHeight * 0.36, max(rowStride * 1.12, viewportHeight * favoriteReorderAutoScrollKeepFraction))
        let activationHeight = min(keepHeight, max(rowStride * 0.62, viewportHeight * favoriteReorderAutoScrollActivationFraction))

        let direction: FavoriteReorderAutoScrollDirection?
        let intensity: CGFloat

        switch favoriteReorderAutoScrollDirection {
        case .up:
            if localY <= keepHeight {
                direction = .up
                intensity = 1 - min(max(localY, 0), keepHeight) / keepHeight
            } else {
                direction = nil
                intensity = 0
            }
        case .down:
            if localY >= max(0, viewportHeight - keepHeight) {
                let distanceFromBottom = max(0, viewportHeight - localY)
                direction = .down
                intensity = 1 - min(distanceFromBottom, keepHeight) / keepHeight
            } else {
                direction = nil
                intensity = 0
            }
        case nil:
            if localY <= activationHeight {
                direction = .up
                intensity = 1 - min(max(localY, 0), keepHeight) / keepHeight
            } else if localY >= max(0, viewportHeight - activationHeight) {
                let distanceFromBottom = max(0, viewportHeight - localY)
                direction = .down
                intensity = 1 - min(distanceFromBottom, keepHeight) / keepHeight
            } else {
                direction = nil
                intensity = 0
            }
        }

        guard let direction else {
            favoriteReorderAutoScrollDirection = nil
            favoriteReorderAutoScrollDelta = 0
            return
        }

        favoriteReorderAutoScrollDirection = direction
        let pageStep = max(
            rowStride * 0.08,
            (viewportHeight - (rowStride * favoriteReorderAutoScrollPageOverlapRows)) * (0.035 + (0.095 * intensity))
        )
        favoriteReorderAutoScrollDelta = direction.deltaSign * pageStep
        favoriteReorderAutoScrollToken &+= 1
    }

    private func startFavoriteEntryDragMonitor() {
        favoriteEntryDragMonitorTask?.cancel()
        favoriteEntryDragMonitorTask = Task { @MainActor in
            while !Task.isCancelled, draggedFavoriteEntryKey != nil {
                updateFavoriteEntryDragState()
                try? await Task.sleep(for: favoriteReorderAutoScrollInterval)
            }
        }
    }

    private func stopFavoriteReorderAutoScroll() {
        favoriteReorderAutoScrollDirection = nil
        favoriteReorderAutoScrollDelta = 0
    }

    private func stopFavoriteEntryDragMonitor() {
        favoriteEntryDragMonitorTask?.cancel()
        favoriteEntryDragMonitorTask = nil
    }

    private func beginFavoriteEntryDrag(_ key: FavoriteEntryOrderKey, previewImage: NSImage?) {
        lockTabHoverForFavoriteReorder()
        draggedFavoriteEntryKey = key
        favoriteEntryDropIndex = currentFavoriteReorderEntries.firstIndex(where: { $0.orderKey == key })
        favoriteEntryDragPreviewImage = previewImage
        setHoveredHistoryRow(nil)
        cancelContinuousPreviewHoverTask()
        startFavoriteEntryDragMonitor()
        updateFavoriteEntryDragState()
    }

    private func commitFavoriteEntryDragIfNeeded() {
        guard let draggedFavoriteEntryKey,
              let fromIndex = currentFavoriteReorderEntries.firstIndex(where: { $0.orderKey == draggedFavoriteEntryKey }),
              let toOffset = favoriteEntryDropIndex,
              toOffset != fromIndex,
              toOffset != fromIndex + 1 else {
            return
        }

        services.moveFavoriteEntries(fromOffsets: IndexSet(integer: fromIndex), toOffset: toOffset)
    }

    private func favoriteEntryDropIndicatorY(viewportHeight: CGFloat) -> CGFloat? {
        guard let draggedFavoriteEntryKey,
              currentFavoriteReorderEntries.contains(where: { $0.orderKey == draggedFavoriteEntryKey }),
              let dropIndex = favoriteEntryDropIndex,
              let fromIndex = currentFavoriteReorderEntries.firstIndex(where: { $0.orderKey == draggedFavoriteEntryKey }),
              dropIndex != fromIndex,
              dropIndex != fromIndex + 1 else {
            return nil
        }

        let offsetY = (CGFloat(dropIndex) * rowStride) - appState.panelScrollOffset
        return max(2, min(viewportHeight - 2, offsetY))
    }

    private func favoriteEntryDropIndicator(width: CGFloat, y: CGFloat) -> some View {
        Capsule(style: .continuous)
            .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.92 : 0.82))
            .frame(width: max(0, width - 56), height: 4)
            .shadow(color: Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.14), radius: 6, y: 0)
            .offset(x: 44, y: y - 2)
            .allowsHitTesting(false)
    }

    private func setHoveredHistoryRow(_ rowID: ClipboardItem.ID?) {
        guard hoveredHistoryRowID != rowID || appState.hoveredRowID != rowID else { return }
        hoveredHistoryRowID = rowID
        appState.hoveredRowID = rowID
        scheduleContinuousPreviewIfNeeded(for: rowID)
    }

    private func scheduleContinuousPreviewIfNeeded(for rowID: ClipboardItem.ID?) {
        cancelContinuousPreviewHoverTask()

        guard let rowID else { return }
        guard services.canContinuePreview(for: rowID) else { return }

        continuousPreviewHoverTask = Task { @MainActor in
            try? await Task.sleep(for: continuousPreviewHoverDelay)
            guard !Task.isCancelled else { return }
            services.continuePreviewOnStableHover(rowID: rowID)
        }
    }

    private func cancelContinuousPreviewHoverTask() {
        continuousPreviewHoverTask?.cancel()
        continuousPreviewHoverTask = nil
    }

    private func endFavoriteReorderDrag() {
        stopFavoriteEntryDragMonitor()
        stopFavoriteReorderAutoScroll()
        draggedFavoriteEntryKey = nil
        draggedFavoriteGroupID = nil
        hoveredFavoriteGroupID = nil
        favoriteEntryDropIndex = nil
        favoriteEntryDragPreviewImage = nil
        favoriteEntryDragPreviewLocation = nil
    }

    private func handleHistoryPointerMove(_ location: CGPoint, items: [ClipboardItem]) {
        guard draggedFavoriteEntryKey == nil else { return }
        guard !appState.isRightDragSelecting else { return }
        unlockTabHoverIfNeeded()
        let documentY = appState.panelScrollOffset + max(0, location.y)
        updateHoveredHistoryRow(documentY: documentY, items: items)
    }

    private func handleFavoritePointerMove(_ location: CGPoint, entries: [FavoritePanelEntry]) {
        guard draggedFavoriteEntryKey == nil else { return }
        guard !appState.isRightDragSelecting else { return }
        unlockTabHoverIfNeeded()
        let documentY = appState.panelScrollOffset + max(0, location.y)
        updateHoveredFavoriteEntry(documentY: documentY, entries: entries)
    }

    private func updateHoveredHistoryRow(documentY: CGFloat?, items: [ClipboardItem]) {
        guard let documentY else {
            setHoveredHistoryRow(nil)
            return
        }
        let rowIndex = Int(floor(documentY / rowStride))
        guard items.indices.contains(rowIndex) else {
            setHoveredHistoryRow(nil)
            return
        }
        setHoveredHistoryRow(items[rowIndex].id)
    }

    private func updateHoveredFavoriteEntry(documentY: CGFloat?, entries: [FavoritePanelEntry]) {
        guard let documentY else {
            setHoveredHistoryRow(nil)
            return
        }
        let rowIndex = Int(floor(documentY / rowStride))
        guard entries.indices.contains(rowIndex) else {
            setHoveredHistoryRow(nil)
            return
        }
        setHoveredHistoryRow(entries[rowIndex].id)
    }

    private func handleFilterBarPointerMove(_ location: CGPoint) {
        guard !isRightDragPanelInteractionActive else { return }
        guard !isFavoriteReorderDragActive else {
            isFilterBarPointerInside = false
            cancelFilterBarCommitTask()
            hoverPreviewTab = nil
            return
        }
        guard !isFavoriteEditorTabLocked else {
            isFilterBarPointerInside = false
            cancelFilterBarCommitTask()
            hoverPreviewTab = nil
            return
        }
        isFilterBarPointerInside = true
        guard usesHoverTabSwitching else {
            cancelFilterBarCommitTask()
            hoverPreviewTab = nil
            return
        }
        guard isTabHoverUnlocked else { return }
        guard let tab = tab(at: location) else {
            return
        }

        previewTabImmediately(tab)
        scheduleTabSelectionCommit(for: tab)
    }

    private func tab(at location: CGPoint) -> PanelTab? {
        let orderedTabs = appState.visiblePanelTabs.compactMap { tab -> (PanelTab, CGRect)? in
            guard let frame = tabFrames[tab] else { return nil }
            return (tab, frame)
        }

        guard !orderedTabs.isEmpty else { return nil }

        let minY = orderedTabs.map(\.1.minY).min() ?? 0
        let maxY = orderedTabs.map(\.1.maxY).max() ?? 0
        let verticalPadding: CGFloat = 6
        guard location.y >= (minY - verticalPadding), location.y <= (maxY + verticalPadding) else {
            return nil
        }

        let horizontalPadding: CGFloat = 6
        let minX = (orderedTabs.first?.1.minX ?? 0) - horizontalPadding
        let maxX = (orderedTabs.last?.1.maxX ?? 0) + horizontalPadding
        guard location.x >= minX, location.x <= maxX else {
            return nil
        }

        let centers = orderedTabs.map { $0.1.midX }
        for index in orderedTabs.indices {
            let leftBoundary = index == orderedTabs.startIndex
                ? minX
                : (centers[index - 1] + centers[index]) / 2
            let rightBoundary = index == orderedTabs.index(before: orderedTabs.endIndex)
                ? maxX
                : (centers[index] + centers[index + 1]) / 2

            if location.x >= leftBoundary, location.x < rightBoundary {
                return orderedTabs[index].0
            }
        }

        return orderedTabs.last?.0
    }

    private func previewTabImmediately(_ tab: PanelTab) {
        if hoverPreviewTab != tab {
            hoverPreviewTab = tab
        }
    }

    private func commitTabSelectionImmediately(_ tab: PanelTab) {
        guard !isFavoriteEditorTabLocked || tab == .favorites else { return }
        cancelFilterBarCommitTask()
        hoverPreviewTab = nil
        if appState.activeTab != tab {
            appState.activeTab = tab
        }
    }

    private func scheduleTabSelectionCommit(for tab: PanelTab) {
        guard !isFavoriteEditorTabLocked || tab == .favorites else { return }
        if appState.activeTab == tab {
            if hoverPreviewTab == tab {
                hoverPreviewTab = nil
            }
            cancelFilterBarCommitTask()
            return
        }

        if pendingFilterBarCommitTab == tab {
            return
        }

        cancelFilterBarCommitTask()
        pendingFilterBarCommitTab = tab
        filterBarCommitTask = Task { @MainActor in
            try? await Task.sleep(for: filterBarCommitDelay)
            guard !Task.isCancelled else { return }
            if appState.activeTab != tab {
                appState.activeTab = tab
            }
            if hoverPreviewTab == tab {
                hoverPreviewTab = nil
            }
            pendingFilterBarCommitTab = nil
            filterBarCommitTask = nil
        }
    }

    private func cancelFilterBarCommitTask() {
        filterBarCommitTask?.cancel()
        filterBarCommitTask = nil
        pendingFilterBarCommitTab = nil
    }

    private var usesHoverTabSwitching: Bool {
        appState.settings.panelTabSwitchMode == .hover || services.currentPanelPresentationMode == .rightDrag
    }

    private var isFavoriteEditorTabLocked: Bool {
        appState.panelMode == .history &&
        appState.isFavoriteEditorPresented &&
        appState.activeTab == .favorites
    }

    private func scheduleRowAssetResumeAfterTabSwitch() {
        cancelRowAssetResumeTask()
        areRowAssetsDeferred = true

        rowAssetResumeTask = Task { @MainActor in
            try? await Task.sleep(for: rowAssetResumeDelay)
            guard !Task.isCancelled else { return }
            areRowAssetsDeferred = false
        }
    }

    private func cancelRowAssetResumeTask() {
        rowAssetResumeTask?.cancel()
        rowAssetResumeTask = nil
    }

    private func scheduleHistoryPresentationSync() {
        cancelHistoryPresentationSyncTask()
        historyPresentationSyncTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            rebuildHistoryCache()
            clampListPosition()
            pruneRememberedRowPreviewImages()
            historyPresentationSyncTask = nil
        }
    }

    private func cancelHistoryPresentationSyncTask() {
        historyPresentationSyncTask?.cancel()
        historyPresentationSyncTask = nil
    }

    private func toggleSearch() {
        if isSearchExpanded {
            isSearchExpanded = false
            isSearchFieldFocused = false
            appState.searchQuery = ""
        } else {
            services.preparePanelForTextInput()
            isSearchExpanded = true
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
    }

    private func openSearchIfNeeded() {
        guard !isSearchExpanded else {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
            return
        }

        services.preparePanelForTextInput()
        isSearchExpanded = true
        DispatchQueue.main.async {
            isSearchFieldFocused = true
        }
    }

    private func collapseSearchForDismissal() {
        isSearchExpanded = false
        isSearchFieldFocused = false
        if !appState.searchQuery.isEmpty {
            appState.searchQuery = ""
        }
    }

    private func chromeHeaderButton<Content: View>(
        action: @escaping () -> Void,
        isHighlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(
                            Color.primary.opacity(
                                isHighlighted
                                    ? (colorScheme == .dark ? 0.22 : 0.12)
                                    : (colorScheme == .dark ? 0.12 : 0.06)
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(
                            Color.primary.opacity(
                                isHighlighted
                                    ? (colorScheme == .dark ? 0.20 : 0.10)
                                    : (colorScheme == .dark ? 0.14 : 0.08)
                            ),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func headerTooltipHost<Content: View>(
        _ id: HeaderTooltipID,
        onHover: ((Bool) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .onHover { hovering in
                onHover?(hovering)
                if hovering {
                    hoveredFavoriteHandleTooltipItemID = nil
                    hoveredHeaderTooltipID = id
                } else if hoveredHeaderTooltipID == id {
                    hoveredHeaderTooltipID = nil
                }
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: HeaderTooltipFramePreferenceKey.self,
                        value: [id: proxy.frame(in: .named(panelCoordinateSpace))]
                    )
                }
            )
    }

    private func headerTooltipBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.92))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color(red: 0.11, green: 0.12, blue: 0.14).opacity(0.96)
                            : Color.white.opacity(0.96)
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.08),
                        radius: colorScheme == .dark ? 6 : 10,
                        y: colorScheme == .dark ? 2 : 4
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 1)
            )
    }

    private var selectedControlFillColor: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.24)
            : Color.black.opacity(0.72)
    }

    private var selectedControlStrokeColor: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.52)
            : Color.black.opacity(0.10)
    }

    private var selectedTabTextColor: Color {
        selectedControlForegroundColor
    }

    private var selectedControlForegroundColor: Color {
        .white
    }

    private var defaultControlFillColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06)
    }

    private var defaultTabFillColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04)
    }

    private var defaultControlStrokeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08)
    }

    private var defaultTabStrokeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.06)
    }

    private var defaultControlForegroundColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.82 : 0.86)
    }

    private var stackHeaderControlHeight: CGFloat {
        34
    }

    private var stackRowTextBlockMinHeight: CGFloat {
        34
    }

    private var stackHeaderControlCornerRadius: CGFloat {
        12
    }

    private var stackHeaderSegmentCornerRadius: CGFloat {
        10
    }

    private var listBackgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.22)
            : Color.white.opacity(0.62)
    }

    private var rowHoverColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.035)
    }

    private var activeRowHighlightID: ClipboardItem.ID? {
        appState.isRightDragSelecting ? appState.rightDragHighlightedRowID : hoveredHistoryRowID
    }

    private var isRightDragPanelInteractionActive: Bool {
        appState.isRightDragSelecting && services.currentPanelPresentationMode == .rightDrag
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.16) : Color.white.opacity(0.74))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.09), lineWidth: 1)
            )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

private enum HistoryRowBadgeState: Equatable {
    case hiddenTop
    case active(Int)
    case inactive
}

private struct HistoryRowView: View, Equatable {
    let services: AppServices
    let appState: AppState
    let item: ClipboardItem
    let isLast: Bool
    let badgeState: HistoryRowBadgeState
    let isFavorited: Bool
    let isHovered: Bool
    let actionsVisible: Bool
    let showsFavoriteMoveToTopAction: Bool
    let showsFavoriteReorderHandle: Bool
    let isFavoriteReorderHandleVisible: Bool
    let isFavoriteBeingDragged: Bool
    let showsFavoriteReorderTooltip: Bool
    let rowStride: CGFloat
    let deferAssetLoading: Bool
    let rememberedPreviewImage: NSImage?
    let colorScheme: ColorScheme
    let onBeforePrimaryAction: () -> Void
    let onFavoriteMoveToTop: () -> Void
    let onRememberedPreviewImage: (NSImage) -> Void
    let onFavoriteReorderHandleHoverChanged: (Bool) -> Void
    let onFavoriteReorderStarted: (NSImage?) -> Void
    let onFavoriteReorderEnded: () -> Void

    static func == (lhs: HistoryRowView, rhs: HistoryRowView) -> Bool {
        lhs.item == rhs.item &&
        lhs.isLast == rhs.isLast &&
        lhs.badgeState == rhs.badgeState &&
        lhs.isFavorited == rhs.isFavorited &&
        lhs.isHovered == rhs.isHovered &&
        lhs.actionsVisible == rhs.actionsVisible &&
        lhs.showsFavoriteMoveToTopAction == rhs.showsFavoriteMoveToTopAction &&
        lhs.showsFavoriteReorderHandle == rhs.showsFavoriteReorderHandle &&
        lhs.isFavoriteReorderHandleVisible == rhs.isFavoriteReorderHandleVisible &&
        lhs.isFavoriteBeingDragged == rhs.isFavoriteBeingDragged &&
        lhs.showsFavoriteReorderTooltip == rhs.showsFavoriteReorderTooltip &&
        lhs.deferAssetLoading == rhs.deferAssetLoading &&
        lhs.rememberedPreviewImage.map(ObjectIdentifier.init) == rhs.rememberedPreviewImage.map(ObjectIdentifier.init) &&
        lhs.colorScheme == rhs.colorScheme
    }

    private func localized(_ key: String) -> String {
        EdgePanelLocalizationSupport.localized(key)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard !appState.isFavoriteEditorPresented else { return }
                onBeforePrimaryAction()
                services.paste(item: item)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    numberBadge

                    VStack(alignment: .leading, spacing: 0) {
                        rowMeta
                            .frame(height: 20)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        rowContent
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(isHovered ? rowHoverColor : Color.clear)
                .overlay(alignment: .bottom) {
                    if !isLast {
                        Rectangle()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                            .frame(height: 1)
                    }
                }
            }
            .buttonStyle(.plain)

            rowActions
                .padding(.top, 5)
                .padding(.trailing, 12)
                .opacity(actionsVisible ? 1 : 0)
                .allowsHitTesting(actionsVisible)
        }
        .overlay(alignment: .topLeading) {
            if showsFavoriteReorderHandle {
                favoriteReorderHandle
                    .padding(.leading, 12)
                    .padding(.top, 30)
                    .opacity(isFavoriteReorderHandleVisible ? 1 : 0)
                    .allowsHitTesting(isFavoriteReorderHandleVisible)
            }
        }
        .frame(height: rowStride)
        .contentShape(Rectangle())
        .contextMenu {
            if item.kind == .stack {
                Button(localized("打开堆栈")) {
                    services.openStackSession(from: item)
                }
            } else if item.resolvedURL != nil {
                Button(localized("访问")) {
                    services.openResolvedURL(for: item)
                }
            }

            if showsFavoriteMoveToTopAction {
                Button(localized("移到最前")) {
                    onFavoriteMoveToTop()
                }
            }

            Button(localized(isFavorited ? "取消收藏" : "收藏")) {
                services.toggleFavorite(for: item.id)
            }

            Menu(localized(isFavorited ? "加入分组" : "收藏并加入")) {
                if appState.favoriteGroups.isEmpty {
                    Button(FavoriteGroup.defaultGeneratedName) {
                        services.addItemToFavoriteGroup(item, groupID: nil)
                    }
                } else {
                    ForEach(appState.favoriteGroups) { group in
                        Button(group.name) {
                            services.addItemToFavoriteGroup(item, groupID: group.id)
                        }
                    }
                }
            }

            if appState.activeTab == .favorites,
               let activeGroupID = appState.activeFavoriteGroupID,
               item.favoriteGroupIDs.contains(activeGroupID) {
                Button(localized("从当前分组移除")) {
                    services.removeFavoriteItemFromActiveGroup(item.id)
                }
            }

            if item.kind != .stack {
                Button(localized("复制")) {
                    services.copy(item: item)
                }
            }

            Button(role: .destructive) {
                appState.remove(itemID: item.id)
            } label: {
                Text(localized("删除"))
            }
        }
    }

    private var favoriteReorderHandle: some View {
        ZStack {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(isFavoriteBeingDragged ? 0.96 : 0.82))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
                )

            FavoriteEntryLocalReorderDragSource(
                onHoverChanged: onFavoriteReorderHandleHoverChanged,
                onDragStarted: {
                    onFavoriteReorderStarted(makeFavoriteDragPreviewImage())
                },
                onDragEnded: onFavoriteReorderEnded
            )
        }
        .frame(width: 20, height: 20)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .topLeading) {
            if showsFavoriteReorderTooltip && !isFavoriteBeingDragged {
                reorderHandleTooltipBubble("拖动调整顺序")
                    .offset(x: -4, y: 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                    .allowsHitTesting(false)
            }
        }
    }

    private func reorderHandleTooltipBubble(_ text: String) -> some View {
        Text(localized(text))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.92))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color(red: 0.11, green: 0.12, blue: 0.14).opacity(0.96)
                            : Color.white.opacity(0.96)
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.08),
                        radius: colorScheme == .dark ? 6 : 10,
                        y: colorScheme == .dark ? 2 : 4
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 1)
            )
    }

    private var favoriteDragPreviewCard: some View {
        HStack(alignment: .top, spacing: 10) {
            numberBadge

            VStack(alignment: .leading, spacing: 4) {
                dragPreviewMeta
                rowContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: 420, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color(red: 0.16, green: 0.17, blue: 0.20).opacity(0.96)
                        : Color.white.opacity(0.96)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 16, y: 6)
    }

    private func makeFavoriteDragPreviewImage() -> NSImage? {
        let renderer = ImageRenderer(
            content: favoriteDragPreviewCard
                .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.proposedSize = ProposedViewSize(width: 420, height: rowStride)
        return renderer.nsImage
    }

    private var dragPreviewMeta: some View {
        HStack(alignment: .center, spacing: 6) {
            sourceAppIcon

            kindBadge(title: kindBadgeTitle)

            Text(rowTimestamp(for: item.kind == .stack ? item.stackUpdatedAt : item.createdAt))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)
        }
    }

    private var rowMeta: some View {
        HStack(alignment: .center, spacing: 6) {
            sourceAppIcon

            kindBadge(title: kindBadgeTitle)

            if appState.activeTab != .favorites {
                Text(rowTimestamp(for: item.kind == .stack ? item.stackUpdatedAt : item.createdAt))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 0)

            if reserveActionWidth > 0 {
                Color.clear.frame(width: reserveActionWidth, height: 1)
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        switch item.kind {
        case .text:
            let unavailableMessage = services.unavailableRowMessage(for: item)
            VStack(alignment: .leading, spacing: unavailableMessage == nil ? 0 : 4) {
                Text(item.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        unavailableMessage == nil
                            ? Color.primary.opacity(0.96)
                            : Color.red.opacity(0.9)
                    )
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .lineSpacing(1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let unavailableMessage {
                    Text(unavailableMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.78))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .passthroughText:
            let unavailableMessage = services.unavailableRowMessage(for: item)
            let detailMessage = passthroughDetailMessage(unavailableMessage: unavailableMessage)
            VStack(alignment: .leading, spacing: detailMessage == nil ? 0 : 4) {
                if unavailableMessage == nil, item.isPendingPassthroughText {
                    PendingPassthroughIndicatorView(title: passthroughHeadline())
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(passthroughHeadline())
                        .font(.system(size: 13))
                        .foregroundStyle(
                            unavailableMessage == nil
                                ? Color.primary.opacity(0.96)
                                : Color.red.opacity(0.9)
                        )
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .lineSpacing(1.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let detailMessage {
                    Text(detailMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(
                            unavailableMessage == nil
                                ? Color.secondary.opacity(0.88)
                                : Color.red.opacity(0.78)
                        )
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .image:
            let hasUnavailableImage = services.hasUnavailableImageAsset(item)
            HStack(alignment: .center, spacing: 6) {
                imagePreview

                if hasUnavailableImage {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.imageMetadataSummary)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .lineLimit(1)

                        Text(localized("图片资源已失效，无法写回。"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.red.opacity(0.78))
                            .lineLimit(1)
                    }
                } else {
                    Text(item.imageMetadataSummary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .frame(height: 40, alignment: .center)
                }

                Spacer(minLength: 0)
            }
        case .file:
            let hasUnavailableFiles = services.hasUnavailableFiles(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(services.fileRowHeadline(for: item))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hasUnavailableFiles ? Color.red.opacity(0.9) : Color.primary.opacity(0.96))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(services.fileRowDetailLines(for: item).prefix(1).enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: index == 0 ? 12 : 11))
                        .foregroundStyle(
                            hasUnavailableFiles
                                ? Color.red.opacity(index == 0 ? 0.82 : 0.74)
                                : (index == 0 ? Color.primary.opacity(0.92) : .secondary)
                        )
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .stack:
            VStack(alignment: .leading, spacing: 2) {
                Text(EdgePanelLocalizationSupport.pendingPasteCount(item.stackEntries.count))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.96))

                ForEach(Array(services.stackPreviewLines(for: item).prefix(1).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func passthroughHeadline() -> String {
        switch item.passthroughTextMode {
        case .pending:
            return localized("超长文本准备中")
        case .clipboardOnly:
            return localized("超长文本未进入历史")
        case .abandoned:
            return localized("超长文本未完成读取")
        case .discarded:
            return localized("超长文本已丢弃")
        case .cachedOneTime:
            break
        case nil:
            break
        }

        let trimmedPreview = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPreview.isEmpty ? localized("超长文本不可用") : trimmedPreview
    }

    private func passthroughDetailMessage(unavailableMessage: String?) -> String? {
        switch item.passthroughTextMode {
        case .pending:
            return localized("当前仍可直接粘贴。若 8 秒内未完成，将不进入历史。")
        case .clipboardOnly:
            return localized("内容过大。当前仍可直接粘贴；复制下一条后将自动丢弃。")
        case .abandoned, .discarded:
            return unavailableMessage
        case .cachedOneTime:
            return unavailableMessage
        case nil:
            return unavailableMessage
        }
    }

    private var reserveActionWidth: CGFloat {
        var items: [(title: String, symbol: String, tint: Color)] = []
        if item.kind == .stack {
            items.append((localized("打开"), "arrow.right.circle", .secondary))
        } else if item.resolvedURL != nil {
            items.append((localized("访问"), "arrow.up.right.square", .secondary))
        }
        items.append((localized(isFavorited ? "已收藏" : "收藏"), isFavorited ? "star.fill" : "star", .secondary))
        items.append((localized("删除"), "trash", .red))
        return PanelRowActionsGroup.requiredWidth(for: items)
    }

    private var rowActions: some View {
        var items: [PanelRowActionsGroup.Item] = []
        if item.kind == .stack {
            items.append(.init(title: localized("打开"), symbol: "arrow.right.circle") {
                services.openStackSession(from: item)
            })
        } else if item.resolvedURL != nil {
            items.append(.init(title: localized("访问"), symbol: "arrow.up.right.square") {
                services.openResolvedURL(for: item)
            })
        }
        items.append(.init(title: localized(isFavorited ? "已收藏" : "收藏"), symbol: isFavorited ? "star.fill" : "star") {
            services.toggleFavorite(for: item.id)
        })
        items.append(.init(title: localized("删除"), symbol: "trash", tint: .red) {
            appState.remove(itemID: item.id)
        })

        return PanelRowActionsGroup(items: items)
    }

    private var kindBadgeTitle: String {
        switch item.kind {
        case .image:
            return PanelTab.image.title
        case .file:
            return PanelTab.file.title
        case .text:
            if item.resolvedURL != nil {
                return PanelTab.url.title
            }
            if item.isLikelyCode {
                return PanelTab.code.title
            }
            if item.hasTruncatedTextPreview {
                return localized("超长文本")
            }
            return PanelTab.text.title
        case .passthroughText:
            return localized("超长文本")
        case .stack:
            return localized("堆栈")
        }
    }

    private var sourceAppIcon: some View {
        HistorySourceAppIconView(
            services: services,
            item: item,
            deferAssetLoading: deferAssetLoading
        )
        .frame(width: 18, height: 18)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05))
        )
    }

    private func kindBadge(title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.78))
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05))
            )
    }

    private var imagePreview: some View {
        HistoryImagePreviewView(
            services: services,
            item: item,
            deferAssetLoading: deferAssetLoading,
            rememberedImage: rememberedPreviewImage,
            onImageResolved: onRememberedPreviewImage
        )
        .frame(width: 68, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var numberBadge: some View {
        PanelNumberBadgeView(badgeState: badgeState, colorScheme: colorScheme)
    }

    private var rowHoverColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.035)
    }

    private func rowTimestamp(for date: Date) -> String {
        EdgePanelLocalizationSupport.relativeTimestamp(for: date)
    }
}

private struct PanelNumberBadgeView: View {
    let badgeState: HistoryRowBadgeState
    let colorScheme: ColorScheme

    var body: some View {
        switch badgeState {
        case .hiddenTop:
            Text("0")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .frame(width: 20, height: 20)
                .padding(.top, 1)
        case .active(let number):
            Text(String(number))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.9))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 1)
                )
                .padding(.top, 1)
        case .inactive:
            Text("·")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.secondary.opacity(0.7))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 1)
                )
                .padding(.top, 1)
        }
    }
}

private struct PendingPassthroughIndicatorView: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "hourglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.72))

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.88))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            AnimatedEllipsisView()
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.secondary.opacity(0.78))
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }
}

private struct AnimatedEllipsisView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.45, paused: false)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.45) % 3
            Text(String(repeating: ".", count: phase + 1))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 24, alignment: .leading)
        }
    }
}

private struct FavoriteSnippetRowView: View {
    let services: AppServices
    let appState: AppState
    let snippet: FavoriteSnippet
    let isLast: Bool
    let badgeState: HistoryRowBadgeState
    let isPrimaryActionEnabled: Bool
    let isCurrentlyEditing: Bool
    let isHovered: Bool
    let actionsVisible: Bool
    let showsMoveToTopAction: Bool
    let showsReorderHandle: Bool
    let isReorderHandleVisible: Bool
    let isBeingDragged: Bool
    let showsReorderTooltip: Bool
    let rowStride: CGFloat
    let colorScheme: ColorScheme
    let onBeforePrimaryAction: () -> Void
    let onMoveToTop: () -> Void
    let onReorderHandleHoverChanged: (Bool) -> Void
    let onReorderStarted: (NSImage?) -> Void
    let onReorderEnded: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard isPrimaryActionEnabled else { return }
                onBeforePrimaryAction()
                services.pasteFavoriteSnippet(id: snippet.id)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    PanelNumberBadgeView(badgeState: badgeState, colorScheme: colorScheme)

                    VStack(alignment: .leading, spacing: 0) {
                        rowMeta
                            .frame(height: 20)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        rowContent
                            .padding(.top, 10)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background((isHovered || isCurrentlyEditing) ? rowHoverColor : Color.clear)
                .overlay(alignment: .bottom) {
                    if !isLast {
                        Rectangle()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                            .frame(height: 1)
                    }
                }
            }
            .buttonStyle(.plain)

            rowActions
                .padding(.top, 5)
                .padding(.trailing, 12)
                .opacity(actionsVisible ? 1 : 0)
                .allowsHitTesting(actionsVisible)
        }
        .overlay(alignment: .topLeading) {
            if showsReorderHandle {
                favoriteReorderHandle
                    .padding(.leading, 12)
                    .padding(.top, 30)
                    .opacity(isReorderHandleVisible ? 1 : 0)
                    .allowsHitTesting(isReorderHandleVisible)
            }
        }
        .frame(height: rowStride)
        .contentShape(Rectangle())
        .contextMenu {
            if !isCurrentlyEditing {
                Button(EdgePanelLocalizationSupport.localized("编辑")) {
                    services.openFavoriteSnippetEditor(snippetID: snippet.id)
                }

                if showsMoveToTopAction {
                    Button(EdgePanelLocalizationSupport.localized("移到最前")) {
                        onMoveToTop()
                    }
                }

                Menu(EdgePanelLocalizationSupport.localized("加入分组")) {
                    if appState.favoriteGroups.isEmpty {
                        Button(FavoriteGroup.defaultGeneratedName) {
                            services.addFavoriteSnippetToGroup(snippet.id, groupID: nil)
                        }
                    } else {
                        ForEach(appState.favoriteGroups) { group in
                            Button(group.name) {
                                services.addFavoriteSnippetToGroup(snippet.id, groupID: group.id)
                            }
                        }
                    }
                }

                if let activeGroupID = appState.activeFavoriteGroupID,
                   snippet.groupIDs.contains(activeGroupID) {
                    Button(EdgePanelLocalizationSupport.localized("从当前分组移除")) {
                        services.removeFavoriteSnippetFromActiveGroup(snippet.id)
                    }
                }

                Button(EdgePanelLocalizationSupport.localized("复制")) {
                    services.copyFavoriteSnippet(snippetID: snippet.id)
                }

                Button(role: .destructive) {
                    services.removeFavoriteSnippet(snippetID: snippet.id)
                } label: {
                    Text(EdgePanelLocalizationSupport.localized("删除"))
                }
            }
        }
    }

    private var rowMeta: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.78))
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05))
                )

            Text(EdgePanelLocalizationSupport.localized("收藏文本"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.78))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05))
                )

            Spacer(minLength: 0)

            if isCurrentlyEditing {
                FavoriteEditingStatusBadgeView(colorScheme: colorScheme)
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Color.clear.frame(width: reserveActionWidth, height: 1)
            }
        }
    }

    private var rowContent: some View {
        Text(snippet.previewText)
            .font(.system(size: 13))
            .foregroundStyle(Color.primary.opacity(0.96))
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .lineSpacing(1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var favoriteReorderHandle: some View {
        ZStack {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(isBeingDragged ? 0.96 : 0.82))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
                )

            FavoriteEntryLocalReorderDragSource(
                onHoverChanged: onReorderHandleHoverChanged,
                onDragStarted: {
                    onReorderStarted(makeFavoriteDragPreviewImage())
                },
                onDragEnded: onReorderEnded
            )
        }
        .frame(width: 20, height: 20)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .topLeading) {
            if showsReorderTooltip && !isBeingDragged {
                reorderHandleTooltipBubble("拖动调整顺序")
                    .offset(x: -4, y: 22)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                    .allowsHitTesting(false)
            }
        }
    }

    private func reorderHandleTooltipBubble(_ text: String) -> some View {
        Text(EdgePanelLocalizationSupport.localized(text))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.92))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color(red: 0.11, green: 0.12, blue: 0.14).opacity(0.96)
                            : Color.white.opacity(0.96)
                    )
                    .shadow(
                        color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.08),
                        radius: colorScheme == .dark ? 6 : 10,
                        y: colorScheme == .dark ? 2 : 4
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 1)
            )
    }

    private var favoriteDragPreviewCard: some View {
        HStack(alignment: .top, spacing: 10) {
            PanelNumberBadgeView(badgeState: badgeState, colorScheme: colorScheme)

            VStack(alignment: .leading, spacing: 4) {
                rowMeta
                rowContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(width: 420, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    colorScheme == .dark
                        ? Color(red: 0.16, green: 0.17, blue: 0.20).opacity(0.96)
                        : Color.white.opacity(0.96)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10), radius: 16, y: 6)
    }

    private func makeFavoriteDragPreviewImage() -> NSImage? {
        let renderer = ImageRenderer(
            content: favoriteDragPreviewCard
                .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.proposedSize = ProposedViewSize(width: 420, height: rowStride)
        return renderer.nsImage
    }

    private var reserveActionWidth: CGFloat {
        PanelRowActionsGroup.requiredWidth(for: [
            (EdgePanelLocalizationSupport.localized("编辑"), "pencil", .secondary),
            (EdgePanelLocalizationSupport.localized("已收藏"), "star.fill", .secondary),
            (EdgePanelLocalizationSupport.localized("删除"), "trash", .red)
        ])
    }

    private var rowActions: some View {
        PanelRowActionsGroup(items: [
            .init(title: EdgePanelLocalizationSupport.localized("编辑"), symbol: "pencil") {
                services.openFavoriteSnippetEditor(snippetID: snippet.id)
            },
            .init(title: EdgePanelLocalizationSupport.localized("已收藏"), symbol: "star.fill") {
                services.removeFavoriteSnippet(snippetID: snippet.id)
            },
            .init(title: EdgePanelLocalizationSupport.localized("删除"), symbol: "trash", tint: .red) {
                services.removeFavoriteSnippet(snippetID: snippet.id)
            }
        ])
    }

    private var rowHoverColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.035)
    }
}

private struct FavoriteEditingStatusBadgeView: View {
    let colorScheme: ColorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.45)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 3 + 1

            HStack(spacing: 4) {
                Text(EdgePanelLocalizationSupport.localized("编辑中"))
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(foregroundColor.opacity(index < phase ? 1 : 0.28))
                            .frame(width: dotDiameter, height: dotDiameter)
                    }
                }
                .frame(width: dotSlotWidth, alignment: .leading)
            }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    Capsule(style: .continuous)
                        .fill(fillColor)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                )
        }
    }

    private var fillColor: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.24)
            : Color.black.opacity(0.72)
    }

    private var strokeColor: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.52)
            : Color.black.opacity(0.10)
    }

    private var foregroundColor: Color {
        .white
    }

    private var dotSlotWidth: CGFloat {
        15
    }

    private var dotDiameter: CGFloat {
        3.5
    }
}

private struct HistorySourceAppIconView: View {
    let services: AppServices
    let item: ClipboardItem
    let deferAssetLoading: Bool

    @State private var loadedIcon: NSImage?

    var body: some View {
        Group {
            if item.kind == .stack {
                StackGlyphIcon(isSelected: false)
                    .frame(width: StackGlyphIcon.sourceSize, height: StackGlyphIcon.sourceSize)
            } else if let icon = loadedIcon ?? services.cachedSourceAppIcon(for: item) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(2)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: iconTaskID) {
            await loadIconIfNeeded()
        }
    }

    private var iconTaskID: String {
        "\(item.sourceAppBundleID ?? item.id.uuidString)-\(deferAssetLoading)"
    }

    private func loadIconIfNeeded() async {
        guard item.kind != .stack else { return }
        guard !deferAssetLoading else { return }

        if let cached = services.cachedSourceAppIcon(for: item) {
            loadedIcon = cached
            return
        }

        await Task.yield()
        guard !Task.isCancelled else { return }
        loadedIcon = services.sourceAppIcon(for: item)
    }
}

private struct HistoryImagePreviewView: View {
    let services: AppServices
    let item: ClipboardItem
    let deferAssetLoading: Bool
    let rememberedImage: NSImage?
    let onImageResolved: (NSImage) -> Void

    @State private var loadedImage: NSImage?

    var body: some View {
        Group {
            if let image = loadedImage ?? services.cachedPreviewImage(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .medium))
                    Text(deferAssetLoading ? "载入中" : "预览不可用")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: imageTaskID) {
            await loadPreviewIfNeeded()
        }
    }

    private var imageTaskID: String {
        "\(item.id.uuidString)-\(deferAssetLoading)"
    }

    private func loadPreviewIfNeeded() async {
        if let rememberedImage {
            loadedImage = rememberedImage
            onImageResolved(rememberedImage)
            return
        }

        if let cached = services.cachedPreviewImage(for: item) {
            loadedImage = cached
            onImageResolved(cached)
            return
        }

        guard !deferAssetLoading else { return }

        await Task.yield()
        guard !Task.isCancelled else { return }
        if let preview = services.previewImage(for: item) {
            loadedImage = preview
            onImageResolved(preview)
            return
        }
    }
}

private struct PanelRowActionsGroup: View {
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        var tint: Color = .secondary
        let action: () -> Void
    }

    let items: [Item]

    @State private var expandedIndex: Int?

    private static let collapsedDiameter: CGFloat = 28
    private static let spacing: CGFloat = 4

    static func reservedWidth(for title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let textWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        return max(40, textWidth + 24)
    }

    static func requiredWidth(for items: [(title: String, symbol: String, tint: Color)]) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        let maxExpandedWidth = items.map { reservedWidth(for: $0.title) }.max() ?? collapsedDiameter
        return maxExpandedWidth
            + CGFloat(max(0, items.count - 1)) * collapsedDiameter
            + CGFloat(max(0, items.count - 1)) * spacing
    }

    var body: some View {
        let maxExpandedWidth = items.map { Self.reservedWidth(for: $0.title) }.max() ?? Self.collapsedDiameter
        let totalWidth = Self.requiredWidth(for: items.map { ($0.title, $0.symbol, $0.tint) })

        return HStack(spacing: Self.spacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                PanelRowActionButton(
                    title: item.title,
                    symbol: item.symbol,
                    tint: item.tint,
                    width: expandedIndex == index ? maxExpandedWidth : Self.collapsedDiameter,
                    isExpanded: expandedIndex == index,
                    onHoverChanged: { hovering in
                        if hovering {
                            expandedIndex = index
                        }
                    },
                    action: item.action
                )
            }
        }
        .frame(width: totalWidth, alignment: .trailing)
        .contentShape(Rectangle())
        .onHover { hovering in
            if !hovering {
                expandedIndex = nil
            }
        }
    }
}

private struct PanelRowActionButton: View {
    let title: String
    let symbol: String
    var tint: Color = .secondary
    let width: CGFloat
    let isExpanded: Bool
    let onHoverChanged: (Bool) -> Void
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let collapsedDiameter: CGFloat = 28

    var body: some View {
        let iconFontSize: CGFloat = symbol == "arrow.up.right.square" ? 11 : 10

        Button(action: action) {
            ZStack {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
                    )
                    .frame(width: width, height: collapsedDiameter)

                HStack(spacing: isExpanded ? 4 : 0) {
                    Image(systemName: symbol)
                        .font(.system(size: iconFontSize, weight: .semibold))
                        .frame(width: 12, height: 12)

                    if isExpanded {
                        Text(title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                .foregroundStyle(tint)
                .frame(width: width, height: collapsedDiameter, alignment: .center)
            }
            .frame(width: width, height: collapsedDiameter)
            .animation(.easeInOut(duration: 0.10), value: isExpanded)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
    }
}

private struct TabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [PanelTab: CGRect] = [:]

    static func reduce(value: inout [PanelTab: CGRect], nextValue: () -> [PanelTab: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct PanelTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [PanelTab: CGRect] = [:]

    static func reduce(value: inout [PanelTab: CGRect], nextValue: () -> [PanelTab: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HistoryListFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() {
            value = next
        }
    }
}

private struct FavoriteGroupFramePreferenceKey: PreferenceKey {
    static var defaultValue: [PanelFavoriteGroupTarget: CGRect] = [:]

    static func reduce(value: inout [PanelFavoriteGroupTarget: CGRect], nextValue: () -> [PanelFavoriteGroupTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum HeaderControlFrameKey: Hashable {
    case close
    case search
    case favoriteAdd
    case stack
    case pin
}

private enum HeaderTooltipID: Hashable {
    case historyClose
    case search
    case favoriteAdd
    case stack
    case pin
    case stackBack
    case stackSequential
    case stackReverse
    case stackProcessor
    case stackClose
}

private struct HeaderControlFramePreferenceKey: PreferenceKey {
    static var defaultValue: [HeaderControlFrameKey: CGRect] = [:]

    static func reduce(value: inout [HeaderControlFrameKey: CGRect], nextValue: () -> [HeaderControlFrameKey: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HeaderTooltipFramePreferenceKey: PreferenceKey {
    static var defaultValue: [HeaderTooltipID: CGRect] = [:]

    static func reduce(value: inout [HeaderTooltipID: CGRect], nextValue: () -> [HeaderTooltipID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ViewSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private extension View {
    func measureSize(onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: ViewSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ViewSizePreferenceKey.self, perform: onChange)
    }
}

private struct FilterBarTrackingView: NSViewRepresentable {
    let onMove: (CGPoint) -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> FilterBarTrackingNSView {
        let view = FilterBarTrackingNSView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: FilterBarTrackingNSView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
        DispatchQueue.main.async {
            nsView.refreshCurrentPointerLocation()
        }
    }
}

private struct HistoryListTrackingView: NSViewRepresentable {
    let onMove: (CGPoint) -> Void
    let onExit: () -> Void

    func makeNSView(context: Context) -> HistoryListTrackingNSView {
        let view = HistoryListTrackingNSView()
        view.onMove = onMove
        view.onExit = onExit
        return view
    }

    func updateNSView(_ nsView: HistoryListTrackingNSView, context: Context) {
        nsView.onMove = onMove
        nsView.onExit = onExit
        DispatchQueue.main.async {
            nsView.refreshCurrentPointerLocation()
        }
    }
}

private struct PanelWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> PanelWindowDragNSView {
        PanelWindowDragNSView()
    }

    func updateNSView(_ nsView: PanelWindowDragNSView, context: Context) {}
}

private final class PanelPointerBridge {
    weak var view: NSView?

    func currentPointerLocation() -> CGPoint? {
        guard let view, let window = view.window else { return nil }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let localPoint = view.convert(windowPoint, from: nil)
        return CGPoint(x: localPoint.x, y: view.bounds.height - localPoint.y)
    }
}

private struct PanelPointerSpaceView: NSViewRepresentable {
    let bridge: PanelPointerBridge

    func makeNSView(context: Context) -> PanelPointerSpaceNSView {
        let view = PanelPointerSpaceNSView()
        bridge.view = view
        return view
    }

    func updateNSView(_ nsView: PanelPointerSpaceNSView, context: Context) {
        bridge.view = nsView
    }
}

private struct FavoriteReorderDragSource: NSViewRepresentable {
    let dragIdentifier: String
    let previewImageProvider: () -> NSImage?
    let onHoverChanged: (Bool) -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> FavoriteReorderDragSourceView {
        let view = FavoriteReorderDragSourceView()
        view.dragIdentifier = dragIdentifier
        view.previewImageProvider = previewImageProvider
        view.onHoverChanged = onHoverChanged
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: FavoriteReorderDragSourceView, context: Context) {
        nsView.dragIdentifier = dragIdentifier
        nsView.previewImageProvider = previewImageProvider
        nsView.onHoverChanged = onHoverChanged
        nsView.onDragStarted = onDragStarted
        nsView.onDragEnded = onDragEnded
        nsView.onClick = onClick
    }
}

private struct FavoriteEntryLocalReorderDragSource: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> FavoriteEntryLocalReorderDragSourceView {
        let view = FavoriteEntryLocalReorderDragSourceView()
        view.onHoverChanged = onHoverChanged
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: FavoriteEntryLocalReorderDragSourceView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
        nsView.onDragStarted = onDragStarted
        nsView.onDragEnded = onDragEnded
    }
}

private final class PanelWindowDragNSView: NSView {
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private final class PanelPointerSpaceNSView: NSView {
    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class FavoriteReorderDragSourceView: NSView, NSDraggingSource {
    var dragIdentifier: String?
    var previewImageProvider: (() -> NSImage?)?
    var onHoverChanged: ((Bool) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onClick: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var dragSessionStarted = false
    private var trackingArea: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        dragSessionStarted = false
        onHoverChanged?(false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragSessionStarted,
              let mouseDownEvent,
              let dragIdentifier else {
            return
        }

        let startPoint = convert(mouseDownEvent.locationInWindow, from: nil)
        let currentPoint = convert(event.locationInWindow, from: nil)
        guard hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y) >= 2 else {
            return
        }

        dragSessionStarted = true
        onDragStarted?()

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(dragIdentifier, forType: .string)
        pasteboardItem.setString(dragIdentifier, forType: NSPasteboard.PasteboardType(UTType.plainText.identifier))

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let image = previewImageProvider?() ?? NSImage(size: NSSize(width: 1, height: 1))
        let frame = NSRect(
            x: startPoint.x - 24,
            y: startPoint.y - (image.size.height * 0.55),
            width: image.size.width,
            height: image.size.height
        )
        draggingItem.setDraggingFrame(frame, contents: image)

        let session = beginDraggingSession(with: [draggingItem], event: mouseDownEvent, source: self)
        session.draggingFormation = .none
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    override func mouseUp(with event: NSEvent) {
        if !dragSessionStarted {
            onClick?()
        }
        mouseDownEvent = nil
        dragSessionStarted = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownEvent = nil
        dragSessionStarted = false
        onDragEnded?()
    }
}

private final class FavoriteEntryLocalReorderDragSourceView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var isDraggingLocally = false
    private var trackingArea: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        isDraggingLocally = false
        onHoverChanged?(false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isDraggingLocally, let mouseDownEvent else { return }
        let startPoint = convert(mouseDownEvent.locationInWindow, from: nil)
        let currentPoint = convert(event.locationInWindow, from: nil)
        guard hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y) >= 2 else {
            return
        }

        isDraggingLocally = true
        onDragStarted?()
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingLocally {
            onDragEnded?()
        }
        mouseDownEvent = nil
        isDraggingLocally = false
    }
}

private final class FilterBarTrackingNSView: NSView {
    var onMove: ((CGPoint) -> Void)?
    var onExit: (() -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private weak var previousMouseMovedWindow: NSWindow?
    private var previousAcceptsMouseMovedEvents = false
    private var hoverPollTimer: Timer?
    private var isPointerInside = false

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingAreaRef = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
        super.updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureMouseMovedEventsIfNeeded()
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        startHoverPollingIfNeeded()
        report(locationInWindow: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        report(locationInWindow: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        stopHoverPolling()
        onExit?()
    }

    override func removeFromSuperview() {
        stopHoverPolling()
        restoreMouseMovedEventsIfNeeded()
        super.removeFromSuperview()
    }

    func refreshCurrentPointerLocation() {
        guard let window else { return }
        let screenLocation = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenLocation)
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else {
            if isPointerInside {
                isPointerInside = false
                stopHoverPolling()
                onExit?()
            }
            return
        }
        if !isPointerInside {
            isPointerInside = true
            startHoverPollingIfNeeded()
        }
        onMove?(localPoint)
    }

    private func report(locationInWindow: CGPoint) {
        let localPoint = convert(locationInWindow, from: nil)
        guard bounds.contains(localPoint) else { return }
        onMove?(localPoint)
    }

    private func configureMouseMovedEventsIfNeeded() {
        guard let window else { return }
        if previousMouseMovedWindow !== window {
            restoreMouseMovedEventsIfNeeded()
            previousMouseMovedWindow = window
            previousAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
        }
        if !window.acceptsMouseMovedEvents {
            window.acceptsMouseMovedEvents = true
        }
    }

    private func startHoverPollingIfNeeded() {
        guard hoverPollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.refreshCurrentPointerLocation()
        }
        timer.tolerance = 1.0 / 240.0
        RunLoop.main.add(timer, forMode: .common)
        hoverPollTimer = timer
    }

    private func stopHoverPolling() {
        hoverPollTimer?.invalidate()
        hoverPollTimer = nil
    }

    private func restoreMouseMovedEventsIfNeeded() {
        guard let previousMouseMovedWindow else { return }
        stopHoverPolling()
        previousMouseMovedWindow.acceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
        self.previousMouseMovedWindow = nil
    }
}

private final class HistoryListTrackingNSView: NSView {
    var onMove: ((CGPoint) -> Void)?
    var onExit: (() -> Void)?

    private var trackingAreaRef: NSTrackingArea?
    private weak var previousMouseMovedWindow: NSWindow?
    private var previousAcceptsMouseMovedEvents = false

    override var isOpaque: Bool {
        false
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let trackingAreaRef = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaRef)
        self.trackingAreaRef = trackingAreaRef
        super.updateTrackingAreas()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureMouseMovedEventsIfNeeded()
    }

    override func mouseEntered(with event: NSEvent) {
        report(locationInWindow: event.locationInWindow)
    }

    override func mouseMoved(with event: NSEvent) {
        report(locationInWindow: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }

    override func removeFromSuperview() {
        restoreMouseMovedEventsIfNeeded()
        super.removeFromSuperview()
    }

    func refreshCurrentPointerLocation() {
        guard let window else { return }
        let screenLocation = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenLocation)
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else { return }
        onMove?(localPoint)
    }

    private func report(locationInWindow: CGPoint) {
        let localPoint = convert(locationInWindow, from: nil)
        guard bounds.contains(localPoint) else { return }
        onMove?(localPoint)
    }

    private func configureMouseMovedEventsIfNeeded() {
        guard let window else { return }
        if previousMouseMovedWindow !== window {
            restoreMouseMovedEventsIfNeeded()
            previousMouseMovedWindow = window
            previousAcceptsMouseMovedEvents = window.acceptsMouseMovedEvents
        }
        if !window.acceptsMouseMovedEvents {
            window.acceptsMouseMovedEvents = true
        }
    }

    private func restoreMouseMovedEventsIfNeeded() {
        guard let previousMouseMovedWindow else { return }
        previousMouseMovedWindow.acceptsMouseMovedEvents = previousAcceptsMouseMovedEvents
        self.previousMouseMovedWindow = nil
    }
}

private struct StackDragHandle: View {
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                    .fill(color)
                    .frame(width: 12, height: 1.4)
            }
        }
        .frame(width: 12, height: 8.8, alignment: .topLeading)
    }
}

private enum FavoriteReorderAutoScrollDirection {
    case up
    case down

    var deltaSign: CGFloat {
        switch self {
        case .up:
            return -1
        case .down:
            return 1
        }
    }
}

private struct StackEntryDropDelegate: DropDelegate {
    let targetEntryID: ClipboardItem.StackEntry.ID
    let entries: [ClipboardItem.StackEntry]
    @Binding var draggedEntryID: ClipboardItem.StackEntry.ID?
    let move: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedEntryID,
              draggedEntryID != targetEntryID,
              let fromIndex = entries.firstIndex(where: { $0.id == draggedEntryID }),
              let toIndex = entries.firstIndex(where: { $0.id == targetEntryID }) else {
            return
        }

        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        move(fromIndex, destination)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedEntryID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct FavoriteEntryDropDelegate: DropDelegate {
    let targetEntryKey: FavoriteEntryOrderKey
    let entries: [FavoritePanelEntry]
    @Binding var draggedEntryKey: FavoriteEntryOrderKey?
    let move: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedEntryKey,
              draggedEntryKey != targetEntryKey,
              let fromIndex = entries.firstIndex(where: { $0.orderKey == draggedEntryKey }),
              let toIndex = entries.firstIndex(where: { $0.orderKey == targetEntryKey }) else {
            return
        }

        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        move(fromIndex, destination)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedEntryKey = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct FavoriteAutoScrollDropDelegate: DropDelegate {
    let onUpdated: (CGPoint) -> Void
    let onExited: () -> Void
    let onDropped: () -> Void

    func dropEntered(info: DropInfo) {
        onUpdated(info.location)
    }

    func dropExited(info: DropInfo) {
        onExited()
    }

    func performDrop(info: DropInfo) -> Bool {
        onDropped()
        return false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onUpdated(info.location)
        return DropProposal(operation: .move)
    }
}

private struct FavoriteGroupDropDelegate: DropDelegate {
    let targetGroupID: FavoriteGroup.ID
    let groups: [FavoriteGroup]
    @Binding var draggedGroupID: FavoriteGroup.ID?
    let move: (Int, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedGroupID,
              draggedGroupID != targetGroupID,
              let fromIndex = groups.firstIndex(where: { $0.id == draggedGroupID }),
              let toIndex = groups.firstIndex(where: { $0.id == targetGroupID }) else {
            return
        }

        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        move(fromIndex, destination)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedGroupID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
