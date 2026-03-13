import SwiftUI

/// Preset picker for render settings
struct PresetPickerView: View {

    // MARK: - Properties

    @Binding var settings: RenderSettings
    @ObservedObject var presetManager: PresetManager = .shared
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
        let chipName = isActive && isModified ? "\(preset.name) *" : preset.name

        return Button {
            presetManager.activePresetID = preset.id
            settings = preset.settings
            onChange?()
        } label: {
            Text(chipName)
                .font(.system(size: 10))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            isActive
                                ? Color.accentColor.opacity(0.3)
                                : Color(nsColor: .controlBackgroundColor)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isActive ? Color.accentColor : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private var managePresetsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Presets")
                .font(.headline)

            List {
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
                            presetManager.updatePreset(
                                preset.id, with: settings
                            )
                        },
                        onDelete: {
                            presetManager.deletePreset(preset.id)
                        }
                    )
                }
                .onMove { from, to in
                    presetManager.reorderPresets(
                        fromOffsets: from, toOffset: to
                    )
                }
            }
            .listStyle(.plain)
        }
        .padding(16)
        .frame(width: 280)
        .frame(maxHeight: 300)
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

    @State private var isEditing = false
    @State private var editingName: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Circle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 6, height: 6)

            if isEditing {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
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
                    .onTapGesture {
                        editingName = preset.name
                        isEditing = true
                    }
            }

            Spacer()

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

