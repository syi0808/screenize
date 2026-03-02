import Foundation
import CoreGraphics

/// Merges short or similar adjacent scene segments in a SimulatedPath.
///
/// Two-pass algorithm:
/// 1. Absorb scenes shorter than `minSegmentDuration` into the longer neighbor.
/// 2. Merge adjacent scenes with similar transforms (zoom and center within thresholds).
struct SegmentMerger {

    static func merge(
        _ path: SimulatedPath,
        settings: MergeSettings
    ) -> SimulatedPath {
        guard path.sceneSegments.count > 1 else { return path }

        var scenes = path.sceneSegments.sorted {
            $0.scene.startTime < $1.scene.startTime
        }
        var transitions = path.transitionSegments

        // Pass 1: Absorb short segments
        scenes = absorbShortSegments(
            scenes, transitions: &transitions, settings: settings
        )

        // Pass 2: Merge similar adjacent segments
        scenes = mergeSimilarSegments(
            scenes, transitions: &transitions, settings: settings
        )

        return SimulatedPath(
            sceneSegments: scenes,
            transitionSegments: transitions
        )
    }

    // MARK: - Pass 1: Absorb Short Segments

    private static func absorbShortSegments(
        _ scenes: [SimulatedSceneSegment],
        transitions: inout [SimulatedTransitionSegment],
        settings: MergeSettings
    ) -> [SimulatedSceneSegment] {
        var result = scenes
        var changed = true

        // Iterate until no more short segments need absorption
        while changed {
            changed = false
            var i = 0
            while i < result.count {
                let duration = result[i].scene.endTime
                    - result[i].scene.startTime
                guard duration < settings.minSegmentDuration else {
                    i += 1
                    continue
                }

                // Find the best neighbor to absorb into
                let absorbIndex: Int
                if i > 0 {
                    absorbIndex = i - 1 // Prefer previous
                } else if i < result.count - 1 {
                    absorbIndex = i + 1 // Fall back to next
                } else {
                    i += 1 // Only segment left, can't absorb
                    continue
                }

                let absorberID = result[absorbIndex].scene.id
                let absorbedID = result[i].scene.id

                let merged = mergeSegmentPair(
                    absorber: result[absorbIndex],
                    absorbed: result[i]
                )

                // Remove only the direct transition between the pair
                removeTransitionBetween(
                    from: absorberID, to: absorbedID,
                    transitions: &transitions
                )
                removeTransitionBetween(
                    from: absorbedID, to: absorberID,
                    transitions: &transitions
                )

                // Replace absorber with merged, remove absorbed
                result[absorbIndex] = merged
                result.remove(at: i)

                // Update remaining transitions to reference the merged scene
                updateTransitionReferences(
                    oldID: absorbedID,
                    newScene: merged,
                    in: &transitions
                )

                changed = true
                // Don't increment i — re-check at the same index
                if i > result.count {
                    i = result.count
                }
            }
        }

        return result
    }

    // MARK: - Pass 2: Merge Similar Segments

    private static func mergeSimilarSegments(
        _ scenes: [SimulatedSceneSegment],
        transitions: inout [SimulatedTransitionSegment],
        settings: MergeSettings
    ) -> [SimulatedSceneSegment] {
        guard scenes.count > 1 else { return scenes }

        var result = [scenes[0]]

        for i in 1..<scenes.count {
            let prev = result[result.count - 1]
            let current = scenes[i]

            if areSimilar(prev, current, settings: settings) {
                let merged = mergeSegmentPair(
                    absorber: prev, absorbed: current
                )
                // Remove transition between them
                removeTransitionBetween(
                    from: prev.scene.id, to: current.scene.id,
                    transitions: &transitions
                )
                // Update any transitions referencing the absorbed scene
                updateTransitionReferences(
                    oldID: current.scene.id,
                    newScene: merged,
                    in: &transitions
                )
                result[result.count - 1] = merged
            } else {
                result.append(current)
            }
        }

        return result
    }

    // MARK: - Similarity Check

    private static func areSimilar(
        _ a: SimulatedSceneSegment,
        _ b: SimulatedSceneSegment,
        settings: MergeSettings
    ) -> Bool {
        let zoomDiff = abs(a.shotPlan.idealZoom - b.shotPlan.idealZoom)
        let centerDiffX = abs(
            a.shotPlan.idealCenter.x - b.shotPlan.idealCenter.x
        )
        let centerDiffY = abs(
            a.shotPlan.idealCenter.y - b.shotPlan.idealCenter.y
        )
        return zoomDiff <= settings.maxZoomDiffForMerge
            && centerDiffX <= settings.maxCenterDiffForMerge
            && centerDiffY <= settings.maxCenterDiffForMerge
    }

    // MARK: - Merge Two Segments

    private static func mergeSegmentPair(
        absorber: SimulatedSceneSegment,
        absorbed: SimulatedSceneSegment
    ) -> SimulatedSceneSegment {
        let newStart = min(absorber.scene.startTime, absorbed.scene.startTime)
        let newEnd = max(absorber.scene.endTime, absorbed.scene.endTime)

        let newScene = CameraScene(
            id: absorber.scene.id,
            startTime: newStart,
            endTime: newEnd,
            primaryIntent: absorber.scene.primaryIntent,
            focusRegions: absorber.scene.focusRegions
                + absorbed.scene.focusRegions,
            appContext: absorber.scene.appContext
        )

        // Combine and sort samples, replacing scene boundary times
        var allSamples = absorber.samples + absorbed.samples
        allSamples.sort { $0.time < $1.time }

        // Ensure boundary samples exist
        if let first = allSamples.first, first.time > newStart {
            allSamples.insert(
                TimedTransform(time: newStart, transform: first.transform),
                at: 0
            )
        }
        if let last = allSamples.last, last.time < newEnd {
            allSamples.append(
                TimedTransform(time: newEnd, transform: last.transform)
            )
        }

        var newShotPlan = ShotPlan(
            scene: newScene,
            shotType: absorber.shotPlan.shotType,
            idealZoom: absorber.shotPlan.idealZoom,
            idealCenter: absorber.shotPlan.idealCenter,
            zoomSource: absorber.shotPlan.zoomSource
        )
        newShotPlan.inherited = absorber.shotPlan.inherited

        return SimulatedSceneSegment(
            scene: newScene,
            shotPlan: newShotPlan,
            samples: allSamples
        )
    }

    // MARK: - Transition Helpers

    private static func removeTransitionsInvolving(
        sceneID: UUID,
        from transitions: inout [SimulatedTransitionSegment]
    ) {
        transitions.removeAll {
            $0.fromScene.id == sceneID || $0.toScene.id == sceneID
        }
    }

    private static func removeTransitionBetween(
        from fromID: UUID,
        to toID: UUID,
        transitions: inout [SimulatedTransitionSegment]
    ) {
        transitions.removeAll {
            $0.fromScene.id == fromID && $0.toScene.id == toID
        }
    }

    private static func updateTransitionReferences(
        oldID: UUID,
        newScene: SimulatedSceneSegment,
        in transitions: inout [SimulatedTransitionSegment]
    ) {
        for i in 0..<transitions.count {
            let trans = transitions[i]
            var fromScene = trans.fromScene
            var toScene = trans.toScene
            var needsUpdate = false

            if fromScene.id == oldID {
                fromScene = newScene.scene
                needsUpdate = true
            }
            if toScene.id == oldID {
                toScene = newScene.scene
                needsUpdate = true
            }

            if needsUpdate {
                let plan = TransitionPlan(
                    fromScene: fromScene,
                    toScene: toScene,
                    style: trans.transitionPlan.style,
                    easing: trans.transitionPlan.easing
                )

                transitions[i] = SimulatedTransitionSegment(
                    fromScene: fromScene,
                    toScene: toScene,
                    transitionPlan: plan,
                    startTransform: trans.startTransform,
                    endTransform: trans.endTransform
                )
            }
        }
    }
}
