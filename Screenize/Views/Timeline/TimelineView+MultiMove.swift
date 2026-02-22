import Foundation

/// A segment being moved alongside the primary dragged segment.
struct CompanionSegment {
    let id: UUID
    let trackType: TrackType
    let initialStart: TimeInterval
    let initialEnd: TimeInterval
    var previewStart: TimeInterval
    var previewEnd: TimeInterval
}

private func preferredSnapShiftHelper(
    current: TimeInterval?, candidate: TimeInterval
) -> TimeInterval {
    guard let current else { return candidate }
    return abs(candidate) < abs(current) ? candidate : current
}

// MARK: - Multi-Move & Interaction Helpers

extension TimelineView {

    /// Collect companion segments from the timeline for all selected segments except the primary.
    func collectCompanions(excluding primaryID: UUID) -> [CompanionSegment] {
        var companions: [CompanionSegment] = []
        for track in timeline.tracks {
            switch track {
            case .camera(let cameraTrack):
                for segment in cameraTrack.segments
                where segment.id != primaryID && selection.contains(segment.id) {
                    companions.append(CompanionSegment(
                        id: segment.id, trackType: .transform,
                        initialStart: segment.startTime, initialEnd: segment.endTime,
                        previewStart: segment.startTime, previewEnd: segment.endTime
                    ))
                }
            case .cursor(let cursorTrack):
                for segment in cursorTrack.segments
                where segment.id != primaryID && selection.contains(segment.id) {
                    companions.append(CompanionSegment(
                        id: segment.id, trackType: .cursor,
                        initialStart: segment.startTime, initialEnd: segment.endTime,
                        previewStart: segment.startTime, previewEnd: segment.endTime
                    ))
                }
            case .keystroke(let keystrokeTrack):
                for segment in keystrokeTrack.segments
                where segment.id != primaryID && selection.contains(segment.id) {
                    companions.append(CompanionSegment(
                        id: segment.id, trackType: .keystroke,
                        initialStart: segment.startTime, initialEnd: segment.endTime,
                        previewStart: segment.startTime, previewEnd: segment.endTime
                    ))
                }
            case .audio(let audioTrack):
                for segment in audioTrack.segments
                where segment.id != primaryID && selection.contains(segment.id) {
                    companions.append(CompanionSegment(
                        id: segment.id, trackType: .audio,
                        initialStart: segment.startTime, initialEnd: segment.endTime,
                        previewStart: segment.startTime, previewEnd: segment.endTime
                    ))
                }
            }
        }
        return companions
    }

    /// Compute the allowable delta range [minDelta, maxDelta] for a segment
    /// given the non-selected segments on its track.
    func allowableDeltaRange(
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval,
        segmentID: UUID,
        trackType: TrackType,
        selectedIDs: Set<UUID>
    ) -> (min: TimeInterval, max: TimeInterval) {
        let nonSelectedRanges = segmentRangesForTrack(trackType)
            .filter { !selectedIDs.contains($0.id) }
            .sorted { $0.start < $1.start }

        let leftBound = nonSelectedRanges
            .filter { $0.end <= segmentStart }
            .map(\.end)
            .max() ?? 0

        let rightBound = nonSelectedRanges
            .filter { $0.start >= segmentEnd }
            .map(\.start)
            .min() ?? duration

        let minDelta = leftBound - segmentStart
        let maxDelta = rightBound - segmentEnd
        return (minDelta, maxDelta)
    }

    /// Get all segment ranges for a given track type.
    func segmentRangesForTrack(_ trackType: TrackType) -> [SegmentRange] {
        for track in timeline.tracks {
            switch track {
            case .camera(let trk) where trackType == .transform:
                return trk.segments.map {
                    SegmentRange(id: $0.id, start: $0.startTime, end: $0.endTime)
                }
            case .cursor(let trk) where trackType == .cursor:
                return trk.segments.map {
                    SegmentRange(id: $0.id, start: $0.startTime, end: $0.endTime)
                }
            case .keystroke(let trk) where trackType == .keystroke:
                return trk.segments.map {
                    SegmentRange(id: $0.id, start: $0.startTime, end: $0.endTime)
                }
            default:
                continue
            }
        }
        return []
    }

    // MARK: - Snap & Commit Helpers

    func snapTargets(from ranges: [SegmentRange], excluding id: UUID) -> [TimeInterval] {
        var targets = ranges
            .filter { $0.id != id }
            .flatMap { [$0.start, $0.end] }
        targets.append(currentTime)
        return targets
    }

    func editBounds(
        from ranges: [SegmentRange],
        excluding id: UUID,
        currentStart: TimeInterval,
        currentEnd: TimeInterval
    ) -> SegmentEditBounds {
        let previousEnd = ranges
            .filter { $0.id != id && $0.end <= currentStart }
            .map(\.end)
            .max() ?? 0

        let nextStart = ranges
            .filter { $0.id != id && $0.start >= currentEnd }
            .map(\.start)
            .min() ?? duration

        let safeMaxEnd = max(previousEnd + minSegmentDuration, nextStart)
        return SegmentEditBounds(minStart: previousEnd, maxEnd: safeMaxEnd)
    }

    func snappedRange(
        start: TimeInterval,
        end: TimeInterval,
        mode: SegmentInteractionMode,
        snapTargets: [TimeInterval],
        editBounds: SegmentEditBounds
    ) -> (TimeInterval, TimeInterval) {
        let threshold = Double(snapThresholdInPoints / pixelsPerSecond)

        switch mode {
        case .move:
            let segmentDuration = end - start
            var bestShift: TimeInterval?

            for target in snapTargets {
                let startShift = target - start
                if abs(startShift) <= threshold {
                    bestShift = preferredSnapShiftHelper(
                        current: bestShift, candidate: startShift
                    )
                }
                let endShift = target - end
                if abs(endShift) <= threshold {
                    bestShift = preferredSnapShiftHelper(
                        current: bestShift, candidate: endShift
                    )
                }
            }

            guard let shift = bestShift else {
                return (start, end)
            }

            var snappedStart = start + shift
            let maxStart = max(editBounds.minStart, editBounds.maxEnd - segmentDuration)
            snappedStart = max(editBounds.minStart, min(maxStart, snappedStart))
            let snappedEnd = snappedStart + segmentDuration
            return (snappedStart, snappedEnd)

        case .resizeStart:
            var snappedStart = start
            var closestDistance: Double = .infinity
            for target in snapTargets where abs(target - start) <= threshold {
                let dist = abs(target - start)
                if dist < closestDistance {
                    closestDistance = dist
                    snappedStart = target
                }
            }
            snappedStart = max(
                editBounds.minStart,
                min(end - minSegmentDuration, snappedStart)
            )
            return (snappedStart, end)

        case .resizeEnd:
            var snappedEnd = end
            var closestDistance: Double = .infinity
            for target in snapTargets where abs(target - end) <= threshold {
                let dist = abs(target - end)
                if dist < closestDistance {
                    closestDistance = dist
                    snappedEnd = target
                }
            }
            snappedEnd = min(
                editBounds.maxEnd,
                max(start + minSegmentDuration, snappedEnd)
            )
            return (start, snappedEnd)
        }
    }

    func commitInteraction(for id: UUID) {
        guard let interaction = activeSegmentInteraction, interaction.id == id else {
            return
        }

        if interaction.companions.isEmpty {
            let didApply = onSegmentTimeRangeChange?(
                id, interaction.previewStart, interaction.previewEnd
            ) ?? false
            if !didApply {
                activeSegmentInteraction = nil
                return
            }
        } else {
            var changes: [(UUID, TimeInterval, TimeInterval)] = [
                (id, interaction.previewStart, interaction.previewEnd)
            ]
            changes += interaction.companions.map {
                ($0.id, $0.previewStart, $0.previewEnd)
            }
            onBatchSegmentTimeRangeChange?(changes)
        }

        activeSegmentInteraction = nil
    }
}
