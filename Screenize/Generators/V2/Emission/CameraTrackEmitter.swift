import Foundation
import CoreGraphics

/// Converts a SimulatedPath into a CameraTrack with CameraSegments.
///
/// Uses a two-pass approach to handle contiguous scenes (zero gap between scenes):
/// - Pass 1: Compute how much time to carve from each scene for transitions.
/// - Pass 2: Emit trimmed scene segments and properly-timed transition segments.
struct CameraTrackEmitter {

    // MARK: - Private Types

    private struct SceneTrimInfo {
        var leftTrim: TimeInterval = 0
        var rightTrim: TimeInterval = 0
    }

    private struct TransitionTiming {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let midTime: TimeInterval? // for zoomOutAndIn
    }

    // MARK: - Public API

    /// Emit a CameraTrack from a simulated path.
    static func emit(_ path: SimulatedPath, duration: TimeInterval) -> CameraTrack {
        guard !path.sceneSegments.isEmpty else {
            return CameraTrack(name: "Camera (Smart V2)", segments: [])
        }

        let orderedScenes = path.sceneSegments.sorted {
            $0.scene.startTime < $1.scene.startTime
        }

        // Pass 1: Compute trims for each scene based on adjacent transitions
        var trims = [SceneTrimInfo](repeating: SceneTrimInfo(), count: orderedScenes.count)
        var transitionInfos: [(
            segment: SimulatedTransitionSegment, fromIndex: Int, toIndex: Int
        )] = []

        for transSeg in path.transitionSegments {
            guard let fromIdx = findSceneIndex(
                for: transSeg.fromScene, in: orderedScenes
            ), let toIdx = findSceneIndex(
                for: transSeg.toScene, in: orderedScenes
            ) else { continue }

            let totalDur = transitionDuration(transSeg.transitionPlan.style)
            let halfDur = totalDur / 2

            let fromDuration = orderedScenes[fromIdx].scene.endTime
                - orderedScenes[fromIdx].scene.startTime
            let toDuration = orderedScenes[toIdx].scene.endTime
                - orderedScenes[toIdx].scene.startTime

            // Cap at 30% of each scene's duration to prevent consuming short scenes
            trims[fromIdx].rightTrim += min(halfDur, fromDuration * 0.3)
            trims[toIdx].leftTrim += min(halfDur, toDuration * 0.3)

            transitionInfos.append((
                segment: transSeg, fromIndex: fromIdx, toIndex: toIdx
            ))
        }

        // Validate: ensure each scene retains positive duration after trimming
        for i in 0..<trims.count {
            let sceneDur = orderedScenes[i].scene.endTime
                - orderedScenes[i].scene.startTime
            let totalTrim = trims[i].leftTrim + trims[i].rightTrim
            if totalTrim >= sceneDur {
                let scale = sceneDur * 0.8 / totalTrim
                trims[i].leftTrim *= scale
                trims[i].rightTrim *= scale
            }
        }

        // Pass 2: Emit all segments with adjusted timing
        var allSegments: [CameraSegment] = []

        // Emit trimmed scene segments
        for (i, sceneSeg) in orderedScenes.enumerated() {
            let effectiveStart = sceneSeg.scene.startTime + trims[i].leftTrim
            let effectiveEnd = sceneSeg.scene.endTime - trims[i].rightTrim
            guard effectiveStart < effectiveEnd else { continue }

            allSegments.append(contentsOf: emitTrimmedSceneSegment(
                sceneSeg, effectiveStart: effectiveStart, effectiveEnd: effectiveEnd
            ))
        }

        // Emit transition segments with computed timing
        for info in transitionInfos {
            let transStart = orderedScenes[info.fromIndex].scene.endTime
                - trims[info.fromIndex].rightTrim
            let transEnd = orderedScenes[info.toIndex].scene.startTime
                + trims[info.toIndex].leftTrim

            var midTime: TimeInterval?
            if case let .zoomOutAndIn(outDur, inDur) =
                info.segment.transitionPlan.style {
                let actualDur = transEnd - transStart
                midTime = transStart + actualDur * (outDur / (outDur + inDur))
            }

            let timing = TransitionTiming(
                startTime: transStart, endTime: transEnd, midTime: midTime
            )
            allSegments.append(contentsOf: emitTimedTransitionSegment(
                info.segment, timing: timing
            ))
        }

        allSegments.sort { $0.startTime < $1.startTime }
        return CameraTrack(name: "Camera (Smart V2)", segments: allSegments)
    }

    // MARK: - Scene Index Lookup

    private static func findSceneIndex(
        for scene: CameraScene,
        in orderedScenes: [SimulatedSceneSegment]
    ) -> Int? {
        orderedScenes.firstIndex {
            abs($0.scene.startTime - scene.startTime) < 0.001
            && abs($0.scene.endTime - scene.endTime) < 0.001
        }
    }

    // MARK: - Transition Duration

    private static func transitionDuration(
        _ style: TransitionStyle
    ) -> TimeInterval {
        switch style {
        case let .directPan(duration):
            return duration
        case let .zoomOutAndIn(outDuration, inDuration):
            return outDuration + inDuration
        case .cut:
            return 0.01
        }
    }

    // MARK: - Trimmed Scene Emission

    private static func emitTrimmedSceneSegment(
        _ sceneSeg: SimulatedSceneSegment,
        effectiveStart: TimeInterval,
        effectiveEnd: TimeInterval
    ) -> [CameraSegment] {
        let samples = sceneSeg.samples
        guard !samples.isEmpty else { return [] }

        if samples.count == 1 {
            return [makeSegment(
                start: effectiveStart, end: effectiveEnd,
                startTransform: samples[0].transform,
                endTransform: samples[0].transform,
                easing: .linear
            )]
        }

        let first = samples.first!
        let last = samples.last!

        // Static hold: same transforms → single segment with adjusted times
        if samples.count == 2 && first.transform == last.transform {
            return [makeSegment(
                start: effectiveStart, end: effectiveEnd,
                startTransform: first.transform, endTransform: last.transform,
                easing: .linear
            )]
        }

        // Multi-sample: filter to effective range with boundary interpolation
        let filtered = filterSamples(
            samples, start: effectiveStart, end: effectiveEnd
        )
        guard filtered.count >= 2 else {
            return [makeSegment(
                start: effectiveStart, end: effectiveEnd,
                startTransform: first.transform, endTransform: last.transform,
                easing: .easeInOut
            )]
        }

        let subCount = filtered.count - 1
        var segments: [CameraSegment] = []
        for i in 0..<subCount {
            let easing: EasingCurve
            if subCount == 1 {
                easing = .easeInOut
            } else if i == 0 {
                easing = .easeOut
            } else if i == subCount - 1 {
                easing = .easeIn
            } else {
                easing = .linear
            }
            segments.append(makeSegment(
                start: filtered[i].time,
                end: filtered[i + 1].time,
                startTransform: filtered[i].transform,
                endTransform: filtered[i + 1].transform,
                easing: easing
            ))
        }
        return segments
    }

    /// Filter samples to effective time range, adding interpolated boundary samples.
    private static func filterSamples(
        _ samples: [TimedTransform],
        start: TimeInterval,
        end: TimeInterval
    ) -> [TimedTransform] {
        guard samples.count >= 2 else { return samples }

        var result: [TimedTransform] = []

        if let s = interpolatedSample(at: start, in: samples) {
            result.append(s)
        }
        for sample in samples where sample.time > start && sample.time < end {
            result.append(sample)
        }
        if let s = interpolatedSample(at: end, in: samples) {
            result.append(s)
        }

        return result
    }

    /// Linearly interpolate a transform at a given time within sorted samples.
    private static func interpolatedSample(
        at time: TimeInterval,
        in samples: [TimedTransform]
    ) -> TimedTransform? {
        guard let first = samples.first, let last = samples.last else {
            return nil
        }
        if time <= first.time {
            return TimedTransform(time: time, transform: first.transform)
        }
        if time >= last.time {
            return TimedTransform(time: time, transform: last.transform)
        }
        for i in 0..<(samples.count - 1) {
            if samples[i].time <= time && time <= samples[i + 1].time {
                let span = samples[i + 1].time - samples[i].time
                guard span > 0 else {
                    return TimedTransform(
                        time: time, transform: samples[i].transform
                    )
                }
                let t = (time - samples[i].time) / span
                let zoom = samples[i].transform.zoom
                    + (samples[i + 1].transform.zoom
                       - samples[i].transform.zoom) * t
                let cx = samples[i].transform.center.x
                    + (samples[i + 1].transform.center.x
                       - samples[i].transform.center.x) * t
                let cy = samples[i].transform.center.y
                    + (samples[i + 1].transform.center.y
                       - samples[i].transform.center.y) * t
                return TimedTransform(
                    time: time,
                    transform: TransformValue(
                        zoom: zoom,
                        center: NormalizedPoint(x: cx, y: cy)
                    )
                )
            }
        }
        return nil
    }

    // MARK: - Timed Transition Emission

    private static func emitTimedTransitionSegment(
        _ transSeg: SimulatedTransitionSegment,
        timing: TransitionTiming
    ) -> [CameraSegment] {
        let plan = transSeg.transitionPlan

        switch plan.style {
        case .directPan:
            return [makeSegment(
                start: timing.startTime, end: timing.endTime,
                startTransform: transSeg.startTransform,
                endTransform: transSeg.endTransform,
                easing: plan.easing
            )]

        case .zoomOutAndIn:
            let midTime = timing.midTime
                ?? (timing.startTime + timing.endTime) / 2

            let midCenter = NormalizedPoint(
                x: (transSeg.startTransform.center.x
                    + transSeg.endTransform.center.x) / 2,
                y: (transSeg.startTransform.center.y
                    + transSeg.endTransform.center.y) / 2
            )
            let midTransform = TransformValue(zoom: 1.0, center: midCenter)

            let zoomOut = makeSegment(
                start: timing.startTime, end: midTime,
                startTransform: transSeg.startTransform,
                endTransform: midTransform,
                easing: plan.zoomOutEasing
            )
            let zoomIn = makeSegment(
                start: midTime, end: timing.endTime,
                startTransform: midTransform,
                endTransform: transSeg.endTransform,
                easing: plan.zoomInEasing
            )
            return [zoomOut, zoomIn]

        case .cut:
            return [makeSegment(
                start: timing.startTime, end: timing.endTime,
                startTransform: transSeg.startTransform,
                endTransform: transSeg.endTransform,
                easing: .linear
            )]
        }
    }

    // MARK: - Helpers

    private static func makeSegment(
        start: TimeInterval,
        end: TimeInterval,
        startTransform: TransformValue,
        endTransform: TransformValue,
        easing: EasingCurve
    ) -> CameraSegment {
        let clampedStart = TransformValue(
            zoom: startTransform.zoom,
            center: clampCenter(startTransform.center, zoom: startTransform.zoom)
        )
        let clampedEnd = TransformValue(
            zoom: endTransform.zoom,
            center: clampCenter(endTransform.center, zoom: endTransform.zoom)
        )

        return CameraSegment(
            startTime: start,
            endTime: max(start + 0.001, end),
            startTransform: clampedStart,
            endTransform: clampedEnd,
            interpolation: easing
        )
    }

    /// Clamp center so viewport stays in [0, 1].
    private static func clampCenter(
        _ center: NormalizedPoint, zoom: CGFloat
    ) -> NormalizedPoint {
        guard zoom > 1.0 else { return center }
        let halfCrop = 0.5 / zoom
        let x = max(halfCrop, min(1.0 - halfCrop, center.x))
        let y = max(halfCrop, min(1.0 - halfCrop, center.y))
        return NormalizedPoint(x: x, y: y)
    }
}
