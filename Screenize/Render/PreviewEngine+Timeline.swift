import Foundation
import CoreGraphics

// MARK: - Timeline Updates

extension PreviewEngine {

    /// Invalidate the cache when the timeline changes
    func invalidateCache(from startTime: TimeInterval, to endTime: TimeInterval) {
        renderCoordinator.invalidateCache(from: startTime, to: endTime)

        // If the current frame falls within a dirty range, re-render
        if currentTime >= startTime && currentTime <= endTime {
            scrubController.scrub(to: currentTime)
        }
    }

    /// Invalidate a specific time range and update the evaluator
    /// More efficient than invalidateAllCache when only a portion of the timeline changed
    func invalidateRange(with timeline: Timeline, from startTime: TimeInterval, to endTime: TimeInterval) {
        guard let project = project else { return }

        // Recreate the evaluator with the updated timeline
        let newEvaluator = RenderPipelineFactory.createEvaluator(
            timeline: timeline,
            project: project,
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
            clickEvents: renderClickEvents,
            frameRate: frameRate
        )

        renderCoordinator.updateEvaluator(newEvaluator)
        renderCoordinator.invalidateCache(from: startTime, to: endTime)

        // Re-render if the current frame falls within the dirty range
        if currentTime >= startTime && currentTime <= endTime {
            scrubController.scrub(to: currentTime)
        }
    }

    /// Invalidate the entire cache
    /// - Parameter timeline: Updated timeline (nil only clears the cache)
    func invalidateAllCache(with timeline: Timeline? = nil) {
        if let timeline = timeline {
            updateTimeline(timeline)
        } else {
            renderCoordinator.invalidateAllCache()
            scrubController.scrub(to: currentTime)
        }
    }

    /// Update the trim range
    func updateTrimRange(start: TimeInterval, end: TimeInterval?) {
        self.trimStart = start
        self.trimEnd = end

        // Adjust if the current time falls outside the trim range
        isSeeking = true
        if currentTime < effectiveTrimStart {
            currentTime = effectiveTrimStart
        } else if currentTime > effectiveTrimEnd {
            currentTime = effectiveTrimEnd
        }
        isSeeking = false

        // Re-render the current frame
        scrubController.scrub(to: currentTime)
    }

    /// Recreate the evaluator when the timeline updates
    /// - Parameter timeline: New timeline
    func updateTimeline(_ timeline: Timeline) {
        guard let project = project else { return }

        // Re-interpolate mouse positions if spring config changed
        let newSpringConfig = timeline.cursorTrackV2?.springConfig
        if newSpringConfig != lastSpringConfig {
            let smoothedResult = MouseDataConverter.loadAndConvertWithInterpolation(
                from: project,
                frameRate: frameRate,
                springConfig: newSpringConfig
            )
            smoothedMousePositions = smoothedResult.positions
            lastSpringConfig = newSpringConfig
        }

        // Create a new evaluator (reuse stored mouse data)
        let newEvaluator = RenderPipelineFactory.createEvaluator(
            timeline: timeline,
            project: project,
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
            clickEvents: renderClickEvents,
            frameRate: frameRate
        )

        renderCoordinator.updateEvaluator(newEvaluator)
        renderCoordinator.invalidateAllCache()

        // Re-render the current frame
        scrubController.scrub(to: currentTime)
    }

    /// Rebuild the renderer and evaluator when render settings change
    /// - Parameter renderSettings: New render settings
    func updateRenderSettings(_ renderSettings: RenderSettings) {
        guard let extractor = frameExtractor else { return }

        // Update the project's render settings BEFORE capturing the local copy
        // (ScreenizeProject is a struct, so guard let captures a snapshot)
        self.project?.renderSettings = renderSettings

        guard let project = project else { return }

        // Recreate the evaluator (isWindowMode may change)
        let newEvaluator = RenderPipelineFactory.createEvaluator(
            project: project,
            rawMousePositions: rawMousePositions,
            smoothedMousePositions: smoothedMousePositions,
            clickEvents: renderClickEvents,
            frameRate: frameRate
        )

        // Recreate the renderer
        let newRenderer = RenderPipelineFactory.createPreviewRenderer(
            renderSettings: renderSettings,
            captureMeta: project.captureMeta,
            sourceSize: extractor.videoSize,
            scale: previewScale
        )

        renderCoordinator.updateEvaluator(newEvaluator)
        renderCoordinator.updateRenderer(newRenderer)
        renderCoordinator.invalidateAllCache()

        // Update audio volumes
        audioPlayer.updateVolumes(renderSettings: renderSettings)

        // Re-render the current frame
        scrubController.scrub(to: currentTime)
    }
}
