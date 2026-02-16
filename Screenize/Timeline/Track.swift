import Foundation
import CoreGraphics

// MARK: - Track Type

/// Track type
enum TrackType: String, Codable, CaseIterable {
    case transform   // Zoom/pan
    case cursor      // Cursor style/visibility
    case keystroke   // Keystroke overlay
    case audio       // Audio (future extension)
}

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

struct CursorSegment: Codable, Identifiable, Equatable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var style: CursorStyle
    var visible: Bool
    var scale: CGFloat
    var position: NormalizedPoint?
    var clickFeedback: ClickFeedbackConfig
    var transitionToNext: SegmentTransition

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        style: CursorStyle = .arrow,
        visible: Bool = true,
        scale: CGFloat = 2.5,
        position: NormalizedPoint? = nil,
        clickFeedback: ClickFeedbackConfig = .default,
        transitionToNext: SegmentTransition = .cut
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.style = style
        self.visible = visible
        self.scale = scale
        self.position = position
        self.clickFeedback = clickFeedback
        self.transitionToNext = transitionToNext
    }
}

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

// MARK: - Track Protocol

/// Track protocol
protocol Track: Codable, Identifiable {
    var id: UUID { get }
    var name: String { get set }
    var isEnabled: Bool { get set }
    var trackType: TrackType { get }

    /// Number of keyframes
    var keyframeCount: Int { get }
}

// MARK: - Transform Track

/// Transform (zoom/pan) track
struct TransformTrack: Track, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var keyframes: [TransformKeyframe]

    var trackType: TrackType { .transform }
    var keyframeCount: Int { keyframes.count }

    init(
        id: UUID = UUID(),
        name: String = "Transform",
        isEnabled: Bool = true,
        keyframes: [TransformKeyframe] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    // MARK: - Keyframe Management

    /// Add keyframe (keep sorted by time)
    mutating func addKeyframe(_ keyframe: TransformKeyframe) {
        keyframes.append(keyframe)
        keyframes.sort { $0.time < $1.time }
    }

    /// Remove keyframe
    mutating func removeKeyframe(id: UUID) {
        keyframes.removeAll { $0.id == id }
    }

    /// Update keyframe
    mutating func updateKeyframe(_ keyframe: TransformKeyframe) {
        if let index = keyframes.firstIndex(where: { $0.id == keyframe.id }) {
            keyframes[index] = keyframe
            keyframes.sort { $0.time < $1.time }
        }
    }

    /// Find a keyframe at a specific time
    func keyframe(at time: TimeInterval, tolerance: TimeInterval = 0.016) -> TransformKeyframe? {
        keyframes.first { abs($0.time - time) <= tolerance }
    }

    /// Keyframes within a time range
    func keyframes(in range: ClosedRange<TimeInterval>) -> [TransformKeyframe] {
        keyframes.filter { range.contains($0.time) }
    }
}

// MARK: - Cursor Track

/// Cursor track
struct CursorTrack: Track, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool

    // Default cursor settings
    var defaultStyle: CursorStyle
    var defaultScale: CGFloat
    var defaultVisible: Bool

    // Style keyframes (future extension)
    var styleKeyframes: [CursorStyleKeyframe]?

    var trackType: TrackType { .cursor }
    var keyframeCount: Int { styleKeyframes?.count ?? 0 }

    init(
        id: UUID = UUID(),
        name: String = "Cursor",
        isEnabled: Bool = true,
        defaultStyle: CursorStyle = .arrow,
        defaultScale: CGFloat = 2.5,
        defaultVisible: Bool = true,
        styleKeyframes: [CursorStyleKeyframe]? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.defaultStyle = defaultStyle
        self.defaultScale = defaultScale
        self.defaultVisible = defaultVisible
        self.styleKeyframes = styleKeyframes?.sorted { $0.time < $1.time }
    }
}

// MARK: - Keystroke Track

/// Keystroke overlay track
struct KeystrokeTrack: Track, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var keyframes: [KeystrokeKeyframe]

    var trackType: TrackType { .keystroke }
    var keyframeCount: Int { keyframes.count }

    init(
        id: UUID = UUID(),
        name: String = "Keystroke",
        isEnabled: Bool = true,
        keyframes: [KeystrokeKeyframe] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    // MARK: - Keyframe Management

    mutating func addKeyframe(_ keyframe: KeystrokeKeyframe) {
        keyframes.append(keyframe)
        keyframes.sort { $0.time < $1.time }
    }

    mutating func removeKeyframe(id: UUID) {
        keyframes.removeAll { $0.id == id }
    }

    mutating func updateKeyframe(_ keyframe: KeystrokeKeyframe) {
        if let index = keyframes.firstIndex(where: { $0.id == keyframe.id }) {
            keyframes[index] = keyframe
            keyframes.sort { $0.time < $1.time }
        }
    }

    /// Active keystroke overlays at the given time
    func activeKeystrokes(at time: TimeInterval) -> [KeystrokeKeyframe] {
        keyframes.filter { $0.isActive(at: time) }
    }
}

// MARK: - AnyTrack (Type-Erased Wrapper)

/// Type-erased track wrapper (Codable support)
enum AnyTrack: Codable, Identifiable, Equatable {
    case transform(TransformTrack)
    case cursor(CursorTrack)
    case keystroke(KeystrokeTrack)

    var id: UUID {
        switch self {
        case .transform(let track): return track.id
        case .cursor(let track): return track.id
        case .keystroke(let track): return track.id
        }
    }

    var name: String {
        get {
            switch self {
            case .transform(let track): return track.name
            case .cursor(let track): return track.name
            case .keystroke(let track): return track.name
            }
        }
        set {
            switch self {
            case .transform(var track):
                track.name = newValue
                self = .transform(track)
            case .cursor(var track):
                track.name = newValue
                self = .cursor(track)
            case .keystroke(var track):
                track.name = newValue
                self = .keystroke(track)
            }
        }
    }

    var isEnabled: Bool {
        get {
            switch self {
            case .transform(let track): return track.isEnabled
            case .cursor(let track): return track.isEnabled
            case .keystroke(let track): return track.isEnabled
            }
        }
        set {
            switch self {
            case .transform(var track):
                track.isEnabled = newValue
                self = .transform(track)
            case .cursor(var track):
                track.isEnabled = newValue
                self = .cursor(track)
            case .keystroke(var track):
                track.isEnabled = newValue
                self = .keystroke(track)
            }
        }
    }

    var trackType: TrackType {
        switch self {
        case .transform: return .transform
        case .cursor: return .cursor
        case .keystroke: return .keystroke
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TrackType.self, forKey: .type)

        switch type {
        case .transform:
            let track = try container.decode(TransformTrack.self, forKey: .data)
            self = .transform(track)
        case .cursor:
            let track = try container.decode(CursorTrack.self, forKey: .data)
            self = .cursor(track)
        case .keystroke:
            let track = try container.decode(KeystrokeTrack.self, forKey: .data)
            self = .keystroke(track)
        case .audio:
            // Future extension
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Audio track not yet supported"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .transform(let track):
            try container.encode(TrackType.transform, forKey: .type)
            try container.encode(track, forKey: .data)
        case .cursor(let track):
            try container.encode(TrackType.cursor, forKey: .type)
            try container.encode(track, forKey: .data)
        case .keystroke(let track):
            try container.encode(TrackType.keystroke, forKey: .type)
            try container.encode(track, forKey: .data)
        }
    }

    // MARK: - Convenience Initializers

    init(_ track: TransformTrack) {
        self = .transform(track)
    }

    init(_ track: CursorTrack) {
        self = .cursor(track)
    }

    init(_ track: KeystrokeTrack) {
        self = .keystroke(track)
    }
}

// MARK: - Segment Track Protocol

protocol SegmentTrack: Codable, Identifiable {
    var id: UUID { get }
    var name: String { get set }
    var isEnabled: Bool { get set }
    var trackType: TrackType { get }
    var segmentCount: Int { get }
}

struct CameraTrack: SegmentTrack, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var segments: [CameraSegment]

    var trackType: TrackType { .transform }
    var segmentCount: Int { segments.count }

    init(id: UUID = UUID(), name: String = "Camera", isEnabled: Bool = true, segments: [CameraSegment] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.segments = segments.sorted { $0.startTime < $1.startTime }
    }

    mutating func addSegment(_ segment: CameraSegment) -> Bool {
        guard !hasOverlap(segment, excluding: nil) else { return false }
        segments.append(segment)
        segments.sort { $0.startTime < $1.startTime }
        return true
    }

    mutating func updateSegment(_ segment: CameraSegment) -> Bool {
        guard let index = segments.firstIndex(where: { $0.id == segment.id }) else { return false }
        guard !hasOverlap(segment, excluding: segment.id) else { return false }
        segments[index] = segment
        segments.sort { $0.startTime < $1.startTime }
        return true
    }

    mutating func removeSegment(id: UUID) {
        segments.removeAll { $0.id == id }
    }

    func activeSegment(at time: TimeInterval) -> CameraSegment? {
        segments.first { time >= $0.startTime && time < $0.endTime }
    }

    private func hasOverlap(_ segment: CameraSegment, excluding excludedID: UUID?) -> Bool {
        segments.contains { existing in
            if let excludedID, existing.id == excludedID { return false }
            return segment.startTime < existing.endTime && segment.endTime > existing.startTime
        }
    }
}

struct CursorTrackV2: SegmentTrack, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var segments: [CursorSegment]

    var trackType: TrackType { .cursor }
    var segmentCount: Int { segments.count }

    init(id: UUID = UUID(), name: String = "Cursor", isEnabled: Bool = true, segments: [CursorSegment] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.segments = segments.sorted { $0.startTime < $1.startTime }
    }

    mutating func addSegment(_ segment: CursorSegment) -> Bool {
        guard !hasOverlap(segment, excluding: nil) else { return false }
        segments.append(segment)
        segments.sort { $0.startTime < $1.startTime }
        return true
    }

    mutating func updateSegment(_ segment: CursorSegment) -> Bool {
        guard let index = segments.firstIndex(where: { $0.id == segment.id }) else { return false }
        guard !hasOverlap(segment, excluding: segment.id) else { return false }
        segments[index] = segment
        segments.sort { $0.startTime < $1.startTime }
        return true
    }

    mutating func removeSegment(id: UUID) {
        segments.removeAll { $0.id == id }
    }

    func activeSegment(at time: TimeInterval) -> CursorSegment? {
        segments.first { time >= $0.startTime && time < $0.endTime }
    }

    private func hasOverlap(_ segment: CursorSegment, excluding excludedID: UUID?) -> Bool {
        segments.contains { existing in
            if let excludedID, existing.id == excludedID { return false }
            return segment.startTime < existing.endTime && segment.endTime > existing.startTime
        }
    }
}

struct KeystrokeTrackV2: SegmentTrack, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var segments: [KeystrokeSegment]

    var trackType: TrackType { .keystroke }
    var segmentCount: Int { segments.count }

    init(id: UUID = UUID(), name: String = "Keystroke", isEnabled: Bool = true, segments: [KeystrokeSegment] = []) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.segments = segments.sorted { $0.startTime < $1.startTime }
    }

    /// Keystroke segments are allowed to overlap.
    mutating func addSegment(_ segment: KeystrokeSegment) {
        segments.append(segment)
        segments.sort { $0.startTime < $1.startTime }
    }

    mutating func updateSegment(_ segment: KeystrokeSegment) -> Bool {
        guard let index = segments.firstIndex(where: { $0.id == segment.id }) else { return false }
        segments[index] = segment
        segments.sort { $0.startTime < $1.startTime }
        return true
    }

    mutating func removeSegment(id: UUID) {
        segments.removeAll { $0.id == id }
    }

    func activeSegments(at time: TimeInterval) -> [KeystrokeSegment] {
        segments.filter { time >= $0.startTime && time < $0.endTime }
    }
}

enum AnySegmentTrack: Codable, Identifiable, Equatable {
    case camera(CameraTrack)
    case cursor(CursorTrackV2)
    case keystroke(KeystrokeTrackV2)

    var id: UUID {
        switch self {
        case .camera(let track): return track.id
        case .cursor(let track): return track.id
        case .keystroke(let track): return track.id
        }
    }

    var name: String {
        get {
            switch self {
            case .camera(let track): return track.name
            case .cursor(let track): return track.name
            case .keystroke(let track): return track.name
            }
        }
        set {
            switch self {
            case .camera(var track):
                track.name = newValue
                self = .camera(track)
            case .cursor(var track):
                track.name = newValue
                self = .cursor(track)
            case .keystroke(var track):
                track.name = newValue
                self = .keystroke(track)
            }
        }
    }

    var isEnabled: Bool {
        get {
            switch self {
            case .camera(let track): return track.isEnabled
            case .cursor(let track): return track.isEnabled
            case .keystroke(let track): return track.isEnabled
            }
        }
        set {
            switch self {
            case .camera(var track):
                track.isEnabled = newValue
                self = .camera(track)
            case .cursor(var track):
                track.isEnabled = newValue
                self = .cursor(track)
            case .keystroke(var track):
                track.isEnabled = newValue
                self = .keystroke(track)
            }
        }
    }

    var trackType: TrackType {
        switch self {
        case .camera: return .transform
        case .cursor: return .cursor
        case .keystroke: return .keystroke
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(TrackType.self, forKey: .type)

        switch type {
        case .transform:
            let track = try container.decode(CameraTrack.self, forKey: .data)
            self = .camera(track)
        case .cursor:
            let track = try container.decode(CursorTrackV2.self, forKey: .data)
            self = .cursor(track)
        case .keystroke:
            let track = try container.decode(KeystrokeTrackV2.self, forKey: .data)
            self = .keystroke(track)
        case .audio:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Audio track not yet supported"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .camera(let track):
            try container.encode(TrackType.transform, forKey: .type)
            try container.encode(track, forKey: .data)
        case .cursor(let track):
            try container.encode(TrackType.cursor, forKey: .type)
            try container.encode(track, forKey: .data)
        case .keystroke(let track):
            try container.encode(TrackType.keystroke, forKey: .type)
            try container.encode(track, forKey: .data)
        }
    }
}
