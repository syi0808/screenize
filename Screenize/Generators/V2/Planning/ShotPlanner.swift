import Foundation
import CoreGraphics

/// Determines camera shot type, zoom level, and center position for each scene.
struct ShotPlanner {

    // MARK: - Public API

    /// Plan shot parameters for each scene.
    static func plan(
        scenes: [CameraScene],
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis] = [],
        settings: ShotSettings
    ) -> [ShotPlan] {
        var plans = scenes.map { scene in
            planScene(scene, screenBounds: screenBounds,
                      eventTimeline: eventTimeline,
                      frameAnalysis: frameAnalysis, settings: settings)
        }
        resolveIdleScenes(&plans, settings: settings)
        return plans
    }

    // MARK: - Per-Scene Planning

    private static func planScene(
        _ scene: CameraScene,
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        settings: ShotSettings
    ) -> ShotPlan {
        let zoomRange = zoomRange(for: scene.primaryIntent, settings: settings)
        var (zoom, zoomSource) = computeZoom(
            scene: scene, zoomRange: zoomRange,
            screenBounds: screenBounds, eventTimeline: eventTimeline,
            settings: settings
        )

        // Reduce zoom for post-click expansions/modals to show more content
        if let change = scene.contextChange {
            zoom = adjustZoomForContextChange(
                zoom, change: change, zoomRange: zoomRange, settings: settings
            )
        }

        let center = computeCenter(
            scene: scene, zoom: zoom, screenBounds: screenBounds,
            eventTimeline: eventTimeline, frameAnalysis: frameAnalysis,
            settings: settings
        )
        let shotType = classifyShotType(zoom: zoom)

        return ShotPlan(
            scene: scene,
            shotType: shotType,
            idealZoom: zoom,
            idealCenter: center,
            zoomSource: zoomSource
        )
    }

    /// Reduce zoom when post-click UI changes expand the area of interest.
    private static func adjustZoomForContextChange(
        _ zoom: CGFloat,
        change: UIStateSample.ContextChange,
        zoomRange: ClosedRange<CGFloat>,
        settings: ShotSettings
    ) -> CGFloat {
        switch change {
        case .expansion(let ratio):
            // Scale zoom inversely with expansion ratio (capped at 0.5x reduction)
            let factor = max(0.5, 1.0 / sqrt(ratio))
            return clamp(zoom * factor, to: zoomRange, settings: settings)
        case .modalOpened:
            // Modals need room to display — use lower bound of zoom range
            return clamp(zoomRange.lowerBound, to: zoomRange, settings: settings)
        case .contraction, .none:
            return zoom
        }
    }

    // MARK: - Idle Scene Resolution

    /// Idle scenes inherit center from nearest non-idle neighbor with zoom decayed toward 1.0.
    /// Leading idles (before first non-idle) stay at zoom 1.0 as an establishing shot.
    /// Trailing idles inherit from previous non-idle with decay.
    private static func resolveIdleScenes(_ plans: inout [ShotPlan], settings: ShotSettings) {
        guard plans.count > 1 else { return }
        let decay = settings.idleZoomDecay

        let firstNonIdleIndex = plans.firstIndex { $0.scene.primaryIntent != .idle }

        // Forward pass: idle inherits from previous non-idle
        var lastNonIdleIndex: Int?
        for i in 0..<plans.count {
            if plans[i].scene.primaryIntent != .idle {
                lastNonIdleIndex = i
            } else if let prev = lastNonIdleIndex {
                plans[i] = plans[i].inheriting(from: plans[prev], decayFactor: decay)
            }
        }

        // Backward pass: only for trailing idles after last non-idle that had no forward source.
        // Leading idles (before first non-idle) stay at zoom 1.0 center (0.5, 0.5)
        // as an establishing shot — do NOT inherit from next non-idle.
        if let firstNI = firstNonIdleIndex {
            var nextNonIdleIndex: Int?
            for i in stride(from: plans.count - 1, through: 0, by: -1) {
                if plans[i].scene.primaryIntent != .idle {
                    nextNonIdleIndex = i
                } else if i >= firstNI, lastNonIdleIndex == nil {
                    // Trailing idles with no forward source
                    if let next = nextNonIdleIndex {
                        plans[i] = plans[i].inheriting(
                            from: plans[next], decayFactor: decay
                        )
                    }
                }
                // Leading idles (i < firstNI): deliberately left unchanged at zoom 1.0
            }
        }
    }

    // MARK: - Intent-Specific Event Filtering

    /// Extract positions relevant to the scene's intent, filtering out noise from mouse moves.
    /// Falls back to all event positions if no intent-specific events are found.
    private static func relevantPositions(
        for intent: UserIntent,
        events: [UnifiedEvent]
    ) -> [NormalizedPoint] {
        let filtered: [NormalizedPoint]
        switch intent {
        case .clicking, .navigating:
            let clicks = events.compactMap { event -> NormalizedPoint? in
                if case .click = event.kind { return event.position }
                return nil
            }
            filtered = clicks
        case .dragging:
            let drags = events.compactMap { event -> NormalizedPoint? in
                switch event.kind {
                case .dragStart, .dragEnd: return event.position
                default: return nil
                }
            }
            filtered = drags
        default:
            filtered = []
        }
        return filtered.isEmpty ? events.map(\.position) : filtered
    }

    // MARK: - Zoom Range by Intent

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
        case .clicking:
            return settings.clickingZoomRange
        case .navigating:
            return settings.navigatingZoomRange
        case .dragging:
            return settings.draggingZoomRange
        case .scrolling:
            return settings.scrollingZoomRange
        case .reading:
            return settings.readingZoomRange
        case .switching:
            return settings.switchingZoom...settings.switchingZoom
        case .idle:
            return settings.idleZoom...settings.idleZoom
        }
    }

    // MARK: - Zoom Computation

    private static func computeZoom(
        scene: CameraScene,
        zoomRange: ClosedRange<CGFloat>,
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        settings: ShotSettings
    ) -> (CGFloat, ZoomSource) {
        // 1. Element-based sizing (highest priority)
        if let elementRegion = scene.focusRegions.first(where: { region in
            if case .activeElement = region.source { return true }
            return false
        }), let normalizedFrame = normalizeFrame(
            elementRegion.region, screenBounds: screenBounds
        ) {
            let areaSize = max(
                normalizedFrame.width + settings.workAreaPadding * 2,
                normalizedFrame.height + settings.workAreaPadding * 2
            )
            if areaSize > 0.01 {
                let computed = settings.targetAreaCoverage / areaSize
                return (clamp(computed, to: zoomRange, settings: settings), .element)
            }
        }

        // 1.5. UIStateSample fallback: use nearest UI state element when no FocusRegion
        let sceneEvents = eventTimeline.events(in: scene.startTime...scene.endTime)
        if scene.focusRegions.first(where: { if case .activeElement = $0.source { return true }; return false }) == nil {
            if let elemFrame = nearestUIStateElementFrame(
                events: sceneEvents, screenBounds: screenBounds
            ) {
                let areaSize = max(
                    elemFrame.width + settings.workAreaPadding * 2,
                    elemFrame.height + settings.workAreaPadding * 2
                )
                if areaSize > 0.01 {
                    let computed = settings.targetAreaCoverage / areaSize
                    return (clamp(computed, to: zoomRange, settings: settings), .element)
                }
            }
        }

        // 2. Activity bounding box from intent-relevant event positions
        let positions = relevantPositions(for: scene.primaryIntent, events: sceneEvents)
        if positions.count >= 2 {
            let bbox = computeBoundingBox(
                positions: positions, padding: settings.workAreaPadding
            )
            let areaSize = max(bbox.width, bbox.height)
            if areaSize > 0.01 {
                let computed = settings.targetAreaCoverage / areaSize
                return (clamp(computed, to: zoomRange, settings: settings), .activityBBox)
            }
        }

        // 3. Single event: use intent range lower bound directly
        if positions.count == 1 {
            return (clamp(zoomRange.lowerBound, to: zoomRange, settings: settings), .singleEvent)
        }

        // 4. Fallback: midpoint of the intent range
        let defaultZoom = (zoomRange.lowerBound + zoomRange.upperBound) / 2
        return (clamp(defaultZoom, to: zoomRange, settings: settings), .intentMidpoint)
    }

    /// Compute bounding box from a set of normalized positions with padding.
    private static func computeBoundingBox(
        positions: [NormalizedPoint],
        padding: CGFloat
    ) -> CGRect {
        guard !positions.isEmpty else { return .zero }
        let xs = positions.map(\.x)
        let ys = positions.map(\.y)
        guard let xMin = xs.min(), let xMax = xs.max(),
              let yMin = ys.min(), let yMax = ys.max() else { return .zero }
        let minX = max(0, xMin - padding)
        let maxX = min(1, xMax + padding)
        let minY = max(0, yMin - padding)
        let maxY = min(1, yMax + padding)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Normalize a pixel-space frame to 0-1 space. Returns nil if the result is out of valid range
    /// (e.g. global screen coordinates that can't be mapped to display-local space).
    private static func normalizeFrame(
        _ frame: CGRect, screenBounds: CGSize
    ) -> CGRect? {
        // Detect if the frame is already normalized (values in 0-1 range)
        if frame.maxX <= 1.1 && frame.maxY <= 1.1 && frame.minX >= -0.1 && frame.minY >= -0.1 {
            return frame
        }
        guard screenBounds.width > 0, screenBounds.height > 0 else { return nil }
        let normalized = CGRect(
            x: frame.origin.x / screenBounds.width,
            y: frame.origin.y / screenBounds.height,
            width: frame.width / screenBounds.width,
            height: frame.height / screenBounds.height
        )
        // Validate: origin must be within [0,1] range to be a valid display-local frame
        guard normalized.origin.x >= -0.1 && normalized.origin.x <= 1.1 &&
              normalized.origin.y >= -0.1 && normalized.origin.y <= 1.1 else {
            return nil
        }
        return normalized
    }

    private static func clamp(
        _ zoom: CGFloat,
        to range: ClosedRange<CGFloat>,
        settings: ShotSettings
    ) -> CGFloat {
        let ranged = min(max(zoom, range.lowerBound), range.upperBound)
        return min(max(ranged, settings.minZoom), settings.maxZoom)
    }

    // MARK: - Center Computation

    private static func computeCenter(
        scene: CameraScene,
        zoom: CGFloat,
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        settings: ShotSettings
    ) -> NormalizedPoint {
        switch scene.primaryIntent {
        case .idle, .switching:
            return NormalizedPoint(x: 0.5, y: 0.5)

        case .typing:
            return computeTypingCenter(
                scene: scene, zoom: zoom, screenBounds: screenBounds,
                eventTimeline: eventTimeline, settings: settings
            )

        default:
            return computeActivityCenter(
                scene: scene, zoom: zoom,
                eventTimeline: eventTimeline, frameAnalysis: frameAnalysis,
                settings: settings
            )
        }
    }

    /// Typing: use caret bounds or last mouse position, constrained to keep element visible.
    private static func computeTypingCenter(
        scene: CameraScene,
        zoom: CGFloat,
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        settings: ShotSettings
    ) -> NormalizedPoint {
        let sceneEvents = eventTimeline.events(in: scene.startTime...scene.endTime)
        var center: NormalizedPoint

        // Prefer first caret position: CursorFollowController starts at idealCenter
        // and pans forward, so the camera should start where typing begins.
        if let firstWithCaret = sceneEvents.first(where: {
            $0.metadata.caretBounds != nil
        }), let caretBounds = firstWithCaret.metadata.caretBounds,
           let normalized = normalizeFrame(caretBounds, screenBounds: screenBounds) {
            center = NormalizedPoint(x: normalized.midX, y: normalized.midY)
        } else if let firstEvent = sceneEvents.first {
            center = firstEvent.position
        } else {
            // Fallback to focus region cursor position
            let cursorRegions = scene.focusRegions.filter {
                if case .cursorPosition = $0.source { return true }
                return false
            }
            let lastCursor = cursorRegions.last
            center = NormalizedPoint(
                x: lastCursor?.region.midX ?? 0.5,
                y: lastCursor?.region.midY ?? 0.5
            )
        }

        // Constrain to show element if available
        if let elementRegion = scene.focusRegions.first(where: { region in
            if case .activeElement = region.source { return true }
            return false
        }), let normalizedBounds = normalizeFrame(
            elementRegion.region, screenBounds: screenBounds
        ) {
            center = constrainCenterToShowElement(
                desiredCenter: center,
                elementBounds: normalizedBounds,
                zoom: zoom,
                padding: settings.workAreaPadding
            )
        }

        return clampCenter(center, zoom: zoom)
    }

    /// Clicking/dragging/etc: geometric centroid of event positions, optionally blended with saliency.
    private static func computeActivityCenter(
        scene: CameraScene,
        zoom: CGFloat,
        eventTimeline: EventTimeline,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        settings: ShotSettings
    ) -> NormalizedPoint {
        // Use intent-relevant event positions; fall back to focus regions
        let sceneEvents = eventTimeline.events(in: scene.startTime...scene.endTime)
        let relevant = relevantPositions(
            for: scene.primaryIntent, events: sceneEvents
        )
        let dataPoints: [NormalizedPoint]
        if !relevant.isEmpty {
            dataPoints = relevant
        } else {
            let regions = scene.focusRegions
            guard !regions.isEmpty else {
                return clampCenter(NormalizedPoint(x: 0.5, y: 0.5), zoom: zoom)
            }
            dataPoints = regions.map {
                NormalizedPoint(x: $0.region.midX, y: $0.region.midY)
            }
        }

        // Geometric centroid (equal weight for all positions)
        let count = CGFloat(dataPoints.count)
        var centerX = dataPoints.map(\.x).reduce(0, +) / count
        var centerY = dataPoints.map(\.y).reduce(0, +) / count

        // Blend with saliency center when no element info is available
        let hasElementInfo = scene.focusRegions.contains {
            if case .activeElement = $0.source { return true }
            return false
        }
        if !hasElementInfo, let saliency = nearestSaliencyCenter(
            for: scene, frameAnalysis: frameAnalysis
        ) {
            let weight: CGFloat = 0.3
            centerX = centerX * (1 - weight) + saliency.x * weight
            centerY = centerY * (1 - weight) + saliency.y * weight
        }

        let center = NormalizedPoint(x: centerX, y: centerY)
        return clampCenter(center, zoom: zoom)
    }

    // MARK: - Viewport Constraints

    /// Clamp center so the viewport stays within [0, 1] at the given zoom.
    /// Ported from SessionCenterResolver.constrainCenterToShowElement.
    static func constrainCenterToShowElement(
        desiredCenter: NormalizedPoint,
        elementBounds: CGRect,
        zoom: CGFloat,
        padding: CGFloat = 0.08
    ) -> NormalizedPoint {
        guard zoom > 1.0 else { return desiredCenter }

        let paddedBounds = CGRect(
            x: max(0, elementBounds.minX - padding),
            y: max(0, elementBounds.minY - padding),
            width: min(1.0, elementBounds.width + padding * 2),
            height: min(1.0, elementBounds.height + padding * 2)
        )

        let halfViewportW = 0.5 / zoom
        let halfViewportH = 0.5 / zoom

        let minCenterX = paddedBounds.maxX - halfViewportW
        let maxCenterX = paddedBounds.minX + halfViewportW
        let minCenterY = paddedBounds.maxY - halfViewportH
        let maxCenterY = paddedBounds.minY + halfViewportH

        var constrainedX = desiredCenter.x
        var constrainedY = desiredCenter.y

        if minCenterX <= maxCenterX {
            constrainedX = max(minCenterX, min(maxCenterX, desiredCenter.x))
        } else {
            constrainedX = paddedBounds.midX
        }

        if minCenterY <= maxCenterY {
            constrainedY = max(minCenterY, min(maxCenterY, desiredCenter.y))
        } else {
            constrainedY = paddedBounds.midY
        }

        return NormalizedPoint(x: constrainedX, y: constrainedY)
    }

    /// Clamp center so the viewport [center - 0.5/zoom, center + 0.5/zoom] stays in [0, 1].
    static func clampCenter(
        _ center: NormalizedPoint, zoom: CGFloat
    ) -> NormalizedPoint {
        guard zoom > 1.0 else { return center }
        let halfCrop = 0.5 / zoom
        let x = max(halfCrop, min(1.0 - halfCrop, center.x))
        let y = max(halfCrop, min(1.0 - halfCrop, center.y))
        return NormalizedPoint(x: x, y: y)
    }

    // MARK: - Saliency Lookup

    /// Find the nearest saliency center from frame analysis within a scene's time range.
    private static func nearestSaliencyCenter(
        for scene: CameraScene,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis]
    ) -> NormalizedPoint? {
        let sceneMidTime = (scene.startTime + scene.endTime) / 2
        var best: (distance: TimeInterval, center: CGPoint)?
        for analysis in frameAnalysis {
            guard let saliencyCenter = analysis.saliencyCenter else { continue }
            let dist = abs(analysis.time - sceneMidTime)
            if best == nil || dist < best!.distance {
                best = (dist, saliencyCenter)
            }
        }
        guard let result = best else { return nil }
        // FrameAnalysis.saliencyCenter is normalized (0-1) with top-left origin Y
        // Convert to bottom-left origin to match NormalizedPoint convention
        return NormalizedPoint(x: CGFloat(result.center.x), y: 1.0 - CGFloat(result.center.y))
    }

    // MARK: - UIStateSample Element Lookup

    /// Find the nearest UI state element frame (normalized) from events in a scene.
    private static func nearestUIStateElementFrame(
        events: [UnifiedEvent],
        screenBounds: CGSize
    ) -> CGRect? {
        for event in events {
            if case .uiStateChange(let sample) = event.kind,
               let info = sample.elementInfo {
                return normalizeFrame(info.frame, screenBounds: screenBounds)
            }
        }
        // Fallback: check click events that carry element info
        for event in events {
            if case .click = event.kind,
               let info = event.metadata.elementInfo {
                return normalizeFrame(info.frame, screenBounds: screenBounds)
            }
        }
        return nil
    }

    // MARK: - Shot Type Classification

    private static func classifyShotType(zoom: CGFloat) -> ShotType {
        if zoom > 2.0 {
            return .closeUp(zoom: zoom)
        } else if zoom > 1.0 {
            return .medium(zoom: zoom)
        } else {
            return .wide
        }
    }
}
