import Foundation

struct UpdateInfo: Codable, Equatable {
    let version: String
    let downloadURL: String
    let releaseNotes: String

    enum CodingKeys: String, CodingKey {
        case version
        case downloadURL = "download_url"
        case releaseNotes = "release_notes"
    }
}

@MainActor
final class UpdateCheckService {
    enum CheckResult {
        case upToDate
        case updateAvailable(UpdateInfo)
        case failed(Error)
    }

    private let url: URL
    private let session: URLSession

    init(url: URL) {
        self.url = url
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func checkForUpdates() async -> CheckResult {
        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return .failed(URLError(.badServerResponse))
            }

            let updateInfo = try JSONDecoder().decode(UpdateInfo.self, from: data)

            guard let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
                return .failed(URLError(.unknown))
            }

            if isVersion(updateInfo.version, greaterThan: currentVersion) {
                return .updateAvailable(updateInfo)
            } else {
                return .upToDate
            }
        } catch {
            return .failed(error)
        }
    }

    private func isVersion(_ remote: String, greaterThan local: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let localComponents = local.split(separator: ".").compactMap { Int($0) }

        let maxCount = max(remoteComponents.count, localComponents.count)
        for i in 0..<maxCount {
            let remoteValue = i < remoteComponents.count ? remoteComponents[i] : 0
            let localValue = i < localComponents.count ? localComponents[i] : 0
            if remoteValue > localValue { return true }
            if remoteValue < localValue { return false }
        }
        return false
    }
}
