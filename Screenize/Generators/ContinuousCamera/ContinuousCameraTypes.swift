import Foundation
import CoreGraphics

// MARK: - Micro Tracker Settings

/// Configuration for the idle re-centering layer (Layer 2).
struct MicroTrackerSettings {
    /// Cursor velocity threshold (normalized units/sec) below which idle re-centering activates.
    var idleVelocityThreshold: CGFloat = 0.02
    /// Spring damping ratio for idle re-centering.
    var dampingRatio: CGFloat = 1.0
    /// Spring response time in seconds for idle re-centering.
    var response: CGFloat = 3.0
}

// MARK: - Dead Zone Settings

/// Configuration for viewport-aware dead zone camera targeting.
struct DeadZoneSettings {
    /// Fraction of viewport that is the safe zone (no camera movement). 0.75 = 75%.
    var safeZoneFraction: CGFloat = 0.75
    /// Safe zone fraction during typing (smaller = more responsive to caret movement).
    var safeZoneFractionTyping: CGFloat = 0.60
    /// Width of gradient transition band between safe and trigger zones (fraction of viewport).
    var gradientBandWidth: CGFloat = 0.25
    /// Partial correction fraction. 0 = minimal movement, 1 = center cursor.
    var correctionFraction: CGFloat = 0.45
    /// Hysteresis margin as fraction of safe zone half-width.
    /// Entering dead zone requires exceeding safeHalf + hysteresisHalf;
    /// leaving requires dropping below safeHalf - hysteresisHalf.
    var hysteresisMargin: CGFloat = 0.15
    /// Correction fraction during typing (more aggressive caret following).
    var correctionFractionTyping: CGFloat = 0.80
    /// Minimum spring response time (when next action is imminent).
    var minResponse: CGFloat = 0.20
    /// Maximum spring response time (when next action is far away).
    var maxResponse: CGFloat = 0.50
    /// Time-to-next-action threshold below which minResponse is used.
    var responseFastThreshold: TimeInterval = 0.5
    /// Time-to-next-action threshold above which maxResponse is used.
    var responseSlowThreshold: TimeInterval = 2.0
}

// MARK: - Waypoint Urgency

/// How quickly the camera should reach a waypoint.
/// Higher urgency = shorter effective spring response time.
enum WaypointUrgency: Int, Comparable {
    case lazy = 0       // idle, reading — camera drifts slowly
    case normal = 1     // clicking, navigating, scrolling — standard speed
    case high = 2       // typing — camera should arrive before user starts
    case immediate = 3  // switching — instant cut

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Camera Waypoint

/// A target camera state at a specific time.
struct CameraWaypoint {
    let time: TimeInterval
    let targetZoom: CGFloat
    let targetCenter: NormalizedPoint
    let urgency: WaypointUrgency
    let source: UserIntent
}

// MARK: - Camera State

/// Mutable state of the simulated camera including position, zoom, and velocities.
struct CameraState {
    var positionX: CGFloat
    var positionY: CGFloat
    var zoom: CGFloat
    var velocityX: CGFloat = 0
    var velocityY: CGFloat = 0
    var velocityZoom: CGFloat = 0
    var deadZoneActive: Bool = false
}

// MARK: - Continuous Camera Settings

/// Configuration for the continuous camera physics simulation.
struct ContinuousCameraSettings {
    /// Damping ratio for position springs (1.0 = critical, <1 = underdamped).
    var positionDampingRatio: CGFloat = 1.0
    /// Response time in seconds for position springs.
    var positionResponse: CGFloat = 0.35
    /// Damping ratio for zoom spring.
    var zoomDampingRatio: CGFloat = 0.90
    /// Response time in seconds for zoom spring.
    var zoomResponse: CGFloat = 0.55
    /// Duration in seconds over which urgency transitions are blended.
    var urgencyBlendDuration: TimeInterval = 0.5
    /// Multipliers applied to response time per urgency level.
    /// Lower multiplier = faster response.
    var urgencyMultipliers: [WaypointUrgency: CGFloat] = [
        .immediate: 0.05,
        .high: 0.5,
        .normal: 1.0,
        .lazy: 2.0
    ]
    /// Physics tick rate (Hz).
    var tickRate: Double = 60.0
    /// Minimum interval between typing detail waypoints derived from caret data.
    var typingDetailMinInterval: TimeInterval = 0.2
    /// Minimum spatial movement to emit a typing detail waypoint.
    var typingDetailMinDistance: CGFloat = 0.025
    /// Minimum zoom level (1.0 = no zoom).
    var minZoom: CGFloat = 1.0
    /// Maximum zoom level.
    var maxZoom: CGFloat = 2.8
    /// Post-hoc zoom intensity multiplier.
    var zoomIntensity: CGFloat = 1.0
    /// Stiffness of the soft boundary pushback force. Higher = harder boundary.
    var boundaryStiffness: CGFloat = 12.0

    /// Shot settings for zoom range and center calculation.
    var shot = ShotSettings()
    /// Spring config for pre-smoothing mouse positions.
    var springConfig: SpringCursorConfig? = .default
    /// Cursor emission settings.
    var cursor = CursorEmissionSettings()
    /// Keystroke emission settings.
    var keystroke = KeystrokeEmissionSettings()
    /// Micro tracking layer settings.
    var micro = MicroTrackerSettings()
    /// Dead zone targeting settings.
    var deadZone = DeadZoneSettings()
}
