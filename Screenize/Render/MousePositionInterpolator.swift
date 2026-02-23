import Foundation
import CoreGraphics

// MARK: - Mouse Position Interpolator

/// Smooths mouse positions using Gaussian pre-filtering + Catmull-Rom spline interpolation
/// with boundary reflection and idle stabilization
struct MousePositionInterpolator {

    // MARK: - Public API

    /// Smooth mouse positions with improved interpolation
    /// - Parameters:
    ///   - positions: Original mouse position data
    ///   - outputFrameRate: Output frame rate
    ///   - baseTension: Catmull-Rom tension (0.2 = natural curve)
    ///   - gaussianRadius: Gaussian pre-filter radius (3 = mild smoothing)
    /// - Returns: Interpolated mouse positions at frame rate intervals
    static func interpolate(
        _ positions: [RenderMousePosition],
        outputFrameRate: Double,
        baseTension: CGFloat = 0.2,
        gaussianRadius: Int = 3
    ) -> [RenderMousePosition] {
        guard positions.count >= 2 else { return positions }

        let frameDuration = 1.0 / outputFrameRate

        // Step 1: Gaussian pre-filter to remove sub-pixel jitter
        let smoothed = gaussianSmooth(positions, radius: gaussianRadius)

        // Step 2: Catmull-Rom interpolation with reflected boundaries
        var interpolated: [RenderMousePosition] = []

        for i in 0..<smoothed.count - 1 {
            let p0 = reflectedPoint(smoothed, index: i - 1).position
            let p1 = smoothed[i].position
            let p2 = smoothed[i + 1].position
            let p3 = reflectedPoint(smoothed, index: i + 2).position

            let startTime = smoothed[i].timestamp
            let endTime = smoothed[i + 1].timestamp
            let duration = endTime - startTime

            guard duration > 0.001 else {
                interpolated.append(smoothed[i])
                continue
            }

            var t: TimeInterval = 0
            while t < duration {
                let progress = CGFloat(t / duration)
                let point = catmullRom(
                    p0: p0, p1: p1, p2: p2, p3: p3,
                    t: progress, tension: baseTension
                )
                let deriv = catmullRomDerivative(
                    p0: p0, p1: p1, p2: p2, p3: p3,
                    t: progress, tension: baseTension
                )
                let velocity = sqrt(deriv.x * deriv.x + deriv.y * deriv.y) / CGFloat(duration)

                interpolated.append(RenderMousePosition(
                    timestamp: startTime + t,
                    x: point.x,
                    y: point.y,
                    velocity: velocity
                ))
                t += frameDuration
            }
        }

        // Add the final position
        if let last = smoothed.last {
            interpolated.append(last)
        }

        // Step 3: Idle stabilization (clamp stationary jitter)
        let stabilized = stabilizeIdlePositions(interpolated, threshold: 0.001)

        // Step 4: Deduplicate by timestamp
        return deduplicateByTimestamp(stabilized, minInterval: frameDuration * 0.5)
    }

    // MARK: - Gaussian Pre-Filter

    /// Apply 1D Gaussian smoothing to x/y coordinates independently
    private static func gaussianSmooth(
        _ positions: [RenderMousePosition],
        radius: Int
    ) -> [RenderMousePosition] {
        guard positions.count > radius * 2 else { return positions }

        let kernel = gaussianKernel(radius: radius)
        var result = positions

        for i in 0..<positions.count {
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            var weightSum: CGFloat = 0

            for k in -radius...radius {
                let idx = min(max(i + k, 0), positions.count - 1)
                let weight = kernel[k + radius]
                sumX += positions[idx].position.x * weight
                sumY += positions[idx].position.y * weight
                weightSum += weight
            }

            result[i] = RenderMousePosition(
                timestamp: positions[i].timestamp,
                x: sumX / weightSum,
                y: sumY / weightSum,
                velocity: positions[i].velocity
            )
        }

        return result
    }

    /// Generate a 1D Gaussian kernel
    private static func gaussianKernel(radius: Int) -> [CGFloat] {
        let sigma = CGFloat(radius) / 2.0
        var kernel = [CGFloat](repeating: 0, count: radius * 2 + 1)

        for i in 0..<kernel.count {
            let x = CGFloat(i - radius)
            kernel[i] = exp(-(x * x) / (2 * sigma * sigma))
        }

        let sum = kernel.reduce(0, +)
        return kernel.map { $0 / sum }
    }

    // MARK: - Boundary Reflection

    /// Get a position with boundary reflection for Catmull-Rom endpoints
    private static func reflectedPoint(
        _ positions: [RenderMousePosition],
        index: Int
    ) -> RenderMousePosition {
        if index < 0 {
            // Reflect: virtual point = 2 * p[0] - p[1]
            let p0 = positions[0].position
            let p1 = positions[min(1, positions.count - 1)].position
            return RenderMousePosition(
                timestamp: positions[0].timestamp,
                x: 2 * p0.x - p1.x,
                y: 2 * p0.y - p1.y,
                velocity: positions[0].velocity
            )
        } else if index >= positions.count {
            // Reflect: virtual point = 2 * p[last] - p[last-1]
            let pLast = positions[positions.count - 1].position
            let pPrev = positions[max(0, positions.count - 2)].position
            return RenderMousePosition(
                timestamp: positions[positions.count - 1].timestamp,
                x: 2 * pLast.x - pPrev.x,
                y: 2 * pLast.y - pPrev.y,
                velocity: positions[positions.count - 1].velocity
            )
        }
        return positions[index]
    }

    // MARK: - Idle Stabilization

    /// Gradually blend positions toward an idle anchor using exponential decay.
    /// When velocity drops below threshold, blendFactor increases toward 1.0 (locked).
    /// When velocity returns, blendFactor decays back toward 0.0 (free movement).
    private static func stabilizeIdlePositions(
        _ positions: [RenderMousePosition],
        threshold: CGFloat,
        decayRate: CGFloat = 8.0
    ) -> [RenderMousePosition] {
        guard positions.count >= 2 else { return positions }

        var result = positions
        var idleAnchor: CGPoint?
        var blendFactor: CGFloat = 0

        for i in 0..<result.count {
            let velocity = computeInstantVelocity(result, at: i)
            let dt: CGFloat = i > 0
                ? CGFloat(result[i].timestamp - result[i - 1].timestamp)
                : 0

            if velocity < threshold {
                if idleAnchor == nil {
                    idleAnchor = result[i].position
                }
                blendFactor = min(1.0, blendFactor + (1.0 - blendFactor) * (1.0 - exp(-decayRate * dt)))
            } else {
                blendFactor = max(0.0, blendFactor * exp(-decayRate * dt))
                if blendFactor < 0.01 {
                    blendFactor = 0
                    idleAnchor = nil
                }
            }

            if let anchor = idleAnchor, blendFactor > 0.001 {
                let blendedX = result[i].position.x + (anchor.x - result[i].position.x) * blendFactor
                let blendedY = result[i].position.y + (anchor.y - result[i].position.y) * blendFactor
                let blendedVelocity = result[i].velocity * (1.0 - blendFactor)
                result[i] = RenderMousePosition(
                    timestamp: result[i].timestamp,
                    x: blendedX,
                    y: blendedY,
                    velocity: blendedVelocity
                )
            }
        }

        return result
    }

    /// Compute instantaneous velocity at a given index
    private static func computeInstantVelocity(
        _ positions: [RenderMousePosition],
        at index: Int
    ) -> CGFloat {
        guard index > 0 else { return 0 }

        let prev = positions[index - 1]
        let curr = positions[index]
        let dt = curr.timestamp - prev.timestamp
        guard dt > 0.001 else { return 0 }

        let dx = curr.position.x - prev.position.x
        let dy = curr.position.y - prev.position.y
        return sqrt(dx * dx + dy * dy) / CGFloat(dt)
    }

    // MARK: - Deduplication

    /// Remove positions that are too close in timestamp
    private static func deduplicateByTimestamp(
        _ positions: [RenderMousePosition],
        minInterval: TimeInterval
    ) -> [RenderMousePosition] {
        var result: [RenderMousePosition] = []
        var lastTimestamp: TimeInterval = -1

        for pos in positions.sorted(by: { $0.timestamp < $1.timestamp }) {
            if pos.timestamp - lastTimestamp >= minInterval {
                result.append(pos)
                lastTimestamp = pos.timestamp
            }
        }

        return result
    }

    // MARK: - Catmull-Rom Spline

    /// Catmull-Rom spline derivative at parameter t (velocity direction and magnitude in parameter space)
    private static func catmullRomDerivative(
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        t: CGFloat,
        tension: CGFloat
    ) -> CGPoint {
        let t2 = t * t

        let m1x = tension * (p2.x - p0.x)
        let m1y = tension * (p2.y - p0.y)
        let m2x = tension * (p3.x - p1.x)
        let m2y = tension * (p3.y - p1.y)

        let da = 6 * t2 - 6 * t
        let db = 3 * t2 - 4 * t + 1
        let dc = -6 * t2 + 6 * t
        let dd = 3 * t2 - 2 * t

        let x = da * p1.x + db * m1x + dc * p2.x + dd * m2x
        let y = da * p1.y + db * m1y + dc * p2.y + dd * m2y

        return CGPoint(x: x, y: y)
    }

    /// Catmull-Rom spline interpolation between p1 and p2
    private static func catmullRom(
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        t: CGFloat,
        tension: CGFloat
    ) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t

        let m1x = tension * (p2.x - p0.x)
        let m1y = tension * (p2.y - p0.y)
        let m2x = tension * (p3.x - p1.x)
        let m2y = tension * (p3.y - p1.y)

        let a = 2 * t3 - 3 * t2 + 1
        let b = t3 - 2 * t2 + t
        let c = -2 * t3 + 3 * t2
        let d = t3 - t2

        let x = a * p1.x + b * m1x + c * p2.x + d * m2x
        let y = a * p1.y + b * m1y + c * p2.y + d * m2y

        return CGPoint(x: x, y: y)
    }
}

// MARK: - PreviewEngine Compatibility

extension PreviewEngine {
    static func interpolateMousePositions(
        _ positions: [RenderMousePosition],
        outputFrameRate: Double,
        tension: CGFloat = 0.2
    ) -> [RenderMousePosition] {
        MousePositionInterpolator.interpolate(
            positions,
            outputFrameRate: outputFrameRate,
            baseTension: tension
        )
    }
}
