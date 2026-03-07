import SwiftUI

// MARK: - Gesture Handlers

extension TimelineView {

    func moveGesture(
        for id: UUID,
        trackType: TrackType,
        start: TimeInterval,
        end: TimeInterval,
        ranges: [SegmentRange]
    ) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("trackArea"))
            .onChanged { value in
                let isMultiMove = selection.contains(id) && selection.count > 1

                if !isInteracting(with: id, mode: .move) {
                    let companions = isMultiMove ? collectCompanions(excluding: id) : []
                    activeSegmentInteraction = SegmentInteraction(
                        id: id,
                        mode: .move,
                        initialStart: start,
                        initialEnd: end,
                        previewStart: start,
                        previewEnd: end,
                        companions: companions
                    )
                }

                guard var interaction = activeSegmentInteraction, interaction.id == id, interaction.mode == .move else {
                    return
                }

                let segmentDuration = interaction.initialEnd - interaction.initialStart
                let rawDelta = Double(value.translation.width / pixelsPerSecond)

                if interaction.companions.isEmpty {
                    // Single segment move (original logic)
                    let unclampedStart = interaction.initialStart + rawDelta
                    let unclampedCenter = unclampedStart + segmentDuration / 2

                    let others = ranges.filter { $0.id != id }.sorted { $0.start < $1.start }
                    var gapStart: TimeInterval = 0
                    var gapEnd: TimeInterval = duration
                    for other in others {
                        let otherCenter = (other.start + other.end) / 2
                        if unclampedCenter <= otherCenter {
                            gapEnd = other.start
                            break
                        }
                        gapStart = other.end
                    }

                    let dynBounds = SegmentEditBounds(minStart: gapStart, maxEnd: gapEnd)
                    var proposedStart = max(gapStart, min(gapEnd - segmentDuration, unclampedStart))
                    proposedStart = max(0, min(duration - segmentDuration, proposedStart))
                    var proposedEnd = proposedStart + segmentDuration

                    let allSnapTargets = snapTargets(from: ranges, excluding: id)
                    (proposedStart, proposedEnd) = snappedRange(
                        start: proposedStart, end: proposedEnd,
                        mode: .move, snapTargets: allSnapTargets, editBounds: dynBounds
                    )

                    interaction.previewStart = proposedStart
                    interaction.previewEnd = proposedEnd
                    activeSegmentInteraction = interaction
                } else {
                    // Multi-segment move: constrain delta across all participants
                    let selectedIDs = Set(
                        [interaction.id] + interaction.companions.map(\.id)
                    )

                    // Compute allowable delta for the primary segment
                    let primaryRange = allowableDeltaRange(
                        segmentStart: interaction.initialStart,
                        segmentEnd: interaction.initialEnd,
                        segmentID: interaction.id,
                        trackType: trackType,
                        selectedIDs: selectedIDs
                    )
                    var globalMinDelta = primaryRange.min
                    var globalMaxDelta = primaryRange.max

                    // Compute allowable delta for each companion
                    for companion in interaction.companions {
                        let compRange = allowableDeltaRange(
                            segmentStart: companion.initialStart,
                            segmentEnd: companion.initialEnd,
                            segmentID: companion.id,
                            trackType: companion.trackType,
                            selectedIDs: selectedIDs
                        )
                        globalMinDelta = max(globalMinDelta, compRange.min)
                        globalMaxDelta = min(globalMaxDelta, compRange.max)
                    }

                    // Clamp the raw delta to the intersection of all allowable ranges
                    let constrainedDelta = max(globalMinDelta, min(globalMaxDelta, rawDelta))

                    // Apply snap on primary segment only
                    var proposedStart = interaction.initialStart + constrainedDelta
                    var proposedEnd = proposedStart + segmentDuration
                    let dynBounds = SegmentEditBounds(
                        minStart: interaction.initialStart + globalMinDelta,
                        maxEnd: interaction.initialEnd + globalMaxDelta
                    )
                    let allSnapTargets = snapTargets(from: ranges, excluding: id)
                    (proposedStart, proposedEnd) = snappedRange(
                        start: proposedStart, end: proposedEnd,
                        mode: .move, snapTargets: allSnapTargets, editBounds: dynBounds
                    )

                    // Derive final delta from primary
                    let finalDelta = proposedStart - interaction.initialStart

                    interaction.previewStart = proposedStart
                    interaction.previewEnd = proposedEnd
                    for i in interaction.companions.indices {
                        let comp = interaction.companions[i]
                        interaction.companions[i].previewStart = comp.initialStart + finalDelta
                        interaction.companions[i].previewEnd = comp.initialEnd + finalDelta
                    }
                    activeSegmentInteraction = interaction
                }
            }
            .onEnded { _ in
                let hasCompanions = activeSegmentInteraction?.companions.isEmpty == false
                commitInteraction(for: id)
                if !hasCompanions {
                    onSegmentSelect?(trackType, id)
                }
            }
    }

    func resizeGesture(
        for id: UUID,
        trackType: TrackType,
        start: TimeInterval,
        end: TimeInterval,
        mode: SegmentInteractionMode,
        snapTargets: [TimeInterval],
        editBounds: SegmentEditBounds
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("trackArea"))
            .onChanged { value in
                if !isInteracting(with: id, mode: mode) {
                    activeSegmentInteraction = SegmentInteraction(
                        id: id,
                        mode: mode,
                        initialStart: start,
                        initialEnd: end,
                        previewStart: start,
                        previewEnd: end
                    )
                }

                guard var interaction = activeSegmentInteraction, interaction.id == id, interaction.mode == mode else {
                    return
                }

                let deltaTime = Double(value.translation.width / pixelsPerSecond)
                var proposedStart = interaction.initialStart
                var proposedEnd = interaction.initialEnd

                switch mode {
                case .resizeStart:
                    proposedStart = interaction.initialStart + deltaTime
                    proposedStart = max(editBounds.minStart, min(interaction.initialEnd - minSegmentDuration, proposedStart))
                case .resizeEnd:
                    proposedEnd = interaction.initialEnd + deltaTime
                    proposedEnd = min(editBounds.maxEnd, max(interaction.initialStart + minSegmentDuration, proposedEnd))
                case .move:
                    break
                }

                (proposedStart, proposedEnd) = snappedRange(
                    start: proposedStart,
                    end: proposedEnd,
                    mode: mode,
                    snapTargets: snapTargets,
                    editBounds: editBounds
                )

                interaction.previewStart = proposedStart
                interaction.previewEnd = proposedEnd
                activeSegmentInteraction = interaction
            }
            .onEnded { _ in
                commitInteraction(for: id)
                onSegmentSelect?(trackType, id)
            }
    }

}
