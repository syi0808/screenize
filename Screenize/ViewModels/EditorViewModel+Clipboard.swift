import Foundation

/// A copied segment for internal clipboard operations.
enum CopiedSegment {
    case camera(CameraSegment)
    case cursor(CursorSegment)
    case keystroke(KeystrokeSegment)

    var trackType: TrackType {
        switch self {
        case .camera: return .transform
        case .cursor: return .cursor
        case .keystroke: return .keystroke
        }
    }

    var startTime: TimeInterval {
        switch self {
        case .camera(let s): return s.startTime
        case .cursor(let s): return s.startTime
        case .keystroke(let s): return s.startTime
        }
    }

    var endTime: TimeInterval {
        switch self {
        case .camera(let s): return s.endTime
        case .cursor(let s): return s.endTime
        case .keystroke(let s): return s.endTime
        }
    }

    var duration: TimeInterval { endTime - startTime }
}

// MARK: - Copy / Duplicate / Paste

extension EditorViewModel {

    /// Copy all selected segments to the internal clipboard.
    func copySelectedSegments() {
        guard !selection.isEmpty else { return }
        clipboard = selection.segments.compactMap { ident in
            findCopiedSegment(id: ident.id, trackType: ident.trackType)
        }
    }

    /// Duplicate all selected segments, placing each copy right after its original.
    func duplicateSelectedSegments() {
        guard !selection.isEmpty else { return }
        saveUndoSnapshot()

        var newSelection = SegmentSelection()

        for ident in selection.segments {
            switch ident.trackType {
            case .transform:
                if let newID = duplicateCameraSegment(ident.id) {
                    newSelection.add(newID, trackType: .transform)
                }
            case .cursor:
                if let newID = duplicateCursorSegment(ident.id) {
                    newSelection.add(newID, trackType: .cursor)
                }
            case .keystroke:
                if let newID = duplicateKeystrokeSegment(ident.id) {
                    newSelection.add(newID, trackType: .keystroke)
                }
            case .audio:
                break
            }
        }

        if !newSelection.isEmpty {
            selection = newSelection
            hasUnsavedChanges = true
            invalidatePreviewCache()
        }
    }

    /// Paste clipboard segments at the current playhead position.
    func pasteSegments() {
        guard !clipboard.isEmpty else { return }
        saveUndoSnapshot()

        let earliestStart = clipboard.map(\.startTime).min() ?? 0
        let timeOffset = currentTime - earliestStart
        var newSelection = SegmentSelection()

        for copied in clipboard {
            let newStart = copied.startTime + timeOffset
            let newEnd = min(duration, copied.endTime + timeOffset)
            guard newEnd > newStart else { continue }

            switch copied {
            case .camera(let original):
                if let newID = insertCameraSegment(original, startTime: newStart, endTime: newEnd) {
                    newSelection.add(newID, trackType: .transform)
                }
            case .cursor(let original):
                if let newID = insertCursorSegment(original, startTime: newStart, endTime: newEnd) {
                    newSelection.add(newID, trackType: .cursor)
                }
            case .keystroke(let original):
                if let newID = insertKeystrokeSegment(original, startTime: newStart, endTime: newEnd) {
                    newSelection.add(newID, trackType: .keystroke)
                }
            }
        }

        if !newSelection.isEmpty {
            selection = newSelection
            hasUnsavedChanges = true
            invalidatePreviewCache()
        }
    }

    // MARK: - Copy/Duplicate/Paste Helpers

    private func findCopiedSegment(id: UUID, trackType: TrackType) -> CopiedSegment? {
        switch trackType {
        case .transform:
            if let track = project.timeline.cameraTrack,
               let segment = track.segments.first(where: { $0.id == id }) {
                return .camera(segment)
            }
        case .cursor:
            if let track = project.timeline.cursorTrackV2,
               let segment = track.segments.first(where: { $0.id == id }) {
                return .cursor(segment)
            }
        case .keystroke:
            if let track = project.timeline.keystrokeTrackV2,
               let segment = track.segments.first(where: { $0.id == id }) {
                return .keystroke(segment)
            }
        case .audio:
            break
        }
        return nil
    }

    private func duplicateCameraSegment(_ id: UUID) -> UUID? {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }),
              case .camera(var track) = project.timeline.tracks[trackIndex],
              let original = track.segments.first(where: { $0.id == id }) else { return nil }

        let segDuration = original.endTime - original.startTime
        let newStart = original.endTime
        let newEnd = min(duration, newStart + segDuration)
        guard newEnd > newStart else { return nil }

        let duplicate = CameraSegment(
            startTime: newStart,
            endTime: newEnd,
            startTransform: original.startTransform,
            endTransform: original.endTransform,
            interpolation: original.interpolation,
            mode: original.mode,
            cursorFollow: original.cursorFollow,
            transitionToNext: original.transitionToNext
        )
        guard track.addSegment(duplicate) else { return nil }
        project.timeline.tracks[trackIndex] = .camera(track)
        return duplicate.id
    }

    private func duplicateCursorSegment(_ id: UUID) -> UUID? {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }),
              case .cursor(var track) = project.timeline.tracks[trackIndex],
              let original = track.segments.first(where: { $0.id == id }) else { return nil }

        let segDuration = original.endTime - original.startTime
        let newStart = original.endTime
        let newEnd = min(duration, newStart + segDuration)
        guard newEnd > newStart else { return nil }

        let duplicate = CursorSegment(
            startTime: newStart,
            endTime: newEnd,
            style: original.style,
            visible: original.visible,
            scale: original.scale,
            clickFeedback: original.clickFeedback,
            transitionToNext: original.transitionToNext
        )
        guard track.addSegment(duplicate) else { return nil }
        project.timeline.tracks[trackIndex] = .cursor(track)
        return duplicate.id
    }

    private func duplicateKeystrokeSegment(_ id: UUID) -> UUID? {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }),
              case .keystroke(var track) = project.timeline.tracks[trackIndex],
              let original = track.segments.first(where: { $0.id == id }) else { return nil }

        let segDuration = original.endTime - original.startTime
        let newStart = original.endTime
        let newEnd = min(duration, newStart + segDuration)
        guard newEnd > newStart else { return nil }

        let duplicate = KeystrokeSegment(
            startTime: newStart,
            endTime: newEnd,
            displayText: original.displayText,
            position: original.position,
            fadeInDuration: original.fadeInDuration,
            fadeOutDuration: original.fadeOutDuration
        )
        track.addSegment(duplicate)
        project.timeline.tracks[trackIndex] = .keystroke(track)
        return duplicate.id
    }

    private func insertCameraSegment(
        _ original: CameraSegment, startTime: TimeInterval, endTime: TimeInterval
    ) -> UUID? {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }),
              case .camera(var track) = project.timeline.tracks[trackIndex] else { return nil }

        let pasted = CameraSegment(
            startTime: startTime,
            endTime: endTime,
            startTransform: original.startTransform,
            endTransform: original.endTransform,
            interpolation: original.interpolation,
            mode: original.mode,
            cursorFollow: original.cursorFollow,
            transitionToNext: original.transitionToNext
        )
        guard track.addSegment(pasted) else { return nil }
        project.timeline.tracks[trackIndex] = .camera(track)
        return pasted.id
    }

    private func insertCursorSegment(
        _ original: CursorSegment, startTime: TimeInterval, endTime: TimeInterval
    ) -> UUID? {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }),
              case .cursor(var track) = project.timeline.tracks[trackIndex] else { return nil }

        let pasted = CursorSegment(
            startTime: startTime,
            endTime: endTime,
            style: original.style,
            visible: original.visible,
            scale: original.scale,
            clickFeedback: original.clickFeedback,
            transitionToNext: original.transitionToNext
        )
        guard track.addSegment(pasted) else { return nil }
        project.timeline.tracks[trackIndex] = .cursor(track)
        return pasted.id
    }

    private func insertKeystrokeSegment(
        _ original: KeystrokeSegment, startTime: TimeInterval, endTime: TimeInterval
    ) -> UUID? {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }),
              case .keystroke(var track) = project.timeline.tracks[trackIndex] else { return nil }

        let pasted = KeystrokeSegment(
            startTime: startTime,
            endTime: endTime,
            displayText: original.displayText,
            position: original.position,
            fadeInDuration: original.fadeInDuration,
            fadeOutDuration: original.fadeOutDuration
        )
        track.addSegment(pasted)
        project.timeline.tracks[trackIndex] = .keystroke(track)
        return pasted.id
    }
}
