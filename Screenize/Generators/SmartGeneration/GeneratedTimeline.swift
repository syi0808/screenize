import Foundation
import CoreGraphics

/// Output of the smart generation pipeline.
struct GeneratedTimeline {
    let cameraTrack: CameraTrack
    let cursorTrack: CursorTrackV2
    let keystrokeTrack: KeystrokeTrackV2

    /// Cursor speeds computed during segment-based generation, for spring cache use.
    var cursorSpeeds: [UUID: CGFloat] = [:]

    /// Spring config from segment-based generation, for spring cache use.
    var springConfig: SegmentSpringSimulator.Config?
}
