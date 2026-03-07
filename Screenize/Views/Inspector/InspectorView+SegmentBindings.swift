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

                return CameraSegment(startTime: 0, endTime: 1, startTransform: .identity, endTransform: .identity)
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
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .audio }),
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
            return "Camera"
        case .cursor:
            return "Cursor"
        case .keystroke:
            return "Keystroke"
        case .audio:
            return "Audio"
        }
    }
}
