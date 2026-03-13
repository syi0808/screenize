import Foundation
import CoreGraphics

/// Legacy type kept only for backward-compatible decoding of old project files.
private struct LegacySegmentTransition: Codable {
    var duration: TimeInterval
    var easing: EasingCurve
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

struct CameraSegment: Identifiable, Equatable, Codable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var kind: CameraSegmentKind

    var isContinuous: Bool {
        if case .continuous = kind { return true }
        return false
    }

    init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval, kind: CameraSegmentKind) {
        self.id = id; self.startTime = startTime; self.endTime = endTime; self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, kind, transitionToNext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        endTime = try container.decode(TimeInterval.self, forKey: .endTime)
        kind = try container.decode(CameraSegmentKind.self, forKey: .kind)
        _ = try container.decodeIfPresent(LegacySegmentTransition.self, forKey: .transitionToNext)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(kind, forKey: .kind)
    }
}

// MARK: - Cursor Segment

struct CursorSegment: Identifiable, Equatable, Codable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var style: CursorStyle
    var visible: Bool
    var scale: CGFloat
    var clickFeedback: ClickFeedbackConfig

    init(id: UUID = UUID(), startTime: TimeInterval, endTime: TimeInterval,
         style: CursorStyle = .arrow, visible: Bool = true, scale: CGFloat = 2.5,
         clickFeedback: ClickFeedbackConfig = .default) {
        self.id = id; self.startTime = startTime; self.endTime = endTime
        self.style = style; self.visible = visible; self.scale = scale
        self.clickFeedback = clickFeedback
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, style, visible, scale, clickFeedback, transitionToNext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        endTime = try container.decode(TimeInterval.self, forKey: .endTime)
        style = try container.decode(CursorStyle.self, forKey: .style)
        visible = try container.decode(Bool.self, forKey: .visible)
        scale = try container.decode(CGFloat.self, forKey: .scale)
        clickFeedback = try container.decode(ClickFeedbackConfig.self, forKey: .clickFeedback)
        _ = try container.decodeIfPresent(LegacySegmentTransition.self, forKey: .transitionToNext)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(style, forKey: .style)
        try container.encode(visible, forKey: .visible)
        try container.encode(scale, forKey: .scale)
        try container.encode(clickFeedback, forKey: .clickFeedback)
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
