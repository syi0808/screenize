# Language Selection Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted language selector that switches the app UI to any shipped localization immediately.

**Architecture:** Introduce an `AppLanguageManager` singleton that resolves the current localization bundle and drives a lightweight refresh token. Keep existing `L10n` call sites intact by routing bundle lookup through the manager, then rebuild top-level SwiftUI roots and imperative window titles when the language changes.

**Tech Stack:** SwiftUI, AppKit, Foundation, XCTest, Xcode project resources

---

## Chunk 1: TDD Foundation

### Task 1: Add failing localization-selection tests

**Files:**
- Modify: `ScreenizeTests/App/L10nTests.swift`
- Create: `ScreenizeTests/Project/GeneralSettingsViewTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests that expect:
- a supported app-language list with `system default` plus shipped locales
- explicit language selection to resolve localized strings from a non-English bundle
- general settings helper output for language options

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/GeneralSettingsViewTests test`
Expected: FAIL because the general settings view does not exist yet.

## Chunk 2: Language Infrastructure

### Task 2: Implement app language state and bundle resolution

**Files:**
- Create: `Screenize/App/AppLanguageManager.swift`
- Modify: `Screenize/App/L10n.swift`
- Modify: `Screenize/ScreenizeApp.swift`
- Modify: `Screenize/EditorEntryPoint.swift`

- [ ] **Step 1: Write minimal implementation for test expectations**

Add:
- supported language option model
- persisted selection and system-default resolution
- bundle selection for `L10n`
- a localized root wrapper that rebuilds SwiftUI trees when the selection changes

- [ ] **Step 2: Run targeted tests to verify they pass**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/L10nTests test`
Expected: PASS

## Chunk 3: Settings UI

### Task 3: Add the language picker to dedicated app settings

**Files:**
- Create: `Screenize/Views/Settings/GeneralSettingsView.swift`
- Modify: `Screenize/ScreenizeApp.swift`
- Modify: `Screenize/Views/MainWelcomeView.swift`
- Modify: `Screenize/Views/Settings/GenerationSettingsView.swift`
- Modify: `Screenize/Views/Settings/GenerationSettingsWindowController.swift`
- Modify: `Screenize/en.lproj/Localizable.strings`
- Modify: `Screenize/ko.lproj/Localizable.strings`
- Modify: `Screenize/ja.lproj/Localizable.strings`
- Modify: `Screenize/zh-Hans.lproj/Localizable.strings`
- Modify: `Screenize/fr.lproj/Localizable.strings`
- Modify: `Screenize/de.lproj/Localizable.strings`

- [ ] **Step 1: Add the general settings UI and localized labels**

Expose a compact language section with the shipped languages plus `System Default`, wire it to the macOS `Settings` scene, and add a welcome-screen entry point.

- [ ] **Step 2: Keep advanced generation settings focused on Smart Generation**

Remove the language controls from advanced generation settings and leave that window accessible only from editor-specific UI.

- [ ] **Step 3: Run settings-focused tests**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/GeneralSettingsViewTests -only-testing:ScreenizeTests/GenerationSettingsViewTests test`
Expected: PASS

## Chunk 4: Verification

### Task 4: Verify integration quality

**Files:**
- Modify if needed: touched files from previous tasks

- [ ] **Step 1: Run the focused tests**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/L10nTests -only-testing:ScreenizeTests/GeneralSettingsViewTests -only-testing:ScreenizeTests/GenerationSettingsViewTests test`
Expected: PASS

- [ ] **Step 2: Run lint**

Run: `./scripts/lint.sh`
Expected: PASS without new lint errors

- [ ] **Step 3: Run debug build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Log the completed work**

Use the `work-logger` workflow to create and index a work log in English.
