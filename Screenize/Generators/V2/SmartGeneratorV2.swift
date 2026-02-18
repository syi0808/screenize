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
        let path = simulator.simulate(
            shotPlans: shotPlans,
            transitions: transitions,
            mouseData: mouseData,
            settings: settings.simulation,
            duration: duration
        )

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
