import Foundation
import CoreGraphics

/// Camera shot type for a scene.
enum ShotType {
    case closeUp(zoom: CGFloat)
    case medium(zoom: CGFloat)
    case wide
}

/// How zoom was determined for diagnostic tracking.
enum ZoomSource {
    case element
    case activityBBox
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

    /// Create a copy that inherits zoom/center from another plan.
    func inheriting(from source: ShotPlan) -> ShotPlan {
        var plan = ShotPlan(
            scene: scene,
            shotType: source.shotType,
            idealZoom: source.idealZoom,
            idealCenter: source.idealCenter,
            zoomSource: source.zoomSource
        )
        plan.inherited = true
        return plan
    }
}
