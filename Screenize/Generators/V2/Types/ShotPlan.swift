import Foundation
import CoreGraphics

/// Camera shot type for a scene.
enum ShotType {
    case closeUp(zoom: CGFloat)
    case medium(zoom: CGFloat)
    case wide
}

/// Camera strategy for a single scene.
struct ShotPlan {
    let scene: CameraScene
    let shotType: ShotType
    let idealZoom: CGFloat
    let idealCenter: NormalizedPoint

    /// Create a copy that inherits zoom/center from another plan.
    func inheriting(from source: ShotPlan) -> ShotPlan {
        ShotPlan(
            scene: scene,
            shotType: source.shotType,
            idealZoom: source.idealZoom,
            idealCenter: source.idealCenter
        )
    }
}
