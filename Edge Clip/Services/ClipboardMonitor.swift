import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ClipboardMonitor {
    private static let explicitPlainTextProbeTypes: [NSPasteboard.PasteboardType] = [
        .string,
        NSPasteboard.PasteboardType("NSStringPboardType"),
        NSPasteboard.PasteboardType("public.text"),
        NSPasteboard.PasteboardType("public.plain-text"),
        NSPasteboard.PasteboardType("public.utf8-plain-text"),
        NSPasteboard.PasteboardType("public.utf16-plain-text"),
        NSPasteboard.PasteboardType("public.utf16-external-plain-text")
    ]
    private static let richTextProbeTypes: [NSPasteboard.PasteboardType] = [
        .html,
        .rtf,
        NSPasteboard.PasteboardType("com.apple.flat-rtfd")
    ]
    private static let webArchiveProbeTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("Apple Web Archive pasteboard type"),
        NSPasteboard.PasteboardType("com.apple.webarchive")
    ]
    private static let ignorableTextScalars: Set<UInt32> = [
        0xFEFF, // zero width no-break space
        0xFFFC, // object replacement character for attachments/images
        0x200B, // zero width space
        0x200C, // zero width non-joiner
        0x200D, // zero width joiner
        0x2060  // word joiner
    ]

    enum CapturePolicy: Equatable {
        case ignoreAll
        case defaultTextPreferred
    }

    private struct TextSnapshot {
        let text: String
        let byteCount: Int
        let oversizedRichTextByteCount: Int?
    }

    struct TextCapturePayload {
        let text: String
        let requestID: UUID?
    }

    private static let maximumRichTextParseByteCount = ClipboardItem.maximumStoredTextByteCount
    private static let passthroughPreviewCharacterLimit = 2_000
    private static let pasteboardPollingInterval: TimeInterval = 0.01
    private static let richTextCaptureDelay: Duration = .milliseconds(320)
    private static let delayedPendingPlaceholderDelay: Duration = .milliseconds(620)
    private static let oversizedTextCaptureTimeout: Duration = .seconds(8)
    private static let htmlImageDownloadByteLimit = 16 * 1_024 * 1_024
    private static let emptyPasteboardRetryInterval: Duration = .milliseconds(40)
    private static let emptyPasteboardRetryAttempts = 12
    private static let deferredImageCaptureRetryInterval: Duration = .milliseconds(20)
    private static let deferredImageCaptureRetryAttempts = 10

    private enum HTMLImageCaptureSource {
        case inlineImage(NSImage)
        case resolvedURL(URL)
    }

    private enum RichImageProbeOrigin: String {
        case richTextAttachment = "attachment"
        case webArchive = "webArchive"
        case html = "html"
    }

    private struct RichImageProbeResult {
        let origin: RichImageProbeOrigin
        let source: HTMLImageCaptureSource
        let isImageOnlyFragment: Bool
    }

    private struct WebArchiveResource {
        let data: Data?
        let mimeType: String?
        let url: URL?
    }

    struct Capture {
        enum Payload {
            case text(TextCapturePayload)
            case passthroughText(ClipboardItem.PassthroughTextPayload)
            case image(NSImage)
            case files([URL])
        }

        let payload: Payload
        let sourceAppBundleID: String?
        let sourceAppName: String?
    }

    var onCapture: ((Capture) -> Void)?
    var capturePolicyProvider: ((String?) -> CapturePolicy)?
    var imageCaptureEnabledProvider: ((String?) -> Bool)?
    var onOversizedTextCaptureSkipped: ((Int, String?, String?) -> Void)?
    var onPasteboardChanged: ((Int) -> Void)?
    var onPendingTextCaptureAbandoned: ((UUID) -> Void)?
    var onPendingTextCaptureTimedOut: ((UUID, Int, String?, String?) -> Void)?

    private let pasteboard: NSPasteboard
    private let pollingQueue = DispatchQueue(label: "com.ivean.edgeclip.clipboard-monitor", qos: .userInitiated)
    private let readbackServiceClient = ClipboardReadbackServiceClient()
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private var pendingTextCaptureChangeCount: Int?
    private var pendingTextCaptureTask: Task<Void, Never>?
    private var pendingTextCaptureRequestID: UUID?
    private var pendingPlaceholderTask: Task<Void, Never>?
    private var pendingPlaceholderRequestID: UUID?
    private var pendingPlaceholderDidEmit = false
    private var pendingTextCaptureTimeoutTask: Task<Void, Never>?
    private var pendingEmptyPasteboardRetryChangeCount: Int?
    private var pendingEmptyPasteboardRetryTask: Task<Void, Never>?
    private var pendingDeferredImageCaptureChangeCount: Int?
    private var pendingDeferredImageCaptureTask: Task<Void, Never>?
    private var pendingHTMLImageCaptureChangeCount: Int?
    private var pendingHTMLImageCaptureTask: Task<Void, Never>?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
        timer.schedule(
            deadline: .now() + Self.pasteboardPollingInterval,
            repeating: Self.pasteboardPollingInterval,
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.pollPasteboard()
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
        pendingTextCaptureChangeCount = nil
        pendingTextCaptureTask?.cancel()
        pendingTextCaptureTask = nil
        pendingTextCaptureRequestID = nil
        pendingPlaceholderRequestID = nil
        pendingPlaceholderDidEmit = false
        pendingPlaceholderTask?.cancel()
        pendingPlaceholderTask = nil
        pendingTextCaptureTimeoutTask?.cancel()
        pendingTextCaptureTimeoutTask = nil
        pendingEmptyPasteboardRetryChangeCount = nil
        pendingEmptyPasteboardRetryTask?.cancel()
        pendingEmptyPasteboardRetryTask = nil
        pendingDeferredImageCaptureChangeCount = nil
        pendingDeferredImageCaptureTask?.cancel()
        pendingDeferredImageCaptureTask = nil
        pendingHTMLImageCaptureChangeCount = nil
        pendingHTMLImageCaptureTask?.cancel()
        pendingHTMLImageCaptureTask = nil
    }

    func ignoreCurrentContents() {
        lastChangeCount = pasteboard.changeCount
        pendingTextCaptureChangeCount = nil
        pendingTextCaptureTask?.cancel()
        pendingTextCaptureTask = nil
        pendingTextCaptureRequestID = nil
        pendingPlaceholderRequestID = nil
        pendingPlaceholderDidEmit = false
        pendingPlaceholderTask?.cancel()
        pendingPlaceholderTask = nil
        pendingTextCaptureTimeoutTask?.cancel()
        pendingTextCaptureTimeoutTask = nil
        pendingEmptyPasteboardRetryChangeCount = nil
        pendingEmptyPasteboardRetryTask?.cancel()
        pendingEmptyPasteboardRetryTask = nil
        pendingDeferredImageCaptureChangeCount = nil
        pendingDeferredImageCaptureTask?.cancel()
        pendingDeferredImageCaptureTask = nil
        pendingHTMLImageCaptureChangeCount = nil
        pendingHTMLImageCaptureTask?.cancel()
        pendingHTMLImageCaptureTask = nil
    }

    private func pollPasteboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        abandonPendingTextCaptureForClipboardChangeIfNeeded(nextChangeCount: currentChangeCount)
        lastChangeCount = currentChangeCount

        let sourceApp = NSWorkspace.shared.frontmostApplication
        let sourceBundleID = sourceApp?.bundleIdentifier
        let sourceName = sourceApp?.localizedName
        let capturePolicy = capturePolicyProvider?(sourceBundleID) ?? .defaultTextPreferred
        let imageCaptureEnabled = imageCaptureEnabledProvider?(sourceBundleID) ?? true

        onPasteboardChanged?(currentChangeCount)
        processPasteboardChange(
            expectedChangeCount: currentChangeCount,
            sourceAppBundleID: sourceBundleID,
            sourceAppName: sourceName,
            capturePolicy: capturePolicy,
            imageCaptureEnabled: imageCaptureEnabled,
            allowsEmptyPasteboardRetry: true
        )
    }

    private func processPasteboardChange(
        expectedChangeCount: Int,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        capturePolicy: CapturePolicy,
        imageCaptureEnabled: Bool,
        allowsEmptyPasteboardRetry: Bool
    ) {
        guard lastChangeCount == expectedChangeCount else { return }

        if allowsEmptyPasteboardRetry,
           isPasteboardTemporarilyEmpty() {
            requestEmptyPasteboardRetryIfNeeded(
                expectedChangeCount: expectedChangeCount,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                capturePolicy: capturePolicy,
                imageCaptureEnabled: imageCaptureEnabled
            )
            return
        }

        if capturePolicy == .ignoreAll {
            return
        }

        if let fileURLs = fileURLsFromPasteboard(), !fileURLs.isEmpty {
            onCapture?(
                Capture(
                    payload: .files(fileURLs),
                    sourceAppBundleID: sourceAppBundleID,
                    sourceAppName: sourceAppName
                )
            )
            return
        }

        let hasPlainTextContent = hasPlainTextContentOnPasteboard()
        let hasRichTextContent = hasRichTextContentOnPasteboard()
        let hasPotentialDirectImageContent = hasPotentialDirectImageContentOnPasteboard()
        let shouldInspectDirectImagePayload = !hasPlainTextContent && !hasRichTextContent
        let hasDirectImageContent = shouldInspectDirectImagePayload ? hasDirectImageContentOnPasteboard() : false
        
        // 性能优化：在文本优先模式下，如果有纯文本，延迟探测富文本中的图片附件。
        // 这防止了在复制超长 HTML 文本时，主线程因同步解析 NSAttributedString 而卡死。
        let richImageProbe: RichImageProbeResult?
        if capturePolicy == .defaultTextPreferred && hasPlainTextContent {
            richImageProbe = nil 
        } else {
            richImageProbe = richImageProbeFromPasteboard()
        }
        
        let imageCaptureSource =
            richImageProbe?.source ??
            ((!hasPlainTextContent && !hasRichTextContent) ? imageURLCaptureSourceFromPasteboard() : nil)
        let imageOnlyRichFragment = richImageProbe?.isImageOnlyFragment ?? false

        if (hasDirectImageContent || hasPotentialDirectImageContent),
           !hasPlainTextContent,
           !hasRichTextContent {
            captureImageIfAvailable(
                expectedChangeCount: expectedChangeCount,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                imageCaptureEnabled: imageCaptureEnabled,
                retriesDirectImageIfNeeded: hasPotentialDirectImageContent,
                imageCaptureSource: imageCaptureSource
            )
            return
        }

        if shouldCaptureImageImmediately(
            hasPlainTextContent: hasPlainTextContent,
            hasRichTextContent: hasRichTextContent,
            imageCaptureSource: imageCaptureSource,
            imageOnlyRichFragment: imageOnlyRichFragment
        ) {
            captureImageIfAvailable(
                expectedChangeCount: expectedChangeCount,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                imageCaptureEnabled: imageCaptureEnabled,
                retriesDirectImageIfNeeded: hasPotentialDirectImageContent,
                imageCaptureSource: imageCaptureSource
            )
            return
        }

        if capturePolicy == .defaultTextPreferred,
           (hasPlainTextContent || hasRichTextContent) {
            // 彻底移除同步采集路径 (captureDirectPlainTextIfAvailable)，统一走异步 XPC 链路。
            // 即使是纯文本，也委托给 Readback Service 处理，以防超大文本阻塞主线程。
            let requestID = UUID() 
            
            // 如果只有富文本且没有纯文本，立即显示占位符。
            // 如果有纯文本，则走延迟占位逻辑（给 XPC 一点处理时间，如果快就不显示占位）。
            let emitsPlaceholderImmediately = hasRichTextContent && !hasPlainTextContent
            if emitsPlaceholderImmediately {
                emitPendingPlaceholder(
                    requestID: requestID,
                    changeCount: expectedChangeCount,
                    sourceAppBundleID: sourceAppBundleID,
                    sourceAppName: sourceAppName
                )
            }
            
            requestTextCapture(
                expectedChangeCount: expectedChangeCount,
                requestID: requestID,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                imageCaptureEnabled: imageCaptureEnabled,
                delaysForRichText: hasRichTextContent,
                // 开启延迟占位，确保即使是纯文本在处理较慢时也能被用户感知。
                showsDelayedPendingPlaceholder: !emitsPlaceholderImmediately,
                hasDirectImageFallback: hasDirectImageContent || hasPotentialDirectImageContent,
                imageCaptureSource: imageCaptureSource,
                imageOnlyRichFragment: imageOnlyRichFragment
            )
            return
        }

        captureImageIfAvailable(
            expectedChangeCount: expectedChangeCount,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            imageCaptureEnabled: imageCaptureEnabled,
            retriesDirectImageIfNeeded: hasPotentialDirectImageContent,
            imageCaptureSource: imageCaptureSource
        )
    }

    private func captureDirectPlainTextIfAvailable(
        expectedChangeCount: Int,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        imageCaptureEnabled: Bool,
        hasDirectImageFallback: Bool,
        imageCaptureSource: HTMLImageCaptureSource?,
        imageOnlyRichFragment: Bool
    ) -> Bool {
        guard let textSnapshot = plainTextSnapshotFromPasteboard() else { return false }
        guard containsMeaningfulText(textSnapshot.text) else { return false }

        if shouldPreferImageCapture(
            for: textSnapshot.text,
            hasDirectImageFallback: hasDirectImageFallback,
            imageCaptureSource: imageCaptureSource,
            imageOnlyRichFragment: imageOnlyRichFragment
        ) {
            captureImageIfAvailable(
                expectedChangeCount: expectedChangeCount,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                imageCaptureEnabled: imageCaptureEnabled,
                retriesDirectImageIfNeeded: hasDirectImageFallback,
                imageCaptureSource: imageCaptureSource
            )
            return true
        }

        if textSnapshot.byteCount > ClipboardItem.maximumStoredTextByteCount {
            onCapture?(
                Capture(
                    payload: .passthroughText(
                        ClipboardItem.PassthroughTextPayload(
                            requestID: UUID(),
                            capturedChangeCount: expectedChangeCount,
                            previewText: "超长文本未进入历史",
                            mode: .clipboardOnly,
                            byteCount: textSnapshot.byteCount,
                            cacheToken: nil
                        )
                    ),
                    sourceAppBundleID: sourceAppBundleID,
                    sourceAppName: sourceAppName
                )
            )
        } else {
            onCapture?(
                Capture(
                    payload: .text(TextCapturePayload(text: textSnapshot.text, requestID: nil)),
                    sourceAppBundleID: sourceAppBundleID,
                    sourceAppName: sourceAppName
                )
            )
        }

        return true
    }

    private func fileURLsFromPasteboard() -> [URL]? {
        if let items = pasteboard.pasteboardItems, !items.isEmpty {
            let urls = items.compactMap { item -> URL? in
                guard let value = item.string(forType: .fileURL) else {
                    return nil
                }
                return URL(string: value)?.standardizedFileURL
            }

            if !urls.isEmpty {
                return urls.filter(\.isFileURL)
            }
        }

        if let values = pasteboard.propertyList(forType: .fileURL) as? [String] {
            let urls = values.compactMap { URL(string: $0)?.standardizedFileURL }
            if !urls.isEmpty {
                return urls.filter(\.isFileURL)
            }
        }

        if let paths = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            let urls = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
            if !urls.isEmpty {
                return urls
            }
        }

        return nil
    }

    private func hasPlainTextContentOnPasteboard() -> Bool {
        if pasteboard.availableType(from: Self.explicitPlainTextProbeTypes) != nil {
            return true
        }

        guard let items = pasteboard.pasteboardItems else {
            return false
        }

        return items.contains { item in
            item.types.contains { type in
                isSupportedPlainTextType(type)
            }
        }
    }

    private func hasRichTextContentOnPasteboard() -> Bool {
        pasteboard.availableType(from: Self.richTextProbeTypes) != nil
    }

    private func hasDirectImageContentOnPasteboard() -> Bool {
        imageFromPasteboard() != nil
    }

    private func hasPotentialDirectImageContentOnPasteboard() -> Bool {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            return false
        }

        return items.contains { item in
            item.types.contains(where: isDirectImagePasteboardType(_:))
        }
    }

    private func requestTextCapture(
        expectedChangeCount: Int,
        requestID: UUID?,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        imageCaptureEnabled: Bool,
        delaysForRichText: Bool,
        showsDelayedPendingPlaceholder: Bool,
        hasDirectImageFallback: Bool,
        imageCaptureSource: HTMLImageCaptureSource?,
        imageOnlyRichFragment: Bool
    ) {
        guard pendingTextCaptureChangeCount != expectedChangeCount else { return }
        pendingTextCaptureChangeCount = expectedChangeCount
        pendingTextCaptureRequestID = requestID
        pendingTextCaptureTask?.cancel()

        let request = ClipboardReadbackRequest(
            requestID: UUID(),
            expectedChangeCount: expectedChangeCount,
            inlineTextThresholdBytes: ClipboardItem.maximumStoredTextByteCount,
            previewCharacterLimit: Self.passthroughPreviewCharacterLimit
        )

        scheduleDelayedPendingPlaceholderIfNeeded(
            requestID: requestID,
            expectedChangeCount: expectedChangeCount,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            enabled: showsDelayedPendingPlaceholder
        )
        schedulePendingTextCaptureTimeoutIfNeeded(
            requestID: requestID,
            expectedChangeCount: expectedChangeCount,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName
        )

        pendingTextCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if pendingTextCaptureChangeCount == expectedChangeCount {
                    pendingTextCaptureChangeCount = nil
                    pendingTextCaptureTask = nil
                }
                if pendingTextCaptureRequestID == requestID {
                    pendingTextCaptureRequestID = nil
                }
            }

            do {
                if delaysForRichText {
                    try? await Task.sleep(for: Self.richTextCaptureDelay)
                }
                if Task.isCancelled {
                    abandonPendingPlaceholderIfNeeded(requestID)
                    return
                }
                guard lastChangeCount == expectedChangeCount else {
                    abandonPendingPlaceholderIfNeeded(requestID)
                    return
                }

                let response = try await readbackServiceClient.fetchClipboardText(request)
                if Task.isCancelled {
                    return
                }

                switch response.outcome {
                case .smallText:
                    cancelPendingTextCaptureTimeoutIfNeeded(for: requestID)
                    cancelPendingPlaceholderIfNeeded(for: requestID)
                    guard let text = response.text else {
                        fallbackToInlineTextOrImage(
                            expectedChangeCount: expectedChangeCount,
                            requestID: requestID,
                            sourceAppBundleID: sourceAppBundleID,
                            sourceAppName: sourceAppName,
                            imageCaptureEnabled: imageCaptureEnabled,
                            hasDirectImageFallback: hasDirectImageFallback,
                            imageCaptureSource: imageCaptureSource,
                            imageOnlyRichFragment: imageOnlyRichFragment
                        )
                        return
                    }

                    guard containsMeaningfulText(text) else {
                        fallbackToInlineTextOrImage(
                            expectedChangeCount: expectedChangeCount,
                            requestID: requestID,
                            sourceAppBundleID: sourceAppBundleID,
                            sourceAppName: sourceAppName,
                            imageCaptureEnabled: imageCaptureEnabled,
                            hasDirectImageFallback: hasDirectImageFallback,
                            imageCaptureSource: imageCaptureSource,
                            imageOnlyRichFragment: imageOnlyRichFragment
                        )
                        return
                    }

                    if shouldPreferImageCapture(
                        for: text,
                        hasDirectImageFallback: hasDirectImageFallback,
                        imageCaptureSource: imageCaptureSource,
                        imageOnlyRichFragment: imageOnlyRichFragment
                    ) {
                        captureImageIfAvailable(
                            expectedChangeCount: expectedChangeCount,
                            sourceAppBundleID: sourceAppBundleID,
                            sourceAppName: sourceAppName,
                            imageCaptureEnabled: imageCaptureEnabled,
                            retriesDirectImageIfNeeded: hasDirectImageFallback,
                            imageCaptureSource: imageCaptureSource
                        )
                        return
                    }

                    let byteCount = response.byteCount ?? text.lengthOfBytes(using: .utf8)
                    if byteCount > ClipboardItem.maximumStoredTextByteCount {
                        onOversizedTextCaptureSkipped?(byteCount, sourceAppBundleID, sourceAppName)
                        return
                    }

                    onCapture?(
                        Capture(
                            payload: .text(TextCapturePayload(text: text, requestID: requestID)),
                            sourceAppBundleID: sourceAppBundleID,
                            sourceAppName: sourceAppName
                        )
                    )
                case .cachedOneTime:
                    cancelPendingTextCaptureTimeoutIfNeeded(for: requestID)
                    cancelPendingPlaceholderIfNeeded(for: requestID)
                    if response.cacheToken == nil,
                       let imageCaptureSource {
                        captureImageIfAvailable(
                            expectedChangeCount: expectedChangeCount,
                            sourceAppBundleID: sourceAppBundleID,
                            sourceAppName: sourceAppName,
                            imageCaptureEnabled: imageCaptureEnabled,
                            retriesDirectImageIfNeeded: hasDirectImageFallback,
                            imageCaptureSource: imageCaptureSource
                        )
                        return
                    }

                    let byteCount = response.byteCount ?? (ClipboardItem.maximumStoredTextByteCount + 1)
                    onCapture?(
                        Capture(
                            payload: .passthroughText(
                                ClipboardItem.PassthroughTextPayload(
                                    requestID: requestID ?? UUID(),
                                    capturedChangeCount: expectedChangeCount,
                                    previewText: normalizedPassthroughPreviewText(response.previewText),
                                    mode: response.cacheToken == nil ? .pending : .cachedOneTime,
                                    byteCount: byteCount,
                                    cacheToken: response.cacheToken
                                )
                            ),
                            sourceAppBundleID: sourceAppBundleID,
                            sourceAppName: sourceAppName
                        )
                    )
                case .stale:
                    cancelPendingTextCaptureTimeoutIfNeeded(for: requestID)
                    abandonPendingPlaceholderIfNeeded(requestID)
                    fallbackToInlineTextOrImage(
                        expectedChangeCount: expectedChangeCount,
                        requestID: requestID,
                        sourceAppBundleID: sourceAppBundleID,
                        sourceAppName: sourceAppName,
                        imageCaptureEnabled: imageCaptureEnabled,
                        hasDirectImageFallback: hasDirectImageFallback,
                        imageCaptureSource: imageCaptureSource,
                        imageOnlyRichFragment: imageOnlyRichFragment
                    )
                case .failed:
                    cancelPendingTextCaptureTimeoutIfNeeded(for: requestID)
                    abandonPendingPlaceholderIfNeeded(requestID)
                    fallbackToInlineTextOrImage(
                        expectedChangeCount: expectedChangeCount,
                        requestID: requestID,
                        sourceAppBundleID: sourceAppBundleID,
                        sourceAppName: sourceAppName,
                        imageCaptureEnabled: imageCaptureEnabled,
                        hasDirectImageFallback: hasDirectImageFallback,
                        imageCaptureSource: imageCaptureSource,
                        imageOnlyRichFragment: imageOnlyRichFragment
                    )
                }
            } catch {
                cancelPendingTextCaptureTimeoutIfNeeded(for: requestID)
                abandonPendingPlaceholderIfNeeded(requestID)
                guard lastChangeCount == expectedChangeCount else { return }
                fallbackToInlineTextOrImage(
                    expectedChangeCount: expectedChangeCount,
                    requestID: requestID,
                    sourceAppBundleID: sourceAppBundleID,
                    sourceAppName: sourceAppName,
                    imageCaptureEnabled: imageCaptureEnabled,
                    hasDirectImageFallback: hasDirectImageFallback,
                    imageCaptureSource: imageCaptureSource,
                    imageOnlyRichFragment: imageOnlyRichFragment
                )
            }
        }
    }

    private func fallbackToInlineTextOrImage(
        expectedChangeCount: Int,
        requestID: UUID?,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        imageCaptureEnabled: Bool,
        hasDirectImageFallback: Bool,
        imageCaptureSource: HTMLImageCaptureSource?,
        imageOnlyRichFragment: Bool
    ) {
        guard lastChangeCount == expectedChangeCount else { return }
        cancelPendingPlaceholderIfNeeded(for: requestID)

        if let textSnapshot = textSnapshotFromPasteboard() {
            if let oversizedByteCount = textSnapshot.oversizedRichTextByteCount {
                if let imageCaptureSource {
                    captureImageIfAvailable(
                        expectedChangeCount: expectedChangeCount,
                        sourceAppBundleID: sourceAppBundleID,
                        sourceAppName: sourceAppName,
                        imageCaptureEnabled: imageCaptureEnabled,
                        retriesDirectImageIfNeeded: hasDirectImageFallback,
                        imageCaptureSource: imageCaptureSource
                    )
                    return
                }

                onCapture?(
                    Capture(
                        payload: .passthroughText(
                            ClipboardItem.PassthroughTextPayload(
                                requestID: requestID ?? UUID(),
                                capturedChangeCount: expectedChangeCount,
                                previewText: "超长文本",
                                mode: .pending,
                                byteCount: oversizedByteCount,
                                cacheToken: nil
                            )
                        ),
                        sourceAppBundleID: sourceAppBundleID,
                        sourceAppName: sourceAppName
                    )
                )
                return
            }

            if containsMeaningfulText(textSnapshot.text) {
                if shouldPreferImageCapture(
                    for: textSnapshot.text,
                    hasDirectImageFallback: hasDirectImageFallback,
                    imageCaptureSource: imageCaptureSource,
                    imageOnlyRichFragment: imageOnlyRichFragment
                ) {
                    captureImageIfAvailable(
                        expectedChangeCount: expectedChangeCount,
                        sourceAppBundleID: sourceAppBundleID,
                        sourceAppName: sourceAppName,
                        imageCaptureEnabled: imageCaptureEnabled,
                        retriesDirectImageIfNeeded: hasDirectImageFallback,
                        imageCaptureSource: imageCaptureSource
                    )
                    return
                }

                if textSnapshot.byteCount > ClipboardItem.maximumStoredTextByteCount {
                    onCapture?(
                        Capture(
                            payload: .passthroughText(
                                ClipboardItem.PassthroughTextPayload(
                                    requestID: requestID ?? UUID(),
                                    capturedChangeCount: expectedChangeCount,
                                    previewText: makePassthroughPreviewText(from: textSnapshot.text),
                                    mode: .pending,
                                    byteCount: textSnapshot.byteCount,
                                    cacheToken: nil
                                )
                            ),
                            sourceAppBundleID: sourceAppBundleID,
                            sourceAppName: sourceAppName
                        )
                    )
                } else {
                    onCapture?(
                        Capture(
                            payload: .text(
                                TextCapturePayload(
                                    text: textSnapshot.text,
                                    requestID: requestID
                                )
                            ),
                            sourceAppBundleID: sourceAppBundleID,
                            sourceAppName: sourceAppName
                        )
                    )
                }
                return
            }
        }

        captureImageIfAvailable(
            expectedChangeCount: expectedChangeCount,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            imageCaptureEnabled: imageCaptureEnabled,
            retriesDirectImageIfNeeded: hasDirectImageFallback,
            imageCaptureSource: imageCaptureSource
        )
    }

    private func emitPendingPlaceholder(
        requestID: UUID,
        changeCount: Int,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) {
        pendingPlaceholderRequestID = requestID
        pendingPlaceholderDidEmit = true
        onCapture?(
            Capture(
                payload: .passthroughText(
                    ClipboardItem.PassthroughTextPayload(
                        requestID: requestID,
                        capturedChangeCount: changeCount,
                        previewText: "超长文本准备中",
                        mode: .pending,
                        byteCount: nil,
                        cacheToken: nil
                    )
                ),
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName
            )
        )
    }

    private func scheduleDelayedPendingPlaceholderIfNeeded(
        requestID: UUID?,
        expectedChangeCount: Int,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        enabled: Bool
    ) {
        pendingPlaceholderTask?.cancel()
        pendingPlaceholderTask = nil
        pendingPlaceholderRequestID = requestID
        pendingPlaceholderDidEmit = false

        guard enabled, let requestID else { return }

        pendingPlaceholderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: Self.delayedPendingPlaceholderDelay)
            guard !Task.isCancelled,
                  self.pendingPlaceholderRequestID == requestID,
                  !self.pendingPlaceholderDidEmit,
                  self.lastChangeCount == expectedChangeCount else {
                return
            }

            self.emitPendingPlaceholder(
                requestID: requestID,
                changeCount: expectedChangeCount,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName
            )
        }
    }

    private func cancelPendingPlaceholderIfNeeded(for requestID: UUID?) {
        guard let requestID,
              pendingPlaceholderRequestID == requestID else {
            return
        }

        pendingPlaceholderTask?.cancel()
        pendingPlaceholderTask = nil
        pendingPlaceholderRequestID = nil
        pendingPlaceholderDidEmit = false
    }

    private func abandonPendingPlaceholderIfNeeded(_ requestID: UUID?) {
        guard let requestID,
              pendingPlaceholderRequestID == requestID else {
            return
        }

        let shouldNotify = pendingPlaceholderDidEmit
        cancelPendingTextCaptureTimeoutIfNeeded(for: requestID)
        pendingPlaceholderTask?.cancel()
        pendingPlaceholderTask = nil
        pendingPlaceholderRequestID = nil
        pendingPlaceholderDidEmit = false
        if shouldNotify || true {
            onPendingTextCaptureAbandoned?(requestID)
        }
    }

    private func abandonPendingTextCaptureForClipboardChangeIfNeeded(nextChangeCount: Int) {
        guard let requestID = pendingTextCaptureRequestID,
              let expectedChangeCount = pendingTextCaptureChangeCount,
              expectedChangeCount != nextChangeCount else {
            return
        }

        pendingTextCaptureTask?.cancel()
        pendingTextCaptureTask = nil
        pendingTextCaptureChangeCount = nil
        pendingTextCaptureRequestID = nil
        pendingTextCaptureTimeoutTask?.cancel()
        pendingTextCaptureTimeoutTask = nil

        let shouldNotify = pendingPlaceholderRequestID == requestID || pendingPlaceholderDidEmit
        pendingPlaceholderTask?.cancel()
        pendingPlaceholderTask = nil
        pendingPlaceholderRequestID = nil
        pendingPlaceholderDidEmit = false

        if shouldNotify || true {
            onPendingTextCaptureAbandoned?(requestID)
        }
    }

    private func requestEmptyPasteboardRetryIfNeeded(
        expectedChangeCount: Int,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        capturePolicy: CapturePolicy,
        imageCaptureEnabled: Bool
    ) {
        guard pendingEmptyPasteboardRetryChangeCount != expectedChangeCount else {
            return
        }

        pendingEmptyPasteboardRetryChangeCount = expectedChangeCount
        pendingEmptyPasteboardRetryTask?.cancel()
        pendingEmptyPasteboardRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if pendingEmptyPasteboardRetryChangeCount == expectedChangeCount {
                    pendingEmptyPasteboardRetryChangeCount = nil
                    pendingEmptyPasteboardRetryTask = nil
                }
            }

            for _ in 0..<Self.emptyPasteboardRetryAttempts {
                try? await Task.sleep(for: Self.emptyPasteboardRetryInterval)
                guard !Task.isCancelled,
                      lastChangeCount == expectedChangeCount else {
                    return
                }

                if !isPasteboardTemporarilyEmpty() {
                    processPasteboardChange(
                        expectedChangeCount: expectedChangeCount,
                        sourceAppBundleID: sourceAppBundleID,
                        sourceAppName: sourceAppName,
                        capturePolicy: capturePolicy,
                        imageCaptureEnabled: imageCaptureEnabled,
                        allowsEmptyPasteboardRetry: false
                    )
                    return
                }
            }

            guard !Task.isCancelled,
                  lastChangeCount == expectedChangeCount else {
                return
            }

            processPasteboardChange(
                expectedChangeCount: expectedChangeCount,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                capturePolicy: capturePolicy,
                imageCaptureEnabled: imageCaptureEnabled,
                allowsEmptyPasteboardRetry: false
            )
        }
    }

    private func schedulePendingTextCaptureTimeoutIfNeeded(
        requestID: UUID?,
        expectedChangeCount: Int,
        sourceAppBundleID: String?,
        sourceAppName: String?
    ) {
        pendingTextCaptureTimeoutTask?.cancel()
        pendingTextCaptureTimeoutTask = nil

        guard let requestID else { return }

        pendingTextCaptureTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: Self.oversizedTextCaptureTimeout)
            guard !Task.isCancelled,
                  self.pendingTextCaptureRequestID == requestID,
                  self.pendingTextCaptureChangeCount == expectedChangeCount,
                  self.lastChangeCount == expectedChangeCount else {
                return
            }

            self.pendingTextCaptureTask?.cancel()
            self.pendingTextCaptureTask = nil
            self.pendingTextCaptureChangeCount = nil
            self.pendingTextCaptureRequestID = nil

            self.onPendingTextCaptureTimedOut?(
                requestID,
                expectedChangeCount,
                sourceAppBundleID,
                sourceAppName
            )
        }
    }

    private func cancelPendingTextCaptureTimeoutIfNeeded(for requestID: UUID?) {
        guard requestID == nil || pendingTextCaptureRequestID == requestID else {
            return
        }

        pendingTextCaptureTimeoutTask?.cancel()
        pendingTextCaptureTimeoutTask = nil
    }

    private func captureImageIfAvailable(
        expectedChangeCount: Int,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        imageCaptureEnabled: Bool,
        retriesDirectImageIfNeeded: Bool,
        imageCaptureSource: HTMLImageCaptureSource? = nil
    ) {
        guard lastChangeCount == expectedChangeCount else { return }
        guard imageCaptureEnabled else { return }

        if let image = imageFromPasteboard() {
            onCapture?(
                Capture(
                    payload: .image(image),
                    sourceAppBundleID: sourceAppBundleID,
                    sourceAppName: sourceAppName
                )
            )
            return
        }

        if retriesDirectImageIfNeeded {
            requestDeferredDirectImageCaptureIfNeeded(
                expectedChangeCount: expectedChangeCount,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                imageCaptureEnabled: imageCaptureEnabled,
                imageCaptureSource: imageCaptureSource
            )
            return
        }

        requestHTMLImageCaptureIfAvailable(
            expectedChangeCount: expectedChangeCount,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            imageSource: imageCaptureSource ?? richImageProbeFromPasteboard()?.source ?? imageURLCaptureSourceFromPasteboard()
        )
    }

    private func requestDeferredDirectImageCaptureIfNeeded(
        expectedChangeCount: Int,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        imageCaptureEnabled: Bool,
        imageCaptureSource: HTMLImageCaptureSource?
    ) {
        guard pendingDeferredImageCaptureChangeCount != expectedChangeCount else {
            return
        }

        pendingDeferredImageCaptureChangeCount = expectedChangeCount
        pendingDeferredImageCaptureTask?.cancel()
        pendingDeferredImageCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if pendingDeferredImageCaptureChangeCount == expectedChangeCount {
                    pendingDeferredImageCaptureChangeCount = nil
                    pendingDeferredImageCaptureTask = nil
                }
            }

            for _ in 0..<Self.deferredImageCaptureRetryAttempts {
                guard !Task.isCancelled,
                      lastChangeCount == expectedChangeCount,
                      imageCaptureEnabled else {
                    return
                }

                if let image = imageFromPasteboard(),
                   image.size.width > 0,
                   image.size.height > 0 {
                    onCapture?(
                        Capture(
                            payload: .image(image),
                            sourceAppBundleID: sourceAppBundleID,
                            sourceAppName: sourceAppName
                        )
                    )
                    return
                }

                try? await Task.sleep(for: Self.deferredImageCaptureRetryInterval)
            }

            guard !Task.isCancelled,
                  lastChangeCount == expectedChangeCount else {
                return
            }

            requestHTMLImageCaptureIfAvailable(
                expectedChangeCount: expectedChangeCount,
                sourceAppBundleID: sourceAppBundleID,
                sourceAppName: sourceAppName,
                imageSource: imageCaptureSource ?? richImageProbeFromPasteboard()?.source ?? imageURLCaptureSourceFromPasteboard()
            )
        }
    }

    private func textSnapshotFromPasteboard() -> TextSnapshot? {
        if let snapshot = plainTextSnapshotFromPasteboard() {
            return snapshot
        }

        let richTextTypes: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
            (.html, .html),
            (.rtf, .rtf)
        ]

        for (type, documentType) in richTextTypes {
            guard let data = pasteboard.data(forType: type) else {
                continue
            }

            if data.count > Self.maximumRichTextParseByteCount {
                return TextSnapshot(
                    text: "",
                    byteCount: data.count,
                    oversizedRichTextByteCount: data.count
                )
            }

            guard let attributed = try? NSAttributedString(
                    data: data,
                    options: [.documentType: documentType],
                    documentAttributes: nil
                  ) else {
                continue
            }

            let text = attributed.string
            if !text.isEmpty {
                return TextSnapshot(
                    text: text,
                    byteCount: text.lengthOfBytes(using: .utf8),
                    oversizedRichTextByteCount: nil
                )
            }
        }

        return nil
    }

    private func plainTextSnapshotFromPasteboard() -> TextSnapshot? {
        // 安全防护：在同步读取前先评估大小，避免在主线程上因 materializing 超大字符串而卡死。
        // 虽然 NSPasteboard 没有直接的 size 属性，但我们可以尝试读取 Data 并检查其长度。
        for type in orderedPlainTextProbeTypes() {
            // 注意：data(forType:) 仍然会读取内容，但在某些系统实现中可能比 string(forType:) 的 UTF16 转换稍快。
            // 真正的防御已经在上层通过全量异步化解决了。
            if let data = pasteboard.data(forType: type) {
                let byteCount = data.count
                if byteCount > ClipboardItem.maximumStoredTextByteCount * 2 { // 这里的阈值可以稍宽，作为最后一道防线
                    return TextSnapshot(
                        text: "", 
                        byteCount: byteCount, 
                        oversizedRichTextByteCount: nil
                    )
                }
                
                if let text = decodePlainText(data), !text.isEmpty {
                    return TextSnapshot(
                        text: text,
                        byteCount: byteCount,
                        oversizedRichTextByteCount: nil
                    )
                }
            }
        }

        return nil
    }

    private func containsMeaningfulText(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return false
            }

            if CharacterSet.controlCharacters.contains(scalar) {
                return false
            }

            return !Self.ignorableTextScalars.contains(scalar.value)
        }
    }

    private func shouldCaptureImageImmediately(
        hasPlainTextContent: Bool,
        hasRichTextContent: Bool,
        imageCaptureSource: HTMLImageCaptureSource?,
        imageOnlyRichFragment: Bool
    ) -> Bool {
        guard imageCaptureSource != nil else {
            return false
        }

        if imageOnlyRichFragment {
            return true
        }

        return !hasRichTextContent && !hasPlainTextContent
    }

    private func shouldPreferImageCapture(
        for text: String,
        hasDirectImageFallback: Bool,
        imageCaptureSource: HTMLImageCaptureSource?,
        imageOnlyRichFragment: Bool
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard containsMeaningfulText(trimmed) else {
            return true
        }

        if imageOnlyRichFragment,
           imageCaptureSource != nil {
            return true
        }

        if hasDirectImageFallback || imageCaptureSource != nil,
           isLikelyImageURLText(trimmed) {
            return true
        }

        return false
    }

    private func imageFromPasteboard() -> NSImage? {
        if let image = NSImage(pasteboard: pasteboard),
           image.size.width > 0,
           image.size.height > 0 {
            return image
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first(where: { $0.size.width > 0 && $0.size.height > 0 }) {
            return image
        }

        guard let items = pasteboard.pasteboardItems else { return nil }

        for item in items {
            for type in item.types where isDirectImagePasteboardType(type) {
                guard let data = item.data(forType: type), !data.isEmpty else { continue }

                guard let image = NSImage(data: data),
                      image.size.width > 0,
                      image.size.height > 0 else {
                    continue
                }

                return image
            }
        }

        return nil
    }

    private func requestHTMLImageCaptureIfAvailable(
        expectedChangeCount: Int,
        sourceAppBundleID: String?,
        sourceAppName: String?,
        imageSource: HTMLImageCaptureSource?
    ) {
        guard let imageSource else { return }

        guard pendingHTMLImageCaptureChangeCount != expectedChangeCount else {
            return
        }

        pendingHTMLImageCaptureChangeCount = expectedChangeCount
        pendingHTMLImageCaptureTask?.cancel()
        pendingHTMLImageCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.pendingHTMLImageCaptureChangeCount == expectedChangeCount {
                    self.pendingHTMLImageCaptureChangeCount = nil
                    self.pendingHTMLImageCaptureTask = nil
                }
            }

            let image: NSImage?
            switch imageSource {
            case let .inlineImage(inlineImage):
                image = inlineImage
            case let .resolvedURL(url):
                image = await downloadImage(from: url)
            }

            guard !Task.isCancelled,
                  lastChangeCount == expectedChangeCount,
                  let image,
                  image.size.width > 0,
                  image.size.height > 0 else {
                return
            }

            onCapture?(
                Capture(
                    payload: .image(image),
                    sourceAppBundleID: sourceAppBundleID,
                    sourceAppName: sourceAppName
                )
            )
        }
    }

    private func richImageProbeFromPasteboard() -> RichImageProbeResult? {
        if let probe = richTextAttachmentImageProbeFromPasteboard() {
            return probe
        }

        if let probe = webArchiveImageProbeFromPasteboard() {
            return probe
        }

        return htmlImageProbeFromPasteboard()
    }

    private func htmlImageProbeFromPasteboard() -> RichImageProbeResult? {
        guard let data = pasteboard.data(forType: .html) else {
            return nil
        }
        
        // 安全防护：HTML 解析非常耗时且耗内存。限制在 1MB 以内。
        if data.count > 1 * 1024 * 1024 {
            return nil
        }

        guard let html = decodeHTML(data) else {
            return nil
        }

        guard let rawSource = firstHTMLImageSource(in: html) else {
            return nil
        }

        if let image = inlineImageFromHTMLSource(rawSource) {
            return RichImageProbeResult(
                origin: .html,
                source: .inlineImage(image),
                isImageOnlyFragment: isImageOnlyHTMLFragment(html)
            )
        }

        guard let resolvedURL = resolvedHTMLImageURL(from: rawSource) else {
            return nil
        }

        return RichImageProbeResult(
            origin: .html,
            source: .resolvedURL(resolvedURL),
            isImageOnlyFragment: isImageOnlyHTMLFragment(html)
        )
    }

    private func richTextAttachmentImageProbeFromPasteboard() -> RichImageProbeResult? {
        let attachmentTypes: [(NSPasteboard.PasteboardType, NSAttributedString.DocumentType)] = [
            (NSPasteboard.PasteboardType("com.apple.flat-rtfd"), .rtfd),
            (NSPasteboard.PasteboardType("public.rtfd"), .rtfd),
            (.rtf, .rtf),
            (.html, .html)
        ]

        for (type, documentType) in attachmentTypes {
            guard let data = pasteboard.data(forType: type) else {
                continue
            }
            
            // 安全防护：如果数据量过大（超过 1MB），不在主线程进行耗时的 NSAttributedString 解析。
            if data.count > 1 * 1024 * 1024 {
                continue
            }
            
            guard let attributed = try? NSAttributedString(
                    data: data,
                    options: [.documentType: documentType],
                    documentAttributes: nil
                  ),
                  let image = firstAttachmentImage(in: attributed) else {
                continue
            }

            return RichImageProbeResult(
                origin: .richTextAttachment,
                source: .inlineImage(image),
                isImageOnlyFragment: !containsMeaningfulText(attributed.string)
            )
        }

        return nil
    }

    private func firstAttachmentImage(in attributedString: NSAttributedString) -> NSImage? {
        guard attributedString.length > 0 else {
            return nil
        }

        var result: NSImage?
        attributedString.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, _, stop in
            guard let attachment = value as? NSTextAttachment,
                  let image = image(from: attachment) else {
                return
            }

            result = image
            stop.pointee = true
        }

        return result
    }

    private func image(from attachment: NSTextAttachment) -> NSImage? {
        let bounds = attachment.bounds
        if let image = attachment.image(
            forBounds: bounds,
            textContainer: nil,
            characterIndex: 0
        ),
           image.size.width > 0,
           image.size.height > 0 {
            return image
        }

        guard let fileWrapper = attachment.fileWrapper else {
            return nil
        }

        return image(from: fileWrapper)
    }

    private func image(from fileWrapper: FileWrapper) -> NSImage? {
        if fileWrapper.isRegularFile,
           let data = fileWrapper.regularFileContents,
           let image = NSImage(data: data),
           image.size.width > 0,
           image.size.height > 0 {
            return image
        }

        guard fileWrapper.isDirectory,
              let children = fileWrapper.fileWrappers?.values else {
            return nil
        }

        for child in children {
            if let image = image(from: child) {
                return image
            }
        }

        return nil
    }

    private func webArchiveImageProbeFromPasteboard() -> RichImageProbeResult? {
        for type in Self.webArchiveProbeTypes {
            guard let data = pasteboard.data(forType: type) else {
                continue
            }
            
            // 安全防护：WebArchive 通常很大，限制主线程解析大小（1MB）。
            if data.count > 1 * 1024 * 1024 {
                continue
            }

            guard let propertyList = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                  ),
                  let archive = propertyList as? [String: Any],
                  let probe = richImageProbe(fromWebArchive: archive) else {
                continue
            }

            return probe
        }

        return nil
    }

    private func richImageProbe(fromWebArchive archive: [String: Any]) -> RichImageProbeResult? {
        let resources = webArchiveResources(from: archive)
        guard !resources.isEmpty else {
            return nil
        }

        if let htmlResource = resources.first(where: isHTMLWebArchiveResource(_:)),
           let htmlData = htmlResource.data,
           let html = decodeHTML(htmlData),
           let rawSource = firstHTMLImageSource(in: html) {
            let isImageOnlyFragment = isImageOnlyHTMLFragment(html)

            if let inlineImage = inlineImageFromHTMLSource(rawSource) {
                return RichImageProbeResult(
                    origin: .webArchive,
                    source: .inlineImage(inlineImage),
                    isImageOnlyFragment: isImageOnlyFragment
                )
            }

            if let resolvedURL = resolvedHTMLImageURL(from: rawSource, baseURL: htmlResource.url) {
                if let archivedImage = imageFromWebArchiveResources(resources, matching: resolvedURL) {
                    return RichImageProbeResult(
                        origin: .webArchive,
                        source: .inlineImage(archivedImage),
                        isImageOnlyFragment: isImageOnlyFragment
                    )
                }

                return RichImageProbeResult(
                    origin: .webArchive,
                    source: .resolvedURL(resolvedURL),
                    isImageOnlyFragment: isImageOnlyFragment
                )
            }
        }

        guard let archivedImage = imageFromWebArchiveResources(resources) else {
            return nil
        }

        return RichImageProbeResult(
            origin: .webArchive,
            source: .inlineImage(archivedImage),
            isImageOnlyFragment: true
        )
    }

    private func imageURLCaptureSourceFromPasteboard() -> HTMLImageCaptureSource? {
        for candidate in imageURLStringCandidatesFromPasteboard() {
            guard let url = imageURL(from: candidate) else {
                continue
            }

            return .resolvedURL(url)
        }

        return nil
    }

    private func imageURLStringCandidatesFromPasteboard() -> [String] {
        let urlTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType("public.url"),
            .string
        ]

        var candidates: [String] = []
        for type in urlTypes {
            if let value = pasteboard.string(forType: type) {
                candidates.append(value)
            }
        }

        if let items = pasteboard.pasteboardItems {
            for item in items {
                for type in urlTypes {
                    if let value = item.string(forType: type) {
                        candidates.append(value)
                    }
                }
            }
        }

        return candidates
    }

    private func orderedPlainTextProbeTypes() -> [NSPasteboard.PasteboardType] {
        var ordered: [NSPasteboard.PasteboardType] = []
        var seen = Set<String>()

        func append(_ type: NSPasteboard.PasteboardType) {
            guard seen.insert(type.rawValue).inserted else { return }
            ordered.append(type)
        }

        Self.explicitPlainTextProbeTypes.forEach(append)

        if let items = pasteboard.pasteboardItems {
            for item in items {
                for type in item.types where isSupportedPlainTextType(type) {
                    append(type)
                }
            }
        }

        return ordered
    }

    private func isSupportedPlainTextType(_ type: NSPasteboard.PasteboardType) -> Bool {
        if Self.richTextProbeTypes.contains(type) {
            return false
        }

        if Self.explicitPlainTextProbeTypes.contains(type) {
            return true
        }

        guard let utType = UTType(type.rawValue) else {
            return false
        }

        if utType.conforms(to: .html) || utType.conforms(to: .rtf) {
            return false
        }

        return utType.conforms(to: .plainText) || utType.conforms(to: .text)
    }

    private func imageURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else {
            return nil
        }

        let lowercasePath = url.path.lowercased()
        let imageExtensions = [
            ".png", ".jpg", ".jpeg", ".gif", ".webp",
            ".bmp", ".tif", ".tiff", ".heic", ".heif", ".avif"
        ]

        guard imageExtensions.contains(where: lowercasePath.hasSuffix) else {
            return nil
        }

        return url
    }

    private func decodeHTML(_ data: Data) -> String? {
        if let html = String(data: data, encoding: .utf8) {
            return html
        }

        if let html = String(data: data, encoding: .unicode) {
            return html
        }

        if let html = String(data: data, encoding: .utf16) {
            return html
        }

        return nil
    }

    private func isImageOnlyHTMLFragmentOnPasteboard() -> Bool {
        guard let data = pasteboard.data(forType: .html),
              let html = decodeHTML(data) else {
            return false
        }

        return isImageOnlyHTMLFragment(html)
    }

    private func isImageOnlyHTMLFragment(_ html: String) -> Bool {
        guard firstHTMLImageSource(in: html) != nil else {
            return false
        }

        let withoutImages = replacingMatches(
            in: html,
            pattern: #"<img\b[^>]*>"#,
            with: " "
        )
        let withoutTags = replacingMatches(
            in: withoutImages,
            pattern: #"<[^>]+>"#,
            with: " "
        )
        let normalized = decodeHTMLAttributeValue(
            withoutTags.replacingOccurrences(of: "&nbsp;", with: " ")
        )

        return !containsMeaningfulText(normalized)
    }

    private func replacingMatches(
        in string: String,
        pattern: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return string
        }

        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.stringByReplacingMatches(
            in: string,
            options: [],
            range: range,
            withTemplate: replacement
        )
    }

    private func firstHTMLImageSource(in html: String) -> String? {
        let patterns = [
            #"<img\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"]"#,
            #"<img\b[^>]*\bsrc\s*=\s*([^>\s]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, options: [], range: range),
                  let sourceRange = Range(match.range(at: 1), in: html) else {
                continue
            }

            let source = html[sourceRange].trimmingCharacters(in: .whitespacesAndNewlines)
            if !source.isEmpty {
                return decodeHTMLAttributeValue(String(source))
            }
        }

        return nil
    }

    private func decodeHTMLAttributeValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private func inlineImageFromHTMLSource(_ source: String) -> NSImage? {
        guard source.lowercased().hasPrefix("data:image/"),
              let commaIndex = source.firstIndex(of: ",") else {
            return nil
        }

        let metadata = source[..<commaIndex].lowercased()
        let payload = String(source[source.index(after: commaIndex)...])
        let data: Data?
        if metadata.contains(";base64") {
            data = Data(base64Encoded: payload)
        } else {
            data = payload.removingPercentEncoding?.data(using: .utf8)
        }

        guard let data,
              !data.isEmpty else {
            return nil
        }

        return NSImage(data: data)
    }

    private func resolvedHTMLImageURL(from source: String, baseURL: URL? = nil) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("//") {
            let scheme = sourcePageURLFromPasteboard()?.scheme ?? "https"
            return URL(string: "\(scheme):\(trimmed)")
        }

        if let absoluteURL = URL(string: trimmed),
           let scheme = absoluteURL.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            return absoluteURL
        }

        guard let baseURL = baseURL ?? sourcePageURLFromPasteboard() else {
            return nil
        }

        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private func isLikelyImageURLText(_ text: String) -> Bool {
        imageURL(from: text) != nil
    }

    private func sourcePageURLFromPasteboard() -> URL? {
        let sourceTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType("org.chromium.source-url"),
            NSPasteboard.PasteboardType("public.url")
        ]

        for type in sourceTypes {
            if let value = pasteboard.string(forType: type),
               let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return url
            }
        }

        if let items = pasteboard.pasteboardItems {
            for item in items {
                for type in sourceTypes {
                    if let value = item.string(forType: type),
                       let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        return url
                    }
                }
            }
        }

        return nil
    }

    private func downloadImage(from url: URL) async -> NSImage? {
        if url.isFileURL {
            return NSImage(contentsOf: url)
        }

        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  data.count > 0,
                  data.count <= Self.htmlImageDownloadByteLimit,
                  let mimeType = httpResponse.mimeType?.lowercased(),
                  mimeType.hasPrefix("image/") else {
                return nil
            }

            return NSImage(data: data)
        } catch {
            return nil
        }
    }

    private func isHTMLWebArchiveResource(_ resource: WebArchiveResource) -> Bool {
        guard let mimeType = resource.mimeType?.lowercased() else {
            return false
        }

        return mimeType.contains("html")
    }

    private func webArchiveResources(from archive: [String: Any]) -> [WebArchiveResource] {
        var resources: [WebArchiveResource] = []

        func appendResource(from dictionary: [String: Any]) {
            let data = dictionary["WebResourceData"] as? Data
            let mimeType = dictionary["WebResourceMIMEType"] as? String
            let url = (dictionary["WebResourceURL"] as? String).flatMap(URL.init(string:))
            resources.append(
                WebArchiveResource(
                    data: data,
                    mimeType: mimeType,
                    url: url
                )
            )
        }

        if let mainResource = archive["WebMainResource"] as? [String: Any] {
            appendResource(from: mainResource)
        }

        if let subresources = archive["WebSubresources"] as? [[String: Any]] {
            subresources.forEach(appendResource(from:))
        }

        if let subframeArchives = archive["WebSubframeArchives"] as? [[String: Any]] {
            for subframeArchive in subframeArchives {
                resources.append(contentsOf: webArchiveResources(from: subframeArchive))
            }
        }

        return resources
    }

    private func imageFromWebArchiveResources(
        _ resources: [WebArchiveResource],
        matching resolvedURL: URL? = nil
    ) -> NSImage? {
        let imageResources = resources.filter { resource in
            guard let mimeType = resource.mimeType?.lowercased() else {
                return false
            }

            return mimeType.hasPrefix("image/")
        }

        if let resolvedURL {
            if let matchingImage = imageResources.first(where: { resource in
                guard let resourceURL = resource.url else {
                    return false
                }

                return resourceURL.absoluteString == resolvedURL.absoluteString
            }),
               let image = imageFromWebArchiveResource(matchingImage) {
                return image
            }
        }

        for resource in imageResources {
            if let image = imageFromWebArchiveResource(resource) {
                return image
            }
        }

        return nil
    }

    private func imageFromWebArchiveResource(_ resource: WebArchiveResource) -> NSImage? {
        guard let data = resource.data,
              !data.isEmpty,
              let image = NSImage(data: data),
              image.size.width > 0,
              image.size.height > 0 else {
            return nil
        }

        return image
    }

    private func isPasteboardTemporarilyEmpty() -> Bool {
        let hasTopLevelTypes = !(pasteboard.types?.isEmpty ?? true)
        let hasItemTypes = pasteboard.pasteboardItems?.contains(where: { !$0.types.isEmpty }) ?? false
        return !hasTopLevelTypes && !hasItemTypes
    }

    private func abbreviated(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(0, limit - 1))) + "…"
    }

    private func isDirectImagePasteboardType(_ type: NSPasteboard.PasteboardType) -> Bool {
        if type == .tiff {
            return true
        }

        guard let utType = UTType(type.rawValue) else {
            return false
        }

        return utType.conforms(to: .image)
    }

    private func decodePlainText(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .unicode
        ]

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding), !text.isEmpty {
                return text
            }
        }

        return nil
    }

    private func makePassthroughPreviewText(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "超长文本" }
        guard trimmed.count > Self.passthroughPreviewCharacterLimit else { return trimmed }
        return String(trimmed.prefix(Self.passthroughPreviewCharacterLimit - 1)) + "…"
    }

    private func normalizedPassthroughPreviewText(_ text: String?) -> String {
        guard let text else { return "超长文本" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "超长文本" : trimmed
    }
}
