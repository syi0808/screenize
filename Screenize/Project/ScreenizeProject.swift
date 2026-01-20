import Foundation
import CoreGraphics

/// Screenize project file
/// Contains recorded media and timeline editing data
struct ScreenizeProject: Codable, Identifiable {
    let id: UUID
    var version: Int = 1
    var name: String
    var createdAt: Date
    var modifiedAt: Date

    // Media reference
    var media: MediaAsset
    var captureMeta: CaptureMeta

    // Timeline
    var timeline: Timeline

    // Rendering settings
    var renderSettings: RenderSettings

    // Frame analysis cache (for Smart Zoom)
    var frameAnalysisCache: [VideoFrameAnalyzer.FrameAnalysis]?
    var frameAnalysisVersion: Int = 1  // Algorithm version (re-run analysis when it changes)

    init(
        id: UUID = UUID(),
        name: String,
        media: MediaAsset,
        captureMeta: CaptureMeta,
        timeline: Timeline = Timeline(),
        renderSettings: RenderSettings = RenderSettings(),
        frameAnalysisCache: [VideoFrameAnalyzer.FrameAnalysis]? = nil
    ) {
        self.id = id
        self.version = 1
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.media = media
        self.captureMeta = captureMeta
        self.timeline = timeline
        self.renderSettings = renderSettings
        self.frameAnalysisCache = frameAnalysisCache
        self.frameAnalysisVersion = 1
    }

    // MARK: - File Operations

    /// Save the project to a file
    func save(to url: URL) throws {
        var project = self
        project.modifiedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: url)
    }

    /// Load the project from a file
    static func load(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data)
    }

    // MARK: - Computed Properties

    /// Project file extension
    static let fileExtension = "fsproj"

    /// Total duration
    var duration: TimeInterval {
        media.duration
    }

    /// Total frame count
    var totalFrames: Int {
        Int(media.duration * media.frameRate)
    }

    /// backgroundEnabled triggers window mode rendering (applies to both window and display capture)
    var isWindowMode: Bool {
        renderSettings.backgroundEnabled
    }
}
