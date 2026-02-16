import Foundation
import CoreGraphics

// MARK: - Evaluated Frame State

/// Evaluated frame state at a specific time
/// Result of merging keyframes from all tracks
struct EvaluatedFrameState {
    /// Evaluated time
    let time: TimeInterval

    /// Transform state (zoom/pan)
    let transform: TransformState

    /// Cursor state
    let cursor: CursorState

    /// Active keystroke overlays
    let keystrokes: [ActiveKeystroke]

    init(
        time: TimeInterval,
        transform: TransformState,
        cursor: CursorState,
        keystrokes: [ActiveKeystroke] = []
    ) {
        self.time = time
        self.transform = transform
        self.cursor = cursor
        self.keystrokes = keystrokes
    }
}

// MARK: - Transform State

/// Transform state for the current frame
struct TransformState: Equatable {
    /// Zoom scale (1.0 = 100%)
    let zoom: CGFloat

    /// Center of zoom (0.0 - 1.0, normalized, origin at top-left)
    let center: NormalizedPoint

    /// Zoom velocity (per second, for motion blur)
    let zoomVelocity: CGFloat

    /// Pan velocity (normalized per second, for motion blur)
    let panVelocity: CGFloat

    /// Pan direction (radians, for motion blur)
    let panDirection: CGFloat

    /// Indicates whether zooming is active
    var isZooming: Bool {
        zoom > 1.01  // Consider zooming if zoom exceeds 1%
    }

    /// Identity state (no zoom, centered)
    static let identity = Self(zoom: 1.0, center: .center)

    // MARK: - Initialization

    init(
        zoom: CGFloat,
        center: NormalizedPoint,
        zoomVelocity: CGFloat = 0,
        panVelocity: CGFloat = 0,
        panDirection: CGFloat = 0
    ) {
        self.zoom = max(1.0, zoom)
        self.center = center.clamped()
        self.zoomVelocity = zoomVelocity
        self.panVelocity = panVelocity
        self.panDirection = panDirection
    }

    /// Initialize from TransformValue
    init(from value: TransformValue) {
        self.init(zoom: value.zoom, center: value.center)
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
    }
}

// MARK: - Cursor State

/// Cursor state for the current frame
struct CursorState {
    /// Position (normalized, 0-1, top-left origin)
    let position: NormalizedPoint

    /// Cursor style
    let style: CursorStyle

    /// Size scale
    let scale: CGFloat

    /// Visibility
    let visible: Bool

    /// Indicates whether it is clicking
    let isClicking: Bool

    /// Click type (only while clicking)
    let clickType: ClickType?

    /// Velocity (normalized per second, for motion blur)
    let velocity: CGFloat

    /// Movement direction (radians, for motion blur)
    let movementDirection: CGFloat

    /// Click scale modifier (1.0 = neutral)
    let clickScaleModifier: CGFloat

    // MARK: - Initialization

    init(
        position: NormalizedPoint,
        style: CursorStyle = .arrow,
        scale: CGFloat = 2.5,
        visible: Bool = true,
        isClicking: Bool = false,
        clickType: ClickType? = nil,
        velocity: CGFloat = 0,
        movementDirection: CGFloat = 0,
        clickScaleModifier: CGFloat = 1.0
    ) {
        self.position = position.clamped()
        self.style = style
        self.scale = max(0.5, scale)
        self.visible = visible
        self.isClicking = isClicking
        self.clickType = clickType
        self.velocity = velocity
        self.movementDirection = movementDirection
        self.clickScaleModifier = max(0.1, clickScaleModifier)
    }

    /// Initialization for backward compatibility
    init(
        position: CGPoint,
        style: CursorStyle = .arrow,
        scale: CGFloat = 2.5,
        visible: Bool = true,
        isClicking: Bool = false,
        clickType: ClickType? = nil,
        velocity: CGFloat = 0,
        movementDirection: CGFloat = 0,
        clickScaleModifier: CGFloat = 1.0
    ) {
        self.init(
            position: NormalizedPoint(position),
            style: style,
            scale: scale,
            visible: visible,
            isClicking: isClicking,
            clickType: clickType,
            velocity: velocity,
            movementDirection: movementDirection,
            clickScaleModifier: clickScaleModifier
        )
    }

    /// Default cursor state
    static func `default`(at position: NormalizedPoint) -> Self {
        Self(position: position)
    }

    /// Hidden cursor
    static let hidden = Self(
        position: .center,
        visible: false
    )

    private static func clamp(_ value: CGFloat) -> CGFloat {
        max(0, min(1, value))
    }
}

// MARK: - Active Keystroke

/// Currently active keystroke overlay
struct ActiveKeystroke {
    /// Text to display
    let displayText: String

    /// Opacity (with fade-in/out applied)
    let opacity: CGFloat

    /// Animation progress (0.0-1.0)
    let progress: CGFloat

    /// Overlay center position (normalized, 0-1, top-left origin)
    let position: NormalizedPoint

    init(displayText: String, opacity: CGFloat, progress: CGFloat, position: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.95)) {
        self.displayText = displayText
        self.opacity = max(0, min(1, opacity))
        self.progress = max(0, min(1, progress))
        self.position = position
    }

    /// Created from a KeystrokeKeyframe
    init(from keyframe: KeystrokeKeyframe, at time: TimeInterval) {
        self.displayText = keyframe.displayText
        self.opacity = keyframe.opacity(at: time)
        self.progress = keyframe.progress(at: time)
        self.position = keyframe.position
    }
}

// Note: ClickType is now defined in Models/ClickType.swift
