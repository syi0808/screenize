import Foundation

/// Visual transition style between scenes.
enum TransitionStyle {
    case directPan(duration: TimeInterval)
    /// Single-phase zoom out while panning to target.
    case zoomOutAndPan(duration: TimeInterval)
    /// Single-phase zoom in while panning to target.
    case zoomInAndPan(duration: TimeInterval)
    case cut
}

/// Planned transition between two adjacent scenes.
struct TransitionPlan {
    let fromScene: CameraScene
    let toScene: CameraScene
    let style: TransitionStyle
    let easing: EasingCurve
}
