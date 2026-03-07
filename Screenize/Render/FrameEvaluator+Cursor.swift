import Foundation
import CoreGraphics

// MARK: - Cursor Evaluation

extension FrameEvaluator {

    /// Evaluate the cursor track
    func evaluateCursor(at time: TimeInterval) -> CursorState {
        guard let track = timeline.cursorTrackV2, track.isEnabled else {
            return .hidden
        }

        // Check the click state
        let (isClicking, clickType) = checkClickState(at: time)
        let clickScaleModifier = computeClickScaleModifier(at: time)

        let activeSegment = track.activeSegment(at: time)
        let position = interpolateMousePosition(at: time)

        return CursorState(
            position: position,
            style: activeSegment?.style ?? .arrow,
            scale: activeSegment?.scale ?? 2.5,
            visible: activeSegment?.visible ?? true,
            isClicking: isClicking,
            clickType: clickType,
            velocity: 0,
            movementDirection: 0,
            clickScaleModifier: clickScaleModifier
        )
    }

    // MARK: - Mouse Position Interpolation

    /// Interpolate mouse positions using a Catmull-Rom spline
    func interpolateMousePosition(at time: TimeInterval) -> NormalizedPoint {
        guard mousePositions.count >= 2 else {
            if let first = mousePositions.first {
                return normalizePosition(first.position)
            }
            return .center
        }

        // Find the position corresponding to the given time
        let (index, t) = findInterpolationParameters(for: time)

        // Catmull-Rom interpolation
        let interpolatedPosition = catmullRomInterpolate(index: index, t: t)

        return normalizePosition(interpolatedPosition)
    }

    func findInterpolationParameters(for time: TimeInterval) -> (index: Int, t: CGFloat) {
        guard mousePositions.count >= 4 else {
            // Fall back to linear interpolation
            if mousePositions.count >= 2 {
                let t0 = mousePositions[0].timestamp
                let t1 = mousePositions[mousePositions.count - 1].timestamp
                let duration = max(0.001, t1 - t0)
                let rawT = (time - t0) / duration
                return (0, CGFloat(clamp(rawT, min: 0, max: 1)))
            }
            return (0, 0)
        }

        // Handle boundary cases
        if time <= mousePositions[1].timestamp {
            let t0 = mousePositions[0].timestamp
            let t1 = mousePositions[1].timestamp
            let duration = max(0.001, t1 - t0)
            let rawT = (time - t0) / duration
            return (1, CGFloat(clamp(rawT, min: 0, max: 1)))
        }

        if time >= mousePositions[mousePositions.count - 2].timestamp {
            return (mousePositions.count - 3, 1.0)
        }

        // Binary search
        var low = 1
        var high = mousePositions.count - 2

        while low < high - 1 {
            let mid = (low + high) / 2
            if mousePositions[mid].timestamp <= time {
                low = mid
            } else {
                high = mid
            }
        }

        let t0 = mousePositions[low].timestamp
        let t1 = mousePositions[high].timestamp
        let duration = max(0.001, t1 - t0)
        let rawT = (time - t0) / duration

        return (low, CGFloat(clamp(rawT, min: 0, max: 1)))
    }

    func catmullRomInterpolate(index: Int, t: CGFloat) -> CGPoint {
        let n = mousePositions.count

        let i0 = max(0, index - 1)
        let i1 = index
        let i2 = min(n - 1, index + 1)
        let i3 = min(n - 1, index + 2)

        let p0 = mousePositions[i0].position
        let p1 = mousePositions[i1].position
        let p2 = mousePositions[i2].position
        let p3 = mousePositions[i3].position

        let tension: CGFloat = 0.2  // 0.5 → 0.2: smoother interpolation closer to the actual mouse path

        let t2 = t * t
        let t3 = t2 * t

        let x = catmullRomValue(p0: p0.x, p1: p1.x, p2: p2.x, p3: p3.x, t: t, t2: t2, t3: t3, tension: tension)
        let y = catmullRomValue(p0: p0.y, p1: p1.y, p2: p2.y, p3: p3.y, t: t, t2: t2, t3: t3, tension: tension)

        return CGPoint(x: x, y: y)
    }

    func catmullRomValue(
        p0: CGFloat, p1: CGFloat, p2: CGFloat, p3: CGFloat,
        t: CGFloat, t2: CGFloat, t3: CGFloat, tension: CGFloat
    ) -> CGFloat {
        let a0 = -tension * p0 + (2 - tension) * p1 + (tension - 2) * p2 + tension * p3
        let a1 = 2 * tension * p0 + (tension - 3) * p1 + (3 - 2 * tension) * p2 - tension * p3
        let a2 = -tension * p0 + tension * p2
        let a3 = p1

        return a0 * t3 + a1 * t2 + a2 * t + a3
    }

    func normalizePosition(_ position: CGPoint) -> NormalizedPoint {
        // PreviewEngine already provides normalized (0-1) coordinates, so use them directly
        return NormalizedPoint(x: position.x, y: position.y)
    }
}
