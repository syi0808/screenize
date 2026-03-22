import Foundation

/// Describes how the camera transitions between two adjacent segments.
enum TransitionStyle: String, Codable, Equatable {
    /// Camera stays fixed -- segments are visually continuous.
    case hold
    /// Camera pans without changing zoom level.
    case directPan
    /// Full zoom-out, pan, zoom-in transition (existing behavior).
    case fullTransition
}
