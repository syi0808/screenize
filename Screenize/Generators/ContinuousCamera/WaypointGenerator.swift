import Foundation
import CoreGraphics

/// Converts classified intent spans into camera waypoints for the spring-damper simulator.
///
/// Each waypoint represents a target camera state (zoom + center) at a specific time.
/// The simulator will smoothly animate between these waypoints using physics.
struct WaypointGenerator {

    // MARK: - Public API

    /// Generate camera waypoints from intent spans.
    /// - Parameters:
    ///   - intentSpans: Classified user intent spans (from IntentClassifier)
    ///   - screenBounds: Video dimensions for normalizing element frames
    ///   - eventTimeline: Optional event timeline for position data
    ///   - frameAnalysis: Vision framework analysis results
    ///   - settings: Continuous camera settings
    /// - Returns: Time-sorted array of camera waypoints
    static func generate(
        from intentSpans: [IntentSpan],
        screenBounds: CGSize,
        eventTimeline: EventTimeline?,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        settings: ContinuousCameraSettings
    ) -> [CameraWaypoint] {
        guard !intentSpans.isEmpty else {
            return [initialWaypoint()]
        }

        var waypoints: [CameraWaypoint] = []

        // Ensure t=0 waypoint exists
        if intentSpans[0].startTime > 0.001 {
            waypoints.append(initialWaypoint())
        }

        // Generate a waypoint at the start of each intent span
        for (index, span) in intentSpans.enumerated() {
            let zoom = computeZoom(for: span, settings: settings)
            let center = computeCenter(for: span, zoom: zoom)
            let urg = urgency(for: span.intent)

            waypoints.append(CameraWaypoint(
                time: span.startTime,
                targetZoom: zoom,
                targetCenter: center,
                urgency: urg,
                source: span.intent
            ))

            // For idle spans, resolve zoom from nearest non-idle neighbor
            if case .idle = span.intent {
                let inherited = resolveIdleZoom(
                    at: index, spans: intentSpans, settings: settings
                )
                let lastIndex = waypoints.count - 1
                let decayedCenter = waypoints[lastIndex].targetCenter
                waypoints[lastIndex] = CameraWaypoint(
                    time: span.startTime,
                    targetZoom: inherited,
                    targetCenter: decayedCenter,
                    urgency: .lazy,
                    source: .idle
                )
            }
        }

        // Sort by time (should already be sorted, but enforce)
        waypoints.sort { $0.time < $1.time }

        return waypoints
    }

    // MARK: - Urgency Mapping

    /// Map a user intent to waypoint urgency.
    static func urgency(for intent: UserIntent) -> WaypointUrgency {
        switch intent {
        case .typing:
            return .high
        case .clicking, .navigating, .scrolling, .dragging:
            return .normal
        case .switching:
            return .immediate
        case .idle, .reading:
            return .lazy
        }
    }

    // MARK: - Zoom Computation

    /// Compute zoom level for an intent span using ShotPlanner's zoom range logic.
    private static func computeZoom(
        for span: IntentSpan,
        settings: ContinuousCameraSettings
    ) -> CGFloat {
        let zoomRange = zoomRange(for: span.intent, settings: settings.shot)

        // Use midpoint of zoom range as default
        // (ShotPlanner uses element/bbox analysis, but we don't have scene context here)
        let defaultZoom = (zoomRange.lowerBound + zoomRange.upperBound) / 2
        let clamped = max(settings.minZoom, min(settings.maxZoom, defaultZoom))
        return clamped
    }

    /// Get zoom range for an intent type. Mirrors ShotPlanner.zoomRange().
    static func zoomRange(
        for intent: UserIntent, settings: ShotSettings
    ) -> ClosedRange<CGFloat> {
        switch intent {
        case .typing(let context):
            switch context {
            case .codeEditor:    return settings.typingCodeZoomRange
            case .textField:     return settings.typingTextFieldZoomRange
            case .terminal:      return settings.typingTerminalZoomRange
            case .richTextEditor: return settings.typingRichTextZoomRange
            }
        case .clicking:    return settings.clickingZoomRange
        case .navigating:  return settings.navigatingZoomRange
        case .dragging:    return settings.draggingZoomRange
        case .scrolling:   return settings.scrollingZoomRange
        case .reading:     return settings.readingZoomRange
        case .switching:   return settings.switchingZoom...settings.switchingZoom
        case .idle:        return settings.idleZoom...settings.idleZoom
        }
    }

    // MARK: - Center Computation

    /// Compute target center for an intent span.
    /// All intents use span.focusPosition — IntentClassifier already sets the
    /// correct position for idle (inherited from nearest neighbor) and switching
    /// (mouse position at switch time).
    private static func computeCenter(
        for span: IntentSpan,
        zoom: CGFloat
    ) -> NormalizedPoint {
        return ShotPlanner.clampCenter(span.focusPosition, zoom: zoom)
    }

    // MARK: - Idle Resolution

    /// Resolve zoom for idle spans by inheriting from nearest non-idle neighbor with decay.
    private static func resolveIdleZoom(
        at index: Int,
        spans: [IntentSpan],
        settings: ContinuousCameraSettings
    ) -> CGFloat {
        let decay = settings.shot.idleZoomDecay

        // Look backward for nearest non-idle
        for i in stride(from: index - 1, through: 0, by: -1) where spans[i].intent != .idle {
            let neighborZoom = computeZoom(for: spans[i], settings: settings)
            return 1.0 + (neighborZoom - 1.0) * decay
        }

        // Look forward for nearest non-idle
        for i in (index + 1)..<spans.count where spans[i].intent != .idle {
            let neighborZoom = computeZoom(for: spans[i], settings: settings)
            return 1.0 + (neighborZoom - 1.0) * decay
        }

        // No non-idle neighbors — establishing shot at zoom 1.0
        return 1.0
    }

    // MARK: - Helpers

    /// Default initial waypoint at t=0 with no zoom.
    private static func initialWaypoint() -> CameraWaypoint {
        CameraWaypoint(
            time: 0,
            targetZoom: 1.0,
            targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
            urgency: .lazy,
            source: .idle
        )
    }
}
