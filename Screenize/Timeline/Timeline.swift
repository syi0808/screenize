import Foundation

/// Segment-based timeline model.
struct Timeline: Codable, Equatable {
    /// Segment tracks for editor/rendering.
    var tracks: [AnySegmentTrack]

    /// Total timeline duration in seconds.
    var duration: TimeInterval

    /// Trim start time on source timeline.
    var trimStart: TimeInterval

    /// Trim end time on source timeline; nil means `duration`.
    var trimEnd: TimeInterval?

    /// Pre-computed continuous camera path from physics simulation.
    /// When set, FrameEvaluator uses this instead of CameraTrack segments.
    var continuousTransforms: [TimedTransform]?

    init(
        tracks: [AnySegmentTrack] = [],
        duration: TimeInterval = 0,
        trimStart: TimeInterval = 0,
        trimEnd: TimeInterval? = nil,
        continuousTransforms: [TimedTransform]? = nil
    ) {
        self.tracks = tracks
        self.duration = duration
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.continuousTransforms = continuousTransforms
    }

    // MARK: - Trim

    var effectiveTrimStart: TimeInterval {
        max(0, min(trimStart, duration))
    }

    var effectiveTrimEnd: TimeInterval {
        min(duration, trimEnd ?? duration)
    }

    var trimmedDuration: TimeInterval {
        max(0, effectiveTrimEnd - effectiveTrimStart)
    }

    var isTrimmed: Bool {
        effectiveTrimStart > 0 || effectiveTrimEnd < duration
    }

    func isTimeInTrimRange(_ time: TimeInterval) -> Bool {
        time >= effectiveTrimStart && time <= effectiveTrimEnd
    }

    // MARK: - Default

    static func withDefaultTracks(duration: TimeInterval, trimStart: TimeInterval = 0, trimEnd: TimeInterval? = nil) -> Self {
        Self(
            tracks: [
                .camera(CameraTrack()),
                .cursor(CursorTrackV2()),
                .keystroke(KeystrokeTrackV2()),
            ],
            duration: duration,
            trimStart: trimStart,
            trimEnd: trimEnd
        )
    }

    // MARK: - Track Access

    var cameraTrack: CameraTrack? {
        get {
            for case .camera(let track) in tracks {
                return track
            }
            return nil
        }
        set {
            guard let newValue else { return }
            if let index = tracks.firstIndex(where: { $0.trackType == .transform }) {
                tracks[index] = .camera(newValue)
            } else {
                tracks.insert(.camera(newValue), at: 0)
            }
        }
    }

    var cursorTrackV2: CursorTrackV2? {
        get {
            for case .cursor(let track) in tracks {
                return track
            }
            return nil
        }
        set {
            guard let newValue else { return }
            if let index = tracks.firstIndex(where: { $0.trackType == .cursor }) {
                tracks[index] = .cursor(newValue)
            } else {
                tracks.append(.cursor(newValue))
            }
        }
    }

    var keystrokeTrackV2: KeystrokeTrackV2? {
        get {
            for case .keystroke(let track) in tracks {
                return track
            }
            return nil
        }
        set {
            guard let newValue else { return }
            if let index = tracks.firstIndex(where: { $0.trackType == .keystroke }) {
                tracks[index] = .keystroke(newValue)
            } else {
                tracks.append(.keystroke(newValue))
            }
        }
    }

    var audioTrack: AudioTrack? {
        get {
            for case .audio(let track) in tracks {
                return track
            }
            return nil
        }
        set {
            guard let newValue else { return }
            if let index = tracks.firstIndex(where: { $0.trackType == .audio }) {
                tracks[index] = .audio(newValue)
            } else {
                tracks.append(.audio(newValue))
            }
        }
    }

    var micAudioTrack: AudioTrack? {
        get {
            for case .audio(let track) in tracks where track.audioSource == .microphone {
                return track
            }
            return nil
        }
        set {
            guard let newValue else { return }
            if let index = tracks.firstIndex(where: {
                if case .audio(let t) = $0, t.audioSource == .microphone { return true }
                return false
            }) {
                tracks[index] = .audio(newValue)
            } else {
                tracks.append(.audio(newValue))
            }
        }
    }

    var systemAudioTrack: AudioTrack? {
        get {
            for case .audio(let track) in tracks where track.audioSource == .system {
                return track
            }
            return nil
        }
        set {
            guard let newValue else { return }
            if let index = tracks.firstIndex(where: {
                if case .audio(let t) = $0, t.audioSource == .system { return true }
                return false
            }) {
                tracks[index] = .audio(newValue)
            } else {
                tracks.append(.audio(newValue))
            }
        }
    }

    // MARK: - Validation

    var totalSegmentCount: Int {
        tracks.reduce(into: 0) { count, track in
            switch track {
            case .camera(let cameraTrack):
                count += cameraTrack.segmentCount
            case .cursor(let cursorTrack):
                count += cursorTrack.segmentCount
            case .keystroke(let keystrokeTrack):
                count += keystrokeTrack.segmentCount
            case .audio(let audioTrack):
                count += audioTrack.segmentCount
            }
        }
    }

    var isEmpty: Bool {
        totalSegmentCount == 0
    }

    var isValid: Bool {
        duration > 0
    }
}
