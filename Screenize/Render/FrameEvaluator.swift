import Foundation
import CoreGraphics

/// Frame evaluator
/// Computes the frame state at a specific time by evaluating all timeline tracks
final class FrameEvaluator {

    // MARK: - Properties

    /// Timeline
    let timeline: Timeline

    /// Raw mouse position data
    let rawMousePositions: [RenderMousePosition]

    /// Smoothed mouse position data (Catmull-Rom interpolated)
    let smoothedMousePositions: [RenderMousePosition]

    /// Click event data (for cursor state)
    let clickEvents: [RenderClickEvent]

    /// Frame rate
    let frameRate: Double

    /// Scale factor
    let scaleFactor: CGFloat

    /// Screen bounds (in pixels)
    let screenBoundsPixel: CGSize

    /// Flag for window mode (disables center clamping in window mode)
    let isWindowMode: Bool

    /// Effective mouse positions based on smooth cursor toggle
    var mousePositions: [RenderMousePosition] {
        let useSmoothCursor = timeline.cursorTrackV2?.useSmoothCursor ?? true
        return useSmoothCursor ? smoothedMousePositions : rawMousePositions
    }

    // MARK: - Initialization

    init(
        timeline: Timeline,
        rawMousePositions: [RenderMousePosition] = [],
        smoothedMousePositions: [RenderMousePosition] = [],
        clickEvents: [RenderClickEvent] = [],
        frameRate: Double = 60.0,
        scaleFactor: CGFloat = 1.0,
        screenBoundsPixel: CGSize = .zero,
        isWindowMode: Bool = false
    ) {
        self.timeline = timeline
        self.rawMousePositions = rawMousePositions
        self.smoothedMousePositions = smoothedMousePositions
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

    // MARK: - Helpers

    func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
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
