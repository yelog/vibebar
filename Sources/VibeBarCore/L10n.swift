import Foundation

// MARK: - App Language

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case zh
    case en
    case ja
    case ko

    public var id: String { rawValue }

    /// Native name displayed in the language picker (always in the language's own script).
    public var nativeName: String {
        switch self {
        case .system: return ""
        case .zh: return "中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        }
    }

    /// The actual language to use for string lookup.
    public var resolved: AppLanguage {
        self == .system ? Self.resolveSystemLanguage() : self
    }

    /// Scan `Locale.preferredLanguages` and return the first supported language, or `.en` as fallback.
    public static func resolveSystemLanguage() -> AppLanguage {
        for preferred in Locale.preferredLanguages {
            let code = Locale(identifier: preferred).language.languageCode?.identifier ?? ""
            switch code {
            case "zh": return .zh
            case "en": return .en
            case "ja": return .ja
            case "ko": return .ko
            default: continue
            }
        }
        return .en
    }
}

// MARK: - L10n Manager

@MainActor
public final class L10n: ObservableObject {
    public static let shared = L10n()

    @Published public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            resolvedLang = language.resolved
        }
    }

    @Published public private(set) var resolvedLang: AppLanguage

    private init() {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        let lang = AppLanguage(rawValue: raw) ?? .system
        self.language = lang
        self.resolvedLang = lang.resolved
    }

    /// Look up a localized string for the given key.
    public func string(_ key: L10nKey) -> String {
        L10nStrings.string(key, lang: resolvedLang)
    }

    /// Look up a localized format string and apply arguments.
    public func string(_ key: L10nKey, _ args: CVarArg...) -> String {
        let template = L10nStrings.string(key, lang: resolvedLang)
        return String(format: template, arguments: args)
    }
}
