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
        Text("Manage Presets")
            .padding(16)
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

