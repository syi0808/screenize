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
/// 5. Emit cursor and keystroke tracks
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
        let segments = SegmentPlanner.plan(
            intentSpans: intentSpans,
            screenBounds: screenBounds,
            eventTimeline: timeline,
            frameAnalysis: frameAnalysis,
            settings: settings.shot,
            zoomIntensity: settings.zoomIntensity
        )

        let cameraTrack = CameraTrack(
            name: "Camera (Segment)",
            segments: segments
        )

        #if DEBUG
        print("[SegmentCamera] Generated \(segments.count) segments from \(intentSpans.count) intent spans")
        #endif

        // Step 5: Emit cursor and keystroke tracks
        let cursorTrack = CursorTrackEmitter.emit(
            duration: duration,
            settings: settings.cursor
        )
        let keystrokeTrack = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline,
            duration: duration,
            settings: settings.keystroke
        )

        return GeneratedTimeline(
            cameraTrack: cameraTrack,
            cursorTrack: cursorTrack,
            keystrokeTrack: keystrokeTrack
        )
    }
}
