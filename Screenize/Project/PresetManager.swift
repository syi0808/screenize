import Foundation

/// Manages render settings presets (save/load/delete)
@MainActor
final class PresetManager: ObservableObject {

    // MARK: - Singleton

    static let shared = PresetManager()

    // MARK: - Published Properties

    /// User-created presets
    @Published private(set) var userPresets: [RenderSettingsPreset] = []

    // MARK: - Initialization

    private init() {
        loadUserPresets()
    }

    // MARK: - Public Methods

    /// Save current settings as a new preset
    func savePreset(name: String, settings: RenderSettings) {
        let preset = RenderSettingsPreset(
            name: name,
            settings: settings
        )
        userPresets.append(preset)
        saveUserPresets()
    }

    /// Delete a user preset
    func deletePreset(_ id: UUID) {
        userPresets.removeAll { $0.id == id }
        saveUserPresets()
    }

    /// Rename a user preset
    func renamePreset(_ id: UUID, to newName: String) {
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else { return }
        userPresets[index].name = newName
        saveUserPresets()
    }

    // MARK: - Persistence

    private var presetsFileURL: URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("Screenize/render_presets.json")
        }
        let screenizeDir = appSupport.appendingPathComponent("Screenize")
        return screenizeDir.appendingPathComponent("render_presets.json")
    }

    private func loadUserPresets() {
        guard FileManager.default.fileExists(atPath: presetsFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: presetsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            userPresets = try decoder.decode([RenderSettingsPreset].self, from: data)
        } catch {
            Log.project.error("Failed to load presets: \(error)")
        }
    }

    private func saveUserPresets() {
        do {
            // Ensure directory exists
            let directory = presetsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(userPresets)
            try data.write(to: presetsFileURL, options: .atomic)
        } catch {
            Log.project.error("Failed to save presets: \(error)")
        }
    }
}
