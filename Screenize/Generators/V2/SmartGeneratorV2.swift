import Foundation
import CoreGraphics

/// V2 smart generation orchestrator.
/// Skeleton — implementation will be added in Step 3 of the migration.
class SmartGeneratorV2 {

    /// Generate a complete timeline from recording data.
    func generate(
        from mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample],
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        screenBounds: CGSize,
        settings: SmartGenerationSettings
    ) -> GeneratedTimeline {
        fatalError("SmartGeneratorV2 is not yet implemented. Use existing generators.")
    }
}

/// Output of the V2 smart generation pipeline.
struct GeneratedTimeline {
    let cameraTrack: CameraTrack
    let cursorTrack: CursorTrackV2
    let keystrokeTrack: KeystrokeTrackV2
}

/// Settings for the V2 smart generation pipeline.
struct SmartGenerationSettings {
    static let `default` = Self()
}
