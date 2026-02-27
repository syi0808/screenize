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
        let useCaretTracking: Bool
        if case .typing = scene.primaryIntent {
            useCaretTracking = sceneEvents.contains {
                eventHasCaretData($0)
            }
        } else {
            useCaretTracking = false
        }

        // During typing, prefer caret-driven events when caret metadata exists.
        // If caret data is unavailable, fall back to mouse movement.
        let panTriggerEvents: [UnifiedEvent]
        if case .typing = scene.primaryIntent {
            if useCaretTracking {
                panTriggerEvents = sceneEvents.filter { event in
                    switch event.kind {
                    case .keyDown, .uiStateChange, .click:
                        return true
                    case .mouseMove:
                        return eventHasCaretData(event)
                    default:
                        return false
                    }
                }
            } else {
                panTriggerEvents = sceneEvents.filter { event in
                    switch event.kind {
                    case .mouseMove, .click:
                        return true
                    default:
                        return false
                    }
                }
            }
        } else {
            panTriggerEvents = sceneEvents
        }

        var lastPanTime: TimeInterval = -.greatestFiniteMagnitude
        var previousTracked: (time: TimeInterval, position: NormalizedPoint)?

        for event in panTriggerEvents {
            guard let trackedPosition = extractTrackedPosition(
                event: event,
                screenBounds: settings.screenBounds,
                preferCaret: useCaretTracking
            ) else { continue }
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
            let msg = String(
                format: "[V2-CursorFollow] t=%.2f dist=%.3f dur=%.2fs (%.2f,%.2f)→(%.2f,%.2f)",
                event.time, distance, panDuration,
                currentCenter.x, currentCenter.y, newCenter.x, newCenter.y
            )
            Log.generator.debug("\(msg)")
            #endif

            let panStart = event.time
            let panEnd = min(panStart + panDuration, scene.endTime)

            // Only emit "hold at old center" if previous pan has finished
            if panStart >= lastPanTime {
                samples.append(TimedTransform(
                    time: panStart, transform: TransformValue(zoom: zoom, center: currentCenter)
                ))
            }
            samples.append(TimedTransform(
                time: panEnd, transform: TransformValue(zoom: zoom, center: newCenter)
            ))
            currentCenter = newCenter
            lastPanTime = panEnd
        }

        // Ensure chronological order after overlapping pan corrections
        samples.sort { $0.time < $1.time }

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

    /// Resolve tracked position for follow panning.
    /// For typing scenes, caret data is preferred when available.
    private func extractTrackedPosition(
        event: UnifiedEvent,
        screenBounds: CGSize,
        preferCaret: Bool
    ) -> NormalizedPoint? {
        if preferCaret {
            if let caret = caretBounds(in: event),
               let center = normalizedCenter(
                from: caret, screenBounds: screenBounds
               ) {
                return center
            }

            switch event.kind {
            case .keyDown, .uiStateChange:
                return nil
            default:
                break
            }
        }

        return event.position
    }

    private func eventHasCaretData(_ event: UnifiedEvent) -> Bool {
        caretBounds(in: event) != nil
    }

    private func caretBounds(in event: UnifiedEvent) -> CGRect? {
        if let bounds = event.metadata.caretBounds {
            return bounds
        }
        if case .uiStateChange(let sample) = event.kind {
            return sample.caretBounds
        }
        return nil
    }

    private func normalizedCenter(
        from frame: CGRect,
        screenBounds: CGSize
    ) -> NormalizedPoint? {
        guard let normalized = normalizeFrame(frame, screenBounds: screenBounds) else {
            return nil
        }
        return NormalizedPoint(x: normalized.midX, y: normalized.midY)
    }

    private func normalizeFrame(
        _ frame: CGRect,
        screenBounds: CGSize
    ) -> CGRect? {
        if frame.maxX <= 1.1 && frame.maxY <= 1.1
            && frame.minX >= -0.1 && frame.minY >= -0.1 {
            return frame
        }

        guard screenBounds.width > 0, screenBounds.height > 0 else {
            return nil
        }

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

}
