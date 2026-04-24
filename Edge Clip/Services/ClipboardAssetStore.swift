import AppKit
import Foundation

@MainActor
final class ClipboardAssetStore {
    private static let maximumPixelCount: Int64 = 24_000_000
    private static let maximumPNGByteCount = 25 * 1_024 * 1_024

    struct ProtectedFileSnapshot {
        let relativePaths: [String]
        let totalByteCount: Int
    }

    private let fileManager: FileManager
    private let assetsDirectoryURL: URL

    init(
        rootDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        assetsDirectoryURL = rootDirectoryURL.appendingPathComponent("assets", isDirectory: true)
        self.fileManager = fileManager
    }

    func saveImage(_ image: NSImage, id: UUID) throws -> ClipboardItem.ImagePayload {
        try ensureAssetsDirectory()

        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            throw AssetStoreError.failedToEncodeImage
        }

        let pixelCount = Int64(bitmap.pixelsWide) * Int64(bitmap.pixelsHigh)
        guard pixelCount <= Self.maximumPixelCount else {
            throw AssetStoreError.imageTooLarge
        }

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw AssetStoreError.failedToEncodeImage
        }
        guard pngData.count <= Self.maximumPNGByteCount else {
            throw AssetStoreError.imageTooLarge
        }

        let relativePath = "\(id.uuidString).png"
        let fileURL = url(for: relativePath)
        try pngData.write(to: fileURL, options: .atomic)

        return ClipboardItem.ImagePayload(
            assetRelativePath: relativePath,
            pixelWidth: bitmap.pixelsWide,
            pixelHeight: bitmap.pixelsHigh,
            byteSize: pngData.count
        )
    }

    func saveText(_ text: String, id: UUID) throws -> String {
        try ensureAssetsDirectory()

        let relativePath = "text-\(id.uuidString).txt"
        let fileURL = url(for: relativePath)
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return relativePath
    }

    func saveProtectedFiles(_ urls: [URL], id: UUID) throws -> ProtectedFileSnapshot {
        try ensureAssetsDirectory()

        let rootRelativePath = "file-\(id.uuidString)"
        let rootURL = url(for: rootRelativePath)
        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        var relativePaths: [String] = []
        var totalByteCount = 0

        for (index, sourceURL) in urls.enumerated() {
            let destinationURL = uniqueDestinationURL(
                in: rootURL,
                preferredName: sanitizedFilename(for: sourceURL, fallbackIndex: index)
            )
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            relativePaths.append("\(rootRelativePath)/\(destinationURL.lastPathComponent)")
            totalByteCount += estimatedByteCount(of: destinationURL)
        }

        return ProtectedFileSnapshot(
            relativePaths: relativePaths,
            totalByteCount: totalByteCount
        )
    }

    func loadText(at relativePath: String) -> String? {
        guard !relativePath.isEmpty else { return nil }
        return try? String(contentsOf: url(for: relativePath), encoding: .utf8)
    }

    func removeAsset(at relativePath: String) {
        guard !relativePath.isEmpty else { return }
        let fileURL = url(for: relativePath)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }

        try? fileManager.removeItem(at: fileURL)
    }

    func url(for relativePath: String) -> URL {
        assetsDirectoryURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    func assetExists(at relativePath: String) -> Bool {
        fileManager.fileExists(atPath: url(for: relativePath).path)
    }

    func cleanupOrphanedAssets(using items: [ClipboardItem]) {
        try? ensureAssetsDirectory()

        let retainedTopLevelPaths = topLevelAssetRelativePaths(
            from: items.compactMap(\.imageAssetRelativePath) +
            items.compactMap(\.textAssetRelativePath) +
            items.flatMap(\.fileProtectedAssetRelativePaths)
        )

        guard let topLevelItems = try? fileManager.contentsOfDirectory(
            at: assetsDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for fileURL in topLevelItems {
            if !retainedTopLevelPaths.contains(fileURL.lastPathComponent) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    func topLevelAssetRelativePaths(from relativePaths: [String]) -> Set<String> {
        Set(
            relativePaths.compactMap { relativePath in
                let normalized = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !normalized.isEmpty else { return nil }
                return normalized.split(separator: "/", maxSplits: 1).first.map(String.init) ?? normalized
            }
        )
    }

    private func ensureAssetsDirectory() throws {
        try fileManager.createDirectory(at: assetsDirectoryURL, withIntermediateDirectories: true)
    }

    private func sanitizedFilename(for url: URL, fallbackIndex: Int) -> String {
        let rawName = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rawName.isEmpty {
            return rawName
        }
        return "favorite-\(fallbackIndex)"
    }

    private func uniqueDestinationURL(in directory: URL, preferredName: String) -> URL {
        let baseName = (preferredName as NSString).deletingPathExtension
        let ext = (preferredName as NSString).pathExtension

        var candidateURL = directory.appendingPathComponent(preferredName)
        var suffix = 1
        while fileManager.fileExists(atPath: candidateURL.path) {
            let nextName: String
            if ext.isEmpty {
                nextName = "\(baseName)-\(suffix)"
            } else {
                nextName = "\(baseName)-\(suffix).\(ext)"
            }
            candidateURL = directory.appendingPathComponent(nextName)
            suffix += 1
        }
        return candidateURL
    }

    private func estimatedByteCount(of url: URL) -> Int {
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]

        if let values = try? url.resourceValues(forKeys: resourceKeys),
           values.isDirectory == true {
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys)
            ) else {
                return 0
            }

            var total = 0
            for case let childURL as URL in enumerator {
                if let childValues = try? childURL.resourceValues(forKeys: resourceKeys),
                   childValues.isDirectory != true {
                    total += childValues.totalFileAllocatedSize ?? childValues.fileAllocatedSize ?? childValues.fileSize ?? 0
                }
            }
            return total
        }

        if let values = try? url.resourceValues(forKeys: resourceKeys) {
            return values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
        }

        if let attributes = try? fileManager.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber {
            return size.intValue
        }

        return 0
    }

    enum AssetStoreError: LocalizedError {
        case failedToEncodeImage
        case imageTooLarge

        var errorDescription: String? {
            switch self {
            case .failedToEncodeImage:
                return "图片资源保存失败"
            case .imageTooLarge:
                return "图片过大，已跳过采集"
            }
        }
    }
}
