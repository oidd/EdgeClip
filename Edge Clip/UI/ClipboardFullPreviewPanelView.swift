import AppKit
import Combine
import CryptoKit
import PDFKit
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private enum FullPreviewLocalizationSupport {
    nonisolated static func localized(_ key: String) -> String {
        AppLocalization.localized(key)
    }

    nonisolated static func indexedStackEntryTitle(_ index: Int) -> String {
        if AppLocalization.isEnglish {
            return "Item \(index)"
        }
        return "第 \(index) 条"
    }

    nonisolated static func pageTitle(_ index: Int) -> String {
        if AppLocalization.isEnglish {
            return "Page \(index)"
        }
        return "第 \(index) 页"
    }

    nonisolated static func sheetTitle(_ index: Int) -> String {
        if AppLocalization.isEnglish {
            return "Sheet \(index)"
        }
        return "表 \(index)"
    }

    nonisolated static func pendingPasteSummary(total: Int, orderTitle: String) -> String {
        if AppLocalization.isEnglish {
            return total == 1 ? "1 pending paste · \(orderTitle)" : "\(total) pending pastes · \(orderTitle)"
        }
        return total == 1 ? "1 条待粘贴 · \(orderTitle)" : "\(total) 条待粘贴 · \(orderTitle)"
    }

    nonisolated static func itemAndCharacterSummary(itemCount: Int, characterCount: Int) -> String {
        if AppLocalization.isEnglish {
            let itemText = itemCount == 1 ? "1 item" : "\(itemCount) items"
            let charText = characterCount == 1 ? "1 character" : "\(characterCount) characters"
            return "\(itemText) · \(charText)"
        }
        return "\(itemCount) 条 · 共 \(characterCount) 字符"
    }

    nonisolated static func projectCount(_ count: Int) -> String {
        if AppLocalization.isEnglish {
            return count == 1 ? "1 item" : "\(count) items"
        }
        return "\(count) 个项目"
    }

    nonisolated static func generatedItemEstimate(_ count: Int) -> String {
        if AppLocalization.isEnglish {
            return count == 0 ? "No generated items yet" : "Estimated \(count) items"
        }
        return count == 0 ? "尚未生成可插入项" : "预计生成 \(count) 项"
    }

    nonisolated static func characterCountLabel(_ count: Int, prefix: String? = nil) -> String {
        let resolvedPrefix = prefix ?? AppLocalization.localized("当前")
        if AppLocalization.isEnglish {
            return count == 1 ? "\(resolvedPrefix) 1 character" : "\(resolvedPrefix) \(count) characters"
        }
        return "\(resolvedPrefix) \(count) 字符"
    }

    nonisolated static func visibleItemsFootnote(_ count: Int) -> String {
        if AppLocalization.isEnglish {
            return "Showing the first \(count) items only."
        }
        return "仅展示前 \(count) 项内容。"
    }

    nonisolated static func metadataCountSubtitle(kindLabel: String, count: Int) -> String {
        if AppLocalization.isEnglish {
            return "\(kindLabel) · \(count) items"
        }
        return "\(kindLabel) · \(count)项"
    }
}

private func sidePanelSelectedControlFillColor(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color.accentColor.opacity(0.24)
        : Color.black.opacity(0.72)
}

private func sidePanelSelectedControlStrokeColor(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color.accentColor.opacity(0.52)
        : Color.black.opacity(0.10)
}

private let sidePanelSelectedControlForegroundColor: Color = .white

struct ClipboardFullPreviewPanelView: View {
    @ObservedObject var services: AppServices
    @ObservedObject var appState: AppState
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private func localized(_ key: String) -> String {
        FullPreviewLocalizationSupport.localized(key)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                Divider()
                    .overlay(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))

                previewBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let favoriteEditorConfirmation = services.favoriteEditorConfirmation,
               appState.isFavoriteEditorPresented {
                favoriteEditorConfirmationOverlay(favoriteEditorConfirmation)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.74))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.09), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            syncImagePreviewModeWithCurrentImage()
        }
        .onChange(of: currentImagePreviewIdentity) { _, _ in
            syncImagePreviewModeWithCurrentImage()
        }
    }

    private func favoriteEditorConfirmationOverlay(
        _ state: AppServices.FavoriteEditorConfirmationState
    ) -> some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.30 : 0.12)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(localized(state.title))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.96))

                Text(localized(state.message))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    ForEach(state.buttons) { button in
                        Button {
                            services.resolveFavoriteEditorConfirmation(button.intent)
                        } label: {
                            Text(localized(button.title))
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                        }
                        .buttonStyle(FavoriteEditorConfirmationButtonStyle(
                            style: button.style,
                            colorScheme: colorScheme
                        ))
                    }
                }
            }
            .padding(18)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? Color(red: 0.14, green: 0.15, blue: 0.17).opacity(0.98) : Color.white.opacity(0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10), radius: 24, y: 10)
        }
        .transition(.opacity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized(currentTitle))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Text(localized(subtitleText))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(appState.isStackProcessorPresented ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            if !appState.isStackProcessorPresented,
               !appState.isFavoriteEditorPresented,
               let content = services.fullPreviewContent,
               services.fullPreviewSupportsItemNavigation {
                previewNavigationButton(symbol: "chevron.left", disabled: !services.canShowPreviousFullPreviewItem) {
                    services.showPreviousFullPreviewItem()
                }

                Text("\(content.currentIndex + 1) / \(content.items.count)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44)

                previewNavigationButton(symbol: "chevron.right", disabled: !services.canShowNextFullPreviewItem) {
                    services.showNextFullPreviewItem()
                }
            }

            if !appState.isFavoriteEditorPresented && services.canImportPreviewTextToStack {
                previewNavigationButton(disabled: false, action: {
                    services.importCurrentPreviewTextToStack()
                }) {
                    StackGlyphIcon(isSelected: true)
                        .frame(width: StackGlyphIcon.toolbarSize, height: StackGlyphIcon.toolbarSize)
                }
                .help(localized("把当前文本加入堆栈"))
            }

            if showsImagePreviewModeControl {
                imagePreviewModeControl
            }

            if services.canOpenCurrentPreviewInFinder {
                finderOpenButton
            }

            previewNavigationButton(symbol: "xmark", disabled: false, action: onClose)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var previewBody: some View {
        if appState.isStackProcessorPresented {
            VStack(spacing: 0) {
                StackProcessorContentView(services: services, appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        } else if appState.isFavoriteEditorPresented {
            VStack(spacing: 0) {
                FavoriteSnippetEditorContentView(services: services, appState: appState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        } else if let unavailable = services.fullPreviewUnavailableState {
            VStack(spacing: 0) {
                PreviewUnavailableView(
                    title: "当前记录暂时无法完整预览",
                    message: unavailable.message
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        } else if let content = services.fullPreviewContent,
                  content.kind == .stack {
            VStack(spacing: 0) {
                StackCollectionPreviewContentView(content: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        } else if let content = services.fullPreviewContent,
                  content.kind == .file {
            VStack(spacing: 0) {
                FilePreviewContainerView(services: services, content: content)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        } else if let currentItem = services.fullPreviewCurrentItem {
            VStack(spacing: 0) {
                if let textContent = currentItem.textContent {
                    TextPreviewContentView(
                        payload: services.currentTextPreviewPayload,
                        text: textContent,
                        showsPartialNotice: services.fullPreviewContent?.kind == .passthroughText
                    )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let url = currentItem.url,
                          services.fullPreviewContent?.kind == .image {
                    ImagePreviewContentView(
                        url: url,
                        payload: currentImagePreviewPayload,
                        layoutMode: appState.imagePreviewLayoutMode
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let url = currentItem.url {
                    FilePreviewContentView(
                        url: url,
                        securityScopedBookmarkData: currentItem.securityScopedBookmarkData
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PreviewUnavailableView(
                        title: "当前项目不可预览",
                        message: "这条记录当前没有可展示的完整内容。"
                    )
                }

                footer
            }
        } else {
            PreviewUnavailableView(
                title: "当前项目不可预览",
                message: "文件可能已经失效，或系统当前无法为它生成 Quick Look 预览。"
            )
        }
    }

    private var footer: some View {
        HStack {
            Text(localized(footerLeadingText))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            if let trailingText = footerTrailingText {
                Text(localized(trailingText))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03))
    }

    private func previewNavigationButton(symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        previewNavigationButton(disabled: disabled, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary.opacity(0.55) : Color.primary)
        }
    }

    private func previewNavigationButton<Content: View>(
        disabled: Bool,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(disabled ? 0.05 : (colorScheme == .dark ? 0.12 : 0.06)))
                )
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var finderOpenButton: some View {
        Button(action: services.openCurrentPreviewInFinder) {
            Label(localized("在访达中打开"), systemImage: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var currentTitle: String {
        if appState.isStackProcessorPresented {
            return localized("数据处理")
        }
        if appState.isFavoriteEditorPresented {
            return localized(appState.activeFavoriteSnippetID == nil ? "新增收藏" : "编辑收藏")
        }
        if services.fullPreviewUnavailableState != nil {
            return localized("完整预览")
        }
        if let content = services.fullPreviewContent,
           content.kind == .stack {
            return localized("堆栈预览")
        }
        if let content = services.fullPreviewContent,
           content.kind == .file,
           services.fullPreviewUsesFileOverview {
            return fileOverviewTitle(for: content)
        }
        return services.fullPreviewCurrentItem?.displayName ?? localized("完整预览")
    }

    private var subtitleText: String {
        if appState.isStackProcessorPresented {
            return localized("按分隔符自动拆分文本并同步到右侧堆栈")
        }
        if appState.isFavoriteEditorPresented {
            return localized("在收藏库中维护可直接回填的常用文本")
        }
        if let unavailable = services.fullPreviewUnavailableState {
            return compactPreviewCategoryLabel(for: unavailable.kind, items: [])
        }
        guard let content = services.fullPreviewContent else {
            return localized("预览")
        }

        if content.kind == .stack {
            return stackPreviewSubtitle(for: content)
        }

        return compactPreviewCategoryLabel(for: content.kind, items: content.items)
    }

    private var footerLeadingText: String {
        if appState.isStackProcessorPresented {
            return localized("编辑并拆分文本后，可手动写入右侧堆栈")
        }
        if appState.isFavoriteEditorPresented {
            return localized("保存后会更新左侧收藏列表，不会写入普通历史记录")
        }
        if services.fullPreviewUnavailableState != nil {
            return localized("当前记录暂时无法完整预览，空格或 Esc 可关闭")
        }
        if let content = services.fullPreviewContent,
           content.kind == .stack {
            return localized("空格或 Esc 可关闭")
        }
        return localized("空格或 Esc 可关闭预览")
    }

    private var footerTrailingText: String? {
        if services.fullPreviewUnavailableState != nil {
            return nil
        }
        if appState.isStackProcessorPresented {
            let count = services.stackProcessorPreviewCount
            return FullPreviewLocalizationSupport.generatedItemEstimate(count)
        }
        if appState.isFavoriteEditorPresented {
            let count = appState.favoriteEditorDraft.count
            if count == 0 {
                return localized("尚未输入内容")
            }
            return FullPreviewLocalizationSupport.characterCountLabel(count)
        }
        guard let content = services.fullPreviewContent else { return nil }
        if services.fullPreviewUsesFileOverview {
            return localized("点按项目可在访达中定位")
        }
        if content.kind == .stack {
            let totalCharacters = content.items.reduce(0) { partial, item in
                partial + (item.textContent?.count ?? 0)
            }
            return FullPreviewLocalizationSupport.itemAndCharacterSummary(
                itemCount: content.items.count,
                characterCount: totalCharacters
            )
        }
        if content.kind == .image {
            return imagePreviewFooterHint
        }
        if content.items.count > 1 {
            return localized("左右方向键可切换")
        }
        if case .text = content.kind {
            return nil
        }
        if case .passthroughText = content.kind {
            return nil
        }
        return nil
    }

    private func stackPreviewSubtitle(for content: AppServices.FullPreviewContent) -> String {
        let total = content.items.count
        guard total > 0 else { return localized("空堆栈") }
        let orderTitle = appState.item(withID: content.itemID)?.stackOrderMode.title ?? services.currentStackOrderMode.title

        return FullPreviewLocalizationSupport.pendingPasteSummary(total: total, orderTitle: orderTitle)
    }

    private func fileOverviewTitle(for content: AppServices.FullPreviewContent) -> String {
        if content.items.count > 1 {
            return FullPreviewLocalizationSupport.projectCount(content.items.count)
        }
        return content.items.first?.displayName ?? localized("文件夹")
    }

    private func compactPreviewCategoryLabel(
        for kind: ClipboardItem.ContentKind,
        items: [AppServices.FullPreviewContent.Item]
    ) -> String {
        switch kind {
        case .image:
            return localized("图片")
        case .file:
            let containsItems = !items.isEmpty
            let allFolders = containsItems && items.allSatisfy { $0.filePresentation?.isFolder == true }
            return localized(allFolders ? "文件夹" : "文件")
        case .text, .passthroughText:
            return localized("文本")
        case .stack:
            return localized("堆栈")
        }
    }

    private var showsImagePreviewModeControl: Bool {
        !appState.isStackProcessorPresented &&
        !appState.isFavoriteEditorPresented &&
        services.fullPreviewUnavailableState == nil &&
        currentImagePreviewURL != nil
    }

    private var currentImagePreviewURL: URL? {
        guard services.fullPreviewContent?.kind == .image else { return nil }
        return services.fullPreviewCurrentItem?.url
    }

    private var currentImagePreviewIdentity: String {
        currentImagePreviewURL?.standardizedFileURL.path ?? "no-image"
    }

    private var currentImagePreviewPayload: ClipboardItem.ImagePayload? {
        guard let itemID = services.fullPreviewContent?.itemID else { return nil }
        return appState.item(withID: itemID)?.imagePayload
    }

    private var imagePreviewFooterHint: String {
        switch (appState.imagePreviewLayoutMode, appState.imagePreviewWidthTier) {
        case (.fit, .standard):
            return localized("完整看图，再点「全览」可展开")
        case (.fit, .expanded):
            return localized("完整看图，再点「全览」可收起")
        case (.fitWidth, .standard):
            return localized("细看内容，再点「细节」可展开")
        case (.fitWidth, .expanded):
            return localized("细看内容，再点「细节」可收起")
        }
    }

    private var imagePreviewModeControl: some View {
        HStack(spacing: 4) {
            ForEach(ImagePreviewLayoutMode.allCases, id: \.self) { mode in
                let isSelected = appState.imagePreviewLayoutMode == mode
                Button {
                    appState.selectImagePreviewLayoutMode(mode)
                } label: {
                    HStack(spacing: 6) {
                        Text(mode.title)
                            .font(.system(size: 12, weight: .semibold))

                        if isSelected {
                            Image(systemName: appState.imagePreviewWidthTier.badgeSymbolName)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.secondary)
                                .frame(width: 15, height: 15)
                                .background(
                                    Circle()
                                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08))
                                )
                        }
                    }
                    .foregroundStyle(
                        isSelected
                            ? Color.primary
                            : Color.secondary
                    )
                    .padding(.horizontal, isSelected ? 11 : 12)
                    .frame(minWidth: 58)
                    .frame(height: 28)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                isSelected
                                    ? Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10)
                                    : Color.clear
                            )
                    )
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.05))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
        )
    }

    private func syncImagePreviewModeWithCurrentImage() {
        appState.setDefaultImagePreviewLayoutMode(Self.defaultImagePreviewMode(for: currentImagePreviewPayload))
    }

    private static func defaultImagePreviewMode(
        for payload: ClipboardItem.ImagePayload?
    ) -> ImagePreviewLayoutMode {
        guard let payload,
              payload.pixelWidth > 0,
              payload.pixelHeight > 0 else {
            return .fit
        }

        let aspectRatio = CGFloat(payload.pixelHeight) / CGFloat(payload.pixelWidth)
        if payload.pixelHeight >= 2_400, aspectRatio >= 1.95 {
            return .fitWidth
        }

        if payload.pixelHeight >= 4_000, aspectRatio >= 1.6 {
            return .fitWidth
        }

        return .fit
    }
}

private struct PreviewUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text(FullPreviewLocalizationSupport.localized(title))
                .font(.system(size: 14, weight: .semibold))

            Text(FullPreviewLocalizationSupport.localized(message))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct ImagePreviewContentView: View {
    let url: URL
    let payload: ClipboardItem.ImagePayload?
    let layoutMode: ImagePreviewLayoutMode

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = ImagePreviewContentModel()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.035))

                content(in: proxy.size)
                    .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: url.standardizedFileURL.path) {
            await model.load(from: url)
        }
        .onDisappear {
            model.clear()
        }
    }

    @ViewBuilder
    private func content(in availableSize: CGSize) -> some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView("正在准备图片预览…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            PreviewUnavailableView(
                title: "当前图片暂时无法载入",
                message: "图片资源可能已经失效，或本地预览文件已被删除。"
            )
        case .loaded(let image):
            let aspectRatio = resolvedAspectRatio(for: image)
            if layoutMode == .fitWidth {
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        RoundedPreviewImageView(image: image)
                            .aspectRatio(aspectRatio, contentMode: .fit)
                            .frame(
                                width: max(availableSize.width - 36, 1),
                                alignment: .top
                            )
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                let imageSize = fittedImageSize(
                    for: aspectRatio,
                    in: CGSize(
                        width: max(availableSize.width - 36, 1),
                        height: max(availableSize.height - 36, 1)
                    )
                )
                RoundedPreviewImageView(image: image)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(width: imageSize.width, height: imageSize.height, alignment: .center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func resolvedAspectRatio(for image: NSImage) -> CGFloat {
        if let payload,
           payload.pixelWidth > 0,
           payload.pixelHeight > 0 {
            return CGFloat(payload.pixelWidth) / CGFloat(payload.pixelHeight)
        }

        let size = image.size
        guard size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private func fittedImageSize(for aspectRatio: CGFloat, in bounds: CGSize) -> CGSize {
        let boundedWidth = max(bounds.width, 1)
        let boundedHeight = max(bounds.height, 1)
        let boundedAspectRatio = boundedWidth / boundedHeight

        if aspectRatio >= boundedAspectRatio {
            return CGSize(width: boundedWidth, height: max(1, boundedWidth / aspectRatio))
        }

        return CGSize(width: max(1, boundedHeight * aspectRatio), height: boundedHeight)
    }
}

private struct RoundedPreviewImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> RoundedPreviewImageContainerView {
        let container = RoundedPreviewImageContainerView()
        container.update(image: image)
        return container
    }

    func updateNSView(_ nsView: RoundedPreviewImageContainerView, context: Context) {
        nsView.update(image: image)
    }
}

private final class RoundedPreviewImageContainerView: NSView {
    private let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = bounds
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func update(image: NSImage) {
        imageView.image = image
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
    }
}

@MainActor
private final class ImagePreviewContentModel: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded(NSImage)
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    private var currentPath: String?
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

    func load(from url: URL) async {
        let path = url.standardizedFileURL.path
        guard currentPath != path || isIdle else { return }
        currentPath = path

        let cacheKey = path as NSString
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            phase = .loaded(cachedImage)
            return
        }

        let shouldKeepCurrentImageVisible: Bool
        if case .loaded = phase {
            shouldKeepCurrentImageVisible = true
        } else {
            shouldKeepCurrentImageVisible = false
        }
        if !shouldKeepCurrentImageVisible {
            phase = .loading
        }

        let image = await Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }.value

        guard !Task.isCancelled else { return }
        guard currentPath == path else { return }
        if let image {
            Self.imageCache.setObject(image, forKey: cacheKey)
            phase = .loaded(image)
        } else {
            phase = .failed
        }
    }

    func clear() {
        currentPath = nil
        phase = .idle
    }

    private var isIdle: Bool {
        if case .idle = phase {
            return true
        }
        return false
    }
}

private struct TextPreviewContentView: View {
    let payload: ClipboardItem.TextPayload?
    let text: String
    var showsPartialNotice: Bool = false
    @State private var isScrolledToBottom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = previewNotice {
                TopPinnedPreviewNoticeView(message: notice)
            }

            ZStack(alignment: .bottom) {
                ReadOnlyTextPreviewView(
                    text: text,
                    usesMonospacedFont: payload?.isTabular ?? false,
                    bottomContentInset: showsOmissionNotice ? 56 : 0,
                    onScrolledToBottomChanged: showsOmissionNotice ? { isScrolledToBottom = $0 } : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if showsOmissionNotice && isScrolledToBottom {
                    BottomPinnedPreviewNoticeView(message: "预览到此结束，后续内容未展示")
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.015))
        .onChange(of: text) { _, _ in
            isScrolledToBottom = false
        }
        .onChange(of: showsOmissionNotice) { _, newValue in
            if !newValue {
                isScrolledToBottom = false
            }
        }
    }

    private var previewNotice: String? {
        if showsPartialNotice {
            return FullPreviewLocalizationSupport.localized("仅显示部分内容作为预览，文本可以正常粘贴")
        }
        guard let payload, payload.hasTruncatedPreview else { return nil }
        return FullPreviewLocalizationSupport.localized("仅显示部分内容作为预览，文本可以正常粘贴")
    }

    private var showsOmissionNotice: Bool {
        if showsPartialNotice {
            return true
        }
        guard let payload else { return false }
        return payload.hasTruncatedPreview
    }
}

private struct StackCollectionPreviewContentView: View {
    let content: AppServices.FullPreviewContent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(content.items.enumerated()), id: \.element.id) { offset, item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(offset == 0 ? FullPreviewLocalizationSupport.localized("下一条") : FullPreviewLocalizationSupport.indexedStackEntryTitle(offset + 1))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)
                        }

                        Text(item.textContent ?? "")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.96))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                    if offset < content.items.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(height: 1)
                            .padding(.horizontal, 18)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.015))
    }
}

private struct TopPinnedPreviewNoticeView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(FullPreviewLocalizationSupport.localized(message))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .textSelection(.disabled)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BottomPinnedPreviewNoticeView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(FullPreviewLocalizationSupport.localized(message))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .textSelection(.disabled)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownDocumentPreviewView: View {
    let artifact: HTMLPreviewArtifact

    var body: some View {
        HTMLDocumentPreviewView(artifact: artifact)
    }
}

private struct PlainTextDocumentPreviewView: View {
    let artifact: PlainTextPreviewArtifact

    var body: some View {
        ReadOnlyTextPreviewView(
            text: artifact.text,
            usesMonospacedFont: artifact.usesMonospacedFont
        )
            .padding(18)
            .background(Color.primary.opacity(0.015))
    }
}

private struct StackProcessorContentView: View {
    @ObservedObject var services: AppServices
    @ObservedObject var appState: AppState

    @Environment(\.colorScheme) private var colorScheme

    private func localized(_ key: String) -> String {
        FullPreviewLocalizationSupport.localized(key)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localized("输入文本"))
                        .font(.system(size: 13, weight: .semibold))

                    TextEditor(
                        text: Binding(
                            get: { appState.stackProcessorDraft },
                            set: { services.updateStackProcessorDraft($0) }
                        )
                    )
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 188, maxHeight: 188)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(localized("拆分规则"))
                        .font(.system(size: 13, weight: .semibold))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(StackDelimiterOption.allCases, id: \.self) { option in
                            let isSelected = appState.stackDelimiterOptions.contains(option)
                            Button {
                                services.toggleStackDelimiter(option)
                            } label: {
                                Text(option.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isSelected ? selectionForegroundColor : defaultControlForegroundColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                    .padding(.horizontal, 12)
                                    .frame(height: 32)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(
                                                isSelected
                                                    ? selectedControlFillColor
                                                    : defaultControlFillColor
                                            )
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .stroke(
                                                isSelected
                                                    ? selectedControlStrokeColor
                                                    : defaultControlStrokeColor,
                                                lineWidth: 1
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if appState.stackDelimiterOptions.contains(.custom) {
                        TextField(
                            "输入自定义符号",
                            text: Binding(
                                get: { appState.stackCustomDelimiter },
                                set: { services.updateStackCustomDelimiter($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(FullPreviewLocalizationSupport.characterCountLabel(appState.stackProcessorDraft.count, prefix: localized("原文")))
                        Text(FullPreviewLocalizationSupport.generatedItemEstimate(services.stackProcessorPreviewCount))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                    Text(localized("编辑内容后不会自动覆盖右侧堆栈，只有点击下方按钮才会写入。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        processorActionButton(
                            title: AppServices.StackProcessorApplyMode.insertAbove.title,
                            fill: defaultControlFillColor,
                            stroke: defaultControlStrokeColor,
                            foreground: defaultControlForegroundColor,
                            mode: .insertAbove
                        )

                        processorActionButton(
                            title: AppServices.StackProcessorApplyMode.insertBelow.title,
                            fill: defaultControlFillColor,
                            stroke: defaultControlStrokeColor,
                            foreground: defaultControlForegroundColor,
                            mode: .insertBelow
                        )
                    }

                    processorActionButton(
                        title: AppServices.StackProcessorApplyMode.replace.title,
                        fill: selectedControlFillColor,
                        stroke: selectedControlStrokeColor,
                        foreground: selectionForegroundColor,
                        mode: .replace
                    )
                }
            }
            .padding(18)
        }
        .background(Color.primary.opacity(0.015))
    }

    private var selectedControlFillColor: Color {
        sidePanelSelectedControlFillColor(colorScheme)
    }

    private var selectedControlStrokeColor: Color {
        sidePanelSelectedControlStrokeColor(colorScheme)
    }

    private var defaultControlFillColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05)
    }

    private var defaultControlStrokeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08)
    }

    private var defaultControlForegroundColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.82 : 0.86)
    }

    private var selectionForegroundColor: Color {
        sidePanelSelectedControlForegroundColor
    }

    private func processorActionButton(
        title: String,
        fill: Color,
        stroke: Color,
        foreground: Color,
        mode: AppServices.StackProcessorApplyMode
    ) -> some View {
        Button {
            services.applyStackProcessorDraft(mode, closePanelAfterApply: true)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(foreground.opacity(services.canApplyStackProcessorDraft ? 1 : 0.45))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(fill.opacity(services.canApplyStackProcessorDraft ? 1 : 0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!services.canApplyStackProcessorDraft)
    }
}

private struct FavoriteSnippetEditorContentView: View {
    @ObservedObject var services: AppServices
    @ObservedObject var appState: AppState

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isEditorFocused: Bool

    private func localized(_ key: String) -> String {
        FullPreviewLocalizationSupport.localized(key)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localized("收藏文本"))
                        .font(.system(size: 13, weight: .semibold))

                    TextEditor(
                        text: Binding(
                            get: { appState.favoriteEditorDraft },
                            set: { services.updateFavoriteEditorDraft($0) }
                        )
                    )
                    .font(.system(size: 14))
                    .focused($isEditorFocused)
                    .modifier(FavoriteEditorWritingToolsModifier())
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 240, maxHeight: 240)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(FullPreviewLocalizationSupport.characterCountLabel(appState.favoriteEditorDraft.count))
                        if appState.activeFavoriteSnippetID != nil {
                            Text(localized("正在编辑现有收藏"))
                        } else {
                            Text(localized("将创建新的收藏条目"))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                    Text(localized("这里维护的是独立收藏库，不会进入普通剪贴板历史。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Button {
                        services.saveFavoriteSnippetFromEditor()
                    } label: {
                        Text(localized(appState.activeFavoriteSnippetID == nil ? "保存为收藏" : "保存修改"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(sidePanelSelectedControlForegroundColor.opacity(services.canSaveFavoriteSnippetDraft ? 1 : 0.45))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(sidePanelSelectedControlFillColor(colorScheme).opacity(services.canSaveFavoriteSnippetDraft ? 1 : 0.55))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(sidePanelSelectedControlStrokeColor(colorScheme), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!services.canSaveFavoriteSnippetDraft)
                }
            }
            .padding(18)
        }
        .background(Color.primary.opacity(0.015))
        .onAppear {
            requestEditorFocus()
        }
        .onChange(of: appState.activeFavoriteSnippetID) { _, _ in
            requestEditorFocus()
        }
        .onChange(of: services.favoriteEditorConfirmation != nil) { _, isPresentingConfirmation in
            if !isPresentingConfirmation {
                requestEditorFocus()
            }
        }
    }

    private func requestEditorFocus() {
        DispatchQueue.main.async {
            isEditorFocused = true
        }
    }
}

private struct FavoriteEditorWritingToolsModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.writingToolsBehavior(.disabled)
        } else {
            content
        }
    }
}

private struct FavoriteEditorConfirmationButtonStyle: ButtonStyle {
    let style: AppServices.FavoriteEditorConfirmationButton.Style
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color
        let stroke: Color
        let foreground: Color

        switch style {
        case .accent:
            fill = sidePanelSelectedControlFillColor(colorScheme).opacity(configuration.isPressed ? 0.88 : 1)
            stroke = sidePanelSelectedControlStrokeColor(colorScheme)
            foreground = sidePanelSelectedControlForegroundColor
        case .secondary:
            fill = Color.primary.opacity(colorScheme == .dark ? (configuration.isPressed ? 0.14 : 0.10) : (configuration.isPressed ? 0.09 : 0.06))
            stroke = Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08)
            foreground = Color.primary.opacity(0.92)
        case .destructive:
            fill = Color.red.opacity(colorScheme == .dark ? (configuration.isPressed ? 0.20 : 0.16) : (configuration.isPressed ? 0.12 : 0.08))
            stroke = Color.red.opacity(0.34)
            foreground = Color.red.opacity(0.96)
        }

        return configuration.label
            .foregroundStyle(foreground.opacity(configuration.isPressed ? 0.92 : 1))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}

private struct FilePreviewContainerView: View {
    let services: AppServices
    let content: AppServices.FullPreviewContent

    var body: some View {
        if content.items.count > 1 ||
            content.items.first?.filePresentation?.isFolder == true {
            FileCollectionPreviewContentView(services: services, items: content.items)
        } else if let currentItem = content.items.first,
                  let url = currentItem.url {
            FilePreviewContentView(
                url: url,
                securityScopedBookmarkData: currentItem.securityScopedBookmarkData
            )
        } else {
            PreviewUnavailableView(
                title: "当前文件暂时无法内嵌预览",
                message: "这条文件记录当前没有可展示的内容。"
            )
        }
    }
}

private struct FileCollectionPreviewContentView: View {
    let services: AppServices
    let items: [AppServices.FullPreviewContent.Item]

    @StateObject private var model = FileCollectionOverviewModel()

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView("正在准备项目概览…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .rendered(let artifact):
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 18) {
                        summaryCard(for: artifact)

                        LazyVStack(spacing: 10) {
                            ForEach(artifact.entries) { entry in
                                overviewEntryButton(entry)
                            }
                        }

                        if let footnote = artifact.footnote {
                            Text(footnote)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                }
            case .failed(let message):
                PreviewUnavailableView(
                    title: "当前项目暂时无法生成概览",
                    message: message
                )
            }
        }
        .task(id: previewKey) {
            await model.load(items: items)
        }
        .onDisappear {
            model.clear()
        }
    }

    private var previewKey: String {
        items.map(\.id).joined(separator: "|")
    }

    private func summaryCard(for artifact: FileCollectionOverviewArtifact) -> some View {
        PreviewOverviewCard(title: "内容概览") {
            if !artifact.badges.isEmpty {
                PreviewBadgeFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(artifact.badges) { badge in
                        PreviewBadgeChip(title: badge.title, value: badge.value)
                    }
                }
            }
        }
    }

    private func overviewEntryButton(_ entry: FileCollectionOverviewArtifact.Entry) -> some View {
        let iconStyle = PreviewEntryIconSupport.style(
            title: entry.title,
            kindLabel: entry.kindLabel,
            isFolder: entry.isFolder
        )
        return Button {
            services.revealFileInFinder(
                url: entry.url,
                securityScopedBookmarkData: entry.securityScopedBookmarkData
            )
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconStyle.symbolName)
                    .font(.system(size: iconStyle.fontSize, weight: .semibold))
                    .foregroundStyle(iconStyle.tint)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.96))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)

                    Text(entry.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ArchivePreviewContentView: View {
    let artifact: ArchivePreviewArtifact

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard

                if artifact.entries.isEmpty {
                    Text(FullPreviewLocalizationSupport.localized(artifact.footnote ?? "压缩包内没有可展示的项目。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(artifact.entries) { entry in
                            archiveEntryRow(entry)
                        }
                    }
                }

                if !artifact.entries.isEmpty, let footnote = artifact.footnote {
                    Text(footnote)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
    }

    private var summaryCard: some View {
        PreviewOverviewCard(title: "内容概览") {
            if !artifact.badges.isEmpty {
                PreviewBadgeFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(artifact.badges) { badge in
                        PreviewBadgeChip(title: badge.title, value: badge.value)
                    }
                }
            }
        }
    }

    private func archiveEntryRow(_ entry: ArchivePreviewArtifact.Entry) -> some View {
        let iconStyle = PreviewEntryIconSupport.style(
            title: entry.title,
            kindLabel: entry.kindLabel,
            isFolder: entry.isFolder
        )
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconStyle.symbolName)
                .font(.system(size: iconStyle.fontSize, weight: .semibold))
                .foregroundStyle(iconStyle.tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06))
                )

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.96))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                Text(entry.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

}

private struct DiskImagePreviewContentView: View {
    let artifact: DiskImagePreviewArtifact

    var body: some View {
        VStack(spacing: 0) {
            PreviewOverviewCard(title: "安装包信息") {
                PreviewBadgeFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(artifact.badges) { badge in
                        PreviewBadgeChip(title: badge.title, value: badge.value)
                    }
                }
            }
            .padding(18)

            VStack {
                Spacer(minLength: 0)
                Image(nsImage: Self.diskImageIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .shadow(color: Color.black.opacity(0.06), radius: 14, y: 6)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let diskImageIcon: NSImage = {
        let diskImageType = UTType(filenameExtension: "dmg") ?? .data
        return NSWorkspace.shared.icon(for: diskImageType)
    }()
}

private struct PreviewBadgeChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(FullPreviewLocalizationSupport.localized(title))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .foregroundStyle(Color.primary.opacity(0.92))
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

private struct PreviewOverviewCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(FullPreviewLocalizationSupport.localized(title), systemImage: "square.grid.2x2")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(colorScheme == .dark ? 0.96 : 0.9))

            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentColor.opacity(colorScheme == .dark ? 0.26 : 0.14), lineWidth: 1)
        )
    }
}

private struct PreviewBadgeFlowLayout<Content: View>: View {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        PreviewWrappingLayout(horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing) {
            content
        }
    }
}

private struct PreviewWrappingLayout: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        let containerWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedRowWidth = currentRowWidth == 0 ? size.width : currentRowWidth + horizontalSpacing + size.width

            if proposedRowWidth > containerWidth, currentRowWidth > 0 {
                maxRowWidth = max(maxRowWidth, currentRowWidth)
                totalHeight += currentRowHeight + verticalSpacing
                currentRowWidth = size.width
                currentRowHeight = size.height
            } else {
                currentRowWidth = proposedRowWidth
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }

        maxRowWidth = max(maxRowWidth, currentRowWidth)
        if currentRowHeight > 0 {
            totalHeight += currentRowHeight
        }

        return CGSize(width: maxRowWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let exceedsCurrentRow = cursorX > bounds.minX && (cursorX + size.width) > bounds.maxX

            if exceedsCurrentRow {
                cursorX = bounds.minX
                cursorY += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: cursorX, y: cursorY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            cursorX += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

@MainActor
private final class FileCollectionOverviewModel: ObservableObject {
    enum Phase {
        case idle
        case loading
        case rendered(FileCollectionOverviewArtifact)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var currentPreviewKey: String?

    func load(items: [AppServices.FullPreviewContent.Item]) async {
        let previewKey = items.map(\.id).joined(separator: "|")
        guard currentPreviewKey != previewKey || phase.isIdle else { return }
        currentPreviewKey = previewKey
        phase = .loading

        do {
            let artifact = try await Task.detached(priority: .userInitiated) {
                try FileCollectionOverviewArtifact.make(for: items)
            }.value
            guard !Task.isCancelled else { return }
            guard currentPreviewKey == previewKey else { return }
            phase = .rendered(artifact)
        } catch {
            guard !Task.isCancelled else { return }
            guard currentPreviewKey == previewKey else { return }
            phase = .failed(FullPreviewLocalizationSupport.localized("所选项目可能已失效，或当前没有权限读取它们的预览信息。"))
        }
    }

    func clear() {
        currentPreviewKey = nil
        phase = .idle
    }
}

private extension FileCollectionOverviewModel.Phase {
    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

private struct FileCollectionOverviewArtifact: Sendable {
    struct SummaryBadge: Identifiable, Sendable {
        let id: String
        let title: String
        let value: String
    }

    struct Entry: Identifiable, Sendable {
        let id: String
        let url: URL
        let securityScopedBookmarkData: Data?
        let title: String
        let kindLabel: String
        let subtitle: String
        let isFolder: Bool
    }

    let badges: [SummaryBadge]
    let entries: [Entry]
    let footnote: String?

    nonisolated static func make(for items: [AppServices.FullPreviewContent.Item]) throws -> FileCollectionOverviewArtifact {
        if items.count == 1,
           let item = items.first,
           item.filePresentation?.isFolder == true {
            return try makeFolderArtifact(for: item)
        }
        return try makeSelectionArtifact(for: items)
    }

    private nonisolated static func makeSelectionArtifact(
        for items: [AppServices.FullPreviewContent.Item]
    ) throws -> FileCollectionOverviewArtifact {
        let entries = items.compactMap { item -> Entry? in
            guard let url = item.url else { return nil }
            let scoped = scopedURL(for: item, fallbackURL: url)
            defer { scoped.stopAccess() }

            let metadata = item.filePresentation ?? FilePresentationSupport.makeMetadata(
                for: scoped.url,
                fallbackDisplayName: item.displayName
            )
            return Entry(
                id: item.id,
                url: scoped.url,
                securityScopedBookmarkData: item.securityScopedBookmarkData,
                title: metadata.displayName,
                kindLabel: metadata.panelKindLabel,
                subtitle: overviewSubtitle(for: metadata),
                isFolder: metadata.isFolder
            )
        }

        let folderCount = entries.filter(\.isFolder).count
        let fileCount = max(0, entries.count - folderCount)
        return FileCollectionOverviewArtifact(
            badges: [
                SummaryBadge(id: "total", title: FullPreviewLocalizationSupport.localized("总项目"), value: "\(entries.count)"),
                SummaryBadge(id: "folders", title: FullPreviewLocalizationSupport.localized("文件夹"), value: "\(folderCount)"),
                SummaryBadge(id: "files", title: FullPreviewLocalizationSupport.localized("文件"), value: "\(fileCount)")
            ],
            entries: entries,
            footnote: nil
        )
    }

    private nonisolated static func makeFolderArtifact(
        for item: AppServices.FullPreviewContent.Item
    ) throws -> FileCollectionOverviewArtifact {
        guard let url = item.url else {
            throw CocoaError(.fileNoSuchFile)
        }

        let scoped = scopedURL(for: item, fallbackURL: url)
        defer { scoped.stopAccess() }

        let contents = try FileManager.default.contentsOfDirectory(
            at: scoped.url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isPackageKey,
                .localizedTypeDescriptionKey,
                .fileSizeKey,
                .totalFileSizeKey,
                .nameKey
            ],
            options: [.skipsHiddenFiles]
        )

        let sortedContents = contents.sorted {
            let lhsMetadata = FilePresentationSupport.makeMetadata(for: $0, fallbackDisplayName: $0.lastPathComponent)
            let rhsMetadata = FilePresentationSupport.makeMetadata(for: $1, fallbackDisplayName: $1.lastPathComponent)
            if lhsMetadata.isFolder != rhsMetadata.isFolder {
                return lhsMetadata.isFolder && !rhsMetadata.isFolder
            }
            return lhsMetadata.displayName.localizedStandardCompare(rhsMetadata.displayName) == .orderedAscending
        }

        let visibleEntries = Array(sortedContents.prefix(30)).map { childURL -> Entry in
            let metadata = FilePresentationSupport.makeMetadata(
                for: childURL,
                fallbackDisplayName: childURL.lastPathComponent
            )
            return Entry(
                id: childURL.standardizedFileURL.path,
                url: childURL.standardizedFileURL,
                securityScopedBookmarkData: nil,
                title: metadata.displayName,
                kindLabel: metadata.panelKindLabel,
                subtitle: overviewSubtitle(for: metadata),
                isFolder: metadata.isFolder
            )
        }

        let folderCount = sortedContents.reduce(into: 0) { result, childURL in
            if FilePresentationSupport.makeMetadata(for: childURL, fallbackDisplayName: childURL.lastPathComponent).isFolder {
                result += 1
            }
        }
        let fileCount = max(0, sortedContents.count - folderCount)

        return FileCollectionOverviewArtifact(
            badges: [
                SummaryBadge(id: "total", title: FullPreviewLocalizationSupport.localized("可见项目"), value: "\(sortedContents.count)"),
                SummaryBadge(id: "folders", title: FullPreviewLocalizationSupport.localized("文件夹"), value: "\(folderCount)"),
                SummaryBadge(id: "files", title: FullPreviewLocalizationSupport.localized("文件"), value: "\(fileCount)")
            ],
            entries: visibleEntries,
            footnote: sortedContents.count > visibleEntries.count ? FullPreviewLocalizationSupport.visibleItemsFootnote(visibleEntries.count) : nil
        )
    }

    private nonisolated static func overviewSubtitle(for metadata: FilePresentationSupport.Metadata) -> String {
        if metadata.isFolder {
            if let folderItemCount = metadata.folderItemCount {
                return FullPreviewLocalizationSupport.metadataCountSubtitle(
                    kindLabel: metadata.panelKindLabel,
                    count: folderItemCount
                )
            }
            return metadata.panelKindLabel
        }

        if let sizeText = metadata.sizeText, !sizeText.isEmpty {
            return "\(metadata.panelKindLabel) · \(sizeText)"
        }

        return metadata.panelKindLabel
    }

    private nonisolated static func scopedURL(
        for item: AppServices.FullPreviewContent.Item,
        fallbackURL: URL
    ) -> (url: URL, stopAccess: () -> Void) {
        var candidateURL = fallbackURL.standardizedFileURL

        if let bookmarkData = item.securityScopedBookmarkData {
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

        let didStartAccessing = candidateURL.startAccessingSecurityScopedResource()
        return (
            url: candidateURL,
            stopAccess: {
                if didStartAccessing {
                    candidateURL.stopAccessingSecurityScopedResource()
                }
            }
        )
    }
}

private struct FilePreviewContentView: View {
    let url: URL
    let securityScopedBookmarkData: Data?

    @StateObject private var model = FilePreviewContentModel()

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView("正在准备文件预览…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .rendered(let artifact):
                renderedView(for: artifact)
            case .failed(let message):
                PreviewUnavailableView(
                    title: "当前文件暂时无法内嵌预览",
                    message: message
                )
            }
        }
        .task(id: url.standardizedFileURL.path) {
            await model.load(for: url, securityScopedBookmarkData: securityScopedBookmarkData)
        }
        .onDisappear {
            model.clear()
        }
    }

    @ViewBuilder
    private func renderedView(for artifact: FilePreviewArtifact) -> some View {
        switch artifact {
        case .markdown(let markdownArtifact):
            MarkdownDocumentPreviewView(artifact: markdownArtifact)
        case .plainText(let plainTextArtifact):
            PlainTextDocumentPreviewView(artifact: plainTextArtifact)
        case .archive(let archiveArtifact):
            ArchivePreviewContentView(artifact: archiveArtifact)
        case .diskImage(let diskImageArtifact):
            DiskImagePreviewContentView(artifact: diskImageArtifact)
        case .pdf(let pdfURL):
            PDFDocumentPreviewView(url: pdfURL)
        case .quickLookSlides(let slideURL):
            QuickLookSlidesPreviewView(url: slideURL)
        case .html(let htmlArtifact):
            HTMLDocumentPreviewView(artifact: htmlArtifact)
                .id(htmlArtifact.htmlURL.path)
        case .spreadsheet(let sheetArtifact):
            SpreadsheetDocumentPreviewView(artifact: sheetArtifact)
        case .quickLookFallback(let fallbackURL):
            QuickLookPreviewItemView(url: fallbackURL)
        }
    }
}

@MainActor
private final class FilePreviewContentModel: ObservableObject {
    enum Phase {
        case idle
        case loading
        case rendered(FilePreviewArtifact)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var currentSourcePath: String?

    func load(for url: URL, securityScopedBookmarkData: Data?) async {
        let sourcePath = url.standardizedFileURL.path
        guard currentSourcePath != sourcePath || phase.isIdle else { return }
        currentSourcePath = sourcePath
        phase = .loading

        do {
            let artifact = try await FilePreviewExportService.shared.previewArtifact(
                for: url,
                securityScopedBookmarkData: securityScopedBookmarkData
            )
            guard !Task.isCancelled else { return }
            guard currentSourcePath == sourcePath else { return }
            phase = .rendered(artifact)
        } catch {
            guard !Task.isCancelled else { return }
            guard currentSourcePath == sourcePath else { return }
            phase = .rendered(.quickLookFallback(url))
        }
    }

    func clear() {
        currentSourcePath = nil
        phase = .idle
    }
}

private extension FilePreviewContentModel.Phase {
    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

private enum FilePreviewArtifact {
    case markdown(HTMLPreviewArtifact)
    case plainText(PlainTextPreviewArtifact)
    case archive(ArchivePreviewArtifact)
    case diskImage(DiskImagePreviewArtifact)
    case pdf(URL)
    case quickLookSlides(URL)
    case html(HTMLPreviewArtifact)
    case spreadsheet(SpreadsheetPreviewArtifact)
    case quickLookFallback(URL)
}

private struct HTMLNavigationSeed: Sendable {
    let id: String
    let title: String
    let offset: CGFloat
    let image: NSImage?
}

private struct HTMLPreviewArtifact: Sendable {
    enum NavigationMode: Sendable {
        case slides
        case pagedDocument
        case generic
    }

    let htmlURL: URL
    let baseURL: URL
    let pageSize: CGSize?
    let navigationMode: NavigationMode
    let initialNavigation: [HTMLNavigationSeed]
    let allowsHorizontalScrolling: Bool
}

private struct SpreadsheetPreviewArtifact: Sendable {
    struct Sheet: Identifiable, Sendable {
        let id: String
        let title: String
        let htmlURL: URL
    }

    let sheets: [Sheet]
    let baseURL: URL
    let pageSize: CGSize?
}

private struct PlainTextPreviewArtifact: Sendable {
    let text: String
    let usesMonospacedFont: Bool
}

private struct ArchivePreviewArtifact: Sendable {
    struct SummaryBadge: Identifiable, Sendable {
        let id: String
        let title: String
        let value: String
    }

    struct Entry: Identifiable, Sendable {
        let id: String
        let title: String
        let kindLabel: String
        let subtitle: String
        let isFolder: Bool
    }

    let badges: [SummaryBadge]
    let entries: [Entry]
    let footnote: String?
}

private struct DiskImagePreviewArtifact: Sendable {
    struct SummaryBadge: Identifiable, Sendable {
        let id: String
        let title: String
        let value: String
    }

    let badges: [SummaryBadge]
}

private enum ZIPArchiveListingReader {
    nonisolated private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
    nonisolated private static let zip64EndOfCentralDirectorySignature: UInt32 = 0x0606_4b50
    nonisolated private static let zip64EndOfCentralDirectoryLocatorSignature: UInt32 = 0x0706_4b50
    nonisolated private static let centralDirectoryFileHeaderSignature: UInt32 = 0x0201_4b50
    nonisolated private static let generalPurposeUTF8Flag: UInt16 = 1 << 11
    nonisolated private static let unicodePathExtraFieldHeaderID: UInt16 = 0x7075
    nonisolated private static let gb18030Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )
    nonisolated private static let big5Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
    )
    nonisolated private static let cp437Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)
        )
    )

    nonisolated static func entries(for url: URL) throws -> [String] {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let endOfCentralDirectoryOffset = findEndOfCentralDirectory(in: data) else {
            throw archivePreviewError(FullPreviewLocalizationSupport.localized("未找到 ZIP 中央目录。"))
        }

        let directory = try centralDirectoryLocation(
            in: data,
            endOfCentralDirectoryOffset: endOfCentralDirectoryOffset
        )
        guard directory.offset >= 0,
              directory.size >= 0,
              directory.offset + directory.size <= data.count else {
            throw archivePreviewError(FullPreviewLocalizationSupport.localized("ZIP 中央目录范围无效。"))
        }

        var cursor = directory.offset
        let end = directory.offset + directory.size
        var entries: [String] = []
        entries.reserveCapacity(min(directory.entryCount, 128))

        while cursor + 46 <= end {
            let signature = uint32(in: data, at: cursor)
            guard signature == centralDirectoryFileHeaderSignature else {
                break
            }

            let generalPurposeBitFlag = uint16(in: data, at: cursor + 8)
            let fileNameLength = Int(uint16(in: data, at: cursor + 28))
            let extraFieldLength = Int(uint16(in: data, at: cursor + 30))
            let fileCommentLength = Int(uint16(in: data, at: cursor + 32))
            let recordLength = 46 + fileNameLength + extraFieldLength + fileCommentLength

            guard fileNameLength >= 0,
                  extraFieldLength >= 0,
                  fileCommentLength >= 0,
                  cursor + recordLength <= end else {
                throw archivePreviewError(FullPreviewLocalizationSupport.localized("ZIP 目录记录已损坏。"))
            }

            let fileNameOffset = cursor + 46
            let extraFieldOffset = fileNameOffset + fileNameLength
            let fileNameData = data.subdata(in: fileNameOffset ..< extraFieldOffset)
            let extraFieldData = data.subdata(in: extraFieldOffset ..< extraFieldOffset + extraFieldLength)

            let decodedPath = decodeEntryPath(
                from: fileNameData,
                extraFieldData: extraFieldData,
                generalPurposeBitFlag: generalPurposeBitFlag
            )
            if !decodedPath.isEmpty {
                entries.append(decodedPath)
            }

            cursor += recordLength
        }

        if entries.isEmpty, directory.entryCount > 0 {
            throw archivePreviewError(FullPreviewLocalizationSupport.localized("未能解析 ZIP 目录条目。"))
        }

        return entries
    }

    nonisolated private static func centralDirectoryLocation(
        in data: Data,
        endOfCentralDirectoryOffset: Int
    ) throws -> (offset: Int, size: Int, entryCount: Int) {
        let recordedEntryCount = uint16(in: data, at: endOfCentralDirectoryOffset + 10)
        let recordedDirectorySize = uint32(in: data, at: endOfCentralDirectoryOffset + 12)
        let recordedDirectoryOffset = uint32(in: data, at: endOfCentralDirectoryOffset + 16)

        let requiresZIP64 = recordedEntryCount == .max ||
            recordedDirectorySize == .max ||
            recordedDirectoryOffset == .max

        if requiresZIP64 {
            guard endOfCentralDirectoryOffset >= 20 else {
                throw archivePreviewError(FullPreviewLocalizationSupport.localized("ZIP64 目录定位信息缺失。"))
            }

            let locatorOffset = endOfCentralDirectoryOffset - 20
            guard uint32(in: data, at: locatorOffset) == zip64EndOfCentralDirectoryLocatorSignature else {
                throw archivePreviewError(FullPreviewLocalizationSupport.localized("ZIP64 目录定位信息缺失。"))
            }

            let zip64DirectoryOffset = Int(uint64(in: data, at: locatorOffset + 8))
            guard zip64DirectoryOffset >= 0,
                  zip64DirectoryOffset + 56 <= data.count,
                  uint32(in: data, at: zip64DirectoryOffset) == zip64EndOfCentralDirectorySignature else {
                throw archivePreviewError(FullPreviewLocalizationSupport.localized("ZIP64 目录记录无效。"))
            }

            return (
                offset: Int(uint64(in: data, at: zip64DirectoryOffset + 48)),
                size: Int(uint64(in: data, at: zip64DirectoryOffset + 40)),
                entryCount: Int(uint64(in: data, at: zip64DirectoryOffset + 32))
            )
        }

        return (
            offset: Int(recordedDirectoryOffset),
            size: Int(recordedDirectorySize),
            entryCount: Int(recordedEntryCount)
        )
    }

    nonisolated private static func decodeEntryPath(
        from fileNameData: Data,
        extraFieldData: Data,
        generalPurposeBitFlag: UInt16
    ) -> String {
        if let unicodePath = unicodePath(from: extraFieldData), !unicodePath.isEmpty {
            return sanitize(decodedPath: unicodePath)
        }

        if generalPurposeBitFlag & generalPurposeUTF8Flag != 0,
           let utf8Path = String(data: fileNameData, encoding: .utf8),
           !utf8Path.isEmpty {
            return sanitize(decodedPath: utf8Path)
        }

        if let utf8Path = String(data: fileNameData, encoding: .utf8), !utf8Path.isEmpty {
            return sanitize(decodedPath: utf8Path)
        }

        let fallbackEncodings = legacyFallbackEncodings(for: fileNameData)
        for encoding in fallbackEncodings {
            if let decodedPath = String(data: fileNameData, encoding: encoding), !decodedPath.isEmpty {
                return sanitize(decodedPath: decodedPath)
            }
        }

        return sanitize(decodedPath: String(decoding: fileNameData, as: UTF8.self))
    }

    nonisolated private static func unicodePath(from extraFieldData: Data) -> String? {
        var cursor = 0
        while cursor + 4 <= extraFieldData.count {
            let headerID = uint16(in: extraFieldData, at: cursor)
            let fieldSize = Int(uint16(in: extraFieldData, at: cursor + 2))
            let fieldDataStart = cursor + 4
            let fieldDataEnd = fieldDataStart + fieldSize

            guard fieldDataEnd <= extraFieldData.count else {
                break
            }

            if headerID == unicodePathExtraFieldHeaderID, fieldSize > 5 {
                let version = extraFieldData[fieldDataStart]
                if version == 1 {
                    let unicodeData = extraFieldData.subdata(in: (fieldDataStart + 5) ..< fieldDataEnd)
                    if let unicodePath = String(data: unicodeData, encoding: .utf8), !unicodePath.isEmpty {
                        return unicodePath
                    }
                }
            }

            cursor = fieldDataEnd
        }

        return nil
    }

    nonisolated private static func legacyFallbackEncodings(for fileNameData: Data) -> [String.Encoding] {
        if looksLikeGBEncodedPath(fileNameData) {
            return [gb18030Encoding, big5Encoding, cp437Encoding]
        }
        return [cp437Encoding, gb18030Encoding, big5Encoding]
    }

    nonisolated private static func looksLikeGBEncodedPath(_ data: Data) -> Bool {
        let bytes = Array(data)
        let nonASCIIByteCount = bytes.reduce(into: 0) { partialResult, byte in
            if byte >= 0x80 {
                partialResult += 1
            }
        }
        guard nonASCIIByteCount >= 2 else {
            return false
        }

        var index = 0
        var validGBSequenceBytes = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte >= 0x80 else {
                index += 1
                continue
            }

            if byte >= 0x81, byte <= 0xFE, index + 1 < bytes.count {
                let trailing = bytes[index + 1]
                if ((0x40...0x7E).contains(trailing) || (0x80...0xFE).contains(trailing)),
                   trailing != 0x7F {
                    validGBSequenceBytes += 2
                    index += 2
                    continue
                }

                if index + 3 < bytes.count {
                    let second = bytes[index + 1]
                    let third = bytes[index + 2]
                    let fourth = bytes[index + 3]
                    if (0x30...0x39).contains(second),
                       (0x81...0xFE).contains(third),
                       (0x30...0x39).contains(fourth) {
                        validGBSequenceBytes += 4
                        index += 4
                        continue
                    }
                }
            }

            index += 1
        }

        return validGBSequenceBytes >= max(2, (nonASCIIByteCount / 2) * 2)
    }

    nonisolated private static func sanitize(decodedPath: String) -> String {
        decodedPath
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .newlines)
    }

    nonisolated private static func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else {
            return nil
        }

        let minimumOffset = max(0, data.count - (22 + 0xFFFF))
        for offset in stride(from: data.count - 22, through: minimumOffset, by: -1) {
            guard uint32(in: data, at: offset) == endOfCentralDirectorySignature else {
                continue
            }

            let commentLength = Int(uint16(in: data, at: offset + 20))
            if offset + 22 + commentLength == data.count {
                return offset
            }
        }

        return nil
    }

    nonisolated private static func uint16(in data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) |
            (UInt16(data[offset + 1]) << 8)
    }

    nonisolated private static func uint32(in data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    nonisolated private static func uint64(in data: Data, at offset: Int) -> UInt64 {
        UInt64(data[offset]) |
            (UInt64(data[offset + 1]) << 8) |
            (UInt64(data[offset + 2]) << 16) |
            (UInt64(data[offset + 3]) << 24) |
            (UInt64(data[offset + 4]) << 32) |
            (UInt64(data[offset + 5]) << 40) |
            (UInt64(data[offset + 6]) << 48) |
            (UInt64(data[offset + 7]) << 56)
    }

    nonisolated private static func archivePreviewError(_ description: String) -> NSError {
        NSError(
            domain: "EdgeClipArchivePreview",
            code: 1001,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

private struct PreviewEntryIconStyle {
    let symbolName: String
    let tint: Color
    let fontSize: CGFloat
}

private enum PreviewEntryIconSupport {
    private static let imageExtensions: Set<String> = [
        "avif", "bmp", "gif", "heic", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"
    ]
    private static let codeExtensions: Set<String> = [
        "bash", "c", "cc", "conf", "cpp", "css", "fish", "h", "hpp", "ini",
        "java", "js", "json", "jsonl", "kt", "less", "log", "m", "markdown",
        "md", "mdown", "mkd", "mkdn", "mm", "php", "plist", "py", "rb", "rs",
        "scss", "sh", "sql", "swift", "toml", "ts", "tsx", "xml", "yaml",
        "yml", "zsh"
    ]
    private static let spreadsheetExtensions: Set<String> = [
        "csv", "numbers", "ods", "tsv", "xls", "xlsx"
    ]
    private static let presentationExtensions: Set<String> = [
        "key", "odp", "ppt", "pptx"
    ]
    private static let archiveExtensions: Set<String> = [
        "7z", "bz2", "gz", "rar", "tar", "tbz", "tbz2", "tgz", "txz", "xz", "zip"
    ]
    private static let audioExtensions: Set<String> = [
        "aac", "aiff", "flac", "m4a", "mp3", "ogg", "wav"
    ]
    private static let videoExtensions: Set<String> = [
        "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm"
    ]
    private static let designExtensions: Set<String> = [
        "ai", "fig", "indd", "psd", "sketch", "xd"
    ]
    private static let pdfExtensions: Set<String> = ["pdf"]

    static func style(title: String, kindLabel: String, isFolder: Bool) -> PreviewEntryIconStyle {
        if isFolder {
            return PreviewEntryIconStyle(symbolName: "folder.fill", tint: .accentColor, fontSize: 16)
        }

        let fileExtension = URL(fileURLWithPath: title).pathExtension.lowercased()
        if imageExtensions.contains(fileExtension) {
            return PreviewEntryIconStyle(symbolName: "photo", tint: .green, fontSize: 16)
        }
        if codeExtensions.contains(fileExtension) {
            return PreviewEntryIconStyle(symbolName: "chevron.left.forwardslash.chevron.right", tint: .orange, fontSize: 14.5)
        }
        if spreadsheetExtensions.contains(fileExtension) || kindLabel == FullPreviewLocalizationSupport.localized("电子表格") {
            return PreviewEntryIconStyle(symbolName: "tablecells", tint: .green, fontSize: 16)
        }
        if presentationExtensions.contains(fileExtension) || kindLabel == FullPreviewLocalizationSupport.localized("演示文稿") {
            return PreviewEntryIconStyle(symbolName: "rectangle.on.rectangle", tint: .orange, fontSize: 16)
        }
        if archiveExtensions.contains(fileExtension) || kindLabel == FullPreviewLocalizationSupport.localized("压缩包") {
            return PreviewEntryIconStyle(symbolName: "doc.zipper", tint: .brown, fontSize: 16)
        }
        if audioExtensions.contains(fileExtension) {
            return PreviewEntryIconStyle(symbolName: "waveform", tint: .purple, fontSize: 16)
        }
        if videoExtensions.contains(fileExtension) {
            return PreviewEntryIconStyle(symbolName: "film", tint: .pink, fontSize: 16)
        }
        if designExtensions.contains(fileExtension) {
            return PreviewEntryIconStyle(symbolName: "paintpalette", tint: .purple, fontSize: 16)
        }
        if pdfExtensions.contains(fileExtension) {
            return PreviewEntryIconStyle(symbolName: "doc.text", tint: .red, fontSize: 16)
        }
        if kindLabel == FullPreviewLocalizationSupport.localized("文稿") {
            return PreviewEntryIconStyle(symbolName: "doc.text", tint: .indigo, fontSize: 16)
        }
        return PreviewEntryIconStyle(symbolName: "doc", tint: Color.primary.opacity(0.82), fontSize: 16)
    }
}

private actor FilePreviewExportService {
    static let shared = FilePreviewExportService()
    nonisolated private static let markdownExtensions: Set<String> = [
        "markdown", "md", "mdown", "mkd", "mkdn"
    ]
    nonisolated private static let archiveExtensions: Set<String> = [
        "7z", "bz2", "gz", "rar", "tar", "tbz", "tbz2", "tgz", "txz", "xz", "zip"
    ]
    nonisolated private static let plainTextExtensions: Set<String> = [
        "bash", "c", "cc", "conf", "cpp", "css", "fish", "h", "hpp",
        "ini", "java", "js", "json", "jsonl", "kt", "less", "log", "m",
        "mm", "php", "plist", "py", "rb", "rs", "scss", "sh", "sql",
        "swift", "text", "toml", "ts", "tsx", "txt", "xml", "yaml",
        "yml", "zsh"
    ]
    nonisolated private static let codeLikeTextExtensions: Set<String> = [
        "bash", "c", "cc", "conf", "cpp", "css", "fish", "h", "hpp",
        "ini", "java", "js", "json", "jsonl", "kt", "less", "log", "m",
        "mm", "php", "plist", "py", "rb", "rs", "scss", "sh", "sql",
        "swift", "toml", "ts", "tsx", "xml", "yaml", "yml", "zsh"
    ]
    private let inlineTextPreviewByteLimit = 1_500_000
    private let maximumCachedPreviewCount = 18

    private struct CachedPreview: Sendable {
        let fingerprint: String
        let artifact: FilePreviewArtifactRecord
    }

    private enum FilePreviewArtifactRecord: Sendable {
        case markdown(HTMLPreviewArtifact)
        case plainText(PlainTextPreviewArtifact)
        case archive(ArchivePreviewArtifact)
        case diskImage(DiskImagePreviewArtifact)
        case pdf(URL)
        case quickLookSlides(URL)
        case html(HTMLPreviewArtifact)
        case spreadsheet(SpreadsheetPreviewArtifact)
        case quickLookFallback(URL)
    }

    private struct PreviewProperties: Sendable {
        let width: Double?
        let height: Double?
        let pageElementXPath: String?
        let canHavePages: Bool
    }

    private enum ArchiveFormat {
        case zip
        case tar
        case tgz
        case tbz2
        case txz
        case gzip
        case bzip2
        case xz
        case rar
        case sevenZip

        var displayName: String {
            switch self {
            case .zip: return "ZIP"
            case .tar: return "TAR"
            case .tgz: return "TGZ"
            case .tbz2: return "TBZ2"
            case .txz: return "TXZ"
            case .gzip: return "GZIP"
            case .bzip2: return "BZIP2"
            case .xz: return "XZ"
            case .rar: return "RAR"
            case .sevenZip: return "7Z"
            }
        }
    }

    private var cache: [String: CachedPreview] = [:]
    private var cacheAccessOrder: [String] = []
    private let fileManager = FileManager.default
    private let readbackServiceClient = ClipboardReadbackServiceClient()

    func previewArtifact(for sourceURL: URL, securityScopedBookmarkData: Data?) async throws -> FilePreviewArtifact {
        let fingerprint = try previewFingerprint(for: sourceURL)
        let cacheKey = sourceURL.standardizedFileURL.path

        if let cached = cache[cacheKey], cached.fingerprint == fingerprint {
            touchCacheKey(cacheKey)
            return materialize(cached.artifact)
        }

        let artifactRecord: FilePreviewArtifactRecord
        let pathExtension = sourceURL.pathExtension.lowercased()
        if Self.markdownExtensions.contains(pathExtension),
           let markdownArtifact = try makeMarkdownPreviewArtifact(
                from: sourceURL,
                fingerprint: fingerprint,
                securityScopedBookmarkData: securityScopedBookmarkData
           ) {
            artifactRecord = .markdown(markdownArtifact)
        } else if Self.plainTextExtensions.contains(pathExtension),
                  let plainTextArtifact = try makePlainTextPreviewArtifact(
                    from: sourceURL,
                    pathExtension: pathExtension,
                    securityScopedBookmarkData: securityScopedBookmarkData
                  ) {
            return .plainText(plainTextArtifact)
        } else if pathExtension == "dmg" {
            artifactRecord = try makeDiskImagePreviewArtifact(
                from: sourceURL,
                securityScopedBookmarkData: securityScopedBookmarkData
            )
        } else if Self.archiveExtensions.contains(pathExtension) {
            artifactRecord = try makeArchivePreviewArtifact(
                from: sourceURL,
                securityScopedBookmarkData: securityScopedBookmarkData
            )
        } else if pathExtension == "pdf" {
            artifactRecord = .pdf(sourceURL)
        } else if ["ppt", "pptx"].contains(pathExtension) {
            do {
                artifactRecord = try await exportPreviewArtifact(
                    for: sourceURL,
                    fingerprint: fingerprint,
                    securityScopedBookmarkData: securityScopedBookmarkData
                )
            } catch {
                if let fallbackURL = try? ensureQuickLookFallbackURL(
                    for: sourceURL,
                    fingerprint: fingerprint,
                    securityScopedBookmarkData: securityScopedBookmarkData
                ) {
                    artifactRecord = .quickLookSlides(fallbackURL)
                } else {
                    artifactRecord = .quickLookSlides(sourceURL)
                }
            }
        } else {
            do {
                artifactRecord = try await exportPreviewArtifact(
                    for: sourceURL,
                    fingerprint: fingerprint,
                    securityScopedBookmarkData: securityScopedBookmarkData
                )
            } catch {
                if let fallbackURL = try? ensureQuickLookFallbackURL(
                    for: sourceURL,
                    fingerprint: fingerprint,
                    securityScopedBookmarkData: securityScopedBookmarkData
                ) {
                    artifactRecord = .quickLookFallback(fallbackURL)
                } else {
                    throw error
                }
            }
        }

        storeCachedPreview(
            CachedPreview(fingerprint: fingerprint, artifact: artifactRecord),
            forKey: cacheKey
        )
        return materialize(artifactRecord)
    }

    private func touchCacheKey(_ key: String) {
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
    }

    private func storeCachedPreview(_ preview: CachedPreview, forKey key: String) {
        cache[key] = preview
        touchCacheKey(key)

        while cache.count > maximumCachedPreviewCount {
            guard let oldestKey = cacheAccessOrder.first else { break }
            cache.removeValue(forKey: oldestKey)
            cacheAccessOrder.removeFirst()
        }
    }

    private func materialize(_ record: FilePreviewArtifactRecord) -> FilePreviewArtifact {
        switch record {
        case .markdown(let artifact):
            return .markdown(artifact)
        case .plainText(let artifact):
            return .plainText(artifact)
        case .archive(let artifact):
            return .archive(artifact)
        case .diskImage(let artifact):
            return .diskImage(artifact)
        case .pdf(let url):
            return .pdf(url)
        case .quickLookSlides(let url):
            return .quickLookSlides(url)
        case .html(let artifact):
            return .html(artifact)
        case .spreadsheet(let artifact):
            return .spreadsheet(artifact)
        case .quickLookFallback(let url):
            return .quickLookFallback(url)
        }
    }

    private func exportPreviewArtifact(
        for sourceURL: URL,
        fingerprint: String,
        securityScopedBookmarkData: Data?
    ) async throws -> FilePreviewArtifactRecord {
        let response = try await readbackServiceClient.generatePreviewExport(
            PreviewExportRequest(
                requestID: UUID(),
                sourcePath: sourceURL.path,
                securityScopedBookmarkData: securityScopedBookmarkData,
                fingerprint: fingerprint
            )
        )
        guard let previewDirectoryPath = response.previewDirectoryPath else {
            return .quickLookFallback(try ensureQuickLookFallbackURL(
                for: sourceURL,
                fingerprint: fingerprint,
                securityScopedBookmarkData: securityScopedBookmarkData
            ))
        }
        let previewDirectory = URL(fileURLWithPath: previewDirectoryPath, isDirectory: true)

        let previewHTMLURL = previewDirectory.appendingPathComponent("Preview.html")
        let previewURLURL = previewDirectory.appendingPathComponent("Preview.url")
        let previewPropertiesURL = previewDirectory.appendingPathComponent("PreviewProperties.plist")

        if fileManager.fileExists(atPath: previewURLURL.path),
           let previewURLString = try? String(contentsOf: previewURLURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
           let previewURL = URL(string: previewURLString),
           fileManager.fileExists(atPath: previewURL.path) {
            return .pdf(previewURL)
        }

        guard fileManager.fileExists(atPath: previewHTMLURL.path) else {
            return .quickLookFallback(try ensureQuickLookFallbackURL(
                for: sourceURL,
                fingerprint: fingerprint,
                securityScopedBookmarkData: securityScopedBookmarkData
            ))
        }

        let previewProperties = try loadPreviewProperties(from: previewPropertiesURL)
        let html = (try? String(contentsOf: previewHTMLURL, encoding: .utf8)) ?? ""

        if let spreadsheet = spreadsheetArtifactIfNeeded(
            html: html,
            previewDirectory: previewDirectory,
            pageSize: pageSize(from: previewProperties)
        ) {
            return .spreadsheet(spreadsheet)
        }

        let navigationMode: HTMLPreviewArtifact.NavigationMode
        if previewProperties.pageElementXPath == "/html/body/div" || html.contains("class=\"slide\"") {
            navigationMode = .slides
        } else if previewProperties.canHavePages {
            navigationMode = .pagedDocument
        } else {
            navigationMode = .generic
        }

        let initialNavigation = makeInitialNavigation(
            html: html,
            previewDirectory: previewDirectory,
            pageSize: pageSize(from: previewProperties),
            navigationMode: navigationMode
        )

        return .html(
            HTMLPreviewArtifact(
                htmlURL: previewHTMLURL,
                baseURL: previewDirectory,
                pageSize: pageSize(from: previewProperties),
                navigationMode: navigationMode,
                initialNavigation: initialNavigation,
                allowsHorizontalScrolling: true
            )
        )
    }

    private func makeMarkdownPreviewArtifact(
        from sourceURL: URL,
        fingerprint: String,
        securityScopedBookmarkData: Data?
    ) throws -> HTMLPreviewArtifact? {
        guard let text = try loadInlineTextPreview(
            from: sourceURL,
            securityScopedBookmarkData: securityScopedBookmarkData
        ), !text.isEmpty else {
            return nil
        }

        let root = previewRoot(for: fingerprint)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let htmlURL = root.appendingPathComponent("markdown-rendered.html")
        let html = MarkdownPreviewRenderer.renderDocument(
            markdown: text,
            title: sourceURL.deletingPathExtension().lastPathComponent
        )
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)

        return HTMLPreviewArtifact(
            htmlURL: htmlURL,
            baseURL: root,
            pageSize: nil,
            navigationMode: .generic,
            initialNavigation: [],
            allowsHorizontalScrolling: false
        )
    }

    private func makePlainTextPreviewArtifact(
        from sourceURL: URL,
        pathExtension: String,
        securityScopedBookmarkData: Data?
    ) throws -> PlainTextPreviewArtifact? {
        guard let text = try loadInlineTextPreview(
            from: sourceURL,
            securityScopedBookmarkData: securityScopedBookmarkData
        ), !text.isEmpty else {
            return nil
        }

        return PlainTextPreviewArtifact(
            text: text,
            usesMonospacedFont: Self.codeLikeTextExtensions.contains(pathExtension)
        )
    }

    private func makeArchivePreviewArtifact(
        from sourceURL: URL,
        securityScopedBookmarkData: Data?
    ) throws -> FilePreviewArtifactRecord {
        let scoped = scopedURL(for: sourceURL, securityScopedBookmarkData: securityScopedBookmarkData)
        defer { scoped.stopAccess() }

        let archiveURL = scoped.url
        let format = archiveFormat(for: archiveURL)
        let sizeText = archiveFileSizeText(for: archiveURL)
        let listing = (try? archiveListing(for: archiveURL, format: format)) ?? (
            entries: [],
            footnote: FullPreviewLocalizationSupport.localized("未能读取压缩包内容。")
        )

        let visibleLimit = 80
        let visibleEntries = Array(listing.entries.prefix(visibleLimit)).enumerated().map { index, path in
            archiveEntry(path: path, index: index)
        }
        let folderCount = listing.entries.reduce(into: 0) { partialResult, path in
            if path.hasSuffix("/") {
                partialResult += 1
            }
        }
        let fileCount = max(0, listing.entries.count - folderCount)

        var badges = [
            ArchivePreviewArtifact.SummaryBadge(id: "format", title: FullPreviewLocalizationSupport.localized("格式"), value: format.displayName)
        ]
        if let sizeText {
            badges.append(.init(id: "size", title: FullPreviewLocalizationSupport.localized("大小"), value: sizeText))
        }
        if !listing.entries.isEmpty {
            badges.append(.init(id: "total", title: FullPreviewLocalizationSupport.localized("项目"), value: "\(listing.entries.count)"))
            badges.append(.init(id: "folders", title: FullPreviewLocalizationSupport.localized("文件夹"), value: "\(folderCount)"))
            badges.append(.init(id: "files", title: FullPreviewLocalizationSupport.localized("文件"), value: "\(fileCount)"))
        }

        let footnote: String?
        if listing.entries.count > visibleEntries.count {
            footnote = FullPreviewLocalizationSupport.visibleItemsFootnote(visibleEntries.count)
        } else {
            footnote = listing.footnote
        }

        return .archive(
            ArchivePreviewArtifact(
                badges: badges,
                entries: visibleEntries,
                footnote: footnote
            )
        )
    }

    private func makeDiskImagePreviewArtifact(
        from sourceURL: URL,
        securityScopedBookmarkData: Data?
    ) throws -> FilePreviewArtifactRecord {
        let scoped = scopedURL(for: sourceURL, securityScopedBookmarkData: securityScopedBookmarkData)
        defer { scoped.stopAccess() }

        let metadata = FilePresentationSupport.makeMetadata(
            for: scoped.url,
            fallbackDisplayName: scoped.url.lastPathComponent
        )
        var badges = [
            DiskImagePreviewArtifact.SummaryBadge(id: "format", title: FullPreviewLocalizationSupport.localized("格式"), value: "DMG")
        ]
        if let sizeText = metadata.sizeText {
            badges.append(.init(id: "size", title: FullPreviewLocalizationSupport.localized("大小"), value: sizeText))
        }
        return .diskImage(DiskImagePreviewArtifact(badges: badges))
    }

    private func loadInlineTextPreview(
        from sourceURL: URL,
        securityScopedBookmarkData: Data?
    ) throws -> String? {
        let scoped = scopedURL(for: sourceURL, securityScopedBookmarkData: securityScopedBookmarkData)
        defer { scoped.stopAccess() }

        if let fileSize = try? scoped.url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > inlineTextPreviewByteLimit {
            return nil
        }

        let data = try Data(contentsOf: scoped.url, options: [.mappedIfSafe])
        guard !data.isEmpty else { return "" }

        let encodings: [String.Encoding] = [
            .utf8,
            .unicode,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian
        ]

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding) {
                return text
            }
        }

        return nil
    }

    private func archiveFormat(for url: URL) -> ArchiveFormat {
        let lowercasedName = url.lastPathComponent.lowercased()
        if lowercasedName.hasSuffix(".tar.gz") || lowercasedName.hasSuffix(".tgz") {
            return .tgz
        }
        if lowercasedName.hasSuffix(".tar.bz2") || lowercasedName.hasSuffix(".tbz2") || lowercasedName.hasSuffix(".tbz") {
            return .tbz2
        }
        if lowercasedName.hasSuffix(".tar.xz") || lowercasedName.hasSuffix(".txz") {
            return .txz
        }

        switch url.pathExtension.lowercased() {
        case "zip":
            return .zip
        case "tar":
            return .tar
        case "gz":
            return .gzip
        case "bz2":
            return .bzip2
        case "xz":
            return .xz
        case "rar":
            return .rar
        case "7z":
            return .sevenZip
        default:
            return .zip
        }
    }

    private func archiveListing(
        for url: URL,
        format: ArchiveFormat
    ) throws -> (entries: [String], footnote: String?) {
        switch format {
        case .zip:
            let entries = try ZIPArchiveListingReader.entries(for: url)
            return (entries, entries.isEmpty ? FullPreviewLocalizationSupport.localized("未能读取压缩包内容。") : nil)
        case .tar, .tgz, .tbz2, .txz, .rar, .sevenZip:
            let entries = try runArchiveCommand("/usr/bin/bsdtar", arguments: ["-tf", url.path])
            return (entries, entries.isEmpty ? FullPreviewLocalizationSupport.localized("未能读取压缩包内容。") : nil)
        case .gzip, .bzip2, .xz:
            return ([archiveSyntheticEntryName(for: url)], nil)
        }
    }

    private func runArchiveCommand(_ launchPath: String, arguments: [String]) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(decoding: errorData, as: UTF8.self)
            throw NSError(
                domain: "EdgeClipArchivePreview",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: errorText.isEmpty
                        ? FullPreviewLocalizationSupport.localized("归档目录解析失败。")
                        : errorText
                ]
            )
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: outputData, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func archiveSyntheticEntryName(for url: URL) -> String {
        let lowercasedName = url.lastPathComponent.lowercased()
        let suffixes = [".gz", ".bz2", ".xz"]
        for suffix in suffixes where lowercasedName.hasSuffix(suffix) {
            return String(url.lastPathComponent.dropLast(suffix.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func archiveFileSizeText(for url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey])
        let fileSize = values?.totalFileSize ?? values?.fileSize
        return fileSize.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        }
    }

    private func archiveEntry(path: String, index: Int) -> ArchivePreviewArtifact.Entry {
        let normalizedPath = path
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "./", with: "")
        let isFolder = normalizedPath.hasSuffix("/")
        let trimmedPath = isFolder ? String(normalizedPath.dropLast()) : normalizedPath
        let pathURL = URL(fileURLWithPath: trimmedPath)
        let title = pathURL.lastPathComponent.isEmpty ? trimmedPath : pathURL.lastPathComponent
        let parentPath = pathURL.deletingLastPathComponent().path
        let kindLabel = isFolder
            ? FullPreviewLocalizationSupport.localized("文件夹")
            : FilePresentationSupport.normalizedKindLabel(
                localizedTypeDescription: nil,
                url: pathURL,
                fallbackToLocalizedDescription: false
            )
        let subtitleBase = parentPath == "/" || parentPath == "." ? FullPreviewLocalizationSupport.localized("根目录") : parentPath
        return ArchivePreviewArtifact.Entry(
            id: "archive-entry-\(index)",
            title: title,
            kindLabel: kindLabel,
            subtitle: "\(subtitleBase) · \(kindLabel)",
            isFolder: isFolder
        )
    }

    private func ensureQuickLookFallbackURL(
        for sourceURL: URL,
        fingerprint: String,
        securityScopedBookmarkData: Data?
    ) throws -> URL {
        let stagedURL = previewRoot(for: fingerprint).appendingPathComponent("staged-\(sourceURL.lastPathComponent)")
        if fileManager.fileExists(atPath: stagedURL.path) {
            return stagedURL
        }

        let root = previewRoot(for: fingerprint)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let scoped = scopedURL(for: sourceURL, securityScopedBookmarkData: securityScopedBookmarkData)
        defer { scoped.stopAccess() }
        try stageFileIfNeeded(sourceURL: scoped.url, stagedURL: stagedURL)
        return stagedURL
    }

    private func makeInitialNavigation(
        html: String,
        previewDirectory: URL,
        pageSize: CGSize?,
        navigationMode: HTMLPreviewArtifact.NavigationMode
    ) -> [HTMLNavigationSeed] {
        switch navigationMode {
        case .slides:
            let slideCount = html.components(separatedBy: "<div class=\"slide\"").count - 1
            guard slideCount > 1 else { return [] }
            let pageHeight = pageSize?.height ?? 560
            let slideImageSources = slideImageSources(from: html)
            return (0..<slideCount).map { index in
                HTMLNavigationSeed(
                    id: "slide-\(index)",
                    title: FullPreviewLocalizationSupport.pageTitle(index + 1),
                    offset: CGFloat(index) * pageHeight,
                    image: slideThumbnail(
                        from: index < slideImageSources.count ? slideImageSources[index] : nil,
                        previewDirectory: previewDirectory
                    )
                )
            }
        case .pagedDocument, .generic:
            return []
        }
    }

    private func slideImageSources(from html: String) -> [String?] {
        let marker = "<div class=\"slide\""
        let segments = html.components(separatedBy: marker)
        guard segments.count > 1 else { return [] }

        return segments.dropFirst().map { segment in
            segment.firstMatch(of: #"<img[^>]+src="([^"]+)""#)
        }
    }

    private func slideThumbnail(from relativePath: String?, previewDirectory: URL) -> NSImage? {
        guard let relativePath, !relativePath.isEmpty else { return nil }
        let imageURL = previewDirectory.appendingPathComponent(relativePath)
        guard fileManager.fileExists(atPath: imageURL.path),
              let image = NSImage(contentsOf: imageURL) else {
            return nil
        }
        return resizedThumbnail(from: image, maxSize: NSSize(width: 176, height: 124))
    }

    private func spreadsheetArtifactIfNeeded(
        html: String,
        previewDirectory: URL,
        pageSize: CGSize?
    ) -> SpreadsheetPreviewArtifact? {
        guard html.contains("TabViewItem"), html.contains("SheetFrame") else {
            return nil
        }

        let pattern = #"<div class="TabHeader">([^<]*)</div><a href="([^"]+)"></a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: nsRange)
        let sheets = matches.enumerated().compactMap { index, match -> SpreadsheetPreviewArtifact.Sheet? in
            guard match.numberOfRanges == 3,
                  let titleRange = Range(match.range(at: 1), in: html),
                  let hrefRange = Range(match.range(at: 2), in: html) else {
                return nil
            }

            let title = String(html[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let href = String(html[hrefRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { return nil }
            let htmlURL = previewDirectory.appendingPathComponent(href)
            guard fileManager.fileExists(atPath: htmlURL.path) else { return nil }

            return SpreadsheetPreviewArtifact.Sheet(
                id: "sheet-\(index)",
                title: title.isEmpty ? FullPreviewLocalizationSupport.sheetTitle(index + 1) : title,
                htmlURL: htmlURL
            )
        }

        guard !sheets.isEmpty else { return nil }
        return SpreadsheetPreviewArtifact(sheets: sheets, baseURL: previewDirectory, pageSize: pageSize)
    }

    private func loadPreviewProperties(from url: URL) throws -> PreviewProperties {
        guard fileManager.fileExists(atPath: url.path) else {
            return PreviewProperties(width: nil, height: nil, pageElementXPath: nil, canHavePages: false)
        }

        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dictionary = plist as? [String: Any] ?? [:]

        return PreviewProperties(
            width: dictionary["Width"] as? Double,
            height: dictionary["Height"] as? Double,
            pageElementXPath: dictionary["PageElementXPath"] as? String,
            canHavePages: dictionary["CanHavePages"] as? Bool ?? false
        )
    }

    private func pageSize(from properties: PreviewProperties) -> CGSize? {
        guard let width = properties.width, let height = properties.height else {
            return nil
        }

        return CGSize(width: width, height: height)
    }

    private func previewFingerprint(for url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let raw = "\(url.standardizedFileURL.path)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values.fileSize ?? 0)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func previewRoot(for fingerprint: String) -> URL {
        let baseDirectory =
            (try? fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ??
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return baseDirectory
            .appendingPathComponent("edgeclip_embedded_previews", isDirectory: true)
            .appendingPathComponent(fingerprint, isDirectory: true)
    }

    private func stageFileIfNeeded(sourceURL: URL, stagedURL: URL) throws {
        if fileManager.fileExists(atPath: stagedURL.path) {
            let sourceValues = try sourceURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let stagedValues = try stagedURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if sourceValues.fileSize == stagedValues.fileSize,
               sourceValues.contentModificationDate == stagedValues.contentModificationDate {
                return
            }
            try fileManager.removeItem(at: stagedURL)
        }

        try fileManager.copyItem(at: sourceURL, to: stagedURL)
        let sourceValues = try sourceURL.resourceValues(forKeys: [.contentModificationDateKey])
        if let modifiedAt = sourceValues.contentModificationDate {
            try fileManager.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: stagedURL.path)
        }
    }

    private func scopedURL(
        for sourceURL: URL,
        securityScopedBookmarkData: Data?
    ) -> (url: URL, stopAccess: () -> Void) {
        var candidateURL = sourceURL.standardizedFileURL

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

        let didStartAccessing = candidateURL.startAccessingSecurityScopedResource()
        return (
            url: candidateURL,
            stopAccess: {
                if didStartAccessing {
                    candidateURL.stopAccessingSecurityScopedResource()
                }
            }
        )
    }
}

private struct SpreadsheetDocumentPreviewView: View {
    let artifact: SpreadsheetPreviewArtifact

    @State private var selectedSheetIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            if artifact.sheets.count > 1 {
                sheetTabs
                Divider()
            }

            HTMLDocumentPreviewView(
                artifact: HTMLPreviewArtifact(
                    htmlURL: currentSheet.htmlURL,
                    baseURL: artifact.baseURL,
                    pageSize: artifact.pageSize,
                    navigationMode: .pagedDocument,
                    initialNavigation: [],
                    allowsHorizontalScrolling: true
                )
            )
            .id(currentSheet.id)
        }
    }

    private var currentSheet: SpreadsheetPreviewArtifact.Sheet {
        artifact.sheets[min(max(selectedSheetIndex, 0), artifact.sheets.count - 1)]
    }

    private var sheetTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(artifact.sheets.enumerated()), id: \.offset) { index, sheet in
                    Button {
                        selectedSheetIndex = index
                    } label: {
                        Text(sheet.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selectedSheetIndex == index ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedSheetIndex == index ? Color.accentColor : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.02))
    }
}

private struct PDFDocumentPreviewView: View {
    let url: URL

    @StateObject private var model = PDFDocumentPreviewModel()

    var body: some View {
        Group {
            if let document = model.document {
                HStack(spacing: 0) {
                    if model.pages.count > 1 {
                        DocumentNavigationSidebar(
                            items: model.pages.map {
                                DocumentNavigationItem(
                                    id: $0.id,
                                    title: $0.title,
                                    subtitle: nil,
                                    image: $0.thumbnail
                                )
                            },
                            selectedID: model.selectedPageID,
                            onSelect: { model.selectPage(id: $0) }
                        )
                        Divider()
                    }

                    PDFKitDocumentView(document: document, selectedPageIndex: model.selectedPageIndex)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if model.isLoading {
                ProgressView("正在准备 PDF 预览…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PreviewUnavailableView(
                    title: "当前文件暂时无法内嵌预览",
                    message: "系统没有为这个 PDF 生成可用的页面数据。"
                )
            }
        }
        .task(id: url.standardizedFileURL.path) {
            await model.load(url: url)
        }
        .onDisappear {
            model.release()
        }
    }
}

@MainActor
private final class PDFDocumentPreviewModel: ObservableObject {
    struct PageItem: Identifiable {
        let id: String
        let title: String
        var thumbnail: NSImage?
    }

    @Published private(set) var document: PDFDocument?
    @Published private(set) var pages: [PageItem] = []
    @Published private(set) var selectedPageIndex = 0
    @Published private(set) var isLoading = false

    private var currentURL: URL?
    private var thumbnailTask: Task<Void, Never>?

    private let eagerLeadingThumbnailCount = 8
    private let selectedThumbnailRadius = 2

    var selectedPageID: String? {
        pages.indices.contains(selectedPageIndex) ? pages[selectedPageIndex].id : nil
    }

    func load(url: URL) async {
        if currentURL == url.standardizedFileURL, document != nil {
            scheduleThumbnailLoading(around: selectedPageIndex)
            return
        }

        thumbnailTask?.cancel()
        guard !isLoading else { return }
        isLoading = true

        let document = PDFDocument(url: url)
        currentURL = url.standardizedFileURL
        self.document = document
        self.pages = (0..<(document?.pageCount ?? 0)).map { index in
            PageItem(id: "pdf-\(index)", title: FullPreviewLocalizationSupport.pageTitle(index + 1), thumbnail: nil)
        }
        selectedPageIndex = 0
        isLoading = false
        scheduleThumbnailLoading(around: 0)
    }

    func selectPage(id: String) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        selectedPageIndex = index
        scheduleThumbnailLoading(around: index)
    }

    func release() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
        currentURL = nil
        document = nil
        pages = []
        selectedPageIndex = 0
        isLoading = false
    }

    private func scheduleThumbnailLoading(around centerIndex: Int) {
        thumbnailTask?.cancel()

        let indexesToLoad = thumbnailIndexes(around: centerIndex)
        guard !indexesToLoad.isEmpty else { return }

        thumbnailTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for index in indexesToLoad {
                guard !Task.isCancelled else { return }
                guard pages.indices.contains(index), pages[index].thumbnail == nil else { continue }
                guard let page = document?.page(at: index) else { continue }
                let thumbnail = page.thumbnail(of: NSSize(width: 68, height: 96), for: .mediaBox)
                guard !Task.isCancelled, pages.indices.contains(index) else { return }
                var updated = pages[index]
                updated.thumbnail = thumbnail
                pages[index] = updated
            }
        }
    }

    private func thumbnailIndexes(around centerIndex: Int) -> [Int] {
        guard !pages.isEmpty else { return [] }

        var candidates: [Int] = []
        candidates.reserveCapacity(eagerLeadingThumbnailCount + selectedThumbnailRadius * 2 + 1)

        for index in 0..<min(eagerLeadingThumbnailCount, pages.count) {
            candidates.append(index)
        }

        let lowerBound = max(0, centerIndex - selectedThumbnailRadius)
        let upperBound = min(pages.count - 1, centerIndex + selectedThumbnailRadius)
        for index in lowerBound...upperBound {
            if !candidates.contains(index) {
                candidates.append(index)
            }
        }

        return candidates.filter { pages.indices.contains($0) && pages[$0].thumbnail == nil }
    }
}

private struct PDFKitDocumentView: NSViewRepresentable {
    let document: PDFDocument
    let selectedPageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = .clear
        pdfView.document = document
        if let page = document.page(at: selectedPageIndex) {
            pdfView.go(to: page)
        }
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
        if let page = document.page(at: selectedPageIndex), nsView.currentPage != page {
            nsView.go(to: page)
        }
    }
}

private struct HTMLDocumentPreviewView: View {
    let artifact: HTMLPreviewArtifact

    @StateObject private var controller: HTMLPreviewController

    init(artifact: HTMLPreviewArtifact) {
        self.artifact = artifact
        _controller = StateObject(wrappedValue: HTMLPreviewController(initialNavigation: artifact.initialNavigation))
    }

    var body: some View {
        HStack(spacing: 0) {
            if !controller.items.isEmpty {
                DocumentNavigationSidebar(
                    items: controller.items,
                    selectedID: controller.selectedID,
                    onSelect: { controller.selectedID = $0 }
                )
                Divider()
            }

            HTMLPreviewHostRepresentable(artifact: artifact, controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
private final class HTMLPreviewController: ObservableObject {
    @Published var items: [DocumentNavigationItem] = []
    @Published var selectedID: String?

    fileprivate var actions: [String: HTMLNavigationAction] = [:]

    init(initialNavigation: [HTMLNavigationSeed] = []) {
        guard !initialNavigation.isEmpty else { return }
        self.items = initialNavigation.map {
            DocumentNavigationItem(
                id: $0.id,
                title: $0.title,
                subtitle: nil,
                image: $0.image
            )
        }
        self.actions = Dictionary(
            uniqueKeysWithValues: initialNavigation.map { ($0.id, HTMLNavigationAction.scroll($0.offset)) }
        )
        self.selectedID = initialNavigation.first?.id
    }

    func update(items: [DocumentNavigationItem], actions: [String: HTMLNavigationAction]) {
        let existingImages = Dictionary(
            uniqueKeysWithValues: self.items.compactMap { item in
                item.image.map { (item.id, $0) }
            }
        )

        self.items = items.map { item in
            guard item.image == nil, let image = existingImages[item.id] else {
                return item
            }

            return DocumentNavigationItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                image: image
            )
        }
        self.actions = actions
        if selectedID == nil || !actions.keys.contains(selectedID ?? "") {
            selectedID = items.first?.id
        }
    }

    func updateImage(_ image: NSImage?, for id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].image == nil || image != nil else { return }

        var updated = items[index]
        updated = DocumentNavigationItem(
            id: updated.id,
            title: updated.title,
            subtitle: updated.subtitle,
            image: image
        )
        items[index] = updated
    }
}

private struct DocumentNavigationItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let image: NSImage?
}

private enum HTMLNavigationAction {
    case scroll(CGFloat)
}

private struct HTMLNavigationSnapshotDescriptor {
    let id: String
    let title: String
    let offset: CGFloat
}

private struct DocumentNavigationSidebar: View {
    let items: [DocumentNavigationItem]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    Button {
                        onSelect(item.id)
                    } label: {
                        VStack(alignment: .center, spacing: 8) {
                            if let image = item.image {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 88, height: 62)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 88, height: 62)
                                    .overlay(
                                        Image(systemName: "doc.text.image")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    )
                            }

                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .center)

                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedID == item.id ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .frame(width: 132)
        .background(Color.primary.opacity(0.02))
    }
}

private struct HTMLPreviewHostRepresentable: NSViewRepresentable {
    let artifact: HTMLPreviewArtifact
    @ObservedObject var controller: HTMLPreviewController

    func makeNSView(context: Context) -> HTMLPreviewHostView {
        let host = HTMLPreviewHostView(artifact: artifact, controller: controller)
        context.coordinator.hostView = host
        host.load()
        return host
    }

    func updateNSView(_ nsView: HTMLPreviewHostView, context: Context) {
        nsView.updateSelection(id: controller.selectedID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: HTMLPreviewHostView, coordinator: Coordinator) {
        nsView.teardown()
        coordinator.hostView = nil
    }

    final class Coordinator {
        weak var hostView: HTMLPreviewHostView?
    }
}

private protocol EmbeddedPreviewScrollForwarding: AnyObject {
    func forwardEmbeddedScrollWheel(_ event: NSEvent) -> Bool
}

private final class EmbeddedPreviewWebView: WKWebView {
    weak var scrollForwarder: EmbeddedPreviewScrollForwarding?

    override func scrollWheel(with event: NSEvent) {
        if scrollForwarder?.forwardEmbeddedScrollWheel(event) == true {
            return
        }
        super.scrollWheel(with: event)
    }
}

private final class HTMLPreviewHostView: NSView, WKNavigationDelegate, EmbeddedPreviewScrollForwarding {
    private let artifact: HTMLPreviewArtifact
    private weak var controller: HTMLPreviewController?
    private let scrollView = NSScrollView()
    private let documentView = FlippedDocumentView()
    private let webView: EmbeddedPreviewWebView
    private var lastAppliedSelectionID: String?
    private var currentContentSize = CGSize(width: 640, height: 480)
    private var snapshotGeneration = UUID()

    init(artifact: HTMLPreviewArtifact, controller: HTMLPreviewController) {
        self.artifact = artifact
        self.controller = controller
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = EmbeddedPreviewWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)

        wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = artifact.allowsHorizontalScrolling
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        addSubview(scrollView)

        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.scrollForwarder = self
        documentView.addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        layoutDocument()
    }

    func load() {
        webView.loadFileURL(artifact.htmlURL, allowingReadAccessTo: artifact.baseURL)
    }

    func teardown() {
        snapshotGeneration = UUID()
        webView.navigationDelegate = nil
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        webView.removeFromSuperview()
    }

    func updateSelection(id: String?) {
        guard let id, lastAppliedSelectionID != id else { return }
        guard let action = controller?.actions[id] else { return }
        apply(action: action)
        lastAppliedSelectionID = id
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        disableInnerScrolling()
        refreshMetricsAndNavigation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshMetricsAndNavigation()
        }
    }

    private func disableInnerScrolling() {
        for subview in webView.subviews {
            if let scrollSubview = subview as? NSScrollView {
                scrollSubview.hasVerticalScroller = false
                scrollSubview.hasHorizontalScroller = false
                scrollSubview.drawsBackground = false
            }
        }
    }

    private func refreshMetricsAndNavigation() {
        let pageHeight = artifact.pageSize?.height ?? 0
        let script = """
        (() => {
          const contentWidth = Math.max(document.body.scrollWidth, document.documentElement.scrollWidth, 0);
          const contentHeight = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, 0);
          const slideElements = Array.from(document.querySelectorAll('.slide'));
          if (slideElements.length > 1) {
            return {
              kind: 'slides',
              width: contentWidth,
              height: contentHeight,
              items: slideElements.map((element, index) => {
                const text = (element.innerText || '').replace(/\\s+/g, ' ').trim();
                return {
                  id: 'slide-' + index,
                  title: text ? text.slice(0, 32) : '第 ' + (index + 1) + ' 页',
                  offset: element.offsetTop
                };
              })
            };
          }

          const wrapper = document.querySelector('.s1');
          const pageHeight = \(pageHeight);
          if (pageHeight > 0 && wrapper) {
            const totalHeight = Math.max(wrapper.scrollHeight, contentHeight);
            const pageCount = Math.max(1, Math.ceil(totalHeight / pageHeight));
            return {
              kind: 'pages',
              width: contentWidth,
              height: totalHeight,
              items: Array.from({ length: pageCount }, (_, index) => ({
                id: 'page-' + index,
                title: '第 ' + (index + 1) + ' 页',
                offset: index * pageHeight
              }))
            };
          }

          return {
            kind: 'generic',
            width: contentWidth,
            height: contentHeight,
            items: []
          };
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, let payload = result as? [String: Any] else { return }
            let width = CGFloat(payload["width"] as? Double ?? Double(self.currentContentSize.width))
            let height = CGFloat(payload["height"] as? Double ?? Double(self.currentContentSize.height))
            self.currentContentSize = CGSize(width: max(width, 320), height: max(height, 320))
            self.layoutDocument()
            var descriptors = (payload["items"] as? [[String: Any]] ?? []).compactMap { dictionary -> HTMLNavigationSnapshotDescriptor? in
                guard let id = dictionary["id"] as? String,
                      let title = dictionary["title"] as? String,
                      let offset = dictionary["offset"] as? Double else {
                    return nil
                }

                return HTMLNavigationSnapshotDescriptor(
                    id: id,
                    title: title,
                    offset: CGFloat(offset)
                )
            }

            if descriptors.isEmpty, !self.artifact.initialNavigation.isEmpty {
                descriptors = self.artifact.initialNavigation.map {
                    HTMLNavigationSnapshotDescriptor(id: $0.id, title: $0.title, offset: $0.offset)
                }
            }

            let items = descriptors.map {
                (
                    DocumentNavigationItem(id: $0.id, title: $0.title, subtitle: nil, image: nil),
                    HTMLNavigationAction.scroll($0.offset)
                )
            }

            self.controller?.update(
                items: items.map(\.0),
                actions: Dictionary(uniqueKeysWithValues: items.map { ($0.0.id, $0.1) })
            )

            if let selectedID = self.controller?.selectedID {
                self.updateSelection(id: selectedID)
            }

            self.generateSnapshotsIfNeeded(from: descriptors)
        }
    }

    private func layoutDocument() {
        scrollView.frame = bounds
        let width = max(scrollView.contentSize.width, currentContentSize.width)
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: currentContentSize.height)
        webView.frame = documentView.bounds
    }

    private func apply(action: HTMLNavigationAction) {
        switch action {
        case .scroll(let offset):
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func forwardEmbeddedScrollWheel(_ event: NSEvent) -> Bool {
        let canScrollVertically = currentContentSize.height > scrollView.contentSize.height + 1
        let canScrollHorizontally = currentContentSize.width > scrollView.contentSize.width + 1
        guard canScrollVertically || canScrollHorizontally else {
            return false
        }

        scrollView.scrollWheel(with: event)
        return true
    }

    private func generateSnapshotsIfNeeded(from descriptors: [HTMLNavigationSnapshotDescriptor]) {
        guard let pageSize = artifact.pageSize,
              !descriptors.isEmpty,
              artifact.navigationMode != .generic else {
            return
        }

        let generation = UUID()
        snapshotGeneration = generation
        generateSnapshot(at: 0, descriptors: descriptors, pageSize: pageSize, generation: generation)
    }

    private func generateSnapshot(
        at index: Int,
        descriptors: [HTMLNavigationSnapshotDescriptor],
        pageSize: CGSize,
        generation: UUID
    ) {
        guard generation == snapshotGeneration,
              descriptors.indices.contains(index) else {
            return
        }

        let descriptor = descriptors[index]
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: descriptor.offset, width: pageSize.width, height: pageSize.height)
        configuration.snapshotWidth = 132

        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self, generation == self.snapshotGeneration else { return }
            self.controller?.updateImage(image, for: descriptor.id)
            self.generateSnapshot(at: index + 1, descriptors: descriptors, pageSize: pageSize, generation: generation)
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private enum MarkdownPreviewRenderer {
    private enum ListKind {
        case unordered
        case ordered

        nonisolated var htmlTag: String {
            switch self {
            case .unordered:
                return "ul"
            case .ordered:
                return "ol"
            }
        }
    }

    nonisolated static func renderDocument(markdown: String, title: String) -> String {
        let bodyHTML = renderBlocks(markdown)
        let safeTitle = escapeHTML(title.isEmpty ? "Markdown" : title)
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(safeTitle)</title>
        <style>
        :root {
          color-scheme: light dark;
          --bg: transparent;
          --fg: #1f2328;
          --muted: #59636e;
          --line: rgba(31,35,40,0.10);
          --card: rgba(175,184,193,0.12);
          --card-strong: rgba(175,184,193,0.22);
          --link: #0969da;
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg: transparent;
            --fg: #e6edf3;
            --muted: #9da7b3;
            --line: rgba(240,246,252,0.10);
            --card: rgba(110,118,129,0.18);
            --card-strong: rgba(110,118,129,0.28);
            --link: #58a6ff;
          }
        }
        * { box-sizing: border-box; }
        html, body { margin: 0; padding: 0; background: transparent; }
        body {
          padding: 24px 26px 32px;
          color: var(--fg);
          background: transparent;
          font: 16px/1.72 -apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"PingFang SC\", sans-serif;
          word-break: break-word;
        }
        article { max-width: 860px; margin: 0 auto; }
        h1, h2, h3, h4, h5, h6 {
          margin: 1.4em 0 0.55em;
          line-height: 1.25;
          font-weight: 700;
          letter-spacing: -0.01em;
        }
        h1 { font-size: 2rem; }
        h2 { font-size: 1.55rem; padding-bottom: 0.28em; border-bottom: 1px solid var(--line); }
        h3 { font-size: 1.24rem; }
        p, ul, ol, blockquote, pre, table { margin: 0 0 1em; }
        ul, ol { padding-left: 1.45em; }
        li + li { margin-top: 0.28em; }
        blockquote {
          margin-left: 0;
          padding: 0.15em 0 0.15em 1em;
          color: var(--muted);
          border-left: 3px solid var(--card-strong);
        }
        hr {
          border: 0;
          height: 1px;
          margin: 1.5em 0;
          background: var(--line);
        }
        a {
          color: var(--link);
          text-decoration: none;
        }
        a:hover { text-decoration: underline; }
        pre {
          padding: 14px 16px;
          overflow-x: auto;
          border: 1px solid var(--line);
          border-radius: 12px;
          background: var(--card);
        }
        code, pre code {
          font: 13px/1.65 SFMono-Regular, SF Mono, Menlo, Monaco, Consolas, monospace;
        }
        :not(pre) > code {
          padding: 0.14em 0.4em;
          border-radius: 6px;
          background: var(--card);
        }
        pre code {
          display: block;
          white-space: pre;
          background: transparent;
        }
        table {
          width: 100%;
          border-collapse: collapse;
          border-spacing: 0;
          overflow: hidden;
          border: 1px solid var(--line);
          border-radius: 12px;
        }
        th, td {
          padding: 10px 12px;
          text-align: left;
          border-bottom: 1px solid var(--line);
        }
        thead th {
          font-weight: 600;
          background: var(--card);
        }
        tbody tr:last-child td { border-bottom: 0; }
        img {
          max-width: 100%;
          border-radius: 12px;
        }
        .language-badge {
          display: inline-flex;
          align-items: center;
          margin-bottom: 8px;
          padding: 0.18em 0.55em;
          border-radius: 999px;
          background: var(--card-strong);
          color: var(--muted);
          font: 11px/1.2 -apple-system, BlinkMacSystemFont, \"SF Pro Text\", sans-serif;
          text-transform: uppercase;
          letter-spacing: 0.06em;
        }
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(bodyHTML)
        </article>
        </body>
        </html>
        """
    }

    nonisolated private static func renderBlocks(_ markdown: String) -> String {
        let lines = normalizedLines(for: markdown)
        var htmlBlocks: [String] = []
        var paragraphLines: [String] = []
        var listItems: [String] = []
        var listKind: ListKind?
        var quoteLines: [String] = []
        var index = 0
        var codeFence: (marker: String, language: String, lines: [String])?

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let paragraph = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " ")
            htmlBlocks.append("<p>\(renderInline(paragraph))</p>")
            paragraphLines.removeAll()
        }

        func flushList() {
            guard let currentListKind = listKind, !listItems.isEmpty else { return }
            let body = listItems.map { "<li>\(renderInline($0))</li>" }.joined()
            htmlBlocks.append("<\(currentListKind.htmlTag)>\(body)</\(currentListKind.htmlTag)>")
            listKind = nil
            listItems.removeAll()
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            let body = quoteLines
                .map { "<p>\(renderInline($0))</p>" }
                .joined()
            htmlBlocks.append("<blockquote>\(body)</blockquote>")
            quoteLines.removeAll()
        }

        func flushPending() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if var activeCodeFence = codeFence {
                if isCodeFenceEnd(trimmed, marker: activeCodeFence.marker) {
                    htmlBlocks.append(renderCodeBlock(language: activeCodeFence.language, code: activeCodeFence.lines.joined(separator: "\n")))
                    codeFence = nil
                    index += 1
                    continue
                }

                activeCodeFence.lines.append(line)
                codeFence = activeCodeFence
                index += 1
                continue
            }

            if trimmed.isEmpty {
                flushPending()
                index += 1
                continue
            }

            if let table = parseTable(lines: lines, startIndex: index) {
                flushPending()
                htmlBlocks.append(table.html)
                index = table.nextIndex
                continue
            }

            if let fence = parseCodeFenceStart(trimmed) {
                flushPending()
                codeFence = (marker: fence.marker, language: fence.language, lines: [])
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                flushPending()
                htmlBlocks.append("<hr>")
                index += 1
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushPending()
                htmlBlocks.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
                index += 1
                continue
            }

            if let item = parseListItem(trimmed) {
                flushParagraph()
                flushQuote()
                if listKind != item.kind {
                    flushList()
                    listKind = item.kind
                }
                listItems.append(item.text)
                index += 1
                continue
            }

            if let quote = parseBlockquote(trimmed) {
                flushParagraph()
                flushList()
                quoteLines.append(quote)
                index += 1
                continue
            }

            paragraphLines.append(trimmed)
            index += 1
        }

        if let codeFence {
            htmlBlocks.append(renderCodeBlock(language: codeFence.language, code: codeFence.lines.joined(separator: "\n")))
        }
        flushPending()
        return htmlBlocks.joined(separator: "\n")
    }

    nonisolated private static func normalizedLines(for markdown: String) -> [String] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    nonisolated private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else {
            return nil
        }
        let text = line.dropFirst(level + 1).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    nonisolated private static func parseCodeFenceStart(_ line: String) -> (marker: String, language: String)? {
        if line.hasPrefix("```") {
            let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return ("```", language)
        }
        if line.hasPrefix("~~~") {
            let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return ("~~~", language)
        }
        return nil
    }

    nonisolated private static func isCodeFenceEnd(_ line: String, marker: String) -> Bool {
        line == marker || line.hasPrefix(marker)
    }

    nonisolated private static func parseListItem(_ line: String) -> (kind: ListKind, text: String)? {
        if let unordered = line.firstMatch(of: #"^[-*+]\s+(.+)$"#) {
            return (.unordered, unordered)
        }
        if let ordered = line.firstMatch(of: #"^\d+\.\s+(.+)$"#) {
            return (.ordered, ordered)
        }
        return nil
    }

    nonisolated private static func parseBlockquote(_ line: String) -> String? {
        line.firstMatch(of: #"^>\s?(.*)$"#)
    }

    nonisolated private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        return compact == "---" || compact == "***" || compact == "___"
    }

    nonisolated private static func parseTable(lines: [String], startIndex: Int) -> (html: String, nextIndex: Int)? {
        guard startIndex + 1 < lines.count else { return nil }
        let headerLine = lines[startIndex].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[startIndex + 1].trimmingCharacters(in: .whitespaces)
        guard headerLine.contains("|"), isMarkdownTableSeparator(separatorLine) else {
            return nil
        }

        let headers = splitTableRow(headerLine)
        guard !headers.isEmpty else { return nil }

        var rows: [[String]] = []
        var index = startIndex + 2
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains("|") else { break }
            rows.append(splitTableRow(trimmed))
            index += 1
        }

        let headerHTML = headers.map { "<th>\(renderInline($0))</th>" }.joined()
        let bodyHTML = rows.map { row in
            let columns = row.map { "<td>\(renderInline($0))</td>" }.joined()
            return "<tr>\(columns)</tr>"
        }.joined()

        let html = """
        <table>
        <thead><tr>\(headerHTML)</tr></thead>
        <tbody>\(bodyHTML)</tbody>
        </table>
        """
        return (html, index)
    }

    nonisolated private static func isMarkdownTableSeparator(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.contains("|") else { return false }
        let pattern = #"^\|?[:\-|]+\|?$"#
        return (try? NSRegularExpression(pattern: pattern))
            .map { regex in
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                return regex.firstMatch(in: line, range: range) != nil
            } ?? false
    }

    nonisolated private static func splitTableRow(_ line: String) -> [String] {
        var content = line
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    nonisolated private static func renderCodeBlock(language: String, code: String) -> String {
        let escapedCode = escapeHTML(code)
        let badge = language.isEmpty ? "" : "<div class=\"language-badge\">\(escapeHTML(language))</div>"
        return """
        <pre>\(badge)<code class=\"language-\(escapeHTML(language.lowercased()))\">\(escapedCode)</code></pre>
        """
    }

    nonisolated private static func renderInline(_ text: String) -> String {
        var protectedFragments: [String: String] = [:]
        var tokenIndex = 0

        func protect(_ html: String) -> String {
            // Keep placeholder tokens free of Markdown punctuation so later inline
            // passes cannot mutate them before we restore the protected HTML.
            let token = "%%EDGEMDTOKEN\(tokenIndex)%%"
            tokenIndex += 1
            protectedFragments[token] = html
            return token
        }

        var html = escapeHTML(text)
        html = replace(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#, in: html) { groups in
            let alt = groups[0]
            let url = groups[1]
            return protect("<img src=\"\(url)\" alt=\"\(alt)\">")
        }
        html = replace(pattern: #"\[([^\]]+)\]\(([^)]+)\)"#, in: html) { groups in
            let label = groups[0]
            let destination = groups[1]
            return protect("<a href=\"\(destination)\">\(label)</a>")
        }
        html = replace(pattern: #"`([^`\n]+)`"#, in: html) { groups in
            protect("<code>\(groups[0])</code>")
        }
        html = replace(pattern: #"\*\*([^\*]+)\*\*"#, in: html) { groups in
            "<strong>\(groups[0])</strong>"
        }
        html = replace(pattern: #"__([^_]+)__"#, in: html) { groups in
            "<strong>\(groups[0])</strong>"
        }
        html = replace(pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#, in: html) { groups in
            "<em>\(groups[0])</em>"
        }
        html = replace(pattern: #"(?<!_)_([^_\n]+)_(?!_)"#, in: html) { groups in
            "<em>\(groups[0])</em>"
        }
        html = replace(pattern: #"~~([^~]+)~~"#, in: html) { groups in
            "<del>\(groups[0])</del>"
        }

        for (token, fragment) in protectedFragments {
            html = html.replacingOccurrences(of: token, with: fragment)
        }
        return html
    }

    nonisolated private static func replace(
        pattern: String,
        in text: String,
        transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
        guard !matches.isEmpty else { return text }

        var output = ""
        var cursor = text.startIndex

        for match in matches {
            guard let fullRange = Range(match.range, in: text) else { continue }
            output += text[cursor..<fullRange.lowerBound]

            let groups = (1..<match.numberOfRanges).compactMap { index -> String? in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
            output += transform(groups)
            cursor = fullRange.upperBound
        }

        output += text[cursor...]
        return output
    }

    nonisolated private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension String {
    nonisolated func firstMatch(of pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range),
              match.numberOfRanges > 1,
              let resultRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[resultRange])
    }
}

private struct ReadOnlyTextPreviewView: NSViewRepresentable {
    let text: String
    var usesMonospacedFont = false
    var bottomContentInset: CGFloat = 0
    var onScrolledToBottomChanged: ((Bool) -> Void)? = nil

    final class Coordinator {
        var configuration: Configuration?
        var boundsObserver: NSObjectProtocol?
        var onScrolledToBottomChanged: ((Bool) -> Void)?
        var lastReportedBottomState: Bool?

        deinit {
            removeBoundsObserver()
        }

        func updateBoundsObserver(for scrollView: NSScrollView) {
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = onScrolledToBottomChanged != nil

            guard onScrolledToBottomChanged != nil else {
                removeBoundsObserver()
                lastReportedBottomState = nil
                return
            }

            guard boundsObserver == nil else { return }
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.reportScrolledToBottom(for: scrollView)
            }
        }

        func removeBoundsObserver() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }
        }

        func scheduleBottomStateReport(for scrollView: NSScrollView) {
            guard onScrolledToBottomChanged != nil else { return }
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.reportScrolledToBottom(for: scrollView)
            }
        }

        private func reportScrolledToBottom(for scrollView: NSScrollView) {
            let isAtBottom = Self.isScrolledToBottom(in: scrollView)
            guard lastReportedBottomState != isAtBottom else { return }
            lastReportedBottomState = isAtBottom
            onScrolledToBottomChanged?(isAtBottom)
        }

        private static func isScrolledToBottom(in scrollView: NSScrollView) -> Bool {
            guard let documentView = scrollView.documentView else {
                return true
            }

            let visibleRect = scrollView.documentVisibleRect
            if documentView.bounds.height <= visibleRect.height + 1 {
                return true
            }

            return visibleRect.maxY >= documentView.bounds.maxY - 1
        }
    }

    fileprivate struct Configuration: Equatable {
        let text: String
        let usesMonospacedFont: Bool
        let bottomContentInset: CGFloat
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomContentInset, right: 0)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 2, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.font = textFont
        textView.textStorage?.setAttributedString(makeAttributedText(for: text))
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        scrollView.documentView = textView
        context.coordinator.onScrolledToBottomChanged = onScrolledToBottomChanged
        context.coordinator.updateBoundsObserver(for: scrollView)
        context.coordinator.configuration = configuration
        context.coordinator.scheduleBottomStateReport(for: scrollView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }

        nsView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: bottomContentInset, right: 0)
        context.coordinator.onScrolledToBottomChanged = onScrolledToBottomChanged
        context.coordinator.updateBoundsObserver(for: nsView)

        if context.coordinator.configuration != configuration {
            textView.textStorage?.setAttributedString(makeAttributedText(for: text))
            context.coordinator.configuration = configuration
            context.coordinator.lastReportedBottomState = nil
            context.coordinator.scheduleBottomStateReport(for: nsView)
        } else {
            context.coordinator.scheduleBottomStateReport(for: nsView)
        }

        textView.font = textFont
    }

    private var textFont: NSFont {
        if usesMonospacedFont {
            return .monospacedSystemFont(ofSize: 14, weight: .regular)
        }
        return .systemFont(ofSize: 15)
    }

    private var configuration: Configuration {
        Configuration(
            text: text,
            usesMonospacedFont: usesMonospacedFont,
            bottomContentInset: bottomContentInset
        )
    }

    private func makeAttributedText(for text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.paragraphSpacing = 0

        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]

        attributed.append(NSAttributedString(string: text, attributes: attributes))
        return attributed
    }
}

private struct QuickLookPreviewItemView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView(frame: .zero, style: .normal)!
        previewView.autostarts = true
        previewView.shouldCloseWithWindow = true
        let item = PreviewItem(url: url)
        context.coordinator.previewItem = item
        previewView.previewItem = item
        previewView.refreshPreviewItem()
        return previewView
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        let currentURL = context.coordinator.previewItem?.previewItemURL?.standardizedFileURL
        guard currentURL != url.standardizedFileURL else { return }
        let item = PreviewItem(url: url)
        context.coordinator.previewItem = item
        nsView.previewItem = item
        nsView.refreshPreviewItem()
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: Coordinator) {
        nsView.close()
        coordinator.previewItem = nil
    }

    final class Coordinator {
        var previewItem: PreviewItem?
    }
}

private struct QuickLookSlidesPreviewView: View {
    let url: URL

    @StateObject private var controller = QuickLookSlidesController()

    var body: some View {
        HStack(spacing: 0) {
            if !controller.items.isEmpty {
                DocumentNavigationSidebar(
                    items: controller.items,
                    selectedID: controller.selectedID,
                    onSelect: { controller.selectPage(id: $0) }
                )
                Divider()
            }

            QuickLookSlidesRepresentable(url: url, controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@MainActor
private final class QuickLookSlidesController: ObservableObject {
    @Published var items: [DocumentNavigationItem] = []
    @Published var selectedID: String?

    func reset() {
        items = []
        selectedID = nil
    }

    func updatePageCount(_ count: Int) {
        guard count > 0 else {
            items = []
            selectedID = nil
            return
        }

        var existingImages: [String: NSImage] = [:]
        for item in items {
            if let image = item.image {
                existingImages[item.id] = image
            }
        }
        let newItems: [DocumentNavigationItem] = (0..<count).map { index in
            let id = "slide-\(index)"
            return DocumentNavigationItem(
                id: id,
                title: FullPreviewLocalizationSupport.pageTitle(index + 1),
                subtitle: nil,
                image: existingImages[id]
            )
        }

        items = newItems
        if let selectedID, newItems.contains(where: { $0.id == selectedID }) {
            return
        }
        self.selectedID = newItems.first?.id
    }

    func selectPage(id: String) {
        selectedID = id
    }

    func updateSelectedPage(index: Int) {
        guard items.indices.contains(index) else { return }
        let newID = items[index].id
        if selectedID != newID {
            selectedID = newID
        }
    }

    func updateImage(_ image: NSImage?, for index: Int) {
        guard items.indices.contains(index) else { return }
        updateImage(image, for: items[index].id)
    }

    func updateImage(_ image: NSImage?, for id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].image == nil || image != nil else { return }

        var updated = items[index]
        updated = DocumentNavigationItem(
            id: updated.id,
            title: updated.title,
            subtitle: updated.subtitle,
            image: image
        )
        items[index] = updated
    }
}

private struct QuickLookSlidesRepresentable: NSViewRepresentable {
    let url: URL
    @ObservedObject var controller: QuickLookSlidesController

    func makeNSView(context: Context) -> QuickLookSlidesHostView {
        let host = QuickLookSlidesHostView(url: url, controller: controller)
        context.coordinator.hostView = host
        host.load()
        return host
    }

    func updateNSView(_ nsView: QuickLookSlidesHostView, context: Context) {
        nsView.update(url: url, selectedID: controller.selectedID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static func dismantleNSView(_ nsView: QuickLookSlidesHostView, coordinator: Coordinator) {
        nsView.teardown()
        coordinator.hostView = nil
    }

    final class Coordinator {
        weak var hostView: QuickLookSlidesHostView?
    }
}

private struct QuickLookSlidesDiscoveredPage {
    let id: String
    let title: String
    let image: NSImage?
    let displayState: Any
}

private final class QuickLookSlidesHostView: NSView {
    private var currentURL: URL
    private weak var controller: QuickLookSlidesController?
    private let previewView = QLPreviewView(frame: .zero, style: .normal)!
    private var previewItem: PreviewItem?
    private var localMonitor: Any?
    private let discoveryController = QuickLookSlidesDiscoveryController()
    private var discoveredPages: [QuickLookSlidesDiscoveredPage] = []
    private var currentPageIndex = 0
    private var lastWheelTimestamp: TimeInterval = 0
    private var isApplyingSelection = false

    init(url: URL, controller: QuickLookSlidesController) {
        self.currentURL = url.standardizedFileURL
        self.controller = controller
        super.init(frame: .zero)

        wantsLayer = true
        previewView.autostarts = true
        previewView.shouldCloseWithWindow = true
        addSubview(previewView)
        installScrollMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewView.frame = bounds
    }

    func load() {
        loadVisiblePreviewItem()
        scheduleRefresh()
    }

    func update(url: URL, selectedID: String?) {
        let normalizedURL = url.standardizedFileURL
        if currentURL != normalizedURL {
            currentURL = normalizedURL
            prepareForURLChange()
            load()
            return
        }

        updateSelection(id: selectedID)
    }

    private func updateSelection(id: String?) {
        guard let id,
              let index = controller?.items.firstIndex(where: { $0.id == id }),
              discoveredPages.indices.contains(index),
              currentPageIndex != index else {
            return
        }
        applyDiscoveredPage(index: index)
    }

    func teardown() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        discoveryController.teardown()
        previewView.previewItem = nil
        previewView.close()
        previewItem = nil
        scheduleControllerReset()
        previewView.removeFromSuperview()
    }

    private func prepareForURLChange() {
        discoveryController.cancel()
        discoveredPages = []
        currentPageIndex = 0
        lastWheelTimestamp = 0
        isApplyingSelection = false
        previewView.previewItem = nil
        previewItem = nil
        scheduleControllerReset()
    }

    private func loadVisiblePreviewItem() {
        let item: PreviewItem
        if let previewItem {
            previewItem.update(url: currentURL)
            item = previewItem
        } else {
            let newItem = PreviewItem(url: currentURL)
            previewItem = newItem
            item = newItem
            previewView.previewItem = item
        }

        previewView.refreshPreviewItem()
    }

    private func installScrollMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScrollWheel(event)
        }
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard discoveredPages.count > 1,
              window === event.window else {
            return event
        }

        let windowPoint = event.locationInWindow
        let localPoint = convert(windowPoint, from: nil)
        guard bounds.contains(localPoint) else {
            return event
        }

        let deltaY = event.scrollingDeltaY
        guard abs(deltaY) > abs(event.scrollingDeltaX), abs(deltaY) > 2 else {
            return nil
        }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastWheelTimestamp > 0.18 else {
            return nil
        }
        lastWheelTimestamp = now

        if deltaY < 0 {
            applyDiscoveredPage(index: min(currentPageIndex + 1, discoveredPages.count - 1))
        } else {
            applyDiscoveredPage(index: max(currentPageIndex - 1, 0))
        }

        return nil
    }

    private func scheduleRefresh() {
        discoveryController.start(
            url: currentURL,
            onUpdate: { [weak self] pages in
                guard let self else { return }
                self.applyDiscoveredPages(pages, isFinal: false)
            },
            onComplete: { [weak self] pages in
                guard let self else { return }
                self.applyDiscoveredPages(pages, isFinal: true)
            }
        )
    }

    private func applyDiscoveredPages(_ pages: [QuickLookSlidesDiscoveredPage], isFinal _: Bool) {
        let sessionURL = currentURL
        let previousSelectedID = controller?.selectedID
        let previousSelectedIndex = currentPageIndex
        discoveredPages = pages
        if pages.isEmpty {
            scheduleControllerReset(for: sessionURL)
            return
        }

        let targetSelectedID: String
        if let previousSelectedID,
           let selectedIndex = pages.firstIndex(where: { $0.id == previousSelectedID }) {
            currentPageIndex = selectedIndex
            targetSelectedID = previousSelectedID
        } else if pages.indices.contains(previousSelectedIndex) {
            currentPageIndex = previousSelectedIndex
            targetSelectedID = pages[previousSelectedIndex].id
        } else {
            currentPageIndex = 0
            targetSelectedID = pages.first?.id ?? ""
            applyDiscoveredPage(index: 0)
        }

        scheduleControllerSync(
            pages: pages,
            targetSelectedID: targetSelectedID,
            for: sessionURL
        )
    }

    private func applyDiscoveredPage(index: Int) {
        guard discoveredPages.indices.contains(index) else { return }
        isApplyingSelection = true
        currentPageIndex = index
        let page = discoveredPages[index]
        previewView.displayState = cloneDisplayState(page.displayState) ?? page.displayState
        controller?.updateSelectedPage(index: index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.isApplyingSelection = false
        }
    }

    private func cloneDisplayState(_ state: Any) -> Any? {
        guard let object = state as? NSObject,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false),
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else {
            return nil
        }
        unarchiver.requiresSecureCoding = false
        let cloned = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()
        return cloned
    }

    private func scheduleControllerReset(for url: URL? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let url, self.currentURL != url {
                return
            }
            self.controller?.reset()
        }
    }

    private func scheduleControllerSync(
        pages: [QuickLookSlidesDiscoveredPage],
        targetSelectedID: String,
        for url: URL
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.currentURL == url else { return }
            guard let controller = self.controller else { return }

            controller.updatePageCount(pages.count)
            for (index, page) in pages.enumerated() where page.image != nil {
                controller.updateImage(page.image, for: index)
            }

            if !targetSelectedID.isEmpty {
                controller.selectPage(id: targetSelectedID)
            }
        }
    }
}

private final class QuickLookSlidesDiscoveryController {
    private let window: NSWindow
    private let previewView = QLPreviewView(frame: .zero, style: .normal)!
    private var currentURL: URL?
    private var previewItem: PreviewItem?
    private var onUpdate: (([QuickLookSlidesDiscoveredPage]) -> Void)?
    private var onComplete: (([QuickLookSlidesDiscoveredPage]) -> Void)?
    private var pages: [QuickLookSlidesDiscoveredPage] = []
    private var lastFingerprint: String?
    private var unchangedCount = 0
    private var sessionToken = UUID()
    private var isTornDown = false

    init() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: screenFrame.maxX + 240, y: screenFrame.midY - 220, width: 760, height: 440)
        self.window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.backgroundColor = .white
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))

        previewView.autostarts = true
        previewView.shouldCloseWithWindow = false
        previewView.frame = window.contentView?.bounds ?? .zero
        previewView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(previewView)
    }

    func start(
        url: URL,
        onUpdate: @escaping ([QuickLookSlidesDiscoveredPage]) -> Void,
        onComplete: @escaping ([QuickLookSlidesDiscoveredPage]) -> Void
    ) {
        guard !isTornDown else { return }
        cancel()
        currentURL = url.standardizedFileURL
        self.onUpdate = onUpdate
        self.onComplete = onComplete
        pages = []
        lastFingerprint = nil
        unchangedCount = 0
        let token = UUID()
        sessionToken = token

        let item: PreviewItem
        if let previewItem {
            previewItem.update(url: currentURL!)
            item = previewItem
        } else {
            let newItem = PreviewItem(url: currentURL!)
            previewItem = newItem
            item = newItem
            previewView.previewItem = item
        }

        window.orderFrontRegardless()
        window.makeFirstResponder(previewView)
        previewView.refreshPreviewItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.captureCurrentPage(attempt: 0, token: token)
        }
    }

    func cancel() {
        guard !isTornDown else { return }
        sessionToken = UUID()
        onUpdate = nil
        onComplete = nil
        pages = []
        lastFingerprint = nil
        unchangedCount = 0
        previewView.previewItem = nil
        previewItem = nil
        window.orderOut(nil)
    }

    func teardown() {
        guard !isTornDown else { return }
        isTornDown = true
        cancel()
        previewView.close()
        previewView.removeFromSuperview()
        window.contentView = nil
        window.close()
    }

    private func captureCurrentPage(attempt: Int, token: UUID) {
        guard isActive(token) else { return }

        guard let state = previewView.displayState,
              let fingerprint = fingerprint(for: state) else {
            if attempt < 24 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    self?.captureCurrentPage(attempt: attempt + 1, token: token)
                }
            } else {
                finish(token: token)
            }
            return
        }

        if pages.isEmpty || lastFingerprint != fingerprint {
            let index = pages.count
            let image = captureWindowThumbnail()
            let page = QuickLookSlidesDiscoveredPage(
                id: "slide-\(index)",
                title: FullPreviewLocalizationSupport.pageTitle(index + 1),
                image: image,
                displayState: state
            )
            pages.append(page)
            lastFingerprint = fingerprint
            unchangedCount = 0
            onUpdate?(pages)
            advanceToNextPage(after: fingerprint, token: token)
            return
        }

        waitForNextPageChange(after: fingerprint, attempt: attempt + 1, token: token)
    }

    private func advanceToNextPage(after previousFingerprint: String, token: UUID) {
        guard isActive(token) else { return }
        sendPageNavigation(forward: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.waitForNextPageChange(after: previousFingerprint, attempt: 0, token: token)
        }
    }

    private func waitForNextPageChange(after previousFingerprint: String, attempt: Int, token: UUID) {
        guard isActive(token) else { return }

        if let state = previewView.displayState,
           let fingerprint = fingerprint(for: state),
           fingerprint != previousFingerprint {
            captureCurrentPage(attempt: 0, token: token)
            return
        }

        if attempt < 8 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                self?.waitForNextPageChange(after: previousFingerprint, attempt: attempt + 1, token: token)
            }
            return
        }

        unchangedCount += 1
        if unchangedCount >= 2 {
            finish(token: token)
            return
        }

        advanceToNextPage(after: previousFingerprint, token: token)
    }

    private func sendPageNavigation(forward: Bool) {
        let keyCode: UInt16 = forward ? 121 : 116 // page down / page up
        let characters = forward ? "\u{F72D}" : "\u{F72C}"
        let location = NSPoint(x: previewView.bounds.midX, y: previewView.bounds.midY)
        let windowLocation = previewView.convert(location, to: nil)

        guard let keyDown = NSEvent.keyEvent(
            with: .keyDown,
            location: windowLocation,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ),
        let keyUp = NSEvent.keyEvent(
            with: .keyUp,
            location: windowLocation,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            return
        }

        previewView.keyDown(with: keyDown)
        previewView.keyUp(with: keyUp)
    }

    private func captureWindowThumbnail() -> NSImage? {
        guard let contentView = window.contentView else { return nil }

        let bounds = contentView.bounds
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }

        bitmap.size = bounds.size
        contentView.cacheDisplay(in: bounds, to: bitmap)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmap)
        return resizedThumbnail(from: image, maxSize: NSSize(width: 176, height: 124))
    }

    private func fingerprint(for state: Any) -> String? {
        guard let object = state as? NSObject else { return nil }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: false) {
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        return String(describing: object)
    }

    private func finish(token: UUID) {
        guard isActive(token) else { return }
        let onComplete = self.onComplete
        self.onUpdate = nil
        self.onComplete = nil
        previewView.previewItem = nil
        previewItem = nil
        window.orderOut(nil)
        onComplete?(pages)
    }

    private func isActive(_ token: UUID) -> Bool {
        !isTornDown && sessionToken == token
    }
}

nonisolated private func resizedThumbnail(from image: NSImage, maxSize: NSSize) -> NSImage {
    guard image.size.width > 0, image.size.height > 0 else { return image }

    let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height)
    let clampedScale = min(scale, 1)
    let targetSize = NSSize(
        width: max(1, floor(image.size.width * clampedScale)),
        height: max(1, floor(image.size.height * clampedScale))
    )

    let thumbnail = NSImage(size: targetSize)
    thumbnail.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(origin: .zero, size: targetSize),
        from: NSRect(origin: .zero, size: image.size),
        operation: .copy,
        fraction: 1
    )
    thumbnail.unlockFocus()
    return thumbnail
}

private final class PreviewItem: NSObject, QLPreviewItem {
    private(set) var previewItemURL: URL?
    private(set) var previewItemTitle: String?

    init(url: URL) {
        self.previewItemURL = url
        self.previewItemTitle = url.lastPathComponent
        super.init()
    }

    func update(url: URL) {
        previewItemURL = url
        previewItemTitle = url.lastPathComponent
    }
}
