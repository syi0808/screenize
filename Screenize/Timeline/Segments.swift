import Foundation
import CoreGraphics

// MARK: - Segment Transition

/// Transition applied when moving from one segment to the next.
struct SegmentTransition: Codable, Equatable, Hashable {
    var duration: TimeInterval
    var easing: EasingCurve

    static let cut = Self(duration: 0, easing: .linear)
    static let `default` = Self(duration: 0.35, easing: .easeInOut)
}

/// Per-segment cursor follow configuration for camera movement.
struct CursorFollowConfig: Codable, Equatable, Hashable {
    var deadZone: CGFloat
    var springDamping: CGFloat
    var response: CGFloat
    var lookAhead: CGFloat
    var maxSpeed: CGFloat

    static let `default` = Self(
        deadZone: 0.04,
        springDamping: 0.9,
        response: 0.25,
        lookAhead: 0.04,
        maxSpeed: 5.0
    )
}

/// Click feedback style for cursor rendering.
struct ClickFeedbackConfig: Codable, Equatable, Hashable {
    var mouseDownScale: CGFloat
    var mouseDownDuration: TimeInterval
    var mouseUpDuration: TimeInterval
    var mouseUpSpring: EasingCurve

    static let `default` = Self(
        mouseDownScale: 0.75,
        mouseDownDuration: 0.08,
        mouseUpDuration: 0.15,
        mouseUpSpring: .spring(dampingRatio: 0.6, response: 0.3)
    )
}

// MARK: - Camera Segment

enum CameraSegmentMode: String, Codable {
    case manual
    case followCursor
}

struct CameraSegment: Codable, Identifiable, Equatable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var startTransform: TransformValue
    var endTransform: TransformValue
    var interpolation: EasingCurve
    var mode: CameraSegmentMode
    var cursorFollow: CursorFollowConfig
    var transitionToNext: SegmentTransition

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        startTransform: TransformValue,
        endTransform: TransformValue,
        interpolation: EasingCurve = .easeInOut,
        mode: CameraSegmentMode = .manual,
        cursorFollow: CursorFollowConfig = .default,
        transitionToNext: SegmentTransition = .default
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.startTransform = startTransform
        self.endTransform = endTransform
        self.interpolation = interpolation
        self.mode = mode
        self.cursorFollow = cursorFollow
        self.transitionToNext = transitionToNext
    }
}

// MARK: - Cursor Segment

struct CursorSegment: Codable, Identifiable, Equatable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var style: CursorStyle
    var visible: Bool
    var scale: CGFloat
    var clickFeedback: ClickFeedbackConfig
    var transitionToNext: SegmentTransition

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        style: CursorStyle = .arrow,
        visible: Bool = true,
        scale: CGFloat = 2.5,
        clickFeedback: ClickFeedbackConfig = .default,
        transitionToNext: SegmentTransition = .cut
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.style = style
        self.visible = visible
        self.scale = scale
        self.clickFeedback = clickFeedback
        self.transitionToNext = transitionToNext
    }
}

// MARK: - Keystroke Segment

struct KeystrokeSegment: Codable, Identifiable, Equatable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var displayText: String
    var position: NormalizedPoint
    var fadeInDuration: TimeInterval
    var fadeOutDuration: TimeInterval

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        displayText: String,
        position: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.95),
        fadeInDuration: TimeInterval = 0.15,
        fadeOutDuration: TimeInterval = 0.3
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.displayText = displayText
        self.position = position
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
    }
}

// MARK: - Audio Segment

struct AudioSegment: Codable, Identifiable, Equatable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    /// Per-segment volume multiplier (0.0–1.0)
    var volume: Float
    var isMuted: Bool

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        volume: Float = 1.0,
        isMuted: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.volume = volume
        self.isMuted = isMuted
    }
}

// MARK: - Audio Source

enum AudioSource: String, Codable {
    case system
    case microphone
}
