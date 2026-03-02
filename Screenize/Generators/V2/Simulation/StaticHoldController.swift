import Foundation
import CoreGraphics

/// Camera controller that primarily holds a fixed position but tracks the cursor
/// to prevent it from going off-screen during clicking/navigating/scrolling scenes.
///
/// When zoom > 1.0 and an event timeline is available, monitors mouse positions
/// and pans the camera when the cursor approaches the viewport edge. Uses more
/// conservative parameters than CursorFollowController to preserve a "holding" feel.
/// Falls back to pure static hold when zoom <= 1.0 or no timeline is available.
struct StaticHoldController: CameraController {

    /// Margin inside viewport edge before triggering a pan (fraction of viewport).
    /// More conservative than CursorFollowController's 0.05.
    private let viewportMargin: CGFloat = 0.15

    /// Minimum time between consecutive pans.
    private let minPanInterval: TimeInterval = 0.3

    /// Partial correction fraction: each pan moves this fraction toward ideal center.
    /// Gentler than CursorFollowController's 0.6.
    private let correctionFraction: CGFloat = 0.4

    /// Pan duration = distance * this scale, clamped to [minPanDuration, maxPanDuration].
    private let panDurationScale: CGFloat = 1.0
    private let minPanDuration: TimeInterval = 0.2
    private let maxPanDuration: TimeInterval = 0.5

    func simulate(
        scene: CameraScene,
        shotPlan: ShotPlan,
        mouseData: MouseDataSource,
        settings: SimulationSettings
    ) -> [TimedTransform] {
        let zoom = shotPlan.idealZoom
        var currentCenter = shotPlan.idealCenter
        var samples: [TimedTransform] = []

        let startTransform = TransformValue(zoom: zoom, center: currentCenter)

        if scene.startTime >= scene.endTime {
            return [TimedTransform(time: scene.startTime, transform: startTransform)]
        }

        samples.append(TimedTransform(time: scene.startTime, transform: startTransform))

        // Static hold when no zoom or no timeline
        guard let timeline = settings.eventTimeline, zoom > 1.0 else {
            samples.append(TimedTransform(
                time: scene.endTime,
                transform: TransformValue(zoom: zoom, center: currentCenter)
            ))
            return samples
        }

        // Track intent-relevant events within the scene
        let sceneEvents = timeline.events(in: scene.startTime...scene.endTime)
        let moveEvents = panTriggerEvents(
            for: scene.primaryIntent,
            from: sceneEvents
        )

        var lastPanTime: TimeInterval = -.greatestFiniteMagnitude

        for event in moveEvents {
            let pos = event.position

            guard pos.isOutsideViewport(
                zoom: zoom, center: currentCenter, margin: viewportMargin
            ) else { continue }
            guard event.time - lastPanTime >= minPanInterval else { continue }

            let distance = pos.distance(to: currentCenter)
            let panDuration = min(
                maxPanDuration,
                max(minPanDuration, Double(distance * panDurationScale))
            )

            // Compute partial correction toward the cursor
            let fullCorrection = pos.centerToIncludeInViewport(
                zoom: zoom, currentCenter: currentCenter, padding: viewportMargin
            )
            let newCenter = ShotPlanner.clampCenter(
                NormalizedPoint(
                    x: currentCenter.x + (fullCorrection.x - currentCenter.x) * correctionFraction,
                    y: currentCenter.y + (fullCorrection.y - currentCenter.y) * correctionFraction
                ),
                zoom: zoom
            )

            let panStart = event.time
            let panEnd = min(panStart + panDuration, scene.endTime)

            if panStart >= lastPanTime {
                samples.append(TimedTransform(
                    time: panStart,
                    transform: TransformValue(zoom: zoom, center: currentCenter)
                ))
            }
            samples.append(TimedTransform(
                time: panEnd,
                transform: TransformValue(zoom: zoom, center: newCenter)
            ))

            currentCenter = newCenter
            lastPanTime = panEnd
        }

        samples.sort { $0.time < $1.time }

        let lastTime = samples.last?.time ?? scene.startTime
        if lastTime < scene.endTime {
            samples.append(TimedTransform(
                time: scene.endTime,
                transform: TransformValue(zoom: zoom, center: currentCenter)
            ))
        }

        return samples
    }

    private func panTriggerEvents(
        for intent: UserIntent,
        from events: [UnifiedEvent]
    ) -> [UnifiedEvent] {
        switch intent {
        case .clicking, .navigating:
            let clickAnchors = events.filter { event in
                if case .click(let click) = event.kind {
                    return click.clickType == .leftDown
                }
                return false
            }
            if !clickAnchors.isEmpty {
                return clickAnchors
            }
        case .scrolling:
            let scrollAnchors = events.filter { event in
                if case .scroll = event.kind { return true }
                return false
            }
            if !scrollAnchors.isEmpty {
                return scrollAnchors
            }
        case .reading, .idle, .switching:
            return []
        default:
            break
        }

        return events.filter { event in
            switch event.kind {
            case .mouseMove, .click:
                return true
            default:
                return false
            }
        }
    }
}
