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
        settings: ShotSettings
    ) -> [ShotPlan] {
        var plans = scenes.map { scene in
            planScene(scene, screenBounds: screenBounds,
                      eventTimeline: eventTimeline, settings: settings)
        }
        resolveIdleScenes(&plans, settings: settings)
        return plans
    }

    // MARK: - Per-Scene Planning

    private static func planScene(
        _ scene: CameraScene,
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        settings: ShotSettings
    ) -> ShotPlan {
        let zoomRange = zoomRange(for: scene.primaryIntent, settings: settings)
        let (zoom, zoomSource) = computeZoom(
            scene: scene, zoomRange: zoomRange,
            screenBounds: screenBounds, eventTimeline: eventTimeline,
            settings: settings
        )
        let center = computeCenter(
            scene: scene, zoom: zoom, screenBounds: screenBounds,
            eventTimeline: eventTimeline, settings: settings
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

    private static func zoomRange(
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
            return settings.clickingZoom...settings.clickingZoom
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

        // 2. Activity bounding box from intent-relevant event positions
        let sceneEvents = eventTimeline.events(in: scene.startTime...scene.endTime)
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
        let minX = max(0, xs.min()! - padding)
        let maxX = min(1, xs.max()! + padding)
        let minY = max(0, ys.min()! - padding)
        let maxY = min(1, ys.max()! + padding)
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
                eventTimeline: eventTimeline, settings: settings
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

        // Prefer caret position from UIStateSample metadata
        if let lastWithCaret = sceneEvents.last(where: {
            $0.metadata.caretBounds != nil
        }), let caretBounds = lastWithCaret.metadata.caretBounds,
           let normalized = normalizeFrame(caretBounds, screenBounds: screenBounds) {
            center = NormalizedPoint(x: normalized.midX, y: normalized.midY)
        } else if let lastEvent = sceneEvents.last {
            center = lastEvent.position
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

    /// Clicking/dragging/etc: geometric centroid of event positions.
    private static func computeActivityCenter(
        scene: CameraScene,
        zoom: CGFloat,
        eventTimeline: EventTimeline,
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
        let centerX = dataPoints.map(\.x).reduce(0, +) / count
        let centerY = dataPoints.map(\.y).reduce(0, +) / count

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
