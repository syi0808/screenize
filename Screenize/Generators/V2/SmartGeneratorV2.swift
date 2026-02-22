import Foundation
import CoreGraphics

/// V2 smart generation orchestrator.
///
/// Pipeline: EventTimeline → IntentClassifier → SceneSegmenter →
/// ShotPlanner → TransitionPlanner → CameraSimulator →
/// CameraTrackEmitter + CursorTrackEmitter + KeystrokeTrackEmitter
class SmartGeneratorV2 {

    private let simulator = CameraSimulator()

    /// Generate a complete timeline from recording data.
    func generate(
        from mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample],
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        screenBounds: CGSize,
        settings: SmartGenerationSettings
    ) -> GeneratedTimeline {
        let duration = mouseData.duration

        // 1. Build event timeline
        let timeline = EventTimeline.build(
            from: mouseData,
            uiStateSamples: uiStateSamples
        )

        // 2. Classify intents
        let intentSpans = IntentClassifier.classify(
            events: timeline,
            uiStateSamples: uiStateSamples
        )

        // 3. Segment into scenes
        let scenes = SceneSegmenter.segment(
            intentSpans: intentSpans,
            eventTimeline: timeline,
            duration: duration
        )

        // 4. Plan shots
        let shotPlans = ShotPlanner.plan(
            scenes: scenes,
            screenBounds: screenBounds,
            eventTimeline: timeline,
            settings: settings.shot
        )

        // 5. Plan transitions
        let transitions = TransitionPlanner.plan(
            shotPlans: shotPlans,
            settings: settings.transition
        )

        // 6. Simulate camera path
        var simSettings = settings.simulation
        simSettings.eventTimeline = timeline
        simSettings.screenBounds = screenBounds
        let path = simulator.simulate(
            shotPlans: shotPlans,
            transitions: transitions,
            mouseData: mouseData,
            settings: simSettings,
            duration: duration
        )

        // 7. Post-process camera path
        let ppSettings = settings.postProcessing
        let smoothed = PathSmoother.smooth(path, settings: ppSettings.smoothing)
        let enforced = HoldEnforcer.enforce(smoothed, settings: ppSettings.hold)
        let refined = TransitionRefiner.refine(
            enforced, settings: ppSettings.transitionRefinement
        )
        let processedPath = SegmentMerger.merge(
            refined, settings: ppSettings.merge
        )

        // 8. Emit tracks
        let rawCameraTrack = CameraTrackEmitter.emit(
            processedPath, duration: duration
        )
        let cameraTrack = SegmentOptimizer.optimize(
            rawCameraTrack, settings: ppSettings.optimization
        )

        #if DEBUG
        Self.dumpDiagnostics(
            timeline: timeline, intentSpans: intentSpans,
            scenes: scenes, shotPlans: shotPlans,
            transitions: transitions,
            cameraTrack: cameraTrack
        )
        #endif
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

    // MARK: - Diagnostics

    #if DEBUG
    private static func dumpDiagnostics(
        timeline: EventTimeline,
        intentSpans: [IntentSpan],
        scenes: [CameraScene],
        shotPlans: [ShotPlan],
        transitions: [TransitionPlan],
        cameraTrack: CameraTrack
    ) {
        print("[V2-Pipeline] === Diagnostics ===")
        print("[V2-Pipeline] EventTimeline: \(timeline.events.count) events, \(String(format: "%.1f", timeline.duration))s")

        // Intent span summary
        var intentCounts: [String: Int] = [:]
        for span in intentSpans {
            let key = intentLabel(span.intent)
            intentCounts[key, default: 0] += 1
        }
        let intentSummary = intentCounts.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: ", ")
        print("[V2-Pipeline] IntentSpans: \(intentSpans.count) [\(intentSummary)]")

        // Scene summary
        var sceneCounts: [String: Int] = [:]
        for scene in scenes {
            let key = intentLabel(scene.primaryIntent)
            sceneCounts[key, default: 0] += 1
        }
        let sceneSummary = sceneCounts.sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }.joined(separator: ", ")
        print("[V2-Pipeline] Scenes: \(scenes.count) [\(sceneSummary)]")

        // Shot plans detail
        print("[V2-Pipeline] ShotPlans:")
        for (i, plan) in shotPlans.enumerated() {
            let intent = intentLabel(plan.scene.primaryIntent)
            let t = String(format: "t=%.1f-%.1f", plan.scene.startTime, plan.scene.endTime)
            let zoom = String(format: "zoom=%.2f", plan.idealZoom)
            let center = String(format: "center=(%.2f,%.2f)", plan.idealCenter.x, plan.idealCenter.y)
            let src: String
            switch plan.zoomSource {
            case .element: src = "src=element"
            case .activityBBox: src = "src=bbox"
            case .singleEvent: src = "src=single"
            case .intentMidpoint: src = "src=midpoint"
            }
            let sceneEvents = timeline.events(in: plan.scene.startTime...plan.scene.endTime)
            let inherited = plan.inherited ? " inherited" : ""
            print("[V2-Pipeline]   [\(i)] \(intent) \(t) \(zoom) \(center) \(src) events=\(sceneEvents.count)\(inherited)")

            // Event type breakdown
            let breakdown = eventBreakdown(sceneEvents)
            print("[V2-Pipeline]       \(breakdown)")
        }

        // Transition summary
        print("[V2-Pipeline] Transitions: \(transitions.count)")
        for (i, trans) in transitions.enumerated() {
            let fromT = String(format: "%.1f", trans.fromScene.endTime)
            let toT = String(format: "%.1f", trans.toScene.startTime)
            let style: String
            switch trans.style {
            case .directPan(let dur):
                style = String(format: "directPan(%.2fs)", dur)
            case let .zoomOutAndIn(outDur, inDur, midZoom):
                style = String(format: "zoomOutAndIn(%.2f+%.2fs midZ=%.2f)", outDur, inDur, midZoom)
            case .cut:
                style = "cut"
            }
            print("[V2-Pipeline]   [\(i)] t=\(fromT)→\(toT) \(style) easing=\(trans.easing)")
        }

        // Camera track summary
        print("[V2-Pipeline] CameraTrack: \(cameraTrack.segments.count) segments")
        for (i, seg) in cameraTrack.segments.enumerated() {
            let t = String(format: "t=%.2f-%.2f", seg.startTime, seg.endTime)
            let zoomStr = String(format: "zoom=%.2f→%.2f", seg.startTransform.zoom, seg.endTransform.zoom)
            let posStr = String(
                format: "pos=(%.2f,%.2f)→(%.2f,%.2f)",
                seg.startTransform.center.x, seg.startTransform.center.y,
                seg.endTransform.center.x, seg.endTransform.center.y
            )
            let easingStr = "\(seg.interpolation)"
            print("[V2-Pipeline]   [\(i)] \(t) \(zoomStr) \(posStr) easing=\(easingStr)")
        }
        print("[V2-Pipeline] === End Diagnostics ===")
    }

    private static func intentLabel(_ intent: UserIntent) -> String {
        switch intent {
        case .typing(let ctx):
            switch ctx {
            case .codeEditor: return "typing(code)"
            case .textField: return "typing(field)"
            case .terminal: return "typing(term)"
            case .richTextEditor: return "typing(rich)"
            }
        case .clicking: return "clicking"
        case .navigating: return "navigating"
        case .dragging: return "dragging"
        case .scrolling: return "scrolling"
        case .reading: return "reading"
        case .switching: return "switching"
        case .idle: return "idle"
        }
    }

    private static func eventBreakdown(_ events: [UnifiedEvent]) -> String {
        var moves = 0, clicks = 0, keys = 0, drags = 0, scrolls = 0, ui = 0
        for event in events {
            switch event.kind {
            case .mouseMove: moves += 1
            case .click: clicks += 1
            case .keyDown, .keyUp: keys += 1
            case .dragStart, .dragEnd: drags += 1
            case .scroll: scrolls += 1
            case .uiStateChange: ui += 1
            }
        }
        return "moves:\(moves) clicks:\(clicks) keys:\(keys) drags:\(drags) scrolls:\(scrolls) ui:\(ui)"
    }
    #endif
}

/// Output of the V2 smart generation pipeline.
struct GeneratedTimeline {
    let cameraTrack: CameraTrack
    let cursorTrack: CursorTrackV2
    let keystrokeTrack: KeystrokeTrackV2
}

/// Settings for the V2 smart generation pipeline.
struct SmartGenerationSettings {
    var shot = ShotSettings()
    var transition = TransitionSettings()
    var simulation = SimulationSettings()
    var cursor = CursorEmissionSettings()
    var keystroke = KeystrokeEmissionSettings()
    var postProcessing = PostProcessingSettings()

    static let `default` = Self()
}

// MARK: - Shot Settings

/// Per-intent zoom and center calculation settings.
struct ShotSettings {
    // Zoom ranges by intent type
    var typingCodeZoomRange: ClosedRange<CGFloat> = 2.0...2.5
    var typingTextFieldZoomRange: ClosedRange<CGFloat> = 2.2...2.8
    var typingTerminalZoomRange: ClosedRange<CGFloat> = 1.6...2.0
    var typingRichTextZoomRange: ClosedRange<CGFloat> = 1.8...2.2
    var clickingZoom: CGFloat = 2.0
    var navigatingZoomRange: ClosedRange<CGFloat> = 1.5...1.8
    var draggingZoomRange: ClosedRange<CGFloat> = 1.3...1.6
    var scrollingZoomRange: ClosedRange<CGFloat> = 1.3...1.5
    var readingZoomRange: ClosedRange<CGFloat> = 1.0...1.3
    var switchingZoom: CGFloat = 1.0
    var idleZoom: CGFloat = 1.0

    /// Target area coverage fraction guiding zoom from work area size.
    var targetAreaCoverage: CGFloat = 0.7

    /// Extra margin around the bounding box (normalized).
    var workAreaPadding: CGFloat = 0.08

    /// Absolute zoom bounds.
    var minZoom: CGFloat = 1.0
    var maxZoom: CGFloat = 2.8

    /// Idle zoom decay factor (0 = full zoom-out to 1.0, 1 = keep neighbor zoom).
    var idleZoomDecay: CGFloat = 0.5
}

// MARK: - Transition Settings

/// Inter-scene transition style settings using viewport-relative distances.
///
/// Transition selection uses viewport-relative distance (how many viewport-widths away the target is):
/// - `viewportDistance < directPanThreshold`: smooth direct pan (target is within viewport)
/// - `viewportDistance < gentlePanThreshold`: longer direct pan (target near viewport edge)
/// - `viewportDistance >= gentlePanThreshold`: zoom out proportionally, pan, zoom in
struct TransitionSettings {
    /// Max viewport-relative distance for a short direct pan (target within viewport).
    /// 0.6 means target center is within 60% of viewport half-width from current center.
    var directPanThreshold: CGFloat = 0.6

    /// Max viewport-relative distance for a medium direct pan (target near viewport edge).
    /// 1.2 means target center is up to 1.2x the viewport half-width away.
    var gentlePanThreshold: CGFloat = 1.2

    /// Viewport-relative distance at which full zoom-out (to 1.0) is used.
    /// Between gentlePanThreshold and this value, intermediate zoom is proportional.
    var fullZoomOutThreshold: CGFloat = 3.0

    /// Duration range for short direct pans.
    var shortPanDurationRange: ClosedRange<TimeInterval> = 0.4...0.6

    /// Duration range for medium direct pans.
    var mediumPanDurationRange: ClosedRange<TimeInterval> = 0.6...0.9

    /// Duration range for zoom-out/in phases (scales with distance).
    var zoomOutDurationRange: ClosedRange<TimeInterval> = 0.35...0.5

    /// Easing for direct pan transitions (critically damped — no overshoot).
    var panEasing: EasingCurve = .spring(dampingRatio: 1.0, response: 0.6)

    /// Easing for the zoom-out phase.
    var zoomOutEasing: EasingCurve = .easeOut

    /// Easing for the zoom-in phase (slight underdamp for snap feel).
    var zoomInEasing: EasingCurve = .spring(dampingRatio: 0.92, response: 0.55)
}

// MARK: - Simulation Settings

/// Camera simulation settings.
struct SimulationSettings {
    /// Minimum zoom (fully zoomed out).
    var minZoom: CGFloat = 1.0

    /// Event timeline for cursor-following controllers.
    var eventTimeline: EventTimeline?

    /// Screen bounds for normalizing caret coordinates.
    var screenBounds: CGSize = .zero
}

// MARK: - Cursor Emission Settings

/// Cursor track emission settings.
struct CursorEmissionSettings {
    var cursorScale: CGFloat = 2.0
}

// MARK: - Keystroke Emission Settings

/// Keystroke track emission settings.
struct KeystrokeEmissionSettings {
    var enabled: Bool = true
    var shortcutsOnly: Bool = true
    var displayDuration: TimeInterval = 1.5
    var fadeInDuration: TimeInterval = 0.15
    var fadeOutDuration: TimeInterval = 0.3
    var minInterval: TimeInterval = 0.05
}

// MARK: - Post-Processing Settings

/// Settings for the post-processing pipeline applied between simulation and track emission.
struct PostProcessingSettings {
    var smoothing = SmoothingSettings()
    var hold = HoldSettings()
    var transitionRefinement = TransitionRefinementSettings()
    var merge = MergeSettings()
    var optimization = OptimizationSettings()
}

/// Jitter smoothing settings for camera path samples.
/// Disabled by default — intended for future CursorFollowController output.
struct SmoothingSettings {
    /// Enable moving-average smoothing. Disabled for StaticHoldController (no jitter).
    var enabled: Bool = false
    /// Number of samples in the moving-average window.
    var windowSize: Int = 5
    /// Maximum deviation (in normalized units) to consider as jitter.
    var maxDeviation: CGFloat = 0.02
}

/// Minimum hold duration enforcement settings.
struct HoldSettings {
    /// Minimum hold duration for zoomed-in scenes (zoom > zoomInThreshold).
    var minZoomInHold: TimeInterval = 0.8
    /// Minimum hold duration for zoomed-out scenes (zoom <= zoomInThreshold).
    var minZoomOutHold: TimeInterval = 0.5
    /// Zoom level above which a scene is considered "zoomed in".
    var zoomInThreshold: CGFloat = 1.05
}

/// Transition refinement settings.
struct TransitionRefinementSettings {
    /// Snap transition start/end transforms to adjacent scene edge transforms.
    var enabled: Bool = true
}

/// Settings for merging short or similar scene segments.
struct MergeSettings {
    /// Scenes shorter than this duration are absorbed into neighbors.
    var minSegmentDuration: TimeInterval = 0.3
    /// Maximum zoom difference for merging adjacent similar scenes.
    var maxZoomDiffForMerge: CGFloat = 0.15
    /// Maximum center difference (per axis) for merging adjacent similar scenes.
    var maxCenterDiffForMerge: CGFloat = 0.08
}

/// Settings for final CameraTrack segment optimization.
struct OptimizationSettings {
    /// Maximum zoom difference to consider negligible when merging CameraSegments.
    var negligibleZoomDiff: CGFloat = 0.03
    /// Maximum center difference (per axis) to consider negligible.
    var negligibleCenterDiff: CGFloat = 0.015
    /// Merge consecutive hold segments with negligible differences.
    var mergeConsecutiveHolds: Bool = true
}

// MARK: - Dynamics Factory

extension SmartGenerationSettings {

    /// Create settings driven by a single dynamics parameter.
    ///
    /// - Parameter dynamics: 0.0 (calm) to 1.0 (aggressive). 0.5 = current defaults.
    ///   Calm produces minimal zoom, longer holds, heavy merging, and slow transitions.
    ///   Aggressive produces maximum zoom, short holds, minimal merging, and fast snappy transitions.
    static func withDynamics(_ d: CGFloat) -> SmartGenerationSettings {
        let d = max(0, min(1, d))
        var s = SmartGenerationSettings()

        // --- Shot Settings ---
        s.shot.typingCodeZoomRange = lerpRange3(
            low: 1.4...1.7, mid: 2.0...2.5, high: 2.6...3.2, d: d
        )
        s.shot.typingTextFieldZoomRange = lerpRange3(
            low: 1.5...1.8, mid: 2.2...2.8, high: 2.8...3.5, d: d
        )
        s.shot.typingTerminalZoomRange = lerpRange3(
            low: 1.2...1.4, mid: 1.6...2.0, high: 2.0...2.6, d: d
        )
        s.shot.typingRichTextZoomRange = lerpRange3(
            low: 1.3...1.5, mid: 1.8...2.2, high: 2.3...2.8, d: d
        )
        s.shot.clickingZoom = lerp3(1.4, 2.0, 2.6, d: d)
        s.shot.navigatingZoomRange = lerpRange3(
            low: 1.1...1.3, mid: 1.5...1.8, high: 1.9...2.3, d: d
        )
        s.shot.draggingZoomRange = lerpRange3(
            low: 1.0...1.2, mid: 1.3...1.6, high: 1.6...2.0, d: d
        )
        s.shot.scrollingZoomRange = lerpRange3(
            low: 1.0...1.1, mid: 1.3...1.5, high: 1.6...1.9, d: d
        )
        s.shot.readingZoomRange = lerpRange3(
            low: 1.0...1.0, mid: 1.0...1.3, high: 1.3...1.6, d: d
        )
        s.shot.targetAreaCoverage = lerp3(0.8, 0.7, 0.55, d: d)
        s.shot.workAreaPadding = lerp3(0.12, 0.08, 0.04, d: d)
        s.shot.maxZoom = lerp3(2.0, 2.8, 3.5, d: d)

        // --- Transition Settings ---
        s.transition.directPanThreshold = lerp3(0.8, 0.6, 0.4, d: d)
        s.transition.gentlePanThreshold = lerp3(1.6, 1.2, 0.8, d: d)
        s.transition.fullZoomOutThreshold = lerp3(4.0, 3.0, 2.0, d: d)
        s.transition.shortPanDurationRange = lerpTimeRange3(
            low: 0.6...0.9, mid: 0.4...0.6, high: 0.2...0.35, d: d
        )
        s.transition.mediumPanDurationRange = lerpTimeRange3(
            low: 0.9...1.3, mid: 0.6...0.9, high: 0.3...0.5, d: d
        )
        s.transition.zoomOutDurationRange = lerpTimeRange3(
            low: 0.5...0.7, mid: 0.35...0.5, high: 0.2...0.3, d: d
        )

        // Spring easing: calm = critically damped slow, aggressive = slight underdamp fast
        let panDamping = lerp3(1.0, 1.0, 0.85, d: d)
        let panResponse = lerp3(0.8, 0.6, 0.4, d: d)
        s.transition.panEasing = .spring(
            dampingRatio: panDamping, response: panResponse
        )
        let zoomInDamping = lerp3(1.0, 0.92, 0.82, d: d)
        let zoomInResponse = lerp3(0.7, 0.55, 0.4, d: d)
        s.transition.zoomInEasing = .spring(
            dampingRatio: zoomInDamping, response: zoomInResponse
        )

        // --- Hold Settings ---
        s.postProcessing.hold.minZoomInHold = lerpTime3(
            1.4, 0.8, 0.4, d: d
        )
        s.postProcessing.hold.minZoomOutHold = lerpTime3(
            1.0, 0.5, 0.2, d: d
        )

        // --- Merge Settings ---
        s.postProcessing.merge.minSegmentDuration = lerpTime3(
            0.6, 0.3, 0.15, d: d
        )
        s.postProcessing.merge.maxZoomDiffForMerge = lerp3(
            0.3, 0.15, 0.05, d: d
        )
        s.postProcessing.merge.maxCenterDiffForMerge = lerp3(
            0.15, 0.08, 0.03, d: d
        )

        // --- Optimization Settings ---
        s.postProcessing.optimization.negligibleZoomDiff = lerp3(
            0.06, 0.03, 0.01, d: d
        )
        s.postProcessing.optimization.negligibleCenterDiff = lerp3(
            0.03, 0.015, 0.005, d: d
        )

        // --- Cursor Settings ---
        s.cursor.cursorScale = lerp3(1.5, 2.0, 2.5, d: d)

        // --- Keystroke Settings ---
        s.keystroke.displayDuration = lerpTime3(2.0, 1.5, 0.8, d: d)
        s.keystroke.fadeInDuration = lerpTime3(0.25, 0.15, 0.08, d: d)
        s.keystroke.fadeOutDuration = lerpTime3(0.5, 0.3, 0.15, d: d)

        return s
    }

    // MARK: - Interpolation Helpers

    /// Piecewise-linear interpolation with three anchors: low at d=0, mid at d=0.5, high at d=1.
    private static func lerp3(
        _ low: CGFloat, _ mid: CGFloat, _ high: CGFloat, d: CGFloat
    ) -> CGFloat {
        if d <= 0.5 {
            let t = d / 0.5
            return low + (mid - low) * t
        } else {
            let t = (d - 0.5) / 0.5
            return mid + (high - mid) * t
        }
    }

    /// Piecewise-linear interpolation for TimeInterval values.
    private static func lerpTime3(
        _ low: TimeInterval, _ mid: TimeInterval, _ high: TimeInterval,
        d: CGFloat
    ) -> TimeInterval {
        let t = Double(d)
        if t <= 0.5 {
            let u = t / 0.5
            return low + (mid - low) * u
        } else {
            let u = (t - 0.5) / 0.5
            return mid + (high - mid) * u
        }
    }

    /// Interpolate a ClosedRange<CGFloat> with three anchors.
    private static func lerpRange3(
        low: ClosedRange<CGFloat>, mid: ClosedRange<CGFloat>,
        high: ClosedRange<CGFloat>, d: CGFloat
    ) -> ClosedRange<CGFloat> {
        let lb = lerp3(
            low.lowerBound, mid.lowerBound, high.lowerBound, d: d
        )
        let ub = lerp3(
            low.upperBound, mid.upperBound, high.upperBound, d: d
        )
        return lb...ub
    }

    /// Interpolate a ClosedRange<TimeInterval> with three anchors.
    private static func lerpTimeRange3(
        low: ClosedRange<TimeInterval>, mid: ClosedRange<TimeInterval>,
        high: ClosedRange<TimeInterval>, d: CGFloat
    ) -> ClosedRange<TimeInterval> {
        let lb = lerpTime3(
            low.lowerBound, mid.lowerBound, high.lowerBound, d: d
        )
        let ub = lerpTime3(
            low.upperBound, mid.upperBound, high.upperBound, d: d
        )
        return lb...ub
    }
}
