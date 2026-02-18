import Foundation
import CoreGraphics

/// Converts a SimulatedPath into a CameraTrack with CameraSegments.
struct CameraTrackEmitter {

    // MARK: - Public API

    /// Emit a CameraTrack from a simulated path.
    static func emit(_ path: SimulatedPath, duration: TimeInterval) -> CameraTrack {
        guard !path.sceneSegments.isEmpty else {
            return CameraTrack(name: "Camera (Smart V2)", segments: [])
        }

        // Build a time-sorted list of emitted items (scenes and transitions)
        var items: [(startTime: TimeInterval, segments: [CameraSegment])] = []

        // Emit scene segments
        for sceneSeg in path.sceneSegments {
            let segments = emitSceneSegment(sceneSeg)
            if let first = segments.first {
                items.append((startTime: first.startTime, segments: segments))
            }
        }

        // Emit transition segments
        for transSeg in path.transitionSegments {
            let segments = emitTransitionSegment(transSeg)
            if let first = segments.first {
                items.append((startTime: first.startTime, segments: segments))
            }
        }

        // Sort by start time and flatten
        items.sort { $0.startTime < $1.startTime }
        let allSegments = items.flatMap(\.segments)

        return CameraTrack(name: "Camera (Smart V2)", segments: allSegments)
    }

    // MARK: - Scene Segment Emission

    private static func emitSceneSegment(
        _ sceneSeg: SimulatedSceneSegment
    ) -> [CameraSegment] {
        let samples = sceneSeg.samples
        guard !samples.isEmpty else { return [] }

        if samples.count == 1 {
            let t = samples[0]
            return [makeSegment(
                start: t.time, end: t.time + 0.001,
                startTransform: t.transform, endTransform: t.transform,
                easing: .linear
            )]
        }

        // For StaticHold: start and end transforms are equal → single segment
        let first = samples.first!
        let last = samples.last!

        if samples.count == 2 && first.transform == last.transform {
            return [makeSegment(
                start: first.time, end: last.time,
                startTransform: first.transform, endTransform: last.transform,
                easing: .linear
            )]
        }

        // For future controllers with multiple samples: pair consecutive
        var segments: [CameraSegment] = []
        for i in 0..<(samples.count - 1) {
            segments.append(makeSegment(
                start: samples[i].time,
                end: samples[i + 1].time,
                startTransform: samples[i].transform,
                endTransform: samples[i + 1].transform,
                easing: .easeInOut
            ))
        }
        return segments
    }

    // MARK: - Transition Segment Emission

    private static func emitTransitionSegment(
        _ transSeg: SimulatedTransitionSegment
    ) -> [CameraSegment] {
        let plan = transSeg.transitionPlan
        let fromTime = transSeg.fromScene.endTime
        let toTime = transSeg.toScene.startTime

        switch plan.style {
        case .directPan(let panDuration):
            let start = max(fromTime, toTime - panDuration)
            let end = toTime
            return [makeSegment(
                start: start, end: end,
                startTransform: transSeg.startTransform,
                endTransform: transSeg.endTransform,
                easing: plan.easing
            )]

        case .zoomOutAndIn(let outDuration, let inDuration):
            let totalDuration = outDuration + inDuration
            let midTime: TimeInterval
            if toTime - fromTime >= totalDuration {
                midTime = fromTime + outDuration
            } else {
                midTime = (fromTime + toTime) / 2
            }

            let midCenter = NormalizedPoint(
                x: (transSeg.startTransform.center.x + transSeg.endTransform.center.x) / 2,
                y: (transSeg.startTransform.center.y + transSeg.endTransform.center.y) / 2
            )
            let midTransform = TransformValue(zoom: 1.0, center: midCenter)

            let zoomOut = makeSegment(
                start: fromTime, end: midTime,
                startTransform: transSeg.startTransform,
                endTransform: midTransform,
                easing: .easeOut
            )
            let zoomIn = makeSegment(
                start: midTime, end: toTime,
                startTransform: midTransform,
                endTransform: transSeg.endTransform,
                easing: .spring(dampingRatio: 1.0, response: 0.6)
            )
            return [zoomOut, zoomIn]

        case .cut:
            // Instant transition: very short segment
            let cutDuration = min(0.01, toTime - fromTime)
            let start = max(fromTime, toTime - cutDuration)
            return [makeSegment(
                start: start, end: toTime,
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
        // Clamp centers to valid viewport bounds
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
