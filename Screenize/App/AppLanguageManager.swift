import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Equatable {
    case systemDefault = "system"
    case english = "en"
    case korean = "ko"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var localeIdentifier: String? {
        switch self {
        case .systemDefault:
            return nil
        case .english, .korean, .japanese, .simplifiedChinese, .french, .german:
            return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .systemDefault:
            return L10n.string("common.system_default", defaultValue: "System Default")
        case .english:
            return "English"
        case .korean:
            return "한국어"
        case .japanese:
            return "日本語"
        case .simplifiedChinese:
            return "简体中文"
        case .french:
            return "Français"
        case .german:
            return "Deutsch"
        }
    }

    static func from(localeIdentifier: String) -> Self? {
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-").lowercased()
        return Self.allCases.first { language in
            guard language != .systemDefault else { return false }
            let candidate = language.rawValue.lowercased()
            return normalized == candidate || normalized.hasPrefix(candidate + "-")
        }
    }
}

final class AppLanguageManager: ObservableObject {

    static let shared = AppLanguageManager()

    static let userDefaultsKey = "selectedAppLanguage"

    @Published private(set) var selectedLanguage: AppLanguage
    @Published private(set) var refreshID = UUID()

    private let userDefaults: UserDefaults
    private let bundle: Bundle

    init(
        userDefaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) {
        self.userDefaults = userDefaults
        self.bundle = bundle

        if let storedValue = userDefaults.string(forKey: Self.userDefaultsKey),
           let storedLanguage = AppLanguage(rawValue: storedValue) {
            self.selectedLanguage = storedLanguage
        } else {
            self.selectedLanguage = .systemDefault
        }
    }

    var supportedLanguages: [AppLanguage] {
        Self.supportedAppLanguages(in: bundle)
    }

    var resolvedLanguage: AppLanguage {
        Self.resolvedLanguage(
            selection: selectedLanguage,
            preferredLocalizations: Locale.preferredLanguages,
            supportedLanguages: supportedLanguages.filter { $0 != .systemDefault }
        )
    }

    var localizationBundle: Bundle {
        Self.bundle(for: resolvedLanguage, in: bundle) ?? bundle
    }

    var formattingLocale: Locale {
        guard let localeIdentifier = resolvedLanguage.localeIdentifier else {
            return .current
        }
        return Locale(identifier: localeIdentifier)
    }

    func selectLanguage(_ language: AppLanguage) {
        guard selectedLanguage != language else { return }
        selectedLanguage = language
        userDefaults.set(language.rawValue, forKey: Self.userDefaultsKey)
        refreshID = UUID()
    }

    static func supportedAppLanguages(in bundle: Bundle) -> [AppLanguage] {
        let availableLocalizations = Set(bundle.localizations)
        return AppLanguage.allCases.filter { language in
            guard let localeIdentifier = language.localeIdentifier else {
                return true
            }
            return availableLocalizations.contains(localeIdentifier)
        }
    }

    static func resolvedLanguage(
        selection: AppLanguage,
        preferredLocalizations: [String],
        supportedLanguages: [AppLanguage]
    ) -> AppLanguage {
        guard selection == .systemDefault else {
            return selection
        }

        for preferredLocalization in preferredLocalizations {
            if let matchedLanguage = AppLanguage.from(localeIdentifier: preferredLocalization),
               supportedLanguages.contains(matchedLanguage) {
                return matchedLanguage
            }
        }

        return supportedLanguages.first ?? .english
    }

    static func bundle(for language: AppLanguage, in bundle: Bundle) -> Bundle? {
        guard let localeIdentifier = language.localeIdentifier,
              let resourcePath = bundle.path(forResource: localeIdentifier, ofType: "lproj") else {
            return language == .systemDefault ? bundle : nil
        }

        return Bundle(path: resourcePath)
    }
}

struct LocalizedRootView<Content: View>: View {
    @ObservedObject private var languageManager: AppLanguageManager
    private let content: () -> Content

    init(
        languageManager: AppLanguageManager = .shared,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.languageManager = languageManager
        self.content = content
    }

    var body: some View {
        content()
            .id(languageManager.refreshID)
            .environment(\.locale, languageManager.formattingLocale)
            .environmentObject(languageManager)
    }
}
