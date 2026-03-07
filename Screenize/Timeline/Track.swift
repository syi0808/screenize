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
    var useSmoothCursor: Bool
    var springConfig: SpringCursorConfig
    var segments: [CursorSegment]

    var trackType: TrackType { .cursor }
    var segmentCount: Int { segments.count }

    init(
        id: UUID = UUID(),
        name: String = "Cursor",
        isEnabled: Bool = true,
        useSmoothCursor: Bool = true,
        springConfig: SpringCursorConfig = .default,
        segments: [CursorSegment] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.useSmoothCursor = useSmoothCursor
        self.springConfig = springConfig
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

    // MARK: - Codable (backward-compatible)

    private enum CodingKeys: String, CodingKey {
        case id, name, isEnabled, useSmoothCursor, springConfig, segments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        useSmoothCursor = try container.decode(Bool.self, forKey: .useSmoothCursor)
        springConfig = try container.decodeIfPresent(SpringCursorConfig.self, forKey: .springConfig)
            ?? .default
        segments = try container.decode([CursorSegment].self, forKey: .segments)
        segments.sort { $0.startTime < $1.startTime }
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

// MARK: - Audio Track

struct AudioTrack: SegmentTrack, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var audioSource: AudioSource
    var segments: [AudioSegment]

    var trackType: TrackType { .audio }
    var segmentCount: Int { segments.count }

    init(
        id: UUID = UUID(),
        name: String = "Mic Audio",
        isEnabled: Bool = true,
        audioSource: AudioSource = .microphone,
        segments: [AudioSegment] = []
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.audioSource = audioSource
        self.segments = segments.sorted { $0.startTime < $1.startTime }
    }

    @discardableResult
    mutating func addSegment(_ segment: AudioSegment) -> Bool {
        guard !hasOverlap(segment, excluding: nil) else { return false }
        segments.append(segment)
        segments.sort { $0.startTime < $1.startTime }
        return true
    }

    mutating func updateSegment(_ segment: AudioSegment) -> Bool {
        guard let index = segments.firstIndex(where: { $0.id == segment.id }) else { return false }
        guard !hasOverlap(segment, excluding: segment.id) else { return false }
        segments[index] = segment
        segments.sort { $0.startTime < $1.startTime }
        return true
    }

    mutating func removeSegment(id: UUID) {
        segments.removeAll { $0.id == id }
    }

    func activeSegment(at time: TimeInterval) -> AudioSegment? {
        segments.first { time >= $0.startTime && time < $0.endTime }
    }

    private func hasOverlap(_ segment: AudioSegment, excluding excludedID: UUID?) -> Bool {
        segments.contains { existing in
            if let excludedID, existing.id == excludedID { return false }
            return segment.startTime < existing.endTime && segment.endTime > existing.startTime
        }
    }
}

enum AnySegmentTrack: Codable, Identifiable, Equatable {
    case camera(CameraTrack)
    case cursor(CursorTrackV2)
    case keystroke(KeystrokeTrackV2)
    case audio(AudioTrack)

    var id: UUID {
        switch self {
        case .camera(let track): return track.id
        case .cursor(let track): return track.id
        case .keystroke(let track): return track.id
        case .audio(let track): return track.id
        }
    }

    var name: String {
        get {
            switch self {
            case .camera(let track): return track.name
            case .cursor(let track): return track.name
            case .keystroke(let track): return track.name
            case .audio(let track): return track.name
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
            case .audio(var track):
                track.name = newValue
                self = .audio(track)
            }
        }
    }

    var isEnabled: Bool {
        get {
            switch self {
            case .camera(let track): return track.isEnabled
            case .cursor(let track): return track.isEnabled
            case .keystroke(let track): return track.isEnabled
            case .audio(let track): return track.isEnabled
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
            case .audio(var track):
                track.isEnabled = newValue
                self = .audio(track)
            }
        }
    }

    var trackType: TrackType {
        switch self {
        case .camera: return .transform
        case .cursor: return .cursor
        case .keystroke: return .keystroke
        case .audio: return .audio
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
            let track = try container.decode(AudioTrack.self, forKey: .data)
            self = .audio(track)
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
        case .audio(let track):
            try container.encode(TrackType.audio, forKey: .type)
            try container.encode(track, forKey: .data)
        }
    }
}
