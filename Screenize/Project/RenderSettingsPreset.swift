import Foundation

/// A named render settings preset
struct RenderSettingsPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    var settings: RenderSettings
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        settings: RenderSettings,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.createdAt = createdAt
    }
}
