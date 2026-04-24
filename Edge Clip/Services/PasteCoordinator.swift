import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PasteCoordinator {
    private final class LazyImagePasteboardDataProvider: NSObject, NSPasteboardItemDataProvider {
        private let sourceURL: URL?
        private let fallbackImage: NSImage?
        private var cachedImage: NSImage?
        private let originalImageType: NSPasteboard.PasteboardType?

        let supportedTypes: [NSPasteboard.PasteboardType]

        init(sourceURL: URL?, fallbackImage: NSImage?) {
            self.sourceURL = sourceURL
            self.fallbackImage = fallbackImage
            if let sourceURL,
               let type = UTType(filenameExtension: sourceURL.pathExtension),
               type.conforms(to: .image) {
                self.originalImageType = NSPasteboard.PasteboardType(type.identifier)
            } else {
                self.originalImageType = nil
            }

            var types: [NSPasteboard.PasteboardType] = [
                NSPasteboard.PasteboardType(UTType.png.identifier),
                .tiff
            ]
            if let originalImageType {
                types.insert(originalImageType, at: 0)
            }
            if sourceURL?.pathExtension.lowercased() == "png" {
                types.insert(NSPasteboard.PasteboardType(UTType.png.identifier), at: 0)
            }
            supportedTypes = Array(NSOrderedSet(array: types)) as? [NSPasteboard.PasteboardType] ?? types
        }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            if let originalImageType,
               type == originalImageType {
                if let data = originalImageData() {
                    item.setData(data, forType: type)
                }
                return
            }

            switch type {
            case NSPasteboard.PasteboardType(UTType.png.identifier):
                if let data = pngData() {
                    item.setData(data, forType: type)
                }
            case .tiff:
                if let data = tiffData() {
                    item.setData(data, forType: type)
                }
            default:
                break
            }
        }

        func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
            cachedImage = nil
        }

        private func originalImageData() -> Data? {
            guard let sourceURL else { return nil }
            return try? Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        }

        private func pngData() -> Data? {
            if let sourceURL,
               sourceURL.pathExtension.lowercased() == "png" {
                return try? Data(contentsOf: sourceURL, options: [.mappedIfSafe])
            }

            guard let image = loadImage(),
                  let tiff = image.tiffRepresentation,
                  let representation = NSBitmapImageRep(data: tiff) else {
                return nil
            }
            return representation.representation(using: .png, properties: [:])
        }

        private func tiffData() -> Data? {
            loadImage()?.tiffRepresentation
        }

        private func loadImage() -> NSImage? {
            if let cachedImage {
                return cachedImage
            }

            if let sourceURL,
               let image = NSImage(contentsOf: sourceURL) {
                cachedImage = image
                return image
            }

            cachedImage = fallbackImage
            return fallbackImage
        }
    }

    private let fileManager = FileManager.default
    private var activePasteboardDataProviders: [NSObject] = []

    enum PasteResult {
        case autoPasted
        case copiedOnly
        case failed(String)
    }

    enum PasteboardWriteResult {
        case success
        case failed(String)
    }

    func paste(
        item: ClipboardItem,
        settings: AppSettings,
        focusTracker: FocusTracker,
        textProvider: (ClipboardItem) -> String?,
        imageAssetURLProvider: (String) -> URL?,
        imageProvider: (ClipboardItem) -> NSImage?,
        didWriteToPasteboard: @escaping () -> Void,
        didCollapsePanel: @escaping () -> Void
    ) async -> PasteResult {
        let pasteboard = NSPasteboard.general
        switch write(
            item: item,
            to: pasteboard,
            textProvider: textProvider,
            imageAssetURLProvider: imageAssetURLProvider,
            imageProvider: imageProvider
        ) {
        case .success:
            didWriteToPasteboard()
        case let .failed(message):
            return .failed(message)
        }

        return await completePasteFlow(
            settings: settings,
            focusTracker: focusTracker,
            didCollapsePanel: didCollapsePanel
        )
    }

    func pasteCurrentClipboard(
        settings: AppSettings,
        focusTracker: FocusTracker,
        didCollapsePanel: @escaping () -> Void
    ) async -> PasteResult {
        await completePasteFlow(
            settings: settings,
            focusTracker: focusTracker,
            didCollapsePanel: didCollapsePanel
        )
    }

    func copyToPasteboard(
        item: ClipboardItem,
        textProvider: (ClipboardItem) -> String?,
        imageAssetURLProvider: (String) -> URL?,
        imageProvider: (ClipboardItem) -> NSImage?
    ) -> PasteboardWriteResult {
        write(
            item: item,
            to: .general,
            textProvider: textProvider,
            imageAssetURLProvider: imageAssetURLProvider,
            imageProvider: imageProvider
        )
    }

    func writeTextToPasteboard(_ text: String, to pasteboard: NSPasteboard = .general) -> PasteboardWriteResult {
        guard !text.isEmpty else {
            return .failed("无法写入空文本到系统剪切板")
        }

        activePasteboardDataProviders.removeAll()

        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) {
            return .success
        }

        pasteboard.clearContents()
        if pasteboard.writeObjects([text as NSString]) {
            return .success
        }

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(text.utf8), forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
        if let utf16Data = text.data(using: .utf16LittleEndian) {
            item.setData(
                utf16Data,
                forType: NSPasteboard.PasteboardType("public.utf16-external-plain-text")
            )
        }

        pasteboard.clearContents()
        if pasteboard.writeObjects([item]) {
            return .success
        }

        return .failed("文本暂时无法写入系统剪贴板，请再试一次。")
    }

    private func write(
        item: ClipboardItem,
        to pasteboard: NSPasteboard,
        textProvider: (ClipboardItem) -> String?,
        imageAssetURLProvider: (String) -> URL?,
        imageProvider: (ClipboardItem) -> NSImage?
    ) -> PasteboardWriteResult {
        switch item.kind {
        case .text:
            guard let text = textProvider(item) ?? item.textContent else {
                return .failed(AppLocalization.localized("当前只保留了预览内容，请重新复制一次原文。"))
            }
            return writeTextToPasteboard(text, to: pasteboard)
        case .passthroughText:
            return .failed(AppLocalization.localized("这是一条旧版会话文本，当前版本不支持再次写回。"))
        case .image:
            let fileURL: URL?
            if let relativePath = item.imageAssetRelativePath {
                fileURL = imageAssetURLProvider(relativePath)
            } else {
                fileURL = nil
            }
            let image = fileURL == nil ? imageProvider(item) : nil

            guard fileURL != nil || image != nil else {
                return .failed(AppLocalization.localized("图片资源不存在，无法写回剪切板"))
            }

            let stagedImageURL = fileURL.flatMap { stageFileURLsForPaste([$0])?.first }
            pasteboard.clearContents()
            guard writeImage(image, originalFileURL: fileURL, stagedFileURL: stagedImageURL, to: pasteboard) else {
                return .failed(AppLocalization.localized("无法写入图片到系统剪切板"))
            }
            return .success
        case .file:
            let resolved = resolveFileURLsForPaste(item)
            let urls = resolved.urls
            guard !urls.isEmpty else {
                resolved.stopAccess()
                return .failed(AppLocalization.localized("没有可写回的文件"))
            }

            defer { resolved.stopAccess() }
            guard let stagedURLs = stageFileURLsForPaste(urls), !stagedURLs.isEmpty else {
                return .failed(AppLocalization.localized("无法为文件创建可共享副本（文件权限可能已失效，请重新复制该文件）"))
            }
            pasteboard.clearContents()
            guard writeFileURLs(stagedURLs, to: pasteboard) else {
                return .failed(AppLocalization.localized("无法写入文件到系统剪切板（文件访问权限可能已失效，请重新复制该文件）"))
            }
            return .success
        case .stack:
            return .failed(AppLocalization.localized("堆栈条目不能直接写回系统剪切板"))
        }
    }

    private func writeImage(
        _ image: NSImage?,
        originalFileURL: URL?,
        stagedFileURL: URL?,
        to pasteboard: NSPasteboard
    ) -> Bool {
        let fileURLType = NSPasteboard.PasteboardType.fileURL
        let legacyFilesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

        let provider = LazyImagePasteboardDataProvider(
            sourceURL: originalFileURL,
            fallbackImage: image
        )
        guard !provider.supportedTypes.isEmpty else {
            return false
        }

        let item = NSPasteboardItem()
        if let stagedFileURL {
            item.setString(stagedFileURL.absoluteString, forType: fileURLType)
            item.setPropertyList([stagedFileURL.path], forType: legacyFilesType)
        }
        item.setDataProvider(provider, forTypes: provider.supportedTypes)

        activePasteboardDataProviders = []
        pasteboard.clearContents()
        let wrote = pasteboard.writeObjects([item])
        if wrote {
            activePasteboardDataProviders = [provider]
        } else {
            activePasteboardDataProviders.removeAll()
        }
        return wrote
    }

    private func writeFileURLs(_ urls: [URL], to pasteboard: NSPasteboard) -> Bool {
        guard !urls.isEmpty else { return false }

        let fileURLType = NSPasteboard.PasteboardType.fileURL
        let legacyFilesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let absoluteStrings = urls.map(\.absoluteString)
        let paths = urls.map(\.path)

        if urls.count == 1,
           let imageProvider = makeLazyImagePasteboardDataProvider(for: urls[0]) {
            let item = NSPasteboardItem()
            if let absoluteString = absoluteStrings.first {
                item.setString(absoluteString, forType: fileURLType)
            }
            item.setPropertyList(paths, forType: legacyFilesType)
            item.setDataProvider(imageProvider, forTypes: imageProvider.supportedTypes)

            activePasteboardDataProviders = []
            pasteboard.clearContents()
            let wrote = pasteboard.writeObjects([item])
            if wrote {
                activePasteboardDataProviders = [imageProvider]
            } else {
                activePasteboardDataProviders.removeAll()
            }
            return wrote
        }

        activePasteboardDataProviders.removeAll()
        pasteboard.clearContents()
        pasteboard.declareTypes([fileURLType, legacyFilesType], owner: nil)

        var wroteAnyType = false

        if urls.count == 1, let absoluteString = absoluteStrings.first {
            wroteAnyType = pasteboard.setString(absoluteString, forType: fileURLType) || wroteAnyType
        } else {
            wroteAnyType = pasteboard.setPropertyList(absoluteStrings, forType: fileURLType) || wroteAnyType
        }

        wroteAnyType = pasteboard.setPropertyList(paths, forType: legacyFilesType) || wroteAnyType

        return wroteAnyType
    }

    private func stageFileURLsForPaste(_ urls: [URL]) -> [URL]? {
        guard !urls.isEmpty else { return nil }

        do {
            let pasteStagingDirectory = makeFreshPasteStagingDirectory()
            if fileManager.fileExists(atPath: pasteStagingDirectory.path) {
                try fileManager.removeItem(at: pasteStagingDirectory)
            }
            try fileManager.createDirectory(at: pasteStagingDirectory, withIntermediateDirectories: true)

            var stagedURLs: [URL] = []
            stagedURLs.reserveCapacity(urls.count)

            for (index, url) in urls.enumerated() {
                let filename = sanitizedFilename(for: url, fallbackIndex: index)
                let destinationURL = uniqueDestinationURL(
                    in: pasteStagingDirectory,
                    preferredName: filename
                )
                try fileManager.copyItem(at: url, to: destinationURL)
                stagedURLs.append(destinationURL)
            }

            return stagedURLs
        } catch {
            return nil
        }
    }

    func canStageFileURLs(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        return stageFileURLsForPaste(urls) != nil
    }

    private func sanitizedFilename(for url: URL, fallbackIndex: Int) -> String {
        let rawName = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawName.isEmpty {
            return rawName
        }
        return "item-\(fallbackIndex)"
    }

    private func uniqueDestinationURL(in directory: URL, preferredName: String) -> URL {
        let baseName = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension

        var candidate = directory.appendingPathComponent(preferredName)
        var suffix = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let nextName: String
            if ext.isEmpty {
                nextName = "\(baseName)-\(suffix)"
            } else {
                nextName = "\(baseName)-\(suffix).\(ext)"
            }
            candidate = directory.appendingPathComponent(nextName)
            suffix += 1
        }
        return candidate
    }

    private func makeFreshPasteStagingDirectory() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("EdgeClipPasteStaging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeLazyImagePasteboardDataProvider(for fileURL: URL) -> LazyImagePasteboardDataProvider? {
        guard let type = UTType(filenameExtension: fileURL.pathExtension),
              type.conforms(to: .image) else {
            return nil
        }
        return LazyImagePasteboardDataProvider(sourceURL: fileURL, fallbackImage: nil)
    }

    private func resolveFileURLsForPaste(_ item: ClipboardItem) -> (urls: [URL], stopAccess: () -> Void) {
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

    private func sendPasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // 0x09 is the virtual key code for V on ANSI layout.
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func completePasteFlow(
        settings: AppSettings,
        focusTracker: FocusTracker,
        didCollapsePanel: @escaping () -> Void
    ) async -> PasteResult {
        didCollapsePanel()

        guard settings.autoPasteEnabled else {
            _ = focusTracker.restoreLastExternalApp()
            return .copiedOnly
        }

        guard PermissionCenter.isAccessibilityGranted() else {
            PermissionCenter.requestAccessibilityIfNeeded()
            _ = focusTracker.restoreLastExternalApp()
            return .copiedOnly
        }

        _ = focusTracker.restoreLastExternalApp()

        // Give the previous app a short moment to receive focus before sending Cmd+V.
        try? await Task.sleep(for: .milliseconds(100))
        sendPasteShortcut()

        return .autoPasted
    }
}
