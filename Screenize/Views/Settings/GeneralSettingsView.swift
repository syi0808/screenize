import AppKit
import SwiftUI

enum SettingsWindowOpener {
    @MainActor
    static func open() {
        let selectorName = if #available(macOS 14.0, *) {
            "showSettingsWindow:"
        } else {
            "showPreferencesWindow:"
        }

        NSApp.sendAction(Selector(selectorName), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var languageManager: AppLanguageManager

    struct LanguagePickerOption: Equatable {
        let language: AppLanguage
        let title: String
    }

    static func languagePickerOptions(supportedLanguages: [AppLanguage]) -> [LanguagePickerOption] {
        supportedLanguages.map { language in
            LanguagePickerOption(language: language, title: language.displayName)
        }
    }

    private var selectedLanguageBinding: Binding<AppLanguage> {
        Binding(
            get: { languageManager.selectedLanguage },
            set: { languageManager.selectLanguage($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                icon: "gearshape",
                title: L10n.string("general_settings.title", defaultValue: "Settings")
            )
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    SettingsSection(
                        title: L10n.string("general_settings.section.general", defaultValue: "General")
                    ) {
                        Picker(
                            L10n.string("general_settings.language", defaultValue: "Language"),
                            selection: selectedLanguageBinding
                        ) {
                            ForEach(
                                Self.languagePickerOptions(supportedLanguages: languageManager.supportedLanguages),
                                id: \.language
                            ) { option in
                                Text(option.title)
                                    .tag(option.language)
                            }
                        }
                        .pickerStyle(.menu)

                        Text(
                            L10n.string(
                                "general_settings.language.description",
                                defaultValue: "Choose the language used throughout the app."
                            )
                        )
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 220)
    }
}
