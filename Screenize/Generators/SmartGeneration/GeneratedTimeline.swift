import Foundation

/// Output of the smart generation pipeline.
struct GeneratedTimeline {
    let cameraTrack: CameraTrack
    let cursorTrack: CursorTrackV2
    let keystrokeTrack: KeystrokeTrackV2
}
