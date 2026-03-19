# English Localization Foundation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce an English-first localization foundation so user-facing strings are no longer hard-coded and future locale expansion can be added incrementally.

**Architecture:** Add a small localization helper for shared user-facing strings and dynamic error messages, back it with a `Localizable.strings` resource, and migrate the highest-traffic UI entry points first. Keep logging strings unchanged so localization only affects user-visible copy.

**Tech Stack:** Swift, SwiftUI, XCTest, Xcode project resources, Foundation localization APIs

---

## Chunk 1: Foundation

### Task 1: Add a regression-tested localization helper

**Files:**
- Create: `Screenize/App/L10n.swift`
- Create: `ScreenizeTests/App/L10nTests.swift`

- [ ] **Step 1: Write the failing tests**
- [ ] **Step 2: Run the tests to verify helper APIs are missing**
- [ ] **Step 3: Implement the minimal helper for shared keys and formatted error messages**
- [ ] **Step 4: Run the tests to verify they pass**

### Task 2: Add the English localization resource

**Files:**
- Create: `Screenize/en.lproj/Localizable.strings`
- Modify: `Screenize.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the English strings file with keys used by the helper and migrated views**
- [ ] **Step 2: Register the strings file in the app resources build phase**

## Chunk 2: Core UI Migration

### Task 3: Migrate app shell and entry views

**Files:**
- Modify: `Screenize/ScreenizeApp.swift`
- Modify: `Screenize/Views/ContentView.swift`
- Modify: `Screenize/Views/MainWelcomeView.swift`
- Modify: `Screenize/Views/Onboarding/PermissionSetupWizardView.swift`
- Modify: `Screenize/ViewModels/PermissionWizardViewModel.swift`

- [ ] **Step 1: Replace hard-coded user-visible strings with localization keys or helper calls**
- [ ] **Step 2: Keep log/debug strings unchanged**
- [ ] **Step 3: Add missing English resource entries**

### Task 4: Migrate recording and keyboard-shortcut surfaces

**Files:**
- Modify: `Screenize/Views/Recording/CaptureToolbarPanel.swift`
- Modify: `Screenize/Views/KeyboardShortcutHelpView.swift`

- [ ] **Step 1: Localize toolbar labels, menu items, and shortcut UI copy**
- [ ] **Step 2: Add missing English resource entries**

## Chunk 3: Verification

### Task 5: Verify targeted tests and app health

**Files:**
- No code changes required

- [ ] **Step 1: Run `xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/L10nTests test`**
- [ ] **Step 2: Run `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`**
- [ ] **Step 3: Run `./scripts/lint.sh`**
- [ ] **Step 4: Record the completed work with `/log-work`**
