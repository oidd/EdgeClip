import Combine
import Foundation

enum PanelTab: String, CaseIterable, Codable {
    case all
    case text
    case image
    case file
    case favorites
    case code
    case url

    var title: String {
        switch self {
        case .all:
            return AppLocalization.localized("全部")
        case .text:
            return AppLocalization.localized("文本")
        case .image:
            return AppLocalization.localized("图片")
        case .file:
            return AppLocalization.localized("文件")
        case .favorites:
            return AppLocalization.localized("收藏")
        case .code:
            return AppLocalization.localized("代码")
        case .url:
            return AppLocalization.localized("网址")
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .text:
            return "text.alignleft"
        case .image:
            return "photo"
        case .file:
            return "doc"
        case .favorites:
            return "star"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .url:
            return "link"
        }
    }

    var isFixedDefault: Bool {
        switch self {
        case .all, .favorites:
            return true
        case .text, .image, .file, .code, .url:
            return false
        }
    }

    static let fixedDefaults: [PanelTab] = [.all, .favorites]
    static let replaceableChoices: [PanelTab] = [.text, .image, .file, .code, .url]
    static let defaultReplaceableSlots: [PanelTab] = [.text, .image, .file]

    static func sanitizedReplaceableSlots(from storedTabs: [PanelTab]) -> [PanelTab] {
        var result: [PanelTab] = []
        for tab in storedTabs where replaceableChoices.contains(tab) && !result.contains(tab) {
            result.append(tab)
            if result.count == 3 {
                break
            }
        }

        for tab in defaultReplaceableSlots where !result.contains(tab) {
            result.append(tab)
            if result.count == 3 {
                break
            }
        }
        return result
    }
}

enum RightDragHeaderTarget: Equatable {
    case close
    case search
    case favoriteAdd
    case stack
    case pin
}

enum PanelFavoriteGroupTarget: Hashable {
    case all
    case group(FavoriteGroup.ID)

    var groupID: FavoriteGroup.ID? {
        switch self {
        case .all:
            return nil
        case .group(let id):
            return id
        }
    }
}

enum PanelMode: Equatable {
    case history
    case stack
}

enum ImagePreviewLayoutMode: String, CaseIterable {
    case fit
    case fitWidth

    var title: String {
        switch self {
        case .fit:
            return AppLocalization.localized("全览")
        case .fitWidth:
            return AppLocalization.localized("细节")
        }
    }
}

enum ImagePreviewWidthTier: String {
    case standard
    case expanded

    var badgeSymbolName: String {
        switch self {
        case .standard:
            return "plus"
        case .expanded:
            return "minus"
        }
    }
}

struct ActiveStackSession: Equatable {
    var historyItemID: ClipboardItem.ID?
    var entries: [ClipboardItem.StackEntry]
    var orderMode: StackOrderMode
    var updatedAt: Date

    init(
        historyItemID: ClipboardItem.ID? = nil,
        entries: [ClipboardItem.StackEntry] = [],
        orderMode: StackOrderMode = .sequential,
        updatedAt: Date = Date()
    ) {
        self.historyItemID = historyItemID
        self.entries = entries
        self.orderMode = orderMode
        self.updatedAt = updatedAt
    }
}

struct TransientNotice: Equatable, Identifiable {
    enum Tone: Equatable {
        case info
        case warning
    }

    let id: UUID
    let message: String
    let tone: Tone

    init(id: UUID = UUID(), message: String, tone: Tone = .warning) {
        self.id = id
        self.message = message
        self.tone = tone
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var history: [ClipboardItem] = []
    @Published private(set) var favoriteSnippets: [FavoriteSnippet] = []
    @Published private(set) var favoriteGroups: [FavoriteGroup] = []
    @Published var settings = AppSettings()
    @Published var permissionGranted: Bool = false
    @Published var lastErrorMessage: String?
    @Published var transientNotice: TransientNotice?
    var panelVisibleStartIndex: Int = 0
    @Published private(set) var historyDiskUsageBytes: Int = 0
    @Published private(set) var panelPresentationID: Int = 0
    @Published private(set) var resolvedAppLanguage: AppResolvedLanguage = .english
    @Published private(set) var appLocaleIdentifier: String = AppResolvedLanguage.english.localeIdentifier

    @Published var panelMode: PanelMode = .history
    @Published var activeTab: PanelTab = .all
    @Published var searchQuery = ""
    @Published var isPanelPinned = false
    var hoveredRowID: ClipboardItem.ID?
    @Published var rightDragHighlightedRowID: ClipboardItem.ID?
    @Published var isRightDragSelecting = false
    @Published var rightDragScrollCommandToken: Int = 0
    @Published var rightDragScrollDelta: CGFloat = 0
    @Published var rightDragHeaderTarget: RightDragHeaderTarget?
    @Published var rightDragHoveredTab: PanelTab?
    @Published var searchRevealRequestToken: Int = 0
    @Published var onboardingPresentationRequestToken: Int = 0
    @Published var rightDragConflictNoticeDismissed = false
    @Published var imagePreviewLayoutMode: ImagePreviewLayoutMode = .fit
    @Published var imagePreviewWidthTier: ImagePreviewWidthTier = .standard
    @Published var activeStackSession: ActiveStackSession?
    @Published var dormantStackItemID: ClipboardItem.ID?
    @Published var isStackProcessorPresented = false
    @Published var stackProcessorDraft = ""
    @Published var isFavoriteEditorPresented = false
    @Published var activeFavoriteSnippetID: FavoriteSnippet.ID?
    @Published var activeFavoriteGroupID: FavoriteGroup.ID?
    @Published var favoriteEditorDraft = ""
    @Published var favoriteEditorInitialDraft = ""
    @Published var favoriteGroupRenameRequestToken: Int = 0
    @Published var stackDelimiterOptions: Set<StackDelimiterOption> = [.newline]
    @Published var stackCustomDelimiter = ""
    @Published var preStackPinState: Bool?
    @Published var preFavoriteEditorPinState: Bool?
    var panelHiddenTopIndex: Int?
    var panelScrollOffset: CGFloat = 0
    var isPanelTabHoverUnlocked = true
    var panelHistoryListFrame: CGRect?
    var panelTabFrames: [PanelTab: CGRect] = [:]
    var panelFavoriteGroupFrames: [PanelFavoriteGroupTarget: CGRect] = [:]
    var panelCloseButtonFrame: CGRect?
    var panelSearchButtonFrame: CGRect?
    var panelFavoriteAddButtonFrame: CGRect?
    var panelStackButtonFrame: CGRect?
    var panelPinButtonFrame: CGRect?
    var pendingFavoriteGroupRenameID: FavoriteGroup.ID?

    var onItemsRemoved: (([ClipboardItem]) -> Void)?

    init() {
        synchronizeLocalization()
    }

    var appLocale: Locale {
        Locale(identifier: appLocaleIdentifier)
    }

    func filteredHistory(for tab: PanelTab, matching query: String? = nil) -> [ClipboardItem] {
        let baseItems: [ClipboardItem]
        switch tab {
        case .all:
            baseItems = history
        case .text:
            baseItems = history.filter { $0.kind == .text || $0.kind == .passthroughText }
        case .image:
            baseItems = history.filter { $0.kind == .image }
        case .file:
            baseItems = history.filter { $0.kind == .file }
        case .favorites:
            baseItems = filteredFavoriteHistoryItems(in: activeFavoriteGroupID, matching: nil)
        case .code:
            baseItems = history.filter(\.isLikelyCode)
        case .url:
            baseItems = history.filter(\.isLikelyURL)
        }

        let normalizedQuery = (query ?? searchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return baseItems
        }

        return baseItems.filter { $0.matchesSearchQuery(normalizedQuery) }
    }

    var filteredHistory: [ClipboardItem] {
        filteredHistory(for: activeTab)
    }

    func filteredFavoriteSnippets(
        in groupID: FavoriteGroup.ID? = nil,
        matching query: String? = nil
    ) -> [FavoriteSnippet] {
        let normalizedQuery = (query ?? searchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        let groupedSnippets = orderedFavoritePanelEntries(in: groupID)
            .compactMap(\.snippet)
        guard !normalizedQuery.isEmpty else { return groupedSnippets }

        return groupedSnippets.filter { $0.matchesSearchQuery(normalizedQuery) }
    }

    func filteredFavoriteHistoryItems(
        in groupID: FavoriteGroup.ID? = nil,
        matching query: String? = nil
    ) -> [ClipboardItem] {
        let normalizedQuery = (query ?? searchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        let groupedItems = orderedFavoritePanelEntries(in: groupID)
            .compactMap(\.historyItem)

        guard !normalizedQuery.isEmpty else { return groupedItems }
        return groupedItems.filter { $0.matchesSearchQuery(normalizedQuery) }
    }

    func favoritePanelEntries(
        in groupID: FavoriteGroup.ID? = nil,
        matching query: String? = nil
    ) -> [FavoritePanelEntry] {
        let normalizedQuery = (query ?? searchQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = orderedFavoritePanelEntries(in: groupID)
        guard !normalizedQuery.isEmpty else { return entries }

        return entries.filter { entry in
            switch entry {
            case .snippet(let snippet):
                return snippet.matchesSearchQuery(normalizedQuery)
            case .historyItem(let item):
                return item.matchesSearchQuery(normalizedQuery)
            }
        }
    }

    var visiblePanelTabs: [PanelTab] {
        PanelTab.fixedDefaults + Array(PanelTab.sanitizedReplaceableSlots(from: settings.panelReplaceableTabs).prefix(3))
    }

    func ingest(_ item: ClipboardItem) {
        guard isMeaningful(item) else { return }

        var removedItems: [ClipboardItem] = []
        if let identity = item.duplicateIdentityKey {
            let duplicateIndexes = history.enumerated()
                .filter { $0.element.duplicateIdentityKey == identity }
                .map(\.offset)

            if let firstIndex = duplicateIndexes.first, firstIndex == 0 {
                return
            }

            if let firstIndex = duplicateIndexes.first {
                let existing = history[firstIndex]
                let promoted = existing.refreshed(using: item)
                history.remove(at: firstIndex)
                history.insert(promoted, at: 0)

                let promotedID = promoted.id
                let extras = history.filter {
                    $0.duplicateIdentityKey == identity && $0.id != promotedID
                }
                removedItems.append(contentsOf: extras)
                history.removeAll {
                    $0.duplicateIdentityKey == identity && $0.id != promotedID
                }

                history = sortHistory(history)
                notifyRemovedItems(removedItems)
                applyHistoryPolicies()
                return
            }
        }

        history.insert(item, at: 0)
        history = sortHistory(history)
        notifyRemovedItems(removedItems)
        applyHistoryPolicies()
    }

    func prependHistoryItem(_ item: ClipboardItem, collapseDuplicates: Bool) {
        guard isMeaningful(item) else { return }
        history.insert(item, at: 0)
        history = sortHistory(history)
        applyHistoryPolicies(collapseDuplicates: collapseDuplicates)
    }

    func restoreHistory(_ items: [ClipboardItem]) {
        history = sortHistory(
            items
                .filter { isMeaningful($0) }
                .map { item in
                    var item = item
                    item.favoriteGroupIDs = sanitizedFavoriteGroupIDs(item.favoriteGroupIDs)
                    return item
                }
        )
        applyHistoryPolicies()
        sanitizeFavoriteGroupReferences()
        normalizeFavoriteGroupMemberOrders()
    }

    func restoreFavoriteSnippets(_ snippets: [FavoriteSnippet]) {
        favoriteSnippets = sortFavoriteSnippets(
            snippets
                .filter(\.isMeaningful)
                .map { snippet in
                    var snippet = snippet
                    snippet.groupIDs = sanitizedFavoriteGroupIDs(snippet.groupIDs)
                    return snippet
                }
        )
        normalizeGlobalFavoritePanelSortOrders()
        sanitizeFavoriteGroupReferences()
        normalizeFavoriteGroupMemberOrders()
    }

    func restoreFavoriteGroups(_ groups: [FavoriteGroup]) {
        favoriteGroups = sortFavoriteGroups(groups.filter(\.isMeaningful))
        normalizeFavoriteGroupSortOrders()
        sanitizeFavoriteGroupReferences()
        normalizeFavoriteGroupMemberOrders()
    }

    func applyHistoryPolicies() {
        applyHistoryPolicies(collapseDuplicates: true)
    }

    private func applyHistoryPolicies(collapseDuplicates: Bool) {
        let original = history
        var retained = sortHistory(history)

        if collapseDuplicates {
            retained = collapseDuplicateHistory(retained)
        }
        retained = trimExpiredHistoryIfNeeded(retained)
        retained = trimHistoryByCountIfNeeded(retained)
        retained = trimHistoryByDiskUsageIfNeeded(retained)
        retained = sortHistory(retained)

        let removed = removedItems(from: original, retained: retained)
        if retained != original {
            history = retained
        }
        normalizeGlobalFavoritePanelSortOrders()
        normalizeFavoriteGroupMemberOrders()
        recalculateHistoryDiskUsage(for: retained)
        notifyRemovedItems(removed)
        clampPanelVisibleStartIndex()
    }

    func toggleFavorite(for itemID: ClipboardItem.ID) {
        guard let index = history.firstIndex(where: { $0.id == itemID }) else { return }
        history[index].isFavorite.toggle()
        if history[index].isFavorite {
            history[index].favoriteSortOrder = favoritePanelTopSortOrder(excluding: .historyItem(itemID))
            history[index].favoriteGroupIDs = sanitizedFavoriteGroupIDs(history[index].favoriteGroupIDs)
        } else {
            history[index].favoriteSortOrder = nil
            history[index].favoriteGroupIDs = []
        }
        history = sortHistory(history)
        normalizeGlobalFavoritePanelSortOrders()
        normalizeFavoriteGroupMemberOrders()
        recalculateHistoryDiskUsage()
        clampPanelVisibleStartIndex()
    }

    func remove(itemID: ClipboardItem.ID) {
        let removed = history.filter { $0.id == itemID }
        history.removeAll { $0.id == itemID }
        normalizeFavoriteGroupMemberOrders()
        recalculateHistoryDiskUsage()
        clampPanelVisibleStartIndex()
        notifyRemovedItems(removed)
    }

    func addBlacklistBundleID(_ bundleID: String) {
        addBlacklistBundleIDs([bundleID])
    }

    func addBlacklistBundleIDs(_ bundleIDs: [String]) {
        let normalized = Set(
            bundleIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !normalized.isEmpty else { return }
        updateSettings { settings in
            settings.blacklistedBundleIDs.formUnion(normalized)
        }
    }

    func removeBlacklistBundleID(_ bundleID: String) {
        updateSettings { settings in
            settings.blacklistedBundleIDs.remove(bundleID)
        }
    }

    func item(withID itemID: ClipboardItem.ID) -> ClipboardItem? {
        history.first { $0.id == itemID }
    }

    func updateItem(itemID: ClipboardItem.ID, mutate: (inout ClipboardItem) -> Void) {
        guard let index = history.firstIndex(where: { $0.id == itemID }) else { return }
        let wasFavorite = history[index].isFavorite
        mutate(&history[index])
        if history[index].isFavorite {
            if !wasFavorite || history[index].favoriteSortOrder == nil {
                history[index].favoriteSortOrder = favoritePanelTopSortOrder(excluding: .historyItem(itemID))
            }
            history[index].favoriteGroupIDs = sanitizedFavoriteGroupIDs(history[index].favoriteGroupIDs)
        } else {
            history[index].favoriteSortOrder = nil
            history[index].favoriteGroupIDs = []
        }
        history = sortHistory(history)
        normalizeGlobalFavoritePanelSortOrders()
        normalizeFavoriteGroupMemberOrders()
        recalculateHistoryDiskUsage()
        clampPanelVisibleStartIndex()
    }

    func favoriteSnippet(withID snippetID: FavoriteSnippet.ID) -> FavoriteSnippet? {
        favoriteSnippets.first { $0.id == snippetID }
    }

    func addFavoriteSnippet(_ snippet: FavoriteSnippet) {
        guard snippet.isMeaningful else { return }
        var snippet = snippet
        snippet.sortOrder = favoritePanelTopSortOrder(excluding: .snippet(snippet.id))
        snippet.groupIDs = sanitizedFavoriteGroupIDs(snippet.groupIDs)
        favoriteSnippets.insert(snippet, at: 0)
        favoriteSnippets = sortFavoriteSnippets(favoriteSnippets)
        normalizeGlobalFavoritePanelSortOrders()
        normalizeFavoriteGroupMemberOrders()
    }

    func updateFavoriteSnippet(snippetID: FavoriteSnippet.ID, mutate: (inout FavoriteSnippet) -> Void) {
        guard let index = favoriteSnippets.firstIndex(where: { $0.id == snippetID }) else { return }
        mutate(&favoriteSnippets[index])
        guard favoriteSnippets[index].isMeaningful else {
            favoriteSnippets.remove(at: index)
            normalizeGlobalFavoritePanelSortOrders()
            normalizeFavoriteGroupMemberOrders()
            return
        }
        favoriteSnippets[index].groupIDs = sanitizedFavoriteGroupIDs(favoriteSnippets[index].groupIDs)
        favoriteSnippets[index].updatedAt = Date()
        favoriteSnippets = sortFavoriteSnippets(favoriteSnippets)
        normalizeGlobalFavoritePanelSortOrders()
        normalizeFavoriteGroupMemberOrders()
    }

    func removeFavoriteSnippet(snippetID: FavoriteSnippet.ID) {
        favoriteSnippets.removeAll { $0.id == snippetID }
        normalizeGlobalFavoritePanelSortOrders()
        normalizeFavoriteGroupMemberOrders()
    }

    func favoriteGroup(withID groupID: FavoriteGroup.ID) -> FavoriteGroup? {
        favoriteGroups.first { $0.id == groupID }
    }

    func selectFavoriteGroup(_ groupID: FavoriteGroup.ID?) {
        activeFavoriteGroupID = groupID
    }

    func addFavoriteGroup(named requestedName: String) -> FavoriteGroup {
        let uniqueName = uniqueFavoriteGroupName(for: requestedName)
        var group = FavoriteGroup(name: uniqueName)
        group.sortOrder = favoriteGroupNextSortOrder(in: favoriteGroups, excluding: group.id)
        favoriteGroups.append(group)
        favoriteGroups = sortFavoriteGroups(favoriteGroups)
        normalizeFavoriteGroupSortOrders()
        normalizeFavoriteGroupMemberOrders()
        return group
    }

    func updateFavoriteGroup(groupID: FavoriteGroup.ID, mutate: (inout FavoriteGroup) -> Void) {
        guard let index = favoriteGroups.firstIndex(where: { $0.id == groupID }) else { return }
        mutate(&favoriteGroups[index])
        favoriteGroups[index].name = uniqueFavoriteGroupName(
            for: favoriteGroups[index].name,
            excluding: groupID
        )
        favoriteGroups[index].updatedAt = Date()
        favoriteGroups = sortFavoriteGroups(favoriteGroups.filter(\.isMeaningful))
        normalizeFavoriteGroupSortOrders()
        normalizeFavoriteGroupMemberOrders()
    }

    func removeFavoriteGroup(groupID: FavoriteGroup.ID) {
        favoriteGroups.removeAll { $0.id == groupID }

        for index in favoriteSnippets.indices {
            favoriteSnippets[index].groupIDs.removeAll { $0 == groupID }
        }

        for index in history.indices {
            history[index].favoriteGroupIDs.removeAll { $0 == groupID }
        }

        if activeFavoriteGroupID == groupID {
            activeFavoriteGroupID = nil
        }
        normalizeFavoriteGroupMemberOrders()
    }

    func requestFavoriteGroupRename(_ groupID: FavoriteGroup.ID) {
        pendingFavoriteGroupRenameID = groupID
        favoriteGroupRenameRequestToken &+= 1
    }

    func clearFavoriteGroupRenameRequest() {
        pendingFavoriteGroupRenameID = nil
    }

    func addFavoriteGroupReference(_ groupID: FavoriteGroup.ID, toFavoriteSnippetID snippetID: FavoriteSnippet.ID) {
        updateFavoriteSnippet(snippetID: snippetID) { snippet in
            if !snippet.groupIDs.contains(groupID) {
                snippet.groupIDs.append(groupID)
            }
        }
        moveFavoriteSnippetToTopInGroup(snippetID, groupID: groupID)
    }

    func addFavoriteGroupReference(_ groupID: FavoriteGroup.ID, toHistoryItemID itemID: ClipboardItem.ID) {
        updateItem(itemID: itemID) { item in
            guard item.isFavorite else { return }
            if !item.favoriteGroupIDs.contains(groupID) {
                item.favoriteGroupIDs.append(groupID)
            }
        }
        moveFavoriteItemToTopInGroup(itemID, groupID: groupID)
    }

    func removeFavoriteGroupReference(_ groupID: FavoriteGroup.ID, fromFavoriteSnippetID snippetID: FavoriteSnippet.ID) {
        updateFavoriteSnippet(snippetID: snippetID) { snippet in
            snippet.groupIDs.removeAll { $0 == groupID }
        }
    }

    func removeFavoriteGroupReference(_ groupID: FavoriteGroup.ID, fromHistoryItemID itemID: ClipboardItem.ID) {
        updateItem(itemID: itemID) { item in
            item.favoriteGroupIDs.removeAll { $0 == groupID }
        }
    }

    func applyFavoriteGroupOrdering(_ orderedGroupIDs: [FavoriteGroup.ID]) {
        guard !orderedGroupIDs.isEmpty else { return }

        let currentGroupIDs = favoriteGroups.map(\.id)
        let mergedGroupIDs = orderedGroupIDs + currentGroupIDs.filter { !orderedGroupIDs.contains($0) }
        for (order, groupID) in mergedGroupIDs.enumerated() {
            guard let index = favoriteGroups.firstIndex(where: { $0.id == groupID }) else { continue }
            favoriteGroups[index].sortOrder = order
        }

        favoriteGroups = sortFavoriteGroups(favoriteGroups)
        normalizeFavoriteGroupSortOrders()
    }

    func applyFavoriteOrdering(_ orderedFavoriteIDs: [ClipboardItem.ID], in groupID: FavoriteGroup.ID? = nil) {
        guard !orderedFavoriteIDs.isEmpty else { return }

        if let groupID {
            guard let index = favoriteGroups.firstIndex(where: { $0.id == groupID }) else { return }
            let currentFavoriteIDs = orderedFavoritePanelEntries(in: groupID)
                .compactMap(\.historyItem)
                .map(\.id)
            let mergedFavoriteIDs = orderedFavoriteIDs + currentFavoriteIDs.filter { !orderedFavoriteIDs.contains($0) }
            let currentOrder = groupMemberOrderKeys(for: favoriteGroups[index])
            var mergedIterator = mergedFavoriteIDs.makeIterator()
            favoriteGroups[index].memberOrder = currentOrder.compactMap { entryKey in
                switch entryKey {
                case .snippet:
                    return entryKey.rawValue
                case .historyItem:
                    guard let nextID = mergedIterator.next() else { return nil }
                    return FavoriteEntryOrderKey.historyItem(nextID).rawValue
                }
            }
            favoriteGroups[index].updatedAt = Date()
            normalizeFavoriteGroupMemberOrders()
            return
        }

        let currentFavoriteIDs = orderedFavoritePanelEntries(in: nil)
            .compactMap(\.historyItem)
            .map(\.id)
        let mergedFavoriteIDs = orderedFavoriteIDs + currentFavoriteIDs.filter { !orderedFavoriteIDs.contains($0) }
        let currentOrder = currentGlobalFavoriteEntryOrder()
        var mergedIterator = mergedFavoriteIDs.makeIterator()
        let updatedOrder = currentOrder.compactMap { entryKey -> FavoriteEntryOrderKey? in
            switch entryKey {
            case .snippet:
                return entryKey
            case .historyItem:
                guard let nextID = mergedIterator.next() else { return nil }
                return .historyItem(nextID)
            }
        }

        applyGlobalFavoriteEntryOrdering(updatedOrder)
        normalizeFavoriteGroupMemberOrders()
        recalculateHistoryDiskUsage()
        clampPanelVisibleStartIndex()
    }

    func applyFavoriteSnippetOrdering(_ orderedSnippetIDs: [FavoriteSnippet.ID], in groupID: FavoriteGroup.ID? = nil) {
        guard !orderedSnippetIDs.isEmpty else { return }

        if let groupID {
            guard let index = favoriteGroups.firstIndex(where: { $0.id == groupID }) else { return }
            let currentSnippetIDs = orderedFavoritePanelEntries(in: groupID)
                .compactMap(\.snippet)
                .map(\.id)
            let mergedSnippetIDs = orderedSnippetIDs + currentSnippetIDs.filter { !orderedSnippetIDs.contains($0) }
            let currentOrder = groupMemberOrderKeys(for: favoriteGroups[index])
            var mergedIterator = mergedSnippetIDs.makeIterator()
            favoriteGroups[index].memberOrder = currentOrder.compactMap { entryKey in
                switch entryKey {
                case .snippet:
                    guard let nextID = mergedIterator.next() else { return nil }
                    return FavoriteEntryOrderKey.snippet(nextID).rawValue
                case .historyItem:
                    return entryKey.rawValue
                }
            }
            favoriteGroups[index].updatedAt = Date()
            normalizeFavoriteGroupMemberOrders()
            return
        }

        let currentSnippetIDs = orderedFavoritePanelEntries(in: nil)
            .compactMap(\.snippet)
            .map(\.id)
        let mergedSnippetIDs = orderedSnippetIDs + currentSnippetIDs.filter { !orderedSnippetIDs.contains($0) }
        let currentOrder = currentGlobalFavoriteEntryOrder()
        var mergedIterator = mergedSnippetIDs.makeIterator()
        let updatedOrder = currentOrder.compactMap { entryKey -> FavoriteEntryOrderKey? in
            switch entryKey {
            case .snippet:
                guard let nextID = mergedIterator.next() else { return nil }
                return .snippet(nextID)
            case .historyItem:
                return entryKey
            }
        }

        applyGlobalFavoriteEntryOrdering(updatedOrder)
        normalizeFavoriteGroupMemberOrders()
    }

    func applyFavoriteEntryOrdering(_ orderedEntries: [FavoriteEntryOrderKey], in groupID: FavoriteGroup.ID? = nil) {
        guard !orderedEntries.isEmpty else { return }

        if let groupID {
            guard let index = favoriteGroups.firstIndex(where: { $0.id == groupID }) else { return }
            let currentOrder = orderedFavoritePanelEntries(in: groupID).map(\.orderKey)
            let mergedOrder = orderedEntries + currentOrder.filter { !orderedEntries.contains($0) }
            favoriteGroups[index].memberOrder = mergedOrder.map(\.rawValue)
            favoriteGroups[index].updatedAt = Date()
            normalizeFavoriteGroupMemberOrders()
            return
        }

        let currentOrder = currentGlobalFavoriteEntryOrder()
        let mergedOrder = orderedEntries + currentOrder.filter { !orderedEntries.contains($0) }
        applyGlobalFavoriteEntryOrdering(mergedOrder)
        normalizeFavoriteGroupMemberOrders()
        recalculateHistoryDiskUsage()
        clampPanelVisibleStartIndex()
    }

    func updateActiveStackSession(_ mutate: (inout ActiveStackSession) -> Void) {
        guard var session = activeStackSession else { return }
        mutate(&session)
        session.updatedAt = Date()
        activeStackSession = session
    }

    func replaceItem(itemID: ClipboardItem.ID, with item: ClipboardItem) {
        guard let index = history.firstIndex(where: { $0.id == itemID }) else { return }

        var replacement = item
        if !replacement.isSessionOnly {
            replacement.isFavorite = history[index].isFavorite
            replacement.favoriteSortOrder = history[index].favoriteSortOrder
            replacement.favoriteGroupIDs = history[index].favoriteGroupIDs
        }

        history[index] = replacement
        history = sortHistory(history)
        applyHistoryPolicies()
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        updated.panelReplaceableTabs = PanelTab.sanitizedReplaceableSlots(from: updated.panelReplaceableTabs)
        updated.hotkeyPanelShortcut.normalize()
        updated.hotkeyFavoritesShortcut.normalize()
        if !updated.hotkeyPanelShortcut.isConfigured {
            updated.hotkeyPanelShortcut = .defaultPanelTrigger
        }
        if updated.hotkeyTriggerMode == .doubleModifier {
            if updated.hotkeyFavoritesModifier == updated.hotkeyPanelModifier {
                updated.hotkeyFavoritesModifier = nil
            }
        } else if updated.hotkeyFavoritesShortcut.conflicts(with: updated.hotkeyPanelShortcut) {
            updated.hotkeyFavoritesShortcut = KeyboardShortcut()
        }
        updated.dataStorageCustomDirectoryPath = updated.dataStorageCustomDirectoryPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if updated.dataStorageCustomDirectoryPath?.isEmpty == true {
            updated.dataStorageCustomDirectoryPath = nil
        }
        if updated.dataStorageCustomDirectoryPath == nil {
            updated.dataStorageCustomDirectoryBookmark = nil
        }
        updated.edgeActivationCustomVerticalPosition = min(
            1,
            max(0, updated.edgeActivationCustomVerticalPosition)
        )
        updated.edgePanelAutoCollapseDistance = max(0, updated.edgePanelAutoCollapseDistance)
        updated.pinnedPanelIdleTransparencyPercent = min(
            90,
            max(0, updated.pinnedPanelIdleTransparencyPercent)
        )
        settings = updated
        synchronizeLocalization()
        if !visiblePanelTabs.contains(activeTab) {
            activeTab = .all
        }
    }

    func synchronizeLocalization(preferredLanguages: [String] = Locale.preferredLanguages) {
        let language = settings.language.resolvedLanguage(preferredLanguages: preferredLanguages)
        let localeIdentifier = language.localeIdentifier
        AppLocalization.updateCurrentLanguage(language)

        if resolvedAppLanguage != language {
            resolvedAppLanguage = language
        }
        if appLocaleIdentifier != localeIdentifier {
            appLocaleIdentifier = localeIdentifier
        }
    }

    func requestOnboardingPresentation() {
        onboardingPresentationRequestToken &+= 1
    }

    func resetPanelStateForPresentation() {
        panelPresentationID &+= 1
        panelMode = .history
        activeTab = .all
        searchQuery = ""
        isPanelPinned = false
        hoveredRowID = nil
        rightDragHighlightedRowID = nil
        isRightDragSelecting = false
        rightDragScrollCommandToken = 0
        rightDragScrollDelta = 0
        rightDragHeaderTarget = nil
        rightDragHoveredTab = nil
        searchRevealRequestToken = 0
        imagePreviewLayoutMode = .fit
        imagePreviewWidthTier = .standard
        panelScrollOffset = 0
        isPanelTabHoverUnlocked = true
        panelVisibleStartIndex = 0
        panelHiddenTopIndex = nil
        activeStackSession = nil
        isStackProcessorPresented = false
        stackProcessorDraft = ""
        isFavoriteEditorPresented = false
        activeFavoriteSnippetID = nil
        activeFavoriteGroupID = nil
        favoriteEditorDraft = ""
        favoriteEditorInitialDraft = ""
        pendingFavoriteGroupRenameID = nil
        preStackPinState = nil
        preFavoriteEditorPinState = nil
    }

    func clearTransientPanelState() {
        panelMode = .history
        hoveredRowID = nil
        rightDragHighlightedRowID = nil
        isRightDragSelecting = false
        rightDragScrollCommandToken = 0
        rightDragScrollDelta = 0
        imagePreviewLayoutMode = .fit
        imagePreviewWidthTier = .standard
        rightDragHeaderTarget = nil
        rightDragHoveredTab = nil
        panelScrollOffset = 0
        isPanelTabHoverUnlocked = true
        panelVisibleStartIndex = 0
        panelHiddenTopIndex = nil
        activeStackSession = nil
        isStackProcessorPresented = false
        stackProcessorDraft = ""
        isFavoriteEditorPresented = false
        activeFavoriteSnippetID = nil
        activeFavoriteGroupID = nil
        favoriteEditorDraft = ""
        favoriteEditorInitialDraft = ""
        pendingFavoriteGroupRenameID = nil
        preStackPinState = nil
        preFavoriteEditorPinState = nil
    }

    func selectImagePreviewLayoutMode(_ mode: ImagePreviewLayoutMode) {
        if imagePreviewLayoutMode == mode {
            imagePreviewWidthTier = imagePreviewWidthTier == .standard ? .expanded : .standard
            return
        }

        imagePreviewLayoutMode = mode
        imagePreviewWidthTier = .standard
    }

    func setDefaultImagePreviewLayoutMode(_ mode: ImagePreviewLayoutMode) {
        imagePreviewLayoutMode = mode
        imagePreviewWidthTier = .standard
    }

    func promoteItemAfterPasteIfNeeded(_ itemID: ClipboardItem.ID) {
        guard settings.pastedItemPlacement == .moveToTop else { return }
        guard let index = history.firstIndex(where: { $0.id == itemID }) else { return }
        guard index != 0 else { return }

        var item = history.remove(at: index)
        item.createdAt = Date()
        history.insert(item, at: 0)
        history = sortHistory(history)
        clampPanelVisibleStartIndex()
    }

    private func trimHistoryByCountIfNeeded(_ items: [ClipboardItem]) -> [ClipboardItem] {
        guard items.count > settings.maxHistoryCount else { return items }

        var retained = items
        while retained.count > settings.maxHistoryCount {
            guard let removableIndex = retained.lastIndex(where: { !$0.isFavorite }) else { break }
            retained.remove(at: removableIndex)
        }

        return retained
    }

    private func trimExpiredHistoryIfNeeded(_ items: [ClipboardItem]) -> [ClipboardItem] {
        guard let days = settings.historyRetentionDays else { return items }

        let safeDays = max(days, 1)
        let cutoff = Calendar.current.date(byAdding: .day, value: -safeDays, to: Date()) ?? .distantPast
        return items.filter { $0.isFavorite || $0.createdAt >= cutoff }
    }

    private func trimHistoryByDiskUsageIfNeeded(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let maxBytes = max(settings.maxHistoryDiskUsageMB, 1) * 1_048_576
        guard historyDiskUsage(of: items) > maxBytes else { return items }

        var retained = items
        var currentBytes = historyDiskUsage(of: retained)

        while currentBytes > maxBytes {
            guard let removableIndex = retained.lastIndex(where: { !$0.isFavorite }) else { break }
            retained.remove(at: removableIndex)
            currentBytes = historyDiskUsage(of: retained)
        }

        return retained
    }

    private func recalculateHistoryDiskUsage(for items: [ClipboardItem]? = nil) {
        let resolvedItems = items ?? history
        let updatedDiskUsage = historyDiskUsage(of: resolvedItems)
        guard historyDiskUsageBytes != updatedDiskUsage else { return }
        historyDiskUsageBytes = updatedDiskUsage
    }

    private func collapseDuplicateHistory(_ items: [ClipboardItem]) -> [ClipboardItem] {
        var firstIndexByIdentity: [String: Int] = [:]
        var collapsed: [ClipboardItem] = []

        for item in items {
            guard let key = item.duplicateIdentityKey else {
                collapsed.append(item)
                continue
            }

            if let existingIndex = firstIndexByIdentity[key] {
                if item.isFavorite {
                    collapsed[existingIndex].isFavorite = true
                    if collapsed[existingIndex].favoriteSortOrder == nil {
                        collapsed[existingIndex].favoriteSortOrder = item.favoriteSortOrder
                    }
                    collapsed[existingIndex].favoriteGroupIDs = sanitizedFavoriteGroupIDs(
                        collapsed[existingIndex].favoriteGroupIDs + item.favoriteGroupIDs
                    )
                }
            } else {
                firstIndexByIdentity[key] = collapsed.count
                collapsed.append(item)
            }
        }

        return collapsed
    }

    private func historyDiskUsage(of items: [ClipboardItem]) -> Int {
        items.reduce(0) { partial, item in
            partial + item.estimatedStorageBytes
        }
    }

    private func sortHistory(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.sorted { lhs, rhs in
            lhs.createdAt > rhs.createdAt
        }
    }

    private func sortFavoriteSnippets(_ snippets: [FavoriteSnippet]) -> [FavoriteSnippet] {
        snippets.sorted { lhs, rhs in
            switch (lhs.sortOrder, rhs.sortOrder) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func sortFavoriteGroups(_ groups: [FavoriteGroup]) -> [FavoriteGroup] {
        groups.sorted { lhs, rhs in
            switch (lhs.sortOrder, rhs.sortOrder) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    private func favoriteGroupNextSortOrder(
        in groups: [FavoriteGroup],
        excluding groupID: FavoriteGroup.ID
    ) -> Int {
        let currentBottomOrder = groups
            .filter { $0.id != groupID }
            .compactMap(\.sortOrder)
            .max() ?? -1
        return currentBottomOrder + 1
    }

    private func normalizeFavoriteGroupSortOrders() {
        for (order, groupID) in favoriteGroups.map(\.id).enumerated() {
            guard let index = favoriteGroups.firstIndex(where: { $0.id == groupID }) else { continue }
            favoriteGroups[index].sortOrder = order
        }
    }

    private func orderedFavoritePanelEntries(in groupID: FavoriteGroup.ID? = nil) -> [FavoritePanelEntry] {
        let entries = favoriteSnippets
            .filter { $0.belongs(to: groupID) }
            .map(FavoritePanelEntry.snippet) +
            history
            .filter {
                $0.isFavorite &&
                $0.kind != .text &&
                $0.kind != .passthroughText &&
                (groupID == nil || $0.favoriteGroupIDs.contains(groupID!))
            }
            .map(FavoritePanelEntry.historyItem)

        let orderMap = favoriteEntryOrderMap(for: groupID)
        return entries.sorted { lhs, rhs in
            switch (orderMap[lhs.orderKey], orderMap[rhs.orderKey]) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return compareStoredGlobalFavoriteOrder(lhs, rhs)
            }
        }
    }

    private func orderedFavoriteItems(
        in items: [ClipboardItem],
        groupID: FavoriteGroup.ID? = nil
    ) -> [ClipboardItem] {
        _ = items
        return orderedFavoritePanelEntries(in: groupID).compactMap(\.historyItem)
    }

    private func orderedFavoriteSnippets(in groupID: FavoriteGroup.ID? = nil) -> [FavoriteSnippet] {
        orderedFavoritePanelEntries(in: groupID).compactMap(\.snippet)
    }

    private func favoritePanelTopSortOrder(excluding excludedKey: FavoriteEntryOrderKey) -> Int {
        let snippetOrders = favoriteSnippets.compactMap { snippet in
            FavoriteEntryOrderKey.snippet(snippet.id) == excludedKey ? nil : snippet.sortOrder
        }
        let historyOrders = history.compactMap { item -> Int? in
            guard item.isFavorite,
                  item.kind != .text,
                  item.kind != .passthroughText,
                  FavoriteEntryOrderKey.historyItem(item.id) != excludedKey else {
                return nil
            }
            return item.favoriteSortOrder
        }
        let currentTopOrder = (snippetOrders + historyOrders).min() ?? 0
        return currentTopOrder - 1
    }

    private func normalizeGlobalFavoritePanelSortOrders() {
        applyGlobalFavoriteEntryOrdering(currentGlobalFavoriteEntryOrder())
    }

    private func currentGlobalFavoriteEntryOrder() -> [FavoriteEntryOrderKey] {
        let entries = favoriteSnippets.map(FavoritePanelEntry.snippet) +
            history
            .filter { $0.isFavorite && $0.kind != .text && $0.kind != .passthroughText }
            .map(FavoritePanelEntry.historyItem)

        return entries
            .sorted(by: compareStoredGlobalFavoriteOrder)
            .map(\.orderKey)
    }

    private func applyGlobalFavoriteEntryOrdering(_ orderedEntries: [FavoriteEntryOrderKey]) {
        let orderMap = Dictionary(uniqueKeysWithValues: orderedEntries.enumerated().map { ($1, $0) })

        for index in favoriteSnippets.indices {
            favoriteSnippets[index].sortOrder = orderMap[.snippet(favoriteSnippets[index].id)]
        }

        for index in history.indices {
            let key = FavoriteEntryOrderKey.historyItem(history[index].id)
            if history[index].isFavorite && history[index].kind != .text && history[index].kind != .passthroughText {
                history[index].favoriteSortOrder = orderMap[key]
            } else {
                history[index].favoriteSortOrder = nil
            }
        }

        favoriteSnippets = sortFavoriteSnippets(favoriteSnippets)
        history = sortHistory(history)
    }

    private func compareStoredGlobalFavoriteOrder(_ lhs: FavoritePanelEntry, _ rhs: FavoritePanelEntry) -> Bool {
        switch (globalStoredOrderValue(for: lhs), globalStoredOrderValue(for: rhs)) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            switch (lhs, rhs) {
            case (.snippet(let left), .snippet(let right)):
                if left.updatedAt != right.updatedAt {
                    return left.updatedAt > right.updatedAt
                }
                return left.createdAt > right.createdAt
            case (.historyItem(let left), .historyItem(let right)):
                return left.createdAt > right.createdAt
            case (.snippet, .historyItem):
                return true
            case (.historyItem, .snippet):
                return false
            }
        }
    }

    private func globalStoredOrderValue(for entry: FavoritePanelEntry) -> Int? {
        switch entry {
        case .snippet(let snippet):
            return snippet.sortOrder
        case .historyItem(let item):
            return item.favoriteSortOrder
        }
    }

    private func favoriteEntryOrderMap(for groupID: FavoriteGroup.ID?) -> [FavoriteEntryOrderKey: Int] {
        let orderKeys: [FavoriteEntryOrderKey]
        if let groupID, let group = favoriteGroup(withID: groupID) {
            orderKeys = groupMemberOrderKeys(for: group)
        } else {
            orderKeys = currentGlobalFavoriteEntryOrder()
        }
        return Dictionary(uniqueKeysWithValues: orderKeys.enumerated().map { ($1, $0) })
    }

    private func groupMemberOrderKeys(for group: FavoriteGroup) -> [FavoriteEntryOrderKey] {
        group.memberOrder.compactMap(FavoriteEntryOrderKey.init(rawValue:))
    }

    private func moveFavoriteItemToTopInGroup(_ itemID: ClipboardItem.ID, groupID: FavoriteGroup.ID) {
        guard let index = favoriteGroups.firstIndex(where: { $0.id == groupID }) else { return }
        guard history.contains(where: { $0.id == itemID && $0.isFavorite && $0.favoriteGroupIDs.contains(groupID) }) else { return }
        favoriteGroups[index].prependHistoryItemID(itemID)
        favoriteGroups[index].updatedAt = Date()
        normalizeFavoriteGroupMemberOrders()
    }

    private func moveFavoriteSnippetToTopInGroup(_ snippetID: FavoriteSnippet.ID, groupID: FavoriteGroup.ID) {
        guard let index = favoriteGroups.firstIndex(where: { $0.id == groupID }) else { return }
        guard favoriteSnippets.contains(where: { $0.id == snippetID && $0.groupIDs.contains(groupID) }) else { return }
        favoriteGroups[index].prependSnippetID(snippetID)
        favoriteGroups[index].updatedAt = Date()
        normalizeFavoriteGroupMemberOrders()
    }

    private func normalizeFavoriteGroupMemberOrders() {
        let globallyOrderedEntryKeys = currentGlobalFavoriteEntryOrder()

        for groupIndex in favoriteGroups.indices {
            let groupID = favoriteGroups[groupIndex].id
            let validEntryKeys = Set(
                favoriteSnippets
                    .filter { $0.groupIDs.contains(groupID) }
                    .map { FavoriteEntryOrderKey.snippet($0.id) } +
                    history
                    .filter { $0.isFavorite && $0.favoriteGroupIDs.contains(groupID) && $0.kind != .text && $0.kind != .passthroughText }
                    .map { FavoriteEntryOrderKey.historyItem($0.id) }
            )

            favoriteGroups[groupIndex].memberOrder = groupMemberOrderKeys(for: favoriteGroups[groupIndex])
                .filter { validEntryKeys.contains($0) }
                .map(\.rawValue)

            for entryKey in globallyOrderedEntryKeys where validEntryKeys.contains(entryKey) {
                let rawValue = entryKey.rawValue
                if !favoriteGroups[groupIndex].memberOrder.contains(rawValue) {
                    favoriteGroups[groupIndex].memberOrder.append(rawValue)
                }
            }
        }
    }

    private func clampPanelVisibleStartIndex() {
        let currentItemsCount: Int
        if activeTab == .favorites {
            currentItemsCount = filteredFavoriteHistoryItems(in: activeFavoriteGroupID, matching: searchQuery).count +
                filteredFavoriteSnippets(in: activeFavoriteGroupID, matching: searchQuery).count
        } else {
            currentItemsCount = filteredHistory.count
        }

        let maxStart = max(0, currentItemsCount - 1)
        panelVisibleStartIndex = min(max(0, panelVisibleStartIndex), maxStart)
        if let hiddenTop = panelHiddenTopIndex {
            if hiddenTop >= 0 && hiddenTop < currentItemsCount {
                panelHiddenTopIndex = hiddenTop
            } else {
                panelHiddenTopIndex = nil
            }
        }
    }

    private func removedItems(from original: [ClipboardItem], retained: [ClipboardItem]) -> [ClipboardItem] {
        let retainedIDs = Set(retained.map(\.id))
        return original.filter { !retainedIDs.contains($0.id) }
    }

    private func notifyRemovedItems(_ items: [ClipboardItem]) {
        let uniqueItems = deduplicated(items)
        guard !uniqueItems.isEmpty else { return }
        onItemsRemoved?(uniqueItems)
    }

    private func deduplicated(_ items: [ClipboardItem]) -> [ClipboardItem] {
        var seen = Set<ClipboardItem.ID>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private func uniqueFavoriteGroupName(
        for requestedName: String,
        excluding excludedGroupID: FavoriteGroup.ID? = nil
    ) -> String {
        let trimmedRequestedName = FavoriteGroup.clampedUserInputName(requestedName)
        let baseName = trimmedRequestedName.isEmpty ? FavoriteGroup.defaultGeneratedName : trimmedRequestedName

        let siblingNames = Set(
            favoriteGroups
                .filter { $0.id != excludedGroupID }
                .map(\.trimmedName)
        )

        guard siblingNames.contains(baseName) else { return baseName }

        var suffix = 2
        while siblingNames.contains(baseName + String(suffix)) {
            suffix += 1
        }
        return baseName + String(suffix)
    }

    private func sanitizedFavoriteGroupIDs(_ groupIDs: [FavoriteGroup.ID]) -> [FavoriteGroup.ID] {
        var seen = Set<FavoriteGroup.ID>()
        var result: [FavoriteGroup.ID] = []
        for groupID in groupIDs where seen.insert(groupID).inserted {
            result.append(groupID)
        }
        return result
    }

    private func sanitizeFavoriteGroupReferences() {
        let validGroupIDs = Set(favoriteGroups.map(\.id))

        for index in favoriteSnippets.indices {
            favoriteSnippets[index].groupIDs = favoriteSnippets[index].groupIDs.filter { validGroupIDs.contains($0) }
        }

        for index in history.indices {
            if history[index].isFavorite {
                history[index].favoriteGroupIDs = history[index].favoriteGroupIDs.filter { validGroupIDs.contains($0) }
            } else {
                history[index].favoriteGroupIDs = []
            }
        }

        if let activeFavoriteGroupID, !validGroupIDs.contains(activeFavoriteGroupID) {
            self.activeFavoriteGroupID = nil
        }
    }

    private func isMeaningful(_ item: ClipboardItem) -> Bool {
        switch item.kind {
        case .text:
            guard let payload = item.textPayload else { return false }
            guard payload.byteCount <= ClipboardItem.maximumStoredTextByteCount || payload.assetRelativePath != nil else {
                return false
            }
            let normalizedPreview = payload.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalizedPreview.isEmpty || payload.byteCount > 0
        case .passthroughText:
            let normalizedPreview = item.preview.trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalizedPreview.isEmpty || (item.passthroughTextByteCount ?? 0) > 0
        case .image:
            return item.imagePayload != nil
        case .file:
            return !item.fileURLs.isEmpty
        case .stack:
            return item.stackPayload != nil
        }
    }
}
