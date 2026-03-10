import Foundation

// MARK: - Generation Settings Preset

/// A named snapshot of generation settings
struct GenerationSettingsPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    let settings: GenerationSettings
    let createdAt: Date

    init(id: UUID = UUID(), name: String, settings: GenerationSettings, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.settings = settings
        self.createdAt = createdAt
    }
}

// MARK: - Generation Settings Manager

/// Manages persistence of generation settings and user-created presets
@MainActor
final class GenerationSettingsManager: ObservableObject {

    // MARK: - Singleton

    static let shared = GenerationSettingsManager()

    // MARK: - Published Properties

    /// Current app-level generation settings
    @Published var settings = GenerationSettings.default

    /// User-created presets
    @Published private(set) var presets: [GenerationSettingsPreset] = []

    // MARK: - Initialization

    private init() {
        loadSettings()
        loadPresets()
    }

    // MARK: - Settings

    /// Save current settings to disk
    func saveSettings() {
        do {
            let directory = settingsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: settingsFileURL, options: .atomic)
        } catch {
            Log.project.error("Failed to save generation settings: \(error)")
        }
    }

    /// Reset settings to defaults
    func resetSettings() {
        settings = .default
        saveSettings()
    }

    /// Returns the effective settings for a given project.
    /// Uses the project's override if present, otherwise falls back to app defaults.
    func effectiveSettings(for project: ScreenizeProject?) -> GenerationSettings {
        project?.generationSettings ?? settings
    }

    // MARK: - Presets

    /// Save current settings as a new preset
    func savePreset(name: String) {
        let preset = GenerationSettingsPreset(
            name: name,
            settings: settings
        )
        presets.append(preset)
        savePresets()
    }

    /// Load a preset into current settings
    func loadPreset(_ id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        settings = preset.settings
        saveSettings()
    }

    /// Delete a preset
    func deletePreset(_ id: UUID) {
        presets.removeAll { $0.id == id }
        savePresets()
    }

    /// Rename a preset
    func renamePreset(_ id: UUID, to newName: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = newName
        savePresets()
    }

    // MARK: - Persistence

    private var settingsFileURL: URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("Screenize/generation_settings.json")
        }
        let screenizeDir = appSupport.appendingPathComponent("Screenize")
        return screenizeDir.appendingPathComponent("generation_settings.json")
    }

    private var presetsFileURL: URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("Screenize/generation_presets.json")
        }
        let screenizeDir = appSupport.appendingPathComponent("Screenize")
        return screenizeDir.appendingPathComponent("generation_presets.json")
    }

    private func loadSettings() {
        guard FileManager.default.fileExists(atPath: settingsFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: settingsFileURL)
            let decoder = JSONDecoder()
            settings = try decoder.decode(GenerationSettings.self, from: data)
        } catch {
            Log.project.error("Failed to load generation settings: \(error)")
        }
    }

    private func loadPresets() {
        guard FileManager.default.fileExists(atPath: presetsFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: presetsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            presets = try decoder.decode([GenerationSettingsPreset].self, from: data)
        } catch {
            Log.project.error("Failed to load generation presets: \(error)")
        }
    }

    private func savePresets() {
        do {
            let directory = presetsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(presets)
            try data.write(to: presetsFileURL, options: .atomic)
        } catch {
            Log.project.error("Failed to save generation presets: \(error)")
        }
    }
}
