import Foundation
import CoreGraphics

// MARK: - Micro Tracker Settings

/// Configuration for the micro tracking layer.
struct MicroTrackerSettings {
    /// Dead zone as fraction of viewport half-size. Micro offset inactive within this zone.
    var deadZoneRatio: CGFloat = 0.4
    /// Maximum micro offset as fraction of viewport half-size.
    var maxOffsetRatio: CGFloat = 0.3
    /// Spring damping ratio for micro offset.
    var dampingRatio: CGFloat = 0.85
    /// Spring response time in seconds.
    var response: CGFloat = 0.15
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

}

// MARK: - Continuous Camera Settings

/// Configuration for the continuous camera physics simulation.
struct ContinuousCameraSettings {
    /// Damping ratio for position springs (1.0 = critical, <1 = underdamped).
    var positionDampingRatio: CGFloat = 1.0
    /// Response time in seconds for position springs.
    var positionResponse: CGFloat = 0.8
    /// Damping ratio for zoom spring.
    var zoomDampingRatio: CGFloat = 1.0
    /// Response time in seconds for zoom spring.
    var zoomResponse: CGFloat = 0.8
    /// Duration in seconds over which urgency transitions are blended.
    var urgencyBlendDuration: TimeInterval = 0.3
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
    var boundaryStiffness: CGFloat = 80.0

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
}
