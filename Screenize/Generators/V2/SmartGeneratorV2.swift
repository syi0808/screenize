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

        #if DEBUG
        Self.dumpDiagnostics(
            timeline: timeline, intentSpans: intentSpans,
            scenes: scenes, shotPlans: shotPlans,
            cameraTrack: CameraTrackEmitter.emit(path, duration: duration)
        )
        #endif

        // 7. Emit tracks
        let cameraTrack = CameraTrackEmitter.emit(path, duration: duration)
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
            case .intentMidpoint: src = "src=midpoint"
            }
            let sceneEvents = timeline.events(in: plan.scene.startTime...plan.scene.endTime)
            let inherited = plan.inherited ? " inherited" : ""
            print("[V2-Pipeline]   [\(i)] \(intent) \(t) \(zoom) \(center) \(src) events=\(sceneEvents.count)\(inherited)")

            // Event type breakdown
            let breakdown = eventBreakdown(sceneEvents)
            print("[V2-Pipeline]       \(breakdown)")
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
            print("[V2-Pipeline]   [\(i)] \(t) \(zoomStr) \(posStr)")
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

/// Inter-scene transition style settings.
struct TransitionSettings {
    /// Max center distance for a short direct pan.
    var shortPanMaxDistance: CGFloat = 0.15

    /// Max center distance for a medium direct pan.
    var mediumPanMaxDistance: CGFloat = 0.4

    /// Duration range for short direct pans.
    var shortPanDurationRange: ClosedRange<TimeInterval> = 0.3...0.5

    /// Duration range for medium direct pans.
    var mediumPanDurationRange: ClosedRange<TimeInterval> = 0.5...0.8

    /// Zoom-out phase duration for zoomOutAndIn transitions.
    var zoomOutDuration: TimeInterval = 0.5

    /// Zoom-in phase duration for zoomOutAndIn transitions.
    var zoomInDuration: TimeInterval = 0.5

    /// Easing for direct pan transitions.
    var panEasing: EasingCurve = .spring(dampingRatio: 0.85, response: 0.5)

    /// Easing for the zoom-out phase.
    var zoomOutEasing: EasingCurve = .easeOut

    /// Easing for the zoom-in phase.
    var zoomInEasing: EasingCurve = .spring(dampingRatio: 1.0, response: 0.6)
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
