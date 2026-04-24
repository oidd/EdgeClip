import Foundation

@MainActor
final class FavoriteSnippetPersistence {
    let rootDirectoryURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private let saveQueue = DispatchQueue(label: "com.ivean.edgeclip.favorite-snippets-save", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.15
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        rootDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.fileManager = fileManager
        fileURL = rootDirectoryURL.appendingPathComponent("favorite-snippets.json", isDirectory: false)
    }

    func load() -> [FavoriteSnippet] {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode([FavoriteSnippet].self, from: data)
            return decoded.filter(\.isMeaningful)
        } catch {
            return []
        }
    }

    func save(_ snippets: [FavoriteSnippet]) {
        scheduleBackgroundSave(snippets.filter(\.isMeaningful))
    }

    func saveImmediately(_ snippets: [FavoriteSnippet]) throws {
        let meaningfulSnippets = snippets.filter(\.isMeaningful)
        cancelPendingSave()
        try writeSnippetsSynchronously(meaningfulSnippets)
    }

    func cancelPendingSave() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
    }

    private func scheduleBackgroundSave(_ snippets: [FavoriteSnippet]) {
        cancelPendingSave()

        let fileURL = self.fileURL
        let fileManager = self.fileManager
        let directory = fileURL.deletingLastPathComponent()
        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [snippets] in
            guard let workItem, !workItem.isCancelled else { return }

            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                let data = try encoder.encode(snippets)
                guard !workItem.isCancelled else { return }
                try data.write(to: fileURL, options: .atomic)
            } catch {
                // Best effort persistence; editing should continue working even if disk write fails.
            }
        }

        guard let workItem else { return }
        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }

    private func writeSnippetsSynchronously(_ snippets: [FavoriteSnippet]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snippets)
        try data.write(to: fileURL, options: .atomic)
    }
}

@MainActor
final class FavoriteGroupPersistence {
    let rootDirectoryURL: URL
    private let fileURL: URL
    private let fileManager: FileManager
    private let saveQueue = DispatchQueue(label: "com.ivean.edgeclip.favorite-groups-save", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDebounceInterval: TimeInterval = 0.15
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        rootDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.fileManager = fileManager
        fileURL = rootDirectoryURL.appendingPathComponent("favorite-groups.json", isDirectory: false)
    }

    func load() -> [FavoriteGroup] {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try decoder.decode([FavoriteGroup].self, from: data)
            return decoded.filter(\.isMeaningful)
        } catch {
            return []
        }
    }

    func save(_ groups: [FavoriteGroup]) {
        scheduleBackgroundSave(groups.filter(\.isMeaningful))
    }

    func saveImmediately(_ groups: [FavoriteGroup]) throws {
        let meaningfulGroups = groups.filter(\.isMeaningful)
        cancelPendingSave()
        try writeGroupsSynchronously(meaningfulGroups)
    }

    func cancelPendingSave() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
    }

    private func scheduleBackgroundSave(_ groups: [FavoriteGroup]) {
        cancelPendingSave()

        let fileURL = self.fileURL
        let fileManager = self.fileManager
        let directory = fileURL.deletingLastPathComponent()
        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [groups] in
            guard let workItem, !workItem.isCancelled else { return }

            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                let data = try encoder.encode(groups)
                guard !workItem.isCancelled else { return }
                try data.write(to: fileURL, options: .atomic)
            } catch {
                // Best effort persistence; editing should continue working even if disk write fails.
            }
        }

        guard let workItem else { return }
        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }

    private func writeGroupsSynchronously(_ groups: [FavoriteGroup]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(groups)
        try data.write(to: fileURL, options: .atomic)
    }
}
