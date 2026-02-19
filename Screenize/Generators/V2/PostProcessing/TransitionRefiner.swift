import Foundation

/// Refines transitions to ensure smooth connections between scenes.
///
/// Snaps each transition's `startTransform` and `endTransform` to the actual
/// edge transforms of the adjacent scene segments. This fixes any drift
/// introduced by earlier post-processing stages.
struct TransitionRefiner {

    static func refine(
        _ path: SimulatedPath,
        settings: TransitionRefinementSettings
    ) -> SimulatedPath {
        guard settings.enabled, !path.transitionSegments.isEmpty else {
            return path
        }

        let refinedTransitions = path.transitionSegments.map { trans in
            refineTransition(trans, scenes: path.sceneSegments)
        }

        return SimulatedPath(
            sceneSegments: path.sceneSegments,
            transitionSegments: refinedTransitions
        )
    }

    // MARK: - Private

    private static func refineTransition(
        _ trans: SimulatedTransitionSegment,
        scenes: [SimulatedSceneSegment]
    ) -> SimulatedTransitionSegment {
        let fromScene = scenes.first { $0.scene.id == trans.fromScene.id }
        let toScene = scenes.first { $0.scene.id == trans.toScene.id }

        let startTransform = fromScene?.samples.last?.transform
            ?? trans.startTransform
        let endTransform = toScene?.samples.first?.transform
            ?? trans.endTransform

        return SimulatedTransitionSegment(
            fromScene: trans.fromScene,
            toScene: trans.toScene,
            transitionPlan: trans.transitionPlan,
            startTransform: startTransform,
            endTransform: endTransform
        )
    }
}
