import Foundation

/// Manages render settings presets (save/load/delete)
@MainActor
final class PresetManager: ObservableObject {

    // MARK: - Singleton

    static let shared = PresetManager()

    // MARK: - Published Properties

    /// User-created presets
    @Published private(set) var userPresets: [RenderSettingsPreset] = []

    /// Currently active preset ID (transient, not persisted)
    @Published var activePresetID: UUID?

    // MARK: - Initialization

    private init() {
        loadUserPresets()
    }

    // MARK: - Public Methods

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

    /// Delete a user preset
    func deletePreset(_ id: UUID) {
        userPresets.removeAll { $0.id == id }
        if activePresetID == id {
            activePresetID = nil
        }
        saveUserPresets()
    }

    /// Rename a user preset
    func renamePreset(_ id: UUID, to newName: String) {
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else { return }
        userPresets[index].name = newName
        saveUserPresets()
    }

    /// Update an existing preset with new settings
    func updatePreset(_ id: UUID, with settings: RenderSettings) {
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else { return }
        userPresets[index].settings = settings
        saveUserPresets()
    }

    /// Reorder presets and recalculate sortOrder values
    func reorderPresets(fromOffsets: IndexSet, toOffset: Int) {
        userPresets.move(fromOffsets: fromOffsets, toOffset: toOffset)
        reassignSortOrders()
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

    /// Reassign sequential sortOrder values to all presets
    private func reassignSortOrders() {
        for index in userPresets.indices {
            userPresets[index].sortOrder = index
        }
    }

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
