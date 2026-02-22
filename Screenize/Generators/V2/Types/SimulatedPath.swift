import Foundation

/// Result of camera path simulation containing scene and transition segments.
struct SimulatedPath {
    let sceneSegments: [SimulatedSceneSegment]
    let transitionSegments: [SimulatedTransitionSegment]
}

/// Simulated camera path for a single scene.
struct SimulatedSceneSegment {
    let scene: CameraScene
    let shotPlan: ShotPlan
    let samples: [TimedTransform]
}

/// Simulated camera path for a transition between scenes.
struct SimulatedTransitionSegment {
    let fromScene: CameraScene
    let toScene: CameraScene
    let transitionPlan: TransitionPlan
    let startTransform: TransformValue
    let endTransform: TransformValue
}

/// Transform value at a specific time.
struct TimedTransform {
    let time: TimeInterval
    let transform: TransformValue
}
