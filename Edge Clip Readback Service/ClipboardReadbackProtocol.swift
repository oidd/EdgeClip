import Foundation

struct ClipboardReadbackRequest: Codable {
    let requestID: UUID
    let expectedChangeCount: Int
    let inlineTextThresholdBytes: Int
    let previewCharacterLimit: Int
}

struct ClipboardReadbackResponse: Codable {
    enum Outcome: String, Codable {
        case smallText
        case cachedOneTime
        case stale
        case failed
    }

    let requestID: UUID
    let expectedChangeCount: Int
    let outcome: Outcome
    let text: String?
    let previewText: String?
    let byteCount: Int?
    let cacheToken: String?
    let errorMessage: String?
}

struct PreviewExportRequest: Codable {
    let requestID: UUID
    let sourcePath: String
    let securityScopedBookmarkData: Data?
    let fingerprint: String
}

struct PreviewExportResponse: Codable {
    let requestID: UUID
    let previewDirectoryPath: String?
    let errorMessage: String?
}

@objc protocol ClipboardReadbackXPCProtocol {
    func fetchClipboardText(_ requestData: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func readCachedText(_ cacheToken: String, withReply reply: @escaping (String?, String?) -> Void)
    func restoreCachedText(_ cacheToken: String, withReply reply: @escaping (Bool, String?) -> Void)
    func discardCachedText(_ cacheToken: String, withReply reply: @escaping () -> Void)
    func generatePreviewExport(_ requestData: Data, withReply reply: @escaping (Data?, String?) -> Void)
}
