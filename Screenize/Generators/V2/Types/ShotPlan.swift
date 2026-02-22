import Foundation
import CoreGraphics

/// Camera shot type for a scene.
enum ShotType {
    case closeUp(zoom: CGFloat)
    case medium(zoom: CGFloat)
    case wide
}

/// How zoom was determined for diagnostic tracking.
enum ZoomSource: Equatable {
    case element
    case activityBBox
    case singleEvent
    case intentMidpoint
}

/// Camera strategy for a single scene.
struct ShotPlan {
    let scene: CameraScene
    let shotType: ShotType
    let idealZoom: CGFloat
    let idealCenter: NormalizedPoint
    var zoomSource: ZoomSource = .intentMidpoint
    var inherited: Bool = false

    /// Create a copy that inherits center from another plan with zoom decayed toward 1.0.
    /// - Parameter decayFactor: 0 = full zoom-out to 1.0, 1 = keep neighbor zoom.
    func inheriting(from source: ShotPlan, decayFactor: CGFloat = 0.5) -> ShotPlan {
        let decayedZoom = 1.0 + (source.idealZoom - 1.0) * decayFactor
        let shotType: ShotType
        if decayedZoom > 2.0 {
            shotType = .closeUp(zoom: decayedZoom)
        } else if decayedZoom > 1.0 {
            shotType = .medium(zoom: decayedZoom)
        } else {
            shotType = .wide
        }
        var plan = ShotPlan(
            scene: scene,
            shotType: shotType,
            idealZoom: decayedZoom,
            idealCenter: source.idealCenter,
            zoomSource: source.zoomSource
        )
        plan.inherited = true
        return plan
    }
}
