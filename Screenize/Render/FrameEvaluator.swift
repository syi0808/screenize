import Foundation
import CoreGraphics

/// Frame evaluator
/// Computes the frame state at a specific time by evaluating all timeline tracks
final class FrameEvaluator {

    // MARK: - Properties

    /// Timeline
    private let timeline: Timeline

    /// Mouse position data (for cursor rendering)
    private let mousePositions: [RenderMousePosition]

    /// Click event data (for cursor state)
    private let clickEvents: [RenderClickEvent]

    /// Frame rate
    private let frameRate: Double

    /// Scale factor
    private let scaleFactor: CGFloat

    /// Screen bounds (in pixels)
    private let screenBoundsPixel: CGSize

    /// Flag for window mode (disables center clamping in window mode)
    private let isWindowMode: Bool

    // MARK: - Initialization

    init(
        timeline: Timeline,
        mousePositions: [RenderMousePosition] = [],
        clickEvents: [RenderClickEvent] = [],
        frameRate: Double = 60.0,
        scaleFactor: CGFloat = 1.0,
        screenBoundsPixel: CGSize = .zero,
        isWindowMode: Bool = false
    ) {
        self.timeline = timeline
        self.mousePositions = mousePositions
        self.clickEvents = clickEvents
        self.frameRate = frameRate
        self.scaleFactor = scaleFactor
        self.screenBoundsPixel = screenBoundsPixel
        self.isWindowMode = isWindowMode
    }

    // MARK: - Main Evaluation

    /// Evaluate the frame state at a specific time
    /// - Parameter time: Time to evaluate (seconds)
    /// - Returns: Evaluated frame state
    func evaluate(at time: TimeInterval) -> EvaluatedFrameState {
        let cursor = evaluateCursor(at: time)
        let transform = evaluateTransform(at: time)
        let keystrokes = evaluateKeystrokes(at: time)

        return EvaluatedFrameState(
            time: time,
            transform: transform,
            cursor: cursor,
            keystrokes: keystrokes
        )
    }

    /// Evaluate using a specific frame number
    func evaluate(frame: Int) -> EvaluatedFrameState {
        let time = Double(frame) / frameRate
        return evaluate(at: time)
    }

    // MARK: - Transform Evaluation

    /// Evaluate the transform track
    /// - Parameter time: Time to evaluate
    private func evaluateTransform(at time: TimeInterval) -> TransformState {
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
    /// Pre-limit the center to avoid letting the crop exceed the image edges
    private func clampCenterForZoom(center: NormalizedPoint, zoom: CGFloat) -> NormalizedPoint {
        guard zoom > 1.0 else { return center }

        let halfCropRatio = 0.5 / zoom
        return NormalizedPoint(
            x: clamp(center.x, min: halfCropRatio, max: 1.0 - halfCropRatio),
            y: clamp(center.y, min: halfCropRatio, max: 1.0 - halfCropRatio)
        )
    }

    // MARK: - Keystroke Evaluation

    /// Evaluate the keystroke overlay track
    private func evaluateKeystrokes(at time: TimeInterval) -> [ActiveKeystroke] {
        guard let track = timeline.keystrokeTrackV2, track.isEnabled else {
            return []
        }

        return track.activeSegments(at: time).map { segment in
            ActiveKeystroke(
                displayText: segment.displayText,
                opacity: keystrokeOpacity(for: segment, at: time),
                progress: CGFloat((time - segment.startTime) / max(0.001, segment.endTime - segment.startTime)),
                position: segment.position
            )
        }
    }

    // MARK: - Cursor Evaluation

    /// Evaluate the cursor track
    private func evaluateCursor(at time: TimeInterval) -> CursorState {
        guard let track = timeline.cursorTrackV2, track.isEnabled else {
            return .hidden
        }

        // Check the click state
        let (isClicking, clickType) = checkClickState(at: time)
        let clickScaleModifier = computeClickScaleModifier(at: time)

        let activeSegment = track.activeSegment(at: time)
        let position = activeSegment?.position ?? interpolateMousePosition(at: time)

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

    private func keystrokeOpacity(for segment: KeystrokeSegment, at time: TimeInterval) -> CGFloat {
        let elapsed = time - segment.startTime
        let remaining = segment.endTime - time

        if segment.fadeInDuration > 0, elapsed < segment.fadeInDuration {
            return CGFloat(elapsed / segment.fadeInDuration)
        }

        if segment.fadeOutDuration > 0, remaining < segment.fadeOutDuration {
            return CGFloat(remaining / segment.fadeOutDuration)
        }

        return 1.0
    }

    /// Interpolate angles (handles wrap-around)
    private func interpolateAngle(from angle1: CGFloat, to angle2: CGFloat, t: CGFloat) -> CGFloat {
        var diff = angle2 - angle1

        // Normalize the difference to the -π to π range
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }

        return angle1 + diff * t
    }

    /// Catmull-Rom point interpolation (low tension for a smoother path)
    private func catmullRomInterpolatePoint(
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        t: CGFloat
    ) -> CGPoint {
        let tension: CGFloat = 0.2  // 0.5 → 0.2: reduce exaggerated curves for a more natural path
        let t2 = t * t
        let t3 = t2 * t

        let x = catmullRomValue(p0: p0.x, p1: p1.x, p2: p2.x, p3: p3.x, t: t, t2: t2, t3: t3, tension: tension)
        let y = catmullRomValue(p0: p0.y, p1: p1.y, p2: p2.y, p3: p3.y, t: t, t2: t2, t3: t3, tension: tension)

        return CGPoint(x: x, y: y)
    }

    // MARK: - Mouse Position Interpolation

    /// Interpolate mouse positions using a Catmull-Rom spline
    private func interpolateMousePosition(at time: TimeInterval) -> NormalizedPoint {
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

    private func findInterpolationParameters(for time: TimeInterval) -> (index: Int, t: CGFloat) {
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

    private func catmullRomInterpolate(index: Int, t: CGFloat) -> CGPoint {
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

    private func catmullRomValue(
        p0: CGFloat, p1: CGFloat, p2: CGFloat, p3: CGFloat,
        t: CGFloat, t2: CGFloat, t3: CGFloat, tension: CGFloat
    ) -> CGFloat {
        let a0 = -tension * p0 + (2 - tension) * p1 + (tension - 2) * p2 + tension * p3
        let a1 = 2 * tension * p0 + (tension - 3) * p1 + (3 - 2 * tension) * p2 - tension * p3
        let a2 = -tension * p0 + tension * p2
        let a3 = p1

        return a0 * t3 + a1 * t2 + a2 * t + a3
    }

    // MARK: - Click State

    private func checkClickState(at time: TimeInterval) -> (isClicking: Bool, clickType: ClickType?) {
        for click in clickEvents {
            if click.isActive(at: time) {
                return (true, click.clickType)
            }
        }
        return (false, nil)
    }

    private func computeClickScaleModifier(at time: TimeInterval) -> CGFloat {
        guard !clickEvents.isEmpty else { return 1.0 }

        let pressDuration: TimeInterval = 0.08
        let pressedScale: CGFloat = 0.8
        let settleDuration: TimeInterval = 0.08

        var candidates: [CGFloat] = []

        for click in clickEvents {
            let downTime = click.timestamp
            let upTime = click.endTimestamp

            let clickModifier: CGFloat
            if time < downTime || time > upTime + settleDuration {
                continue
            } else if time <= downTime + pressDuration {
                let t = CGFloat((time - downTime) / pressDuration)
                clickModifier = 1.0 + (pressedScale - 1.0) * easeOutQuad(t)
            } else if time <= upTime {
                clickModifier = pressedScale
            } else {
                let t = CGFloat((time - upTime) / settleDuration)
                clickModifier = pressedScale + (1.0 - pressedScale) * easeOutQuad(t)
            }

            candidates.append(clickModifier)
        }

        guard !candidates.isEmpty else { return 1.0 }
        if let minimum = candidates.min(), minimum < 1.0 {
            return minimum
        }
        return candidates.max() ?? 1.0
    }

    private func easeOutQuad(_ t: CGFloat) -> CGFloat {
        let clamped = clamp(t, min: 0, max: 1)
        return 1 - (1 - clamped) * (1 - clamped)
    }

    // MARK: - Helpers

    private func normalizePosition(_ position: CGPoint) -> NormalizedPoint {
        // PreviewEngine already provides normalized (0-1) coordinates, so use them directly
        return NormalizedPoint(x: position.x, y: position.y)
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

// MARK: - Supporting Data Types (For Render)

/// Mouse position data for rendering
struct RenderMousePosition {
    let timestamp: TimeInterval
    let position: CGPoint
    let velocity: CGFloat

    init(timestamp: TimeInterval, x: CGFloat, y: CGFloat, velocity: CGFloat = 0) {
        self.timestamp = timestamp
        self.position = CGPoint(x: x, y: y)
        self.velocity = velocity
    }
}

/// Click event data for rendering
struct RenderClickEvent {
    let timestamp: TimeInterval
    let duration: TimeInterval
    let position: CGPoint
    let clickType: ClickType

    var endTimestamp: TimeInterval {
        timestamp + duration
    }

    func isActive(at time: TimeInterval) -> Bool {
        time >= timestamp && time <= endTimestamp
    }

    init(timestamp: TimeInterval, duration: TimeInterval, x: CGFloat, y: CGFloat, clickType: ClickType) {
        self.timestamp = timestamp
        self.duration = duration
        self.position = CGPoint(x: x, y: y)
        self.clickType = clickType
    }
}

// MARK: - Batch Evaluation

extension FrameEvaluator {
    /// Generate an array of states for all frames
    func evaluateAllFrames(totalFrames: Int) -> [EvaluatedFrameState] {
        var states: [EvaluatedFrameState] = []
        states.reserveCapacity(totalFrames)

        for frame in 0..<totalFrames {
            states.append(evaluate(frame: frame))
        }

        return states
    }

    /// Evaluate states for a specific frame range
    func evaluateFrames(from startFrame: Int, to endFrame: Int) -> [EvaluatedFrameState] {
        var states: [EvaluatedFrameState] = []
        let count = endFrame - startFrame + 1
        states.reserveCapacity(count)

        for frame in startFrame...endFrame {
            states.append(evaluate(frame: frame))
        }

        return states
    }
}
