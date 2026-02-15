import Foundation
import CoreGraphics

/// Timeline
/// Contains multiple tracks, each holding keyframes
struct Timeline: Codable, Equatable {
    /// List of tracks
    var tracks: [AnyTrack]

    /// Total timeline duration (seconds)
    var duration: TimeInterval

    /// Trim start time (based on the original video timeline)
    var trimStart: TimeInterval

    /// Trim end time (based on the original video timeline; nil uses duration)
    var trimEnd: TimeInterval?

    init(tracks: [AnyTrack] = [], duration: TimeInterval = 0, trimStart: TimeInterval = 0, trimEnd: TimeInterval? = nil) {
        self.tracks = tracks
        self.duration = duration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
    }

    // MARK: - Trim Properties

    /// Valid trim start time
    var effectiveTrimStart: TimeInterval {
        max(0, min(trimStart, duration))
    }

    /// Valid trim end time
    var effectiveTrimEnd: TimeInterval {
        min(duration, trimEnd ?? duration)
    }

    /// Length of the trimmed segment
    var trimmedDuration: TimeInterval {
        max(0, effectiveTrimEnd - effectiveTrimStart)
    }

    /// Whether trimming is applied
    var isTrimmed: Bool {
        effectiveTrimStart > 0 || effectiveTrimEnd < duration
    }

    /// Check if a time falls within the trim range
    func isTimeInTrimRange(_ time: TimeInterval) -> Bool {
        time >= effectiveTrimStart && time <= effectiveTrimEnd
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case tracks, duration, trimStart, trimEnd
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decodedTracks: [AnyTrack] = []
        var tracksContainer = try container.nestedUnkeyedContainer(forKey: .tracks)
        while !tracksContainer.isAtEnd {
            if let track = try tracksContainer.decode(DiscardableJSON<AnyTrack>.self).value {
                decodedTracks.append(track)
            }
        }
        tracks = decodedTracks
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        // Backward compatibility: trimStart/trimEnd may be missing
        trimStart = try container.decodeIfPresent(TimeInterval.self, forKey: .trimStart) ?? 0
        trimEnd = try container.decodeIfPresent(TimeInterval.self, forKey: .trimEnd)
    }

    /// Create a timeline initialized with default tracks
    static func withDefaultTracks(duration: TimeInterval, trimStart: TimeInterval = 0, trimEnd: TimeInterval? = nil) -> Self {
        Self(
            tracks: [
                .transform(TransformTrack()),
                .cursor(CursorTrack()),
                .keystroke(KeystrokeTrack())
            ],
            duration: duration,
            trimStart: trimStart,
            trimEnd: trimEnd
        )
    }

    // MARK: - Track Access

    /// Transform track (first)
    var transformTrack: TransformTrack? {
        get {
            for case .transform(let track) in tracks {
                return track
            }
            return nil
        }
        set {
            if let newTrack = newValue {
                if let index = tracks.firstIndex(where: { $0.trackType == .transform }) {
                    tracks[index] = .transform(newTrack)
                } else {
                    tracks.insert(.transform(newTrack), at: 0)
                }
            }
        }
    }

    /// Cursor track (first)
    var cursorTrack: CursorTrack? {
        get {
            for case .cursor(let track) in tracks {
                return track
            }
            return nil
        }
        set {
            if let newTrack = newValue {
                if let index = tracks.firstIndex(where: { $0.trackType == .cursor }) {
                    tracks[index] = .cursor(newTrack)
                } else {
                    tracks.append(.cursor(newTrack))
                }
            }
        }
    }

    /// Keystroke track (first)
    var keystrokeTrack: KeystrokeTrack? {
        get {
            for case .keystroke(let track) in tracks {
                return track
            }
            return nil
        }
        set {
            if let newTrack = newValue {
                if let index = tracks.firstIndex(where: { $0.trackType == .keystroke }) {
                    tracks[index] = .keystroke(newTrack)
                } else {
                    tracks.append(.keystroke(newTrack))
                }
            }
        }
    }

    // MARK: - Track Management

    /// Add a track
    mutating func addTrack(_ track: AnyTrack) {
        tracks.append(track)
    }

    /// Remove a track
    mutating func removeTrack(id: UUID) {
        tracks.removeAll { $0.id == id }
    }

    /// Find a track
    func track(id: UUID) -> AnyTrack? {
        tracks.first { $0.id == id }
    }

    /// Update a track
    mutating func updateTrack(_ track: AnyTrack) {
        if let index = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[index] = track
        }
    }

    // MARK: - Keyframe Query

    /// Total keyframe count
    var totalKeyframeCount: Int {
        var count = 0
        for track in tracks {
            switch track {
            case .transform(let t):
                count += t.keyframes.count
            case .cursor(let t):
                count += t.styleKeyframes?.count ?? 0
            case .keystroke(let t):
                count += t.keyframes.count
            }
        }
        return count
    }

    /// Check if keyframes exist within a time range
    func hasKeyframes(in range: ClosedRange<TimeInterval>) -> Bool {
        for track in tracks {
            switch track {
            case .transform(let t):
                if t.keyframes.contains(where: { range.contains($0.time) }) {
                    return true
                }
            case .cursor(let t):
                if let keyframes = t.styleKeyframes,
                   keyframes.contains(where: { range.contains($0.time) }) {
                    return true
                }
            case .keystroke(let t):
                if t.keyframes.contains(where: { range.contains($0.time) }) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Validation

    /// Determine if the timeline is empty
    var isEmpty: Bool {
        totalKeyframeCount == 0
    }

    /// Determine if the timeline is valid
    var isValid: Bool {
        duration > 0
    }
}

private struct DiscardableJSON<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}
