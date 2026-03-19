# Language Selection Design

## Goal
Add an app setting that lets users choose the UI language from the shipped localization resources and apply the change immediately without restarting the app.

## Scope
- Add a persisted app-level language preference with a `System Default` option.
- Expose the preference in a dedicated general settings window that is separate from Smart Generation controls.
- Make `L10n` resolve strings from the selected localization bundle instead of always using `Bundle.main`.
- Refresh active SwiftUI roots and relevant AppKit window/menu titles immediately after the selection changes.

## Approach
Introduce an `AppLanguageManager` singleton as the source of truth for available app languages, persisted selection, resolved effective language, and the bundle used by localization lookups. `L10n` will read strings and formatted values through this manager so existing call sites continue to work with minimal code churn.

Immediate UI refresh will use two layers:
- Top-level SwiftUI roots will rebuild when the language manager publishes a refresh token.
- AppKit-owned window titles that are set imperatively will subscribe to language changes and recalculate their titles.

## UI
The app will gain a dedicated general settings window for app-wide preferences. It will show:
- `System Default`
- `English`
- `한국어`
- `日本語`
- `简体中文`
- `Français`
- `Deutsch`

Only languages with shipped `Localizable.strings` resources will appear in the list.

Entry points:
- macOS app menu `Settings...`
- a settings button on the welcome screen

The existing advanced generation settings window remains editor-specific and should not be exposed from the app menu.

## Data Model
`AppLanguageManager` will store a selected option value in `UserDefaults`. The option model will distinguish:
- a system default sentinel
- explicit app locale identifiers

The manager will also expose:
- a stable list of supported languages
- the resolved language identifier currently in use
- the localized bundle used by `L10n`
- a refresh token for SwiftUI tree invalidation

## Immediate Refresh Behavior
- Main app content will be wrapped in a localized root that rebuilds on language changes.
- Editor windows, the general settings window, and the advanced generation settings window will use the same root wrapper so already-open views update immediately.
- The advanced generation settings window title will be updated through a language-change observer.

## Testing
- Add tests for supported language discovery and persisted selection resolution.
- Add tests that verify `L10n` can resolve strings from a selected non-default localization bundle.
- Add tests for the general settings language option list and keep the existing advanced generation settings reset-behavior regression coverage.

## Risks
- Any user-facing text that bypasses `L10n` will not update automatically. The implementation should stay focused on the current `L10n` path and the settings entry point.
- AppKit window titles created imperatively need explicit refresh hooks because they do not automatically re-evaluate from SwiftUI state.
