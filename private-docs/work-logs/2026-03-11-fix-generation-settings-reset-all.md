---
date: 2026-03-11
time: 21:17
type: bugfix
tags: [generation-settings, smart-generation, settings-ui, reset, bugfix]
files_changed:
  - Screenize/Views/Settings/GenerationSettingsView.swift
  - ScreenizeTests/Project/GenerationSettingsViewTests.swift
  - Screenize.xcodeproj/project.pbxproj
summary: Fixed Advanced Generation Settings Reset All so it respects the active scope and resets project overrides when editing This Project.
---

# Fix Advanced Generation Settings Reset All Scope Handling

## Summary
Fixed the Advanced Generation Settings `Reset All` action so it now follows the currently selected scope. In `App Defaults`, it resets the app-wide settings to `GenerationSettings.default`. In `This Project`, it resets the project override to `GenerationSettings.default` and posts the existing project-change notification so the editor state updates immediately.

## Details
- Investigated `GenerationSettingsView` and confirmed the root cause: individual controls were bound through `editingSettings`, but the top-level `Reset All` button bypassed that path and always called `manager.resetSettings()`.
- Added `GenerationSettingsResetNotification` plus a small `resetAllState(...)` helper to make the scope-based mutation explicit and unit-testable.
- Updated the `Reset All` button to call the new helper. Project-scope resets now update `projectSettings` and emit `.projectGenerationSettingsChanged`; app-scope resets still update `manager.settings`, which continues to auto-save through the existing `onChange`.
- Added `GenerationSettingsViewTests` covering both scope paths:
  - App defaults reset should not touch project settings
  - Project reset should not touch app defaults and should request project notification

## Challenges & Solutions
- The original button action lived inside a SwiftUI view and was not directly testable. I solved that by extracting the state transition into a small pure helper, which allowed a focused regression test without introducing UI test infrastructure.
- The repository currently had unrelated staged and unstaged changes. I kept the bugfix scoped to its own files and avoided touching unrelated work.

## Related Work
- `private-docs/work-logs/2026-03-10-add-generation-settings-window-ui.md`
- `private-docs/work-logs/2026-03-10-menu-bar-toolbar-generation-settings.md`

## Next Steps
- Preset loading currently appears app-default scoped as well. If project-scope presets are expected, that path should be reviewed with the same scope rules used for `Reset All`.
