import Foundation

/// Visual transition style between scenes.
enum TransitionStyle {
    case directPan(duration: TimeInterval)
    case zoomOutAndIn(outDuration: TimeInterval, inDuration: TimeInterval)
    case cut
}

/// Planned transition between two adjacent scenes.
struct TransitionPlan {
    let fromScene: CameraScene
    let toScene: CameraScene
    let style: TransitionStyle
    let easing: EasingCurve
}
