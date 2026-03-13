# Preset UX Improvements Design Spec

**Date**: 2026-03-14
**Scope**: Improve preset list view, management UI, and active preset tracking

## Problem

Current preset UI has several usability gaps:
- No visual indication of which preset is active or if settings have been modified
- Delete and rename only accessible via right-click context menu (not discoverable)
- No way to reorder presets or update an existing preset with current settings
- Redundant Load dropdown menu (chips already serve as load buttons)

## Design Decisions

- Preset count expected to stay under 10 — no search/filter needed
- Management UI as popover (not sheet) to keep inspector context visible
- Inline rename (click name to edit) for fast workflow
- No confirmation dialogs for delete/overwrite — prioritize speed over accident prevention
- `activePresetID` is transient (not persisted) — resets on app launch, no preset highlighted until user loads one
- ExportView's PresetPickerView shares the same active/modified tracking (uses same PresetManager singleton)

## Changes

### 1. Data Model — RenderSettingsPreset

Add `sortOrder: Int` property for user-defined ordering.

```swift
struct RenderSettingsPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var settings: RenderSettings
    var createdAt: Date
    var sortOrder: Int  // NEW
}
```

**Backward compatibility**: Custom `init(from decoder:)` to default `sortOrder` to 0 when decoding existing JSON files that lack the field.

### 2. Data Model — RenderSettings Equatable

Add `Equatable` conformance to `RenderSettings` to enable modified detection. Since `RenderSettings` is a pure value type with `Codable` conformance, synthesized `Equatable` should work if all stored properties are `Equatable`. If any property is not, add manual conformance.

### 3. PresetManager Changes

```swift
@MainActor
final class PresetManager: ObservableObject {
    // Existing
    @Published private(set) var userPresets: [RenderSettingsPreset] = []

    // NEW
    @Published var activePresetID: UUID?

    // Existing
    func savePreset(name:settings:)     // Also sets activePresetID to new preset
    func deletePreset(_:)               // Clears activePresetID if deleted preset was active
    func renamePreset(_:to:)            // No change

    // NEW
    func updatePreset(_ id: UUID, with settings: RenderSettings)
    // Overwrites the settings of an existing preset with the given settings.
    // The UI should only enable the overwrite button when the preset is active and modified.
    // The method itself performs an unconditional update.

    func reorderPresets(fromOffsets: IndexSet, toOffset: Int)
    // Moves presets and recalculates sortOrder values.
    // Persists immediately.
}
```

**Sort behavior**: `userPresets` array maintained in `sortOrder` ascending order. On load, sort by `sortOrder`. If any presets share the same `sortOrder` (e.g., migrated data where all default to 0), reassign sequential values (0, 1, 2, ...) based on array position and persist immediately. On reorder, recalculate all `sortOrder` values sequentially.

### 4. Chip Row UI Changes

**Header row** (unchanged layout):
- "Preset" label + "+" save button

**Chip row**:
- Remove Load dropdown menu (redundant with chips)
- Remove right-click context menu on chips
- Active preset chip: accent color background instead of `controlBackgroundColor`
- Modified indicator: append " *" to active chip name when `isModified` is true
- Add gear icon button (`gearshape`) at the end of chip row → opens management popover

**Modified detection** (computed in view):
```swift
var isModified: Bool {
    guard let activeID = presetManager.activePresetID,
          let preset = presetManager.userPresets.first(where: { $0.id == activeID })
    else { return false }
    return settings != preset.settings
}
```

**Active preset tracking**:
- Chip click sets `activePresetID` and applies settings
- Saving a new preset sets `activePresetID` to the new preset
- Deleting active preset clears `activePresetID`
- If user manually adjusts settings to exactly match a preset, modified auto-clears (pure value comparison)

### 5. Management Popover UI

Triggered by gear button click. Width: 280pt, dynamic height with max scroll.

**Header**: "Manage Presets" title

**List**: Vertical list with each row containing:
- `line.3.horizontal` drag handle (left) — for `onMove` drag reorder
- Preset name — click to enter inline edit mode (TextField), Return or focus loss to save
- Active indicator — small checkmark or dot for active preset
- Overwrite button (`square.and.arrow.down`) — visible only on the active preset's row when modified
- Delete button (`trash`, red foreground) — always visible

**Note**: Management popover is for management only — tapping a preset row does NOT load it. Loading is done via chips in the main view.

**Interactions**:
- Drag and drop reorder via `onMove` modifier. Fallback: if `onMove` inside popover proves unreliable on macOS 13, use up/down arrow buttons per row instead.
- Inline name edit: tap name → TextField appears → edit → Return to confirm. If submitted name is empty, revert to previous name.
- Overwrite: immediately applies current settings to the preset, no confirmation
- Delete: immediately removes preset, no confirmation
- Popover dismisses when clicking outside

### 6. Files Changed

| File | Change |
|------|--------|
| `RenderSettingsPreset.swift` | Add `sortOrder`, custom decoder |
| `RenderSettings.swift` | Add `Equatable` conformance |
| `PresetManager.swift` | Add `activePresetID`, `updatePreset`, `reorderPresets`; update `savePreset`/`deletePreset` |
| `PresetPickerView.swift` | Chip highlight, modified indicator, remove Load menu, remove context menu, add gear button, add management popover |

**No changes needed**:
- `SettingsInspector.swift` — call signature unchanged
- `ExportView+Settings.swift` — call signature unchanged

### 7. Edge Cases

- **Empty state**: No chips, no gear button. Only "Preset" label + "+" save button.
- **Backward compatibility**: Existing `render_presets.json` without `sortOrder` field loads successfully with default value. Order assigned by array index on first load.
- **Active preset deleted**: `activePresetID` cleared, no chip highlighted, no modified indicator.
- **All presets deleted**: Returns to empty state.
- **Duplicate names**: Allowed (user responsibility, no validation beyond empty check).
- **Empty name on rename**: Revert to previous name, do not save.
