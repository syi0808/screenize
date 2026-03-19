---
date: 2026-03-19
time: 23:48
type: feature
tags:
  - localization
  - language-selection
  - settings
  - swiftui
  - appkit
files_changed:
  - Screenize/App/AppLanguageManager.swift
  - Screenize/App/L10n.swift
  - Screenize/App/L10n+Display.swift
  - Screenize/ScreenizeApp.swift
  - Screenize/EditorEntryPoint.swift
  - Screenize/Views/MainWelcomeView.swift
  - Screenize/Views/Settings/GeneralSettingsView.swift
  - Screenize/Views/Settings/GenerationSettingsView.swift
  - Screenize/Views/Settings/GenerationSettingsWindowController.swift
  - Screenize/en.lproj/Localizable.strings
  - Screenize/ko.lproj/Localizable.strings
  - Screenize/ja.lproj/Localizable.strings
  - Screenize/zh-Hans.lproj/Localizable.strings
  - Screenize/fr.lproj/Localizable.strings
  - Screenize/de.lproj/Localizable.strings
  - ScreenizeTests/App/L10nTests.swift
  - ScreenizeTests/Project/GeneralSettingsViewTests.swift
  - ScreenizeTests/Project/GenerationSettingsViewTests.swift
  - Screenize.xcodeproj/project.pbxproj
  - docs/superpowers/specs/2026-03-19-language-selection-design.md
  - docs/superpowers/plans/2026-03-19-language-selection.md
summary: Added an in-app language selection setting in a dedicated Settings window with immediate localization refresh across SwiftUI views and AppKit-hosted windows.
---

# Add Immediate In-App Language Selection

## Summary
Implemented a language picker in a dedicated app `Settings` window so users can choose `System Default` or one of the shipped app localizations and see the UI update immediately without restarting the app.

## Details
- Added `AppLanguageManager` to own the selected language, resolve the effective localization from system preferences, persist the selection in `UserDefaults`, and provide the active localization bundle and formatting locale.
- Updated `L10n` and `L10n+Display` to resolve strings dynamically from the selected bundle instead of caching localized values from `Bundle.main`. This was necessary to avoid stale text after runtime language changes.
- Wrapped the main app window, editor windows, and the advanced generation settings window in `LocalizedRootView` so a language change forces SwiftUI to rebuild with a new `Locale` environment.
- Added a dedicated `GeneralSettingsView` and wired it through the macOS `Settings` scene so the standard app-menu `Settings...` item opens app-wide preferences.
- Added a settings button to the welcome screen so users can reach general settings before creating or opening a project.
- Used `SettingsLink` from the welcome screen only on macOS 14+, while keeping a macOS 13 fallback that opens the settings scene through `showPreferencesWindow:` to avoid availability errors and broken settings launches on older supported systems.
- Moved language selection out of advanced generation settings and exposed only `System Default` plus the bundled languages: English, Korean, Japanese, Simplified Chinese, French, and German in the general settings window.
- Updated the generation settings AppKit window controller to refresh its title when the language changes, so non-SwiftUI window chrome stays synchronized.
- Added the new settings keys to every shipped `Localizable.strings` file and registered the new Swift files in the Xcode project.
- Added tests for supported language discovery, system-language resolution, bundle-specific string lookup, and general-settings language picker ordering.

## Challenges & Solutions
- The existing localization helpers used `static let` values, which made them effectively immutable after first access. Converting localized values to computed properties removed that cache and enabled immediate UI refresh.
- Some screens are created through `NSHostingView` and `NSWindow` instead of only through the SwiftUI app scene. Those entry points had to be wrapped explicitly, and the advanced generation settings window title needed a Combine subscription to update after language changes.
- `SettingsLink` is only available on macOS 14 and newer, while the app still supports macOS 13. The welcome-screen entry point now branches by availability so newer systems use the native SwiftUI control and older systems route through the legacy AppKit selector that matches the older settings API.
- The first implementation placed language selection in advanced generation settings, but that conflicted with the product boundary that Smart Generation tuning should stay editor-specific. The final version split app-wide settings into a dedicated settings window and removed language controls from the generation panel.

## Related Work
- Builds on `private-docs/work-logs/2026-03-18-english-localization-foundation.md`, which established the localization key structure and `L10n` helper layer used by this feature.

## Next Steps
- Audit the remaining UI for hard-coded strings or direct `NSLocalizedString` usage outside `L10n`, because those paths would not automatically participate in runtime language switching.
- Consider adding a small UI test or manual QA checklist for switching languages while the settings and editor windows are already open.
