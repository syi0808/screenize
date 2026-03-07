import Foundation

/// Output of the smart generation pipeline.
struct GeneratedTimeline {
    let cameraTrack: CameraTrack
    let cursorTrack: CursorTrackV2
    let keystrokeTrack: KeystrokeTrackV2
    /// Pre-computed continuous camera path at 60Hz.
    var continuousTransforms: [TimedTransform]?
}
