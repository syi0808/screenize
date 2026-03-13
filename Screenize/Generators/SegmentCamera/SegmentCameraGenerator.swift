import Foundation
import CoreGraphics

/// Segment-based camera generation pipeline.
///
/// Produces multiple discrete CameraSegments with explicit start/end transforms,
/// editable by the user in the timeline. Shares the analysis layer
/// (EventTimeline, IntentClassifier) with ContinuousCameraGenerator.
///
/// Pipeline:
/// 1. Pre-smooth mouse positions
/// 2. Build event timeline
/// 3. Classify intents
/// 4. Plan and build segments via SegmentPlanner
/// 5. Compute spring config (deferred to SpringSimulationCache)
/// 6. Emit cursor track
/// 7. Emit keystroke track
class SegmentCameraGenerator {

    func generate(
        from mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample],
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        screenBounds: CGSize,
        settings: ContinuousCameraSettings
    ) -> GeneratedTimeline {
        // Step 1: Pre-smooth mouse positions (same as continuous)
        let effectiveMouseData: MouseDataSource = SmoothedMouseDataSource(
            wrapping: mouseData,
            springConfig: nil
        )

        let duration = effectiveMouseData.duration

        // Step 2: Build event timeline
        let timeline = EventTimeline.build(
            from: effectiveMouseData,
            uiStateSamples: uiStateSamples
        )

        // Step 3: Classify intents
        let intentSpans = IntentClassifier.classify(
            events: timeline,
            uiStateSamples: uiStateSamples,
            settings: settings.intentClassification
        )

        // Step 4: Plan segments
        let rawSegments = SegmentPlanner.plan(
            intentSpans: intentSpans,
            screenBounds: screenBounds,
            eventTimeline: timeline,
            frameAnalysis: frameAnalysis,
            settings: settings.shot,
            zoomIntensity: settings.zoomIntensity,
            mouseData: effectiveMouseData
        )

        // Step 4.5: Compute cursor speeds for adaptive spring response
        let speeds = SegmentCameraGenerator.cursorSpeeds(
            for: rawSegments,
            mouseData: effectiveMouseData
        )

        // Step 5: Build spring config (stored in GeneratedTimeline for cache use)
        let springConfig = SegmentSpringSimulator.Config(
            positionDampingRatio: settings.positionDampingRatio,
            positionResponse: settings.positionResponse,
            zoomDampingRatio: settings.zoomDampingRatio,
            zoomResponse: settings.zoomResponse,
            tickRate: settings.tickRate,
            minZoom: settings.minZoom,
            maxZoom: settings.maxZoom
        )

        // Keep raw .manual segments — spring simulation deferred to cache
        let segments = rawSegments

        let cameraTrack = CameraTrack(
            name: "Camera (Segment)",
            segments: segments
        )

        #if DEBUG
        print("[SegmentCamera] Generated \(segments.count) .manual segments from \(intentSpans.count) intent spans")
        #endif

        // Step 6: Emit cursor track
        let cursorTrack = CursorTrackEmitter.emit(
            duration: duration,
            settings: settings.cursor
        )
        // Step 7: Emit keystroke track
        let keystrokeTrack = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline,
            duration: duration,
            settings: settings.keystroke
        )

        return GeneratedTimeline(
            cameraTrack: cameraTrack,
            cursorTrack: cursorTrack,
            keystrokeTrack: keystrokeTrack,
            cursorSpeeds: speeds,
            springConfig: springConfig
        )
    }

    /// Compute cursor velocity at the start of each segment.
    /// Returns a dictionary mapping segment ID to speed in normalized units/sec.
    /// Speed is net displacement over the first 0.3s (or segment duration if shorter).
    static func cursorSpeeds(
        for segments: [CameraSegment],
        mouseData: MouseDataSource
    ) -> [UUID: CGFloat] {
        let sampleWindow: TimeInterval = 0.3
        var result: [UUID: CGFloat] = [:]

        for segment in segments {
            let windowEnd = min(segment.startTime + sampleWindow, segment.endTime)
            let samples = mouseData.positions.filter {
                $0.time >= segment.startTime && $0.time <= windowEnd
            }

            guard samples.count >= 2,
                  let first = samples.first,
                  let last = samples.last else {
                result[segment.id] = 0
                continue
            }

            let timeDelta = last.time - first.time
            guard timeDelta > 0.001 else {
                result[segment.id] = 0
                continue
            }

            let dx = last.position.x - first.position.x
            let dy = last.position.y - first.position.y
            let distance = sqrt(dx * dx + dy * dy)
            result[segment.id] = distance / CGFloat(timeDelta)
        }

        return result
    }
}
