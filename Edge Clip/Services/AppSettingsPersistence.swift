import Foundation

@MainActor
final class AppSettingsPersistence {
    private let userDefaults: UserDefaults
    private let key = "edgeclip.settings.v1"
    private let legacyBlacklistMigrationKey = "edgeclip.settings.removedLegacyBlacklistDefaults.v1"
    private let sensitiveDefaultsMigrationKey = "edgeclip.settings.appliedSensitiveDefaults.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func load(defaultValue: AppSettings) -> AppSettings {
        guard let data = userDefaults.data(forKey: key) else {
            userDefaults.set(true, forKey: legacyBlacklistMigrationKey)
            userDefaults.set(true, forKey: sensitiveDefaultsMigrationKey)
            return defaultValue
        }

        guard var decoded = try? decoder.decode(AppSettings.self, from: data) else {
            return defaultValue
        }

        if !userDefaults.bool(forKey: legacyBlacklistMigrationKey) {
            userDefaults.set(true, forKey: legacyBlacklistMigrationKey)
        }

        if !userDefaults.bool(forKey: sensitiveDefaultsMigrationKey) {
            let originalBlacklist = decoded.blacklistedBundleIDs
            if decoded.blacklistedBundleIDs.isEmpty {
                decoded.blacklistedBundleIDs = AppSettings.defaultSensitiveBlacklistedBundleIDs
            }
            userDefaults.set(true, forKey: sensitiveDefaultsMigrationKey)

            if decoded.blacklistedBundleIDs != originalBlacklist,
               let migratedData = try? encoder.encode(decoded) {
                userDefaults.set(migratedData, forKey: key)
            }
        }

        return decoded
    }

    func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        userDefaults.set(data, forKey: key)
    }
}
