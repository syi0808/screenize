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
        scenes.map { scene in
            planScene(scene, screenBounds: screenBounds,
                      eventTimeline: eventTimeline, settings: settings)
        }
    }

    // MARK: - Per-Scene Planning

    private static func planScene(
        _ scene: CameraScene,
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        settings: ShotSettings
    ) -> ShotPlan {
        let zoomRange = zoomRange(for: scene.primaryIntent, settings: settings)
        let zoom = computeZoom(
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
            idealCenter: center
        )
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
    ) -> CGFloat {
        // 1. Element-based sizing (highest priority)
        if let elementRegion = scene.focusRegions.first(where: { region in
            if case .activeElement = region.source { return true }
            return false
        }) {
            let normalizedFrame = normalizeFrame(
                elementRegion.region, screenBounds: screenBounds
            )
            let areaSize = max(
                normalizedFrame.width + settings.workAreaPadding * 2,
                normalizedFrame.height + settings.workAreaPadding * 2
            )
            if areaSize > 0.01 {
                let computed = settings.targetAreaCoverage / areaSize
                return clamp(computed, to: zoomRange, settings: settings)
            }
        }

        // 2. Activity bounding box from event positions
        let sceneEvents = eventTimeline.events(in: scene.startTime...scene.endTime)
        let positions = sceneEvents.map(\.position)
        if positions.count >= 2 {
            let bbox = computeBoundingBox(
                positions: positions, padding: settings.workAreaPadding
            )
            let areaSize = max(bbox.width, bbox.height)
            if areaSize > 0.01 {
                let computed = settings.targetAreaCoverage / areaSize
                return clamp(computed, to: zoomRange, settings: settings)
            }
        }

        // 3. Fallback: midpoint of the intent range
        let defaultZoom = (zoomRange.lowerBound + zoomRange.upperBound) / 2
        return clamp(defaultZoom, to: zoomRange, settings: settings)
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

    /// Normalize a pixel-space frame to 0-1 space. If frame is already in 0-1, return as-is.
    private static func normalizeFrame(
        _ frame: CGRect, screenBounds: CGSize
    ) -> CGRect {
        // Detect if the frame is already normalized (values in 0-1 range)
        if frame.maxX <= 1.1 && frame.maxY <= 1.1 && frame.minX >= -0.1 && frame.minY >= -0.1 {
            return frame
        }
        guard screenBounds.width > 0, screenBounds.height > 0 else { return frame }
        return CGRect(
            x: frame.origin.x / screenBounds.width,
            y: frame.origin.y / screenBounds.height,
            width: frame.width / screenBounds.width,
            height: frame.height / screenBounds.height
        )
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

    /// Typing: use last mouse position from timeline, constrained to keep element visible.
    private static func computeTypingCenter(
        scene: CameraScene,
        zoom: CGFloat,
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        settings: ShotSettings
    ) -> NormalizedPoint {
        // Prefer last mouse position from EventTimeline
        let sceneEvents = eventTimeline.events(in: scene.startTime...scene.endTime)
        var center: NormalizedPoint
        if let lastEvent = sceneEvents.last {
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
        }) {
            let normalizedBounds = normalizeFrame(
                elementRegion.region, screenBounds: screenBounds
            )
            center = constrainCenterToShowElement(
                desiredCenter: center,
                elementBounds: normalizedBounds,
                zoom: zoom,
                padding: settings.workAreaPadding
            )
        }

        return clampCenter(center, zoom: zoom)
    }

    /// Clicking/dragging/etc: weighted average of event positions with recency bias.
    private static func computeActivityCenter(
        scene: CameraScene,
        zoom: CGFloat,
        eventTimeline: EventTimeline,
        settings: ShotSettings
    ) -> NormalizedPoint {
        // Use event positions if available; else fall back to focus regions
        let sceneEvents = eventTimeline.events(in: scene.startTime...scene.endTime)
        let dataPoints: [NormalizedPoint]
        if sceneEvents.count >= 2 {
            dataPoints = sceneEvents.map(\.position)
        } else {
            let regions = scene.focusRegions
            guard !regions.isEmpty else {
                return clampCenter(NormalizedPoint(x: 0.5, y: 0.5), zoom: zoom)
            }
            dataPoints = regions.map {
                NormalizedPoint(x: $0.region.midX, y: $0.region.midY)
            }
        }

        // Weighted average with recency bias
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0
        var totalWeight: CGFloat = 0

        for (index, pos) in dataPoints.enumerated() {
            let weight: CGFloat = 1.0 + CGFloat(index) * 0.5
            weightedX += pos.x * weight
            weightedY += pos.y * weight
            totalWeight += weight
        }

        let center = NormalizedPoint(
            x: weightedX / totalWeight,
            y: weightedY / totalWeight
        )
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
