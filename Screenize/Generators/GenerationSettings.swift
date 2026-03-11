import Foundation
import CoreGraphics

// MARK: - Generation Mode

/// Smart generation mode selection.
enum GenerationMode: String, Codable, CaseIterable {
    case continuous
    case segmentBased
}

// MARK: - Generation Settings

/// User-configurable settings for the smart generation pipeline.
/// Persisted at app level and optionally overridden per project.
struct GenerationSettings: Codable, Equatable {

    var mode: GenerationMode = .continuous
    var cameraMotion = CameraMotionSettings()
    var zoom = ZoomSettings()
    var intentClassification = IntentClassificationSettings()
    var timing = TimingSettings()
    var cursorKeystroke = CursorKeystrokeSettings()

    static let `default` = Self()
}

// MARK: - Camera Motion Settings

struct CameraMotionSettings: Codable, Equatable {
    // Spring physics (from ContinuousCameraSettings)
    var positionDampingRatio: CGFloat = 0.90
    var positionResponse: CGFloat = 0.35
    var zoomDampingRatio: CGFloat = 0.90
    var zoomResponse: CGFloat = 0.55
    var boundaryStiffness: CGFloat = 12.0
    var zoomSettleThreshold: CGFloat = 0.02

    // Urgency multipliers (from ContinuousCameraSettings.urgencyMultipliers)
    var urgencyImmediateMultiplier: CGFloat = 0.05
    var urgencyHighMultiplier: CGFloat = 0.5
    var urgencyNormalMultiplier: CGFloat = 1.0
    var urgencyLazyMultiplier: CGFloat = 2.0
    var urgencyBlendDuration: CGFloat = 0.5

    // Dead zone (from DeadZoneSettings)
    var safeZoneFraction: CGFloat = 0.75
    var safeZoneFractionTyping: CGFloat = 0.60
    var gradientBandWidth: CGFloat = 0.25
    var correctionFraction: CGFloat = 0.45
    var hysteresisMargin: CGFloat = 0.15
    var correctionFractionTyping: CGFloat = 0.80
    var deadZoneMinResponse: CGFloat = 0.20
    var deadZoneMaxResponse: CGFloat = 0.50

    // Micro tracker (from MicroTrackerSettings)
    var idleVelocityThreshold: CGFloat = 0.02
    var microTrackerDampingRatio: CGFloat = 1.0
    var microTrackerResponse: CGFloat = 3.0
}

// MARK: - Zoom Settings

struct ZoomSettings: Codable, Equatable {
    // Per-activity zoom ranges (from ShotSettings)
    var typingCodeZoomMin: CGFloat = 2.0
    var typingCodeZoomMax: CGFloat = 2.5
    var typingTextFieldZoomMin: CGFloat = 2.2
    var typingTextFieldZoomMax: CGFloat = 2.8
    var typingTerminalZoomMin: CGFloat = 1.6
    var typingTerminalZoomMax: CGFloat = 2.0
    var typingRichTextZoomMin: CGFloat = 1.8
    var typingRichTextZoomMax: CGFloat = 2.2
    var clickingZoomMin: CGFloat = 1.5
    var clickingZoomMax: CGFloat = 2.5
    var navigatingZoomMin: CGFloat = 1.5
    var navigatingZoomMax: CGFloat = 1.8
    var draggingZoomMin: CGFloat = 1.3
    var draggingZoomMax: CGFloat = 1.6
    var scrollingZoomMin: CGFloat = 1.3
    var scrollingZoomMax: CGFloat = 1.5
    var readingZoomMin: CGFloat = 1.0
    var readingZoomMax: CGFloat = 1.3

    // Fixed zoom levels
    var switchingZoom: CGFloat = 1.0
    var idleZoom: CGFloat = 1.0

    // Global limits and modifiers
    var targetAreaCoverage: CGFloat = 0.7
    var workAreaPadding: CGFloat = 0.08
    var minZoom: CGFloat = 1.0
    var maxZoom: CGFloat = 2.8
    var idleZoomDecay: CGFloat = 0.5
    var zoomIntensity: CGFloat = 1.0
}

// MARK: - Intent Classification Settings

struct IntentClassificationSettings: Codable, Equatable {
    var typingSessionTimeout: CGFloat = 1.5
    var navigatingClickWindow: CGFloat = 2.0
    var navigatingClickDistance: CGFloat = 0.5
    var navigatingMinClicks: Int = 2
    var idleThreshold: CGFloat = 5.0
    var continuationGapThreshold: CGFloat = 1.5
    var continuationMaxDistance: CGFloat = 0.20
    var scrollMergeGap: CGFloat = 1.0
    var pointSpanDuration: CGFloat = 0.5
    var contextChangeWindow: CGFloat = 0.8
    var typingAnticipation: CGFloat = 0.4
    var clickAnticipation: CGFloat = 0.15
    var dragAnticipation: CGFloat = 0.25
    var scrollAnticipation: CGFloat = 0.25
    var switchAnticipation: CGFloat = 0.25
}

// MARK: - Timing Settings

struct TimingSettings: Codable, Equatable {
    // Lead times per urgency (from WaypointGenerator.entryLeadTime)
    var leadTimeImmediate: CGFloat = 0.24
    var leadTimeHigh: CGFloat = 0.16
    var leadTimeNormal: CGFloat = 0.08
    var leadTimeLazy: CGFloat = 0.0

    // Simulation (from ContinuousCameraSettings)
    var tickRate: CGFloat = 60.0
    var typingDetailMinInterval: CGFloat = 0.2
    var typingDetailMinDistance: CGFloat = 0.025

    // Dead zone response thresholds (from DeadZoneSettings)
    var responseFastThreshold: CGFloat = 0.5
    var responseSlowThreshold: CGFloat = 2.0
}

// MARK: - Cursor & Keystroke Settings

struct CursorKeystrokeSettings: Codable, Equatable {
    var cursorScale: CGFloat = 2.0
    var keystrokeEnabled: Bool = true
    var shortcutsOnly: Bool = true
    var displayDuration: CGFloat = 1.5
    var fadeInDuration: CGFloat = 0.15
    var fadeOutDuration: CGFloat = 0.3
    var minInterval: CGFloat = 0.05
}
