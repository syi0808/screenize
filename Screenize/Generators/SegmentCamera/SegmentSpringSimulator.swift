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

    /// Maps cursor speed (normalized units/sec) to a response factor.
    /// Slow (< 0.3): 1.0, Medium (0.3–0.8): linear 1.0→0.5, Fast (> 0.8): 0.5
    private static func speedFactor(for speed: CGFloat) -> CGFloat {
        let slowThreshold: CGFloat = 0.3
        let fastThreshold: CGFloat = 0.8
        let minFactor: CGFloat = 0.5
        if speed <= slowThreshold { return 1.0 }
        if speed >= fastThreshold { return minFactor }
        let t = (speed - slowThreshold) / (fastThreshold - slowThreshold)
        return 1.0 - t * (1.0 - minFactor)
    }

    /// Simulate spring physics across all segments and return segments with
    /// populated `continuousTransforms`.
    static func simulate(
        segments: [CameraSegment],
        config: Config = Config(),
        cursorSpeeds: [UUID: CGFloat] = [:]
    ) -> [CameraSegment] {
        guard !segments.isEmpty else { return [] }

        let dt = 1.0 / config.tickRate
        let cgDt = CGFloat(dt)

        // Initialize state from first segment's startTransform
        let initial: TransformValue
        switch segments[0].kind {
        case .manual(let start, _):
            initial = start
        case .continuous(let transforms):
            initial = transforms.first?.transform ?? TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        }
        var state = CameraState(
            positionX: initial.center.x,
            positionY: initial.center.y,
            zoom: initial.zoom
        )

        let posDamping = config.positionDampingRatio
        let zoomDamping = config.zoomDampingRatio

        var result: [CameraSegment] = []

        for segment in segments {
            let target: TransformValue
            switch segment.kind {
            case .manual(_, let end):
                target = end
            case .continuous(let transforms):
                target = transforms.last?.transform ?? TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))
            }
            let targetCenter = ShotPlanner.clampCenter(target.center, zoom: target.zoom)
            let targetZoom = target.zoom

            // Reset velocity for hold segments (startTransform ≈ endTransform)
            // to prevent spring overshoot causing jitter after transitions
            let isHoldSegment: Bool = {
                if case .manual(let start, let end) = segment.kind {
                    let dx = abs(start.center.x - end.center.x)
                    let dy = abs(start.center.y - end.center.y)
                    let dz = abs(start.zoom - end.zoom)
                    return dx < 0.001 && dy < 0.001 && dz < 0.001
                }
                return false
            }()
            if isHoldSegment {
                let dampenFactor: CGFloat = 0.3
                state.velocityX *= dampenFactor
                state.velocityY *= dampenFactor
                state.velocityZoom *= dampenFactor
            }

            // Scale spring response to segment duration so the camera movement
            // fills the available time. The spring should use ~70% of the segment
            // to reach the target, leaving natural settling for the rest.
            let segmentDuration = CGFloat(segment.endTime - segment.startTime)
            let factor = speedFactor(for: cursorSpeeds[segment.id] ?? 0)
            let minResponse: CGFloat = 0.15
            let adaptedPosResponse = max(minResponse, max(config.positionResponse, segmentDuration * 0.4) * factor)
            let adaptedZoomResponse = max(minResponse, max(config.zoomResponse, segmentDuration * 0.45) * factor)
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
            updated.kind = .continuous(transforms: samples)
            result.append(updated)
        }

        return result
    }
}
