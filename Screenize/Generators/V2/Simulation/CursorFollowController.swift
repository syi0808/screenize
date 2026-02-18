import Foundation
import CoreGraphics

/// Camera controller that follows the caret/cursor during typing and dragging scenes.
///
/// Starts at the shot plan's ideal zoom/center, then pans when the tracked position
/// moves outside the current viewport. Uses caret bounds when available, falling back
/// to mouse position.
struct CursorFollowController: CameraController {

    /// Minimum time between consecutive pans to prevent jitter.
    private let minMoveInterval: TimeInterval = 0.3

    /// Minimum pan animation duration.
    private let minPanDuration: TimeInterval = 0.15

    /// Maximum pan animation duration.
    private let maxPanDuration: TimeInterval = 0.5

    /// Distance multiplier to compute pan duration: duration = distance * panDurationScale.
    private let panDurationScale: CGFloat = 1.5

    /// Margin inside viewport edge before triggering a pan (fraction of viewport).
    private let viewportMargin: CGFloat = 0.05

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

        for event in sceneEvents {
            // Extract tracked position: prefer caret, fall back to mouse
            let trackedPosition: NormalizedPoint
            if let caretBounds = event.metadata.caretBounds {
                // Caret bounds may be in normalized or pixel space
                let normalizedCaret = normalizeBoundsIfNeeded(
                    caretBounds, screenBounds: settings.screenBounds
                )
                trackedPosition = NormalizedPoint(
                    x: normalizedCaret.midX, y: normalizedCaret.midY
                )
            } else {
                trackedPosition = event.position
            }

            // Check if position is outside current viewport
            guard trackedPosition.isOutsideViewport(
                zoom: zoom, center: currentCenter, margin: viewportMargin
            ) else {
                continue
            }

            // Debounce: skip if too soon after last pan
            guard event.time - lastPanTime >= minMoveInterval else {
                continue
            }

            // Compute distance-based pan duration
            let distance = trackedPosition.distance(to: currentCenter)
            let computedPanDuration = min(
                maxPanDuration,
                max(minPanDuration, Double(distance * panDurationScale))
            )

            #if DEBUG
            print(String(
                format: "[V2-CursorFollow] t=%.2f pan dist=%.3f dur=%.2fs pos=(%.2f,%.2f)→(%.2f,%.2f)",
                event.time, distance, computedPanDuration,
                currentCenter.x, currentCenter.y,
                trackedPosition.x, trackedPosition.y
            ))
            #endif

            // Generate pan: hold at current position, then animate to new center
            let panStart = event.time
            let panEnd = min(panStart + computedPanDuration, scene.endTime)

            // Hold keyframe just before pan
            samples.append(TimedTransform(
                time: panStart,
                transform: TransformValue(zoom: zoom, center: currentCenter)
            ))

            // Compute new center targeting the tracked position
            let newCenter = ShotPlanner.clampCenter(trackedPosition, zoom: zoom)

            // Pan end keyframe
            samples.append(TimedTransform(
                time: panEnd,
                transform: TransformValue(zoom: zoom, center: newCenter)
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

    /// Normalize caret bounds from pixel space to 0-1 if needed.
    private func normalizeBoundsIfNeeded(
        _ bounds: CGRect, screenBounds: CGSize
    ) -> CGRect {
        // Already normalized (values in 0-1 range)
        if bounds.maxX <= 1.1 && bounds.maxY <= 1.1 &&
            bounds.minX >= -0.1 && bounds.minY >= -0.1 {
            return bounds
        }
        guard screenBounds.width > 0, screenBounds.height > 0 else { return bounds }
        return CGRect(
            x: bounds.origin.x / screenBounds.width,
            y: bounds.origin.y / screenBounds.height,
            width: bounds.width / screenBounds.width,
            height: bounds.height / screenBounds.height
        )
    }
}
