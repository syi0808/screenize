import Foundation
import CoreGraphics

/// Continuous camera generation pipeline.
///
/// Unlike SmartGeneratorV2 which uses discrete segments + transitions,
/// this generator produces a single continuous camera path via physics simulation.
///
/// Pipeline:
/// 1. Pre-smooth mouse data
/// 2. Build EventTimeline + classify intents (reuses existing V2 infrastructure)
/// 3. WaypointGenerator: IntentSpan[] → CameraWaypoint[]
/// 4. SpringDamperSimulator: waypoints → continuous TimedTransform[] at 60Hz
/// 5. ContinuousTrackEmitter: samples → CameraTrack (non-overlapping segments)
/// 6. Apply zoom intensity + emit cursor/keystroke tracks
class ContinuousCameraGenerator {

    /// Generate a complete timeline using continuous camera physics.
    func generate(
        from mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample],
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        screenBounds: CGSize,
        settings: ContinuousCameraSettings
    ) -> GeneratedTimeline {
        // Step 1: Pre-smooth mouse positions to match render pipeline cursor path
        let effectiveMouseData: MouseDataSource
        if let springConfig = settings.springConfig {
            effectiveMouseData = SmoothedMouseDataSource(
                wrapping: mouseData,
                springConfig: springConfig
            )
        } else {
            effectiveMouseData = mouseData
        }

        let duration = effectiveMouseData.duration

        // Step 2: Build event timeline
        let timeline = EventTimeline.build(
            from: effectiveMouseData,
            uiStateSamples: uiStateSamples
        )

        // Step 3: Classify intents
        let intentSpans = IntentClassifier.classify(
            events: timeline,
            uiStateSamples: uiStateSamples
        )

        // Step 4: Generate waypoints from intents
        let waypoints = WaypointGenerator.generate(
            from: intentSpans,
            screenBounds: screenBounds,
            eventTimeline: timeline,
            frameAnalysis: frameAnalysis,
            settings: settings
        )

        // Step 5: Simulate continuous camera path
        let samples = SpringDamperSimulator.simulate(
            waypoints: waypoints,
            duration: duration,
            settings: settings
        )

        // Step 6: Convert samples to camera track
        let rawCameraTrack = ContinuousTrackEmitter.emit(from: samples)

        // Step 7: Apply post-hoc zoom intensity
        let cameraTrack = Self.applyZoomIntensity(
            rawCameraTrack, intensity: settings.zoomIntensity
        )

        #if DEBUG
        Self.dumpDiagnostics(
            intentSpans: intentSpans,
            waypoints: waypoints,
            sampleCount: samples.count,
            cameraTrack: cameraTrack,
            duration: duration
        )
        #endif

        // Step 8: Emit cursor and keystroke tracks (reuse V2 emitters)
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

    // MARK: - Zoom Intensity

    /// Scale all zoom values by intensity factor.
    /// Formula: newZoom = 1.0 + (originalZoom - 1.0) * intensity
    private static func applyZoomIntensity(
        _ track: CameraTrack, intensity: CGFloat
    ) -> CameraTrack {
        guard abs(intensity - 1.0) > 0.001 else { return track }
        let scaled = track.segments.map { seg -> CameraSegment in
            var s = seg
            s.startTransform = scaleTransformZoom(
                seg.startTransform, intensity: intensity
            )
            s.endTransform = scaleTransformZoom(
                seg.endTransform, intensity: intensity
            )
            return s
        }
        return CameraTrack(segments: scaled)
    }

    private static func scaleTransformZoom(
        _ t: TransformValue, intensity: CGFloat
    ) -> TransformValue {
        let newZoom = max(1.0, 1.0 + (t.zoom - 1.0) * intensity)
        let clamped = ShotPlanner.clampCenter(t.center, zoom: newZoom)
        return TransformValue(zoom: newZoom, center: clamped)
    }

    // MARK: - Diagnostics

    #if DEBUG
    private static func dumpDiagnostics(
        intentSpans: [IntentSpan],
        waypoints: [CameraWaypoint],
        sampleCount: Int,
        cameraTrack: CameraTrack,
        duration: TimeInterval
    ) {
        print("[ContinuousCamera] === Diagnostics ===")
        print("[ContinuousCamera] Duration: \(String(format: "%.1f", duration))s")
        print("[ContinuousCamera] IntentSpans: \(intentSpans.count)")
        print("[ContinuousCamera] Waypoints: \(waypoints.count)")
        for (i, wp) in waypoints.enumerated() {
            let t = String(format: "t=%.2f", wp.time)
            let zoom = String(format: "zoom=%.2f", wp.targetZoom)
            let center = String(format: "center=(%.2f,%.2f)", wp.targetCenter.x, wp.targetCenter.y)
            print("[ContinuousCamera]   [\(i)] \(t) \(zoom) \(center) urgency=\(wp.urgency)")
        }
        print("[ContinuousCamera] Samples: \(sampleCount)")
        print("[ContinuousCamera] CameraTrack: \(cameraTrack.segments.count) segments")
        for (i, seg) in cameraTrack.segments.enumerated() {
            let t = String(format: "t=%.2f-%.2f", seg.startTime, seg.endTime)
            let zoomStr = String(format: "zoom=%.2f->%.2f", seg.startTransform.zoom, seg.endTransform.zoom)
            print("[ContinuousCamera]   [\(i)] \(t) \(zoomStr)")
        }
        print("[ContinuousCamera] === End Diagnostics ===")
    }
    #endif
}
