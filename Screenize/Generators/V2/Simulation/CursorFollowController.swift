import Foundation
import CoreGraphics

/// Camera controller that follows the caret/cursor during typing and dragging scenes.
///
/// Starts at the shot plan's ideal zoom/center, then pans when the tracked position
/// moves outside the current viewport. Uses caret bounds when available, falling back
/// to mouse position.
struct CursorFollowController: CameraController {

    /// Minimum time between consecutive pans to prevent jitter.
    private let minMoveInterval: TimeInterval = 0.15

    /// Minimum pan animation duration.
    private let minPanDuration: TimeInterval = 0.10

    /// Maximum pan animation duration.
    private let maxPanDuration: TimeInterval = 0.40

    /// Distance multiplier to compute pan duration: duration = distance * panDurationScale.
    private let panDurationScale: CGFloat = 1.2

    /// Margin inside viewport edge before triggering a pan (fraction of viewport).
    private let viewportMargin: CGFloat = 0.05

    /// Partial correction fraction: 0 = move to edge only, 1 = move to center.
    /// 0.6 means each pan only moves 60% toward the ideal center, keeping pans gentle.
    private let correctionFraction: CGFloat = 0.6

    /// Look-ahead duration for predictive panning (seconds).
    private let lookAheadTime: TimeInterval = 0.2

    func simulate(
        scene: CameraScene,
        shotPlan: ShotPlan,
        mouseData: MouseDataSource,
        settings: SimulationSettings
    ) -> [TimedTransform] {
        let zoom = shotPlan.idealZoom
        var currentCenter = shotPlan.idealCenter
        var samples: [TimedTransform] = []

        // Start at shot plan position
        samples.append(TimedTransform(
            time: scene.startTime,
            transform: TransformValue(zoom: zoom, center: currentCenter)
        ))

        guard let timeline = settings.eventTimeline,
              zoom > 1.0 else {
            // No timeline or no zoom → static hold
            samples.append(TimedTransform(
                time: scene.endTime,
                transform: TransformValue(zoom: zoom, center: currentCenter)
            ))
            return samples
        }

        // Get events in scene range
        let sceneEvents = timeline.events(in: scene.startTime...scene.endTime)

        var lastPanTime: TimeInterval = -.greatestFiniteMagnitude
        var previousTracked: (time: TimeInterval, position: NormalizedPoint)?

        for event in sceneEvents {
            let trackedPosition = extractTrackedPosition(
                event: event, screenBounds: settings.screenBounds
            )
            let checkPosition = predictedPosition(
                current: trackedPosition, eventTime: event.time, previous: previousTracked
            )
            previousTracked = (time: event.time, position: trackedPosition)

            guard checkPosition.isOutsideViewport(
                zoom: zoom, center: currentCenter, margin: viewportMargin
            ) else { continue }
            guard event.time - lastPanTime >= minMoveInterval else { continue }

            let distance = trackedPosition.distance(to: currentCenter)
            let panDuration = min(maxPanDuration, max(minPanDuration, Double(distance * panDurationScale)))
            let newCenter = computePartialCorrection(
                tracked: trackedPosition, current: currentCenter, zoom: zoom
            )

            #if DEBUG
            print(String(
                format: "[V2-CursorFollow] t=%.2f dist=%.3f dur=%.2fs (%.2f,%.2f)→(%.2f,%.2f)",
                event.time, distance, panDuration,
                currentCenter.x, currentCenter.y, newCenter.x, newCenter.y
            ))
            #endif

            let panStart = event.time
            let panEnd = min(panStart + panDuration, scene.endTime)
            samples.append(TimedTransform(
                time: panStart, transform: TransformValue(zoom: zoom, center: currentCenter)
            ))
            samples.append(TimedTransform(
                time: panEnd, transform: TransformValue(zoom: zoom, center: newCenter)
            ))
            currentCenter = newCenter
            lastPanTime = panStart
        }

        // End at current position
        let lastTime = samples.last?.time ?? scene.startTime
        if lastTime < scene.endTime {
            samples.append(TimedTransform(
                time: scene.endTime,
                transform: TransformValue(zoom: zoom, center: currentCenter)
            ))
        }

        return samples
    }

    // MARK: - Helpers

    private func extractTrackedPosition(
        event: UnifiedEvent, screenBounds: CGSize
    ) -> NormalizedPoint {
        if let caretBounds = event.metadata.caretBounds,
           let normalized = normalizeBoundsIfNeeded(caretBounds, screenBounds: screenBounds) {
            return NormalizedPoint(x: normalized.midX, y: normalized.midY)
        }
        return event.position
    }

    private func predictedPosition(
        current: NormalizedPoint,
        eventTime: TimeInterval,
        previous: (time: TimeInterval, position: NormalizedPoint)?
    ) -> NormalizedPoint {
        guard let prev = previous else { return current }
        let dt = eventTime - prev.time
        guard dt > 0.01 else { return current }
        let vx = (current.x - prev.position.x) / CGFloat(dt)
        let vy = (current.y - prev.position.y) / CGFloat(dt)
        return NormalizedPoint(
            x: max(0, min(1, current.x + vx * CGFloat(lookAheadTime))),
            y: max(0, min(1, current.y + vy * CGFloat(lookAheadTime)))
        )
    }

    private func computePartialCorrection(
        tracked: NormalizedPoint, current: NormalizedPoint, zoom: CGFloat
    ) -> NormalizedPoint {
        let full = tracked.centerToIncludeInViewport(
            zoom: zoom, currentCenter: current, padding: viewportMargin
        )
        let blended = NormalizedPoint(
            x: current.x + (full.x - current.x) * correctionFraction,
            y: current.y + (full.y - current.y) * correctionFraction
        )
        return ShotPlanner.clampCenter(blended, zoom: zoom)
    }

    /// Normalize caret bounds from pixel space to 0-1 if needed.
    /// Returns nil if the result is out of valid range (e.g. global screen coordinates).
    private func normalizeBoundsIfNeeded(
        _ bounds: CGRect, screenBounds: CGSize
    ) -> CGRect? {
        // Already normalized (values in 0-1 range)
        if bounds.maxX <= 1.1 && bounds.maxY <= 1.1 &&
            bounds.minX >= -0.1 && bounds.minY >= -0.1 {
            return bounds
        }
        guard screenBounds.width > 0, screenBounds.height > 0 else { return nil }
        let normalized = CGRect(
            x: bounds.origin.x / screenBounds.width,
            y: bounds.origin.y / screenBounds.height,
            width: bounds.width / screenBounds.width,
            height: bounds.height / screenBounds.height
        )
        // Validate: origin must be within [0,1] range
        guard normalized.origin.x >= -0.1 && normalized.origin.x <= 1.1 &&
              normalized.origin.y >= -0.1 && normalized.origin.y <= 1.1 else {
            return nil
        }
        return normalized
    }
}
