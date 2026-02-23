import Foundation

/// Visual transition style between scenes.
enum TransitionStyle {
    case directPan(duration: TimeInterval)
    /// Two-phase transition: zoom out to intermediate level, pan, zoom in.
    /// `intermediateZoom` controls how far to zoom out (1.0 = full overview, higher = less zoom-out).
    case zoomOutAndIn(
        outDuration: TimeInterval,
        inDuration: TimeInterval,
        intermediateZoom: CGFloat = 1.0
    )
    case cut
}

/// Planned transition between two adjacent scenes.
struct TransitionPlan {
    let fromScene: CameraScene
    let toScene: CameraScene
    let style: TransitionStyle
    let easing: EasingCurve
    /// Easing for zoom-out phase of zoomOutAndIn transitions.
    var zoomOutEasing: EasingCurve = .spring(dampingRatio: 1.0, response: 0.5)
    /// Easing for zoom-in phase of zoomOutAndIn transitions.
    var zoomInEasing: EasingCurve = .spring(dampingRatio: 1.0, response: 0.6)
}
