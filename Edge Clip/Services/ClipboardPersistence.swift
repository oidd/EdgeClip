import AppKit
import Foundation

@MainActor
private final class BoundedTextCache {
    private struct Entry {
        let text: String
        let byteCount: Int
    }

    private let byteLimit: Int
    private let entryLimit: Int
    private var storage: [ClipboardItem.ID: Entry] = [:]
    private var accessOrder: [ClipboardItem.ID] = []
    private var totalBytes = 0

    init(
        byteLimit: Int = 48 * 1_024 * 1_024,
        entryLimit: Int = 24
    ) {
        self.byteLimit = byteLimit
        self.entryLimit = entryLimit
    }

    func value(for key: ClipboardItem.ID) -> String? {
        guard let entry = storage[key] else { return nil }
        touch(key)
        return entry.text
    }

    func insert(_ text: String, for key: ClipboardItem.ID) {
        let entry = Entry(
            text: text,
            byteCount: text.lengthOfBytes(using: .utf8)
        )

        if let existing = storage[key] {
            totalBytes -= existing.byteCount
            accessOrder.removeAll { $0 == key }
        }

        storage[key] = entry
        accessOrder.append(key)
        totalBytes += entry.byteCount
        evictIfNeeded()
    }

    func removeValue(for key: ClipboardItem.ID) {
        guard let existing = storage.removeValue(forKey: key) else { return }
        totalBytes -= existing.byteCount
        accessOrder.removeAll { $0 == key }
    }

    func retainOnly(keys: Set<ClipboardItem.ID>) {
        for key in storage.keys where !keys.contains(key) {
            removeValue(for: key)
        }
    }

    func removeAll() {
        storage.removeAll()
        accessOrder.removeAll()
        totalBytes = 0
    }

    private func touch(_ key: ClipboardItem.ID) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func evictIfNeeded() {
        while storage.count > entryLimit || totalBytes > byteLimit {
            guard let oldestKey = accessOrder.first else { break }
            removeValue(for: oldestKey)
        }
    }
}

@MainActor
final class ClipboardPersistence {
    let rootDirectoryURL: URL
    private let fileURL: URL
    private let assetStore: ClipboardAssetStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileManager: FileManager
    private let inMemoryTextCache = BoundedTextCache()
    private let saveQueue = DispatchQueue(label: "com.ivean.edgeclip.history-save", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private var pendingSaveTaskID = UUID()
    private let saveDebounceInterval: TimeInterval = 0.15

    init(
        rootDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.fileManager = fileManager
        fileURL = rootDirectoryURL.appendingPathComponent("history.json", isDirectory: false)
        assetStore = ClipboardAssetStore(rootDirectoryURL: rootDirectoryURL, fileManager: fileManager)
    }

    func load() -> [ClipboardItem] {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode([ClipboardItem].self, from: data)
            let migratedItems = decoded.map(migrateTextStorageIfNeeded)
            let validItems = migratedItems.filter { item in
                guard !item.isSessionOnly else {
                    return false
                }
                if let relativePath = item.imageAssetRelativePath,
                   !assetStore.assetExists(at: relativePath) {
                    return false
                }

                if let relativePath = item.textAssetRelativePath,
                   !assetStore.assetExists(at: relativePath) {
                    return false
                }

                return true
            }
            assetStore.cleanupOrphanedAssets(using: validItems)
            return validItems
        } catch {
            return []
        }
    }

    func save(_ history: [ClipboardItem]) {
        let persistedHistory = history.filter { !$0.isSessionOnly }
        let retainedIDs = Set(persistedHistory.map(\.id))
        inMemoryTextCache.retainOnly(keys: retainedIDs)
        scheduleBackgroundSave(persistedHistory)
    }

    func saveImmediately(_ history: [ClipboardItem]) throws {
        let persistedHistory = history.filter { !$0.isSessionOnly }
        let retainedIDs = Set(persistedHistory.map(\.id))
        inMemoryTextCache.retainOnly(keys: retainedIDs)
        cancelPendingSave()
        try writeHistorySynchronously(persistedHistory)
    }

    func cancelPendingSave() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        pendingSaveTaskID = UUID()
    }

    func storeImageAsset(_ image: NSImage, itemID: UUID) throws -> ClipboardItem.ImagePayload {
        try assetStore.saveImage(image, id: itemID)
    }

    func storeTextPayload(_ text: String, itemID: UUID) throws -> ClipboardItem.TextPayload {
        let inlinePayload = ClipboardItem.makeTextPayload(rawText: text, assetRelativePath: nil)
        guard inlinePayload.previewTier != .full else {
            return inlinePayload
        }

        let relativePath = try assetStore.saveText(text, id: itemID)
        inMemoryTextCache.insert(text, for: itemID)
        guard assetStore.assetExists(at: relativePath) else {
            return inlinePayload
        }
        return ClipboardItem.makeTextPayload(rawText: text, assetRelativePath: relativePath)
    }

    func storeProtectedFileSnapshot(
        from urls: [URL],
        itemID: UUID
    ) throws -> ClipboardAssetStore.ProtectedFileSnapshot {
        try assetStore.saveProtectedFiles(urls, id: itemID)
    }

    func imageAssetURL(for relativePath: String) -> URL {
        assetStore.url(for: relativePath)
    }

    func protectedFileURLs(for item: ClipboardItem) -> [URL] {
        item.fileProtectedAssetRelativePaths.compactMap { relativePath in
            guard assetStore.assetExists(at: relativePath) else { return nil }
            return assetStore.url(for: relativePath)
        }
    }

    func textContent(for item: ClipboardItem) -> String? {
        guard item.kind == .text else { return nil }
        if let text = item.textContent {
            return text
        }
        if let cached = inMemoryTextCache.value(for: item.id) {
            return cached
        }
        guard let relativePath = item.textAssetRelativePath else { return nil }
        guard let loaded = assetStore.loadText(at: relativePath) else { return nil }
        inMemoryTextCache.insert(loaded, for: item.id)
        return loaded
    }

    func removeAssociatedAssets(for items: [ClipboardItem]) {
        for item in items {
            inMemoryTextCache.removeValue(for: item.id)
            if let relativePath = item.imageAssetRelativePath {
                assetStore.removeAsset(at: relativePath)
            }
            if let relativePath = item.textAssetRelativePath {
                assetStore.removeAsset(at: relativePath)
            }
            for relativePath in assetStore.topLevelAssetRelativePaths(from: item.fileProtectedAssetRelativePaths) {
                assetStore.removeAsset(at: relativePath)
            }
        }
    }

    func removeProtectedFileAssets(for item: ClipboardItem) {
        for relativePath in assetStore.topLevelAssetRelativePaths(from: item.fileProtectedAssetRelativePaths) {
            assetStore.removeAsset(at: relativePath)
        }
    }

    func cleanupOrphanedAssets(using items: [ClipboardItem]) {
        assetStore.cleanupOrphanedAssets(using: items)
    }

    private func ensureParentDirectory() throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func scheduleBackgroundSave(_ persistedHistory: [ClipboardItem]) {
        cancelPendingSave()

        let taskID = UUID()
        self.pendingSaveTaskID = taskID
        
        let fileURL = self.fileURL
        let fileManager = self.fileManager
        let directory = fileURL.deletingLastPathComponent()

        let workItem = DispatchWorkItem { [weak self, persistedHistory] in
            guard let self, self.pendingSaveTaskID == taskID else { return }

            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                let data = try encoder.encode(persistedHistory)
                
                guard self.pendingSaveTaskID == taskID else { return }
                try data.write(to: fileURL, options: .atomic)
            } catch {
                // Best effort persistence; app should continue working even if disk write fails.
            }
        }

        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }

    private func writeHistorySynchronously(_ persistedHistory: [ClipboardItem]) throws {
        try ensureParentDirectory()
        let data = try encoder.encode(persistedHistory)
        try data.write(to: fileURL, options: .atomic)
    }

    private func migrateTextStorageIfNeeded(_ item: ClipboardItem) -> ClipboardItem {
        guard item.kind == .text,
              var payload = item.textPayload,
              payload.assetRelativePath == nil,
              payload.previewTier != .full,
              let rawText = payload.rawText else {
            return item
        }

        guard let relativePath = try? assetStore.saveText(rawText, id: item.id) else {
            return item
        }

        payload.assetRelativePath = relativePath
        payload.rawText = nil

        var migrated = item
        migrated.textPayload = payload
        return migrated
    }
}
