import Foundation

nonisolated enum AppLocale {
    static let selectionKey = "overline.appLanguage"
    static let systemLanguageSelection = "system"
    static let supportedLanguageCodes = ["ko", "ja", "en"]

    static var languageSelection: String {
        let selection = UserDefaults.standard.string(forKey: selectionKey) ?? systemLanguageSelection
        return supportedLanguageCodes.contains(selection) ? selection : systemLanguageSelection
    }

    static func setLanguageSelection(_ selection: String) {
        guard selection == systemLanguageSelection || supportedLanguageCodes.contains(selection) else { return }
        UserDefaults.standard.set(selection, forKey: selectionKey)
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        syncWidgetLanguage()
    }

    static func syncWidgetLanguage() {
        UserDefaults(suiteName: WidgetStore.group)?.set(languageSelection, forKey: WidgetLanguage.preferenceKey)
    }

    static var languageCode: String {
        let selection = languageSelection
        if supportedLanguageCodes.contains(selection) { return selection }
        let preferred = Bundle.main.preferredLocalizations.first ?? "ko"
        let code = Locale(identifier: preferred).language.languageCode?.identifier ?? "ko"
        return supportedLanguageCodes.contains(code) ? code : "ko"
    }

    static var uiLocale: Locale { Locale(identifier: languageCode) }

    static func locale(for selection: String) -> Locale {
        if supportedLanguageCodes.contains(selection) { return Locale(identifier: selection) }
        return Locale(identifier: Bundle.main.preferredLocalizations.first ?? "ko")
    }

    static func migrateLegacyLanguageSelection() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: selectionKey) == nil,
              let bundleID = Bundle.main.bundleIdentifier,
              let preferences = defaults.persistentDomain(forName: bundleID),
              let language = (preferences["AppleLanguages"] as? [String])?.first
        else { return }

        let code = Locale(identifier: language).language.languageCode?.identifier ?? language
        guard supportedLanguageCodes.contains(code) else { return }
        defaults.set(code, forKey: selectionKey)
        defaults.removeObject(forKey: "AppleLanguages")
    }

    static var regionCode: String {
        Locale.current.region?.identifier ?? (languageCode == "ja" ? "JP" : languageCode == "ko" ? "KR" : "US")
    }

    static var speechLocale: Locale {
        let identifier: String
        switch languageCode {
        case "ja": identifier = "ja-JP"
        case "en": identifier = "en-US"
        default: identifier = "ko-KR"
        }
        return Locale(identifier: identifier)
    }

    static var ocrRecognitionLanguages: [String] {
        let all = ["ko-KR", "ja-JP", "en-US"]
        return [speechLocale.identifier] + all.filter { $0 != speechLocale.identifier }
    }
}
