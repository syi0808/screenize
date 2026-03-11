import Foundation
import CoreGraphics

/// Runs spring physics simulation across camera segments, populating
/// each segment's `continuousTransforms` with pre-computed samples.
///
/// The spring target is each segment's `endTransform`. When a new segment
/// starts, the target changes but velocity carries over for seamless transitions.
struct SegmentSpringSimulator {

    struct Config {
        var positionDampingRatio: CGFloat = 0.90
        var positionResponse: CGFloat = 0.35
        var zoomDampingRatio: CGFloat = 0.90
        var zoomResponse: CGFloat = 0.55
        var tickRate: Double = 60.0
        var minZoom: CGFloat = 1.0
        var maxZoom: CGFloat = 2.8
    }

    /// Simulate spring physics across all segments and return segments with
    /// populated `continuousTransforms`.
    static func simulate(
        segments: [CameraSegment],
        config: Config = Config()
    ) -> [CameraSegment] {
        guard !segments.isEmpty else { return [] }

        let dt = 1.0 / config.tickRate
        let cgDt = CGFloat(dt)

        // Initialize state from first segment's startTransform
        let initial = segments[0].startTransform
        var state = CameraState(
            positionX: initial.center.x,
            positionY: initial.center.y,
            zoom: initial.zoom
        )

        let posDamping = config.positionDampingRatio
        let zoomDamping = config.zoomDampingRatio

        var result: [CameraSegment] = []

        for segment in segments {
            let target = segment.endTransform
            let targetCenter = ShotPlanner.clampCenter(target.center, zoom: target.zoom)
            let targetZoom = target.zoom

            // Scale spring response to segment duration so the camera movement
            // fills the available time. The spring should use ~70% of the segment
            // to reach the target, leaving natural settling for the rest.
            let segmentDuration = CGFloat(segment.endTime - segment.startTime)
            let adaptedPosResponse = max(config.positionResponse, segmentDuration * 0.4)
            let adaptedZoomResponse = max(config.zoomResponse, segmentDuration * 0.45)
            let posOmega = 2.0 * .pi / max(0.001, adaptedPosResponse)
            let zoomOmega = 2.0 * .pi / max(0.001, adaptedZoomResponse)

            var samples: [TimedTransform] = []
            let tickCount = max(1, Int((segment.endTime - segment.startTime) * config.tickRate))
            samples.reserveCapacity(tickCount + 1)

            // Record initial state for this segment
            samples.append(TimedTransform(
                time: segment.startTime,
                transform: TransformValue(
                    zoom: state.zoom,
                    center: NormalizedPoint(x: state.positionX, y: state.positionY)
                )
            ))

            var t = segment.startTime + dt
            while t <= segment.endTime + dt * 0.5 {
                let (newX, newVX) = SpringDamperSimulator.springStep(
                    current: state.positionX, velocity: state.velocityX,
                    target: targetCenter.x,
                    omega: posOmega, zeta: posDamping, dt: cgDt
                )
                let (newY, newVY) = SpringDamperSimulator.springStep(
                    current: state.positionY, velocity: state.velocityY,
                    target: targetCenter.y,
                    omega: posOmega, zeta: posDamping, dt: cgDt
                )
                let (newZ, newVZ) = SpringDamperSimulator.springStep(
                    current: state.zoom, velocity: state.velocityZoom,
                    target: targetZoom,
                    omega: zoomOmega, zeta: zoomDamping, dt: cgDt
                )

                state.positionX = newX
                state.positionY = newY
                state.zoom = min(config.maxZoom, max(config.minZoom, newZ))
                state.velocityX = newVX
                state.velocityY = newVY
                state.velocityZoom = newVZ

                // Clamp center to valid bounds
                let clamped = ShotPlanner.clampCenter(
                    NormalizedPoint(x: state.positionX, y: state.positionY),
                    zoom: state.zoom
                )
                state.positionX = clamped.x
                state.positionY = clamped.y

                let sampleTime = min(t, segment.endTime)
                samples.append(TimedTransform(
                    time: sampleTime,
                    transform: TransformValue(
                        zoom: state.zoom,
                        center: NormalizedPoint(x: state.positionX, y: state.positionY)
                    )
                ))

                t += dt
            }

            var updated = segment
            updated.continuousTransforms = samples
            result.append(updated)
        }

        return result
    }
}
