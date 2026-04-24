import AppKit
import Combine
import Foundation
import ImageIO
import SwiftUI

enum FilePresentationSupport {
    struct Metadata: Sendable {
        let panelKindLabel: String
        let menuBarKindLabel: String
        let displayName: String
        let sizeText: String?
        let folderItemCount: Int?
        let isFolder: Bool
    }

    private enum KindHeuristics {
        nonisolated static let diskImageExtensions: Set<String> = [
            "dmg"
        ]
        nonisolated static let archiveExtensions: Set<String> = [
            "7z", "bz2", "gz", "rar", "tar", "tgz", "xz", "zip"
        ]
        nonisolated static let spreadsheetExtensions: Set<String> = [
            "csv", "numbers", "ods", "tsv", "xls", "xlsx"
        ]
        nonisolated static let presentationExtensions: Set<String> = [
            "key", "odp", "ppt", "pptx"
        ]
        nonisolated static let documentExtensions: Set<String> = [
            "doc", "docx", "markdown", "md", "mdown", "mkd", "mkdn",
            "pages", "pdf", "rtf", "rtfd", "txt"
        ]

        nonisolated static let diskImageKeywords = [
            "disk image", "磁盘映像"
        ]
        nonisolated static let archiveKeywords = [
            "7-zip", "archive", "compressed", "rar", "tar", "zip", "压缩", "归档"
        ]
        nonisolated static let spreadsheetKeywords = [
            "spreadsheet", "excel", "numbers", "工作表", "电子表格"
        ]
        nonisolated static let presentationKeywords = [
            "presentation", "powerpoint", "keynote", "演示文稿", "幻灯片"
        ]
        nonisolated static let documentKeywords = [
            "document", "word", "text", "markdown", "pdf", "文稿", "文本"
        ]
    }

    nonisolated static func makeMetadata(
        for url: URL,
        fallbackDisplayName: String
    ) -> Metadata {
        let standardizedURL = url.standardizedFileURL
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .localizedTypeDescriptionKey,
            .fileSizeKey,
            .totalFileSizeKey
        ]
        let values = try? standardizedURL.resourceValues(forKeys: resourceKeys)
        let displayName = resolvedDisplayName(
            for: standardizedURL,
            fallbackDisplayName: fallbackDisplayName
        )
        let localizedTypeDescription = values?
            .localizedTypeDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isFolder = (values?.isDirectory == true) && (values?.isPackage != true)

        if isFolder {
            return Metadata(
                panelKindLabel: AppLocalization.localized("文件夹"),
                menuBarKindLabel: AppLocalization.localized("文件夹"),
                displayName: displayName,
                sizeText: nil,
                folderItemCount: folderItemCount(for: standardizedURL),
                isFolder: true
            )
        }

        let panelKindLabel = normalizedKindLabel(
            localizedTypeDescription: localizedTypeDescription,
            url: standardizedURL,
            fallbackToLocalizedDescription: true
        )
        let menuBarKindLabel = normalizedKindLabel(
            localizedTypeDescription: localizedTypeDescription,
            url: standardizedURL,
            fallbackToLocalizedDescription: false
        )
        let fileSize = values?.totalFileSize ?? values?.fileSize
        let sizeText = fileSize.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        }

        return Metadata(
            panelKindLabel: panelKindLabel,
            menuBarKindLabel: menuBarKindLabel,
            displayName: displayName,
            sizeText: sizeText,
            folderItemCount: nil,
            isFolder: false
        )
    }

    nonisolated static func normalizedKindLabel(
        localizedTypeDescription: String?,
        url: URL,
        fallbackToLocalizedDescription: Bool
    ) -> String {
        let fileExtension = url.pathExtension.lowercased()
        let normalizedDescription = localizedTypeDescription?.lowercased() ?? ""

        if KindHeuristics.diskImageExtensions.contains(fileExtension) ||
            KindHeuristics.diskImageKeywords.contains(where: normalizedDescription.contains) {
            return AppLocalization.localized("磁盘映像")
        }

        if KindHeuristics.archiveExtensions.contains(fileExtension) ||
            KindHeuristics.archiveKeywords.contains(where: normalizedDescription.contains) {
            return AppLocalization.localized("压缩包")
        }

        if KindHeuristics.spreadsheetExtensions.contains(fileExtension) ||
            KindHeuristics.spreadsheetKeywords.contains(where: normalizedDescription.contains) {
            return AppLocalization.localized("电子表格")
        }

        if KindHeuristics.presentationExtensions.contains(fileExtension) ||
            KindHeuristics.presentationKeywords.contains(where: normalizedDescription.contains) {
            return AppLocalization.localized("演示文稿")
        }

        if KindHeuristics.documentExtensions.contains(fileExtension) ||
            KindHeuristics.documentKeywords.contains(where: normalizedDescription.contains) {
            return AppLocalization.localized("文稿")
        }

        if fallbackToLocalizedDescription,
           let localizedTypeDescription,
           !localizedTypeDescription.isEmpty {
            return localizedTypeDescription
        }

        return AppLocalization.localized("文件")
    }

    nonisolated static func resolvedDisplayName(
        for url: URL,
        fallbackDisplayName: String
    ) -> String {
        let displayName = FileManager.default.displayName(atPath: url.path)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty {
            return displayName
        }

        let trimmedFallback = fallbackDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFallback.isEmpty {
            return trimmedFallback
        }

        return url.lastPathComponent
    }

    nonisolated static func folderItemCount(for url: URL) -> Int? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return contents.count
    }
}

@MainActor
final class AppServices: ObservableObject {
    private struct DataStorageDescriptor {
        let rootURL: URL
        let customDirectoryPath: String?
        let customDirectoryBookmark: Data?
        let scopedAccessURL: URL?

        var usesDefaultLocation: Bool {
            customDirectoryPath == nil
        }
    }

    private let compactPanelSize = NSSize(width: 440, height: 740)
    private let panelRowHeight: CGFloat = 86
    private let stackRowHeight: CGFloat = 82
    // Medium-length text should skip expensive size probing and open with a stable panel size.
    private let largeTextPreviewMeasurementThreshold = 2_400

    private enum RightDragInteractionTarget {
        case row(Int)
        case tab(PanelTab)
        case favoriteGroup(FavoriteGroup.ID?)
        case close
        case search
        case favoriteAdd
        case stack
        case pin
        case none
    }

    private enum PanelPreviewTarget {
        case historyItem(ClipboardItem)
        case favoriteSnippet(FavoriteSnippet)
    }

    enum StackProcessorApplyMode {
        case insertAbove
        case insertBelow
        case replace

        var title: String {
            switch self {
            case .insertAbove:
                return AppLocalization.localized("插入上方")
            case .insertBelow:
                return AppLocalization.localized("插入下方")
            case .replace:
                return AppLocalization.localized("替换堆栈内容")
            }
        }
    }

    struct FullPreviewContent {
        struct Item: Identifiable, Sendable {
            let id: String
            let url: URL?
            let displayName: String
            let textContent: String?
            let securityScopedBookmarkData: Data?
            let filePresentation: FilePresentationSupport.Metadata?
        }

        let itemID: ClipboardItem.ID
        let kind: ClipboardItem.ContentKind
        let items: [Item]
        var currentIndex: Int
    }

    struct FullPreviewUnavailableState {
        let itemID: ClipboardItem.ID
        let kind: ClipboardItem.ContentKind
        let message: String
    }

    enum FavoriteEditorConfirmationIntent: Hashable {
        case saveAndContinue
        case discardAndContinue
        case keepEditingCurrent
    }

    struct FavoriteEditorConfirmationButton: Identifiable, Hashable {
        enum Style: Hashable {
            case accent
            case secondary
            case destructive
        }

        let intent: FavoriteEditorConfirmationIntent
        let title: String
        let style: Style

        var id: FavoriteEditorConfirmationIntent { intent }
    }

    struct FavoriteEditorConfirmationState {
        let title: String
        let message: String
        let buttons: [FavoriteEditorConfirmationButton]
    }

    private struct PreparedFullPreviewPresentation {
        let content: FullPreviewContent
        let stopAccess: () -> Void
    }

    private enum FavoriteEditorTransitionContext {
        case closeEditor
        case closePanel
        case createNext
        case editNext
    }

    let appState = AppState()
    @Published private(set) var isPanelVisible = false
    @Published private(set) var preferredColorScheme: ColorScheme?
    @Published private(set) var activePreviewItemID: ClipboardItem.ID?
    @Published private(set) var isFullPreviewPresented = false
    @Published private(set) var fullPreviewContent: FullPreviewContent?
    @Published private(set) var fullPreviewUnavailableState: FullPreviewUnavailableState?
    @Published private(set) var favoriteEditorConfirmation: FavoriteEditorConfirmationState?
    @Published private(set) var isDataStorageMigrationInProgress = false
    @Published private(set) var dataStorageMigrationStatusText: String?
    var currentPanelPresentationMode: EdgePanelController.PresentationMode { panelController.currentMode }
    var currentPanelRequiresTabHoverUnlock: Bool {
        panelRequiresTabHoverUnlock(for: currentPanelPresentationMode)
    }

    private let clipboardMonitor = ClipboardMonitor()
    private let focusTracker = FocusTracker()
    private let pasteCoordinator = PasteCoordinator()
    private let hotEdgeService = HotEdgeService()
    private let rightMouseDragGestureService = RightMouseDragGestureService()
    private let panelController = EdgePanelController()
    private let menuBarStatusItemController = MenuBarStatusItemController()
    private let mouseGestureTrailOverlayController = MouseGestureTrailOverlayController()
    private let edgeActivationPreviewController = RightEdgeActivationPreviewController()
    private let fullPreviewPanelController = ClipboardFullPreviewPanelController()
    private let stackService = ClipboardStackService()
    private let fileManager = FileManager.default
    private var persistence = ClipboardPersistence(rootDirectoryURL: AppServices.defaultDataStorageRootURL())
    private var favoriteSnippetPersistence = FavoriteSnippetPersistence(rootDirectoryURL: AppServices.defaultDataStorageRootURL())
    private var favoriteGroupPersistence = FavoriteGroupPersistence(rootDirectoryURL: AppServices.defaultDataStorageRootURL())
    private let settingsPersistence = AppSettingsPersistence()
    private let launchAtLoginService = LaunchAtLoginService()
    private let globalHotkeyService = GlobalHotkeyService()
    private let panelPreviewHotkeyBridgeService = PanelPreviewHotkeyBridgeService()
    private let readbackServiceClient = ClipboardReadbackServiceClient()
    private let ownBundleID = Bundle.main.bundleIdentifier
    private var activeDataStorageRootURL = AppServices.defaultDataStorageRootURL()
    private var activeDataStorageSecurityScopeURL: URL?

    private var cancellables = Set<AnyCancellable>()
    private var localPanelKeyMonitor: Any?
    private var localOutsideClickMonitor: Any?
    private var globalOutsideClickMonitor: Any?
    private var appIconCache: [String: NSImage] = [:]
    private var appDisplayNameCache: [String: String] = [:]
    private var favoriteEditorConfirmationHandler: ((FavoriteEditorConfirmationIntent) -> Void)?
    private let imagePreviewCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 180
        cache.totalCostLimit = 48 * 1_024 * 1_024
        return cache
    }()
    private var fileAvailabilityCache: [ClipboardItem.ID: Bool] = [:]
    private var filePresentationCache: [ClipboardItem.ID: FilePresentationSupport.Metadata] = [:]
    private var transientNoticeDismissWorkItem: DispatchWorkItem?
    private var interactionSettingsApplyWorkItem: DispatchWorkItem?
    private var stackProcessorSyncWorkItem: DispatchWorkItem?
    private var pinnedPanelFocusReclaimWorkItem: DispatchWorkItem?
    private var isPinnedPanelIdleDimmed = false
    private var fullPreviewStopAccess: (() -> Void)?
    private var openSettingsWindowAction: (() -> Void)?
    private var started = false
    private var isSettingsWindowVisible = false
    private var rightDragLatestPointer: CGPoint?
    private var rightDragFrozenViewportY: CGFloat?
    private var previewDismissSafetyFrames: [NSRect] = []

    var fullPreviewCurrentItem: FullPreviewContent.Item? {
        guard let fullPreviewContent,
              fullPreviewContent.items.indices.contains(fullPreviewContent.currentIndex) else {
            return nil
        }

        return fullPreviewContent.items[fullPreviewContent.currentIndex]
    }

    var dataStorageLocationDisplayPath: String {
        activeDataStorageRootURL.path
    }

    var dataStorageLocationCompactDisplayPath: String {
        (activeDataStorageRootURL.path as NSString).abbreviatingWithTildeInPath
    }

    var isUsingDefaultDataStorageLocation: Bool {
        activeDataStorageRootURL.standardizedFileURL == Self.defaultDataStorageRootURL(fileManager: fileManager).standardizedFileURL
    }

    private func dataStorageDescriptor(from settings: AppSettings) -> DataStorageDescriptor {
        let defaultRootURL = Self.defaultDataStorageRootURL(fileManager: fileManager).standardizedFileURL
        let trimmedCustomPath = settings.dataStorageCustomDirectoryPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackCustomURL = trimmedCustomPath.flatMap { path -> URL? in
            guard !path.isEmpty else { return nil }
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }

        var resolvedCustomURL: URL?
        var scopedAccessURL: URL?

        if let bookmarkData = settings.dataStorageCustomDirectoryBookmark {
            var isStale = false
            if let bookmarkedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                resolvedCustomURL = bookmarkedURL.standardizedFileURL
                scopedAccessURL = bookmarkedURL.standardizedFileURL
            }
        }

        let rootURL = (resolvedCustomURL ?? fallbackCustomURL ?? defaultRootURL).standardizedFileURL
        let customPath = (resolvedCustomURL ?? fallbackCustomURL)?.path
        let bookmarkData: Data?
        if let customURL = resolvedCustomURL ?? fallbackCustomURL,
           customURL.standardizedFileURL != defaultRootURL {
            bookmarkData = settings.dataStorageCustomDirectoryBookmark
        } else {
            resolvedCustomURL = nil
            scopedAccessURL = nil
            bookmarkData = nil
        }

        return DataStorageDescriptor(
            rootURL: rootURL,
            customDirectoryPath: customPath,
            customDirectoryBookmark: bookmarkData,
            scopedAccessURL: scopedAccessURL
        )
    }

    private func activateDataStorageScopeIfNeeded(_ descriptor: DataStorageDescriptor) {
        if let currentURL = activeDataStorageSecurityScopeURL {
            currentURL.stopAccessingSecurityScopedResource()
            activeDataStorageSecurityScopeURL = nil
        }

        guard let scopedURL = descriptor.scopedAccessURL,
              descriptor.rootURL.standardizedFileURL != Self.defaultDataStorageRootURL(fileManager: fileManager).standardizedFileURL
        else {
            return
        }

        if scopedURL.startAccessingSecurityScopedResource() {
            activeDataStorageSecurityScopeURL = scopedURL
        }
    }

    private func reconfigurePersistenceStores(using descriptor: DataStorageDescriptor) {
        persistence.cancelPendingSave()
        activateDataStorageScopeIfNeeded(descriptor)
        activeDataStorageRootURL = descriptor.rootURL
        persistence = ClipboardPersistence(rootDirectoryURL: descriptor.rootURL, fileManager: fileManager)
        favoriteSnippetPersistence = FavoriteSnippetPersistence(rootDirectoryURL: descriptor.rootURL, fileManager: fileManager)
        favoriteGroupPersistence = FavoriteGroupPersistence(rootDirectoryURL: descriptor.rootURL, fileManager: fileManager)
    }

    private func bookmarkData(for directoryURL: URL) -> Data? {
        try? directoryURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    nonisolated private static func defaultDataStorageRootURL(fileManager: FileManager = .default) -> URL {
        let appSupportRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupportRoot.appendingPathComponent("EdgeClip", isDirectory: true)
    }

    var currentTextPreviewPayload: ClipboardItem.TextPayload? {
        guard let itemID = activePreviewItemID,
              let item = appState.item(withID: itemID),
              item.kind == .text else {
            return nil
        }

        return item.textPayload
    }

    var fullPreviewSupportsItemNavigation: Bool {
        guard let fullPreviewContent else { return false }
        guard fullPreviewContent.kind != .stack else { return false }
        guard !fullPreviewUsesFileOverview else { return false }
        return fullPreviewContent.items.count > 1
    }

    var canShowPreviousFullPreviewItem: Bool {
        guard fullPreviewSupportsItemNavigation else { return false }
        guard let fullPreviewContent else { return false }
        return fullPreviewContent.currentIndex > 0
    }

    var canShowNextFullPreviewItem: Bool {
        guard fullPreviewSupportsItemNavigation else { return false }
        guard let fullPreviewContent else { return false }
        return fullPreviewContent.currentIndex < fullPreviewContent.items.count - 1
    }

    var fullPreviewUsesFileOverview: Bool {
        guard let fullPreviewContent, fullPreviewContent.kind == .file else { return false }
        if fullPreviewContent.items.count > 1 {
            return true
        }
        return fullPreviewCurrentItem?.filePresentation?.isFolder == true
    }

    var shouldTrackContinuousPreviewHover: Bool {
        appState.settings.filePreviewEnabled &&
        appState.settings.continuousFilePreviewEnabled &&
        isFullPreviewPresented &&
        (fullPreviewContent != nil || fullPreviewUnavailableState != nil) &&
        appState.panelMode == .history
    }

    var canOpenCurrentPreviewInFinder: Bool {
        guard let fullPreviewContent, fullPreviewContent.kind == .file else { return false }
        if fullPreviewUsesFileOverview {
            return fullPreviewContent.items.contains { $0.url != nil }
        }
        return fullPreviewCurrentItem?.url != nil
    }

    var stackEntryCount: Int {
        appState.activeStackSession?.entries.count ?? 0
    }

    var activeStackEntries: [ClipboardItem.StackEntry] {
        appState.activeStackSession?.entries ?? []
    }

    var stackProcessorPreviewCount: Int {
        parsedStackProcessorSegments().count
    }

    var currentStackOrderMode: StackOrderMode {
        appState.activeStackSession?.orderMode ?? .sequential
    }

    var canApplyStackProcessorDraft: Bool {
        !parsedStackProcessorSegments().isEmpty
    }

    var canImportPreviewTextToStack: Bool {
        guard let content = fullPreviewContent else { return false }
        guard !appState.isStackProcessorPresented else { return false }
        switch content.kind {
        case .text:
            return currentTextPreviewPayload?.hasTruncatedPreview == false &&
                fullPreviewCurrentItem?.textContent?.isEmpty == false
        case .passthroughText:
            return false
        case .image, .file, .stack:
            return false
        }
    }

    func start() {
        guard !started else { return }
        started = true

        evictOlderRunningInstancesIfNeeded()

        var restoredSettings = settingsPersistence.load(defaultValue: appState.settings)
        restoredSettings.launchAtLoginEnabled = launchAtLoginService.isEnabled()
        if !restoredSettings.menuBarStatusItemVisible {
            restoredSettings.menuBarActivationEnabled = false
        }
        appState.settings = restoredSettings
        appState.synchronizeLocalization()
        reconfigurePersistenceStores(using: dataStorageDescriptor(from: restoredSettings))
        synchronizeAccessibilityPermissionState()
        menuBarStatusItemController.onLeftClick = { [weak self] in
            self?.toggleMenuBarPanel()
        }
        menuBarStatusItemController.onMenuWillOpen = { [weak self] in
            guard let self, self.isPanelVisible else { return }
            self.hidePanel()
        }
        menuBarStatusItemController.onOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        menuBarStatusItemController.onQuit = {
            NSApp.terminate(nil)
        }
        appState.onItemsRemoved = { [weak self] items in
            self?.persistence.removeAssociatedAssets(for: items)
            self?.removeImageCache(for: items)
            self?.removeFileAvailabilityCache(for: items)
            self?.removeFilePresentationCache(for: items)
            self?.handleRemovedItemsAffectingPreview(items)
        }
        appState.restoreFavoriteGroups(favoriteGroupPersistence.load())
        appState.restoreHistory(persistence.load())
        appState.restoreFavoriteSnippets(favoriteSnippetPersistence.load())
        migrateLegacyTextFavoritesIfNeeded()
        appState.dormantStackItemID = currentStackHistoryItem()?.id
        persistence.cleanupOrphanedAssets(using: appState.history)

        observePersistence()
        persistence.save(appState.history)
        Task { [weak self] in
            await self?.protectExistingFavoriteFilesIfNeeded()
        }

        isPanelVisible = panelController.isVisible
        panelController.onVisibilityChanged = { [weak self] isVisible in
            self?.isPanelVisible = isVisible
            self?.handlePanelVisibilityChanged(isVisible)
        }
        panelController.onFrameChanged = { [weak self] in
            self?.handlePanelFrameChanged()
        }
        panelController.isPinnedProvider = { [weak self] in
            self?.appState.isPanelPinned ?? false
        }
        panelController.additionalActiveRegionProvider = { [weak self] point in
            self?.isPointInPanelExtendedInteractionRegion(point) ?? false
        }
        panelController.updateEdgeActivationPlacement(
            side: appState.settings.edgeActivationSide,
            mode: appState.settings.edgeActivationPlacementMode,
            customVerticalPosition: appState.settings.edgeActivationCustomVerticalPosition
        )
        panelController.updateHotkeyPlacement(
            mode: appState.settings.hotkeyPanelPlacementMode,
            lastFrameOrigin: appState.settings.hotkeyPanelLastFrameOrigin?.cgPoint
        )
        panelController.updateEdgeAutoCollapseDistance(appState.settings.edgePanelAutoCollapseDistance)
        panelController.updatePinnedIdleTransparencyPercent(appState.settings.pinnedPanelIdleTransparencyPercent)
        fullPreviewPanelController.onClose = { [weak self] in
            self?.handleAuxiliaryPanelDidClose()
        }

        globalHotkeyService.onAction = { [weak self] action in
            switch action {
            case .clipboardPanel:
                self?.showPanel(mode: .hotkey)
            case .favoritesTab:
                self?.showPanel(mode: .hotkey, preferredTab: .favorites)
            }
        }
        panelPreviewHotkeyBridgeService.shouldBypassEvents = { [weak self] in
            self?.shouldBypassPinnedPanelPreviewHotkeys() ?? true
        }
        panelPreviewHotkeyBridgeService.onAction = { [weak self] action in
            self?.handlePinnedPanelPreviewHotkey(action) ?? false
        }

        focusTracker.start()

        clipboardMonitor.onCapture = { [weak self] capture in
            self?.handleClipboardCaptured(capture)
        }
        clipboardMonitor.capturePolicyProvider = { [weak self] bundleID in
            self?.capturePolicy(forSourceBundleID: bundleID) ?? .defaultTextPreferred
        }
        clipboardMonitor.imageCaptureEnabledProvider = { [weak self] _ in
            self?.appState.settings.recordImageClipboardEnabled ?? true
        }
        clipboardMonitor.onOversizedTextCaptureSkipped = { [weak self] byteCount, _, _ in
            guard let self else { return }
            self.showTransientNotice(self.oversizedTextCaptureMessage(byteCount: byteCount))
        }
        clipboardMonitor.onPasteboardChanged = { [weak self] changeCount in
            self?.handleClipboardChangeCountUpdated(changeCount)
        }
        clipboardMonitor.onPendingTextCaptureAbandoned = { [weak self] requestID in
            self?.handlePendingTextCaptureAbandoned(requestID)
        }
        clipboardMonitor.onPendingTextCaptureTimedOut = { [weak self] requestID, changeCount, bundleID, sourceName in
            self?.handlePendingTextCaptureTimedOut(
                requestID,
                changeCount: changeCount,
                sourceAppBundleID: bundleID,
                sourceAppName: sourceName
            )
        }
        clipboardMonitor.start()

        stackService.shouldBypassHotkeys = { [weak self] in
            self?.shouldBypassStackHotkeys() ?? true
        }
        stackService.onCopyCommand = { [weak self] baselineChangeCount in
            self?.captureCopiedTextIntoStack(baselineChangeCount: baselineChangeCount)
        }
        stackService.onPasteCommand = { [weak self] in
            self?.prepareNextStackPaste() ?? false
        }

        hotEdgeService.onTriggered = { [weak self] in
            self?.showPanel(mode: .edgeTriggered)
        }

        rightMouseDragGestureService.shouldBeginGesture = { [weak self] in
            guard let self else { return false }
            return self.appState.settings.rightMouseDragActivationEnabled && !self.isPanelVisible
        }
        rightMouseDragGestureService.onGestureStarted = { [weak self] point in
            self?.beginRightDragSelection(at: point)
        }
        rightMouseDragGestureService.onGestureMoved = { [weak self] point in
            self?.updateRightDragSelection(at: point)
        }
        rightMouseDragGestureService.onGestureEnded = { [weak self] in
            self?.finishRightDragSelection()
        }
        rightMouseDragGestureService.onScroll = { [weak self] deltaY, point in
            self?.handleRightDragScroll(deltaY: deltaY, pointer: point)
        }
        rightMouseDragGestureService.onAuxiliaryGestureTriggered = { [weak self] gestureID in
            self?.handleRightMouseAuxiliaryGesture(id: gestureID)
        }
        rightMouseDragGestureService.onGesturePreviewChanged = { [weak self] previewState in
            guard let self else { return }
            self.mouseGestureTrailOverlayController.update(
                previewState: previewState,
                appearanceMode: self.appState.settings.appearanceMode
            )
        }

        applyEdgeServiceSettings()
        applyGlobalHotkeySetting()
        applyRightMouseDragGestureSetting()
        scheduleInteractionSettingsApply()
        panelController.updateAppearance(mode: appState.settings.appearanceMode)
        fullPreviewPanelController.updateAppearance(mode: appState.settings.appearanceMode)
        updatePreferredColorSchemeIfNeeded(colorScheme(for: appState.settings.appearanceMode))
        applyApplicationVisibilityState()
        applyMenuBarStatusItemState()
    }

    private func evictOlderRunningInstancesIfNeeded() {
        guard let ownBundleID else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let olderInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: ownBundleID)
            .filter { $0.processIdentifier != currentPID && $0.processIdentifier < currentPID }

        guard !olderInstances.isEmpty else { return }

        for app in olderInstances {
            app.terminate()
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            for app in olderInstances where !app.isTerminated {
                _ = app.forceTerminate()
            }
        }
    }

    func stop() {
        clipboardMonitor.stop()
        focusTracker.stop()
        hotEdgeService.stop()
        rightMouseDragGestureService.stop()
        panelController.hide()
        mouseGestureTrailOverlayController.hide()
        clearFullPreviewPresentationState()
        fullPreviewPanelController.hide()

        try? globalHotkeyService.updateRegistration(
            enabled: false,
            triggerMode: .doubleModifier,
            panelModifier: .command,
            favoritesModifier: nil,
            interval: 0.36,
            panelShortcut: .defaultPanelTrigger,
            favoritesShortcut: KeyboardShortcut()
        )

        stopPanelDigitKeyMonitoring()
        stopOutsideClickMonitoring()
        menuBarStatusItemController.uninstall()
        cancellables.removeAll()
        appIconCache.removeAll()
        appDisplayNameCache.removeAll()
        imagePreviewCache.removeAllObjects()
        filePresentationCache.removeAll()
        interactionSettingsApplyWorkItem?.cancel()
        interactionSettingsApplyWorkItem = nil
        transientNoticeDismissWorkItem?.cancel()
        transientNoticeDismissWorkItem = nil
        stackService.stopBridge()
        stackProcessorSyncWorkItem?.cancel()
        stackProcessorSyncWorkItem = nil
        cancelPinnedPanelFocusReclaim()
        started = false
    }

    func paste(item: ClipboardItem) {
        cancelPinnedPanelFocusReclaim()

        if item.kind == .stack {
            openStackSession(from: item)
            return
        }

        appState.lastErrorMessage = nil
        appState.promoteItemAfterPasteIfNeeded(item.id)
        let transferItem = transferReadyItem(from: item)

        if item.kind == .passthroughText {
            Task {
                switch await preparePassthroughTextForTransfer(item) {
                case .success:
                    let result = await pasteCoordinator.pasteCurrentClipboard(
                        settings: appState.settings,
                        focusTracker: focusTracker,
                        didCollapsePanel: { [weak self] in
                            self?.collapsePanelAfterPasteIfNeeded()
                        }
                    )

                    switch result {
                    case .autoPasted:
                        appState.lastErrorMessage = nil
                        schedulePinnedPanelFocusReclaimAfterAutoPasteIfNeeded()
                    case .copiedOnly:
                        appState.lastErrorMessage = nil
                        showCopiedOnlyPasteNotice()
                    case let .failed(message):
                        appState.lastErrorMessage = nil
                        showTransientNotice(message)
                    }
                case let .failed(message):
                    appState.lastErrorMessage = nil
                    showTransientNotice(message)
                }

                synchronizeAccessibilityPermissionState()
            }
            return
        }

        Task {
            let result = await pasteCoordinator.paste(
                item: transferItem,
                settings: appState.settings,
                focusTracker: focusTracker,
                textProvider: { [weak self] item in
                    self?.resolvedTextContent(for: item)
                },
                imageAssetURLProvider: { [weak self] relativePath in
                    guard let self else { return nil }
                    return self.persistence.imageAssetURL(for: relativePath)
                },
                imageProvider: { [weak self] item in
                    self?.previewImage(for: item)
                },
                didWriteToPasteboard: { [weak self] in
                    self?.clipboardMonitor.ignoreCurrentContents()
                },
                didCollapsePanel: { [weak self] in
                    self?.collapsePanelAfterPasteIfNeeded()
                }
            )

            switch result {
            case .autoPasted:
                appState.lastErrorMessage = nil
                schedulePinnedPanelFocusReclaimAfterAutoPasteIfNeeded()
            case .copiedOnly:
                appState.lastErrorMessage = nil
                showCopiedOnlyPasteNotice()
            case let .failed(message):
                appState.lastErrorMessage = nil
                showTransientNotice(message)
            }

            synchronizeAccessibilityPermissionState()
        }
    }

    func copy(item: ClipboardItem) {
        cancelPinnedPanelFocusReclaim()

        if item.kind == .stack {
            showTransientNotice(AppLocalization.localized("请先打开堆栈，再逐条粘贴或管理其中的内容。"), tone: .info)
            return
        }

        appState.lastErrorMessage = nil
        let transferItem = transferReadyItem(from: item)
        if item.kind == .passthroughText {
            Task {
                switch await preparePassthroughTextForTransfer(item) {
                case .success:
                    appState.lastErrorMessage = nil
                    showTransientNotice(AppLocalization.localized("已复制到系统剪贴板。"), tone: .info)
                case let .failed(message):
                    appState.lastErrorMessage = nil
                    showTransientNotice(message)
                }
            }
            return
        }

        switch pasteCoordinator.copyToPasteboard(
            item: transferItem,
            textProvider: { [weak self] item in
                self?.resolvedTextContent(for: item)
            },
            imageAssetURLProvider: { [weak self] relativePath in
                guard let self else { return nil }
                return self.persistence.imageAssetURL(for: relativePath)
            },
            imageProvider: { [weak self] item in
                self?.previewImage(for: item)
            }
        ) {
        case .success:
            clipboardMonitor.ignoreCurrentContents()
            appState.lastErrorMessage = nil
            showTransientNotice(AppLocalization.localized("已复制到系统剪贴板。"), tone: .info)
        case let .failed(message):
            appState.lastErrorMessage = nil
            showTransientNotice(message)
        }
    }

    func copyFavoriteSnippet(snippetID: FavoriteSnippet.ID) {
        guard let snippet = appState.favoriteSnippet(withID: snippetID) else { return }
        cancelPinnedPanelFocusReclaim()
        appState.lastErrorMessage = nil

        switch pasteCoordinator.writeTextToPasteboard(snippet.text) {
        case .success:
            clipboardMonitor.ignoreCurrentContents()
            showTransientNotice(AppLocalization.localized("已复制到系统剪贴板。"), tone: .info)
        case .failed(let message):
            showTransientNotice(message)
        }
    }

    func toggleStackMode() {
        if appState.panelMode == .stack {
            leaveStackModeToHistory()
        } else {
            openStackSession(from: currentStackHistoryItem())
        }
    }

    func openStackSession(from item: ClipboardItem? = nil) {
        guard isPanelVisible else { return }
        dismissFavoriteEditorIfNeeded(restorePinState: true, clearDraft: false)

        if appState.panelMode != .stack {
            appState.preStackPinState = appState.isPanelPinned
        }

        if isFullPreviewPresented {
            clearFullPreviewPresentationState()
        }

        let sourceItem = item?.kind == .stack ? item : currentStackHistoryItem()
        let payload = sourceItem?.stackPayload
        let currentSession = appState.activeStackSession
        appState.activeStackSession = ActiveStackSession(
            historyItemID: sourceItem?.id ?? currentSession?.historyItemID,
            entries: payload?.entries ?? currentSession?.entries ?? [],
            orderMode: payload?.orderMode ?? currentSession?.orderMode ?? .sequential,
            updatedAt: payload?.updatedAt ?? currentSession?.updatedAt ?? Date()
        )
        appState.panelMode = .stack
        appState.isPanelPinned = true
        appState.hoveredRowID = nil
        appState.rightDragHighlightedRowID = nil
        appState.searchQuery = ""
        updateStackBridgeState()
        updateAuxiliaryPanelPresentation()
    }

    func leaveStackModeToHistory() {
        persistActiveStackSession()
        appState.panelMode = .history
        appState.activeStackSession = nil
        appState.isStackProcessorPresented = false
        appState.stackProcessorDraft = ""
        if let preStackPinState = appState.preStackPinState {
            appState.isPanelPinned = preStackPinState
        }
        appState.preStackPinState = nil
        stackProcessorSyncWorkItem?.cancel()
        stackProcessorSyncWorkItem = nil
        updateStackBridgeState()
        updateAuxiliaryPanelPresentation()
    }

    func toggleStackProcessorPanel() {
        guard appState.panelMode == .stack else { return }
        if appState.isStackProcessorPresented {
            appState.isStackProcessorPresented = false
            updateAuxiliaryPanelPresentation()
            return
        }

        appState.isStackProcessorPresented = true
        updateAuxiliaryPanelPresentation()
    }

    func closeAuxiliaryPanel() {
        if appState.isStackProcessorPresented {
            appState.isStackProcessorPresented = false
            updateAuxiliaryPanelPresentation()
            return
        }

        if appState.isFavoriteEditorPresented {
            requestFavoriteEditorTransition(context: .closeEditor) {
                self.dismissFavoriteEditorIfNeeded(restorePinState: true, clearDraft: true)
                self.updateAuxiliaryPanelPresentation()
            }
            return
        }

        if isFullPreviewPresented || fullPreviewContent != nil || fullPreviewUnavailableState != nil {
            hideFullPreview()
            return
        }

        fullPreviewPanelController.hide()
    }

    func updateStackOrderMode(_ orderMode: StackOrderMode) {
        appState.updateActiveStackSession { session in
            guard session.orderMode != orderMode else { return }
            session.orderMode = orderMode
            session.entries.reverse()
        }
        persistActiveStackSession()
    }

    func moveStackEntries(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        appState.updateActiveStackSession { session in
            session.entries.move(fromOffsets: offsets, toOffset: destination)
        }
        persistActiveStackSession()
    }

    func moveFavoriteItems(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let activeGroupID = appState.activeFavoriteGroupID
        var favorites = appState.filteredFavoriteHistoryItems(in: activeGroupID, matching: nil)
        guard !favorites.isEmpty else { return }
        favorites.move(fromOffsets: offsets, toOffset: destination)
        appState.applyFavoriteOrdering(favorites.map(\.id), in: activeGroupID)
    }

    func moveFavoriteItemToTop(_ itemID: ClipboardItem.ID) {
        let activeGroupID = appState.activeFavoriteGroupID
        var favorites = appState.filteredFavoriteHistoryItems(in: activeGroupID, matching: nil)
        guard let index = favorites.firstIndex(where: { $0.id == itemID }),
              index > 0 else {
            return
        }

        favorites.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        appState.applyFavoriteOrdering(favorites.map(\.id), in: activeGroupID)
    }

    func moveFavoriteSnippets(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let activeGroupID = appState.activeFavoriteGroupID
        var snippets = appState.filteredFavoriteSnippets(in: activeGroupID, matching: nil)
        guard !snippets.isEmpty else { return }
        snippets.move(fromOffsets: offsets, toOffset: destination)
        appState.applyFavoriteSnippetOrdering(snippets.map(\.id), in: activeGroupID)
    }

    func moveFavoriteSnippetToTop(_ snippetID: FavoriteSnippet.ID) {
        let activeGroupID = appState.activeFavoriteGroupID
        var snippets = appState.filteredFavoriteSnippets(in: activeGroupID, matching: nil)
        guard let index = snippets.firstIndex(where: { $0.id == snippetID }),
              index > 0 else {
            return
        }

        snippets.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        appState.applyFavoriteSnippetOrdering(snippets.map(\.id), in: activeGroupID)
    }

    func moveFavoriteEntries(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let activeGroupID = appState.activeFavoriteGroupID
        var entries = appState.favoritePanelEntries(in: activeGroupID, matching: nil)
        guard !entries.isEmpty else { return }
        entries.move(fromOffsets: offsets, toOffset: destination)
        appState.applyFavoriteEntryOrdering(entries.map(\.orderKey), in: activeGroupID)
    }

    func moveFavoriteGroups(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        var groups = appState.favoriteGroups
        guard !groups.isEmpty else { return }
        groups.move(fromOffsets: offsets, toOffset: destination)
        appState.applyFavoriteGroupOrdering(groups.map(\.id))
    }

    func pasteStackEntry(id: ClipboardItem.StackEntry.ID) {
        guard appState.panelMode == .stack, isPanelVisible else { return }
        guard let entry = activeStackEntries.first(where: { $0.id == id }) else { return }

        appState.lastErrorMessage = nil
        switch pasteCoordinator.writeTextToPasteboard(entry.text) {
        case .success:
            clipboardMonitor.ignoreCurrentContents()
        case let .failed(message):
            showTransientNotice(message)
            return
        }

        Task {
            stackService.updateBridgeActive(false)
            defer { updateStackBridgeState() }

            let result = await pasteCoordinator.pasteCurrentClipboard(
                settings: appState.settings,
                focusTracker: focusTracker,
                didCollapsePanel: { [weak self] in
                    self?.collapsePanelAfterPasteIfNeeded()
                }
            )

            switch result {
            case .autoPasted:
                appState.updateActiveStackSession { session in
                    session.entries.removeAll { $0.id == id }
                }
                persistActiveStackSession()
                appState.lastErrorMessage = nil
            case .copiedOnly:
                appState.lastErrorMessage = nil
                showCopiedOnlyPasteNotice()
            case let .failed(message):
                appState.lastErrorMessage = nil
                showTransientNotice(message)
            }

            synchronizeAccessibilityPermissionState()
        }
    }

    func removeStackEntry(id: ClipboardItem.StackEntry.ID) {
        appState.updateActiveStackSession { session in
            session.entries.removeAll { $0.id == id }
        }
        persistActiveStackSession()
    }

    func stackPreviewLines(for item: ClipboardItem) -> [String] {
        Array(item.stackEntries.prefix(2).map {
            ClipboardItem.makePreviewText(from: $0.text)
        })
    }

    func fileRowHeadline(for item: ClipboardItem) -> String {
        guard item.kind == .file else { return "" }

        let names = item.fileDisplayNames
        guard names.count == 1 else {
            guard !names.isEmpty else { return AppLocalization.localized("文件") }
            if AppLocalization.isEnglish {
                return names.count == 1 ? "File" : "Files · \(names.count) items"
            }
            return "文件 · \(names.count)项"
        }

        guard let metadata = filePresentationMetadata(for: item) else {
            return AppLocalization.localized("文件")
        }

        if metadata.isFolder {
            if let folderItemCount = metadata.folderItemCount {
                if AppLocalization.isEnglish {
                    return "\(metadata.panelKindLabel) · \(folderItemCount) items"
                }
                return "\(metadata.panelKindLabel) · \(folderItemCount)项"
            }
            return metadata.panelKindLabel
        }

        if let sizeText = metadata.sizeText, !sizeText.isEmpty {
            return "\(metadata.panelKindLabel) · \(sizeText)"
        }

        return metadata.panelKindLabel
    }

    func fileRowDetailLines(for item: ClipboardItem) -> [String] {
        guard item.kind == .file else { return [] }

        let names = item.fileDisplayNames
        guard !names.isEmpty else { return [AppLocalization.localized("文件项目")] }

        if names.count == 1,
           let metadata = filePresentationMetadata(for: item) {
            return [metadata.displayName]
        }

        var lines = Array(names.prefix(2))
        if names.count > 2 {
            if AppLocalization.isEnglish {
                lines.append("and \(names.count - 2) more")
            } else {
                lines.append("等 \(names.count - 2) 项")
            }
        }
        return lines
    }

    func importCurrentPreviewTextToStack() {
        guard let text = fullPreviewCurrentItem?.textContent else { return }
        clearFullPreviewPresentationState()
        openStackSession(from: currentStackHistoryItem())
        appState.stackProcessorDraft = text
        appState.isStackProcessorPresented = true
        applyStackProcessorDraft(.replace)
        updateAuxiliaryPanelPresentation()
    }

    func updateStackProcessorDraft(_ text: String) {
        appState.stackProcessorDraft = text
    }

    func toggleStackDelimiter(_ option: StackDelimiterOption) {
        if appState.stackDelimiterOptions.contains(option) {
            appState.stackDelimiterOptions.remove(option)
        } else {
            appState.stackDelimiterOptions.insert(option)
        }
    }

    func updateStackCustomDelimiter(_ delimiter: String) {
        appState.stackCustomDelimiter = delimiter
    }

    func applyStackProcessorDraft(
        _ mode: StackProcessorApplyMode,
        closePanelAfterApply: Bool = false
    ) {
        guard appState.panelMode == .stack else { return }

        let newEntries = stackService.makeEntries(
            from: parsedStackProcessorSegments(),
            orderMode: currentStackOrderMode,
            source: .processor
        )
        guard !newEntries.isEmpty else {
            showTransientNotice(AppLocalization.localized("先输入可拆分的文本内容。"), tone: .warning)
            return
        }

        appState.updateActiveStackSession { session in
            switch mode {
            case .insertAbove:
                session.entries = newEntries + session.entries
            case .insertBelow:
                session.entries.append(contentsOf: newEntries)
            case .replace:
                session.entries = newEntries
            }
        }
        persistActiveStackSession()

        guard closePanelAfterApply, appState.isStackProcessorPresented else { return }
        appState.isStackProcessorPresented = false
        updateAuxiliaryPanelPresentation()
    }

    func showTransientNotice(
        _ message: String,
        tone: TransientNotice.Tone = .warning,
        duration: TimeInterval = 2.8
    ) {
        transientNoticeDismissWorkItem?.cancel()
        let notice = TransientNotice(message: message, tone: tone)
        appState.transientNotice = notice

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.appState.transientNotice?.id == notice.id else { return }
            self?.appState.transientNotice = nil
        }
        transientNoticeDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func showCopiedOnlyPasteNotice() {
        if appState.settings.autoPasteEnabled, !PermissionCenter.isAccessibilityGranted() {
            showTransientNotice(
                AppLocalization.localized("未授予辅助权限，已复制到系统剪贴板。授权后可自动粘贴到输入框。"),
                tone: .info,
                duration: 3.4
            )
            return
        }

        showTransientNotice(AppLocalization.localized("已复制并切回前台应用，请手动粘贴。"), tone: .info)
    }

    func chooseDataStorageLocation() {
        guard !isDataStorageMigrationInProgress else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = AppLocalization.localized("迁移")
        panel.message = AppLocalization.localized("选择新的数据存储文件夹。历史记录、收藏和资源文件会自动迁移到这里。")
        panel.directoryURL = activeDataStorageRootURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let destinationURL = panel.url?.standardizedFileURL else {
            return
        }

        requestDataStorageMigration(to: destinationURL)
    }

    func resetDataStorageLocationToDefault() {
        requestDataStorageMigration(to: Self.defaultDataStorageRootURL(fileManager: fileManager))
    }

    func revealDataStorageLocationInFinder() {
        let directoryURL = activeDataStorageRootURL
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
    }

    private func requestDataStorageMigration(to destinationRootURL: URL) {
        let targetURL = destinationRootURL.standardizedFileURL
        guard targetURL != activeDataStorageRootURL.standardizedFileURL else {
            showTransientNotice(AppLocalization.localized("当前已经在使用这个存储位置。"), tone: .info)
            return
        }

        Task { @MainActor [weak self] in
            await self?.performDataStorageMigration(to: targetURL)
        }
    }

    private func performDataStorageMigration(to destinationRootURL: URL) async {
        guard !isDataStorageMigrationInProgress else { return }

        let sourceRootURL = activeDataStorageRootURL.standardizedFileURL
        let targetRootURL = destinationRootURL.standardizedFileURL
        let defaultRootURL = Self.defaultDataStorageRootURL(fileManager: fileManager).standardizedFileURL
        let previousDescriptor = dataStorageDescriptor(from: appState.settings)
        let targetDescriptor = DataStorageDescriptor(
            rootURL: targetRootURL,
            customDirectoryPath: targetRootURL == defaultRootURL ? nil : targetRootURL.path,
            customDirectoryBookmark: targetRootURL == defaultRootURL ? nil : bookmarkData(for: targetRootURL),
            scopedAccessURL: targetRootURL == defaultRootURL ? nil : targetRootURL
        )

        isDataStorageMigrationInProgress = true
        dataStorageMigrationStatusText = AppLocalization.localized("正在迁移数据到新位置…")
        showTransientNotice(AppLocalization.localized("正在迁移数据到新位置，请稍候。"), tone: .info, duration: 4.0)
        clipboardMonitor.stop()
        persistence.cancelPendingSave()
        favoriteSnippetPersistence.cancelPendingSave()
        favoriteGroupPersistence.cancelPendingSave()

        do {
            try await Task.detached(priority: .userInitiated) {
                try Self.prepareDataStorageMigration(
                    fileManager: FileManager.default,
                    from: sourceRootURL,
                    to: targetRootURL
                )
            }.value

            reconfigurePersistenceStores(using: targetDescriptor)
            appState.updateSettings { settings in
                settings.dataStorageCustomDirectoryPath = targetDescriptor.customDirectoryPath
                settings.dataStorageCustomDirectoryBookmark = targetDescriptor.customDirectoryBookmark
            }
            try persistence.saveImmediately(appState.history)
            try favoriteSnippetPersistence.saveImmediately(appState.favoriteSnippets)
            try favoriteGroupPersistence.saveImmediately(appState.favoriteGroups)
            persistence.cleanupOrphanedAssets(using: appState.history)

            if sourceRootURL != targetRootURL {
                try? Self.cleanupMigratedData(
                    fileManager: fileManager,
                    from: sourceRootURL
                )
            }

            dataStorageMigrationStatusText = nil
            isDataStorageMigrationInProgress = false
            clipboardMonitor.start()
            showTransientNotice(AppLocalization.localized("数据已迁移到新的存储位置。"), tone: .info, duration: 3.2)
        } catch {
            reconfigurePersistenceStores(using: previousDescriptor)
            appState.updateSettings { settings in
                settings.dataStorageCustomDirectoryPath = previousDescriptor.customDirectoryPath
                settings.dataStorageCustomDirectoryBookmark = previousDescriptor.customDirectoryBookmark
            }
            persistence.save(appState.history)
            favoriteSnippetPersistence.save(appState.favoriteSnippets)
            favoriteGroupPersistence.save(appState.favoriteGroups)
            dataStorageMigrationStatusText = nil
            isDataStorageMigrationInProgress = false
            clipboardMonitor.start()
            appState.lastErrorMessage = error.localizedDescription
        }
    }

    nonisolated private static func prepareDataStorageMigration(
        fileManager: FileManager,
        from sourceRootURL: URL,
        to destinationRootURL: URL
    ) throws {
        try fileManager.createDirectory(at: destinationRootURL, withIntermediateDirectories: true)

        let managedNames = ["history.json", "favorite-snippets.json", "favorite-groups.json", "assets"]
        let conflictingNames = managedNames.filter { name in
            fileManager.fileExists(atPath: destinationRootURL.appendingPathComponent(name).path)
        }
        if !conflictingNames.isEmpty {
            throw NSError(
                domain: "EdgeClip.DataStorageMigration",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: AppLocalization.localized("目标文件夹已包含 Edge Clip 数据，请选择空文件夹或先清理同名数据。")
                ]
            )
        }

        let sourceAssetsURL = sourceRootURL.appendingPathComponent("assets", isDirectory: true)
        let destinationAssetsURL = destinationRootURL.appendingPathComponent("assets", isDirectory: true)
        if fileManager.fileExists(atPath: sourceAssetsURL.path) {
            try fileManager.copyItem(at: sourceAssetsURL, to: destinationAssetsURL)
        }
    }

    nonisolated private static func cleanupMigratedData(
        fileManager: FileManager,
        from sourceRootURL: URL
    ) throws {
        let managedNames = ["history.json", "favorite-snippets.json", "assets"]
        for name in managedNames {
            let url = sourceRootURL.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }

        let remainingItems = try? fileManager.contentsOfDirectory(
            at: sourceRootURL,
            includingPropertiesForKeys: nil
        )
        if remainingItems?.isEmpty == true {
            try? fileManager.removeItem(at: sourceRootURL)
        }
    }

    func openResolvedURL(for item: ClipboardItem) {
        guard let url = item.resolvedURL else {
            appState.lastErrorMessage = AppLocalization.localized("当前记录不是可访问的网址")
            return
        }

        if !NSWorkspace.shared.open(url) {
            appState.lastErrorMessage = AppLocalization.localized("无法使用默认浏览器打开该网址")
        } else {
            appState.lastErrorMessage = nil
        }
    }

    func revealFileInFinder(url: URL, securityScopedBookmarkData: Data?) {
        let candidateURL = resolvedFinderURL(
            from: url,
            securityScopedBookmarkData: securityScopedBookmarkData
        )

        let didStartAccessing = candidateURL.startAccessingSecurityScopedResource()
        NSWorkspace.shared.activateFileViewerSelecting([candidateURL])
        if didStartAccessing {
            candidateURL.stopAccessingSecurityScopedResource()
        }
    }

    func openCurrentPreviewInFinder() {
        guard let fullPreviewContent, fullPreviewContent.kind == .file else { return }

        if fullPreviewUsesFileOverview {
            if fullPreviewContent.items.count == 1,
               let item = fullPreviewContent.items.first {
                openPreviewItemInFinder(item)
                return
            }

            let candidateURLs = fullPreviewContent.items.compactMap { item -> URL? in
                guard let url = item.url else { return nil }
                return resolvedFinderURL(
                    from: url,
                    securityScopedBookmarkData: item.securityScopedBookmarkData
                )
            }

            guard !candidateURLs.isEmpty else {
                appState.lastErrorMessage = AppLocalization.localized("当前没有可在访达中打开的文件")
                return
            }

            let accessedURLs = candidateURLs.filter { $0.startAccessingSecurityScopedResource() }
            NSWorkspace.shared.activateFileViewerSelecting(candidateURLs)
            accessedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            appState.lastErrorMessage = nil
            return
        }

        guard let item = fullPreviewCurrentItem else {
            appState.lastErrorMessage = AppLocalization.localized("当前没有可在访达中打开的文件")
            return
        }

        openPreviewItemInFinder(item)
    }

    func imageAssetURL(for item: ClipboardItem) -> URL? {
        guard let relativePath = item.imageAssetRelativePath else {
            return nil
        }

        return persistence.imageAssetURL(for: relativePath)
    }

    func toggleFavorite(for itemID: ClipboardItem.ID) {
        Task { [weak self] in
            await self?.toggleFavoriteAsync(for: itemID)
        }
    }

    func resolvedTextContent(for item: ClipboardItem) -> String? {
        if let persistedText = persistence.textContent(for: item) {
            if item.availabilityIssue != nil {
                clearItemAvailabilityIssue(for: item.id)
            }
            return persistedText
        }

        guard let clipboardText = matchingCurrentPasteboardText(for: item) else {
            return nil
        }

        repairMissingTextStorageIfNeeded(for: item, with: clipboardText)
        if item.availabilityIssue != nil {
            clearItemAvailabilityIssue(for: item.id)
        }
        return clipboardText
    }

    func previewImage(for item: ClipboardItem) -> NSImage? {
        guard let relativePath = item.imageAssetRelativePath else {
            return nil
        }

        let cacheKey = relativePath as NSString
        if let cached = imagePreviewCache.object(forKey: cacheKey) {
            return cached
        }

        let url = persistence.imageAssetURL(for: relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let thumbnailMaxPixelSize = 240
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
        ]

        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            let thumbnail = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            imagePreviewCache.setObject(
                thumbnail,
                forKey: cacheKey,
                cost: cgImage.width * cgImage.height * 4
            )
            return thumbnail
        }

        guard let fallback = NSImage(contentsOf: url) else {
            return nil
        }

        let cost = max(1, Int(fallback.size.width * fallback.size.height) * 4)
        imagePreviewCache.setObject(fallback, forKey: cacheKey, cost: cost)
        return fallback
    }

    func cachedPreviewImage(for item: ClipboardItem) -> NSImage? {
        guard let relativePath = item.imageAssetRelativePath else {
            return nil
        }

        return imagePreviewCache.object(forKey: relativePath as NSString)
    }

    func favoritePanelEntries(matching query: String? = nil) -> [FavoritePanelEntry] {
        appState.favoritePanelEntries(in: appState.activeFavoriteGroupID, matching: query)
    }

    func selectFavoriteGroup(_ groupID: FavoriteGroup.ID?) {
        appState.selectFavoriteGroup(groupID)
    }

    @discardableResult
    func createFavoriteGroup(selecting: Bool = true, requestRename: Bool = true) -> FavoriteGroup {
        let group = appState.addFavoriteGroup(named: FavoriteGroup.defaultGeneratedName)
        if selecting {
            appState.activeTab = .favorites
            appState.activeFavoriteGroupID = group.id
            appState.searchQuery = ""
        }
        if requestRename {
            appState.requestFavoriteGroupRename(group.id)
        }
        return group
    }

    func renameFavoriteGroup(_ groupID: FavoriteGroup.ID, to requestedName: String) {
        appState.updateFavoriteGroup(groupID: groupID) { group in
            group.name = FavoriteGroup.clampedUserInputName(requestedName)
        }
    }

    func removeFavoriteGroup(_ groupID: FavoriteGroup.ID) {
        guard appState.favoriteGroup(withID: groupID) != nil else { return }
        appState.removeFavoriteGroup(groupID: groupID)
        showTransientNotice(AppLocalization.localized("已移除分组。"), tone: .info)
    }

    func addItemToFavoriteGroup(_ item: ClipboardItem, groupID: FavoriteGroup.ID?) {
        Task { [weak self] in
            await self?.addItemToFavoriteGroupAsync(item, groupID: groupID)
        }
    }

    func addFavoriteSnippetToGroup(_ snippetID: FavoriteSnippet.ID, groupID: FavoriteGroup.ID?) {
        guard appState.favoriteSnippet(withID: snippetID) != nil else { return }

        let targetGroupID: FavoriteGroup.ID
        if let groupID {
            targetGroupID = groupID
        } else {
            targetGroupID = createFavoriteGroup(selecting: false, requestRename: false).id
        }

        if appState.favoriteSnippet(withID: snippetID)?.groupIDs.contains(targetGroupID) == true {
            return
        }

        appState.addFavoriteGroupReference(targetGroupID, toFavoriteSnippetID: snippetID)
        showTransientNotice(AppLocalization.localized("已加入分组。"), tone: .info)
    }

    func removeFavoriteSnippetFromActiveGroup(_ snippetID: FavoriteSnippet.ID) {
        guard let activeGroupID = appState.activeFavoriteGroupID else { return }
        guard appState.favoriteSnippet(withID: snippetID)?.groupIDs.contains(activeGroupID) == true else { return }
        appState.removeFavoriteGroupReference(activeGroupID, fromFavoriteSnippetID: snippetID)
        showTransientNotice(AppLocalization.localized("已从当前分组移除。"), tone: .info)
    }

    func removeFavoriteItemFromActiveGroup(_ itemID: ClipboardItem.ID) {
        guard let activeGroupID = appState.activeFavoriteGroupID else { return }
        guard appState.item(withID: itemID)?.favoriteGroupIDs.contains(activeGroupID) == true else { return }
        appState.removeFavoriteGroupReference(activeGroupID, fromHistoryItemID: itemID)
        showTransientNotice(AppLocalization.localized("已从当前分组移除。"), tone: .info)
    }

    func isItemFavorited(_ item: ClipboardItem) -> Bool {
        switch item.kind {
        case .text, .passthroughText:
            guard let fingerprint = favoriteSnippetFingerprint(for: item) else { return false }
            return appState.favoriteSnippets.contains { $0.sourceTextFingerprint == fingerprint }
        case .image, .file, .stack:
            return item.isFavorite
        }
    }

    func isItem(_ item: ClipboardItem, inFavoriteGroup groupID: FavoriteGroup.ID) -> Bool {
        switch item.kind {
        case .text, .passthroughText:
            guard let fingerprint = favoriteSnippetFingerprint(for: item) else { return false }
            return appState.favoriteSnippets.contains {
                $0.sourceTextFingerprint == fingerprint && $0.groupIDs.contains(groupID)
            }
        case .image, .file, .stack:
            return item.favoriteGroupIDs.contains(groupID)
        }
    }

    private func addItemToFavoriteGroupAsync(_ item: ClipboardItem, groupID: FavoriteGroup.ID?) async {
        let targetGroupID: FavoriteGroup.ID
        let shouldJumpToFavoritesForRename: Bool
        if let groupID {
            targetGroupID = groupID
            shouldJumpToFavoritesForRename = false
        } else {
            let createdGroup = createFavoriteGroup(selecting: !isItemFavorited(item), requestRename: !isItemFavorited(item))
            targetGroupID = createdGroup.id
            shouldJumpToFavoritesForRename = !isItemFavorited(item)
        }

        switch item.kind {
        case .text:
            guard let snippetID = ensureFavoriteSnippet(for: item) else { return }
            if appState.favoriteSnippet(withID: snippetID)?.groupIDs.contains(targetGroupID) == true {
                return
            }
            appState.addFavoriteGroupReference(targetGroupID, toFavoriteSnippetID: snippetID)
        case .passthroughText:
            guard let snippetID = await ensureFavoritePassthroughSnippet(for: item) else { return }
            if appState.favoriteSnippet(withID: snippetID)?.groupIDs.contains(targetGroupID) == true {
                return
            }
            appState.addFavoriteGroupReference(targetGroupID, toFavoriteSnippetID: snippetID)
        case .image, .file, .stack:
            guard let favoriteItemID = ensureFavoriteHistoryItem(for: item) else { return }
            if appState.item(withID: favoriteItemID)?.favoriteGroupIDs.contains(targetGroupID) == true {
                return
            }
            appState.addFavoriteGroupReference(targetGroupID, toHistoryItemID: favoriteItemID)
        }

        if shouldJumpToFavoritesForRename {
            appState.activeTab = .favorites
            appState.activeFavoriteGroupID = targetGroupID
            appState.searchQuery = ""
        }
        showTransientNotice(AppLocalization.localized("已加入分组。"), tone: .info)
    }

    private func favoriteSnippetFingerprint(for item: ClipboardItem) -> String? {
        switch item.kind {
        case .text:
            return item.textPayload?.contentFingerprint
        case .passthroughText:
            guard let previewText = item.passthroughTextPayload?.previewText,
                  !previewText.isEmpty else { return nil }
            return ClipboardItem.contentFingerprint(for: previewText)
        case .image, .file, .stack:
            return nil
        }
    }

    private func ensureFavoriteSnippet(for item: ClipboardItem) -> FavoriteSnippet.ID? {
        guard item.kind == .text,
              let text = resolvedTextContent(for: item) ?? item.textContent,
              let sourceFingerprint = item.textPayload?.contentFingerprint else {
            showTransientNotice(AppLocalization.localized("当前文本内容已失效，无法加入收藏。"))
            return nil
        }

        if let existing = appState.favoriteSnippets.first(where: { $0.sourceTextFingerprint == sourceFingerprint }) {
            return existing.id
        }

        let snippet = FavoriteSnippet(text: text, sourceTextFingerprint: sourceFingerprint)
        appState.addFavoriteSnippet(snippet)
        return snippet.id
    }

    private func ensureFavoritePassthroughSnippet(for item: ClipboardItem) async -> FavoriteSnippet.ID? {
        guard item.kind == .passthroughText else { return ensureFavoriteSnippet(for: item) }
        guard let text = await durablePassthroughText(for: item) else {
            markItemAvailabilityIssue(for: item.id, issue: .sourceUnavailable)
            showTransientNotice(AppLocalization.localized("原始内容已失效，无法收藏。"))
            return nil
        }

        let sourceFingerprint = ClipboardItem.contentFingerprint(for: text)
        if let existing = appState.favoriteSnippets.first(where: { $0.sourceTextFingerprint == sourceFingerprint }) {
            return existing.id
        }

        let snippet = FavoriteSnippet(text: text, sourceTextFingerprint: sourceFingerprint)
        appState.addFavoriteSnippet(snippet)

        if let cacheToken = item.passthroughTextCacheToken {
            readbackServiceClient.discardCachedText(cacheToken: cacheToken)
        }

        return snippet.id
    }

    private func ensureFavoriteHistoryItem(for item: ClipboardItem) -> ClipboardItem.ID? {
        guard let latestItem = appState.item(withID: item.id) else { return nil }

        switch latestItem.kind {
        case .file:
            if latestItem.isFavorite {
                return latestItem.id
            }
            materializeProtectedFileFavorite(for: latestItem, showsNotice: false)
            return appState.item(withID: latestItem.id)?.isFavorite == true ? latestItem.id : nil
        case .image, .stack:
            if latestItem.isFavorite {
                return latestItem.id
            }
            appState.updateItem(itemID: latestItem.id) { updatedItem in
                updatedItem.isFavorite = true
            }
            return latestItem.id
        case .text, .passthroughText:
            return nil
        }
    }

    func pasteFavoriteSnippet(id: FavoriteSnippet.ID) {
        guard let snippet = appState.favoriteSnippet(withID: id) else { return }
        appState.lastErrorMessage = nil

        switch pasteCoordinator.writeTextToPasteboard(snippet.text) {
        case .success:
            clipboardMonitor.ignoreCurrentContents()
        case .failed(let message):
            showTransientNotice(message)
            return
        }

        Task {
            let result = await pasteCoordinator.pasteCurrentClipboard(
                settings: appState.settings,
                focusTracker: focusTracker,
                didCollapsePanel: { [weak self] in
                    self?.collapsePanelAfterPasteIfNeeded()
                }
            )

            switch result {
            case .autoPasted:
                appState.lastErrorMessage = nil
                appState.updateFavoriteSnippet(snippetID: id) { entry in
                    entry.updatedAt = Date()
                }
                schedulePinnedPanelFocusReclaimAfterAutoPasteIfNeeded()
            case .copiedOnly:
                appState.lastErrorMessage = nil
                showCopiedOnlyPasteNotice()
            case .failed(let message):
                appState.lastErrorMessage = nil
                showTransientNotice(message)
            }

            synchronizeAccessibilityPermissionState()
        }
    }

    func openNewFavoriteSnippetEditor() {
        if appState.isFavoriteEditorPresented && favoriteEditorHasUnsavedChanges {
            requestFavoriteEditorTransition(context: .createNext) {
                self.presentNewFavoriteSnippetEditor()
            }
            return
        }

        presentNewFavoriteSnippetEditor()
    }

    private func presentNewFavoriteSnippetEditor() {
        clearFullPreviewPresentationState()
        appState.isStackProcessorPresented = false
        activateFavoriteEditorPresentation()
        appState.activeTab = .favorites
        appState.searchQuery = ""
        appState.activeFavoriteSnippetID = nil
        appState.favoriteEditorDraft = ""
        appState.favoriteEditorInitialDraft = ""
        appState.isFavoriteEditorPresented = true
        updatePanelKeyMonitoringState()
        updateAuxiliaryPanelPresentation()
    }

    func openFavoriteSnippetEditor(snippetID: FavoriteSnippet.ID) {
        if appState.isFavoriteEditorPresented &&
            appState.activeFavoriteSnippetID != snippetID &&
            favoriteEditorHasUnsavedChanges {
            requestFavoriteEditorTransition(context: .editNext) {
                self.presentFavoriteSnippetEditor(snippetID: snippetID)
            }
            return
        }

        presentFavoriteSnippetEditor(snippetID: snippetID)
    }

    private func presentFavoriteSnippetEditor(snippetID: FavoriteSnippet.ID) {
        guard let snippet = appState.favoriteSnippet(withID: snippetID) else { return }
        clearFullPreviewPresentationState()
        appState.isStackProcessorPresented = false
        activateFavoriteEditorPresentation()
        appState.activeTab = .favorites
        appState.searchQuery = ""
        appState.activeFavoriteSnippetID = snippetID
        appState.favoriteEditorDraft = snippet.text
        appState.favoriteEditorInitialDraft = snippet.text
        appState.isFavoriteEditorPresented = true
        updatePanelKeyMonitoringState()
        updateAuxiliaryPanelPresentation()
    }

    func updateFavoriteEditorDraft(_ text: String) {
        appState.favoriteEditorDraft = text
    }

    var canSaveFavoriteSnippetDraft: Bool {
        !appState.favoriteEditorDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveFavoriteSnippetFromEditor() {
        _ = persistFavoriteSnippetFromEditor(shouldCloseEditor: false)
    }

    @discardableResult
    private func persistFavoriteSnippetFromEditor(shouldCloseEditor: Bool) -> Bool {
        let draft = appState.favoriteEditorDraft
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else {
            showTransientNotice(AppLocalization.localized("先输入要保存的收藏文本。"), tone: .warning)
            return false
        }

        let fingerprint = ClipboardItem.contentFingerprint(for: draft)
        if let editingID = appState.activeFavoriteSnippetID {
            if let duplicate = appState.favoriteSnippets.first(where: { $0.id != editingID && $0.contentFingerprint == fingerprint }) {
                appState.activeFavoriteSnippetID = duplicate.id
                appState.favoriteEditorDraft = duplicate.text
                appState.favoriteEditorInitialDraft = duplicate.text
                appState.activeTab = .favorites
                appState.searchQuery = ""
                showTransientNotice(AppLocalization.localized("已有相同内容的收藏，已定位到现有条目。"), tone: .info)
                return true
            }

            appState.updateFavoriteSnippet(snippetID: editingID) { snippet in
                snippet.text = draft
            }
            appState.activeFavoriteSnippetID = editingID
            appState.favoriteEditorDraft = draft
            appState.favoriteEditorInitialDraft = draft
            appState.activeTab = .favorites
            appState.searchQuery = ""
            if shouldCloseEditor {
                dismissFavoriteEditorIfNeeded(restorePinState: true, clearDraft: true)
                updateAuxiliaryPanelPresentation()
            }
            showTransientNotice(AppLocalization.localized("已更新收藏。"), tone: .info)
            return true
        }

        if let duplicate = appState.favoriteSnippets.first(where: { $0.contentFingerprint == fingerprint }) {
            appState.activeFavoriteSnippetID = duplicate.id
            appState.favoriteEditorDraft = duplicate.text
            appState.favoriteEditorInitialDraft = duplicate.text
            appState.activeTab = .favorites
            appState.searchQuery = ""
            showTransientNotice(AppLocalization.localized("已有相同内容的收藏，已定位到现有条目。"), tone: .info)
            return true
        }

        let snippet = FavoriteSnippet(text: draft)
        appState.addFavoriteSnippet(snippet)
        appState.activeFavoriteSnippetID = snippet.id
        appState.favoriteEditorDraft = snippet.text
        appState.favoriteEditorInitialDraft = snippet.text
        appState.activeTab = .favorites
        appState.searchQuery = ""
        if shouldCloseEditor {
            dismissFavoriteEditorIfNeeded(restorePinState: true, clearDraft: true)
            updateAuxiliaryPanelPresentation()
        }
        showTransientNotice(AppLocalization.localized("已新增收藏。"), tone: .info)
        return true
    }

    func removeFavoriteSnippet(snippetID: FavoriteSnippet.ID, showsNotice: Bool = true) {
        guard let snippet = appState.favoriteSnippet(withID: snippetID) else { return }

        do {
            try restoreFavoriteSnippetToHistory(snippet)
        } catch {
            appState.lastErrorMessage = error.localizedDescription
            return
        }

        appState.removeFavoriteSnippet(snippetID: snippetID)
        if appState.activeFavoriteSnippetID == snippetID {
            dismissFavoriteEditorIfNeeded(restorePinState: true, clearDraft: true)
            updateAuxiliaryPanelPresentation()
        }
        if showsNotice {
            showTransientNotice(AppLocalization.localized("已移出收藏。"), tone: .info)
        }
    }

    private func restoreFavoriteSnippetToHistory(_ snippet: FavoriteSnippet) throws {
        let itemID = UUID()
        let payload = try persistence.storeTextPayload(snippet.text, itemID: itemID)
        let item = ClipboardItem(
            id: itemID,
            createdAt: Date(),
            kind: .text,
            textPayload: payload
        )
        appState.prependHistoryItem(item, collapseDuplicates: false)
        appState.lastErrorMessage = nil
    }

    private func matchingCurrentPasteboardText(for item: ClipboardItem) -> String? {
        guard item.kind == .text,
              let expectedFingerprint = item.textPayload?.contentFingerprint,
              let currentText = NSPasteboard.general.string(forType: .string),
              !currentText.isEmpty,
              ClipboardItem.contentFingerprint(for: currentText) == expectedFingerprint else {
            return nil
        }

        return currentText
    }

    private func transferReadyItem(from item: ClipboardItem) -> ClipboardItem {
        guard item.kind == .file,
              let protectedURLs = protectedFileURLs(for: item),
              var filePayload = item.filePayload else {
            return item
        }

        filePayload.fileURLs = protectedURLs
        filePayload.securityScopedBookmarks = Array(repeating: nil, count: protectedURLs.count)

        var protectedItem = item
        protectedItem.filePayload = filePayload
        return protectedItem
    }

    private func protectedFileURLs(for item: ClipboardItem) -> [URL]? {
        let protectedURLs = persistence.protectedFileURLs(for: item)
        guard !protectedURLs.isEmpty, protectedURLs.count == item.fileURLs.count else {
            return nil
        }
        return protectedURLs
    }

    func unavailableRowMessage(for item: ClipboardItem) -> String? {
        switch item.kind {
        case .text:
            return hasUnavailableStoredText(item) ? AppLocalization.localized("文本内容已失效，无法写回。") : nil
        case .passthroughText:
            if item.isAbandonedPassthroughText {
                return AppLocalization.localized("在读取完成前，剪贴板已发生变化，因此未保留此内容。")
            }
            if item.isDiscardedPassthroughText {
                return AppLocalization.localized("内容过大，为避免性能问题，已不再保留。")
            }
            return hasUnavailablePassthroughText(item) ? AppLocalization.localized("原始内容已失效，无法写回。") : nil
        case .image, .file, .stack:
            return nil
        }
    }

    private func toggleFavoriteAsync(for itemID: ClipboardItem.ID) async {
        guard let item = appState.item(withID: itemID) else { return }

        switch item.kind {
        case .file:
            if item.isFavorite {
                unfavoriteAndPromoteItem(item)
                return
            }
            materializeProtectedFileFavorite(for: item, showsNotice: true)
        case .image, .stack:
            if item.isFavorite {
                unfavoriteAndPromoteItem(item)
            } else {
                appState.toggleFavorite(for: itemID)
            }
        case .text:
            toggleTextFavorite(item)
        case .passthroughText:
            await togglePassthroughTextFavorite(item)
        }
    }

    private func materializeProtectedFileFavorite(
        for item: ClipboardItem,
        showsNotice: Bool
    ) {
        guard item.kind == .file else { return }

        let resolved = resolveSourceFileURLsForTransfer(item)
        defer { resolved.stopAccess() }

        guard !resolved.urls.isEmpty, resolved.urls.count == item.fileURLs.count else {
            if showsNotice {
                showTransientNotice(AppLocalization.localized("源文件已失效，无法收藏。"))
            }
            return
        }

        do {
            let snapshot = try persistence.storeProtectedFileSnapshot(
                from: resolved.urls,
                itemID: item.id
            )

            appState.updateItem(itemID: item.id) { updatedItem in
                guard var payload = updatedItem.filePayload else { return }
                payload.protectedAssetRelativePaths = snapshot.relativePaths
                payload.protectedAssetByteCount = snapshot.totalByteCount
                updatedItem.filePayload = payload
                updatedItem.isFavorite = true
                updatedItem.availabilityIssue = nil
            }
            invalidateFileAvailabilityCache(for: [item.id])
            invalidateFilePresentationCache(for: [item.id])

            if showsNotice {
                showTransientNotice(AppLocalization.localized("已为收藏保存本地副本。"), tone: .info)
            }
        } catch {
            if showsNotice {
                showTransientNotice(AppLocalization.localized("源文件已失效，无法收藏。"))
            }
        }
    }

    private func unfavoriteAndPromoteItem(_ item: ClipboardItem) {
        appState.updateItem(itemID: item.id) { updatedItem in
            updatedItem.isFavorite = false
            updatedItem.createdAt = Date()
        }
        appState.applyHistoryPolicies()

        if item.kind == .file {
            invalidateFileAvailabilityCache(for: [item.id])
            invalidateFilePresentationCache(for: [item.id])
        }
    }

    private func toggleTextFavorite(_ item: ClipboardItem) {
        guard item.kind == .text,
              let text = resolvedTextContent(for: item) ?? item.textContent,
              let sourceFingerprint = item.textPayload?.contentFingerprint else {
            showTransientNotice(AppLocalization.localized("当前文本内容已失效，无法加入收藏。"))
            return
        }

        if let existing = appState.favoriteSnippets.first(where: { $0.sourceTextFingerprint == sourceFingerprint }) {
            removeFavoriteSnippet(snippetID: existing.id, showsNotice: true)
            return
        }

        let snippet = FavoriteSnippet(
            text: text,
            sourceTextFingerprint: sourceFingerprint
        )
        appState.addFavoriteSnippet(snippet)
        showTransientNotice(AppLocalization.localized("已加入收藏。"), tone: .info)
    }

    private func togglePassthroughTextFavorite(_ item: ClipboardItem) async {
        guard item.kind == .passthroughText else { return }

        guard let text = await durablePassthroughText(for: item) else {
            markItemAvailabilityIssue(for: item.id, issue: .sourceUnavailable)
            showTransientNotice(AppLocalization.localized("原始内容已失效，无法收藏。"))
            return
        }

        let sourceFingerprint = ClipboardItem.contentFingerprint(for: text)
        if let existing = appState.favoriteSnippets.first(where: { $0.sourceTextFingerprint == sourceFingerprint }) {
            removeFavoriteSnippet(snippetID: existing.id, showsNotice: true)
            return
        }

        let snippet = FavoriteSnippet(
            text: text,
            sourceTextFingerprint: sourceFingerprint
        )
        appState.addFavoriteSnippet(snippet)

        if let cacheToken = item.passthroughTextCacheToken {
            readbackServiceClient.discardCachedText(cacheToken: cacheToken)
        }

        showTransientNotice(AppLocalization.localized("已加入收藏。"), tone: .info)
    }

    private func durablePassthroughText(for item: ClipboardItem) async -> String? {
        guard item.kind == .passthroughText else { return nil }

        if let cacheToken = item.passthroughTextCacheToken,
           let cachedText = try? await readbackServiceClient.readCachedText(cacheToken: cacheToken) {
            let normalizedText = cachedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty {
                return normalizedText
            }
        }

        let currentChangeCount = NSPasteboard.general.changeCount
        guard item.isPassthroughTextValid(currentChangeCount: currentChangeCount) else {
            return nil
        }

        if let currentText = NSPasteboard.general.string(forType: .string) {
            let normalizedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalizedText.isEmpty {
                return normalizedText
            }
        }

        let request = ClipboardReadbackRequest(
            requestID: UUID(),
            expectedChangeCount: currentChangeCount,
            inlineTextThresholdBytes: ClipboardItem.maximumStoredTextByteCount,
            previewCharacterLimit: 2_000
        )

        guard let response = try? await readbackServiceClient.fetchClipboardText(request) else {
            return nil
        }

        switch response.outcome {
        case .smallText:
            return response.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        case .cachedOneTime:
            guard let cacheToken = response.cacheToken,
                  let cachedText = try? await readbackServiceClient.readCachedText(cacheToken: cacheToken) else {
                return nil
            }
            return cachedText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .stale, .failed:
            return nil
        }
    }

    private func preparePassthroughTextForTransfer(_ item: ClipboardItem) async -> PasteCoordinator.PasteboardWriteResult {
        guard item.kind == .passthroughText else {
            return .failed(AppLocalization.localized("当前记录不是可恢复的超长文本。"))
        }

        if item.isAbandonedPassthroughText || item.isDiscardedPassthroughText {
            markItemAvailabilityIssue(for: item.id, issue: .sourceUnavailable)
            return .failed(AppLocalization.localized("原始内容已失效，无法写回，请重新复制一次。"))
        }

        if let cacheToken = item.passthroughTextCacheToken {
            do {
                try await readbackServiceClient.restoreCachedText(cacheToken: cacheToken)
                if let delay = passthroughRestoreSettleDelay(forByteCount: item.passthroughTextByteCount) {
                    try? await Task.sleep(nanoseconds: delay)
                }
                clipboardMonitor.ignoreCurrentContents()
                clearItemAvailabilityIssue(for: item.id)
                return .success
            } catch {
                // Fall through. If the source text is still on the system clipboard,
                // we can continue to use it even after the helper cache expires.
            }
        }

        if item.isPassthroughTextValid(currentChangeCount: NSPasteboard.general.changeCount) {
            clipboardMonitor.ignoreCurrentContents()
            clearItemAvailabilityIssue(for: item.id)
            return .success
        }

        markItemAvailabilityIssue(for: item.id, issue: .sourceUnavailable)
        return .failed(AppLocalization.localized("原始内容已失效，无法写回，请重新复制一次。"))
    }

    private func passthroughRestoreSettleDelay(forByteCount byteCount: Int?) -> UInt64? {
        guard let byteCount else {
            return nil
        }

        let seconds: Double
        switch byteCount {
        case (96 * 1_024 * 1_024)...:
            seconds = 0.18
        case (48 * 1_024 * 1_024)...:
            seconds = 0.12
        case (16 * 1_024 * 1_024)...:
            seconds = 0.08
        default:
            return nil
        }

        return UInt64(seconds * 1_000_000_000)
    }

    private func repairMissingTextStorageIfNeeded(for item: ClipboardItem, with text: String) {
        guard item.kind == .text,
              let payload = item.textPayload,
              payload.rawText == nil,
              persistence.textContent(for: item) == nil,
              let repairedPayload = try? persistence.storeTextPayload(text, itemID: item.id) else {
            return
        }

        var repairedItem = item
        repairedItem.textPayload = repairedPayload
        appState.replaceItem(itemID: item.id, with: repairedItem)
    }

    private func hasUnavailableStoredText(_ item: ClipboardItem) -> Bool {
        guard item.kind == .text else { return false }

        if item.availabilityIssue == .sourceUnavailable {
            return true
        }

        guard let payload = item.textPayload else { return false }
        if let rawText = payload.rawText,
           !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if persistence.textContent(for: item) != nil {
            return false
        }
        if matchingCurrentPasteboardText(for: item) != nil {
            return false
        }
        return payload.assetRelativePath != nil
    }

    private func hasUnavailablePassthroughText(_ item: ClipboardItem) -> Bool {
        guard item.kind == .passthroughText else { return false }

        if item.isAbandonedPassthroughText || item.isDiscardedPassthroughText {
            return true
        }

        if item.isClipboardOnlyPassthroughText {
            return false
        }

        if item.availabilityIssue == .sourceUnavailable {
            return true
        }

        if item.passthroughTextCacheToken != nil {
            return false
        }

        return !item.isPassthroughTextValid(currentChangeCount: NSPasteboard.general.changeCount)
    }

    private func markItemAvailabilityIssue(
        for itemID: ClipboardItem.ID,
        issue: ClipboardItem.AvailabilityIssue
    ) {
        guard let item = appState.item(withID: itemID),
              item.availabilityIssue != issue else {
            return
        }

        appState.updateItem(itemID: itemID) { updatedItem in
            updatedItem.availabilityIssue = issue
        }
    }

    private func clearItemAvailabilityIssue(for itemID: ClipboardItem.ID) {
        guard let item = appState.item(withID: itemID),
              item.availabilityIssue != nil else {
            return
        }

        appState.updateItem(itemID: itemID) { updatedItem in
            updatedItem.availabilityIssue = nil
        }
    }

    private func openPreviewItemInFinder(_ item: FullPreviewContent.Item) {
        guard let url = item.url else {
            appState.lastErrorMessage = AppLocalization.localized("当前没有可在访达中打开的文件")
            return
        }

        let candidateURL = resolvedFinderURL(
            from: url,
            securityScopedBookmarkData: item.securityScopedBookmarkData
        )
        let didStartAccessing = candidateURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                candidateURL.stopAccessingSecurityScopedResource()
            }
        }

        let didOpen: Bool
        if item.filePresentation?.isFolder == true {
            didOpen = NSWorkspace.shared.open(candidateURL)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([candidateURL])
            didOpen = true
        }

        if didOpen {
            appState.lastErrorMessage = nil
        } else {
            appState.lastErrorMessage = AppLocalization.localized("无法在访达中打开当前文件")
        }
    }

    private func resolvedFinderURL(from url: URL, securityScopedBookmarkData: Data?) -> URL {
        var candidateURL = url.standardizedFileURL

        if let securityScopedBookmarkData {
            var isStale = false
            if let scopedURL = try? URL(
                resolvingBookmarkData: securityScopedBookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                candidateURL = scopedURL.standardizedFileURL
            }
        }

        return candidateURL
    }

    func hasUnavailableImageAsset(_ item: ClipboardItem) -> Bool {
        guard item.kind == .image,
              let relativePath = item.imageAssetRelativePath else {
            return false
        }

        if imagePreviewCache.object(forKey: relativePath as NSString) != nil {
            return false
        }

        let url = persistence.imageAssetURL(for: relativePath)
        return FileManager.default.fileExists(atPath: url.path) == false
    }

    func sourceAppIcon(for item: ClipboardItem) -> NSImage? {
        guard let bundleID = item.sourceAppBundleID else {
            return nil
        }

        return applicationIcon(forBundleID: bundleID)
    }

    func cachedSourceAppIcon(for item: ClipboardItem) -> NSImage? {
        guard let bundleID = item.sourceAppBundleID else {
            return nil
        }

        return appIconCache[bundleID]
    }

    func applicationIcon(forBundleID bundleID: String) -> NSImage? {
        if let cached = appIconCache[bundleID] {
            return cached
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 32, height: 32)
        appIconCache[bundleID] = icon
        return icon
    }

    func applicationDisplayName(forBundleID bundleID: String) -> String {
        if let cached = appDisplayNameCache[bundleID] {
            return cached
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }

        let bundle = Bundle(url: appURL)
        let resolvedName = (
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            FileManager.default.displayName(atPath: appURL.path)
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let displayName = resolvedName.isEmpty ? bundleID : resolvedName
        appDisplayNameCache[bundleID] = displayName
        return displayName
    }

    func hasUnavailableFiles(_ item: ClipboardItem) -> Bool {
        guard item.kind == .file else { return false }

        if let cached = fileAvailabilityCache[item.id] {
            return cached
        }

        let hasUnavailableFiles: Bool
        if let protectedURLs = protectedFileURLs(for: item),
           !protectedURLs.isEmpty {
            hasUnavailableFiles = protectedURLs.contains {
                FileManager.default.fileExists(atPath: $0.standardizedFileURL.path) == false
            }
        } else {
            let bookmarks = item.fileSecurityScopedBookmarks
            let urls = item.fileURLs
            guard !urls.isEmpty else { return false }

            hasUnavailableFiles = urls.enumerated().contains { index, url in
                let bookmarkData = index < bookmarks.count ? bookmarks[index] : nil
                return isFileReachable(originalURL: url, bookmarkData: bookmarkData) == false
            }
        }

        fileAvailabilityCache[item.id] = hasUnavailableFiles
        return hasUnavailableFiles
    }

    func requestAccessibilityPermission() {
        PermissionCenter.requestAccessibilityIfNeeded()
        PermissionCenter.openAccessibilitySettings()
        synchronizeAccessibilityPermissionState()
    }

    func refreshPermissionStatus() {
        synchronizeAccessibilityPermissionState()
    }

    func configureOpenSettingsWindowAction(_ action: @escaping () -> Void) {
        openSettingsWindowAction = action
    }

    func setSettingsWindowVisible(_ isVisible: Bool) {
        guard isSettingsWindowVisible != isVisible else { return }
        isSettingsWindowVisible = isVisible
        if isVisible {
            refreshPreferredColorSchemeFromSystemIfNeeded()
        }
        applyApplicationVisibilityState()
    }

    func refreshPreferredColorSchemeFromSystemIfNeeded() {
        guard appState.settings.appearanceMode == .system else { return }
        let resolvedScheme = systemColorScheme()
        updatePreferredColorSchemeIfNeeded(resolvedScheme)
    }

    func refreshMenuBarStatusItem() {
        applyMenuBarStatusItemState()
    }

    func runningAppBundlePath() -> String {
        PermissionCenter.runningAppBundlePath()
    }

    func revealRunningAppInFinder() {
        PermissionCenter.revealRunningAppInFinder()
    }

    func copyRunningAppPath() {
        PermissionCenter.copyRunningAppPath()
        clipboardMonitor.ignoreCurrentContents()
    }

    func openSettingsWindow() {
        setSettingsWindowVisible(true)
        NSApp.activate(ignoringOtherApps: true)
        openSettingsWindowAction?()
    }

    func showPanel() {
        showPanel(mode: .manual)
    }

    func activatePinnedPanelForKeyboardIfNeeded() {
        guard isPanelVisible, appState.isPanelPinned, appState.panelMode == .history else { return }
        guard !NSApp.isActive else { return }
        panelController.prepareForTextInput()
    }

    func handleMainPanelHoverChanged(_ isHovering: Bool) {
        guard isHovering else { return }
        activatePinnedPanelForKeyboardIfNeeded()
        clearPinnedPanelIdleDimmingIfNeeded()
    }

    private func reclaimPinnedPanelKeyboardFocusAfterPreviewDismissIfNeeded() {
        guard isPointerInteractingWithPinnedPanel() else { return }
        cancelPinnedPanelFocusReclaim()

        schedulePinnedPanelFocusReclaimAttempt(after: 0, remainingIntervals: [0.08])
    }

    private func schedulePinnedPanelFocusReclaimAfterAutoPasteIfNeeded() {
        guard isPointerInteractingWithPinnedPanel() else { return }
        cancelPinnedPanelFocusReclaim()
        // Auto-paste restores focus to the previous app first. On some apps that
        // activation wins briefly after Cmd+V, so a single reclaim is too early.
        schedulePinnedPanelFocusReclaimAttempt(after: 0.16, remainingIntervals: [0.18, 0.24])
    }

    private func cancelPinnedPanelFocusReclaim() {
        pinnedPanelFocusReclaimWorkItem?.cancel()
        pinnedPanelFocusReclaimWorkItem = nil
    }

    private func schedulePinnedPanelFocusReclaimAttempt(
        after delay: TimeInterval,
        remainingIntervals: [TimeInterval]
    ) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isPointerInteractingWithPinnedPanel() else { return }
            guard self.isPanelVisible, self.appState.isPanelPinned, self.appState.panelMode == .history else { return }

            self.panelController.prepareForTextInput()

            guard !self.panelController.isKeyWindow,
                  let nextDelay = remainingIntervals.first else {
                self.pinnedPanelFocusReclaimWorkItem = nil
                return
            }

            self.schedulePinnedPanelFocusReclaimAttempt(
                after: nextDelay,
                remainingIntervals: Array(remainingIntervals.dropFirst())
            )
        }

        pinnedPanelFocusReclaimWorkItem = workItem
        if delay == 0 {
            DispatchQueue.main.async(execute: workItem)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func toggleMenuBarPanel() {
        guard appState.settings.menuBarStatusItemVisible else { return }
        guard appState.settings.menuBarActivationEnabled else { return }

        if panelController.isVisible {
            if currentPanelPresentationMode == .menuBar {
                hidePanel()
                return
            }

            hidePanel()
            DispatchQueue.main.async { [weak self] in
                self?.showMenuBarPanel()
            }
            return
        }

        showMenuBarPanel()
    }

    func showPanel(
        mode: EdgePanelController.PresentationMode,
        pointer: CGPoint? = nil,
        statusItemAnchorRect: CGRect? = nil,
        preferredTab: PanelTab? = nil
    ) {
        cancelPinnedPanelFocusReclaim()

        switch mode {
        case .hotkey:
            guard appState.settings.globalHotkeyEnabled else { return }
        case .edgeTriggered:
            guard appState.settings.edgeActivationEnabled else { return }
        case .rightDrag:
            guard appState.settings.rightMouseDragActivationEnabled else { return }
        case .menuBar:
            guard appState.settings.menuBarStatusItemVisible else { return }
            guard appState.settings.menuBarActivationEnabled else { return }
        case .manual:
            break
        }

        focusTracker.captureCurrentFrontmostApp()

        if mode == .manual {
            NSApp.activate(ignoringOtherApps: true)
        }

        edgeActivationPreviewController.hide()

        if panelController.isVisible {
            if mode == .edgeTriggered {
                return
            }

            if preferredTab == .favorites {
                appState.activeTab = .favorites
                appState.activeFavoriteGroupID = nil
                appState.isPanelTabHoverUnlocked = true
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            hidePanel()
            return
        }

        appState.resetPanelStateForPresentation()
        if let preferredTab {
            appState.activeTab = preferredTab
            if preferredTab == .favorites {
                appState.activeFavoriteGroupID = nil
            }
        }
        appState.isPanelTabHoverUnlocked = !panelRequiresTabHoverUnlock(for: mode)
        clearPreviewDismissSafetyRegion()
        panelController.show(
            mode: mode,
            appearanceMode: appState.settings.appearanceMode,
            size: compactPanelSize,
            edgeActivationSide: appState.settings.edgeActivationSide,
            edgeActivationPlacementMode: appState.settings.edgeActivationPlacementMode,
            edgeActivationCustomVerticalPosition: appState.settings.edgeActivationCustomVerticalPosition,
            pointerOverride: pointer,
            statusItemAnchorRect: statusItemAnchorRect
        ) {
            EdgePanelView(services: self)
                .environmentObject(appState)
        }
    }

    func hidePanel() {
        if appState.isFavoriteEditorPresented {
            requestFavoriteEditorTransition(context: .closePanel) {
                self.hidePanelAfterFavoriteEditorResolved()
            }
            return
        }

        hidePanelAfterFavoriteEditorResolved()
    }

    private func hidePanelAfterFavoriteEditorResolved() {
        cancelPinnedPanelFocusReclaim()
        persistActiveStackSession()
        persistHotkeyPanelFrameIfNeeded()
        if let preStackPinState = appState.preStackPinState {
            appState.isPanelPinned = preStackPinState
        }
        appState.activeStackSession = nil
        appState.panelMode = .history
        appState.isStackProcessorPresented = false
        appState.stackProcessorDraft = ""
        appState.isFavoriteEditorPresented = false
        appState.activeFavoriteSnippetID = nil
        appState.favoriteEditorDraft = ""
        appState.favoriteEditorInitialDraft = ""
        appState.preStackPinState = nil
        appState.preFavoriteEditorPinState = nil
        clearPreviewDismissSafetyRegion()
        updateStackBridgeState()
        forceHideAuxiliaryPanel()
        appState.isRightDragSelecting = false
        appState.rightDragHighlightedRowID = nil
        appState.rightDragHeaderTarget = nil
        appState.rightDragHoveredTab = nil
        rightDragLatestPointer = nil
        rightDragFrozenViewportY = nil
        panelController.hide()
        isPanelVisible = false
    }

    private func collapsePanelAfterPasteIfNeeded() {
        guard !appState.isPanelPinned else { return }
        hidePanel()
    }

    private func activateFavoriteEditorPresentation() {
        if appState.preFavoriteEditorPinState == nil {
            appState.preFavoriteEditorPinState = appState.isPanelPinned
        }
        appState.isPanelPinned = true
    }

    private func dismissFavoriteEditorIfNeeded(restorePinState: Bool, clearDraft: Bool) {
        let wasPresented = appState.isFavoriteEditorPresented
        appState.isFavoriteEditorPresented = false
        updatePanelKeyMonitoringState()

        if clearDraft {
            appState.activeFavoriteSnippetID = nil
            appState.favoriteEditorDraft = ""
            appState.favoriteEditorInitialDraft = ""
        }

        guard restorePinState else {
            if !wasPresented {
                appState.preFavoriteEditorPinState = nil
            }
            return
        }

        let restoredPinState = appState.preFavoriteEditorPinState ?? appState.isPanelPinned
        appState.isPanelPinned = restoredPinState
        appState.preFavoriteEditorPinState = nil

        if wasPresented, !restoredPinState, isPanelVisible {
            panelController.suspendAutoCollapseUntilPointerReenters()
        }
    }

    private var favoriteEditorHasUnsavedChanges: Bool {
        if appState.activeFavoriteSnippetID == nil {
            return !appState.favoriteEditorDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return appState.favoriteEditorDraft != appState.favoriteEditorInitialDraft
    }

    func resolveFavoriteEditorConfirmation(_ intent: FavoriteEditorConfirmationIntent) {
        let handler = favoriteEditorConfirmationHandler
        favoriteEditorConfirmation = nil
        favoriteEditorConfirmationHandler = nil
        handler?(intent)
    }

    private func requestFavoriteEditorTransition(
        context: FavoriteEditorTransitionContext,
        onConfirmedTransition: @escaping () -> Void
    ) {
        guard appState.isFavoriteEditorPresented else {
            onConfirmedTransition()
            return
        }

        guard favoriteEditorHasUnsavedChanges else {
            onConfirmedTransition()
            return
        }

        let canSave = canSaveFavoriteSnippetDraft
        favoriteEditorConfirmation = makeFavoriteEditorConfirmationState(
            for: context,
            canSave: canSave
        )
        favoriteEditorConfirmationHandler = { [weak self] intent in
            guard let self else { return }

            switch intent {
            case .saveAndContinue:
                if self.persistFavoriteSnippetFromEditor(shouldCloseEditor: false) {
                    onConfirmedTransition()
                }
            case .discardAndContinue:
                onConfirmedTransition()
            case .keepEditingCurrent:
                break
            }
        }
    }

    private func makeFavoriteEditorConfirmationState(
        for context: FavoriteEditorTransitionContext,
        canSave: Bool
    ) -> FavoriteEditorConfirmationState {
        let closeTarget = context == .closePanel ? AppLocalization.localized("面板") : AppLocalization.localized("编辑器")
        let isCreatingNewFavorite = appState.activeFavoriteSnippetID == nil

        let pendingTitle = AppLocalization.localized(isCreatingNewFavorite ? "这条新收藏还没处理" : "当前修改还没处理")
        let pendingContextText: String
        switch context {
        case .closeEditor, .closePanel:
            if AppLocalization.isEnglish {
                pendingContextText = isCreatingNewFavorite
                    ? "Choose what to do with this new favorite before closing the \(closeTarget.lowercased())."
                    : "Choose what to do with your changes before closing the \(closeTarget.lowercased())."
            } else {
                pendingContextText = isCreatingNewFavorite
                    ? "关闭\(closeTarget)前，先决定这条新收藏怎么处理。"
                    : "关闭\(closeTarget)前，先决定这次修改怎么处理。"
            }
        case .createNext:
            pendingContextText = AppLocalization.localized(
                isCreatingNewFavorite
                    ? "新建下一条前，先决定当前这条新内容怎么处理。"
                    : "新建下一条前，先决定当前修改怎么处理。"
            )
        case .editNext:
            pendingContextText = AppLocalization.localized(
                isCreatingNewFavorite
                    ? "修改下一条前，先决定当前这条新内容怎么处理。"
                    : "修改下一条前，先决定当前修改怎么处理。"
            )
        }

        let discardActionTitle: String
        switch context {
        case .closeEditor, .closePanel:
            if AppLocalization.isEnglish {
                discardActionTitle = isCreatingNewFavorite
                    ? "Discard and close \(closeTarget)"
                    : "Discard changes and close \(closeTarget)"
            } else {
                discardActionTitle = isCreatingNewFavorite
                    ? "不保存这条并关闭\(closeTarget)"
                    : "放弃修改并关闭\(closeTarget)"
            }
        case .createNext:
            discardActionTitle = AppLocalization.localized(
                isCreatingNewFavorite
                    ? "不保存这条并新建下一条"
                    : "放弃修改并新建下一条"
            )
        case .editNext:
            discardActionTitle = AppLocalization.localized(
                isCreatingNewFavorite
                    ? "不保存这条并修改下一条"
                    : "放弃修改并修改下一条"
            )
        }

        if canSave {
            switch context {
            case .closeEditor, .closePanel:
                return FavoriteEditorConfirmationState(
                    title: pendingTitle,
                    message: pendingContextText,
                    buttons: [
                        .init(
                            intent: .saveAndContinue,
                            title: AppLocalization.isEnglish ? "Save and close \(closeTarget)" : "保存并关闭\(closeTarget)",
                            style: .accent
                        ),
                        .init(intent: .discardAndContinue, title: discardActionTitle, style: .destructive),
                        .init(intent: .keepEditingCurrent, title: AppLocalization.localized("继续编辑本条内容"), style: .secondary)
                    ]
                )
            case .createNext:
                return FavoriteEditorConfirmationState(
                    title: pendingTitle,
                    message: pendingContextText,
                    buttons: [
                        .init(intent: .saveAndContinue, title: AppLocalization.localized("保存并新建下一条"), style: .accent),
                        .init(intent: .discardAndContinue, title: discardActionTitle, style: .destructive),
                        .init(intent: .keepEditingCurrent, title: AppLocalization.localized("继续编辑本条内容"), style: .secondary)
                    ]
                )
            case .editNext:
                return FavoriteEditorConfirmationState(
                    title: pendingTitle,
                    message: pendingContextText,
                    buttons: [
                        .init(intent: .saveAndContinue, title: AppLocalization.localized("保存并修改下一条"), style: .accent),
                        .init(intent: .discardAndContinue, title: discardActionTitle, style: .destructive),
                        .init(intent: .keepEditingCurrent, title: AppLocalization.localized("继续编辑本条内容"), style: .secondary)
                    ]
                )
            }
        }

        let blankTitle = AppLocalization.localized(isCreatingNewFavorite ? "这条新收藏还是空的" : "当前修改已经清空")
        let blankMessage: String
        switch context {
        case .closeEditor, .closePanel:
            if AppLocalization.isEnglish {
                blankMessage = isCreatingNewFavorite
                    ? "Blank content will not be saved. Close the \(closeTarget.lowercased()) now?"
                    : "Blank content will not replace the original favorite. Discard your changes and close the \(closeTarget.lowercased())?"
            } else {
                blankMessage = isCreatingNewFavorite
                    ? "空白内容不会保存。要直接关闭\(closeTarget)吗？"
                    : "空白内容不会覆盖原收藏。要放弃这次修改并关闭\(closeTarget)吗？"
            }
        case .createNext:
            blankMessage = AppLocalization.localized(
                isCreatingNewFavorite
                    ? "空白内容不会保存。要直接新建下一条吗？"
                    : "空白内容不会覆盖原收藏。要放弃修改并新建下一条吗？"
            )
        case .editNext:
            blankMessage = AppLocalization.localized(
                isCreatingNewFavorite
                    ? "空白内容不会保存。要直接修改下一条吗？"
                    : "空白内容不会覆盖原收藏。要放弃修改并修改下一条吗？"
            )
        }

        switch context {
        case .closeEditor, .closePanel:
            return FavoriteEditorConfirmationState(
                title: blankTitle,
                message: blankMessage,
                buttons: [
                    .init(intent: .discardAndContinue, title: discardActionTitle, style: .destructive),
                    .init(intent: .keepEditingCurrent, title: AppLocalization.localized("继续编辑本条内容"), style: .secondary)
                ]
            )
        case .createNext:
            return FavoriteEditorConfirmationState(
                title: blankTitle,
                message: blankMessage,
                buttons: [
                    .init(intent: .discardAndContinue, title: discardActionTitle, style: .destructive),
                    .init(intent: .keepEditingCurrent, title: AppLocalization.localized("继续编辑本条内容"), style: .secondary)
                ]
            )
        case .editNext:
            return FavoriteEditorConfirmationState(
                title: blankTitle,
                message: blankMessage,
                buttons: [
                    .init(intent: .discardAndContinue, title: discardActionTitle, style: .destructive),
                    .init(intent: .keepEditingCurrent, title: AppLocalization.localized("继续编辑本条内容"), style: .secondary)
                ]
            )
        }
    }

    func previewEdgeActivationCustomPosition(_ position: Double) {
        guard let screen = edgeActivationPreviewScreen() else { return }
        let layout = edgeActivationLayout(
            on: screen,
            placementMode: .custom,
            customVerticalPosition: position
        )
        edgeActivationPreviewController.update(
            layout: layout,
            appearanceMode: appState.settings.appearanceMode
        )
    }

    func edgeActivationPreviewLayout(
        customVerticalPosition: Double? = nil
    ) -> EdgePanelController.EdgeActivationLayout? {
        guard let screen = edgeActivationPreviewScreen() else { return nil }
        return edgeActivationLayout(
            on: screen,
            placementMode: .custom,
            customVerticalPosition: customVerticalPosition
        )
    }

    func hideEdgeActivationPreview() {
        edgeActivationPreviewController.hide()
    }

    func preparePanelForTextInput() {
        panelController.prepareForTextInput()
    }

    private func showMenuBarPanel() {
        guard let statusItemAnchorRect = menuBarStatusItemController.buttonScreenFrame else { return }
        showPanel(mode: .menuBar, statusItemAnchorRect: statusItemAnchorRect)
    }

    private func panelRequiresTabHoverUnlock(
        for mode: EdgePanelController.PresentationMode
    ) -> Bool {
        mode.requiresTabHoverUnlock
    }

    private func edgeActivationPreviewScreen(referencePoint: CGPoint? = nil) -> NSScreen? {
        let point = referencePoint ?? NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
    }

    private func edgeActivationLayout(
        on screen: NSScreen,
        placementMode: EdgeActivationPlacementMode? = nil,
        customVerticalPosition: Double? = nil,
        pointer: CGPoint? = nil
    ) -> EdgePanelController.EdgeActivationLayout {
        EdgePanelController.edgeTriggeredLayout(
            on: screen,
            size: compactPanelSize,
            pointer: pointer,
            side: appState.settings.edgeActivationSide,
            placementMode: placementMode ?? appState.settings.edgeActivationPlacementMode,
            customVerticalPosition: customVerticalPosition ?? appState.settings.edgeActivationCustomVerticalPosition
        )
    }

    private func edgeActivationVerticalRange(
        on screen: NSScreen,
        pointer: CGPoint? = nil
    ) -> ClosedRange<CGFloat>? {
        edgeActivationLayout(on: screen, pointer: pointer).activationVerticalRange
    }

    func canOpenFullPreview(for item: ClipboardItem) -> Bool {
        itemSupportsFullPreview(item)
    }

    func toggleFullPreview(for item: ClipboardItem) {
        guard itemSupportsFullPreview(item) else { return }

        if isFullPreviewPresented,
           activePreviewItemID == item.id {
            hideFullPreview()
            return
        }

        presentFullPreview(for: item, showErrors: true)
    }

    private func toggleFullPreview(for snippet: FavoriteSnippet) {
        guard snippetSupportsFullPreview(snippet) else { return }

        if isFullPreviewPresented,
           fullPreviewContent?.itemID == snippet.id,
           fullPreviewContent?.kind == .text,
           fullPreviewCurrentItem?.textContent == snippet.text {
            hideFullPreview()
            return
        }

        presentFullPreview(for: snippet, showErrors: true)
    }

    private func toggleFullPreview(for target: PanelPreviewTarget) {
        switch target {
        case .historyItem(let item):
            toggleFullPreview(for: item)
        case .favoriteSnippet(let snippet):
            toggleFullPreview(for: snippet)
        }
    }

    private func presentFullPreview(for target: PanelPreviewTarget, showErrors: Bool) {
        switch target {
        case .historyItem(let item):
            presentFullPreview(for: item, showErrors: showErrors)
        case .favoriteSnippet(let snippet):
            presentFullPreview(for: snippet, showErrors: showErrors)
        }
    }

    func canContinuePreview(on item: ClipboardItem) -> Bool {
        guard shouldTrackContinuousPreviewHover else { return false }
        guard activePreviewItemID != item.id else { return false }
        return itemSupportsFullPreview(item)
    }

    func canContinuePreview(for rowID: ClipboardItem.ID) -> Bool {
        guard shouldTrackContinuousPreviewHover else { return false }
        guard let target = panelPreviewTarget(for: rowID) else { return false }

        switch target {
        case .historyItem(let item):
            return activePreviewItemID != item.id && itemSupportsFullPreview(item)
        case .favoriteSnippet(let snippet):
            guard fullPreviewContent?.itemID != snippet.id ||
                    fullPreviewCurrentItem?.textContent != snippet.text else {
                return false
            }
            return snippetSupportsFullPreview(snippet)
        }
    }

    func continuePreviewOnStableHover(itemID: ClipboardItem.ID) {
        guard shouldTrackContinuousPreviewHover else { return }
        guard appState.hoveredRowID == itemID else { return }
        guard let item = appState.item(withID: itemID), canContinuePreview(on: item) else { return }

        presentFullPreview(for: item, showErrors: false)
    }

    func continuePreviewOnStableHover(rowID: ClipboardItem.ID) {
        guard shouldTrackContinuousPreviewHover else { return }
        guard appState.hoveredRowID == rowID else { return }
        guard let target = panelPreviewTarget(for: rowID),
              previewTargetSupportsFullPreview(target) else { return }

        presentFullPreview(for: target, showErrors: false)
    }

    func hideFullPreview() {
        guard isFullPreviewPresented ||
                fullPreviewContent != nil ||
                fullPreviewUnavailableState != nil ||
                appState.isStackProcessorPresented ||
                appState.isFavoriteEditorPresented else { return }

        let shouldReactivatePinnedPanel = isPointerInteractingWithPinnedPanel()
        armPreviewDismissSafetyRegionIfNeeded()
        if shouldPreserveCurrentTextPreviewForReuse {
            preserveCurrentTextPreviewForReuse()
        } else {
            clearFullPreviewPresentationState()
        }
        updateAuxiliaryPanelPresentation()
        if shouldReactivatePinnedPanel {
            reclaimPinnedPanelKeyboardFocusAfterPreviewDismissIfNeeded()
        }
    }

    private func forceHideAuxiliaryPanel() {
        if shouldPreserveCurrentTextPreviewForReuse {
            preserveCurrentTextPreviewForReuse()
        } else {
            clearFullPreviewPresentationState()
        }
        appState.isStackProcessorPresented = false
        appState.isFavoriteEditorPresented = false
        appState.favoriteEditorInitialDraft = ""
        appState.preFavoriteEditorPinState = nil
        fullPreviewPanelController.hide()
    }

    func showPreviousFullPreviewItem() {
        guard var fullPreviewContent, fullPreviewContent.currentIndex > 0 else { return }
        fullPreviewContent.currentIndex -= 1
        self.fullPreviewContent = fullPreviewContent
        syncActivePreviewItemID()
    }

    func showNextFullPreviewItem() {
        guard let currentContent = fullPreviewContent else { return }
        guard currentContent.currentIndex < currentContent.items.count - 1 else { return }

        var updatedContent = currentContent
        updatedContent.currentIndex += 1
        fullPreviewContent = updatedContent
        syncActivePreviewItemID()
    }

    private func presentFullPreview(for item: ClipboardItem, showErrors: Bool) {
        guard appState.settings.filePreviewEnabled else { return }

        if reuseHiddenTextPreviewIfPossible(for: item) {
            return
        }

        guard let prepared = prepareFullPreviewPresentation(for: item) else {
            if showErrors {
                presentUnavailableFullPreview(for: item)
            }
            return
        }

        clearFullPreviewPresentationState()
        clearPreviewDismissSafetyRegion()
        fullPreviewStopAccess = prepared.stopAccess
        fullPreviewContent = prepared.content
        fullPreviewUnavailableState = nil
        isFullPreviewPresented = true
        appState.isStackProcessorPresented = false
        appState.isFavoriteEditorPresented = false
        syncActivePreviewItemID()
        updateAuxiliaryPanelPresentation()
    }

    private func presentFullPreview(for snippet: FavoriteSnippet, showErrors: Bool) {
        guard appState.settings.filePreviewEnabled else { return }

        let text = snippet.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            guard showErrors else { return }
            clearFullPreviewPresentationState()
            clearPreviewDismissSafetyRegion()
            fullPreviewUnavailableState = FullPreviewUnavailableState(
                itemID: snippet.id,
                kind: .text,
                message: AppLocalization.localized("这条收藏当前没有可展示的预览内容。")
            )
            isFullPreviewPresented = true
            appState.isStackProcessorPresented = false
            appState.isFavoriteEditorPresented = false
            syncActivePreviewItemID()
            updateAuxiliaryPanelPresentation()
            return
        }

        clearFullPreviewPresentationState()
        clearPreviewDismissSafetyRegion()
        fullPreviewStopAccess = nil
        fullPreviewContent = FullPreviewContent(
            itemID: snippet.id,
            kind: .text,
            items: [
                FullPreviewContent.Item(
                    id: snippet.id.uuidString,
                    url: nil,
                    displayName: snippet.title,
                    textContent: text,
                    securityScopedBookmarkData: nil,
                    filePresentation: nil
                )
            ],
            currentIndex: 0
        )
        fullPreviewUnavailableState = nil
        isFullPreviewPresented = true
        appState.isStackProcessorPresented = false
        appState.isFavoriteEditorPresented = false
        syncActivePreviewItemID()
        updateAuxiliaryPanelPresentation()
    }

    private var shouldPreserveCurrentTextPreviewForReuse: Bool {
        guard !appState.isStackProcessorPresented else { return false }
        guard fullPreviewUnavailableState == nil else { return false }
        guard let fullPreviewContent else { return false }

        switch fullPreviewContent.kind {
        case .text, .passthroughText:
            guard fullPreviewContent.items.indices.contains(fullPreviewContent.currentIndex) else { return false }
            return fullPreviewContent.items[fullPreviewContent.currentIndex].textContent?.isEmpty == false
        case .image, .file, .stack:
            return false
        }
    }

    private func preserveCurrentTextPreviewForReuse() {
        releaseFullPreviewAccessScope()
        isFullPreviewPresented = false
        fullPreviewUnavailableState = nil
        syncActivePreviewItemID()
    }

    private func reuseHiddenTextPreviewIfPossible(for item: ClipboardItem) -> Bool {
        guard !isFullPreviewPresented else { return false }
        guard fullPreviewUnavailableState == nil else { return false }
        guard let expectedText = reusableTextPreviewContent(for: item) else { return false }
        guard let fullPreviewContent else { return false }
        guard fullPreviewContent.itemID == item.id else { return false }
        guard fullPreviewContent.kind == item.kind else { return false }
        guard fullPreviewContent.items.indices.contains(fullPreviewContent.currentIndex) else { return false }
        guard fullPreviewContent.items[fullPreviewContent.currentIndex].textContent == expectedText else { return false }

        clearPreviewDismissSafetyRegion()
        releaseFullPreviewAccessScope()
        isFullPreviewPresented = true
        appState.isStackProcessorPresented = false
        syncActivePreviewItemID()
        updateAuxiliaryPanelPresentation()
        return true
    }

    private func reusableTextPreviewContent(for item: ClipboardItem) -> String? {
        switch item.kind {
        case .text:
            let text = item.textPreviewBody ?? item.preview
            return text.isEmpty ? nil : text
        case .passthroughText:
            return item.preview.isEmpty ? nil : item.preview
        case .image, .file, .stack:
            return nil
        }
    }

    private func presentUnavailableFullPreview(for item: ClipboardItem) {
        clearFullPreviewPresentationState()
        clearPreviewDismissSafetyRegion()
        fullPreviewUnavailableState = FullPreviewUnavailableState(
            itemID: item.id,
            kind: item.kind,
            message: unavailableFullPreviewMessage(for: item)
        )
        isFullPreviewPresented = true
        appState.isStackProcessorPresented = false
        syncActivePreviewItemID()
        updateAuxiliaryPanelPresentation()
    }

    private func prepareFullPreviewPresentation(for item: ClipboardItem) -> PreparedFullPreviewPresentation? {
        switch item.kind {
        case .image:
            guard let relativePath = item.imageAssetRelativePath else { return nil }
            let url = persistence.imageAssetURL(for: relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }

            return PreparedFullPreviewPresentation(
                content: FullPreviewContent(
                    itemID: item.id,
                    kind: item.kind,
                    items: [
                        FullPreviewContent.Item(
                            id: url.standardizedFileURL.path,
                            url: url,
                            displayName: imageFullPreviewDisplayName(for: item, url: url),
                            textContent: nil,
                            securityScopedBookmarkData: nil,
                            filePresentation: nil
                        )
                    ],
                    currentIndex: 0
                ),
                stopAccess: {}
            )
        case .file:
            let resolved = resolveFileURLsForTransfer(item)
            let names = item.fileDisplayNames
            let bookmarks = item.fileSecurityScopedBookmarks
            let previewItems = Array(resolved.urls.enumerated()).compactMap { offset, url -> FullPreviewContent.Item? in
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                let displayName = offset < names.count ? names[offset] : url.lastPathComponent
                let resolvedDisplayName = displayName.isEmpty ? url.lastPathComponent : displayName
                return FullPreviewContent.Item(
                    id: url.standardizedFileURL.path,
                    url: url,
                    displayName: resolvedDisplayName,
                    textContent: nil,
                    securityScopedBookmarkData: offset < bookmarks.count ? bookmarks[offset] : nil,
                    filePresentation: FilePresentationSupport.makeMetadata(
                        for: url,
                        fallbackDisplayName: resolvedDisplayName
                    )
                )
            }

            guard !previewItems.isEmpty else {
                resolved.stopAccess()
                return nil
            }

            return PreparedFullPreviewPresentation(
                content: FullPreviewContent(
                    itemID: item.id,
                    kind: item.kind,
                    items: previewItems,
                    currentIndex: 0
                ),
                stopAccess: resolved.stopAccess
            )
        case .text:
            let text = item.textPreviewBody ?? item.preview
            guard !text.isEmpty else { return nil }
            return PreparedFullPreviewPresentation(
                content: FullPreviewContent(
                    itemID: item.id,
                    kind: item.kind,
                    items: [
                        FullPreviewContent.Item(
                            id: item.id.uuidString,
                            url: nil,
                            displayName: AppLocalization.localized("文本预览"),
                            textContent: text,
                            securityScopedBookmarkData: nil,
                            filePresentation: nil
                        )
                    ],
                    currentIndex: 0
                ),
                stopAccess: {}
            )
        case .passthroughText:
            let text = item.preview
            guard !text.isEmpty else { return nil }
            return PreparedFullPreviewPresentation(
                content: FullPreviewContent(
                    itemID: item.id,
                    kind: item.kind,
                    items: [
                        FullPreviewContent.Item(
                            id: item.id.uuidString,
                            url: nil,
                            displayName: AppLocalization.localized("文本预览"),
                            textContent: text,
                            securityScopedBookmarkData: nil,
                            filePresentation: nil
                        )
                    ],
                    currentIndex: 0
                ),
                stopAccess: {}
            )
        case .stack:
            let previewItems = Array(item.stackEntries.enumerated()).compactMap { offset, entry -> FullPreviewContent.Item? in
                let text = entry.text
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }

                return FullPreviewContent.Item(
                    id: entry.id.uuidString,
                    url: nil,
                    displayName: AppLocalization.isEnglish ? "Item \(offset + 1)" : "第 \(offset + 1) 条",
                    textContent: text,
                    securityScopedBookmarkData: nil,
                    filePresentation: nil
                )
            }

            guard !previewItems.isEmpty else { return nil }

            return PreparedFullPreviewPresentation(
                content: FullPreviewContent(
                    itemID: item.id,
                    kind: item.kind,
                    items: previewItems,
                    currentIndex: 0
                ),
                stopAccess: {}
            )
        }
    }

    private func itemSupportsFullPreview(_ item: ClipboardItem) -> Bool {
        guard appState.settings.filePreviewEnabled else { return false }

        switch item.kind {
        case .image:
            return item.imageAssetRelativePath != nil
        case .file:
            return !item.fileURLs.isEmpty
        case .text:
            return item.textPreviewBody?.isEmpty == false || item.preview.isEmpty == false
        case .passthroughText:
            return !item.preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stack:
            return item.stackEntries.contains {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private func unavailableFullPreviewMessage(for item: ClipboardItem) -> String {
        switch item.kind {
        case .image:
            return AppLocalization.localized("图片资源可能已经失效，或本地预览文件已被删除。")
        case .file:
            return AppLocalization.localized("文件可能已经失效，或系统当前无法为它生成 Quick Look 预览。")
        case .text:
            return AppLocalization.localized("这条文本当前没有可展示的预览内容。")
        case .passthroughText:
            return AppLocalization.localized("由于文本过长，当前仅显示部分内容作为预览，文本可以正常粘贴。")
        case .stack:
            return AppLocalization.localized("当前堆栈为空，暂无可预览的条目。")
        }
    }

    private func clearFullPreviewPresentationState() {
        releaseFullPreviewAccessScope()
        isFullPreviewPresented = false
        fullPreviewContent = nil
        fullPreviewUnavailableState = nil
        syncActivePreviewItemID()
    }

    private func releaseFullPreviewAccessScope() {
        fullPreviewStopAccess?()
        fullPreviewStopAccess = nil
    }

    private func syncActivePreviewItemID() {
        guard isFullPreviewPresented else {
            activePreviewItemID = nil
            return
        }
        activePreviewItemID = fullPreviewContent?.itemID ?? fullPreviewUnavailableState?.itemID
    }

    private func handleAuxiliaryPanelDidClose() {
        let shouldReactivatePinnedPanel = isPointerInteractingWithPinnedPanel()
        if let preFavoriteEditorPinState = appState.preFavoriteEditorPinState {
            appState.isPanelPinned = preFavoriteEditorPinState
        }
        clearFullPreviewPresentationState()
        appState.isStackProcessorPresented = false
        appState.isFavoriteEditorPresented = false
        appState.favoriteEditorInitialDraft = ""
        appState.preFavoriteEditorPinState = nil
        if shouldReactivatePinnedPanel {
            reclaimPinnedPanelKeyboardFocusAfterPreviewDismissIfNeeded()
        }
    }

    private func fullPreviewPanelSize(for item: ClipboardItem, anchoredTo anchorFrame: NSRect) -> NSSize {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(anchorFrame) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let alignedPanelHeight = min(
            max(360, anchorFrame.height),
            max(360, visibleFrame.height - 24)
        )

        switch item.kind {
        case .image:
            guard let payload = item.imagePayload,
                  payload.pixelWidth > 0,
                  payload.pixelHeight > 0 else {
                return NSSize(width: min(visibleFrame.width - 40, 600), height: alignedPanelHeight)
            }

            let previewContentHeight = max(220, alignedPanelHeight - 108)
            let fittedWidth = CGFloat(payload.pixelWidth) * previewContentHeight / CGFloat(payload.pixelHeight)
            let width: CGFloat
            let fitStandardWidth = min(
                min(visibleFrame.width * 0.46, 760),
                max(420, fittedWidth + 32)
            )
            let fitExpandedWidth = min(
                min(visibleFrame.width * 0.52, 860),
                max(520, fittedWidth * 1.22 + 48)
            )
            let fitWidthStandardWidth = min(
                min(visibleFrame.width * 0.54, 880),
                max(540, fittedWidth * 1.42 + 40)
            )
            let fitWidthExpandedWidth = min(
                min(visibleFrame.width * 0.60, 960),
                max(640, fittedWidth * 1.75 + 32)
            )

            switch appState.imagePreviewLayoutMode {
            case .fit:
                width = appState.imagePreviewWidthTier == .expanded
                    ? max(fitStandardWidth, fitExpandedWidth)
                    : fitStandardWidth
            case .fitWidth:
                width = appState.imagePreviewWidthTier == .expanded
                    ? max(fitWidthStandardWidth, fitWidthExpandedWidth)
                    : max(fitStandardWidth, fitWidthStandardWidth)
            }
            return NSSize(width: width, height: alignedPanelHeight)
        case .file:
            let width = min(max(460, visibleFrame.width * 0.34), 640)
            let height = alignedPanelHeight
            return NSSize(width: width, height: height)
        case .text:
            return estimatedTextPreviewSize(
                for: item.textPreviewBody ?? item.preview,
                visibleFrame: visibleFrame,
                minimumHeight: alignedPanelHeight
            )
        case .passthroughText:
            return estimatedTextPreviewSize(
                for: item.preview,
                visibleFrame: visibleFrame,
                minimumHeight: alignedPanelHeight
            )
        case .stack:
            let previewText = stackPreviewDisplayText(for: item.stackEntries)
            return estimatedTextPreviewSize(
                for: previewText,
                visibleFrame: visibleFrame,
                minimumHeight: alignedPanelHeight
            )
        }
    }

    private func fullPreviewPanelSize(for content: FullPreviewContent, anchoredTo anchorFrame: NSRect) -> NSSize {
        if let item = appState.item(withID: content.itemID) {
            return fullPreviewPanelSize(for: item, anchoredTo: anchorFrame)
        }

        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(anchorFrame) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let alignedPanelHeight = min(
            max(360, anchorFrame.height),
            max(360, visibleFrame.height - 24)
        )

        switch content.kind {
        case .text, .passthroughText:
            let previewText: String
            if content.items.indices.contains(content.currentIndex) {
                previewText = content.items[content.currentIndex].textContent ?? ""
            } else {
                previewText = content.items.first?.textContent ?? ""
            }
            return estimatedTextPreviewSize(
                for: previewText,
                visibleFrame: visibleFrame,
                minimumHeight: alignedPanelHeight
            )
        case .stack:
            let previewText = stackPreviewDisplayText(for: content.items.compactMap(\.textContent))
            return estimatedTextPreviewSize(
                for: previewText,
                visibleFrame: visibleFrame,
                minimumHeight: alignedPanelHeight
            )
        case .image:
            return NSSize(width: min(visibleFrame.width - 40, 600), height: alignedPanelHeight)
        case .file:
            return NSSize(width: min(max(460, visibleFrame.width * 0.34), 640), height: alignedPanelHeight)
        }
    }

    private func stackPreviewDisplayText(for entries: [ClipboardItem.StackEntry]) -> String {
        stackPreviewDisplayText(for: entries.map(\.text))
    }

    private func stackPreviewDisplayText(for texts: [String]) -> String {
        let meaningful = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !meaningful.isEmpty else { return AppLocalization.localized("空堆栈") }
        return meaningful.joined(separator: "\n\n────────\n\n")
    }

    private func stackProcessorPanelSize(anchoredTo anchorFrame: NSRect) -> NSSize {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(anchorFrame) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let height = min(max(420, anchorFrame.height), max(420, visibleFrame.height - 24))
        let width = min(max(400, anchorFrame.width - 16), 430)
        return NSSize(width: width, height: height)
    }

    private func favoriteEditorPanelSize(anchoredTo anchorFrame: NSRect) -> NSSize {
        stackProcessorPanelSize(anchoredTo: anchorFrame)
    }

    private func updateAuxiliaryPanelPresentation() {
        let shouldPresentProcessor = appState.isStackProcessorPresented
        let shouldPresentFavoriteEditor = appState.isFavoriteEditorPresented
        let shouldPresentPreview = isFullPreviewPresented && (fullPreviewContent != nil || fullPreviewUnavailableState != nil)

        if shouldPresentProcessor || shouldPresentFavoriteEditor || shouldPresentPreview {
            clearPinnedPanelIdleDimmingIfNeeded()
        }

        guard shouldPresentProcessor || shouldPresentFavoriteEditor || shouldPresentPreview else {
            fullPreviewPanelController.hide()
            return
        }

        let anchorFrame = panelController.previewAnchorFrame ?? panelController.frame ?? NSScreen.main?.visibleFrame ?? .zero
        let preferredSize: NSSize
        if shouldPresentProcessor {
            preferredSize = stackProcessorPanelSize(anchoredTo: anchorFrame)
        } else if shouldPresentFavoriteEditor {
            preferredSize = favoriteEditorPanelSize(anchoredTo: anchorFrame)
        } else if let content = fullPreviewContent {
            preferredSize = fullPreviewPanelSize(for: content, anchoredTo: anchorFrame)
        } else if let previewItemID = activePreviewItemID,
                  let item = appState.item(withID: previewItemID) {
            preferredSize = fullPreviewPanelSize(for: item, anchoredTo: anchorFrame)
        } else {
            preferredSize = stackProcessorPanelSize(anchoredTo: anchorFrame)
        }

        fullPreviewPanelController.show(
            anchoredTo: anchorFrame,
            appearanceMode: appState.settings.appearanceMode,
            initialSize: preferredSize
        ) {
            ClipboardFullPreviewPanelView(services: self, appState: appState) {
                self.closeAuxiliaryPanel()
            }
        }
    }

    private func updateAuxiliaryPanelPositionIfNeeded() {
        let shouldPresentProcessor = appState.isStackProcessorPresented
        let shouldPresentFavoriteEditor = appState.isFavoriteEditorPresented
        let shouldPresentPreview = isFullPreviewPresented && (fullPreviewContent != nil || fullPreviewUnavailableState != nil)
        guard shouldPresentProcessor || shouldPresentFavoriteEditor || shouldPresentPreview else { return }

        let anchorFrame = panelController.previewAnchorFrame ?? panelController.frame ?? NSScreen.main?.visibleFrame ?? .zero
        let preferredSize: NSSize
        if shouldPresentProcessor {
            preferredSize = stackProcessorPanelSize(anchoredTo: anchorFrame)
        } else if shouldPresentFavoriteEditor {
            preferredSize = favoriteEditorPanelSize(anchoredTo: anchorFrame)
        } else if let content = fullPreviewContent {
            preferredSize = fullPreviewPanelSize(for: content, anchoredTo: anchorFrame)
        } else if let previewItemID = activePreviewItemID,
                  let item = appState.item(withID: previewItemID) {
            preferredSize = fullPreviewPanelSize(for: item, anchoredTo: anchorFrame)
        } else {
            preferredSize = stackProcessorPanelSize(anchoredTo: anchorFrame)
        }

        fullPreviewPanelController.updatePosition(
            anchoredTo: anchorFrame,
            size: preferredSize
        )
    }

    private func handlePanelFrameChanged() {
        if panelController.currentMode == .hotkey,
           let origin = panelController.frame?.origin {
            panelController.updateHotkeyPlacement(
                mode: appState.settings.hotkeyPanelPlacementMode,
                lastFrameOrigin: origin
            )
        }
        updateAuxiliaryPanelPositionIfNeeded()
    }

    private func persistHotkeyPanelFrameIfNeeded() {
        guard panelController.currentMode == .hotkey,
              let origin = panelController.frame?.origin else {
            return
        }

        let persistedOrigin = PersistedPanelOrigin(origin)
        guard appState.settings.hotkeyPanelLastFrameOrigin != persistedOrigin else {
            return
        }

        appState.updateSettings { settings in
            settings.hotkeyPanelLastFrameOrigin = persistedOrigin
        }
    }

    private func estimatedTextPreviewSize(
        for text: String,
        visibleFrame: NSRect,
        minimumHeight: CGFloat
    ) -> NSSize {
        let normalized = text.isEmpty ? " " : text
        let candidateWidths: [CGFloat] = [420, 480, 560, 640]
        let maximumHeight = min(visibleFrame.height * 0.72, 720)
        let font = NSFont.systemFont(ofSize: 15)
        let textInsets = CGSize(width: 84, height: 170)

        if normalized.count > largeTextPreviewMeasurementThreshold {
            return NSSize(
                width: min(max(520, visibleFrame.width * 0.42), 640),
                height: max(minimumHeight, maximumHeight)
            )
        }

        for candidateWidth in candidateWidths {
            let width = min(candidateWidth, max(420, visibleFrame.width * 0.42))
            let textBoundingWidth = max(280, width - textInsets.width)
            let measuredHeight = ceil(
                (normalized as NSString).boundingRect(
                    with: CGSize(width: textBoundingWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font]
                ).height
            )
            let panelHeight = max(minimumHeight, min(maximumHeight, measuredHeight + textInsets.height))
            if measuredHeight + textInsets.height <= maximumHeight {
                return NSSize(width: width, height: panelHeight)
            }
        }

        return NSSize(
            width: min(max(480, visibleFrame.width * 0.42), 640),
            height: max(minimumHeight, maximumHeight)
        )
    }

    private func parsedStackProcessorSegments() -> [String] {
        stackService.splitDraft(
            appState.stackProcessorDraft,
            delimiters: appState.stackDelimiterOptions,
            customDelimiter: appState.stackCustomDelimiter
        )
    }

    private func currentStackHistoryItem() -> ClipboardItem? {
        if let dormantStackItemID = appState.dormantStackItemID,
           let item = appState.item(withID: dormantStackItemID),
           item.kind == .stack {
            return item
        }

        return appState.history.first { $0.kind == .stack }
    }

    private func persistActiveStackSession() {
        guard let session = appState.activeStackSession else { return }
        let existingItemID = session.historyItemID ?? currentStackHistoryItem()?.id
        let existingItem = existingItemID.flatMap { appState.item(withID: $0) }

        guard !session.entries.isEmpty else {
            if let existingItemID {
                appState.remove(itemID: existingItemID)
            }
            appState.dormantStackItemID = nil
            return
        }

        let now = Date()
        let payload = ClipboardItem.StackPayload(
            entries: session.entries,
            orderMode: session.orderMode,
            updatedAt: now
        )

        if let existingItemID {
            appState.replaceItem(
                itemID: existingItemID,
                with: ClipboardItem(
                    id: existingItemID,
                    createdAt: now,
                    stackPayload: payload,
                    isFavorite: existingItem?.isFavorite ?? false,
                    sourceAppBundleID: existingItem?.sourceAppBundleID,
                    sourceAppName: existingItem?.sourceAppName
                )
            )
            appState.updateActiveStackSession { session in
                session.historyItemID = existingItemID
                session.updatedAt = now
            }
            appState.dormantStackItemID = existingItemID
            return
        }

        let newItem = ClipboardItem(createdAt: now, stackPayload: payload)
        appState.ingest(newItem)
        appState.updateActiveStackSession { session in
            session.historyItemID = newItem.id
            session.updatedAt = now
        }
        appState.dormantStackItemID = newItem.id
    }

    private func updateStackBridgeState() {
        let shouldEnableBridge = isPanelVisible && appState.panelMode == .stack
        guard shouldEnableBridge else {
            stackService.updateBridgeActive(false)
            return
        }

        guard PermissionCenter.isAccessibilityGranted() else {
            stackService.updateBridgeActive(false)
            showTransientNotice(AppLocalization.localized("堆栈已开启，但当前没有辅助功能权限，Cmd+C / Cmd+V 接管不可用。"), tone: .warning)
            return
        }

        guard stackService.updateBridgeActive(true) else {
            showTransientNotice(AppLocalization.localized("堆栈热键接管启用失败，请确认辅助功能权限可用。"), tone: .warning)
            return
        }
    }

    private func updatePanelPreviewHotkeyBridgeState() {
        let shouldEnableBridge = isPanelVisible && appState.isPanelPinned && appState.panelMode == .history
        guard shouldEnableBridge else {
            panelPreviewHotkeyBridgeService.updateBridgeActive(false)
            return
        }

        guard PermissionCenter.isAccessibilityGranted() else {
            panelPreviewHotkeyBridgeService.updateBridgeActive(false)
            return
        }

        panelPreviewHotkeyBridgeService.updateBridgeActive(true)
    }

    private func shouldBypassStackHotkeys() -> Bool {
        guard appState.panelMode == .stack, isPanelVisible else { return true }
        guard let firstResponder = NSApp.keyWindow?.firstResponder else { return false }
        return firstResponder is NSTextView || firstResponder is NSTextField
    }

    private func shouldBypassPinnedPanelPreviewHotkeys() -> Bool {
        guard isPanelVisible, appState.isPanelPinned, appState.panelMode == .history else {
            return true
        }

        guard !NSApp.isActive else {
            return true
        }

        guard isPointerInteractingWithPinnedPanel() else {
            return true
        }

        if isFullPreviewPresented {
            return false
        }

        return historyItemUnderPointer() == nil
    }

    private func isPointerInteractingWithPinnedPanel(_ point: CGPoint = NSEvent.mouseLocation) -> Bool {
        guard isPanelVisible, appState.isPanelPinned, appState.panelMode == .history else {
            return false
        }

        return panelController.contains(point: point) ||
            isPointInPanelExtendedInteractionRegion(point)
    }

    private func handlePinnedPanelPreviewHotkey(_ action: PanelPreviewHotkeyBridgeService.Action) -> Bool {
        switch action {
        case .togglePreview:
            if isFullPreviewPresented {
                hideFullPreview()
                return true
            }

            guard let target = currentPanelPreviewTarget() else {
                return false
            }

            guard appState.settings.filePreviewEnabled else { return true }
            guard previewTargetSupportsFullPreview(target) else {
                return false
            }

            toggleFullPreview(for: target)
            return true

        case .closePreview:
            guard isFullPreviewPresented else { return false }
            hideFullPreview()
            return true

        case .showPrevious:
            guard isFullPreviewPresented, fullPreviewSupportsItemNavigation else { return false }
            showPreviousFullPreviewItem()
            return true

        case .showNext:
            guard isFullPreviewPresented, fullPreviewSupportsItemNavigation else { return false }
            showNextFullPreviewItem()
            return true
        }
    }

    private func captureCopiedTextIntoStack(baselineChangeCount: Int) {
        guard appState.panelMode == .stack, isPanelVisible else { return }

        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != baselineChangeCount else { return }
        guard let text = pasteboard.string(forType: .string),
              let normalizedText = stackService.normalizeStackText(text) else {
            clipboardMonitor.ignoreCurrentContents()
            return
        }

        appState.updateActiveStackSession { session in
            session.entries = stackService.prependManualEntry(
                normalizedText,
                to: session.entries,
                orderMode: session.orderMode
            )
        }
        persistActiveStackSession()
        ingestCapturedText(
            ClipboardMonitor.TextCapturePayload(text: normalizedText, requestID: nil),
            sourceAppBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            sourceAppName: NSWorkspace.shared.frontmostApplication?.localizedName
        )
        clipboardMonitor.ignoreCurrentContents()
        appState.lastErrorMessage = nil
    }

    private func prepareNextStackPaste() -> Bool {
        guard appState.panelMode == .stack, isPanelVisible else { return false }
        guard let nextEntry = activeStackEntries.first else {
            showTransientNotice(AppLocalization.localized("堆栈已空。"), tone: .info)
            return false
        }

        switch pasteCoordinator.writeTextToPasteboard(nextEntry.text) {
        case .success:
            appState.updateActiveStackSession { session in
                if !session.entries.isEmpty {
                    session.entries.removeFirst()
                }
            }
            clipboardMonitor.ignoreCurrentContents()
            persistActiveStackSession()
            appState.lastErrorMessage = nil
            return true
        case let .failed(message):
            appState.lastErrorMessage = message
            return false
        }
    }

    private func isPointInPanelExtendedInteractionRegion(_ point: CGPoint) -> Bool {
        if menuBarStatusItemController.contains(point: point) {
            return true
        }

        if isPointInPreviewDismissSafetyRegion(point) {
            return true
        }

        if fullPreviewPanelController.contains(point: point) {
            return true
        }

        guard let panelFrame = panelController.frame,
              let previewFrame = fullPreviewPanelController.frame else {
            return false
        }

        return previewBridgeRect(panelFrame: panelFrame, previewFrame: previewFrame)?.contains(point) ?? false
    }

    private func armPreviewDismissSafetyRegionIfNeeded() {
        guard isPanelVisible, !appState.isPanelPinned,
              let previewFrame = fullPreviewPanelController.frame,
              let panelFrame = panelController.frame else {
            clearPreviewDismissSafetyRegion()
            return
        }

        let pointer = NSEvent.mouseLocation
        let expandedPreviewFrame = previewFrame.insetBy(dx: -22, dy: -22)
        let bridgeFrame = previewBridgeRect(panelFrame: panelFrame, previewFrame: previewFrame)?
            .insetBy(dx: 0, dy: -18)
        let safetyFrames = [expandedPreviewFrame, bridgeFrame].compactMap { $0 }

        guard safetyFrames.contains(where: { $0.contains(pointer) }) else {
            clearPreviewDismissSafetyRegion()
            return
        }

        previewDismissSafetyFrames = safetyFrames
    }

    private func isPointInPreviewDismissSafetyRegion(_ point: CGPoint) -> Bool {
        guard !previewDismissSafetyFrames.isEmpty else { return false }
        if previewDismissSafetyFrames.contains(where: { $0.contains(point) }) {
            return true
        }
        clearPreviewDismissSafetyRegion()
        return false
    }

    private func clearPreviewDismissSafetyRegion() {
        previewDismissSafetyFrames.removeAll()
    }

    private func previewBridgeRect(panelFrame: NSRect, previewFrame: NSRect) -> NSRect? {
        let leftFrame: NSRect
        let rightFrame: NSRect

        if previewFrame.midX < panelFrame.midX {
            leftFrame = previewFrame
            rightFrame = panelFrame
        } else {
            leftFrame = panelFrame
            rightFrame = previewFrame
        }

        let bridgeMinX = leftFrame.maxX
        let bridgeMaxX = rightFrame.minX
        guard bridgeMaxX >= bridgeMinX else { return nil }

        let minY = min(panelFrame.minY, previewFrame.minY) - 18
        let maxY = max(panelFrame.maxY, previewFrame.maxY) + 18

        return NSRect(
            x: bridgeMinX,
            y: minY,
            width: max(bridgeMaxX - bridgeMinX, 1),
            height: max(maxY - minY, 1)
        )
    }

    private func imageFullPreviewDisplayName(for item: ClipboardItem, url: URL) -> String {
        let ext = url.pathExtension.uppercased()
        if ext.isEmpty {
            return item.imageMetadataSummary
        }
        return "\(item.imageMetadataSummary) · \(ext)"
    }

    private func migrateLegacyTextFavoritesIfNeeded() {
        let existingSourceFingerprints = Set(appState.favoriteSnippets.compactMap(\.sourceTextFingerprint))
        var addedFingerprints = existingSourceFingerprints
        var snippetsToAdd: [FavoriteSnippet] = []
        var migratedItemIDs: [ClipboardItem.ID] = []

        for item in appState.history where item.isFavorite {
            guard item.kind == .text,
                  let text = resolvedTextContent(for: item) ?? item.textContent,
                  let sourceFingerprint = item.textPayload?.contentFingerprint else {
                continue
            }

            if !addedFingerprints.contains(sourceFingerprint) {
                snippetsToAdd.append(
                    FavoriteSnippet(
                        text: text,
                        sourceTextFingerprint: sourceFingerprint
                    )
                )
                addedFingerprints.insert(sourceFingerprint)
            }
            migratedItemIDs.append(item.id)
        }

        guard !snippetsToAdd.isEmpty || !migratedItemIDs.isEmpty else { return }

        for snippet in snippetsToAdd {
            appState.addFavoriteSnippet(snippet)
        }

        for itemID in migratedItemIDs {
            appState.updateItem(itemID: itemID) { item in
                item.isFavorite = false
                item.favoriteSortOrder = nil
            }
        }
    }

    private func observePersistence() {
        guard cancellables.isEmpty else { return }

        appState.$history
            .dropFirst()
            .sink { [weak self] items in
                guard let self else { return }
                if !self.isDataStorageMigrationInProgress {
                    self.persistence.save(items)
                }
                self.appState.dormantStackItemID = self.currentStackHistoryItem()?.id
                self.applyMenuBarStatusItemState()
            }
            .store(in: &cancellables)

        appState.$favoriteSnippets
            .dropFirst()
            .sink { [weak self] snippets in
                guard let self else { return }
                guard !self.isDataStorageMigrationInProgress else { return }
                self.favoriteSnippetPersistence.save(snippets)
            }
            .store(in: &cancellables)

        appState.$favoriteGroups
            .dropFirst()
            .sink { [weak self] groups in
                guard let self else { return }
                guard !self.isDataStorageMigrationInProgress else { return }
                self.favoriteGroupPersistence.save(groups)
            }
            .store(in: &cancellables)

        appState.$isPanelPinned
            .dropFirst()
            .sink { [weak self] _ in
                self?.clearPinnedPanelIdleDimmingIfNeeded()
                self?.updatePanelPreviewHotkeyBridgeState()
            }
            .store(in: &cancellables)

        appState.$panelMode
            .dropFirst()
            .sink { [weak self] _ in
                self?.updatePanelPreviewHotkeyBridgeState()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            appState.$imagePreviewLayoutMode,
            appState.$imagePreviewWidthTier
        )
            .dropFirst()
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updateAuxiliaryPanelPositionIfNeeded()
                }
            }
            .store(in: &cancellables)

        appState.$settings
            .dropFirst()
            .sink { [weak self] settings in
                guard let self else { return }
                self.settingsPersistence.save(settings)
                if !settings.filePreviewEnabled && self.isFullPreviewPresented {
                    self.hideFullPreview()
                }
                self.appState.applyHistoryPolicies()
                self.scheduleInteractionSettingsApply()
                self.applyLaunchAtLoginSetting()
                self.panelController.updateAppearance(mode: settings.appearanceMode)
                self.panelController.updateEdgeActivationPlacement(
                    side: settings.edgeActivationSide,
                    mode: settings.edgeActivationPlacementMode,
                    customVerticalPosition: settings.edgeActivationCustomVerticalPosition
                )
                self.panelController.updateHotkeyPlacement(
                    mode: settings.hotkeyPanelPlacementMode,
                    lastFrameOrigin: settings.hotkeyPanelLastFrameOrigin?.cgPoint
                )
                self.panelController.updateEdgeAutoCollapseDistance(settings.edgePanelAutoCollapseDistance)
                self.panelController.updatePinnedIdleTransparencyPercent(settings.pinnedPanelIdleTransparencyPercent)
                self.fullPreviewPanelController.updateAppearance(mode: settings.appearanceMode)
                self.updatePreferredColorSchemeIfNeeded(self.colorScheme(for: settings.appearanceMode))
                self.applyApplicationVisibilityState()
                self.applyMenuBarStatusItemState()
                self.updatePanelPreviewHotkeyBridgeState()
            }
            .store(in: &cancellables)
    }

    private func scheduleInteractionSettingsApply() {
        interactionSettingsApplyWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.applyEdgeServiceSettings()
            self.applyGlobalHotkeySetting()
            self.applyRightMouseDragGestureSetting()
        }
        interactionSettingsApplyWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func updatePreferredColorSchemeIfNeeded(_ newScheme: ColorScheme?) {
        guard preferredColorScheme != newScheme else { return }
        preferredColorScheme = newScheme
    }

    private func applyMenuBarStatusItemState() {
        let settings = appState.settings

        if !settings.menuBarStatusItemVisible {
            if isPanelVisible && currentPanelPresentationMode == .menuBar {
                hidePanel()
            }
            menuBarStatusItemController.uninstall()
            return
        }

        if !settings.menuBarActivationEnabled {
            if isPanelVisible && currentPanelPresentationMode == .menuBar {
                hidePanel()
            }
        }

        menuBarStatusItemController.update(
            title: menuBarStatusItemTitle(),
            leftClickBehavior: settings.menuBarActivationEnabled ? .togglePanel : .showMenu
        )
    }

    private func applyApplicationVisibilityState() {
        let shouldShowDockIcon = appState.settings.dockIconVisible || isSettingsWindowVisible
        let targetPolicy: NSApplication.ActivationPolicy = shouldShowDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != targetPolicy else { return }
        _ = NSApp.setActivationPolicy(targetPolicy)
    }

    private func applyEdgeServiceSettings() {
        if appState.settings.edgeActivationEnabled {
            hotEdgeService.start(
                side: appState.settings.edgeActivationSide,
                threshold: appState.settings.edgeThreshold,
                activationDelay: TimeInterval(max(0, appState.settings.edgeActivationDelayMS)) / 1000,
                activationVerticalRangeProvider: { [weak self] screen, pointer in
                    self?.edgeActivationVerticalRange(on: screen, pointer: pointer)
                }
            )
        } else {
            hotEdgeService.stop()
        }
    }

    private func applyLaunchAtLoginSetting() {
        let target = appState.settings.launchAtLoginEnabled
        let current = launchAtLoginService.isEnabled()
        guard target != current else { return }

        do {
            try launchAtLoginService.setEnabled(target)
            appState.lastErrorMessage = nil
        } catch {
            appState.updateSettings { settings in
                settings.launchAtLoginEnabled = current
            }
            if AppLocalization.isEnglish {
                appState.lastErrorMessage = "Failed to update launch at login: \(error.localizedDescription)"
            } else {
                appState.lastErrorMessage = "开机启动设置失败：\(error.localizedDescription)"
            }
        }
    }

    private func applyGlobalHotkeySetting() {
        do {
            try globalHotkeyService.updateRegistration(
                enabled: appState.settings.globalHotkeyEnabled,
                triggerMode: appState.settings.hotkeyTriggerMode,
                panelModifier: appState.settings.hotkeyPanelModifier,
                favoritesModifier: appState.settings.hotkeyFavoritesModifier,
                interval: appState.settings.hotkeyDoublePressInterval,
                panelShortcut: appState.settings.hotkeyPanelShortcut,
                favoritesShortcut: appState.settings.hotkeyFavoritesShortcut
            )
            appState.lastErrorMessage = nil
        } catch {
            if AppLocalization.isEnglish {
                appState.lastErrorMessage = "Failed to update global hotkeys: \(error.localizedDescription)"
            } else {
                appState.lastErrorMessage = "全局快捷键设置失败：\(error.localizedDescription)"
            }
        }
    }

    private func menuBarStatusItemTitle() -> String? {
        guard appState.settings.menuBarShowsLatestPreview else { return nil }
        guard let latestItem = appState.history.first else { return nil }
        return menuBarStatusSummary(for: latestItem)
    }

    private func menuBarStatusSummary(for item: ClipboardItem) -> String {
        switch item.kind {
        case .text, .passthroughText:
            let prefix = AppLocalization.isEnglish ? "\"Text\"" : "「文本」"
            let collapsedText = item.preview
                .replacingOccurrences(
                    of: "\\s+",
                    with: " ",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !collapsedText.isEmpty else { return prefix }

            let prefixText = "\(prefix) "
            let prefixUnits = menuBarTextUnitCount(for: prefixText)
            let availableUnits = max(3, 24 - prefixUnits)
            let candidates = [
                prefixText + collapsedText,
                prefixText + truncatedMenuBarStatusText(collapsedText, maximumUnits: availableUnits),
                prefix
            ]
            return firstFittingMenuBarSummary(candidates, maximumUnits: 24) ?? prefix
        case .image:
            return menuBarImageSummary(for: item.imagePayload)
        case .file:
            return menuBarFileSummary(for: item, maximumUnits: 24)
        case .stack:
            let count = item.stackEntries.count
            if AppLocalization.isEnglish {
                return count > 0 ? "\"Stack\" \(count) items" : "\"Stack\""
            }
            return count > 0 ? "「堆栈」\(count)条" : "「堆栈」"
        }
    }

    private func menuBarImageSummary(
        for payload: ClipboardItem.ImagePayload?,
        maximumUnits: Int = 24
    ) -> String {
        let prefix = AppLocalization.isEnglish ? "\"Image\"" : "「图片」"
        guard let payload else { return prefix }

        let prefixText = "\(prefix) "
        let dimensionText = "\(payload.pixelWidth)×\(payload.pixelHeight)"
        let compactSizeText = compactMenuBarByteCount(payload.byteSize)
        let megapixelText = compactMenuBarMegapixels(
            width: payload.pixelWidth,
            height: payload.pixelHeight
        )

        let candidates = [
            "\(prefixText)\(dimensionText)·\(compactSizeText)",
            "\(prefixText)\(dimensionText)",
            "\(prefixText)\(megapixelText)",
            prefix
        ]

        return firstFittingMenuBarSummary(
            candidates,
            maximumUnits: maximumUnits
        ) ?? prefix
    }

    private func menuBarFileSummary(
        for item: ClipboardItem,
        maximumUnits: Int
    ) -> String {
        let fileNames = item.fileDisplayNames

        guard !fileNames.isEmpty else {
            return AppLocalization.isEnglish ? "\"Files\"" : "「文件」"
        }

        guard fileNames.count == 1 else {
            let count = fileNames.count
            let candidates = [
                AppLocalization.isEnglish ? "\"Files\" \(count) items" : "「文件」\(count)项",
                AppLocalization.isEnglish ? "\"Files\"" : "「文件」"
            ]
            return firstFittingMenuBarSummary(candidates, maximumUnits: maximumUnits) ?? (AppLocalization.isEnglish ? "\"Files\"" : "「文件」")
        }

        let metadata = filePresentationMetadata(for: item)
        let kindLabel = metadata?.menuBarKindLabel ?? AppLocalization.localized("文件")
        let displayName = metadata?.displayName ?? fileNames[0]
        let prefix = AppLocalization.isEnglish ? "\"\(kindLabel)\"" : "「\(kindLabel)」"
        let prefixText = "\(prefix) "
        let prefixUnits = menuBarTextUnitCount(for: prefixText)
        let availableUnits = max(3, maximumUnits - prefixUnits)

        let candidates = [
            prefixText + displayName,
            prefixText + truncatedMenuBarFileName(displayName, maximumUnits: availableUnits),
            prefix
        ]

        return firstFittingMenuBarSummary(candidates, maximumUnits: maximumUnits) ?? prefix
    }

    private func truncatedMenuBarStatusText(_ text: String, maximumUnits: Int) -> String {
        let ellipsis = "…"
        let ellipsisUnits = menuBarTextUnitCount(for: ellipsis)
        guard maximumUnits > ellipsisUnits else { return ellipsis }

        let characters = Array(text)
        var consumedUnits = 0
        var result = ""

        for (index, character) in characters.enumerated() {
            let unitCount = menuBarDisplayUnitCount(for: character)
            let hasRemainingCharacters = index < characters.count - 1
            let budget = hasRemainingCharacters ? (maximumUnits - ellipsisUnits) : maximumUnits

            if consumedUnits + unitCount > budget {
                return result + ellipsis
            }

            result.append(character)
            consumedUnits += unitCount
        }

        return result
    }

    private func firstFittingMenuBarSummary(
        _ candidates: [String],
        maximumUnits: Int
    ) -> String? {
        candidates.first { menuBarTextUnitCount(for: $0) <= maximumUnits }
    }

    private func menuBarDisplayUnitCount(for character: Character) -> Int {
        character.unicodeScalars.allSatisfy(\.isASCII) ? 1 : 2
    }

    private func menuBarTextUnitCount(for text: String) -> Int {
        text.reduce(into: 0) { partialResult, character in
            partialResult += menuBarDisplayUnitCount(for: character)
        }
    }

    private func truncatedMenuBarFileName(_ fileName: String, maximumUnits: Int) -> String {
        let fileNameNSString = fileName as NSString
        let extensionName = fileNameNSString.pathExtension
        guard !extensionName.isEmpty else {
            return truncatedMenuBarStatusText(fileName, maximumUnits: maximumUnits)
        }

        let suffix = ".\(extensionName)"
        let suffixUnits = menuBarTextUnitCount(for: suffix)
        let ellipsis = "…"
        let ellipsisUnits = menuBarTextUnitCount(for: ellipsis)

        guard suffixUnits + ellipsisUnits < maximumUnits else {
            return truncatedMenuBarStatusText(fileName, maximumUnits: maximumUnits)
        }

        let prefixBudget = maximumUnits - suffixUnits - ellipsisUnits
        var prefix = ""
        var consumedUnits = 0

        for character in fileNameNSString.deletingPathExtension {
            let unitCount = menuBarDisplayUnitCount(for: character)
            if consumedUnits + unitCount > prefixBudget {
                break
            }

            prefix.append(character)
            consumedUnits += unitCount
        }

        if consumedUnits == menuBarTextUnitCount(for: fileNameNSString.deletingPathExtension) {
            return fileName
        }

        return prefix + ellipsis + suffix
    }

    private func compactMenuBarByteCount(_ byteCount: Int) -> String {
        let thresholds: [(Double, String)] = [
            (1_000_000_000, "G"),
            (1_000_000, "M"),
            (1_000, "K")
        ]

        let value = Double(max(0, byteCount))

        for (threshold, suffix) in thresholds where value >= threshold {
            let raw = value / threshold
            if raw >= 10 {
                return "\(Int(raw.rounded()))\(suffix)"
            }

            let rounded = (raw * 10).rounded() / 10
            if rounded.rounded(.towardZero) == rounded {
                return "\(Int(rounded))\(suffix)"
            }
            return String(format: "%.1f%@", rounded, suffix)
        }

        return "\(Int(value))B"
    }

    private func compactMenuBarMegapixels(width: Int, height: Int) -> String {
        let megapixels = (Double(width) * Double(height)) / 1_000_000
        guard megapixels > 0 else { return AppLocalization.localized("图片") }

        if megapixels >= 10 {
            return "\(Int(megapixels.rounded()))MP"
        }

        let rounded = (megapixels * 10).rounded() / 10
        if rounded.rounded(.towardZero) == rounded {
            return "\(Int(rounded))MP"
        }

        return String(format: "%.1fMP", rounded)
    }

    private func applyRightMouseDragGestureSetting() {
        guard appState.settings.rightMouseDragActivationEnabled else {
            rightMouseDragGestureService.stop()
            mouseGestureTrailOverlayController.hide()
            return
        }

        guard PermissionCenter.isAccessibilityGranted() else {
            rightMouseDragGestureService.stop()
            mouseGestureTrailOverlayController.hide()
            return
        }

        guard rightMouseDragGestureService.start(
            horizontalTriggerDistance: appState.settings.rightMouseDragTriggerDistance,
            auxiliaryGestureConfigurations: rightMouseAuxiliaryGestureConfigurations()
        ) else {
            appState.lastErrorMessage = AppLocalization.localized("按住右键滑出启用失败，请确认已授予辅助功能权限。")
            return
        }
    }

    @discardableResult
    private func synchronizeAccessibilityPermissionState() -> Bool {
        let isGranted = PermissionCenter.isAccessibilityGranted()
        let shouldDisableRightMouseInteraction = !isGranted && appState.settings.rightMouseDragActivationEnabled

        appState.permissionGranted = isGranted

        guard shouldDisableRightMouseInteraction else {
            return isGranted
        }

        appState.updateSettings { settings in
            settings.rightMouseDragActivationEnabled = false
        }
        return isGranted
    }

    private func rightMouseAuxiliaryGestureConfigurations() -> [RightMouseDragGestureService.AuxiliaryGestureConfiguration] {
        guard appState.settings.rightMouseDragActivationEnabled else { return [] }
        return appState.settings.rightMouseAuxiliaryGestures
            .filter(\.enabled)
            .map {
                .init(
                    id: $0.id,
                    pattern: $0.pattern,
                    note: $0.note
                )
            }
    }

    private func handleRightMouseAuxiliaryGesture(id gestureID: UUID) {
        guard let configuration = appState.settings.rightMouseAuxiliaryGestures.first(where: { $0.id == gestureID }) else {
            return
        }
        guard configuration.enabled else { return }

        switch configuration.actionType {
        case .shortcut:
            sendKeyboardShortcut(using: configuration)
        case .openApplication:
            openApplication(at: configuration.applicationPath)
        }
    }

    private func beginRightDragSelection(at point: CGPoint) {
        guard !isPanelVisible else { return }
        let compensatedPoint = CGPoint(
            x: point.x + appState.settings.rightMouseDragTriggerDistance,
            y: point.y
        )
        showPanel(mode: .rightDrag, pointer: compensatedPoint)
        guard panelController.isVisible else { return }

        appState.isRightDragSelecting = true
        appState.rightDragHighlightedRowID = nil
        appState.rightDragHeaderTarget = nil
        appState.rightDragHoveredTab = nil
        rightDragLatestPointer = point
        rightDragFrozenViewportY = nil
        updateRightDragSelection(at: point)
    }

    private func updateRightDragSelection(at point: CGPoint) {
        guard isPanelVisible, currentPanelPresentationMode == .rightDrag else { return }
        rightDragLatestPointer = point

        let rowIDs = currentRightDragRowIdentifiers()
        let interactionTarget = resolveRightDragInteractionTarget(at: point, itemsCount: rowIDs.count)

        switch interactionTarget {
        case let .row(rowIndex):
            guard !rowIDs.isEmpty else {
                appState.rightDragHeaderTarget = nil
                appState.rightDragHoveredTab = nil
                rightDragFrozenViewportY = nil
                applyRightDragSelection(rowIndex: nil, rowIDs: rowIDs)
                return
            }
            if currentPanelRequiresTabHoverUnlock, !appState.isPanelTabHoverUnlocked {
                appState.isPanelTabHoverUnlocked = true
            }
            appState.rightDragHeaderTarget = nil
            appState.rightDragHoveredTab = nil
            rightDragFrozenViewportY = rightDragViewportY(at: point)
            applyRightDragSelection(rowIndex: rowIndex, rowIDs: rowIDs)
            return
        case let .tab(tab):
            appState.rightDragHeaderTarget = nil
            appState.rightDragHoveredTab = tab
            rightDragFrozenViewportY = nil
            applyRightDragSelection(rowIndex: nil, rowIDs: rowIDs)
            if appState.activeTab != tab {
                appState.activeTab = tab
            }
            return
        case let .favoriteGroup(groupID):
            appState.rightDragHeaderTarget = nil
            appState.rightDragHoveredTab = nil
            rightDragFrozenViewportY = nil
            applyRightDragSelection(rowIndex: nil, rowIDs: rowIDs)
            guard appState.activeTab == .favorites else { return }
            if appState.activeFavoriteGroupID != groupID {
                selectFavoriteGroup(groupID)
            }
            return
        case .search:
            appState.rightDragHeaderTarget = .search
            appState.rightDragHoveredTab = nil
            rightDragFrozenViewportY = nil
            applyRightDragSelection(rowIndex: nil, rowIDs: rowIDs)
            return
        case .close:
            appState.rightDragHeaderTarget = .close
            appState.rightDragHoveredTab = nil
            rightDragFrozenViewportY = nil
            applyRightDragSelection(rowIndex: nil, rowIDs: rowIDs)
            return
        case .favoriteAdd:
            appState.rightDragHeaderTarget = .favoriteAdd
            appState.rightDragHoveredTab = nil
            rightDragFrozenViewportY = nil
            applyRightDragSelection(rowIndex: nil, rowIDs: rowIDs)
            return
        case .stack:
            appState.rightDragHeaderTarget = .stack
            appState.rightDragHoveredTab = nil
            rightDragFrozenViewportY = nil
            applyRightDragSelection(rowIndex: nil, rowIDs: rowIDs)
            return
        case .pin:
            appState.rightDragHeaderTarget = .pin
            appState.rightDragHoveredTab = nil
            rightDragFrozenViewportY = nil
            applyRightDragSelection(rowIndex: nil, rowIDs: rowIDs)
            return
        case .none:
            appState.rightDragHeaderTarget = nil
            appState.rightDragHoveredTab = nil
            rightDragFrozenViewportY = nil
            applyRightDragSelection(rowIndex: nil, rowIDs: rowIDs)
            return
        }

    }

    private func finishRightDragSelection() {
        guard currentPanelPresentationMode == .rightDrag else { return }

        let rowIDs = currentRightDragRowIdentifiers()
        let releaseTarget = rightDragLatestPointer.map {
            resolveRightDragInteractionTarget(at: $0, itemsCount: rowIDs.count)
        } ?? .none
        let selectedFavoriteEntry = rightDragSelectedFavoriteEntry()
        let selectedItem = rightDragSelectedHistoryItem()

        appState.isRightDragSelecting = false
        appState.rightDragHighlightedRowID = nil
        appState.rightDragHeaderTarget = nil
        appState.rightDragHoveredTab = nil
        rightDragLatestPointer = nil
        rightDragFrozenViewportY = nil

        switch releaseTarget {
        case .close:
            hidePanel()
            return
        case .search:
            preparePanelForTextInput()
            appState.searchRevealRequestToken &+= 1
            return
        case .favoriteAdd:
            openNewFavoriteSnippetEditor()
            return
        case .stack:
            toggleStackMode()
            return
        case .pin:
            appState.isPanelPinned.toggle()
            return
        case .favoriteGroup:
            return
        case .tab:
            return
        case .row, .none:
            break
        }

        if appState.activeTab == .favorites {
            guard let selectedFavoriteEntry else {
                hidePanel()
                return
            }
            paste(favoriteEntry: selectedFavoriteEntry)
            return
        }

        guard let selectedItem else {
            hidePanel()
            return
        }
        paste(item: selectedItem)
    }

    private func handleRightDragScroll(deltaY: CGFloat, pointer: CGPoint) {
        guard isPanelVisible, currentPanelPresentationMode == .rightDrag else { return }
        guard deltaY != 0 else { return }

        let normalizedDelta = max(-1, min(1, deltaY))
        let scrollDelta = -normalizedDelta * panelRowHeight
        appState.rightDragScrollDelta = scrollDelta
        appState.rightDragScrollCommandToken &+= 1
        rightDragLatestPointer = pointer
        if rightDragFrozenViewportY == nil,
           let viewportY = rightDragViewportY(at: pointer) {
            rightDragFrozenViewportY = viewportY
        }

        let rowIDs = currentRightDragRowIdentifiers()
        if willRightDragScrollClamp(delta: scrollDelta, itemsCount: rowIDs.count) {
            let rowIndex = rightDragRowIndexForFrozenViewportY(itemsCount: rowIDs.count)
            applyRightDragSelection(rowIndex: rowIndex, rowIDs: rowIDs)
        }
    }

    func refreshRightDragSelectionAfterScroll(documentY: CGFloat?) {
        guard isPanelVisible, currentPanelPresentationMode == .rightDrag else { return }
        guard appState.rightDragHeaderTarget == nil else { return }

        let rowIDs = currentRightDragRowIdentifiers()
        guard !rowIDs.isEmpty else { return }

        if let rowIndex = rightDragRowIndexForFrozenViewportY(itemsCount: rowIDs.count) {
            applyRightDragSelection(rowIndex: rowIndex, rowIDs: rowIDs)
            return
        }

        if let documentY {
            let rowIndex = rightDragRowIndex(documentY: documentY, itemsCount: rowIDs.count)
            applyRightDragSelection(rowIndex: rowIndex, rowIDs: rowIDs)
            return
        }

        guard let pointer = rightDragLatestPointer else { return }
        let rowIndex = rightDragRowIndex(at: pointer, itemsCount: rowIDs.count)
        applyRightDragSelection(rowIndex: rowIndex, rowIDs: rowIDs)
    }

    private func applyRightDragSelection(rowIndex: Int?, rowIDs: [UUID]) {
        guard let rowIndex, rowIDs.indices.contains(rowIndex) else {
            if appState.rightDragHighlightedRowID != nil {
                appState.rightDragHighlightedRowID = nil
            }
            return
        }

        let itemID = rowIDs[rowIndex]
        if appState.rightDragHighlightedRowID != itemID {
            appState.rightDragHighlightedRowID = itemID
        }
    }

    private func resolveRightDragInteractionTarget(at point: CGPoint, itemsCount: Int) -> RightDragInteractionTarget {
        guard let localPoint = panelController.panelLocalPoint(fromScreen: point) else {
            return .none
        }

        unlockPanelTabHoverIfNeeded(at: localPoint)

        if let searchFrame = appState.panelSearchButtonFrame,
           searchFrame.insetBy(dx: -6, dy: -6).contains(localPoint) {
            return .search
        }

        if let closeFrame = appState.panelCloseButtonFrame,
           closeFrame.insetBy(dx: -6, dy: -6).contains(localPoint) {
            return .close
        }

        if let favoriteAddFrame = appState.panelFavoriteAddButtonFrame,
           favoriteAddFrame.insetBy(dx: -6, dy: -6).contains(localPoint) {
            return .favoriteAdd
        }

        if let stackFrame = appState.panelStackButtonFrame,
           stackFrame.insetBy(dx: -6, dy: -6).contains(localPoint) {
            return .stack
        }

        if let pinFrame = appState.panelPinButtonFrame,
           pinFrame.insetBy(dx: -6, dy: -6).contains(localPoint) {
            return .pin
        }

        if appState.isPanelTabHoverUnlocked,
           let tab = rightDragTab(at: localPoint) {
            return .tab(tab)
        }

        if appState.activeTab == .favorites,
           let target = rightDragFavoriteGroup(at: localPoint) {
            return .favoriteGroup(target.groupID)
        }

        if appState.activeTab == .favorites,
           let historyListFrame = appState.panelHistoryListFrame,
           !historyListFrame.contains(localPoint) {
            return .none
        }

        guard let rowIndex = rightDragRowIndex(at: point, itemsCount: itemsCount) else {
            return .none
        }

        return .row(rowIndex)
    }

    private func currentRightDragRowIdentifiers() -> [UUID] {
        if appState.activeTab == .favorites {
            return favoritePanelEntries().map(\.id)
        }

        return appState.filteredHistory.map(\.id)
    }

    private func rightDragSelectedHistoryItem() -> ClipboardItem? {
        guard appState.activeTab != .favorites,
              let selectedID = appState.rightDragHighlightedRowID else {
            return nil
        }

        return appState.filteredHistory.first(where: { $0.id == selectedID })
    }

    private func rightDragSelectedFavoriteEntry() -> FavoritePanelEntry? {
        guard appState.activeTab == .favorites,
              let selectedID = appState.rightDragHighlightedRowID else {
            return nil
        }

        return favoritePanelEntries().first(where: { $0.id == selectedID })
    }

    private func paste(favoriteEntry: FavoritePanelEntry) {
        switch favoriteEntry {
        case .snippet(let snippet):
            pasteFavoriteSnippet(id: snippet.id)
        case .historyItem(let item):
            paste(item: item)
        }
    }

    private func rightDragRowIndex(at point: CGPoint, itemsCount: Int) -> Int? {
        guard let documentY = rightDragDocumentY(at: point) else { return nil }
        return rightDragRowIndex(documentY: documentY, itemsCount: itemsCount)
    }

    private func rightDragRowIndexForFrozenViewportY(itemsCount: Int) -> Int? {
        guard let viewportY = rightDragFrozenViewportY else { return nil }
        let documentY = appState.panelScrollOffset + viewportY
        return rightDragRowIndex(documentY: documentY, itemsCount: itemsCount)
    }

    private func rightDragRowIndex(documentY: CGFloat, itemsCount: Int) -> Int? {
        let rowIndex = Int(floor(documentY / panelRowHeight))
        guard rowIndex >= 0, rowIndex < itemsCount else { return nil }
        return rowIndex
    }

    private func rightDragDocumentY(at point: CGPoint) -> CGFloat? {
        guard let viewportY = rightDragViewportY(at: point) else { return nil }
        return appState.panelScrollOffset + viewportY
    }

    private func rightDragViewportY(at point: CGPoint) -> CGFloat? {
        guard let panelFrame = panelController.frame,
              let historyListFrame = appState.panelHistoryListFrame else {
            return nil
        }

        let expandedHistoryFrame = CGRect(
            x: panelFrame.minX + historyListFrame.minX - 64,
            y: panelFrame.maxY - historyListFrame.maxY,
            width: historyListFrame.width + 128,
            height: historyListFrame.height
        )
        guard expandedHistoryFrame.contains(point) else { return nil }

        let clampedPoint = CGPoint(
            x: min(max(point.x, panelFrame.minX + 1), panelFrame.maxX - 1),
            y: min(max(point.y, panelFrame.minY + 1), panelFrame.maxY - 1)
        )
        guard let localPoint = panelController.panelLocalPoint(fromScreen: clampedPoint),
              localPoint.y >= historyListFrame.minY,
              localPoint.y <= historyListFrame.maxY else {
            return nil
        }

        let viewportY = localPoint.y - historyListFrame.minY
        let upperBound = max(0, historyListFrame.height - 0.001)
        return min(max(0, viewportY), upperBound)
    }

    private func willRightDragScrollClamp(delta: CGFloat, itemsCount: Int) -> Bool {
        guard itemsCount > 0,
              let historyListFrame = appState.panelHistoryListFrame else {
            return false
        }

        let maxOffset = max(0, (CGFloat(itemsCount) * panelRowHeight) - historyListFrame.height)
        let targetOffset = appState.panelScrollOffset + delta
        let clampedOffset = min(max(0, targetOffset), maxOffset)
        return abs(clampedOffset - appState.panelScrollOffset) <= 0.5
    }

    private func unlockPanelTabHoverIfNeeded(at localPoint: CGPoint) {
        guard currentPanelPresentationMode == .rightDrag else { return }
        guard currentPanelRequiresTabHoverUnlock else { return }
        guard !appState.isPanelTabHoverUnlocked else { return }
        guard let historyListFrame = appState.panelHistoryListFrame else { return }
        guard historyListFrame.contains(localPoint) else { return }
        appState.isPanelTabHoverUnlocked = true
    }

    private func rightDragFavoriteGroup(at localPoint: CGPoint) -> PanelFavoriteGroupTarget? {
        guard appState.activeTab == .favorites else { return nil }

        let orderedTargets: [PanelFavoriteGroupTarget] = [.all] + appState.favoriteGroups.map { .group($0.id) }
        for target in orderedTargets {
            guard let frame = appState.panelFavoriteGroupFrames[target] else { continue }
            if frame.insetBy(dx: -4, dy: -4).contains(localPoint) {
                return target
            }
        }

        return nil
    }

    private func rightDragTab(at localPoint: CGPoint) -> PanelTab? {
        let orderedTabs = appState.visiblePanelTabs.compactMap { tab -> (PanelTab, CGRect)? in
            guard let frame = appState.panelTabFrames[tab] else { return nil }
            return (tab, frame)
        }

        guard !orderedTabs.isEmpty else { return nil }

        let minY = orderedTabs.map(\.1.minY).min() ?? 0
        let maxY = orderedTabs.map(\.1.maxY).max() ?? 0
        let verticalPadding: CGFloat = 6
        guard localPoint.y >= (minY - verticalPadding), localPoint.y <= (maxY + verticalPadding) else {
            return nil
        }

        let horizontalPadding: CGFloat = 6
        let minX = (orderedTabs.first?.1.minX ?? 0) - horizontalPadding
        let maxX = (orderedTabs.last?.1.maxX ?? 0) + horizontalPadding
        guard localPoint.x >= minX, localPoint.x <= maxX else {
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

            if localPoint.x >= leftBoundary, localPoint.x < rightBoundary {
                return orderedTabs[index].0
            }
        }

        return orderedTabs.last?.0
    }

    private func handleClipboardCaptured(_ capture: ClipboardMonitor.Capture) {
        if let bundleID = capture.sourceAppBundleID,
           appState.settings.blacklistedBundleIDs.contains(bundleID) {
            return
        }

        switch capture.payload {
        case let .text(textPayload):
            ingestCapturedText(
                textPayload,
                sourceAppBundleID: capture.sourceAppBundleID,
                sourceAppName: capture.sourceAppName
            )
        case let .passthroughText(payload):
            ingestCapturedPassthroughText(
                payload,
                sourceAppBundleID: capture.sourceAppBundleID,
                sourceAppName: capture.sourceAppName
            )
        case let .image(image):
            ingestCapturedImage(
                image,
                sourceAppBundleID: capture.sourceAppBundleID,
                sourceAppName: capture.sourceAppName
            )
        case let .files(urls):
            ingestCapturedFiles(
                urls,
                sourceAppBundleID: capture.sourceAppBundleID,
                sourceAppName: capture.sourceAppName
            )
        }
    }

    private func handlePendingTextCaptureAbandoned(_ requestID: UUID) {
        guard let item = appState.history.first(where: {
            $0.kind == .passthroughText && $0.passthroughTextRequestID == requestID
        }) else {
            return
        }

        appState.updateItem(itemID: item.id) { updatedItem in
            updatedItem.availabilityIssue = .sourceUnavailable
                if var payload = updatedItem.passthroughTextPayload {
                    payload.previewText = AppLocalization.localized("超长文本未完成读取")
                    payload.mode = .abandoned
                    updatedItem.passthroughTextPayload = payload
                }
        }
    }

    private func handlePendingTextCaptureTimedOut(
        _ requestID: UUID,
        changeCount: Int,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) {
        ingestCapturedPassthroughText(
            ClipboardItem.PassthroughTextPayload(
                requestID: requestID,
                capturedChangeCount: changeCount,
                previewText: AppLocalization.localized("超长文本未进入历史"),
                mode: .clipboardOnly,
                byteCount: nil,
                cacheToken: nil
            ),
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )
    }

    private func handleClipboardChangeCountUpdated(_ currentChangeCount: Int) {
        let timedOutItemIDs = appState.history.compactMap { item -> ClipboardItem.ID? in
            guard item.kind == .passthroughText,
                  item.isClipboardOnlyPassthroughText,
                  item.passthroughTextChangeCount != currentChangeCount else {
                return nil
            }
            return item.id
        }

        for itemID in timedOutItemIDs {
            appState.updateItem(itemID: itemID) { updatedItem in
                updatedItem.availabilityIssue = .sourceUnavailable
                if var payload = updatedItem.passthroughTextPayload {
                    payload.previewText = AppLocalization.localized("超长文本已丢弃")
                    payload.mode = .discarded
                    updatedItem.passthroughTextPayload = payload
                }
            }
        }
    }

    private func capturePolicy(forSourceBundleID bundleID: String?) -> ClipboardMonitor.CapturePolicy {
        guard let bundleID else {
            return .defaultTextPreferred
        }

        if appState.settings.blacklistedBundleIDs.contains(bundleID) {
            return .ignoreAll
        }

        return .defaultTextPreferred
    }

    private func ingestCapturedText(
        _ capture: ClipboardMonitor.TextCapturePayload,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) {
        let text = capture.text
        if ClipboardItem.exceedsStoredTextLimit(text) {
            showTransientNotice(oversizedTextCaptureMessage(
                byteCount: text.lengthOfBytes(using: .utf8)
            ))
            return
        }

        let meaningfulText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !meaningfulText.isEmpty else { return }

        let replacementTarget = capture.requestID.flatMap { requestID in
            appState.history.first { $0.passthroughTextRequestID == requestID }
        }
        let itemID = replacementTarget?.id ?? UUID()
        let createdAt = replacementTarget?.createdAt ?? Date()
        do {
            let payload = try persistence.storeTextPayload(meaningfulText, itemID: itemID)
            let item = ClipboardItem(
                id: itemID,
                createdAt: createdAt,
                kind: .text,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                textPayload: payload
            )
            if let replacementTarget {
                appState.replaceItem(itemID: replacementTarget.id, with: item)
            } else {
                appState.ingest(item)
            }
            appState.lastErrorMessage = nil
        } catch {
            appState.lastErrorMessage = error.localizedDescription
        }
    }

    private func ingestCapturedPassthroughText(
        _ payload: ClipboardItem.PassthroughTextPayload,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) {
        let replacementTarget = appState.history.first {
            $0.kind == .passthroughText && $0.passthroughTextRequestID == payload.requestID
        }
        let item = ClipboardItem(
            id: replacementTarget?.id ?? UUID(),
            createdAt: replacementTarget?.createdAt ?? Date(),
            kind: .passthroughText,
            availabilityIssue: payload.mode == .abandoned || payload.mode == .discarded
                ? .sourceUnavailable
                : nil,
            sourceAppBundleID: sourceAppBundleID ?? replacementTarget?.sourceAppBundleID,
            sourceAppName: sourceAppName ?? replacementTarget?.sourceAppName,
            passthroughTextPayload: payload
        )
        if let replacementTarget {
            appState.replaceItem(itemID: replacementTarget.id, with: item)
        } else {
            appState.ingest(item)
        }
        appState.lastErrorMessage = nil
    }

    private func ingestCapturedImage(
        _ image: NSImage,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) {
        guard appState.settings.recordImageClipboardEnabled else { return }
        let itemID = UUID()
        do {
            let payload = try persistence.storeImageAsset(image, itemID: itemID)
            appState.ingest(
                ClipboardItem(
                    id: itemID,
                    createdAt: Date(),
                    imagePayload: payload,
                    sourceAppBundleID: sourceAppBundleID,
                    sourceAppName: sourceAppName
                )
            )
            appState.lastErrorMessage = nil
        } catch {
            appState.lastErrorMessage = error.localizedDescription
        }
    }

    private func ingestCapturedFiles(
        _ urls: [URL],
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) {
        guard appState.settings.recordFileClipboardEnabled else { return }

        let normalizedURLs = urls
            .filter(\.isFileURL)
            .map(\.standardizedFileURL)
        guard !normalizedURLs.isEmpty else { return }

        let displayNames = normalizedURLs.map { url in
            let name = url.lastPathComponent
            return name.isEmpty ? url.path : name
        }

        appState.ingest(
            ClipboardItem(
                fileURLs: normalizedURLs,
                displayNames: displayNames,
                securityScopedBookmarks: createSecurityScopedBookmarks(for: normalizedURLs),
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName
            )
        )
        appState.lastErrorMessage = nil
    }

    private func oversizedTextCaptureMessage(byteCount: Int) -> String {
        let sizeText = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        let limitText = ByteCountFormatter.string(
            fromByteCount: Int64(ClipboardItem.maximumStoredTextByteCount),
            countStyle: .file
        )
        if AppLocalization.isEnglish {
            return "Text is too large (\(sizeText)) and was skipped. Current limit: \(limitText)."
        }
        return "文本过大（\(sizeText)），已跳过采集。当前上限 \(limitText)。"
    }

    private func handlePanelVisibilityChanged(_ isVisible: Bool) {
        if isVisible {
            clearPinnedPanelIdleDimmingIfNeeded(animated: false)
            updatePanelKeyMonitoringState()
            startOutsideClickMonitoring()
        } else {
            clearPinnedPanelIdleDimmingIfNeeded(animated: false)
            hideFullPreview()
            appState.clearTransientPanelState()
            fileAvailabilityCache.removeAll()
            stopPanelDigitKeyMonitoring()
            stopOutsideClickMonitoring()
        }
        applyApplicationVisibilityState()
        updateStackBridgeState()
        updatePanelPreviewHotkeyBridgeState()
    }

    private func updatePanelKeyMonitoringState() {
        guard isPanelVisible, !appState.isFavoriteEditorPresented else {
            stopPanelDigitKeyMonitoring()
            return
        }

        startPanelDigitKeyMonitoring()
    }

    private func startPanelDigitKeyMonitoring() {
        stopPanelDigitKeyMonitoring()

        localPanelKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if handlePanelKey(event) {
                return nil
            }
            return event
        }
    }

    private func stopPanelDigitKeyMonitoring() {
        if let localPanelKeyMonitor {
            NSEvent.removeMonitor(localPanelKeyMonitor)
            self.localPanelKeyMonitor = nil
        }
    }

    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self else { return event }
            handleOutsidePanelClick(at: event.locationInWindow, sourceWindow: event.window)
            return event
        }

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handleOutsidePanelClick(at: event.locationInWindow, sourceWindow: nil)
        }
    }

    private func stopOutsideClickMonitoring() {
        if let localOutsideClickMonitor {
            NSEvent.removeMonitor(localOutsideClickMonitor)
            self.localOutsideClickMonitor = nil
        }

        if let globalOutsideClickMonitor {
            NSEvent.removeMonitor(globalOutsideClickMonitor)
            self.globalOutsideClickMonitor = nil
        }
    }

    private func handleOutsidePanelClick(at locationInWindow: CGPoint, sourceWindow: NSWindow?) {
        guard isPanelVisible else { return }

        let globalPoint: CGPoint
        if let sourceWindow {
            globalPoint = sourceWindow.convertPoint(toScreen: locationInWindow)
        } else {
            globalPoint = NSEvent.mouseLocation
        }

        let isInsidePanelInteractionRegion = panelController.contains(point: globalPoint) ||
            isPointInPanelExtendedInteractionRegion(globalPoint)

        if isInsidePanelInteractionRegion {
            clearPinnedPanelIdleDimmingIfNeeded()
            return
        }

        if appState.isPanelPinned {
            dimPinnedPanelAfterOutsideClickIfNeeded()
            return
        }

        if !isInsidePanelInteractionRegion {
            hidePanel()
        }
    }

    private var isAnyAuxiliaryPanelPresented: Bool {
        appState.isStackProcessorPresented ||
        appState.isFavoriteEditorPresented ||
        isFullPreviewPresented ||
        fullPreviewContent != nil ||
        fullPreviewUnavailableState != nil ||
        fullPreviewPanelController.isVisible
    }

    private func dimPinnedPanelAfterOutsideClickIfNeeded() {
        guard isPanelVisible, appState.isPanelPinned else { return }
        guard !isAnyAuxiliaryPanelPresented else { return }
        setPinnedPanelIdleDimmed(true)
    }

    private func clearPinnedPanelIdleDimmingIfNeeded(animated: Bool = true) {
        setPinnedPanelIdleDimmed(false, animated: animated)
    }

    private func setPinnedPanelIdleDimmed(_ isDimmed: Bool, animated: Bool = true) {
        let canDim = isPanelVisible && appState.isPanelPinned && !isAnyAuxiliaryPanelPresented
        let nextValue = canDim ? isDimmed : false
        isPinnedPanelIdleDimmed = nextValue
        panelController.setPinnedIdleDimmed(nextValue, animated: animated)
    }

    private func handlePanelKey(_ event: NSEvent) -> Bool {
        guard isPanelVisible else { return false }

        if isFullPreviewPresented {
            switch event.keyCode {
            case 53:
                hideFullPreview()
                return true
            case 123:
                guard fullPreviewSupportsItemNavigation else { return false }
                showPreviousFullPreviewItem()
                return true
            case 124:
                guard fullPreviewSupportsItemNavigation else { return false }
                showNextFullPreviewItem()
                return true
            case 49:
                hideFullPreview()
                return true
            default:
                break
            }
        }

        if event.keyCode == 53 {
            hidePanel()
            return true
        }

        if panelController.hasFocusedTextInput() {
            return false
        }

        if appState.isFavoriteEditorPresented {
            return false
        }

        if appState.panelMode == .stack {
            return false
        }

        let blockingModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift, .capsLock, .function]
        if !event.modifierFlags.intersection(blockingModifiers).isEmpty {
            return false
        }

        if event.keyCode == 49 {
            if currentPanelPresentationMode == .rightDrag {
                showTransientNotice(AppLocalization.localized("此交互方式不支持预览"), tone: .info)
                return true
            }

            guard let target = currentPanelPreviewTarget() else {
                return false
            }

            if !appState.settings.filePreviewEnabled {
                return true
            }

            guard previewTargetSupportsFullPreview(target) else {
                return false
            }

            toggleFullPreview(for: target)
            return true
        }

        guard
            let chars = event.charactersIgnoringModifiers,
            chars.count == 1,
            let first = chars.first,
            first >= "0",
            first <= "9",
            let number = Int(String(first))
        else {
            return false
        }

        let visibleEntryCount: Int
        if appState.activeTab == .favorites {
            visibleEntryCount = favoritePanelEntries().count
        } else {
            visibleEntryCount = appState.filteredHistory.count
        }

        guard canActivateVisibleSlot(number, itemsCount: visibleEntryCount) else {
            return true
        }

        pasteVisibleSlot(number)
        return true
    }

    private func currentPanelPreviewTarget() -> PanelPreviewTarget? {
        if let pointedTarget = panelPreviewTargetUnderPointer() {
            return pointedTarget
        }

        if appState.activeTab == .favorites,
           let hoveredRowID = appState.hoveredRowID,
           let hoveredEntry = favoritePanelEntries().first(where: { $0.id == hoveredRowID }) {
            return panelPreviewTarget(for: hoveredEntry)
        }

        if let hoveredRowID = appState.hoveredRowID,
           let hoveredItem = appState.item(withID: hoveredRowID) {
            return .historyItem(hoveredItem)
        }

        return nil
    }

    private func historyItemUnderPointer(_ point: CGPoint = NSEvent.mouseLocation) -> ClipboardItem? {
        guard isPanelVisible, appState.panelMode == .history else { return nil }
        guard panelController.contains(point: point) else { return nil }
        guard let localPoint = panelController.panelLocalPoint(fromScreen: point),
              let historyListFrame = appState.panelHistoryListFrame,
              historyListFrame.contains(localPoint) else {
            return nil
        }

        let items = appState.filteredHistory
        guard !items.isEmpty else { return nil }

        let documentY = appState.panelScrollOffset + (localPoint.y - historyListFrame.minY)
        guard documentY >= 0 else { return nil }

        let rowIndex = Int(floor(documentY / panelRowHeight))
        guard items.indices.contains(rowIndex) else { return nil }
        return items[rowIndex]
    }

    private func panelPreviewTargetUnderPointer(_ point: CGPoint = NSEvent.mouseLocation) -> PanelPreviewTarget? {
        guard isPanelVisible, appState.panelMode == .history else { return nil }
        guard panelController.contains(point: point) else { return nil }
        guard let localPoint = panelController.panelLocalPoint(fromScreen: point),
              let historyListFrame = appState.panelHistoryListFrame,
              historyListFrame.contains(localPoint) else {
            return nil
        }

        let documentY = appState.panelScrollOffset + (localPoint.y - historyListFrame.minY)
        guard documentY >= 0 else { return nil }

        let rowIndex = Int(floor(documentY / panelRowHeight))
        if appState.activeTab == .favorites {
            let entries = favoritePanelEntries()
            guard entries.indices.contains(rowIndex) else { return nil }
            return panelPreviewTarget(for: entries[rowIndex])
        }

        guard let item = historyItemUnderPointer(point) else { return nil }
        return .historyItem(item)
    }

    private func panelPreviewTarget(for entry: FavoritePanelEntry) -> PanelPreviewTarget {
        switch entry {
        case .snippet(let snippet):
            return .favoriteSnippet(snippet)
        case .historyItem(let item):
            return .historyItem(item)
        }
    }

    private func panelPreviewTarget(for rowID: ClipboardItem.ID) -> PanelPreviewTarget? {
        if appState.activeTab == .favorites,
           let entry = favoritePanelEntries().first(where: { $0.id == rowID }) {
            return panelPreviewTarget(for: entry)
        }

        if let item = appState.item(withID: rowID) {
            return .historyItem(item)
        }

        return nil
    }

    private func previewTargetSupportsFullPreview(_ target: PanelPreviewTarget) -> Bool {
        switch target {
        case .historyItem(let item):
            return itemSupportsFullPreview(item)
        case .favoriteSnippet(let snippet):
            return snippetSupportsFullPreview(snippet)
        }
    }

    private func snippetSupportsFullPreview(_ snippet: FavoriteSnippet) -> Bool {
        guard appState.settings.filePreviewEnabled else { return false }
        return !snippet.trimmedText.isEmpty
    }

    private func pasteVisibleSlot(_ number: Int) {
        guard !appState.isFavoriteEditorPresented else { return }

        if appState.activeTab == .favorites {
            let visibleEntries = favoritePanelEntries()
            let targetIndex: Int
            if number == 0 {
                guard let hiddenTopIndex = appState.panelHiddenTopIndex else { return }
                targetIndex = hiddenTopIndex
            } else {
                let startIndex = max(0, appState.panelVisibleStartIndex)
                targetIndex = startIndex + (number - 1)
            }
            guard visibleEntries.indices.contains(targetIndex) else { return }
            switch visibleEntries[targetIndex] {
            case .snippet(let snippet):
                pasteFavoriteSnippet(id: snippet.id)
            case .historyItem(let item):
                paste(item: item)
            }
            return
        }

        let visibleItems = appState.filteredHistory
        let targetIndex: Int
        if number == 0 {
            guard let hiddenTopIndex = appState.panelHiddenTopIndex else { return }
            targetIndex = hiddenTopIndex
        } else {
            let startIndex = max(0, appState.panelVisibleStartIndex)
            targetIndex = startIndex + (number - 1)
        }
        guard visibleItems.indices.contains(targetIndex) else { return }

        paste(item: visibleItems[targetIndex])
    }

    private func canActivateVisibleSlot(_ number: Int, itemsCount: Int) -> Bool {
        guard itemsCount > 0 else { return false }

        if number == 0 {
            return appState.panelHiddenTopIndex != nil
        }

        let visibleShortcutCount = currentVisibleShortcutCount(itemsCount: itemsCount)
        guard visibleShortcutCount > 0 else { return false }
        return number >= 1 && number <= visibleShortcutCount
    }

    private func currentVisibleShortcutCount(itemsCount: Int) -> Int {
        guard itemsCount > 0 else { return 0 }
        guard let historyListFrame = appState.panelHistoryListFrame else {
            return min(9, itemsCount)
        }

        let viewportHeight = max(0, historyListFrame.height)
        guard viewportHeight > 0.5 else { return 0 }

        let rawOffsetInRow = appState.panelScrollOffset.truncatingRemainder(dividingBy: panelRowHeight)
        let offsetInRow = rawOffsetInRow >= 0 ? rawOffsetInRow : (rawOffsetInRow + panelRowHeight)
        let hasPartiallyVisibleTopRow = appState.panelHiddenTopIndex != nil && offsetInRow > 0.5
        let availableHeightForFullyVisibleRows: CGFloat
        if hasPartiallyVisibleTopRow {
            availableHeightForFullyVisibleRows = viewportHeight - (panelRowHeight - offsetInRow)
        } else {
            availableHeightForFullyVisibleRows = viewportHeight
        }

        let fullyVisibleRows = max(0, Int(floor(max(0, availableHeightForFullyVisibleRows) / panelRowHeight)))
        let remainingVisibleItems = max(0, itemsCount - max(0, appState.panelVisibleStartIndex))
        return min(9, min(fullyVisibleRows, remainingVisibleItems))
    }

    private func sendKeyboardShortcut(using configuration: RightMouseAuxiliaryGestureSettings) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        guard let keyCode = keyCode(forShortcutKey: configuration.shortcutKey) else {
            if AppLocalization.isEnglish {
                appState.lastErrorMessage = "Invalid auxiliary gesture shortcut: \(configuration.shortcutKey)"
            } else {
                appState.lastErrorMessage = "附加手势快捷键无效：\(configuration.shortcutKey)"
            }
            return
        }

        let modifiers = shortcutModifierFlags(using: configuration)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func shortcutModifierFlags(using configuration: RightMouseAuxiliaryGestureSettings) -> CGEventFlags {
        var flags: CGEventFlags = []
        if configuration.shortcutUsesCommand { flags.insert(.maskCommand) }
        if configuration.shortcutUsesOption { flags.insert(.maskAlternate) }
        if configuration.shortcutUsesControl { flags.insert(.maskControl) }
        if configuration.shortcutUsesShift { flags.insert(.maskShift) }
        return flags
    }

    private func keyCode(forShortcutKey key: String) -> CGKeyCode? {
        guard let keyCode = KeyboardShortcut.keyCode(for: key) else { return nil }
        return CGKeyCode(keyCode)
    }

    private func openApplication(at applicationPath: String) {
        let trimmedPath = applicationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            appState.lastErrorMessage = AppLocalization.localized("附加手势未指定要打开的 App。")
            return
        }

        let appURL = URL(fileURLWithPath: trimmedPath)
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor [weak self] in
                    if AppLocalization.isEnglish {
                        self?.appState.lastErrorMessage = "Failed to open app: \(error.localizedDescription)"
                    } else {
                        self?.appState.lastErrorMessage = "打开 App 失败：\(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func colorScheme(for mode: AppearanceMode) -> ColorScheme? {
        switch mode {
        case .system:
            return systemColorScheme()
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func systemColorScheme() -> ColorScheme {
        let appearance = NSApp.effectiveAppearance
        let matchedAppearance = appearance.bestMatch(from: [.darkAqua, .aqua])
        return matchedAppearance == .darkAqua ? .dark : .light
    }

    private func isFileReachable(originalURL: URL, bookmarkData: Data?) -> Bool {
        let fileManager = FileManager.default

        if let bookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                let standardizedURL = resolvedURL.standardizedFileURL
                let accessed = standardizedURL.startAccessingSecurityScopedResource()
                defer {
                    if accessed {
                        standardizedURL.stopAccessingSecurityScopedResource()
                    }
                }
                if fileManager.fileExists(atPath: standardizedURL.path) &&
                    fileManager.isReadableFile(atPath: standardizedURL.path) {
                    return true
                }

                if !isStale {
                    return false
                }
            }
        }

        let path = originalURL.standardizedFileURL.path
        return fileManager.fileExists(atPath: path) && fileManager.isReadableFile(atPath: path)
    }

    private func resolveFileURLsForTransfer(_ item: ClipboardItem) -> (urls: [URL], stopAccess: () -> Void) {
        if let protectedURLs = protectedFileURLs(for: item) {
            return (
                urls: protectedURLs,
                stopAccess: {}
            )
        }

        return resolveSourceFileURLsForTransfer(item)
    }

    private func resolveSourceFileURLsForTransfer(_ item: ClipboardItem) -> (urls: [URL], stopAccess: () -> Void) {
        let originalURLs = item.fileURLs
        let bookmarks = item.fileSecurityScopedBookmarks

        var resolvedURLs: [URL] = []
        var scopedURLs: [URL] = []
        resolvedURLs.reserveCapacity(originalURLs.count)

        for (index, originalURL) in originalURLs.enumerated() {
            var candidateURL = originalURL

            if index < bookmarks.count,
               let bookmarkData = bookmarks[index] {
                var isStale = false
                if let scopedURL = try? URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ) {
                    candidateURL = scopedURL.standardizedFileURL
                }
            }

            if candidateURL.startAccessingSecurityScopedResource() {
                scopedURLs.append(candidateURL)
            }
            resolvedURLs.append(candidateURL)
        }

        return (
            urls: resolvedURLs,
            stopAccess: {
                for url in scopedURLs.reversed() {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        )
    }

    private func filePresentationMetadata(for item: ClipboardItem) -> FilePresentationSupport.Metadata? {
        guard item.kind == .file else { return nil }
        guard item.fileDisplayNames.count == 1 else { return nil }

        if let cached = filePresentationCache[item.id] {
            return cached
        }

        let resolved = resolveFileURLsForTransfer(item)
        defer { resolved.stopAccess() }

        guard let url = resolved.urls.first else { return nil }
        let fallbackName = item.fileDisplayNames.first ?? url.lastPathComponent
        let metadata = FilePresentationSupport.makeMetadata(
            for: url,
            fallbackDisplayName: fallbackName
        )
        filePresentationCache[item.id] = metadata
        return metadata
    }

    private func handleRemovedItemsAffectingPreview(_ items: [ClipboardItem]) {
        let removedIDs = Set(items.map(\.id))

        if let previewItemID = fullPreviewContent?.itemID ?? fullPreviewUnavailableState?.itemID,
           removedIDs.contains(previewItemID) {
            clearFullPreviewPresentationState()
            updateAuxiliaryPanelPresentation()
        }

        if let dormantStackItemID = appState.dormantStackItemID,
           removedIDs.contains(dormantStackItemID) {
            appState.dormantStackItemID = currentStackHistoryItem()?.id
        }
    }

    private func removeImageCache(for items: [ClipboardItem]) {
        for item in items {
            guard let relativePath = item.imageAssetRelativePath else { continue }
            imagePreviewCache.removeObject(forKey: relativePath as NSString)
        }
    }

    private func removeFileAvailabilityCache(for items: [ClipboardItem]) {
        for item in items {
            fileAvailabilityCache.removeValue(forKey: item.id)
        }
    }

    private func removeFilePresentationCache(for items: [ClipboardItem]) {
        for item in items {
            filePresentationCache.removeValue(forKey: item.id)
        }
    }

    private func invalidateFileAvailabilityCache(for itemIDs: [ClipboardItem.ID]) {
        for itemID in itemIDs {
            fileAvailabilityCache.removeValue(forKey: itemID)
        }
    }

    private func invalidateFilePresentationCache(for itemIDs: [ClipboardItem.ID]) {
        for itemID in itemIDs {
            filePresentationCache.removeValue(forKey: itemID)
        }
    }

    private func protectExistingFavoriteFilesIfNeeded() async {
        let itemsNeedingProtection = appState.history.filter {
            $0.kind == .file && $0.isFavorite && !$0.hasProtectedFileCopies
        }

        for item in itemsNeedingProtection {
            guard let currentItem = appState.item(withID: item.id),
                  currentItem.isFavorite,
                  currentItem.kind == .file,
                  !currentItem.hasProtectedFileCopies else {
                continue
            }

            materializeProtectedFileFavorite(for: currentItem, showsNotice: false)
        }
    }

    private func createSecurityScopedBookmarks(for urls: [URL]) -> [Data?] {
        urls.map { url in
            do {
                return try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                return nil
            }
        }
    }
}
