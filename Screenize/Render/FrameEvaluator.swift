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

    /// Mouse button events for cursor press/release animation (sorted by timestamp)
    let mouseButtonEvents: [RenderMouseButtonEvent]

    /// Frame rate
    let frameRate: Double

    /// Scale factor
    let scaleFactor: CGFloat

    /// Screen bounds (in pixels)
    let screenBoundsPixel: CGSize

    /// Flag for window mode (disables center clamping in window mode)
    let isWindowMode: Bool

    /// Cached spring-simulated transforms for manual segments
    var springCache: SpringSimulationCache?

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
        mouseButtonEvents: [RenderMouseButtonEvent] = [],
        frameRate: Double = 60.0,
        scaleFactor: CGFloat = 1.0,
        screenBoundsPixel: CGSize = .zero,
        isWindowMode: Bool = false,
        springCache: SpringSimulationCache? = nil
    ) {
        self.timeline = timeline
        self.rawMousePositions = rawMousePositions
        self.smoothedMousePositions = smoothedMousePositions
        self.mouseButtonEvents = mouseButtonEvents
        self.frameRate = frameRate
        self.scaleFactor = scaleFactor
        self.screenBoundsPixel = screenBoundsPixel
        self.isWindowMode = isWindowMode
        self.springCache = springCache
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

/// Individual mouse button event (mouseDown or mouseUp) for cursor animation.
/// Cursor animation is driven directly by down/up events rather than paired click events,
/// so that press/hold/release phases work correctly for drags and rapid clicks.
struct RenderMouseButtonEvent {
    let timestamp: TimeInterval
    let isDown: Bool          // true = mouseDown, false = mouseUp
    let clickType: ClickType  // .left or .right
}
