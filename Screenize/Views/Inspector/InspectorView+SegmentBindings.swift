import SwiftUI

// MARK: - Segment Bindings

extension InspectorView {

    func cameraSegmentBinding(for id: UUID) -> Binding<CameraSegment>? {
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .transform }),
              case .camera(let track) = timeline.tracks[trackIndex],
              track.segments.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                if case .camera(let track) = self.timeline.tracks[trackIndex],
                   let segmentIndex = track.segments.firstIndex(where: { $0.id == id }) {
                    return track.segments[segmentIndex]
                }

                return CameraSegment(
                    startTime: 0,
                    endTime: 1,
                    kind: .manual(startTransform: .identity, endTransform: .identity)
                )
            },
            set: { updated in
                if case .camera(var track) = self.timeline.tracks[trackIndex],
                   track.updateSegment(updated) {
                    self.timeline.tracks[trackIndex] = .camera(track)
                    self.onSegmentChange?()
                }
            }
        )
    }

    func cursorSegmentBinding(for id: UUID) -> Binding<CursorSegment>? {
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .cursor }),
              case .cursor(let track) = timeline.tracks[trackIndex],
              track.segments.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                if case .cursor(let track) = self.timeline.tracks[trackIndex],
                   let segmentIndex = track.segments.firstIndex(where: { $0.id == id }) {
                    return track.segments[segmentIndex]
                }

                return CursorSegment(startTime: 0, endTime: 1)
            },
            set: { updated in
                if case .cursor(var track) = self.timeline.tracks[trackIndex],
                   track.updateSegment(updated) {
                    self.timeline.tracks[trackIndex] = .cursor(track)
                    self.onSegmentChange?()
                }
            }
        )
    }

    func keystrokeSegmentBinding(for id: UUID) -> Binding<KeystrokeSegment>? {
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }),
              case .keystroke(let track) = timeline.tracks[trackIndex],
              track.segments.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                if case .keystroke(let track) = self.timeline.tracks[trackIndex],
                   let segmentIndex = track.segments.firstIndex(where: { $0.id == id }) {
                    return track.segments[segmentIndex]
                }

                return KeystrokeSegment(startTime: 0, endTime: 1, displayText: "")
            },
            set: { updated in
                if case .keystroke(var track) = self.timeline.tracks[trackIndex],
                   track.updateSegment(updated) {
                    self.timeline.tracks[trackIndex] = .keystroke(track)
                    self.onSegmentChange?()
                }
            }
        )
    }

    func audioSegmentBinding(for id: UUID) -> Binding<AudioSegment>? {
        guard let trackIndex = timeline.tracks.firstIndex(where: {
            if case .audio(let t) = $0, t.segments.contains(where: { $0.id == id }) { return true }
            return false
        }),
              case .audio(let track) = timeline.tracks[trackIndex],
              track.segments.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                if case .audio(let track) = self.timeline.tracks[trackIndex],
                   let segmentIndex = track.segments.firstIndex(where: { $0.id == id }) {
                    return track.segments[segmentIndex]
                }

                return AudioSegment(startTime: 0, endTime: 1)
            },
            set: { updated in
                if case .audio(var track) = self.timeline.tracks[trackIndex],
                   track.updateSegment(updated) {
                    self.timeline.tracks[trackIndex] = .audio(track)
                    self.onSegmentChange?()
                }
            }
        )
    }

    func trackName(_ trackType: TrackType) -> String {
        switch trackType {
        case .transform:
            return L10n.string("inspector.track.camera", defaultValue: "Camera")
        case .cursor:
            return L10n.string("inspector.track.cursor", defaultValue: "Cursor")
        case .keystroke:
            return L10n.string("inspector.track.keystroke", defaultValue: "Keystroke")
        case .audio:
            return L10n.string("inspector.track.audio", defaultValue: "Audio")
        }
    }
}
