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
        mouseDownDuration: 0.10,
        mouseUpDuration: 0.25,
        mouseUpSpring: .spring(dampingRatio: 0.92, response: 0.25)
    )
}

// MARK: - Camera Segment

enum CameraSegmentKind: Codable, Equatable {
    case continuous(transforms: [TimedTransform])
    case manual(
        startTransform: TransformValue,
        endTransform: TransformValue
    )

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case transforms
        case startTransform
        case endTransform
        case interpolation  // kept for backward-compat decoding only
    }

    private enum KindType: String, Codable {
        case continuous
        case manual
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)
        switch type {
        case .continuous:
            let transforms = try container.decode([TimedTransform].self, forKey: .transforms)
            self = .continuous(transforms: transforms)
        case .manual:
            let startTransform = try container.decode(TransformValue.self, forKey: .startTransform)
            let endTransform = try container.decode(TransformValue.self, forKey: .endTransform)
            // interpolation was removed; decode and discard for backward compatibility
            _ = try container.decodeIfPresent(EasingCurve.self, forKey: .interpolation)
            self = .manual(
                startTransform: startTransform,
                endTransform: endTransform
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .continuous(let transforms):
            try container.encode(KindType.continuous, forKey: .type)
            try container.encode(transforms, forKey: .transforms)
        case .manual(let startTransform, let endTransform):
            try container.encode(KindType.manual, forKey: .type)
            try container.encode(startTransform, forKey: .startTransform)
            try container.encode(endTransform, forKey: .endTransform)
        }
    }
}

struct CameraSegment: Codable, Identifiable, Equatable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var kind: CameraSegmentKind
    var transitionToNext: SegmentTransition

    var isContinuous: Bool {
        if case .continuous = kind { return true }
        return false
    }

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        kind: CameraSegmentKind,
        transitionToNext: SegmentTransition = .default
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.kind = kind
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
