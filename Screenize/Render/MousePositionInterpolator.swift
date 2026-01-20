import Foundation
import CoreGraphics

// MARK: - Mouse Position Interpolator

/// Utility that smooths mouse positions using a Catmull-Rom spline
struct MousePositionInterpolator {

    /// Smooth mouse positions with a Catmull-Rom spline
    /// - Parameters:
    ///   - positions: Original mouse position data
    ///   - outputFrameRate: Output frame rate
    ///   - tension: Catmull-Rom tension (0.2 gives natural interpolation close to the original path)
    /// - Returns: Interpolated mouse positions
    static func interpolate(
        _ positions: [RenderMousePosition],
        outputFrameRate: Double,
        tension: CGFloat = 0.2
    ) -> [RenderMousePosition] {
        guard positions.count >= 4 else { return positions }

        var interpolated: [RenderMousePosition] = []
        let frameDuration = 1.0 / outputFrameRate

        // Interpolate the first segment (p0-p1)
        if positions.count >= 2 {
            let startTime = positions[0].timestamp
            let endTime = positions[1].timestamp
            let duration = endTime - startTime

            if duration > frameDuration {
                var t: TimeInterval = 0
                while t < duration {
                    let progress = CGFloat(t / duration)
                    // Start with linear interpolation in the first segment
                    let p0 = positions[0].position
                    let p1 = positions[1].position
                    let x = p0.x + (p1.x - p0.x) * progress
                    let y = p0.y + (p1.y - p0.y) * progress

                    interpolated.append(RenderMousePosition(
                        timestamp: startTime + t,
                        x: x,
                        y: y,
                        velocity: positions[0].velocity
                    ))
                    t += frameDuration
                }
            } else {
                interpolated.append(positions[0])
            }
        }

        // Catmull-Rom interpolation for middle segments
        for i in 1..<positions.count - 2 {
            let p0 = positions[i - 1].position
            let p1 = positions[i].position
            let p2 = positions[i + 1].position
            let p3 = positions[i + 2].position

            let startTime = positions[i].timestamp
            let endTime = positions[i + 1].timestamp
            let duration = endTime - startTime

            guard duration > 0.001 else {
                interpolated.append(positions[i])
                continue
            }

            var t: TimeInterval = 0
            while t < duration {
                let progress = CGFloat(t / duration)
                let point = catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: progress, tension: tension)

                // Interpolate velocity
                let velocity = positions[i].velocity + (positions[i + 1].velocity - positions[i].velocity) * progress

                interpolated.append(RenderMousePosition(
                    timestamp: startTime + t,
                    x: point.x,
                    y: point.y,
                    velocity: velocity
                ))
                t += frameDuration
            }
        }

        // Interpolate the final segment (pN-2 ~ pN-1)
        if positions.count >= 2 {
            let lastIdx = positions.count - 1
            let secondLastIdx = positions.count - 2
            let startTime = positions[secondLastIdx].timestamp
            let endTime = positions[lastIdx].timestamp
            let duration = endTime - startTime

            if duration > frameDuration {
                var t: TimeInterval = 0
                while t <= duration {
                    let progress = CGFloat(t / duration)
                    // Last segment also uses linear interpolation
                    let p0 = positions[secondLastIdx].position
                    let p1 = positions[lastIdx].position
                    let x = p0.x + (p1.x - p0.x) * progress
                    let y = p0.y + (p1.y - p0.y) * progress

                    interpolated.append(RenderMousePosition(
                        timestamp: startTime + t,
                        x: x,
                        y: y,
                        velocity: positions[lastIdx].velocity
                    ))
                    t += frameDuration
                }
            } else {
                interpolated.append(positions[lastIdx])
            }
        }

        // Remove duplicates and sort by timestamp
        var uniquePositions: [RenderMousePosition] = []
        var lastTimestamp: TimeInterval = -1

        for pos in interpolated.sorted(by: { $0.timestamp < $1.timestamp }) {
            if pos.timestamp - lastTimestamp >= frameDuration * 0.5 {
                uniquePositions.append(pos)
                lastTimestamp = pos.timestamp
            }
        }

        return uniquePositions
    }

    // MARK: - Private

    /// Catmull-Rom spline interpolation
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
    /// Wrapper for backward compatibility
    /// - Note: Prefer calling MousePositionInterpolator.interpolate() directly
    static func interpolateMousePositions(
        _ positions: [RenderMousePosition],
        outputFrameRate: Double,
        tension: CGFloat = 0.2
    ) -> [RenderMousePosition] {
        MousePositionInterpolator.interpolate(positions, outputFrameRate: outputFrameRate, tension: tension)
    }
}
