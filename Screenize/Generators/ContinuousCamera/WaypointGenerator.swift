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

        // First pass: compute non-idle base transforms.
        var baseTransforms = [TransformValue?](
            repeating: nil,
            count: intentSpans.count
        )
        for (index, span) in intentSpans.enumerated() {
            if case .idle = span.intent { continue }
            baseTransforms[index] = preferredTransform(
                for: span,
                screenBounds: screenBounds,
                eventTimeline: eventTimeline,
                frameAnalysis: frameAnalysis,
                settings: settings
            )
        }

        // Second pass: emit entry waypoints and in-span detail anchors.
        for (index, span) in intentSpans.enumerated() {
            let transform: TransformValue
            if case .idle = span.intent {
                let inherited = resolveIdleZoom(
                    at: index,
                    spans: intentSpans,
                    baseTransforms: baseTransforms,
                    settings: settings
                )
                transform = TransformValue(
                    zoom: inherited,
                    center: computeCenter(for: span, zoom: inherited)
                )
            } else {
                transform = baseTransforms[index]
                    ?? preferredTransform(
                        for: span,
                        screenBounds: screenBounds,
                        eventTimeline: eventTimeline,
                        frameAnalysis: frameAnalysis,
                        settings: settings
                    )
            }

            let baseUrgency = urgency(for: span.intent)
            let entryTime = max(
                0,
                span.startTime - entryLeadTime(for: baseUrgency)
            )
            let waypoint = CameraWaypoint(
                time: entryTime,
                targetZoom: transform.zoom,
                targetCenter: transform.center,
                urgency: baseUrgency,
                source: span.intent
            )
            waypoints.append(waypoint)

            if let timeline = eventTimeline {
                if case .typing = span.intent {
                    waypoints.append(contentsOf: typingDetailWaypoints(
                        for: span,
                        baseTransform: transform,
                        eventTimeline: timeline,
                        screenBounds: screenBounds,
                        settings: settings
                    ))
                } else {
                    waypoints.append(contentsOf: activityDetailWaypoints(
                        for: span,
                        baseTransform: transform,
                        eventTimeline: timeline,
                        settings: settings
                    ))
                }
            }
        }

        return sortAndCoalesce(waypoints)
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

    /// Move high-urgency targets slightly earlier so the camera starts before the action.
    private static func entryLeadTime(for urgency: WaypointUrgency) -> TimeInterval {
        switch urgency {
        case .immediate:
            return 0.24
        case .high:
            return 0.16
        case .normal:
            return 0.08
        case .lazy:
            return 0.0
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

    private static func preferredTransform(
        for span: IntentSpan,
        screenBounds: CGSize,
        eventTimeline: EventTimeline?,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        settings: ContinuousCameraSettings
    ) -> TransformValue {
        if case .switching = span.intent {
            let zoom = clampZoom(settings.shot.switchingZoom, settings: settings)
            let center = computeCenter(for: span, zoom: zoom)
            return TransformValue(zoom: zoom, center: center)
        }

        if let timeline = eventTimeline,
           let planned = plannedTransform(
            for: span,
            screenBounds: screenBounds,
            eventTimeline: timeline,
            frameAnalysis: frameAnalysis,
            settings: settings
           ) {
            return planned
        }

        let zoom = computeZoom(for: span, settings: settings)
        let center = computeCenter(for: span, zoom: zoom)
        return TransformValue(zoom: zoom, center: center)
    }

    private static func plannedTransform(
        for span: IntentSpan,
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        settings: ContinuousCameraSettings
    ) -> TransformValue? {
        var focusRegions: [FocusRegion] = [
            FocusRegion(
                time: span.startTime,
                region: CGRect(
                    x: span.focusPosition.x - 0.05,
                    y: span.focusPosition.y - 0.05,
                    width: 0.1,
                    height: 0.1
                ),
                confidence: span.confidence,
                source: .cursorPosition
            )
        ]

        if let element = span.focusElement {
            focusRegions.append(
                FocusRegion(
                    time: span.startTime,
                    region: element.frame,
                    confidence: span.confidence,
                    source: .activeElement(element)
                )
            )
        }

        let appContext = eventTimeline.events(in: span.startTime...span.endTime)
            .first { $0.metadata.appBundleID != nil }?.metadata.appBundleID

        let scene = CameraScene(
            startTime: span.startTime,
            endTime: span.endTime,
            primaryIntent: span.intent,
            focusRegions: focusRegions,
            appContext: appContext,
            contextChange: span.contextChange
        )

        let plan = ShotPlanner.plan(
            scenes: [scene],
            screenBounds: screenBounds,
            eventTimeline: eventTimeline,
            frameAnalysis: frameAnalysis,
            settings: settings.shot
        ).first

        guard let plan else { return nil }
        let zoom = clampZoom(plan.idealZoom, settings: settings)
        let center = ShotPlanner.clampCenter(plan.idealCenter, zoom: zoom)
        return TransformValue(zoom: zoom, center: center)
    }

    private static func typingDetailWaypoints(
        for span: IntentSpan,
        baseTransform: TransformValue,
        eventTimeline: EventTimeline,
        screenBounds: CGSize,
        settings: ContinuousCameraSettings
    ) -> [CameraWaypoint] {
        let events = eventTimeline.events(in: span.startTime...span.endTime)
        guard !events.isEmpty else { return [] }

        var results: [CameraWaypoint] = []
        var lastTime = span.startTime
        var lastCenter = baseTransform.center

        for event in events {
            guard event.time - span.startTime > 0.05 else { continue }
            guard let caret = caretBounds(in: event),
                  let normalized = normalizeFrame(
                    caret, screenBounds: screenBounds
                  ) else { continue }

            let center = ShotPlanner.clampCenter(
                NormalizedPoint(x: normalized.midX, y: normalized.midY),
                zoom: baseTransform.zoom
            )
            let distance = center.distance(to: lastCenter)
            let delta = event.time - lastTime
            guard delta >= settings.typingDetailMinInterval,
                  distance >= settings.typingDetailMinDistance else {
                continue
            }

            results.append(CameraWaypoint(
                time: event.time,
                targetZoom: baseTransform.zoom,
                targetCenter: center,
                urgency: .high,
                source: span.intent
            ))
            lastTime = event.time
            lastCenter = center
        }

        return results
    }

    private static func activityDetailWaypoints(
        for span: IntentSpan,
        baseTransform: TransformValue,
        eventTimeline: EventTimeline,
        settings: ContinuousCameraSettings
    ) -> [CameraWaypoint] {
        let anchors = detailAnchorEvents(
            for: span.intent,
            events: eventTimeline.events(in: span.startTime...span.endTime)
        )
        guard !anchors.isEmpty else { return [] }

        let minInterval = max(0.12, settings.typingDetailMinInterval * 0.75)
        let minDistance = max(0.02, settings.typingDetailMinDistance * 0.8)
        let urgency = urgency(for: span.intent)

        var results: [CameraWaypoint] = []
        var lastTime = span.startTime
        var lastCenter = baseTransform.center

        for (index, anchor) in anchors.enumerated() {
            let center = ShotPlanner.clampCenter(
                anchor.position,
                zoom: baseTransform.zoom
            )
            let delta = anchor.time - lastTime
            let distance = center.distance(to: lastCenter)
            let isBoundaryAnchor = index == 0 || index == anchors.count - 1
            guard isBoundaryAnchor || (delta >= minInterval && distance >= minDistance)
            else {
                continue
            }

            results.append(CameraWaypoint(
                time: anchor.time,
                targetZoom: baseTransform.zoom,
                targetCenter: center,
                urgency: urgency,
                source: span.intent
            ))
            lastTime = anchor.time
            lastCenter = center
        }

        return results
    }

    private static func detailAnchorEvents(
        for intent: UserIntent,
        events: [UnifiedEvent]
    ) -> [(time: TimeInterval, position: NormalizedPoint)] {
        switch intent {
        case .clicking, .navigating:
            return events.compactMap { event in
                if case .click(let click) = event.kind,
                   click.clickType == .leftDown {
                    return (event.time, event.position)
                }
                return nil
            }
        case .dragging:
            return events.compactMap { event in
                switch event.kind {
                case .dragStart, .dragEnd:
                    return (event.time, event.position)
                default:
                    return nil
                }
            }
        case .scrolling:
            return events.compactMap { event in
                if case .scroll = event.kind {
                    return (event.time, event.position)
                }
                return nil
            }
        default:
            return []
        }
    }

    private static func caretBounds(in event: UnifiedEvent) -> CGRect? {
        if let bounds = event.metadata.caretBounds {
            return bounds
        }
        if case .uiStateChange(let sample) = event.kind {
            return sample.caretBounds
        }
        return nil
    }

    private static func normalizeFrame(
        _ frame: CGRect,
        screenBounds: CGSize
    ) -> CGRect? {
        if frame.maxX <= 1.1 && frame.maxY <= 1.1
            && frame.minX >= -0.1 && frame.minY >= -0.1 {
            return frame
        }

        guard screenBounds.width > 0, screenBounds.height > 0 else { return nil }
        let normalized = CGRect(
            x: frame.origin.x / screenBounds.width,
            y: frame.origin.y / screenBounds.height,
            width: frame.width / screenBounds.width,
            height: frame.height / screenBounds.height
        )
        guard normalized.origin.x >= -0.1 && normalized.origin.x <= 1.1
            && normalized.origin.y >= -0.1 && normalized.origin.y <= 1.1 else {
            return nil
        }
        return normalized
    }

    // MARK: - Idle Resolution

    /// Resolve zoom for idle spans by inheriting from nearest non-idle neighbor with decay.
    private static func resolveIdleZoom(
        at index: Int,
        spans: [IntentSpan],
        baseTransforms: [TransformValue?],
        settings: ContinuousCameraSettings
    ) -> CGFloat {
        let decay = settings.shot.idleZoomDecay

        // Look backward for nearest non-idle
        for i in stride(from: index - 1, through: 0, by: -1) where spans[i].intent != .idle {
            let neighborZoom = baseTransforms[i]?.zoom
                ?? computeZoom(for: spans[i], settings: settings)
            return 1.0 + (neighborZoom - 1.0) * decay
        }

        // Look forward for nearest non-idle
        for i in (index + 1)..<spans.count where spans[i].intent != .idle {
            let neighborZoom = baseTransforms[i]?.zoom
                ?? computeZoom(for: spans[i], settings: settings)
            return 1.0 + (neighborZoom - 1.0) * decay
        }

        // No non-idle neighbors — establishing shot at zoom 1.0
        return 1.0
    }

    private static func clampZoom(
        _ zoom: CGFloat,
        settings: ContinuousCameraSettings
    ) -> CGFloat {
        max(settings.minZoom, min(settings.maxZoom, zoom))
    }

    private static func sortAndCoalesce(
        _ waypoints: [CameraWaypoint]
    ) -> [CameraWaypoint] {
        guard !waypoints.isEmpty else { return [] }
        let sorted = waypoints.sorted { lhs, rhs in
            if abs(lhs.time - rhs.time) < 0.0001 {
                return lhs.urgency.rawValue > rhs.urgency.rawValue
            }
            return lhs.time < rhs.time
        }

        var result: [CameraWaypoint] = [sorted[0]]
        for waypoint in sorted.dropFirst() {
            guard let last = result.last else {
                result.append(waypoint)
                continue
            }
            if abs(last.time - waypoint.time) < 0.0001 {
                if waypoint.urgency.rawValue >= last.urgency.rawValue {
                    result[result.count - 1] = waypoint
                }
            } else {
                result.append(waypoint)
            }
        }
        return result
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
