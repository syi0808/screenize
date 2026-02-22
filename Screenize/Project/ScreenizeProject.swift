import Foundation
import CoreGraphics

/// Screenize project file
/// Contains recorded media and timeline editing data
struct ScreenizeProject: Codable, Identifiable {
    let id: UUID
    var version: Int = 5
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

    // v4: polyrecorder interop block (nil for v2 projects)
    var interop: InteropBlock?

    init(
        id: UUID = UUID(),
        name: String,
        media: MediaAsset,
        captureMeta: CaptureMeta,
        timeline: Timeline = Timeline(),
        renderSettings: RenderSettings = RenderSettings(),
        frameAnalysisCache: [VideoFrameAnalyzer.FrameAnalysis]? = nil,
        interop: InteropBlock? = nil
    ) {
        self.id = id
        self.version = 5
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.media = media
        self.captureMeta = captureMeta
        self.timeline = timeline
        self.renderSettings = renderSettings
        self.frameAnalysisCache = frameAnalysisCache
        self.frameAnalysisVersion = 1
        self.interop = interop
    }

    // MARK: - File Operations

    /// Encode the project to JSON data
    func encodeToJSON() throws -> Data {
        var project = self
        project.modifiedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(project)
    }

    /// Decode a project from JSON data
    static func decodeFromJSON(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: data)
    }

    // MARK: - Constants

    /// Package extension for .screenize packages
    static let packageExtension = "screenize"

    // MARK: - Computed Properties

    /// Total duration
    var duration: TimeInterval {
        media.duration
    }

    /// Total frame count
    var totalFrames: Int {
        Int(media.duration * media.frameRate)
    }

    /// Window capture uses window mode rendering (padding, corner radius, shadow, inset)
    var isWindowMode: Bool {
        captureMeta.displayID == nil
    }
}
