import Foundation

/// Manages reading and writing scenario files within a .screenize package.
enum ScenarioFileManager {
    static let scenarioFilename = "scenario.json"
    static let scenarioRawFilename = "scenario-raw.json"

    /// Save a Scenario to the package directory.
    static func save(_ scenario: Scenario, to packageURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(scenario)
        let url = packageURL.appendingPathComponent(scenarioFilename)
        try data.write(to: url, options: .atomic)
    }

    /// Save ScenarioRawEvents to the package directory.
    static func saveRaw(_ rawEvents: ScenarioRawEvents, to packageURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(rawEvents)
        let url = packageURL.appendingPathComponent(scenarioRawFilename)
        try data.write(to: url, options: .atomic)
    }

    /// Load a Scenario from the package directory. Returns nil if the file does not exist or cannot be decoded.
    static func loadScenario(from packageURL: URL) -> Scenario? {
        let url = packageURL.appendingPathComponent(scenarioFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Scenario.self, from: data)
    }

    /// Load ScenarioRawEvents from the package directory. Returns nil if the file does not exist or cannot be decoded.
    static func loadRawEvents(from packageURL: URL) -> ScenarioRawEvents? {
        let url = packageURL.appendingPathComponent(scenarioRawFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ScenarioRawEvents.self, from: data)
    }
}
