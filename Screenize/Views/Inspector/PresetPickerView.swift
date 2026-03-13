import SwiftUI

/// Preset picker for render settings
struct PresetPickerView: View {

    // MARK: - Properties

    @Binding var settings: RenderSettings
    @StateObject private var presetManager: PresetManager = .shared
    var onChange: (() -> Void)?

    // MARK: - State

    @State private var showSavePopover = false
    @State private var showManagePopover = false
    @State private var newPresetName = ""

    // MARK: - Computed

    private var isModified: Bool {
        guard let activeID = presetManager.activePresetID,
              let preset = presetManager.userPresets.first(where: { $0.id == activeID })
        else { return false }
        return settings != preset.settings
    }

    // MARK: - Body

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

                        Button {
                            showManagePopover = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(4)
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

    // MARK: - Subviews

    private func presetChip(_ preset: RenderSettingsPreset) -> some View {
        let isActive = presetManager.activePresetID == preset.id
        let showUpdate = isActive && isModified

        return HStack(spacing: 4) {
            Button {
                presetManager.activePresetID = preset.id
                settings = preset.settings
                onChange?()
            } label: {
                Text(preset.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            if showUpdate {
                Button {
                    presetManager.updatePreset(preset.id, with: settings)
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Update preset with current settings")
            }

            Button {
                presetManager.deletePreset(preset.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete preset")
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isActive
                        ? Color.accentColor.opacity(0.15)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isActive
                        ? Color.accentColor.opacity(0.5)
                        : Color(nsColor: .separatorColor),
                    lineWidth: 1
                )
        )
    }

    private var managePresetsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Presets")
                .font(.headline)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(presetManager.userPresets) { preset in
                        PresetManagementRow(
                            preset: preset,
                            isActive: presetManager.activePresetID == preset.id,
                            isModified: isModified
                                && presetManager.activePresetID == preset.id,
                            onRename: { newName in
                                presetManager.renamePreset(preset.id, to: newName)
                            },
                            onOverwrite: {
                                presetManager.updatePreset(preset.id, with: settings)
                            },
                            onDelete: {
                                presetManager.deletePreset(preset.id)
                            },
                            onMoveUp: presetManager.userPresets.first?.id != preset.id ? {
                                movePreset(preset.id, direction: .up)
                            } : nil,
                            onMoveDown: presetManager.userPresets.last?.id != preset.id ? {
                                movePreset(preset.id, direction: .down)
                            } : nil
                        )
                        if preset.id != presetManager.userPresets.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(16)
        .frame(width: 280)
    }

    private func movePreset(_ id: UUID, direction: MoveDirection) {
        guard let index = presetManager.userPresets.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = direction == .up ? index - 1 : index + 1
        guard newIndex >= 0, newIndex < presetManager.userPresets.count else { return }
        presetManager.reorderPresets(
            fromOffsets: IndexSet(integer: index),
            toOffset: direction == .up ? newIndex : newIndex + 1
        )
    }

    private enum MoveDirection {
        case up, down
    }

    private var savePresetPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Preset")
                .font(.headline)

            TextField("Preset Name", text: $newPresetName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    savePreset()
                }

            HStack {
                Button("Cancel") {
                    showSavePopover = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save") {
                    savePreset()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 240)
    }

    // MARK: - Actions

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        presetManager.savePreset(name: name, settings: settings)
        showSavePopover = false
    }
}

// MARK: - PresetManagementRow

private struct PresetManagementRow: View {
    let preset: RenderSettingsPreset
    let isActive: Bool
    let isModified: Bool
    let onRename: (String) -> Void
    let onOverwrite: () -> Void
    let onDelete: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    @State private var isEditing = false
    @State private var editingName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Reorder buttons
            VStack(spacing: 0) {
                Button {
                    onMoveUp?()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8))
                        .foregroundColor(onMoveUp != nil ? .secondary : .clear)
                }
                .buttonStyle(.plain)
                .disabled(onMoveUp == nil)

                Button {
                    onMoveDown?()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(onMoveDown != nil ? .secondary : .clear)
                }
                .buttonStyle(.plain)
                .disabled(onMoveDown == nil)
            }
            .frame(width: 14)

            // Active indicator
            Circle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 6, height: 6)

            // Name (inline editable)
            if isEditing {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        finishEditing()
                    }
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
                        editingName = preset.name
                        isEditing = true
                        isTextFieldFocused = true
                    }
            }

            Spacer()

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
                .help("Overwrite with Current Settings")
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
            .help("Delete Preset")
        }
        .padding(.vertical, 4)
    }

    private func finishEditing() {
        let trimmed = editingName
            .trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            onRename(trimmed)
        }
        isEditing = false
    }
}
