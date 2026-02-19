import SwiftUI
#if os(macOS)
import AppKit
#endif

private struct SegmentRange {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
}

private struct SegmentEditBounds {
    let minStart: TimeInterval
    let maxEnd: TimeInterval
}

private func preferredSnapShift(current: TimeInterval?, candidate: TimeInterval) -> TimeInterval {
    guard let current else { return candidate }
    return abs(candidate) < abs(current) ? candidate : current
}

private func timelineTrackIcon(for type: TrackType) -> String {
    switch type {
    case .transform:
        return "arrow.up.left.and.arrow.down.right"
    case .cursor:
        return "cursorarrow"
    case .keystroke:
        return "keyboard"
    case .audio:
        return "waveform"
    }
}

private func timelineIsSegmentInTrimRange(
    start: TimeInterval,
    end: TimeInterval,
    trimStart: TimeInterval,
    trimEnd: TimeInterval?,
    duration: TimeInterval
) -> Bool {
    let effectiveTrimEnd = trimEnd ?? duration
    return end > trimStart && start < effectiveTrimEnd
}

/// Segment timeline view.
struct TimelineView: View {

    @Binding var timeline: Timeline
    let duration: TimeInterval
    @Binding var currentTime: TimeInterval
    @Binding var selectedSegmentID: UUID?
    @Binding var selectedSegmentTrackType: TrackType?

    var onSegmentTimeRangeChange: ((UUID, TimeInterval, TimeInterval) -> Bool)?
    var onAddSegment: ((TrackType, TimeInterval) -> Void)?
    var onSegmentSelect: ((TrackType, UUID) -> Void)?
    var onSeek: ((TimeInterval) async -> Void)?

    @Binding var trimStart: TimeInterval
    @Binding var trimEnd: TimeInterval?
    var onTrimChange: ((TimeInterval, TimeInterval?) -> Void)?

    @State private var pixelsPerSecond: CGFloat = 50
    @State private var timelineAreaWidth: CGFloat = 0
    @State private var isDraggingTrimStart = false
    @State private var isDraggingTrimEnd = false
    @State private var activeSegmentInteraction: SegmentInteraction?
    @State private var resizeCursorHoverCount = 0
    @State private var hoveredSegmentID: UUID?

    private let minPixelsPerSecond: CGFloat = 1
    private let maxPixelsPerSecond: CGFloat = 2000
    private let minSegmentDuration: TimeInterval = 0.05
    private let snapThresholdInPoints: CGFloat = 8
    private let rulerHeight: CGFloat = 24
    private let trackHeight: CGFloat = 40
    private let headerWidth: CGFloat = 120

    private var logZoom: Binding<Double> {
        Binding(
            get: { log2(Double(pixelsPerSecond)) },
            set: { pixelsPerSecond = CGFloat(pow(2, $0)) }
        )
    }

    private enum SegmentInteractionMode {
        case move
        case resizeStart
        case resizeEnd
    }

    private struct SegmentInteraction {
        let id: UUID
        let mode: SegmentInteractionMode
        let initialStart: TimeInterval
        let initialEnd: TimeInterval
        var previewStart: TimeInterval
        var previewEnd: TimeInterval
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            GeometryReader { geometry in
                let availableWidth = geometry.size.width - headerWidth - 1
                let contentWidth = max(availableWidth, CGFloat(duration) * pixelsPerSecond)

                HStack(spacing: 0) {
                    trackHeaders
                    Divider()

                    HorizontalScrollViewWithVerticalWheel {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                TimeRulerView(
                                    duration: duration,
                                    currentTime: currentTime,
                                    pixelsPerSecond: pixelsPerSecond,
                                    scrollOffset: 0,
                                    onTimeTap: { time in
                                        currentTime = time
                                        Task { await onSeek?(time) }
                                    }
                                )

                                Divider()

                                trackContent
                            }

                            trimOverlay

                            PlayheadLine(currentTime: currentTime, pixelsPerSecond: pixelsPerSecond, scrollOffset: 0)
                                .offset(y: rulerHeight)
                        }
                        .frame(width: contentWidth)
                    }
                }
                .onAppear {
                    timelineAreaWidth = availableWidth
                    if duration > 0 {
                        fitToView()
                    }
                }
                .onChange(of: geometry.size.width) { newWidth in
                    timelineAreaWidth = newWidth - headerWidth - 1
                }
            }
        }
        .onChange(of: duration) { newDuration in
            if newDuration > 0 && timelineAreaWidth > 0 {
                fitToView()
            }
        }
        .onDisappear {
            resetResizeCursorIfNeeded()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack {
            Spacer()

            HStack(spacing: 8) {
                Button { pixelsPerSecond = max(minPixelsPerSecond, pixelsPerSecond / 1.5) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)

                Slider(
                    value: logZoom,
                    in: log2(Double(minPixelsPerSecond))...log2(Double(maxPixelsPerSecond))
                )
                .frame(width: 100)

                Button { pixelsPerSecond = min(maxPixelsPerSecond, pixelsPerSecond * 1.5) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)

                Button { fitToView() } label: {
                    Image(systemName: "arrow.left.and.right.square")
                }
                .buttonStyle(.plain)
                .help("Fit timeline to view")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var trackHeaders: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: rulerHeight)
            Divider()

            ForEach(Array(timeline.tracks.enumerated()), id: \.element.id) { index, track in
                HStack(spacing: 8) {
                    Image(systemName: timelineTrackIcon(for: track.trackType))
                        .foregroundColor(TrackColor.color(for: track.trackType))
                        .frame(width: 16)

                    Text(track.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(track.isEnabled ? .primary : .secondary)

                    Spacer()

                    // Smooth cursor toggle (cursor track only)
                    if case .cursor(let cursorTrack) = timeline.tracks[index] {
                        Button {
                            var updated = cursorTrack
                            updated.useSmoothCursor.toggle()
                            timeline.tracks[index] = .cursor(updated)
                        } label: {
                            Image(systemName: cursorTrack.useSmoothCursor
                                ? "cursorarrow.motionlines" : "cursorarrow")
                                .font(.system(size: 10))
                                .foregroundColor(cursorTrack.useSmoothCursor
                                    ? .accentColor : .secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .help(cursorTrack.useSmoothCursor
                            ? "Smooth cursor interpolation (on)"
                            : "Smooth cursor interpolation (off)")
                    }

                    Button {
                        var updated = track
                        updated.isEnabled.toggle()
                        timeline.tracks[index] = updated
                    } label: {
                        Image(systemName: track.isEnabled ? "eye" : "eye.slash")
                            .font(.system(size: 10))
                            .foregroundStyle(track.isEnabled ? .secondary : .tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .frame(height: trackHeight)

                Divider()
            }

            Spacer()
        }
        .frame(width: headerWidth)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var trackContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(timeline.tracks.enumerated()), id: \.element.id) { _, track in
                trackArea(for: track)
                Divider()
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func trackArea(for track: AnySegmentTrack) -> some View {
        ZStack(alignment: .leading) {
            TimelineGridView(duration: duration, pixelsPerSecond: pixelsPerSecond, scrollOffset: 0, height: trackHeight)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    let time = max(0, min(duration, Double(location.x) / Double(pixelsPerSecond)))
                    onAddSegment?(track.trackType, time)
                }
                .onTapGesture {
                    selectedSegmentID = nil
                    selectedSegmentTrackType = nil
                }

            segmentBlocks(for: track)
        }
        .frame(height: trackHeight)
        .opacity(track.isEnabled ? 1.0 : 0.5)
        .coordinateSpace(name: "trackArea")
    }

    @ViewBuilder
    private func segmentBlocks(for track: AnySegmentTrack) -> some View {
        switch track {
        case .camera(let cameraTrack):
            let ranges = cameraTrack.segments.map {
                SegmentRange(id: $0.id, start: $0.startTime, end: $0.endTime)
            }

            ForEach(cameraTrack.segments) { segment in
                segmentBlock(
                    trackType: .transform,
                    id: segment.id,
                    start: segment.startTime,
                    end: segment.endTime,
                    ranges: ranges,
                    editBounds: editBounds(from: ranges, excluding: segment.id, currentStart: segment.startTime, currentEnd: segment.endTime)
                )
            }
        case .cursor(let cursorTrack):
            let ranges = cursorTrack.segments.map {
                SegmentRange(id: $0.id, start: $0.startTime, end: $0.endTime)
            }

            ForEach(cursorTrack.segments) { segment in
                segmentBlock(
                    trackType: .cursor,
                    id: segment.id,
                    start: segment.startTime,
                    end: segment.endTime,
                    ranges: ranges,
                    editBounds: editBounds(from: ranges, excluding: segment.id, currentStart: segment.startTime, currentEnd: segment.endTime),
                    cursorStyle: segment.style
                )
            }
        case .keystroke(let keystrokeTrack):
            let ranges = keystrokeTrack.segments.map {
                SegmentRange(id: $0.id, start: $0.startTime, end: $0.endTime)
            }

            ForEach(keystrokeTrack.segments) { segment in
                segmentBlock(
                    trackType: .keystroke,
                    id: segment.id,
                    start: segment.startTime,
                    end: segment.endTime,
                    ranges: ranges,
                    editBounds: editBounds(from: ranges, excluding: segment.id, currentStart: segment.startTime, currentEnd: segment.endTime)
                )
            }
        }
    }

    private func segmentBlock(
        trackType: TrackType,
        id: UUID,
        start: TimeInterval,
        end: TimeInterval,
        ranges: [SegmentRange],
        editBounds: SegmentEditBounds,
        cursorStyle: CursorStyle? = nil
    ) -> some View {
        let resizeSnapTargets = snapTargets(from: ranges, excluding: id)
        let displayStart = segmentDisplayStart(for: id, fallback: start)
        let displayEnd = segmentDisplayEnd(for: id, fallback: end)
        let x = CGFloat(displayStart) * pixelsPerSecond
        let width = max(6, CGFloat(displayEnd - displayStart) * pixelsPerSecond)
        let color = TrackColor.color(for: trackType)
        let isSelected = selectedSegmentID == id
        let isHovered = hoveredSegmentID == id
        let showHandles = isSelected || isHovered

        let adaptiveHandleWidth: CGFloat = {
            if width < 10 && !isSelected { return 0 }
            if width < 20 { return max(3, width * 0.15) }
            if width < 40 { return max(4, min(10, width * 0.2)) }
            return 10
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(isSelected ? 0.9 : 0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(
                            Color.white.opacity(isSelected ? 0.5 : (isHovered ? 0.35 : 0.15)),
                            lineWidth: 1
                        )
                )

            // Cursor style indicator
            if let style = cursorStyle, width > 20 {
                HStack(spacing: 2) {
                    Image(systemName: style.sfSymbolName)
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.8))
                    if width > 60 {
                        Text(style.displayName)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                .allowsHitTesting(false)
            }

            // Handles: visible only on hover/selection
            if showHandles && adaptiveHandleWidth > 0 {
                HStack(spacing: 0) {
                    segmentHandleView(
                        width: adaptiveHandleWidth,
                        isSelected: isSelected,
                        segmentWidth: width
                    )
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        updateResizeCursor(isHovering)
                    }
                    .highPriorityGesture(
                        resizeGesture(
                            for: id, trackType: trackType,
                            start: start, end: end,
                            mode: .resizeStart,
                            snapTargets: resizeSnapTargets,
                            editBounds: editBounds
                        )
                    )

                    Spacer(minLength: 0)

                    segmentHandleView(
                        width: adaptiveHandleWidth,
                        isSelected: isSelected,
                        segmentWidth: width
                    )
                    .contentShape(Rectangle())
                    .onHover { isHovering in
                        updateResizeCursor(isHovering)
                    }
                    .highPriorityGesture(
                        resizeGesture(
                            for: id, trackType: trackType,
                            start: start, end: end,
                            mode: .resizeEnd,
                            snapTargets: resizeSnapTargets,
                            editBounds: editBounds
                        )
                    )
                }
            } else {
                // Invisible resize hit zones when handles are hidden
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: max(6, min(10, width * 0.25)))
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            updateResizeCursor(isHovering)
                        }
                        .highPriorityGesture(
                            resizeGesture(
                                for: id, trackType: trackType,
                                start: start, end: end,
                                mode: .resizeStart,
                                snapTargets: resizeSnapTargets,
                                editBounds: editBounds
                            )
                        )

                    Spacer(minLength: 0)

                    Color.clear
                        .frame(width: max(6, min(10, width * 0.25)))
                        .contentShape(Rectangle())
                        .onHover { isHovering in
                            updateResizeCursor(isHovering)
                        }
                        .highPriorityGesture(
                            resizeGesture(
                                for: id, trackType: trackType,
                                start: start, end: end,
                                mode: .resizeEnd,
                                snapTargets: resizeSnapTargets,
                                editBounds: editBounds
                            )
                        )
                }
            }
        }
        .frame(width: width, height: 22)
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredSegmentID = isHovering ? id : nil
        }
        .gesture(
            moveGesture(
                for: id,
                trackType: trackType,
                start: start,
                end: end,
                ranges: ranges
            )
        )
        .onTapGesture {
            onSegmentSelect?(trackType, id)
            selectedSegmentID = id
            selectedSegmentTrackType = trackType
        }
        .position(x: x + width / 2, y: trackHeight / 2)
        .opacity(
            timelineIsSegmentInTrimRange(
                start: displayStart,
                end: displayEnd,
                trimStart: trimStart,
                trimEnd: trimEnd,
                duration: duration
            ) ? 1.0 : 0.3
        )
    }

    @ViewBuilder
    private func segmentHandleView(
        width: CGFloat,
        isSelected: Bool,
        segmentWidth: CGFloat
    ) -> some View {
        if segmentWidth < 16 {
            Rectangle()
                .fill(Color.white.opacity(isSelected ? 0.8 : 0.5))
                .frame(width: max(2, width))
        } else {
            Rectangle()
                .fill(Color.white.opacity(isSelected ? 0.22 : 0.12))
                .frame(width: width)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(isSelected ? 0.7 : 0.35))
                        .frame(width: 1)
                )
        }
    }

    private func moveGesture(
        for id: UUID,
        trackType: TrackType,
        start: TimeInterval,
        end: TimeInterval,
        ranges: [SegmentRange]
    ) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("trackArea"))
            .onChanged { value in
                if !isInteracting(with: id, mode: .move) {
                    activeSegmentInteraction = SegmentInteraction(
                        id: id,
                        mode: .move,
                        initialStart: start,
                        initialEnd: end,
                        previewStart: start,
                        previewEnd: end
                    )
                }

                guard var interaction = activeSegmentInteraction, interaction.id == id, interaction.mode == .move else {
                    return
                }

                let segmentDuration = interaction.initialEnd - interaction.initialStart
                let deltaTime = Double(value.translation.width / pixelsPerSecond)
                let unclampedStart = interaction.initialStart + deltaTime
                let unclampedCenter = unclampedStart + segmentDuration / 2

                // Gap detection: find which gap the unclamped center falls into
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

                // Clamp to gap bounds + timeline edges
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
            }
            .onEnded { _ in
                commitInteraction(for: id)
                onSegmentSelect?(trackType, id)
                selectedSegmentID = id
                selectedSegmentTrackType = trackType
            }
    }

    private func resizeGesture(
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
                selectedSegmentID = id
                selectedSegmentTrackType = trackType
            }
    }

}

// MARK: - Snapping & Interaction Helpers

extension TimelineView {

    private func isInteracting(with id: UUID, mode: SegmentInteractionMode) -> Bool {
        guard let interaction = activeSegmentInteraction else { return false }
        return interaction.id == id && interaction.mode == mode
    }

    private func segmentDisplayStart(for id: UUID, fallback: TimeInterval) -> TimeInterval {
        guard let interaction = activeSegmentInteraction, interaction.id == id else {
            return fallback
        }
        return interaction.previewStart
    }

    private func segmentDisplayEnd(for id: UUID, fallback: TimeInterval) -> TimeInterval {
        guard let interaction = activeSegmentInteraction, interaction.id == id else {
            return fallback
        }
        return interaction.previewEnd
    }

    private func snappedRange(
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
                    bestShift = preferredSnapShift(current: bestShift, candidate: startShift)
                }

                let endShift = target - end
                if abs(endShift) <= threshold {
                    bestShift = preferredSnapShift(current: bestShift, candidate: endShift)
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
            snappedStart = max(editBounds.minStart, min(end - minSegmentDuration, snappedStart))
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
            snappedEnd = min(editBounds.maxEnd, max(start + minSegmentDuration, snappedEnd))
            return (start, snappedEnd)
        }
    }

    private func commitInteraction(for id: UUID) {
        guard let interaction = activeSegmentInteraction, interaction.id == id else {
            return
        }

        let didApply = onSegmentTimeRangeChange?(id, interaction.previewStart, interaction.previewEnd) ?? false
        if !didApply {
            activeSegmentInteraction = nil
            return
        }

        activeSegmentInteraction = nil
    }

    private func snapTargets(from ranges: [SegmentRange], excluding id: UUID) -> [TimeInterval] {
        var targets = ranges
            .filter { $0.id != id }
            .flatMap { [$0.start, $0.end] }
        targets.append(currentTime)
        return targets
    }

    private func editBounds(
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

    private func updateResizeCursor(_ isHovering: Bool) {
        #if os(macOS)
        if isHovering {
            if resizeCursorHoverCount == 0 {
                NSCursor.resizeLeftRight.push()
            }
            resizeCursorHoverCount += 1
            return
        }

        resizeCursorHoverCount = max(0, resizeCursorHoverCount - 1)
        if resizeCursorHoverCount == 0 {
            NSCursor.pop()
        }
        #endif
    }

    private func resetResizeCursorIfNeeded() {
        #if os(macOS)
        while resizeCursorHoverCount > 0 {
            NSCursor.pop()
            resizeCursorHoverCount -= 1
        }
        #endif
    }

    private var trimOverlay: some View {
        let effectiveTrimEnd = trimEnd ?? duration
        let startX = CGFloat(trimStart) * pixelsPerSecond
        let endX = CGFloat(effectiveTrimEnd) * pixelsPerSecond

        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if trimStart > 0 {
                    Rectangle().fill(Color.black.opacity(0.5)).frame(width: startX).allowsHitTesting(false)
                }

                if effectiveTrimEnd < duration {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: CGFloat(duration - effectiveTrimEnd) * pixelsPerSecond)
                        .offset(x: endX)
                        .allowsHitTesting(false)
                }

                TrimHandleView(isStart: true, isDragging: $isDraggingTrimStart)
                    .frame(height: geometry.size.height)
                    .offset(x: startX - 6)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDraggingTrimStart = true
                                let newTime = max(0, Double(value.location.x) / Double(pixelsPerSecond))
                                trimStart = min(newTime, effectiveTrimEnd - 0.1)
                            }
                            .onEnded { _ in
                                isDraggingTrimStart = false
                                onTrimChange?(trimStart, trimEnd)
                            }
                    )

                TrimHandleView(isStart: false, isDragging: $isDraggingTrimEnd)
                    .frame(height: geometry.size.height)
                    .offset(x: endX - 6)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDraggingTrimEnd = true
                                let newTime = min(duration, Double(value.location.x) / Double(pixelsPerSecond))
                                trimEnd = max(newTime, trimStart + 0.1)
                            }
                            .onEnded { _ in
                                isDraggingTrimEnd = false
                                onTrimChange?(trimStart, trimEnd)
                            }
                    )
            }
        }
        .offset(y: rulerHeight)
    }

    private func fitToView() {
        guard duration > 0 else { return }
        let availableWidth = timelineAreaWidth > 0 ? timelineAreaWidth : 600
        pixelsPerSecond = max(minPixelsPerSecond, availableWidth / CGFloat(duration))
    }

}

// MARK: - Timeline Grid View

/// Timeline background grid.
struct TimelineGridView: View {

    let duration: TimeInterval
    let pixelsPerSecond: CGFloat
    let scrollOffset: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
        }
    }

    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let visibleStartTime = scrollOffset / pixelsPerSecond
        let visibleEndTime = (scrollOffset + size.width) / pixelsPerSecond

        let interval: TimeInterval = pixelsPerSecond < 30 ? 5.0 : 1.0
        var time = floor(visibleStartTime / interval) * interval

        while time <= visibleEndTime {
            let x = CGFloat(time) * pixelsPerSecond - scrollOffset

            if x >= 0 && x <= size.width {
                let linePath = Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }

                context.stroke(
                    linePath,
                    with: .color(.secondary.opacity(0.1)),
                    lineWidth: 1
                )
            }

            time += interval
        }
    }
}

// MARK: - Track Color

/// Track colors by timeline track type.
enum TrackColor {
    static let transform = Color.blue
    static let cursor = Color.orange
    static let keystroke = Color.cyan

    static func color(for trackType: TrackType) -> Color {
        switch trackType {
        case .transform:
            return transform
        case .cursor:
            return cursor
        case .keystroke:
            return keystroke
        case .audio:
            return .green
        }
    }
}
