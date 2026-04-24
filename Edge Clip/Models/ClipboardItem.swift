import CryptoKit
import Foundation

enum StackOrderMode: String, Codable, CaseIterable {
    case sequential
    case reverse

    var title: String {
        switch self {
        case .sequential:
            return AppLocalization.localized("顺序")
        case .reverse:
            return AppLocalization.localized("倒序")
        }
    }
}

enum StackDelimiterOption: String, Codable, CaseIterable, Hashable {
    case newline
    case whitespace
    case comma
    case period
    case custom

    var title: String {
        switch self {
        case .newline:
            return AppLocalization.localized("换行")
        case .whitespace:
            return AppLocalization.localized("空格")
        case .comma:
            return AppLocalization.localized("逗号")
        case .period:
            return AppLocalization.localized("句号")
        case .custom:
            return AppLocalization.localized("自定义")
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    static let maximumStoredTextByteCount = 8 * 1_024 * 1_024
    private static let maximumFullPreviewTextByteCount = 96 * 1_024
    private static let maximumPartialPreviewTextByteCount = 1 * 1_024 * 1_024
    private static let maximumFullPreviewLogicalLineCount = 400
    private static let maximumPartialPreviewLogicalLineCount = 6_000
    private static let maximumFullPreviewLongestLineCharacterCount = 1_200
    private static let maximumPartialPreviewLongestLineCharacterCount = 12_000
    private static let partialPreviewHeadLineCount = 120
    private static let partialPreviewTailLineCount = 36
    private static let summaryPreviewHeadLineCount = 140
    private static let partialPreviewHeadCharacterLimit = 16_000
    private static let partialPreviewTailCharacterLimit = 6_000
    private static let summaryPreviewCharacterLimit = 16_000

    private struct CachedTextAnalysis: Equatable {
        let resolvedURL: URL?
        let isLikelyCode: Bool

        static let empty = CachedTextAnalysis(resolvedURL: nil, isLikelyCode: false)
    }

    private struct TextProfile: Equatable {
        let previewText: String
        let headSample: String
        let tailSample: String?
        let byteCount: Int
        let logicalLineCount: Int
        let longestLogicalLineCharacterCount: Int
        let previewTier: TextPayload.PreviewTier
        let isTabular: Bool
        let contentFingerprint: String
    }

    enum ContentKind: String, Codable, CaseIterable {
        case text
        case passthroughText
        case image
        case file
        case stack

        var title: String {
            switch self {
            case .text:
                return AppLocalization.localized("文本")
            case .passthroughText:
                return AppLocalization.localized("文本")
            case .image:
                return AppLocalization.localized("图片")
            case .file:
                return AppLocalization.localized("文件")
            case .stack:
                return AppLocalization.localized("堆栈")
            }
        }

        var symbolName: String {
            switch self {
            case .text:
                return "text.alignleft"
            case .passthroughText:
                return "bolt.horizontal.fill"
            case .image:
                return "photo"
            case .file:
                return "doc"
            case .stack:
                return "square.stack.3d.down.forward"
            }
        }
    }

    enum AvailabilityIssue: String, Codable, Equatable {
        case sourceUnavailable
    }

    struct StackEntry: Identifiable, Codable, Equatable {
        enum Source: String, Codable, Equatable {
            case manual
            case processor
        }

        let id: UUID
        var text: String
        var createdAt: Date
        var source: Source

        init(
            id: UUID = UUID(),
            text: String,
            createdAt: Date = Date(),
            source: Source = .manual
        ) {
            self.id = id
            self.text = text
            self.createdAt = createdAt
            self.source = source
        }
    }

    struct StackPayload: Codable, Equatable {
        var entries: [StackEntry]
        var orderMode: StackOrderMode
        var updatedAt: Date

        init(
            entries: [StackEntry] = [],
            orderMode: StackOrderMode = .sequential,
            updatedAt: Date = Date()
        ) {
            self.entries = entries
            self.orderMode = orderMode
            self.updatedAt = updatedAt
        }
    }

    struct TextPayload: Codable, Equatable {
        enum PreviewTier: String, Codable, Equatable {
            case full
            case partial
            case summary

            var title: String {
                switch self {
                case .full:
                    return AppLocalization.localized("完整预览")
                case .partial:
                    return AppLocalization.localized("部分预览")
                case .summary:
                    return AppLocalization.localized("摘要预览")
                }
            }
        }

        private static func normalizedPreviewComparisonText(_ text: String) -> String {
            text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        }

        var rawText: String?
        var assetRelativePath: String?
        var previewText: String
        var headSample: String
        var tailSample: String?
        var byteCount: Int
        var logicalLineCount: Int
        var longestLogicalLineCharacterCount: Int
        var previewTier: PreviewTier
        var isTabular: Bool
        var contentFingerprint: String

        var hasTruncatedPreview: Bool {
            switch previewTier {
            case .full:
                return false
            case .summary:
                return true
            case .partial:
                if tailSample != nil {
                    return true
                }
                if logicalLineCount > ClipboardItem.partialPreviewHeadLineCount {
                    return true
                }
                if let rawText {
                    return Self.normalizedPreviewComparisonText(rawText) != headSample
                }

                let headSampleByteCount = headSample.lengthOfBytes(using: .utf8)
                let newlineNormalizationAllowance = max(0, logicalLineCount - 1)
                return byteCount > headSampleByteCount + newlineNormalizationAllowance
            }
        }

        init(
            rawText: String?,
            assetRelativePath: String? = nil,
            previewText: String,
            headSample: String,
            tailSample: String?,
            byteCount: Int,
            logicalLineCount: Int,
            longestLogicalLineCharacterCount: Int,
            previewTier: PreviewTier,
            isTabular: Bool,
            contentFingerprint: String
        ) {
            self.rawText = rawText
            self.assetRelativePath = assetRelativePath
            self.previewText = previewText
            self.headSample = headSample
            self.tailSample = tailSample
            self.byteCount = byteCount
            self.logicalLineCount = logicalLineCount
            self.longestLogicalLineCharacterCount = longestLogicalLineCharacterCount
            self.previewTier = previewTier
            self.isTabular = isTabular
            self.contentFingerprint = contentFingerprint
        }

        init(rawText: String) {
            self = ClipboardItem.makeTextPayload(rawText: rawText, assetRelativePath: nil)
        }

        private enum CodingKeys: String, CodingKey {
            case rawText
            case assetRelativePath
            case previewText
            case headSample
            case tailSample
            case byteCount
            case logicalLineCount
            case longestLogicalLineCharacterCount
            case previewTier
            case isTabular
            case contentFingerprint
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let decodedRawText = try container.decodeIfPresent(String.self, forKey: .rawText)
            let decodedAssetRelativePath = try container.decodeIfPresent(String.self, forKey: .assetRelativePath)

            if let decodedRawText {
                let fallback = ClipboardItem.makeTextPayload(
                    rawText: decodedRawText,
                    assetRelativePath: decodedAssetRelativePath
                )
                rawText = decodedAssetRelativePath == nil ? decodedRawText : nil
                assetRelativePath = decodedAssetRelativePath
                previewText = try container.decodeIfPresent(String.self, forKey: .previewText) ?? fallback.previewText
                headSample = try container.decodeIfPresent(String.self, forKey: .headSample) ?? fallback.headSample
                tailSample = try container.decodeIfPresent(String.self, forKey: .tailSample) ?? fallback.tailSample
                byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount) ?? fallback.byteCount
                logicalLineCount = try container.decodeIfPresent(Int.self, forKey: .logicalLineCount) ?? fallback.logicalLineCount
                longestLogicalLineCharacterCount = try container.decodeIfPresent(
                    Int.self,
                    forKey: .longestLogicalLineCharacterCount
                ) ?? fallback.longestLogicalLineCharacterCount
                previewTier = try container.decodeIfPresent(PreviewTier.self, forKey: .previewTier) ?? fallback.previewTier
                isTabular = try container.decodeIfPresent(Bool.self, forKey: .isTabular) ?? fallback.isTabular
                contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint)
                    ?? fallback.contentFingerprint
                return
            }

            rawText = nil
            assetRelativePath = decodedAssetRelativePath
            previewText = try container.decodeIfPresent(String.self, forKey: .previewText) ?? ""
            headSample = try container.decodeIfPresent(String.self, forKey: .headSample) ?? previewText
            tailSample = try container.decodeIfPresent(String.self, forKey: .tailSample)
            byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount) ?? 0
            logicalLineCount = try container.decodeIfPresent(Int.self, forKey: .logicalLineCount) ?? 0
            longestLogicalLineCharacterCount = try container.decodeIfPresent(
                Int.self,
                forKey: .longestLogicalLineCharacterCount
            ) ?? 0
            previewTier = try container.decodeIfPresent(PreviewTier.self, forKey: .previewTier) ?? .summary
            isTabular = try container.decodeIfPresent(Bool.self, forKey: .isTabular) ?? false
            contentFingerprint = try container.decodeIfPresent(String.self, forKey: .contentFingerprint)
                    ?? ClipboardItem.contentFingerprint(for: previewText)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(rawText, forKey: .rawText)
            try container.encodeIfPresent(assetRelativePath, forKey: .assetRelativePath)
            try container.encode(previewText, forKey: .previewText)
            try container.encode(headSample, forKey: .headSample)
            try container.encodeIfPresent(tailSample, forKey: .tailSample)
            try container.encode(byteCount, forKey: .byteCount)
            try container.encode(logicalLineCount, forKey: .logicalLineCount)
            try container.encode(
                longestLogicalLineCharacterCount,
                forKey: .longestLogicalLineCharacterCount
            )
            try container.encode(previewTier, forKey: .previewTier)
            try container.encode(isTabular, forKey: .isTabular)
            try container.encode(contentFingerprint, forKey: .contentFingerprint)
        }
    }

    struct PassthroughTextPayload: Codable, Equatable {
        enum Mode: String, Codable, Equatable {
            case pending
            case clipboardOnly
            case cachedOneTime
            case abandoned
            case discarded
        }

        var requestID: UUID
        var capturedChangeCount: Int
        var previewText: String
        var mode: Mode
        var byteCount: Int?
        var cacheToken: String?

        init(
            requestID: UUID = UUID(),
            capturedChangeCount: Int,
            previewText: String,
            mode: Mode = .pending,
            byteCount: Int? = nil,
            cacheToken: String? = nil
        ) {
            self.requestID = requestID
            self.capturedChangeCount = capturedChangeCount
            self.previewText = previewText
            self.mode = mode
            self.byteCount = byteCount
            self.cacheToken = cacheToken
        }

        private enum CodingKeys: String, CodingKey {
            case requestID
            case capturedChangeCount
            case previewText
            case mode
            case byteCount
            case cacheToken
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            requestID = try container.decodeIfPresent(UUID.self, forKey: .requestID) ?? UUID()
            capturedChangeCount = try container.decodeIfPresent(Int.self, forKey: .capturedChangeCount) ?? 0
            previewText = try container.decodeIfPresent(String.self, forKey: .previewText) ?? AppLocalization.localized("系统剪贴板文本（未预读）")
            mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .pending
            byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
            cacheToken = try container.decodeIfPresent(String.self, forKey: .cacheToken)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(requestID, forKey: .requestID)
            try container.encode(capturedChangeCount, forKey: .capturedChangeCount)
            try container.encode(previewText, forKey: .previewText)
            try container.encode(mode, forKey: .mode)
            try container.encodeIfPresent(byteCount, forKey: .byteCount)
            try container.encodeIfPresent(cacheToken, forKey: .cacheToken)
        }
    }

    struct ImagePayload: Codable, Equatable {
        var assetRelativePath: String
        var pixelWidth: Int
        var pixelHeight: Int
        var byteSize: Int
    }

    struct FilePayload: Codable, Equatable {
        var fileURLs: [URL]
        var displayNames: [String]
        var securityScopedBookmarks: [Data?]
        var protectedAssetRelativePaths: [String]
        var protectedAssetByteCount: Int

        init(
            fileURLs: [URL],
            displayNames: [String],
            securityScopedBookmarks: [Data?] = [],
            protectedAssetRelativePaths: [String] = [],
            protectedAssetByteCount: Int = 0
        ) {
            self.fileURLs = fileURLs
            self.displayNames = displayNames
            self.protectedAssetRelativePaths = protectedAssetRelativePaths
            self.protectedAssetByteCount = protectedAssetByteCount
            if securityScopedBookmarks.isEmpty {
                self.securityScopedBookmarks = Array(repeating: nil, count: fileURLs.count)
            } else if securityScopedBookmarks.count < fileURLs.count {
                self.securityScopedBookmarks = securityScopedBookmarks + Array(
                    repeating: nil,
                    count: fileURLs.count - securityScopedBookmarks.count
                )
            } else {
                self.securityScopedBookmarks = Array(securityScopedBookmarks.prefix(fileURLs.count))
            }
        }

        private enum CodingKeys: String, CodingKey {
            case fileURLs
            case displayNames
            case securityScopedBookmarks
            case protectedAssetRelativePaths
            case protectedAssetByteCount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fileURLs = try container.decodeIfPresent([URL].self, forKey: .fileURLs) ?? []
            displayNames = try container.decodeIfPresent([String].self, forKey: .displayNames) ?? []
            protectedAssetRelativePaths = try container.decodeIfPresent(
                [String].self,
                forKey: .protectedAssetRelativePaths
            ) ?? []
            protectedAssetByteCount = try container.decodeIfPresent(
                Int.self,
                forKey: .protectedAssetByteCount
            ) ?? 0
            let decodedBookmarks = try container.decodeIfPresent([Data?].self, forKey: .securityScopedBookmarks) ?? []
            if decodedBookmarks.isEmpty {
                securityScopedBookmarks = Array(repeating: nil, count: fileURLs.count)
            } else if decodedBookmarks.count < fileURLs.count {
                securityScopedBookmarks = decodedBookmarks + Array(
                    repeating: nil,
                    count: fileURLs.count - decodedBookmarks.count
                )
            } else {
                securityScopedBookmarks = Array(decodedBookmarks.prefix(fileURLs.count))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(fileURLs, forKey: .fileURLs)
            try container.encode(displayNames, forKey: .displayNames)
            try container.encode(securityScopedBookmarks, forKey: .securityScopedBookmarks)
            try container.encode(protectedAssetRelativePaths, forKey: .protectedAssetRelativePaths)
            try container.encode(protectedAssetByteCount, forKey: .protectedAssetByteCount)
        }
    }

    let id: UUID
    var createdAt: Date
    var kind: ContentKind {
        didSet {
            cachedTextAnalysis = Self.makeCachedTextAnalysis(kind: kind, textPayload: textPayload)
        }
    }
    var isFavorite: Bool
    var favoriteSortOrder: Int?
    var favoriteGroupIDs: [UUID]
    var availabilityIssue: AvailabilityIssue?
    var sourceAppBundleID: String?
    var sourceAppName: String?
    var textPayload: TextPayload? {
        didSet {
            cachedTextAnalysis = Self.makeCachedTextAnalysis(kind: kind, textPayload: textPayload)
        }
    }
    var passthroughTextPayload: PassthroughTextPayload?
    var imagePayload: ImagePayload?
    var filePayload: FilePayload?
    var stackPayload: StackPayload?
    private var cachedTextAnalysis: CachedTextAnalysis

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: ContentKind,
        isFavorite: Bool = false,
        favoriteSortOrder: Int? = nil,
        favoriteGroupIDs: [UUID] = [],
        availabilityIssue: AvailabilityIssue? = nil,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil,
        textPayload: TextPayload? = nil,
        passthroughTextPayload: PassthroughTextPayload? = nil,
        imagePayload: ImagePayload? = nil,
        filePayload: FilePayload? = nil,
        stackPayload: StackPayload? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.isFavorite = isFavorite
        self.favoriteSortOrder = favoriteSortOrder
        self.favoriteGroupIDs = Self.sanitizedFavoriteGroupIDs(favoriteGroupIDs)
        self.availabilityIssue = availabilityIssue
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceAppName = sourceAppName
        self.textPayload = textPayload
        self.passthroughTextPayload = passthroughTextPayload
        self.imagePayload = imagePayload
        self.filePayload = filePayload
        self.stackPayload = stackPayload
        self.cachedTextAnalysis = Self.makeCachedTextAnalysis(kind: kind, textPayload: textPayload)
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        text: String,
        isFavorite: Bool = false,
        favoriteGroupIDs: [UUID] = [],
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.init(
            id: id,
            createdAt: createdAt,
            kind: .text,
            isFavorite: isFavorite,
            favoriteGroupIDs: favoriteGroupIDs,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            textPayload: TextPayload(rawText: text)
        )
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        passthroughTextPayload: PassthroughTextPayload,
        isFavorite: Bool = false,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.init(
            id: id,
            createdAt: createdAt,
            kind: .passthroughText,
            isFavorite: isFavorite,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            passthroughTextPayload: passthroughTextPayload
        )
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        imagePayload: ImagePayload,
        isFavorite: Bool = false,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.init(
            id: id,
            createdAt: createdAt,
            kind: .image,
            isFavorite: isFavorite,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            imagePayload: imagePayload
        )
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        fileURLs: [URL],
        displayNames: [String],
        securityScopedBookmarks: [Data?] = [],
        isFavorite: Bool = false,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.init(
            id: id,
            createdAt: createdAt,
            kind: .file,
            isFavorite: isFavorite,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            filePayload: FilePayload(
                fileURLs: fileURLs,
                displayNames: displayNames,
                securityScopedBookmarks: securityScopedBookmarks
            )
        )
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        stackPayload: StackPayload,
        isFavorite: Bool = false,
        sourceAppBundleID: String? = nil,
        sourceAppName: String? = nil
    ) {
        self.init(
            id: id,
            createdAt: createdAt,
            kind: .stack,
            isFavorite: isFavorite,
            sourceAppBundleID: sourceAppBundleID,
            sourceAppName: sourceAppName,
            stackPayload: stackPayload
        )
    }

    var preview: String {
        switch kind {
        case .text:
            return textPayload?.previewText ?? ""
        case .passthroughText:
            return passthroughTextPayload?.previewText ?? passthroughTextSummary
        case .image:
            return imageMetadataSummary
        case .file:
            return fileSummary
        case .stack:
            return stackSummary
        }
    }

    var textContent: String? {
        textPayload?.rawText
    }

    var textAssetRelativePath: String? {
        textPayload?.assetRelativePath
    }

    var textPreviewTier: TextPayload.PreviewTier? {
        textPayload?.previewTier
    }

    var textByteCount: Int? {
        textPayload?.byteCount
    }

    var textLogicalLineCount: Int? {
        textPayload?.logicalLineCount
    }

    var textLongestLogicalLineCharacterCount: Int? {
        textPayload?.longestLogicalLineCharacterCount
    }

    var isTabularText: Bool {
        textPayload?.isTabular ?? false
    }

    var hasTruncatedTextPreview: Bool {
        textPayload?.hasTruncatedPreview ?? false
    }

    var textPreviewBody: String? {
        guard let payload = textPayload else { return nil }

        switch payload.previewTier {
        case .full:
            return payload.rawText ?? payload.headSample
        case .partial:
            return payload.headSample
        case .summary:
            return payload.headSample
        }
    }

    var passthroughTextChangeCount: Int? {
        passthroughTextPayload?.capturedChangeCount
    }

    var passthroughTextRequestID: UUID? {
        passthroughTextPayload?.requestID
    }

    var passthroughTextMode: PassthroughTextPayload.Mode? {
        passthroughTextPayload?.mode
    }

    var passthroughTextCacheToken: String? {
        passthroughTextPayload?.cacheToken
    }

    var passthroughTextByteCount: Int? {
        passthroughTextPayload?.byteCount
    }

    var isPendingPassthroughText: Bool {
        passthroughTextPayload?.mode == .pending
    }

    var isClipboardOnlyPassthroughText: Bool {
        passthroughTextPayload?.mode == .clipboardOnly
    }

    var isCachedOneTimePassthroughText: Bool {
        passthroughTextPayload?.mode == .cachedOneTime
    }

    var isAbandonedPassthroughText: Bool {
        passthroughTextPayload?.mode == .abandoned
    }

    var isDiscardedPassthroughText: Bool {
        passthroughTextPayload?.mode == .discarded
    }

    var isSessionOnly: Bool {
        kind == .passthroughText
    }

    var hasAvailabilityIssue: Bool {
        availabilityIssue != nil
    }

    func belongs(to favoriteGroupID: FavoriteGroup.ID?) -> Bool {
        guard let favoriteGroupID else { return true }
        return favoriteGroupIDs.contains(favoriteGroupID)
    }

    func isPassthroughTextValid(currentChangeCount: Int) -> Bool {
        guard let passthroughTextChangeCount else {
            return false
        }
        return passthroughTextChangeCount == currentChangeCount
    }

    var resolvedURL: URL? {
        cachedTextAnalysis.resolvedURL
    }

    var isLikelyURL: Bool {
        resolvedURL != nil
    }

    var isLikelyCode: Bool {
        cachedTextAnalysis.isLikelyCode
    }

    var imageAssetRelativePath: String? {
        imagePayload?.assetRelativePath
    }

    var fileURLs: [URL] {
        filePayload?.fileURLs ?? []
    }

    var fileDisplayNames: [String] {
        let names = filePayload?.displayNames ?? []
        if !names.isEmpty {
            return names
        }

        return fileURLs.map(\.lastPathComponent)
    }

    var fileSecurityScopedBookmarks: [Data?] {
        filePayload?.securityScopedBookmarks ?? []
    }

    var fileProtectedAssetRelativePaths: [String] {
        filePayload?.protectedAssetRelativePaths ?? []
    }

    var hasProtectedFileCopies: Bool {
        !fileProtectedAssetRelativePaths.isEmpty
    }

    var sourceAppDisplayName: String {
        let trimmed = sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? AppLocalization.localized("未知来源") : trimmed
    }

    var stackEntries: [StackEntry] {
        stackPayload?.entries ?? []
    }

    var stackOrderMode: StackOrderMode {
        stackPayload?.orderMode ?? .sequential
    }

    var stackUpdatedAt: Date {
        stackPayload?.updatedAt ?? createdAt
    }

    var stackSummary: String {
        let entries = stackEntries
        guard !entries.isEmpty else {
            return AppLocalization.localized("空堆栈")
        }

        let previews = entries.prefix(2).map { Self.makePreviewText(from: $0.text) }
        let joinedPreview = previews.joined(separator: " / ")
        if AppLocalization.isEnglish {
            let noun = entries.count == 1 ? "item" : "items"
            return "\(entries.count) \(noun) queued · \(joinedPreview)"
        }
        return "\(entries.count) 条待粘贴 · \(joinedPreview)"
    }

    var passthroughTextSummary: String {
        if let byteCount = passthroughTextByteCount,
           isCachedOneTimePassthroughText {
            let sizeText = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        if AppLocalization.isEnglish {
            return "Long text from \(sourceAppDisplayName) · \(sizeText)"
        }
        return "来自 \(sourceAppDisplayName) 的超长文本 · \(sizeText)"
        }

        if AppLocalization.isEnglish {
            return "Long text from \(sourceAppDisplayName)"
        }
        return "来自 \(sourceAppDisplayName) 的超长文本"
    }

    var fileSummary: String {
        let names = fileDisplayNames
        guard let first = names.first else {
            return AppLocalization.localized("文件项目")
        }

        if names.count == 1 {
            return first
        }

        if AppLocalization.isEnglish {
            return "\(first) and \(names.count - 1) more"
        }
        return "\(first) 等 \(names.count - 1) 项"
    }

    var imageMetadataSummary: String {
        guard let imagePayload else {
            return AppLocalization.localized("图片")
        }

        let sizeText = ByteCountFormatter.string(
            fromByteCount: Int64(imagePayload.byteSize),
            countStyle: .file
        )
        return "\(imagePayload.pixelWidth) x \(imagePayload.pixelHeight) · \(sizeText)"
    }

    var duplicateIdentityKey: String? {
        switch kind {
        case .text:
            guard let fingerprint = textPayload?.contentFingerprint,
                  !fingerprint.isEmpty else { return nil }
            return "text:\(fingerprint)"
        case .passthroughText:
            guard let requestID = passthroughTextPayload?.requestID else { return nil }
            return "passthrough:\(requestID.uuidString)"
        case .file:
            let paths = fileURLs.map(\.standardizedFileURL.path)
            guard !paths.isEmpty else { return nil }
            return "file:\(paths.joined(separator: "|"))"
        case .image:
            return nil
        case .stack:
            return nil
        }
    }

    var estimatedStorageBytes: Int {
        switch kind {
        case .text:
            return (textPayload?.byteCount ?? 0) + 224
        case .passthroughText:
            return 256
        case .image:
            return (imagePayload?.byteSize ?? 0) + 192
        case .file:
            let urlBytes = fileURLs.reduce(0) { partial, url in
                partial + url.absoluteString.lengthOfBytes(using: .utf8)
            }
            let nameBytes = fileDisplayNames.reduce(0) { partial, name in
                partial + name.lengthOfBytes(using: .utf8)
            }
            return urlBytes + nameBytes + (filePayload?.protectedAssetByteCount ?? 0) + 192
        case .stack:
            let entryBytes = stackEntries.reduce(0) { partial, entry in
                partial + entry.text.lengthOfBytes(using: .utf8)
            }
            return entryBytes + 224
        }
    }

    func refreshed(using latest: ClipboardItem) -> ClipboardItem {
        let refreshedFilePayload: FilePayload?
        if let latestFilePayload = latest.filePayload {
            if let existingFilePayload = filePayload,
               !existingFilePayload.protectedAssetRelativePaths.isEmpty {
                var mergedFilePayload = latestFilePayload
                mergedFilePayload.protectedAssetRelativePaths = existingFilePayload.protectedAssetRelativePaths
                mergedFilePayload.protectedAssetByteCount = existingFilePayload.protectedAssetByteCount
                refreshedFilePayload = mergedFilePayload
            } else {
                refreshedFilePayload = latestFilePayload
            }
        } else {
            refreshedFilePayload = filePayload
        }

        return ClipboardItem(
            id: id,
            createdAt: latest.createdAt,
            kind: kind,
            isFavorite: isFavorite,
            favoriteSortOrder: favoriteSortOrder,
            favoriteGroupIDs: favoriteGroupIDs,
            availabilityIssue: latest.availabilityIssue,
            sourceAppBundleID: latest.sourceAppBundleID,
            sourceAppName: latest.sourceAppName,
            textPayload: latest.textPayload ?? textPayload,
            passthroughTextPayload: latest.passthroughTextPayload ?? passthroughTextPayload,
            imagePayload: latest.imagePayload ?? imagePayload,
            filePayload: refreshedFilePayload,
            stackPayload: latest.stackPayload ?? stackPayload
        )
    }

    func matchesSearchQuery(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return true }

        let haystacks: [String]
        switch kind {
        case .text:
            let textHaystacks: [String]
            if textPayload?.previewTier == .full {
                textHaystacks = [textPayload?.rawText ?? ""]
            } else {
                textHaystacks = [
                    textPayload?.previewText ?? "",
                    textPayload?.headSample ?? "",
                    textPayload?.tailSample ?? ""
                ]
            }
            haystacks = textHaystacks + [sourceAppDisplayName]
        case .passthroughText:
            haystacks = [
                passthroughTextSummary,
                sourceAppDisplayName
            ]
        case .image:
            haystacks = [
                sourceAppDisplayName,
                imageMetadataSummary
            ]
        case .file:
            haystacks = fileDisplayNames + [sourceAppDisplayName]
        case .stack:
            haystacks = stackEntries.map(\.text) + [stackSummary]
        }

        return haystacks.contains {
            $0.localizedCaseInsensitiveContains(normalized)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case kind
        case isFavorite
        case favoriteSortOrder
        case favoriteGroupIDs
        case availabilityIssue
        case sourceAppBundleID
        case sourceAppName
        case textPayload
        case passthroughTextPayload
        case imagePayload
        case filePayload
        case stackPayload

        // Legacy v1 keys.
        case content
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        sourceAppBundleID = try container.decodeIfPresent(String.self, forKey: .sourceAppBundleID)
        sourceAppName = try container.decodeIfPresent(String.self, forKey: .sourceAppName)
        let decodedIsFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite)
        let legacyIsPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned)
        isFavorite = decodedIsFavorite ?? legacyIsPinned ?? false
        favoriteSortOrder = try container.decodeIfPresent(Int.self, forKey: .favoriteSortOrder)
        favoriteGroupIDs = Self.sanitizedFavoriteGroupIDs(
            try container.decodeIfPresent([UUID].self, forKey: .favoriteGroupIDs) ?? []
        )
        availabilityIssue = try container.decodeIfPresent(AvailabilityIssue.self, forKey: .availabilityIssue)

        let decodedKind = try container.decodeIfPresent(ContentKind.self, forKey: .kind)
        textPayload = try container.decodeIfPresent(TextPayload.self, forKey: .textPayload)
        passthroughTextPayload = try container.decodeIfPresent(PassthroughTextPayload.self, forKey: .passthroughTextPayload)
        imagePayload = try container.decodeIfPresent(ImagePayload.self, forKey: .imagePayload)
        filePayload = try container.decodeIfPresent(FilePayload.self, forKey: .filePayload)
        stackPayload = try container.decodeIfPresent(StackPayload.self, forKey: .stackPayload)

        if textPayload == nil,
           passthroughTextPayload == nil,
           imagePayload == nil,
           filePayload == nil,
           stackPayload == nil,
           let legacyContent = try container.decodeIfPresent(String.self, forKey: .content) {
            textPayload = TextPayload(rawText: legacyContent)
        }

        if passthroughTextPayload != nil {
            kind = .passthroughText
        } else if textPayload != nil {
            kind = .text
        } else if imagePayload != nil {
            kind = .image
        } else if filePayload != nil {
            kind = .file
        } else if stackPayload != nil {
            kind = .stack
        } else {
            kind = decodedKind ?? .text
            if kind == .passthroughText {
                passthroughTextPayload = PassthroughTextPayload(
                    capturedChangeCount: 0,
                    previewText: AppLocalization.localized("系统剪贴板文本（未预读）")
                )
            } else if kind == .text {
                textPayload = TextPayload(rawText: "")
            } else if kind == .stack {
                stackPayload = StackPayload()
            }
        }

        cachedTextAnalysis = Self.makeCachedTextAnalysis(kind: kind, textPayload: textPayload)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(kind, forKey: .kind)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(favoriteSortOrder, forKey: .favoriteSortOrder)
        try container.encode(favoriteGroupIDs, forKey: .favoriteGroupIDs)
        try container.encodeIfPresent(availabilityIssue, forKey: .availabilityIssue)
        try container.encodeIfPresent(sourceAppBundleID, forKey: .sourceAppBundleID)
        try container.encodeIfPresent(sourceAppName, forKey: .sourceAppName)
        try container.encodeIfPresent(textPayload, forKey: .textPayload)
        try container.encodeIfPresent(passthroughTextPayload, forKey: .passthroughTextPayload)
        try container.encodeIfPresent(imagePayload, forKey: .imagePayload)
        try container.encodeIfPresent(filePayload, forKey: .filePayload)
        try container.encodeIfPresent(stackPayload, forKey: .stackPayload)
    }

    private static func sanitizedFavoriteGroupIDs(_ groupIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var result: [UUID] = []
        for groupID in groupIDs where seen.insert(groupID).inserted {
            result.append(groupID)
        }
        return result
    }

    static func exceedsStoredTextLimit(_ text: String) -> Bool {
        text.lengthOfBytes(using: .utf8) > maximumStoredTextByteCount
    }

    static func makePreviewText(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 120 else {
            return trimmed
        }

        return String(trimmed.prefix(117)) + "..."
    }

    static func makeTextPayload(rawText: String, assetRelativePath: String?) -> TextPayload {
        let profile = profileText(rawText)
        return TextPayload(
            rawText: assetRelativePath == nil ? rawText : nil,
            assetRelativePath: assetRelativePath,
            previewText: profile.previewText,
            headSample: profile.headSample,
            tailSample: profile.tailSample,
            byteCount: profile.byteCount,
            logicalLineCount: profile.logicalLineCount,
            longestLogicalLineCharacterCount: profile.longestLogicalLineCharacterCount,
            previewTier: profile.previewTier,
            isTabular: profile.isTabular,
            contentFingerprint: profile.contentFingerprint
        )
    }

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func makeCachedTextAnalysis(
        kind: ContentKind,
        textPayload: TextPayload?
    ) -> CachedTextAnalysis {
        guard kind == .text,
              let text = textPayload?.rawText ?? textPayload?.headSample
        else {
            return .empty
        }

        let resolvedURL = resolveURL(from: text)
        let isLikelyCode = detectLikelyCode(in: text, resolvedURL: resolvedURL)
        return CachedTextAnalysis(resolvedURL: resolvedURL, isLikelyCode: isLikelyCode)
    }

    private static func profileText(_ rawText: String) -> TextProfile {
        let byteCount = rawText.lengthOfBytes(using: .utf8)
        let logicalLines = normalizedLogicalLines(in: rawText)
        let logicalLineCount = max(1, logicalLines.count)
        let longestLogicalLineCharacterCount = logicalLines.map(\.count).max() ?? rawText.count
        let isTabular = detectTabularText(in: logicalLines)

        let previewTier: TextPayload.PreviewTier
        if byteCount <= maximumFullPreviewTextByteCount &&
            logicalLineCount <= maximumFullPreviewLogicalLineCount &&
            longestLogicalLineCharacterCount <= maximumFullPreviewLongestLineCharacterCount {
            previewTier = .full
        } else if byteCount <= maximumPartialPreviewTextByteCount &&
                    logicalLineCount <= maximumPartialPreviewLogicalLineCount &&
                    longestLogicalLineCharacterCount <= maximumPartialPreviewLongestLineCharacterCount {
            previewTier = .partial
        } else {
            previewTier = .summary
        }

        let previewText = makePreviewText(from: rawText)
        let headSample: String
        let tailSample: String?

        switch previewTier {
        case .full:
            headSample = rawText
            tailSample = nil
        case .partial:
            headSample = makeSample(
                from: Array(logicalLines.prefix(partialPreviewHeadLineCount)),
                characterLimit: partialPreviewHeadCharacterLimit
            )
            let tailLines = Array(logicalLines.suffix(partialPreviewTailLineCount))
            let sampledTail = makeSample(
                from: tailLines,
                characterLimit: partialPreviewTailCharacterLimit
            )
            let normalizedHead = headSample.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedTail = sampledTail.trimmingCharacters(in: .whitespacesAndNewlines)
            tailSample = normalizedTail.isEmpty || normalizedTail == normalizedHead ? nil : sampledTail
        case .summary:
            headSample = makeSample(
                from: Array(logicalLines.prefix(summaryPreviewHeadLineCount)),
                characterLimit: summaryPreviewCharacterLimit
            )
            tailSample = nil
        }

        return TextProfile(
            previewText: previewText,
            headSample: headSample,
            tailSample: tailSample,
            byteCount: byteCount,
            logicalLineCount: logicalLineCount,
            longestLogicalLineCharacterCount: longestLogicalLineCharacterCount,
            previewTier: previewTier,
            isTabular: isTabular,
            contentFingerprint: contentFingerprint(for: rawText)
        )
    }

    private static func normalizedLogicalLines(in rawText: String) -> [String] {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.isEmpty ? [normalized] : lines
    }

    private static func makeSample(from lines: [String], characterLimit: Int) -> String {
        guard !lines.isEmpty else { return "" }

        var collected: [String] = []
        var currentCount = 0

        for line in lines {
            let nextCount = currentCount + line.count + (collected.isEmpty ? 0 : 1)
            if !collected.isEmpty && nextCount > characterLimit {
                break
            }

            if collected.isEmpty && line.count > characterLimit {
                collected.append(String(line.prefix(max(80, characterLimit - 1))) + "…")
                break
            }

            collected.append(line)
            currentCount = nextCount
        }

        return collected.joined(separator: "\n")
    }

    private static func detectTabularText(in lines: [String]) -> Bool {
        let sampleLines = Array(lines.prefix(24))
        guard sampleLines.count >= 2 else { return false }

        let tabSeparatedCount = sampleLines.reduce(into: 0) { partial, line in
            if line.contains("\t") {
                partial += 1
            }
        }
        if tabSeparatedCount >= 2 {
            return true
        }

        let commaSeparatedCount = sampleLines.reduce(into: 0) { partial, line in
            let commaCount = line.reduce(into: 0) { count, character in
                if character == "," || character == ";" {
                    count += 1
                }
            }
            if commaCount >= 3 {
                partial += 1
            }
        }
        return commaSeparatedCount >= 3
    }

    static func contentFingerprint(for rawText: String) -> String {
        let digest = SHA256.hash(data: Data(rawText.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func resolveURL(from rawText: String) -> URL? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        if let detector = linkDetector,
           let match = detector.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
           let url = match.url,
           match.range.location == 0,
           match.range.length == trimmed.utf16.count,
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme) {
            return url
        }

        if let directURL = URL(string: trimmed),
           let scheme = directURL.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           directURL.host?.isEmpty == false {
            return directURL
        }

        guard trimmed.unicodeScalars.allSatisfy({ $0.isASCII }) else {
            return nil
        }

        let hostCandidate = trimmed.split(whereSeparator: { ["/", "?", "#"].contains($0) }).first.map(String.init) ?? trimmed
        let domainPattern = #"(?i)^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"#

        guard hostCandidate.range(of: domainPattern, options: .regularExpression) != nil,
              hostCandidate.contains(where: { $0.isLetter }),
              let normalizedURL = URL(string: "https://\(trimmed)"),
              normalizedURL.host?.isEmpty == false
        else {
            return nil
        }

        return normalizedURL
    }

    private static func detectLikelyCode(in text: String, resolvedURL: URL?) -> Bool {
        guard resolvedURL == nil else { return false }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return false }

        let newlineCount = trimmed.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
        let codeSignals = [
            "func ", "class ", "struct ", "enum ", "import ", "return ", "let ", "var ",
            "const ", "def ", "if ", "else", "for ", "while ", "public ", "private ",
            "SELECT ", "INSERT ", "UPDATE ", "DELETE ", "{", "}", ";", "</", "/>"
        ]
        let signalCount = codeSignals.reduce(into: 0) { count, signal in
            if trimmed.localizedCaseInsensitiveContains(signal) {
                count += 1
            }
        }

        if newlineCount >= 2 && signalCount >= 1 {
            return true
        }

        if signalCount >= 2 {
            return true
        }

        return false
    }
}
