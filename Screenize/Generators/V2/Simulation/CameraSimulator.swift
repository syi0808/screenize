import Foundation
import CoreGraphics

/// Orchestrates camera simulation using pluggable controllers.
///
/// For each scene, selects a CameraController and produces time-sampled transforms.
/// Builds transition segments connecting adjacent scenes.
class CameraSimulator {

    // MARK: - Properties

    private let holdController = StaticHoldController()

    // MARK: - Public API

    /// Simulate camera path for a sequence of shot plans and transitions.
    func simulate(
        shotPlans: [ShotPlan],
        transitions: [TransitionPlan],
        mouseData: MouseDataSource,
        settings: SimulationSettings,
        duration: TimeInterval
    ) -> SimulatedPath {
        guard !shotPlans.isEmpty else {
            return SimulatedPath(sceneSegments: [], transitionSegments: [])
        }

        // Phase 1: Simulate each scene independently
        var sceneSegments: [SimulatedSceneSegment] = []
        for shotPlan in shotPlans {
            let controller = selectController(for: shotPlan)
            let samples = controller.simulate(
                scene: shotPlan.scene,
                shotPlan: shotPlan,
                mouseData: mouseData,
                settings: settings
            )
            sceneSegments.append(SimulatedSceneSegment(
                scene: shotPlan.scene,
                shotPlan: shotPlan,
                samples: samples
            ))
        }

        // Phase 2: Build transition segments between adjacent scenes
        var transitionSegments: [SimulatedTransitionSegment] = []
        for (index, transition) in transitions.enumerated() {
            guard index < sceneSegments.count - 1 else { break }

            let prevSegment = sceneSegments[index]
            let nextSegment = sceneSegments[index + 1]

            let startTransform = prevSegment.samples.last?.transform
                ?? TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))
            let endTransform = nextSegment.samples.first?.transform
                ?? TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))

            transitionSegments.append(SimulatedTransitionSegment(
                fromScene: transition.fromScene,
                toScene: transition.toScene,
                transitionPlan: transition,
                startTransform: startTransform,
                endTransform: endTransform
            ))
        }

        return SimulatedPath(
            sceneSegments: sceneSegments,
            transitionSegments: transitionSegments
        )
    }

    // MARK: - Controller Selection

    /// Select the appropriate camera controller for a shot plan.
    /// Currently always returns StaticHoldController; future versions may
    /// return CursorFollowController based on scene intent.
    private func selectController(for shotPlan: ShotPlan) -> CameraController {
        holdController
    }
}
