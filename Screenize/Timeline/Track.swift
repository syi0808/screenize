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
