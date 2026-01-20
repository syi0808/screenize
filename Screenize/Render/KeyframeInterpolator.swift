import Foundation
import CoreGraphics

/// Keyframe interpolator
/// Computes interpolated values at arbitrary times from keyframes
final class KeyframeInterpolator {

    /// Allowed tolerance for floating-point comparisons
    private let epsilon: TimeInterval = 0.0001

    init() {}

    // MARK: - Generic Interpolation

    /// Compute the interpolated value at a given time from a keyframe array
    /// - Parameters:
    ///   - keyframes: Time-sorted keyframes
    ///   - time: Time to evaluate
    ///   - getValue: Closure that extracts the value from a keyframe
    ///   - defaultValue: Value returned when there are no keyframes
    /// - Returns: Interpolated value
    func interpolate<K: TimedKeyframe, V: Interpolatable>(
        keyframes: [K],
        at time: TimeInterval,
        getValue: (K) -> V,
        defaultValue: V
    ) -> V {
        // Handle empty list
        guard !keyframes.isEmpty else {
            return defaultValue
        }

        // Single keyframe
        if keyframes.count == 1 {
            return getValue(keyframes[0])
        }

        // Boundary condition: before the first keyframe
        guard let first = keyframes.first else { return defaultValue }
        if time <= first.time + epsilon {
            return getValue(first)
        }

        // Boundary condition: after the last keyframe
        guard let last = keyframes.last else { return defaultValue }
        if time >= last.time - epsilon {
            return getValue(last)
        }

        // Use binary search to find bounding keyframes
        let (before, after) = findBoundingKeyframes(keyframes, at: time)

        // Compute progress
        let duration = after.time - before.time
        guard duration > epsilon else {
            return getValue(before)
        }

        let progress = (time - before.time) / duration

        // Apply easing (spring uses real duration for physical simulation)
        let easedProgress = before.easing.apply(CGFloat(progress), duration: CGFloat(duration))

        // Interpolate the value
        let fromValue = getValue(before)
        let toValue = getValue(after)

        return fromValue.interpolated(to: toValue, amount: easedProgress)
    }

    // MARK: - Transform Interpolation

    /// Transform keyframe interpolation
    func interpolateTransform(
        keyframes: [TransformKeyframe],
        at time: TimeInterval
    ) -> TransformValue {
        interpolate(
            keyframes: keyframes,
            at: time,
            getValue: { $0.value },
            defaultValue: .identity
        )
    }

    /// Result of a transform interpolation (includes value and velocity)
    struct TransformInterpolationResult {
        let value: TransformValue
        /// Zoom velocity derived from the easing curve derivative (per second)
        let zoomVelocity: CGFloat
        /// Pan velocity derived from the easing curve derivative (normalized per second)
        let panVelocity: CGFloat
        /// Pan direction (radians)
        let panDirection: CGFloat
    }

    /// Interpolate transform keyframes (including velocity)
    /// - Parameters:
    ///   - keyframes: Array of transform keyframes
    ///   - time: Time to evaluate
    ///   - windowMode: Whether window mode is active (true uses anchor point interpolation)
    /// - Returns: Interpolated value with easing-based velocity information
    func interpolateTransformWithVelocity(
        keyframes: [TransformKeyframe],
        at time: TimeInterval,
        windowMode: Bool = false
    ) -> TransformInterpolationResult {
        // Handle empty array
        guard !keyframes.isEmpty else {
            return TransformInterpolationResult(
                value: .identity,
                zoomVelocity: 0,
                panVelocity: 0,
                panDirection: 0
            )
        }

        // Single keyframe (velocity = 0)
        if keyframes.count == 1 {
            return TransformInterpolationResult(
                value: keyframes[0].value,
                zoomVelocity: 0,
                panVelocity: 0,
                panDirection: 0
            )
        }

        // Boundary: before the first keyframe (velocity = 0)
        guard let first = keyframes.first else {
            return TransformInterpolationResult(
                value: .identity,
                zoomVelocity: 0,
                panVelocity: 0,
                panDirection: 0
            )
        }
        if time <= first.time + epsilon {
            return TransformInterpolationResult(
                value: first.value,
                zoomVelocity: 0,
                panVelocity: 0,
                panDirection: 0
            )
        }

        // Boundary: after the last keyframe (velocity = 0)
        guard let last = keyframes.last else {
            return TransformInterpolationResult(
                value: .identity,
                zoomVelocity: 0,
                panVelocity: 0,
                panDirection: 0
            )
        }
        if time >= last.time - epsilon {
            return TransformInterpolationResult(
                value: last.value,
                zoomVelocity: 0,
                panVelocity: 0,
                panDirection: 0
            )
        }

        // Use binary search to find the bounding keyframes
        let (before, after) = findBoundingKeyframes(keyframes, at: time)

        // Compute progress
        let duration = after.time - before.time
        guard duration > epsilon else {
            return TransformInterpolationResult(
                value: before.value,
                zoomVelocity: 0,
                panVelocity: 0,
                panDirection: 0
            )
        }

        let progress = (time - before.time) / duration

        // Apply easing
        let easedProgress = before.easing.apply(CGFloat(progress), duration: CGFloat(duration))

        // Calculate easing derivative (instantaneous velocity ratio)
        let easingDerivative = before.easing.derivative(CGFloat(progress), duration: CGFloat(duration))

        // Interpolate the value (use anchor point interpolation in window mode)
        let fromValue = before.value
        let toValue = after.value
        let interpolatedValue: TransformValue
        if windowMode {
            interpolatedValue = fromValue.interpolatedForWindowMode(to: toValue, amount: easedProgress)
        } else {
            interpolatedValue = fromValue.interpolated(to: toValue, amount: easedProgress)
        }

        // Velocity calculation: derivative * (endValue - startValue) / duration
        let zoomDelta = toValue.zoom - fromValue.zoom
        let zoomVelocity = abs(easingDerivative * zoomDelta / CGFloat(duration))

        let dx = toValue.center.x - fromValue.center.x
        let dy = toValue.center.y - fromValue.center.y
        let rawPanVelocity = abs(easingDerivative) * hypot(dx, dy) / CGFloat(duration)
        let panDirection = atan2(dy, dx)

        // Scale the pan velocity according to the current zoom level
        // At zoom=1 the entire screen fits, so pan has no visual effect
        // Higher zoom levels amplify the visual impact of panning
        let zoomFactor = max(0, interpolatedValue.zoom - 1.0)
        let panVelocity = rawPanVelocity * zoomFactor

        return TransformInterpolationResult(
            value: interpolatedValue,
            zoomVelocity: zoomVelocity,
            panVelocity: panVelocity,
            panDirection: panDirection
        )
    }

    // MARK: - Binary Search

    /// Find bounding keyframes using binary search
    /// - Parameters:
    ///   - keyframes: Time-sorted keyframes
    ///   - time: Time to search
    /// - Returns: A tuple containing the preceding and following keyframes
    func findBoundingKeyframes<K: TimedKeyframe>(
        _ keyframes: [K],
        at time: TimeInterval
    ) -> (before: K, after: K) {
        // Perform binary search
        var low = 0
        var high = keyframes.count - 1

        while low < high - 1 {
            let mid = (low + high) / 2
            if keyframes[mid].time <= time {
                low = mid
            } else {
                high = mid
            }
        }

        return (keyframes[low], keyframes[high])
    }

    /// Find the index of the keyframe immediately before a given time
    func findKeyframeIndex<K: TimedKeyframe>(
        _ keyframes: [K],
        before time: TimeInterval
    ) -> Int? {
        guard !keyframes.isEmpty else { return nil }

        // Before the first keyframe
        if time < keyframes[0].time {
            return nil
        }

        // Perform binary search
        var low = 0
        var high = keyframes.count - 1

        while low < high {
            let mid = (low + high + 1) / 2
            if keyframes[mid].time <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }

        return low
    }

    /// Find the index of the keyframe immediately after a given time
    func findKeyframeIndex<K: TimedKeyframe>(
        _ keyframes: [K],
        after time: TimeInterval
    ) -> Int? {
        guard !keyframes.isEmpty else { return nil }

        // After the last keyframe
        if time >= keyframes[keyframes.count - 1].time {
            return nil
        }

        // Perform binary search
        var low = 0
        var high = keyframes.count - 1

        while low < high {
            let mid = (low + high) / 2
            if keyframes[mid].time <= time {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low
    }

    // MARK: - Keyframe at Time

    /// Find a keyframe that matches a specific time
    func findKeyframe<K: TimedKeyframe>(
        _ keyframes: [K],
        at time: TimeInterval,
        tolerance: TimeInterval = 0.016  // ~1 frame at 60fps
    ) -> K? {
        // Use binary search to find a nearby keyframe
        guard let index = findKeyframeIndex(keyframes, before: time) else {
            // Check the first keyframe
            if let first = keyframes.first, abs(first.time - time) <= tolerance {
                return first
            }
            return nil
        }

        let keyframe = keyframes[index]
        if abs(keyframe.time - time) <= tolerance {
            return keyframe
        }

        // Also check the next keyframe
        if index + 1 < keyframes.count {
            let next = keyframes[index + 1]
            if abs(next.time - time) <= tolerance {
                return next
            }
        }

        return nil
    }
}

// MARK: - CGFloat Interpolatable

extension CGFloat: Interpolatable {
    func interpolated(to target: CGFloat, amount: CGFloat) -> CGFloat {
        self + (target - self) * amount
    }
}

// MARK: - CGPoint Interpolatable

extension CGPoint: Interpolatable {
    func interpolated(to target: CGPoint, amount: CGFloat) -> CGPoint {
        CGPoint(
            x: x + (target.x - x) * amount,
            y: y + (target.y - y) * amount
        )
    }
}
