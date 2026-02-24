import Foundation
import CoreGraphics

/// Enforces minimum hold durations for camera scenes.
///
/// - Zoomed-in scenes (zoom > `zoomInThreshold`) must hold for at least `minZoomInHold`.
/// - Zoomed-out scenes (zoom <= `zoomInThreshold`) must hold for at least `minZoomOutHold`.
/// - When a scene is too short, its end time is extended and subsequent scenes shift forward.
/// - Transitions are rebuilt to reference the updated scene boundaries.
struct HoldEnforcer {

    static func enforce(
        _ path: SimulatedPath,
        settings: HoldSettings
    ) -> SimulatedPath {
        guard !path.sceneSegments.isEmpty else { return path }

        let ordered = path.sceneSegments.sorted {
            $0.scene.startTime < $1.scene.startTime
        }

        // Phase 1: Compute cumulative time shifts from extensions
        var cumulativeShift: TimeInterval = 0
        var shifts: [TimeInterval] = []
        var extensions: [TimeInterval] = []

        for segment in ordered {
            shifts.append(cumulativeShift)
            let duration = segment.scene.endTime - segment.scene.startTime
            let minHold = minHoldDuration(
                zoom: segment.shotPlan.idealZoom, settings: settings
            )
            let deficit = max(0, minHold - duration)
            extensions.append(deficit)
            cumulativeShift += deficit
        }

        // Phase 2: Rebuild scene segments with shifted times
        var newScenes: [SimulatedSceneSegment] = []
        for (i, segment) in ordered.enumerated() {
            let newStart = segment.scene.startTime + shifts[i]
            let newEnd = segment.scene.endTime + shifts[i] + extensions[i]

            let newScene = CameraScene(
                id: segment.scene.id,
                startTime: newStart,
                endTime: newEnd,
                primaryIntent: segment.scene.primaryIntent,
                focusRegions: segment.scene.focusRegions,
                appContext: segment.scene.appContext
            )

            let newSamples = rescaleSamples(
                segment.samples,
                originalStart: segment.scene.startTime,
                originalEnd: segment.scene.endTime,
                newStart: newStart,
                newEnd: newEnd
            )

            var newShotPlan = ShotPlan(
                scene: newScene,
                shotType: segment.shotPlan.shotType,
                idealZoom: segment.shotPlan.idealZoom,
                idealCenter: segment.shotPlan.idealCenter,
                zoomSource: segment.shotPlan.zoomSource
            )
            newShotPlan.inherited = segment.shotPlan.inherited

            newScenes.append(SimulatedSceneSegment(
                scene: newScene,
                shotPlan: newShotPlan,
                samples: newSamples
            ))
        }

        // Phase 3: Rebuild transitions matching by UUID
        let newTransitions = rebuildTransitions(
            original: path.transitionSegments,
            newScenes: newScenes
        )

        return SimulatedPath(
            sceneSegments: newScenes,
            transitionSegments: newTransitions
        )
    }

    // MARK: - Private

    private static func minHoldDuration(
        zoom: CGFloat,
        settings: HoldSettings
    ) -> TimeInterval {
        zoom > settings.zoomInThreshold
            ? settings.minZoomInHold
            : settings.minZoomOutHold
    }

    private static func rescaleSamples(
        _ samples: [TimedTransform],
        originalStart: TimeInterval,
        originalEnd: TimeInterval,
        newStart: TimeInterval,
        newEnd: TimeInterval
    ) -> [TimedTransform] {
        guard !samples.isEmpty else { return samples }
        let originalDuration = originalEnd - originalStart
        guard originalDuration > 0 else {
            return [TimedTransform(
                time: newStart, transform: samples[0].transform
            )]
        }
        let newDuration = newEnd - newStart
        return samples.map { sample in
            let fraction = (sample.time - originalStart) / originalDuration
            let newTime = newStart + fraction * newDuration
            return TimedTransform(time: newTime, transform: sample.transform)
        }
    }

    private static func rebuildTransitions(
        original: [SimulatedTransitionSegment],
        newScenes: [SimulatedSceneSegment]
    ) -> [SimulatedTransitionSegment] {
        original.compactMap { trans in
            guard let fromScene = newScenes.first(where: {
                $0.scene.id == trans.fromScene.id
            }),
            let toScene = newScenes.first(where: {
                $0.scene.id == trans.toScene.id
            }) else { return nil }

            let plan = trans.transitionPlan
            let newPlan = TransitionPlan(
                fromScene: fromScene.scene,
                toScene: toScene.scene,
                style: plan.style,
                easing: plan.easing
            )

            return SimulatedTransitionSegment(
                fromScene: fromScene.scene,
                toScene: toScene.scene,
                transitionPlan: newPlan,
                startTransform: trans.startTransform,
                endTransform: trans.endTransform
            )
        }
    }
}
