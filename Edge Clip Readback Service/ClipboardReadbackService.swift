import AppKit
import Foundation
import UniformTypeIdentifiers

final class ClipboardReadbackService: NSObject, NSXPCListenerDelegate, ClipboardReadbackXPCProtocol {
    private static let explicitPlainTextTypes: [NSPasteboard.PasteboardType] = [
        .string,
        NSPasteboard.PasteboardType("NSStringPboardType"),
        NSPasteboard.PasteboardType("public.text"),
        NSPasteboard.PasteboardType("public.plain-text"),
        NSPasteboard.PasteboardType("public.utf8-plain-text"),
        NSPasteboard.PasteboardType("public.utf16-plain-text"),
        NSPasteboard.PasteboardType("public.utf16-external-plain-text")
    ]
    private static let richTextTypes: Set<NSPasteboard.PasteboardType> = [
        .html,
        .rtf,
        NSPasteboard.PasteboardType("com.apple.flat-rtfd")
    ]

    private struct CachedTextEntry {
        let fileURL: URL
        let byteCount: Int
    }

    private final class BoundedCachedTextStore {
        private let entryLimit: Int
        private var storage: [String: CachedTextEntry] = [:]
        private var accessOrder: [String] = []
        private let fileManager: FileManager
        private let rootDirectory: URL

        init(
            entryLimit: Int = 4,
            fileManager: FileManager = .default
        ) {
            self.entryLimit = entryLimit
            self.fileManager = fileManager
            let baseDirectory =
                (try? fileManager.url(
                    for: .cachesDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )) ??
                URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            rootDirectory = baseDirectory
                .appendingPathComponent("edgeclip_readback_text_cache", isDirectory: true)
            try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }

        func value(for key: String) -> CachedTextEntry? {
            guard let entry = storage[key] else { return nil }
            touch(key)
            return entry
        }

        func text(for key: String) -> String? {
            guard let entry = value(for: key) else { return nil }
            return try? String(contentsOf: entry.fileURL, encoding: .utf8)
        }

        func insert(text: String, byteCount: Int, for key: String) {
            if let existing = storage[key] {
                try? fileManager.removeItem(at: existing.fileURL)
                accessOrder.removeAll { $0 == key }
            }

            let fileURL = rootDirectory.appendingPathComponent("\(key).txt", isDirectory: false)
            try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            do {
                try text.write(to: fileURL, atomically: true, encoding: .utf8)
            } catch {
                return
            }

            storage[key] = CachedTextEntry(fileURL: fileURL, byteCount: byteCount)
            accessOrder.append(key)
            evictIfNeeded()
        }

        func removeValue(for key: String) {
            guard let existing = storage.removeValue(forKey: key) else { return }
            try? fileManager.removeItem(at: existing.fileURL)
            accessOrder.removeAll { $0 == key }
        }

        private func touch(_ key: String) {
            accessOrder.removeAll { $0 == key }
            accessOrder.append(key)
        }

        private func evictIfNeeded() {
            while storage.count > entryLimit {
                guard let oldestKey = accessOrder.first else { break }
                removeValue(for: oldestKey)
            }
        }
    }

    private struct PasteboardTextSnapshot {
        let changeCount: Int
        let text: String?
        let byteCount: Int?
        let oversizedRichTextByteCount: Int?
    }

    private static let maximumRichTextParseByteCount = 8 * 1_024 * 1_024
    private static let ignorableTextScalars: Set<UInt32> = [
        0xFEFF,
        0xFFFC,
        0x200B,
        0x200C,
        0x200D,
        0x2060
    ]

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let workQueue = DispatchQueue(label: "com.ivean.edgeclip.readback-service", qos: .utility)
    private let cachedTextByToken = BoundedCachedTextStore()
    private let fileManager = FileManager.default

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: ClipboardReadbackXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func fetchClipboardText(_ requestData: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        workQueue.async { [weak self] in
            guard let self else {
                reply(nil, "性能保护服务不可用。")
                return
            }

            do {
                let request = try self.decoder.decode(ClipboardReadbackRequest.self, from: requestData)
                
                // 前置检查：如果进入队列时已经发现 changeCount 不一致，直接返回 stale。
                let currentChangeCount = self.getPasteboardChangeCount()
                if currentChangeCount != request.expectedChangeCount {
                    let response = ClipboardReadbackResponse(
                        requestID: request.requestID,
                        expectedChangeCount: request.expectedChangeCount,
                        outcome: .stale,
                        text: nil,
                        previewText: nil,
                        byteCount: nil,
                        cacheToken: nil,
                        errorMessage: nil
                    )
                    let responseData = try self.encoder.encode(response)
                    reply(responseData, nil)
                    return
                }

                let response = try self.makeResponse(for: request)
                let responseData = try self.encoder.encode(response)
                reply(responseData, nil)
            } catch {
                let fallbackRequestID = (try? self.decoder.decode(ClipboardReadbackRequest.self, from: requestData).requestID) ?? UUID()
                let fallbackChangeCount = (try? self.decoder.decode(ClipboardReadbackRequest.self, from: requestData).expectedChangeCount) ?? 0
                let response = ClipboardReadbackResponse(
                    requestID: fallbackRequestID,
                    expectedChangeCount: fallbackChangeCount,
                    outcome: .failed,
                    text: nil,
                    previewText: nil,
                    byteCount: nil,
                    cacheToken: nil,
                    errorMessage: error.localizedDescription
                )
                let responseData = try? self.encoder.encode(response)
                reply(responseData, nil)
            }
        }
    }

    func restoreCachedText(_ cacheToken: String, withReply reply: @escaping (Bool, String?) -> Void) {
        workQueue.async { [weak self] in
            guard let self else {
                reply(false, "性能保护服务不可用。")
                return
            }

            guard let entry = self.cachedTextByToken.value(for: cacheToken),
                  let text = try? String(contentsOf: entry.fileURL, encoding: .utf8) else {
                reply(false, "一次性文本缓存已失效。")
                return
            }

            let succeeded = self.performOnMainThread {
                self.writeTextToPasteboard(text, to: .general)
            }
            if succeeded {
                Thread.sleep(forTimeInterval: self.restoreSettleDelay(forByteCount: entry.byteCount))
            }
            reply(succeeded, succeeded ? nil : "无法恢复一次性文本到系统剪贴板。")
        }
    }

    func readCachedText(_ cacheToken: String, withReply reply: @escaping (String?, String?) -> Void) {
        workQueue.async { [weak self] in
            guard let self else {
                reply(nil, "性能保护服务不可用。")
                return
            }

            guard let text = self.cachedTextByToken.text(for: cacheToken) else {
                reply(nil, "一次性文本缓存已失效。")
                return
            }

            reply(text, nil)
        }
    }

    func discardCachedText(_ cacheToken: String, withReply reply: @escaping () -> Void) {
        workQueue.async { [weak self] in
            self?.cachedTextByToken.removeValue(for: cacheToken)
            reply()
        }
    }

    func generatePreviewExport(_ requestData: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        workQueue.async { [weak self] in
            guard let self else {
                reply(nil, "预览导出服务不可用。")
                return
            }

            do {
                let request = try self.decoder.decode(PreviewExportRequest.self, from: requestData)
                let response = try self.makePreviewExportResponse(for: request)
                let responseData = try self.encoder.encode(response)
                reply(responseData, nil)
            } catch {
                let requestID = (try? self.decoder.decode(PreviewExportRequest.self, from: requestData).requestID) ?? UUID()
                let response = PreviewExportResponse(
                    requestID: requestID,
                    previewDirectoryPath: nil,
                    errorMessage: error.localizedDescription
                )
                let responseData = try? self.encoder.encode(response)
                reply(responseData, nil)
            }
        }
    }

    private func makeResponse(for request: ClipboardReadbackRequest) throws -> ClipboardReadbackResponse {
        // 在正式进行可能耗时的 snapshot 动作前，最后进行一次极速检查。
        let currentCount = getPasteboardChangeCount()
        guard currentCount == request.expectedChangeCount else {
            return ClipboardReadbackResponse(
                requestID: request.requestID,
                expectedChangeCount: request.expectedChangeCount,
                outcome: .stale,
                text: nil,
                previewText: nil,
                byteCount: nil,
                cacheToken: nil,
                errorMessage: nil
            )
        }

        let snapshot = snapshotPlainText()
        guard snapshot.changeCount == request.expectedChangeCount else {
            return ClipboardReadbackResponse(
                requestID: request.requestID,
                expectedChangeCount: request.expectedChangeCount,
                outcome: .stale,
                text: nil,
                previewText: nil,
                byteCount: nil,
                cacheToken: nil,
                errorMessage: nil
            )
        }

        guard let text = snapshot.text else {
            if let oversizedByteCount = snapshot.oversizedRichTextByteCount {
                return ClipboardReadbackResponse(
                    requestID: request.requestID,
                    expectedChangeCount: request.expectedChangeCount,
                    outcome: .cachedOneTime,
                    text: nil,
                    previewText: nil,
                    byteCount: oversizedByteCount,
                    cacheToken: nil,
                    errorMessage: nil
                )
            }

            return ClipboardReadbackResponse(
                requestID: request.requestID,
                expectedChangeCount: request.expectedChangeCount,
                outcome: .failed,
                text: nil,
                previewText: nil,
                byteCount: nil,
                cacheToken: nil,
                errorMessage: "未找到可读取的纯文本内容。"
            )
        }

        guard containsMeaningfulText(text) else {
            return ClipboardReadbackResponse(
                requestID: request.requestID,
                expectedChangeCount: request.expectedChangeCount,
                outcome: .failed,
                text: nil,
                previewText: nil,
                byteCount: nil,
                cacheToken: nil,
                errorMessage: "读取到的文本为空。"
            )
        }

        let byteCount = snapshot.byteCount ?? text.lengthOfBytes(using: .utf8)
        if byteCount <= request.inlineTextThresholdBytes {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return ClipboardReadbackResponse(
                requestID: request.requestID,
                expectedChangeCount: request.expectedChangeCount,
                outcome: .smallText,
                text: trimmed,
                previewText: Self.previewText(from: trimmed, limit: request.previewCharacterLimit),
                byteCount: byteCount,
                cacheToken: nil,
                errorMessage: nil
            )
        }

        let cacheToken = UUID().uuidString
        cachedTextByToken.insert(text: text, byteCount: byteCount, for: cacheToken)
        guard cachedTextByToken.value(for: cacheToken) != nil else {
            return ClipboardReadbackResponse(
                requestID: request.requestID,
                expectedChangeCount: request.expectedChangeCount,
                outcome: .failed,
                text: nil,
                previewText: nil,
                byteCount: nil,
                cacheToken: nil,
                errorMessage: "无法缓存一次性文本。"
            )
        }

        return ClipboardReadbackResponse(
            requestID: request.requestID,
            expectedChangeCount: request.expectedChangeCount,
            outcome: .cachedOneTime,
            text: nil,
            previewText: Self.previewText(from: text, limit: request.previewCharacterLimit),
            byteCount: byteCount,
            cacheToken: cacheToken,
            errorMessage: nil
        )
    }

    private func snapshotPlainText() -> PasteboardTextSnapshot {
        performOnMainThread {
            let pasteboard = NSPasteboard.general

            for type in orderedPlainTextTypes(from: pasteboard) {
                if let textData = pasteboard.data(forType: type),
                   let text = decodePlainText(textData) {
                    return PasteboardTextSnapshot(
                        changeCount: pasteboard.changeCount,
                        text: text,
                        byteCount: textData.count,
                        oversizedRichTextByteCount: nil
                    )
                }

                if let text = pasteboard.string(forType: type),
                   !text.isEmpty {
                    return PasteboardTextSnapshot(
                        changeCount: pasteboard.changeCount,
                        text: text,
                        byteCount: text.lengthOfBytes(using: .utf8),
                        oversizedRichTextByteCount: nil
                    )
                }
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
                    return PasteboardTextSnapshot(
                        changeCount: pasteboard.changeCount,
                        text: nil,
                        byteCount: nil,
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
                if containsMeaningfulText(text) {
                    return PasteboardTextSnapshot(
                        changeCount: pasteboard.changeCount,
                        text: text,
                        byteCount: text.lengthOfBytes(using: .utf8),
                        oversizedRichTextByteCount: nil
                    )
                }
            }

            return PasteboardTextSnapshot(
                changeCount: pasteboard.changeCount,
                text: nil,
                byteCount: nil,
                oversizedRichTextByteCount: nil
            )
        }
    }

    private func orderedPlainTextTypes(from pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var ordered: [NSPasteboard.PasteboardType] = []
        var seen = Set<String>()

        func append(_ type: NSPasteboard.PasteboardType) {
            guard seen.insert(type.rawValue).inserted else { return }
            ordered.append(type)
        }

        Self.explicitPlainTextTypes.forEach(append)

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
        if Self.richTextTypes.contains(type) {
            return false
        }

        if Self.explicitPlainTextTypes.contains(type) {
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

    private func decodePlainText(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .unicode
        ]

        for encoding in encodings {
            if let text = String(data: data, encoding: encoding),
               !text.isEmpty {
                return text
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

    private static func previewText(from text: String, limit: Int) -> String {
        var start = text.startIndex
        while start < text.endIndex, text[start].isWhitespace {
            start = text.index(after: start)
        }

        guard start < text.endIndex else { return "空文本" }

        let previewLimit = max(24, limit - 1)
        let end = text.index(start, offsetBy: previewLimit, limitedBy: text.endIndex) ?? text.endIndex
        let preview = String(text[start..<end])
        guard end < text.endIndex else { return preview }
        return preview + "…"
    }

    private func writeTextToPasteboard(_ text: String, to pasteboard: NSPasteboard) -> Bool {
        guard !text.isEmpty else {
            return false
        }

        pasteboard.clearContents()
        if pasteboard.setString(text, forType: .string) {
            return true
        }

        pasteboard.clearContents()
        if pasteboard.writeObjects([text as NSString]) {
            return true
        }

        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(text.utf8), forType: NSPasteboard.PasteboardType("public.text"))
        item.setData(Data(text.utf8), forType: NSPasteboard.PasteboardType("public.plain-text"))
        item.setData(Data(text.utf8), forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
        if let utf16Data = text.data(using: .utf16LittleEndian) {
            item.setData(
                utf16Data,
                forType: NSPasteboard.PasteboardType("public.utf16-external-plain-text")
            )
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    private func restoreSettleDelay(forByteCount byteCount: Int) -> TimeInterval {
        switch byteCount {
        case (96 * 1_024 * 1_024)...:
            return 0.38
        case (48 * 1_024 * 1_024)...:
            return 0.26
        case (16 * 1_024 * 1_024)...:
            return 0.18
        default:
            return 0.10
        }
    }

    private func getPasteboardChangeCount() -> Int {
        performOnMainThread {
            NSPasteboard.general.changeCount
        }
    }

    private func performOnMainThread<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }

        return DispatchQueue.main.sync(execute: work)
    }

    private func makePreviewExportResponse(for request: PreviewExportRequest) throws -> PreviewExportResponse {
        var isStale = false
        let sourceURL: URL
        let stopAccess: (() -> Void)?

        if let bookmarkData = request.securityScopedBookmarkData,
           let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
           ) {
            sourceURL = resolvedURL
            let startedAccess = resolvedURL.startAccessingSecurityScopedResource()
            if startedAccess {
                stopAccess = { resolvedURL.stopAccessingSecurityScopedResource() }
            } else {
                stopAccess = nil
            }
        } else {
            sourceURL = URL(fileURLWithPath: request.sourcePath)
            stopAccess = nil
        }

        defer { stopAccess?() }

        let root = previewRoot(for: request.fingerprint)
        let stagedURL = root.appendingPathComponent("staged-\(sourceURL.lastPathComponent)")
        let outputDirectory = root.appendingPathComponent("out", isDirectory: true)
        let previewDirectory = outputDirectory.appendingPathComponent("\(sourceURL.lastPathComponent).qlpreview", isDirectory: true)
        let previewHTMLURL = previewDirectory.appendingPathComponent("Preview.html")
        let previewURLURL = previewDirectory.appendingPathComponent("Preview.url")

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try stageFileIfNeeded(sourceURL: sourceURL, stagedURL: stagedURL)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: previewHTMLURL.path) && !fileManager.fileExists(atPath: previewURLURL.path) {
            try runQLManage(inputURL: stagedURL, outputDirectory: outputDirectory)
        }

        guard fileManager.fileExists(atPath: previewDirectory.path) else {
            throw NSError(domain: "EdgeClipPreviewExport", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "系统没有生成可用的预览目录。"
            ])
        }
        return PreviewExportResponse(
            requestID: request.requestID,
            previewDirectoryPath: previewDirectory.path,
            errorMessage: nil
        )
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

    private func runQLManage(inputURL: URL, outputDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", "-o", outputDirectory.path, inputURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(domain: "EdgeClipPreviewExport", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "qlmanage 导出失败，状态码 \(process.terminationStatus)。"
            ])
        }
    }
}
