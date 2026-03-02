import Foundation
import CoreGraphics

/// Continuous camera generation pipeline.
///
/// Unlike SmartGeneratorV2 which uses discrete segments + transitions,
/// this generator produces a single continuous camera path via physics simulation.
/// The resulting `TimedTransform[]` is stored on the Timeline and evaluated
/// directly by FrameEvaluator — no lossy segment conversion.
///
/// Pipeline:
/// 1. Pre-smooth mouse data
/// 2. Build EventTimeline + classify intents (reuses existing V2 infrastructure)
/// 3. WaypointGenerator: IntentSpan[] → CameraWaypoint[]
/// 4. SpringDamperSimulator: waypoints → continuous TimedTransform[] at 60Hz
/// 5. Apply zoom intensity to samples + emit cursor/keystroke tracks
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
            uiStateSamples: uiStateSamples,
            diagnosticsHandler: { diagnostics in
                #if DEBUG
                let sourceRate = String(format: "%.2f", diagnostics.sourceSamplesPerSecond)
                let effectiveRate = String(format: "%.2f", diagnostics.effectiveSamplesPerSecond)
                Log.generator.debug(
                    "Adaptive event sampling: moves=\(diagnostics.selectedMouseMoveCount)/\(diagnostics.sourceMouseMoveCount), rate=\(effectiveRate)Hz (src=\(sourceRate)Hz), burst=\(diagnostics.burstSampleCount), boundary=\(diagnostics.boundarySampleCount), base=\(diagnostics.baseSampleCount), missed=\(diagnostics.missedAnchorCount)/\(diagnostics.anchorCount), budget=\(diagnostics.budgetApplied)"
                )
                #endif
            }
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
        let rawSamples = SpringDamperSimulator.simulate(
            waypoints: waypoints,
            duration: duration,
            settings: settings
        )

        // Step 6: Apply post-hoc zoom intensity directly to samples
        let samples = Self.applyZoomIntensity(
            to: rawSamples, intensity: settings.zoomIntensity
        )

        // Step 7: Create a display-only CameraTrack (single segment for timeline UI)
        let displayTrack = Self.createDisplayTrack(from: samples, duration: duration)

        #if DEBUG
        Self.dumpDiagnostics(
            intentSpans: intentSpans,
            waypoints: waypoints,
            sampleCount: samples.count,
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
            cameraTrack: displayTrack,
            cursorTrack: cursorTrack,
            keystrokeTrack: keystrokeTrack,
            continuousTransforms: samples
        )
    }

    // MARK: - Zoom Intensity (Samples)

    /// Scale zoom values in continuous samples by intensity factor.
    /// Formula: newZoom = 1.0 + (originalZoom - 1.0) * intensity
    private static func applyZoomIntensity(
        to samples: [TimedTransform], intensity: CGFloat
    ) -> [TimedTransform] {
        guard abs(intensity - 1.0) > 0.001 else { return samples }
        return samples.map { sample in
            let newZoom = max(1.0, 1.0 + (sample.transform.zoom - 1.0) * intensity)
            let clamped = ShotPlanner.clampCenter(sample.transform.center, zoom: newZoom)
            return TimedTransform(
                time: sample.time,
                transform: TransformValue(zoom: newZoom, center: clamped)
            )
        }
    }

    // MARK: - Display Track

    /// Create a single-segment CameraTrack for timeline UI visualization.
    /// FrameEvaluator ignores this when continuousTransforms is set.
    private static func createDisplayTrack(
        from samples: [TimedTransform],
        duration: TimeInterval
    ) -> CameraTrack {
        guard let first = samples.first, let last = samples.last else {
            return CameraTrack(segments: [])
        }
        let segment = CameraSegment(
            startTime: first.time,
            endTime: max(first.time + 0.001, last.time > 0 ? last.time : duration),
            startTransform: first.transform,
            endTransform: last.transform
        )
        return CameraTrack(segments: [segment])
    }

    // MARK: - Diagnostics

    #if DEBUG
    private static func dumpDiagnostics(
        intentSpans: [IntentSpan],
        waypoints: [CameraWaypoint],
        sampleCount: Int,
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
        print("[ContinuousCamera] Samples: \(sampleCount) (direct rendering, no segments)")
        print("[ContinuousCamera] === End Diagnostics ===")
    }
    #endif
}
