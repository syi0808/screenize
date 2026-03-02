import Foundation

// MARK: - Segment Operations

extension EditorViewModel {

    /// Add a segment at the current time.
    func addSegment(to trackType: TrackType) {
        addSegment(to: trackType, at: currentTime)
    }

    /// Add a segment at a specified time.
    func addSegment(to trackType: TrackType, at time: TimeInterval) {
        saveUndoSnapshot()
        switch trackType {
        case .transform:
            addTransformSegment(at: time)
            project.timeline.continuousTransforms = nil
        case .cursor:
            addCursorSegment(at: time)
        case .keystroke:
            addKeystrokeSegment(at: time)
        case .audio:
            addAudioSegment(at: time)
        }

        hasUnsavedChanges = true
        // Use the selected segment's time range for targeted invalidation
        if let selectedID = selection.single?.id,
           let (start, end) = segmentTimeRange(for: selectedID) {
            invalidatePreviewCache(from: start, to: end)
        } else {
            invalidatePreviewCache()
        }
    }

    private func addTransformSegment(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }) else {
            return
        }

        guard case .camera(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let endTime = min(duration, time + 1.0)
        let newSegment = CameraSegment(
            startTime: time,
            endTime: max(time + 0.05, endTime),
            startTransform: .identity,
            endTransform: .identity
        )

        _ = track.addSegment(newSegment)

        project.timeline.tracks[trackIndex] = .camera(track)
        selection.select(newSegment.id, trackType: .transform)
    }

    private func addCursorSegment(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }) else {
            return
        }

        guard case .cursor(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let newSegment = CursorSegment(
            startTime: time,
            endTime: min(duration, time + 1.0),
            style: .arrow,
            visible: true,
            scale: 2.5
        )

        _ = track.addSegment(newSegment)

        project.timeline.tracks[trackIndex] = .cursor(track)
        selection.select(newSegment.id, trackType: .cursor)
    }

    private func addKeystrokeSegment(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }) else {
            return
        }

        guard case .keystroke(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let newSegment = KeystrokeSegment(
            startTime: time,
            endTime: min(duration, time + 1.5),
            displayText: "⌘"
        )

        track.addSegment(newSegment)

        project.timeline.tracks[trackIndex] = .keystroke(track)
        selection.select(newSegment.id, trackType: .keystroke)
    }

    private func addAudioSegment(at time: TimeInterval) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .audio }) else {
            return
        }

        guard case .audio(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        let newSegment = AudioSegment(
            startTime: time,
            endTime: min(duration, time + 5.0)
        )

        guard track.addSegment(newSegment) else { return }

        project.timeline.tracks[trackIndex] = .audio(track)
        selection.select(newSegment.id, trackType: .audio)
    }

    /// Delete a segment.
    func deleteSegment(_ id: UUID, from trackType: TrackType) {
        saveUndoSnapshot()

        // Capture time range before deletion for range-based invalidation
        let timeRange = segmentTimeRange(for: id)

        switch trackType {
        case .transform:
            deleteTransformSegment(id)
            project.timeline.continuousTransforms = nil
        case .cursor:
            deleteCursorSegment(id)
        case .keystroke:
            deleteKeystrokeSegment(id)
        case .audio:
            deleteAudioSegment(id)
        }

        selection.remove(id)

        hasUnsavedChanges = true
        if let (start, end) = timeRange {
            invalidatePreviewCache(from: start, to: end)
        } else {
            invalidatePreviewCache()
        }
    }

    private func deleteTransformSegment(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .transform }) else {
            return
        }

        guard case .camera(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.removeSegment(id: id)
        project.timeline.tracks[trackIndex] = .camera(track)
    }

    private func deleteCursorSegment(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .cursor }) else {
            return
        }

        guard case .cursor(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.removeSegment(id: id)
        project.timeline.tracks[trackIndex] = .cursor(track)
    }

    private func deleteKeystrokeSegment(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }) else {
            return
        }

        guard case .keystroke(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.removeSegment(id: id)
        project.timeline.tracks[trackIndex] = .keystroke(track)
    }

    private func deleteAudioSegment(_ id: UUID) {
        guard let trackIndex = project.timeline.tracks.firstIndex(where: { $0.trackType == .audio }) else {
            return
        }

        guard case .audio(var track) = project.timeline.tracks[trackIndex] else {
            return
        }

        track.removeSegment(id: id)
        project.timeline.tracks[trackIndex] = .audio(track)
    }

    /// Update segment start/end time as a single edit operation.
    @discardableResult
    func updateSegmentTimeRange(_ id: UUID, startTime: TimeInterval, endTime: TimeInterval) -> Bool {
        saveUndoSnapshot()
        let result = updateSegmentTimeRangeNoUndo(id, startTime: startTime, endTime: endTime)
        if result {
            hasUnsavedChanges = true
            invalidatePreviewCache(from: startTime, to: endTime)
        }
        return result
    }

    /// Batch update multiple segments' time ranges in a single undo operation.
    func batchUpdateSegmentTimeRanges(_ changes: [(UUID, TimeInterval, TimeInterval)]) {
        saveUndoSnapshot()
        var anyChanged = false
        var rangeStart = TimeInterval.greatestFiniteMagnitude
        var rangeEnd = TimeInterval.zero
        for (id, startTime, endTime) in changes {
            if updateSegmentTimeRangeNoUndo(id, startTime: startTime, endTime: endTime) {
                anyChanged = true
                rangeStart = min(rangeStart, startTime)
                rangeEnd = max(rangeEnd, endTime)
            }
        }
        if anyChanged {
            hasUnsavedChanges = true
            invalidatePreviewCache(from: rangeStart, to: rangeEnd)
        }
    }

    /// Update a segment's time range without saving an undo snapshot.
    private func updateSegmentTimeRangeNoUndo(
        _ id: UUID, startTime: TimeInterval, endTime: TimeInterval
    ) -> Bool {
        let clampedStart = max(0, min(duration, startTime))
        let clampedEnd = min(duration, max(clampedStart + 0.001, endTime))

        for (trackIndex, anyTrack) in project.timeline.tracks.enumerated() {
            switch anyTrack {
            case .camera(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else { return false }
                project.timeline.tracks[trackIndex] = .camera(track)
                project.timeline.continuousTransforms = nil
                return true

            case .cursor(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else { return false }
                project.timeline.tracks[trackIndex] = .cursor(track)
                return true

            case .keystroke(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else { return false }
                project.timeline.tracks[trackIndex] = .keystroke(track)
                return true

            case .audio(var track):
                guard let index = track.segments.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                var segment = track.segments[index]
                segment.startTime = clampedStart
                segment.endTime = clampedEnd
                guard track.updateSegment(segment) else { return false }
                project.timeline.tracks[trackIndex] = .audio(track)
                return true
            }
        }

        return false
    }

    /// Delete all segments.
    func deleteAllSegments() {
        saveUndoSnapshot()
        for (trackIndex, anyTrack) in project.timeline.tracks.enumerated() {
            switch anyTrack {
            case .camera(var track):
                track.segments.removeAll()
                project.timeline.tracks[trackIndex] = .camera(track)
            case .cursor(var track):
                track.segments.removeAll()
                project.timeline.tracks[trackIndex] = .cursor(track)
            case .keystroke(var track):
                track.segments.removeAll()
                project.timeline.tracks[trackIndex] = .keystroke(track)
            case .audio(var track):
                track.segments.removeAll()
                project.timeline.tracks[trackIndex] = .audio(track)
            }
        }

        project.timeline.continuousTransforms = nil
        selection.clear()
        hasUnsavedChanges = true
        invalidatePreviewCache()
    }

    /// Find the time range of a segment by ID across all tracks
    /// Returns (startTime, endTime) or nil if the segment is not found
    func segmentTimeRange(for id: UUID) -> (TimeInterval, TimeInterval)? {
        for track in project.timeline.tracks {
            switch track {
            case .camera(let cameraTrack):
                if let segment = cameraTrack.segments.first(where: { $0.id == id }) {
                    return (segment.startTime, segment.endTime)
                }
            case .cursor(let cursorTrack):
                if let segment = cursorTrack.segments.first(where: { $0.id == id }) {
                    return (segment.startTime, segment.endTime)
                }
            case .keystroke(let keystrokeTrack):
                if let segment = keystrokeTrack.segments.first(where: { $0.id == id }) {
                    return (segment.startTime, segment.endTime)
                }
            case .audio(let audioTrack):
                if let segment = audioTrack.segments.first(where: { $0.id == id }) {
                    return (segment.startTime, segment.endTime)
                }
            }
        }
        return nil
    }
}
