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

enum ClipboardReadbackServiceError: LocalizedError {
    case invalidResponse
    case serviceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "性能保护服务返回了无效结果。"
        case let .serviceUnavailable(message):
            return message
        }
    }
}

@objc protocol ClipboardReadbackXPCProtocol {
    func fetchClipboardText(_ requestData: Data, withReply reply: @escaping (Data?, String?) -> Void)
    func readCachedText(_ cacheToken: String, withReply reply: @escaping (String?, String?) -> Void)
    func restoreCachedText(_ cacheToken: String, withReply reply: @escaping (Bool, String?) -> Void)
    func discardCachedText(_ cacheToken: String, withReply reply: @escaping () -> Void)
    func generatePreviewExport(_ requestData: Data, withReply reply: @escaping (Data?, String?) -> Void)
}

final class ClipboardReadbackServiceClient {
    static let serviceName = "com.ivean.edgeclip.readback"

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var _connection: NSXPCConnection?
    private let connectionLock = NSLock()

    nonisolated init() {}

    private func getOrCreateConnection() -> NSXPCConnection {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        if let existing = _connection {
            return existing
        }

        let connection = NSXPCConnection(serviceName: Self.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: ClipboardReadbackXPCProtocol.self)

        connection.interruptionHandler = { [weak self] in
            self?.handleConnectionInterrupted()
        }
        connection.invalidationHandler = { [weak self] in
            self?.handleConnectionInvalidated()
        }

        connection.resume()
        _connection = connection
        return connection
    }

    private func handleConnectionInterrupted() {
        // Connection will resume automatically.
    }

    private func handleConnectionInvalidated() {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        _connection = nil
    }

    func fetchClipboardText(_ request: ClipboardReadbackRequest) async throws -> ClipboardReadbackResponse {
        let requestData = try encoder.encode(request)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let connection = getOrCreateConnection()
                let replyOnce = ReplyOnce<ClipboardReadbackResponse> { result in
                    continuation.resume(with: result)
                }

                let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                    replyOnce.resume(
                        with: .failure(
                            ClipboardReadbackServiceError.serviceUnavailable(error.localizedDescription)
                        )
                    )
                }

                guard let service = proxy as? ClipboardReadbackXPCProtocol else {
                    continuation.resume(throwing: ClipboardReadbackServiceError.invalidResponse)
                    return
                }

                service.fetchClipboardText(requestData) { [decoder] responseData, message in
                    if let message {
                        replyOnce.resume(
                            with: .failure(
                                ClipboardReadbackServiceError.serviceUnavailable(message)
                            )
                        )
                        return
                    }

                    guard let responseData else {
                        replyOnce.resume(with: .failure(ClipboardReadbackServiceError.invalidResponse))
                        return
                    }

                    do {
                        let response = try decoder.decode(ClipboardReadbackResponse.self, from: responseData)
                        replyOnce.resume(with: .success(response))
                    } catch {
                        replyOnce.resume(with: .failure(error))
                    }
                }
            }
        } onCancel: {
            // Note: with long-lived connection, we don't invalidate the connection on individual task cancellation
            // to avoid impacting other concurrent requests. However, we ensure the continuation is eventually
            // resumed by the XPC reply or an error.
        }
    }

    func restoreCachedText(cacheToken: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let connection = getOrCreateConnection()
            let replyOnce = ReplyOnce<Void> { result in
                continuation.resume(with: result)
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                replyOnce.resume(
                    with: .failure(
                        ClipboardReadbackServiceError.serviceUnavailable(error.localizedDescription)
                    )
                )
            }

            guard let service = proxy as? ClipboardReadbackXPCProtocol else {
                continuation.resume(throwing: ClipboardReadbackServiceError.invalidResponse)
                return
            }

            service.restoreCachedText(cacheToken) { restored, message in
                if restored {
                    replyOnce.resume(with: .success(()))
                } else {
                    replyOnce.resume(
                        with: .failure(
                            ClipboardReadbackServiceError.serviceUnavailable(
                                message ?? "一次性文本缓存已失效。"
                            )
                        )
                    )
                }
            }
        }
    }

    func readCachedText(cacheToken: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let connection = getOrCreateConnection()
            let replyOnce = ReplyOnce<String> { result in
                continuation.resume(with: result)
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                replyOnce.resume(
                    with: .failure(
                        ClipboardReadbackServiceError.serviceUnavailable(error.localizedDescription)
                    )
                )
            }

            guard let service = proxy as? ClipboardReadbackXPCProtocol else {
                continuation.resume(throwing: ClipboardReadbackServiceError.invalidResponse)
                return
            }

            service.readCachedText(cacheToken) { text, message in
                if let text {
                    replyOnce.resume(with: .success(text))
                } else {
                    replyOnce.resume(
                        with: .failure(
                            ClipboardReadbackServiceError.serviceUnavailable(
                                message ?? "一次性文本缓存已失效。"
                            )
                        )
                    )
                }
            }
        }
    }

    func discardCachedText(cacheToken: String) {
        let connection = getOrCreateConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in }

        guard let service = proxy as? ClipboardReadbackXPCProtocol else {
            return
        }

        service.discardCachedText(cacheToken) { }
    }

    func generatePreviewExport(_ request: PreviewExportRequest) async throws -> PreviewExportResponse {
        let requestData = try encoder.encode(request)

        return try await withCheckedThrowingContinuation { continuation in
            let connection = getOrCreateConnection()
            let replyOnce = ReplyOnce<PreviewExportResponse> { result in
                continuation.resume(with: result)
            }

            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                replyOnce.resume(
                    with: .failure(
                        ClipboardReadbackServiceError.serviceUnavailable(error.localizedDescription)
                    )
                )
            }

            guard let service = proxy as? ClipboardReadbackXPCProtocol else {
                continuation.resume(throwing: ClipboardReadbackServiceError.invalidResponse)
                return
            }

            service.generatePreviewExport(requestData) { [decoder] responseData, message in
                if let message {
                    replyOnce.resume(
                        with: .failure(
                            ClipboardReadbackServiceError.serviceUnavailable(message)
                        )
                    )
                    return
                }

                guard let responseData else {
                    replyOnce.resume(with: .failure(ClipboardReadbackServiceError.invalidResponse))
                    return
                }

                do {
                    let response = try decoder.decode(PreviewExportResponse.self, from: responseData)
                    if let errorMessage = response.errorMessage {
                        replyOnce.resume(
                            with: .failure(
                                ClipboardReadbackServiceError.serviceUnavailable(errorMessage)
                            )
                        )
                    } else {
                        replyOnce.resume(with: .success(response))
                    }
                } catch {
                    replyOnce.resume(with: .failure(error))
                }
            }
        }
    }

}

private final class ReplyOnce<Value> {
    private let lock = NSLock()
    private var isResolved = false
    private let handler: (Result<Value, Error>) -> Void

    init(handler: @escaping (Result<Value, Error>) -> Void) {
        self.handler = handler
    }

    func resume(with result: Result<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !isResolved else { return }
        isResolved = true
        handler(result)
    }
}
