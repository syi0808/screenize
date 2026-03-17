import Foundation

// MARK: - SeededRandomNumberGenerator

/// A deterministic pseudo-random number generator using xorshift64.
/// Produces the same sequence for the same seed, enabling reproducible paths.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        // Avoid zero state (xorshift produces only zeros from zero state)
        let raw = UInt64(bitPattern: Int64(seed))
        self.state = raw == 0 ? 0xDEADBEEFCAFEBABE : raw
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

// MARK: - PathGenerator

/// Generates cursor movement path points for mouse_move step replay.
struct PathGenerator {

    // MARK: Public API

    /// Generate cursor path points for a mouse_move step.
    /// Returns array of CGPoints (CG coordinates, top-left origin) at 10ms intervals.
    ///
    /// - Parameters:
    ///   - start: Starting cursor position.
    ///   - end: Ending cursor position.
    ///   - path: Path style; nil and `.auto` both produce a deterministic cubic Bezier.
    ///   - durationMs: Total movement duration in milliseconds.
    ///   - stepId: Unique step identifier used as the RNG seed for determinism.
    /// - Returns: Array of CGPoints sampled at 10ms intervals (count = max(1, durationMs / 10)).
    static func generatePath(
        from start: CGPoint,
        to end: CGPoint,
        path: MousePath?,
        durationMs: Int,
        stepId: UUID
    ) -> [CGPoint] {
        let pointCount = max(1, durationMs / 10)

        switch path {
        case .none, .auto:
            return generateBezierPath(from: start, to: end, pointCount: pointCount, stepId: stepId)
        case .waypoints(let waypoints):
            return generateCatmullRomPath(from: start, to: end, waypoints: waypoints, pointCount: pointCount)
        }
    }

    // MARK: Ease-in-out

    /// Standard ease-in-out (smoothstep variant): slow start, fast middle, slow end.
    /// t=0 → 0, t=0.5 → 0.5, t=1 → 1, and t=0.25 < 0.25.
    static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    // MARK: - Bezier Path

    private static func generateBezierPath(
        from start: CGPoint,
        to end: CGPoint,
        pointCount: Int,
        stepId: UUID
    ) -> [CGPoint] {
        // Zero distance: cursor is already at destination
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance > 0 else { return [start] }

        // Perpendicular unit vector (rotated 90°)
        let perpX = -dy / distance
        let perpY = dx / distance

        // Seeded RNG for deterministic control point offsets
        var rng = SeededRandomNumberGenerator(seed: stepId.hashValue)

        let offset1 = randomOffset(distance: distance, rng: &rng)
        let offset2 = randomOffset(distance: distance, rng: &rng)

        // Cubic Bezier control points
        let c1 = CGPoint(
            x: start.x + dx * 0.3 + perpX * offset1,
            y: start.y + dy * 0.3 + perpY * offset1
        )
        let c2 = CGPoint(
            x: start.x + dx * 0.7 + perpX * offset2,
            y: start.y + dy * 0.7 + perpY * offset2
        )

        return samplePoints(count: pointCount) { curved_t in
            cubicBezier(t: curved_t, p0: start, p1: c1, p2: c2, p3: end)
        }
    }

    /// Returns a random perpendicular offset between 2%–8% of distance, with random sign.
    private static func randomOffset(distance: CGFloat, rng: inout SeededRandomNumberGenerator) -> CGFloat {
        let raw = rng.next()
        // Map to [0, 1)
        let normalized = Double(raw) / Double(UInt64.max)
        // Scale to [0.02, 0.08] of distance
        let fraction = 0.02 + normalized * 0.06
        // Random sign from next bit
        let sign: Double = (rng.next() & 1) == 0 ? 1.0 : -1.0
        return CGFloat(sign * fraction * distance)
    }

    /// Cubic Bezier interpolation.
    private static func cubicBezier(t: Double, p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> CGPoint {
        let u = 1 - t
        let u2 = u * u
        let u3 = u2 * u
        let t2 = t * t
        let t3 = t2 * t
        return CGPoint(
            x: u3 * p0.x + 3 * u2 * t * p1.x + 3 * u * t2 * p2.x + t3 * p3.x,
            y: u3 * p0.y + 3 * u2 * t * p1.y + 3 * u * t2 * p2.y + t3 * p3.y
        )
    }

    // MARK: - Catmull-Rom Path

    private static func generateCatmullRomPath(
        from start: CGPoint,
        to end: CGPoint,
        waypoints: [CGPoint],
        pointCount: Int
    ) -> [CGPoint] {
        // Empty waypoints: straight line
        guard !waypoints.isEmpty else {
            return samplePoints(count: pointCount) { t in
                CGPoint(
                    x: start.x + (end.x - start.x) * t,
                    y: start.y + (end.y - start.y) * t
                )
            }
        }

        // Build the full control-point sequence
        let controlPoints = [start] + waypoints + [end]
        let segmentCount = controlPoints.count - 1

        // Sample with ease-in-out timing
        var points = samplePoints(count: pointCount) { curved_t in
            catmullRomPoint(t: curved_t, points: controlPoints, segmentCount: segmentCount)
        }

        // Guarantee exact waypoint passthrough: each waypoint falls at t = k/segmentCount.
        // Find the sample index closest to that t value and replace it with the exact waypoint.
        for (waypointIndex, waypoint) in waypoints.enumerated() {
            let waypointT = Double(waypointIndex + 1) / Double(segmentCount)
            let waypointLinearT = easeInOutInverse(waypointT)
            let closestIndex = (0..<pointCount).min(by: { a, b in
                let tA = Double(a) / Double(max(pointCount - 1, 1))
                let tB = Double(b) / Double(max(pointCount - 1, 1))
                return abs(tA - waypointLinearT) < abs(tB - waypointLinearT)
            }) ?? 0
            points[closestIndex] = waypoint
        }

        return points
    }

    /// Inverse of easeInOut: given y = easeInOut(x), returns x.
    /// Used to find which linearT corresponds to a given curvedT.
    private static func easeInOutInverse(_ y: Double) -> Double {
        // easeInOut is monotone; we can find the inverse analytically:
        // For y < 0.5: y = 2*x^2  → x = sqrt(y/2)
        // For y >= 0.5: y = 1 - (-2*x+2)^2/2  → x = 1 - sqrt((1-y)/2)
        if y < 0.5 {
            return sqrt(y / 2.0)
        } else {
            return 1.0 - sqrt((1.0 - y) / 2.0)
        }
    }

    /// Evaluate a centripetal Catmull-Rom spline (alpha = 0.5) at parameter t ∈ [0, 1].
    /// t is mapped uniformly across all segments.
    private static func catmullRomPoint(t: Double, points: [CGPoint], segmentCount: Int) -> CGPoint {
        // Map global t to segment index + local parameter
        let scaled = t * Double(segmentCount)
        let segmentIndex = min(Int(scaled), segmentCount - 1)
        let localT = scaled - Double(segmentIndex)

        // Four control points for this segment (clamped at boundaries)
        let p0 = points[max(segmentIndex - 1, 0)]
        let p1 = points[segmentIndex]
        let p2 = points[min(segmentIndex + 1, points.count - 1)]
        let p3 = points[min(segmentIndex + 2, points.count - 1)]

        return catmullRomSegment(t: localT, p0: p0, p1: p1, p2: p2, p3: p3, alpha: 0.5)
    }

    /// Centripetal Catmull-Rom interpolation for a single segment.
    private static func catmullRomSegment(
        t: Double,
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        alpha: Double
    ) -> CGPoint {
        func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
            let dx = Double(b.x - a.x)
            let dy = Double(b.y - a.y)
            return pow(sqrt(dx * dx + dy * dy), alpha)
        }

        let t0: Double = 0
        let t1 = t0 + dist(p0, p1)
        let t2 = t1 + dist(p1, p2)
        let t3 = t2 + dist(p2, p3)

        // Avoid degenerate knot intervals
        guard t1 > t0, t2 > t1, t3 > t2 else {
            // Fallback: linear interpolation between p1 and p2
            return CGPoint(
                x: p1.x + CGFloat(t) * (p2.x - p1.x),
                y: p1.y + CGFloat(t) * (p2.y - p1.y)
            )
        }

        let tParam = t1 + t * (t2 - t1)

        func blend(_ a: CGPoint, _ b: CGPoint, tA: Double, tB: Double, tVal: Double) -> CGPoint {
            let ratio = (tVal - tA) / (tB - tA)
            return CGPoint(
                x: a.x + CGFloat(ratio) * (b.x - a.x),
                y: a.y + CGFloat(ratio) * (b.y - a.y)
            )
        }

        let a1 = blend(p0, p1, tA: t0, tB: t1, tVal: tParam)
        let a2 = blend(p1, p2, tA: t1, tB: t2, tVal: tParam)
        let a3 = blend(p2, p3, tA: t2, tB: t3, tVal: tParam)

        let b1 = blend(a1, a2, tA: t0, tB: t2, tVal: tParam)
        let b2 = blend(a2, a3, tA: t1, tB: t3, tVal: tParam)

        return blend(b1, b2, tA: t1, tB: t2, tVal: tParam)
    }

    // MARK: - Shared Sampling

    /// Sample `count` points using the given evaluator, applying ease-in-out timing.
    /// linear_t goes from 0.0 to 1.0 evenly across all points.
    private static func samplePoints(count: Int, evaluator: (Double) -> CGPoint) -> [CGPoint] {
        guard count > 1 else { return [evaluator(0.0)] }
        return (0..<count).map { i in
            let linearT = Double(i) / Double(count - 1)
            let curvedT = easeInOut(linearT)
            return evaluator(curvedT)
        }
    }
}
