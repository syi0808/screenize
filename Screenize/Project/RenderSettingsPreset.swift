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
