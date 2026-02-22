import Foundation

/// Protocol for pluggable camera controllers used by CameraSimulator.
///
/// Each controller implements a different strategy for generating camera transforms
/// over the duration of a scene. The initial implementation is `StaticHoldController`
/// which holds a fixed position; future implementations (e.g. CursorFollowController)
/// will provide frame-level cursor tracking.
protocol CameraController {
    /// Simulate camera movement for a scene.
    /// Returns time-sorted transforms spanning the scene duration.
    func simulate(
        scene: CameraScene,
        shotPlan: ShotPlan,
        mouseData: MouseDataSource,
        settings: SimulationSettings
    ) -> [TimedTransform]
}
