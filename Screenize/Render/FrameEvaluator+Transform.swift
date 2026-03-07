import Foundation
import CoreGraphics

// MARK: - Transform Evaluation

extension FrameEvaluator {

    /// Evaluate the transform track
    func evaluateTransform(at time: TimeInterval) -> TransformState {
        // Prefer continuous transforms (physics simulation path) when available
        if let samples = timeline.continuousTransforms, !samples.isEmpty {
            return evaluateContinuousTransform(at: time, samples: samples)
        }

        guard let track = timeline.cameraTrack, track.isEnabled else {
            return .identity
        }

        guard let segment = track.activeSegment(at: time) else {
            return .identity
        }

        let duration = max(0.001, segment.endTime - segment.startTime)
        let rawProgress = CGFloat((time - segment.startTime) / duration)
        let progress = segment.interpolation.apply(rawProgress, duration: CGFloat(duration))
        let derivative = segment.interpolation.derivative(rawProgress, duration: CGFloat(duration))
        let interpolatedValue: TransformValue

        if isWindowMode {
            interpolatedValue = segment.startTransform.interpolatedForWindowMode(to: segment.endTransform, amount: progress)
        } else {
            interpolatedValue = segment.startTransform.interpolated(to: segment.endTransform, amount: progress)
        }

        let finalCenter = interpolatedValue.center

        // Clamp the center to the zoom-specific valid range (screen mode only)
        // Window mode allows the window to move freely, so skip clamping
        let clampedCenter = isWindowMode ? finalCenter : clampCenterForZoom(center: finalCenter, zoom: interpolatedValue.zoom)

        return TransformState(
            zoom: interpolatedValue.zoom,
            center: clampedCenter,
            zoomVelocity: abs(derivative * (segment.endTransform.zoom - segment.startTransform.zoom) / CGFloat(duration)),
            panVelocity: abs(derivative) * hypot(
                segment.endTransform.center.x - segment.startTransform.center.x,
                segment.endTransform.center.y - segment.startTransform.center.y
            ) / CGFloat(duration),
            panDirection: atan2(
                segment.endTransform.center.y - segment.startTransform.center.y,
                segment.endTransform.center.x - segment.startTransform.center.x
            )
        )
    }

    /// Clamp the center so the crop area stays within the image bounds
    func clampCenterForZoom(center: NormalizedPoint, zoom: CGFloat) -> NormalizedPoint {
        guard zoom > 1.0 else { return center }

        let halfCropRatio = 0.5 / zoom
        return NormalizedPoint(
            x: clamp(center.x, min: halfCropRatio, max: 1.0 - halfCropRatio),
            y: clamp(center.y, min: halfCropRatio, max: 1.0 - halfCropRatio)
        )
    }

    // MARK: - Continuous Transform Evaluation

    /// Evaluate camera transform from pre-computed continuous samples via binary search + interpolation.
    func evaluateContinuousTransform(
        at time: TimeInterval,
        samples: [TimedTransform]
    ) -> TransformState {
        // Edge cases: before first or after last sample
        if time <= samples[0].time {
            return transformStateFromSample(samples[0], velocitySample: samples.count > 1 ? samples[1] : nil)
        }
        let last = samples.count - 1
        if time >= samples[last].time {
            return transformStateFromSample(samples[last], velocitySample: samples.count > 1 ? samples[last - 1] : nil)
        }

        // Binary search: find largest index where samples[index].time <= time
        var lo = 0
        var hi = last
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if samples[mid].time <= time {
                lo = mid
            } else {
                hi = mid
            }
        }

        let s0 = samples[lo]
        let s1 = samples[hi]
        let dt = s1.time - s0.time
        let t = dt > 0 ? CGFloat((time - s0.time) / dt) : 0

        // Linearly interpolate transform
        let zoom = s0.transform.zoom + (s1.transform.zoom - s0.transform.zoom) * t
        let cx = s0.transform.center.x + (s1.transform.center.x - s0.transform.center.x) * t
        let cy = s0.transform.center.y + (s1.transform.center.y - s0.transform.center.y) * t

        let center = isWindowMode
            ? NormalizedPoint(x: cx, y: cy)
            : clampCenterForZoom(center: NormalizedPoint(x: cx, y: cy), zoom: zoom)

        // Compute velocity from finite differences
        let zoomVelocity = dt > 0
            ? abs(s1.transform.zoom - s0.transform.zoom) / CGFloat(dt)
            : 0
        let dx = s1.transform.center.x - s0.transform.center.x
        let dy = s1.transform.center.y - s0.transform.center.y
        let panVelocity = dt > 0 ? hypot(dx, dy) / CGFloat(dt) : 0
        let panDirection = atan2(dy, dx)

        return TransformState(
            zoom: zoom,
            center: center,
            zoomVelocity: zoomVelocity,
            panVelocity: panVelocity,
            panDirection: panDirection
        )
    }

    /// Create a TransformState from a single sample with optional velocity from a neighbor.
    func transformStateFromSample(
        _ sample: TimedTransform,
        velocitySample neighbor: TimedTransform?
    ) -> TransformState {
        let center = isWindowMode
            ? sample.transform.center
            : clampCenterForZoom(center: sample.transform.center, zoom: sample.transform.zoom)

        guard let neighbor else {
            return TransformState(zoom: sample.transform.zoom, center: center)
        }

        let dt = abs(neighbor.time - sample.time)
        guard dt > 0 else {
            return TransformState(zoom: sample.transform.zoom, center: center)
        }

        let dx = neighbor.transform.center.x - sample.transform.center.x
        let dy = neighbor.transform.center.y - sample.transform.center.y

        return TransformState(
            zoom: sample.transform.zoom,
            center: center,
            zoomVelocity: abs(neighbor.transform.zoom - sample.transform.zoom) / CGFloat(dt),
            panVelocity: hypot(dx, dy) / CGFloat(dt),
            panDirection: atan2(dy, dx)
        )
    }
}
