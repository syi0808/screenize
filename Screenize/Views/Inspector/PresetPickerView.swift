import SwiftUI

/// Preset picker for render settings
struct PresetPickerView: View {

    // MARK: - Properties

    @Binding var settings: RenderSettings
    @ObservedObject var presetManager: PresetManager = .shared
    var onChange: (() -> Void)?

    // MARK: - State

    @State private var showSavePopover = false
    @State private var newPresetName = ""

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Preset")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                // Load preset menu
                if !presetManager.userPresets.isEmpty {
                    Menu {
                        ForEach(presetManager.userPresets) { preset in
                            Button(preset.name) {
                                settings = preset.settings
                                onChange?()
                            }
                        }
                    } label: {
                        Label("Load", systemImage: "tray.and.arrow.down")
                            .font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 70)
                }

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

            // Show user presets with delete option
            if !presetManager.userPresets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(presetManager.userPresets) { preset in
                            presetChip(preset)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private func presetChip(_ preset: RenderSettingsPreset) -> some View {
        Button {
            settings = preset.settings
            onChange?()
        } label: {
            Text(preset.name)
                .font(.system(size: 10))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) {
                presetManager.deletePreset(preset.id)
            }
        }
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
