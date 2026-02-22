import Foundation

/// Camera controller that holds a fixed position and zoom for the entire scene.
///
/// This is the initial controller implementation. It produces a constant transform
/// based on the shot plan's ideal zoom and center, with samples at scene start and end.
struct StaticHoldController: CameraController {

    func simulate(
        scene: CameraScene,
        shotPlan: ShotPlan,
        mouseData: MouseDataSource,
        settings: SimulationSettings
    ) -> [TimedTransform] {
        let transform = TransformValue(
            zoom: shotPlan.idealZoom,
            center: shotPlan.idealCenter
        )

        if scene.startTime >= scene.endTime {
            // Zero-length or invalid scene: return a single sample
            return [TimedTransform(time: scene.startTime, transform: transform)]
        }

        return [
            TimedTransform(time: scene.startTime, transform: transform),
            TimedTransform(time: scene.endTime, transform: transform)
        ]
    }
}
