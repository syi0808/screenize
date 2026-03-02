import Foundation
import CoreGraphics

// MARK: - Keyframe Protocol

/// Time-based keyframe protocol
protocol TimedKeyframe: Codable, Identifiable {
    var id: UUID { get }
    var time: TimeInterval { get set }
    var easing: EasingCurve { get set }
}

/// Interpolatable value protocol
protocol Interpolatable {
    func interpolated(to target: Self, amount: CGFloat) -> Self
}

// MARK: - Transform Keyframe

/// Transform (zoom/pan) keyframe
struct TransformKeyframe: TimedKeyframe, Equatable {
    let id: UUID
    var time: TimeInterval           // Measured in seconds
    var zoom: CGFloat                // 1.0 = 100%, 2.0 = 200%
    var center: NormalizedPoint      // 0.0–1.0 (normalized, top-left origin)
    var easing: EasingCurve          // Interpolation mode to the next keyframe

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        time: TimeInterval,
        zoom: CGFloat = 1.0,
        center: NormalizedPoint = .center,
        easing: EasingCurve = .springDefault
    ) {
        self.id = id
        self.time = time
        self.zoom = max(1.0, zoom)  // Minimum 1.0
        self.center = center.clamped()
        self.easing = easing
    }

    /// Identity keyframe (no zoom, centered)
    static func identity(at time: TimeInterval) -> Self {
        Self(time: time, zoom: 1.0, center: .center)
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
    }
}

/// Transform value (for interpolation)
struct TransformValue: Codable, Interpolatable, Equatable {
    let zoom: CGFloat
    let center: NormalizedPoint

    func interpolated(to target: Self, amount: CGFloat) -> Self {
        Self(
            zoom: zoom + (target.zoom - zoom) * amount,
            center: NormalizedPoint(
                x: center.x + (target.center.x - center.x) * amount,
                y: center.y + (target.center.y - center.y) * amount
            )
        )
    }

    /// Interpolation tuned for window mode
    /// In screen mode center and zoom interpolate independently,
    /// but in window mode visual position = center × zoom.
    /// Independently interpolating center and zoom would skew visual position.
    /// This method linearly interpolates the anchor point (center × zoom)
    /// so the visual position changes at the same rate as zoom.
    func interpolatedForWindowMode(to target: Self, amount: CGFloat) -> Self {
        // Interpolate zoom as usual
        let interpolatedZoom = zoom + (target.zoom - zoom) * amount

        // Anchor point = center × zoom (determines visual position)
        let startAnchorX = center.x * zoom
        let startAnchorY = center.y * zoom
        let endAnchorX = target.center.x * target.zoom
        let endAnchorY = target.center.y * target.zoom

        // Linearly interpolate the anchor point
        let interpolatedAnchorX = startAnchorX + (endAnchorX - startAnchorX) * amount
        let interpolatedAnchorY = startAnchorY + (endAnchorY - startAnchorY) * amount

        // interpolated center = interpolated anchor / interpolated zoom
        // Clamp zoom to avoid zero
        let safeZoom = max(interpolatedZoom, 0.001)
        let interpolatedCenterX = interpolatedAnchorX / safeZoom
        let interpolatedCenterY = interpolatedAnchorY / safeZoom

        return Self(
            zoom: interpolatedZoom,
            center: NormalizedPoint(x: interpolatedCenterX, y: interpolatedCenterY)
        )
    }

    static let identity = Self(zoom: 1.0, center: .center)
}

extension TransformKeyframe {
    var value: TransformValue {
        TransformValue(zoom: zoom, center: center)
    }
}

// MARK: - Cursor Style Keyframe (future extension)

/// Cursor styles
enum CursorStyle: String, Codable, CaseIterable {
    case arrow
    case pointer
    case iBeam
    case crosshair
    case openHand
    case closedHand
    case contextMenu

    var displayName: String {
        switch self {
        case .arrow: return "Arrow"
        case .pointer: return "Pointer"
        case .iBeam: return "I-Beam"
        case .crosshair: return "Crosshair"
        case .openHand: return "Open Hand"
        case .closedHand: return "Closed Hand"
        case .contextMenu: return "Context Menu"
        }
    }

    var sfSymbolName: String {
        switch self {
        case .arrow: return "cursorarrow"
        case .pointer: return "hand.point.up.left"
        case .iBeam: return "character.cursor.ibeam"
        case .crosshair: return "plus"
        case .openHand: return "hand.raised"
        case .closedHand: return "hand.raised.fill"
        case .contextMenu: return "contextualmenu.and.cursorarrow"
        }
    }
}

/// Cursor style keyframe (for future extension)
struct CursorStyleKeyframe: TimedKeyframe, Equatable {
    let id: UUID
    var time: TimeInterval
    var style: CursorStyle
    var visible: Bool
    var scale: CGFloat
    var easing: EasingCurve

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        time: TimeInterval,
        style: CursorStyle = .arrow,
        visible: Bool = true,
        scale: CGFloat = 2.5,
        easing: EasingCurve = .springSnappy
    ) {
        self.id = id
        self.time = time
        self.style = style
        self.visible = visible
        self.scale = max(0.5, scale)
        self.easing = easing
    }
}

// MARK: - Keystroke Keyframe

/// Keystroke overlay keyframe
struct KeystrokeKeyframe: TimedKeyframe, Equatable {
    let id: UUID
    var time: TimeInterval           // Keystroke start time
    var displayText: String          // Display text (e.g., "⌘C", "⇧⌘Z")
    var duration: TimeInterval       // Overlay display duration
    var fadeInDuration: TimeInterval  // Fade-in duration
    var fadeOutDuration: TimeInterval // Fade-out duration
    var position: NormalizedPoint    // Overlay center position (default: bottom-center)
    var easing: EasingCurve

    init(
        id: UUID = UUID(),
        time: TimeInterval,
        displayText: String,
        duration: TimeInterval = 1.5,
        fadeInDuration: TimeInterval = 0.15,
        fadeOutDuration: TimeInterval = 0.3,
        position: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.95),
        easing: EasingCurve = .easeOut
    ) {
        self.id = id
        self.time = time
        self.displayText = displayText
        self.duration = max(0.2, duration)
        self.fadeInDuration = max(0, fadeInDuration)
        self.fadeOutDuration = max(0, fadeOutDuration)
        self.position = position
        self.easing = easing
    }

    /// Overlay end time
    var endTime: TimeInterval {
        time + duration
    }

    /// Check if the overlay is active at the given time
    func isActive(at currentTime: TimeInterval) -> Bool {
        currentTime >= time && currentTime <= endTime
    }

    /// Progress at the given time (0.0-1.0)
    func progress(at currentTime: TimeInterval) -> CGFloat {
        guard isActive(at: currentTime), duration > 0 else { return 0 }
        let elapsed = currentTime - time
        return CGFloat(elapsed / duration)
    }

    /// Opacity at the given time (with fade-in/out applied)
    func opacity(at currentTime: TimeInterval) -> CGFloat {
        guard isActive(at: currentTime) else { return 0 }
        let elapsed = currentTime - time
        let remaining = endTime - currentTime

        // Fade in
        if elapsed < fadeInDuration, fadeInDuration > 0 {
            return CGFloat(elapsed / fadeInDuration)
        }
        // Fade out
        if remaining < fadeOutDuration, fadeOutDuration > 0 {
            return CGFloat(remaining / fadeOutDuration)
        }
        // Fully opaque
        return 1.0
    }
}
