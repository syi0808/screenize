# Preset UX Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve preset management UX with active preset tracking, modified indicator, and a management popover for rename/delete/reorder/overwrite.

**Architecture:** Four files changed. Data model gets `sortOrder` + backward-compatible decoder. `RenderSettings` gains `Equatable`. `PresetManager` gains `activePresetID` and new methods. `PresetPickerView` gets chip highlighting, modified indicator, and a management popover.

**Tech Stack:** SwiftUI, Codable, @MainActor singleton

**Spec:** `docs/superpowers/specs/2026-03-14-preset-ux-improvements-design.md`

---

## File Structure

| File | Role | Action |
|------|------|--------|
| `Screenize/Project/RenderSettings.swift` | Render settings model | Add `Equatable` conformance |
| `Screenize/Project/RenderSettingsPreset.swift` | Preset model | Add `sortOrder`, custom decoder |
| `Screenize/Project/PresetManager.swift` | Preset CRUD + persistence | Add `activePresetID`, `updatePreset`, `reorderPresets`, update existing methods |
| `Screenize/Views/Inspector/PresetPickerView.swift` | Preset UI | Chip highlighting, modified indicator, gear button, management popover |

---

## Task 1: Add Equatable to RenderSettings

**Files:**
- Modify: `Screenize/Project/RenderSettings.swift:8`

All stored property types (`OutputResolution`, `OutputFrameRate`, `VideoCodec`, `ExportQuality`, `ExportFormat`, `GIFSettings`, `OutputColorSpace`, `BackgroundStyle`, `MotionBlurSettings`, `CGFloat`, `Float`, `Bool`) already conform to `Equatable`. Swift can synthesize the conformance.

- [ ] **Step 1: Add Equatable conformance**

Change line 8 from:
```swift
struct RenderSettings: Codable {
```
to:
```swift
struct RenderSettings: Codable, Equatable {
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`
Expected: BUILD SUCCEEDED (synthesized Equatable works with all stored properties)

- [ ] **Step 3: Commit**

```
git add Screenize/Project/RenderSettings.swift
git commit -m "feat: add Equatable conformance to RenderSettings"
```

---

## Task 2: Add sortOrder to RenderSettingsPreset

**Files:**
- Modify: `Screenize/Project/RenderSettingsPreset.swift`

- [ ] **Step 1: Add sortOrder property and custom decoder**

Replace the entire file content with:

```swift
import Foundation

/// A named render settings preset
struct RenderSettingsPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var settings: RenderSettings
    var createdAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        settings: RenderSettings,
        createdAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }

    // MARK: - Codable (backward compatibility)

    private enum CodingKeys: String, CodingKey {
        case id, name, settings, createdAt, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        settings = try container.decode(RenderSettings.self, forKey: .settings)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```
git add Screenize/Project/RenderSettingsPreset.swift
git commit -m "feat: add sortOrder to RenderSettingsPreset with backward-compatible decoder"
```

---

## Task 3: Update PresetManager with new methods

**Files:**
- Modify: `Screenize/Project/PresetManager.swift`

- [ ] **Step 1: Add activePresetID property**

After the `userPresets` property (line 14), add:

```swift
/// Currently active preset ID (transient, not persisted)
@Published var activePresetID: UUID?
```

- [ ] **Step 2: Update savePreset to set activePresetID and assign sortOrder**

Replace the `savePreset` method with:

```swift
/// Save current settings as a new preset
func savePreset(name: String, settings: RenderSettings) {
    let nextSortOrder = (userPresets.map(\.sortOrder).max() ?? -1) + 1
    let preset = RenderSettingsPreset(
        name: name,
        settings: settings,
        sortOrder: nextSortOrder
    )
    userPresets.append(preset)
    activePresetID = preset.id
    saveUserPresets()
}
```

- [ ] **Step 3: Update deletePreset to clear activePresetID when needed**

Replace the `deletePreset` method with:

```swift
/// Delete a user preset
func deletePreset(_ id: UUID) {
    userPresets.removeAll { $0.id == id }
    if activePresetID == id {
        activePresetID = nil
    }
    saveUserPresets()
}
```

- [ ] **Step 4: Add updatePreset method**

After `renamePreset`, add:

```swift
/// Update an existing preset with new settings
func updatePreset(_ id: UUID, with settings: RenderSettings) {
    guard let index = userPresets.firstIndex(where: { $0.id == id }) else { return }
    userPresets[index].settings = settings
    saveUserPresets()
}
```

- [ ] **Step 5: Add reorderPresets method**

After `updatePreset`, add:

```swift
/// Reorder presets and recalculate sortOrder values
func reorderPresets(fromOffsets: IndexSet, toOffset: Int) {
    userPresets.move(fromOffsets: fromOffsets, toOffset: toOffset)
    reassignSortOrders()
    saveUserPresets()
}
```

- [ ] **Step 6: Add reassignSortOrders helper and update loadUserPresets**

Add the helper method in the Persistence section:

```swift
/// Reassign sequential sortOrder values to all presets
private func reassignSortOrders() {
    for index in userPresets.indices {
        userPresets[index].sortOrder = index
    }
}
```

Update `loadUserPresets` to sort by sortOrder and fix duplicates:

```swift
private func loadUserPresets() {
    guard FileManager.default.fileExists(atPath: presetsFileURL.path) else { return }

    do {
        let data = try Data(contentsOf: presetsFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        userPresets = try decoder.decode([RenderSettingsPreset].self, from: data)
        userPresets.sort { $0.sortOrder < $1.sortOrder }

        // Fix duplicate sortOrders from migrated data
        let hasDuplicates = Set(userPresets.map(\.sortOrder)).count < userPresets.count
        if hasDuplicates {
            reassignSortOrders()
            saveUserPresets()
        }
    } catch {
        Log.project.error("Failed to load presets: \(error)")
    }
}
```

- [ ] **Step 7: Build to verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```
git add Screenize/Project/PresetManager.swift
git commit -m "feat: add activePresetID, updatePreset, and reorderPresets to PresetManager"
```

---

## Task 4: Update PresetPickerView — chip highlighting and modified indicator

**Files:**
- Modify: `Screenize/Views/Inspector/PresetPickerView.swift`

This task updates the chip row. The management popover is Task 5.

- [ ] **Step 1: Add isModified computed property and showManagePopover state**

After the existing `@State` properties, add:

```swift
@State private var showManagePopover = false

private var isModified: Bool {
    guard let activeID = presetManager.activePresetID,
          let preset = presetManager.userPresets.first(where: { $0.id == activeID })
    else { return false }
    return settings != preset.settings
}
```

- [ ] **Step 2: Update body — remove Load menu, add gear button**

Replace the entire `body` computed property with:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack {
            Text("Preset")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            // Save as preset
            Button {
                newPresetName = ""
                showSavePopover = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Save Current Settings as Preset")
            .popover(isPresented: $showSavePopover) {
                savePresetPopover
            }
        }

        // Preset chips with gear button
        if !presetManager.userPresets.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presetManager.userPresets) { preset in
                        presetChip(preset)
                    }

                    // Manage button
                    Button {
                        showManagePopover = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Manage Presets")
                    .popover(isPresented: $showManagePopover) {
                        managePresetsPopover
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Update presetChip — active highlighting and modified indicator**

Replace the `presetChip` method with:

```swift
private func presetChip(_ preset: RenderSettingsPreset) -> some View {
    let isActive = presetManager.activePresetID == preset.id
    let chipName = isActive && isModified ? "\(preset.name) *" : preset.name

    return Button {
        settings = preset.settings
        presetManager.activePresetID = preset.id
        onChange?()
    } label: {
        Text(chipName)
            .font(.system(size: 10))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.3) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 1)
            )
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 4: Add placeholder managePresetsPopover**

Add a temporary placeholder so it builds:

```swift
private var managePresetsPopover: some View {
    Text("Manage Presets")
        .padding()
        .frame(width: 280)
}
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```
git add Screenize/Views/Inspector/PresetPickerView.swift
git commit -m "feat: add active preset highlighting and modified indicator to chips"
```

---

## Task 5: Implement management popover

**Files:**
- Modify: `Screenize/Views/Inspector/PresetPickerView.swift`

- [ ] **Step 1: Replace placeholder managePresetsPopover with full implementation**

Replace the placeholder `managePresetsPopover` with:

```swift
private var managePresetsPopover: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Manage Presets")
            .font(.headline)

        List {
            ForEach(presetManager.userPresets) { preset in
                PresetManagementRow(
                    preset: preset,
                    isActive: presetManager.activePresetID == preset.id,
                    isModified: presetManager.activePresetID == preset.id && isModified,
                    onRename: { newName in
                        presetManager.renamePreset(preset.id, to: newName)
                    },
                    onOverwrite: {
                        presetManager.updatePreset(preset.id, with: settings)
                    },
                    onDelete: {
                        presetManager.deletePreset(preset.id)
                    }
                )
            }
            .onMove { from, to in
                presetManager.reorderPresets(fromOffsets: from, toOffset: to)
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 300)
    }
    .padding(16)
    .frame(width: 280)
}
```

- [ ] **Step 2: Create PresetManagementRow view**

Add at the bottom of `PresetPickerView.swift`, outside the `PresetPickerView` struct:

```swift
/// A single row in the preset management popover
private struct PresetManagementRow: View {

    let preset: RenderSettingsPreset
    let isActive: Bool
    let isModified: Bool
    let onRename: (String) -> Void
    let onOverwrite: () -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editName: String = ""

    var body: some View {
        HStack(spacing: 8) {
            // Drag handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Active indicator
            Circle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 6, height: 6)

            // Name (inline editable)
            if isEditing {
                TextField("Name", text: $editName)
                    .onSubmit { commitRename() }
                .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onExitCommand {
                        isEditing = false
                    }
            } else {
                Text(preset.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editName = preset.name
                        isEditing = true
                    }
            }

            // Overwrite button (active + modified only)
            if isModified {
                Button {
                    onOverwrite()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Update preset with current settings")
            }

            // Delete button
            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Delete preset")
        }
        .padding(.vertical, 2)
    }

    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isEditing = false
    }
}
```

- [ ] **Step 3: Remove old savePreset method's logic and ensure savePreset in view still calls manager**

The existing `savePreset()` private method and `savePresetPopover` remain as-is. No changes needed here — they already call `presetManager.savePreset(name:settings:)` which now sets `activePresetID`.

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Manual verification checklist**

Run the app and verify:
1. Chips show with no preset highlighted on launch (activePresetID is transient)
2. Clicking a chip loads settings and highlights it with accent color
3. Changing a setting shows " *" on the active chip
4. Gear button appears at end of chip row, opens management popover
5. In popover: clicking a name enables inline rename, Return saves, empty reverts
6. In popover: overwrite button appears only on active+modified row
7. In popover: delete removes preset, deleting active clears highlight
8. In popover: drag reorder works (or fallback needed)
9. Empty state: no chips, no gear button, only Preset label + save button
10. In popover: clicking a row does NOT load the preset (management only, loading via chips)
11. ExportView preset picker shares same active/modified state

- [ ] **Step 6: Commit**

```
git add Screenize/Views/Inspector/PresetPickerView.swift
git commit -m "feat: add preset management popover with rename, delete, reorder, and overwrite"
```
