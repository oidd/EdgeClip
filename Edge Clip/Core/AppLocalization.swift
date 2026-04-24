import Foundation

enum AppResolvedLanguage: String, Equatable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    nonisolated var localeIdentifier: String {
        rawValue
    }
}

enum AppLanguage: String, Codable, CaseIterable {
    case system
    case english
    case simplifiedChinese

    var optionTitle: String {
        switch self {
        case .system:
            return AppLocalization.localized("跟随系统")
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    func resolvedLanguage(preferredLanguages: [String] = Locale.preferredLanguages) -> AppResolvedLanguage {
        switch self {
        case .system:
            return Self.resolvedSystemLanguage(from: preferredLanguages)
        case .english:
            return .english
        case .simplifiedChinese:
            return .simplifiedChinese
        }
    }

    private static func resolvedSystemLanguage(from preferredLanguages: [String]) -> AppResolvedLanguage {
        for identifier in preferredLanguages {
            let normalized = identifier.lowercased()
            if normalized.hasPrefix("zh") {
                return .simplifiedChinese
            }
            if normalized.hasPrefix("en") {
                return .english
            }
        }
        return .english
    }
}

enum AppLocalization {
    nonisolated private static func englishBundle() -> Bundle? {
        guard let path = Bundle.main.path(forResource: AppResolvedLanguage.english.localeIdentifier, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    nonisolated(unsafe) private(set) static var currentLanguage: AppResolvedLanguage = .english

    nonisolated static var currentLocale: Locale {
        Locale(identifier: currentLanguage.localeIdentifier)
    }

    nonisolated static var isEnglish: Bool {
        currentLanguage == .english
    }

    static func updateCurrentLanguage(_ language: AppResolvedLanguage) {
        currentLanguage = language
    }

    nonisolated static func localized(_ key: String) -> String {
        localized(key, language: currentLanguage)
    }

    nonisolated static func localized(_ key: String, language: AppResolvedLanguage) -> String {
        switch language {
        case .simplifiedChinese:
            return key
        case .english:
            guard let englishBundle = englishBundle() else { return key }
            return englishBundle.localizedString(forKey: key, value: key, table: nil)
        }
    }
}
