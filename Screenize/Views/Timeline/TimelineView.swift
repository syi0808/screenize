import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SegmentRange {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
}

struct SegmentEditBounds {
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

func timelineIsSegmentInTrimRange(
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
    @Binding var selection: SegmentSelection

    var onSegmentTimeRangeChange: ((UUID, TimeInterval, TimeInterval) -> Bool)?
    var onBatchSegmentTimeRangeChange: (([(UUID, TimeInterval, TimeInterval)]) -> Void)?
    var onAddSegment: ((TrackType, TimeInterval) -> Void)?
    var onSegmentSelect: ((TrackType, UUID) -> Void)?
    var onSegmentToggleSelect: ((TrackType, UUID) -> Void)?
    var onSeek: ((TimeInterval) async -> Void)?

    @Binding var trimStart: TimeInterval
    @Binding var trimEnd: TimeInterval?
    var onTrimChange: ((TimeInterval, TimeInterval?) -> Void)?

    @State var pixelsPerSecond: CGFloat = 50
    @State private var timelineAreaWidth: CGFloat = 0
    @State private var isDraggingTrimStart = false
    @State private var isDraggingTrimEnd = false
    @State var activeSegmentInteraction: SegmentInteraction?
    @State private var resizeCursorHoverCount = 0
    @State var hoveredSegmentID: UUID?

    private let minPixelsPerSecond: CGFloat = 1
    private let maxPixelsPerSecond: CGFloat = 2000
    let minSegmentDuration: TimeInterval = 0.05
    let snapThresholdInPoints: CGFloat = 8
    private let rulerHeight: CGFloat = 24
    let trackHeight: CGFloat = 40
    private let headerWidth: CGFloat = 140

    /// Total height of ruler + all track rows (including dividers)
    private var totalContentHeight: CGFloat {
        rulerHeight + 1 + CGFloat(timeline.tracks.count) * (trackHeight + 1)
    }

    private var logZoom: Binding<Double> {
        Binding(
            get: { log2(Double(pixelsPerSecond)) },
            set: { pixelsPerSecond = CGFloat(pow(2, $0)) }
        )
    }

    enum SegmentInteractionMode {
        case move
        case resizeStart
        case resizeEnd
    }

    struct SegmentInteraction {
        let id: UUID
        let mode: SegmentInteractionMode
        let initialStart: TimeInterval
        let initialEnd: TimeInterval
        var previewStart: TimeInterval
        var previewEnd: TimeInterval
        var companions: [CompanionSegment] = []
    }

    // CompanionSegment is defined in TimelineView+MultiMove.swift

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            GeometryReader { geometry in
                let availableWidth = geometry.size.width - headerWidth - 1
                let contentWidth = max(availableWidth, CGFloat(duration) * pixelsPerSecond)

                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 0) {
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
                        .frame(height: totalContentHeight)
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
        .background(DesignColors.windowBackground)
    }

    private var toolbar: some View {
        HStack {
            Spacer()

            HStack(spacing: Spacing.sm) {
                Button { pixelsPerSecond = max(minPixelsPerSecond, pixelsPerSecond / 1.5) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(ToolbarIconButtonStyle())

                Slider(
                    value: logZoom,
                    in: log2(Double(minPixelsPerSecond))...log2(Double(maxPixelsPerSecond))
                )
                .frame(width: 100)

                Button { pixelsPerSecond = min(maxPixelsPerSecond, pixelsPerSecond * 1.5) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(ToolbarIconButtonStyle())

                Button { fitToView() } label: {
                    Image(systemName: "arrow.left.and.right.square")
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .help("Fit timeline to view")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
    }

    private var trackHeaders: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: rulerHeight)
            Divider()

            ForEach(Array(timeline.tracks.enumerated()), id: \.element.id) { index, track in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: timelineTrackIcon(for: track.trackType))
                        .foregroundColor(DesignColors.trackColor(for: track.trackType))
                        .frame(width: Spacing.lg)

                    Text(track.name)
                        .font(Typography.timelineLabel)
                        .lineLimit(1)
                        .foregroundColor(track.isEnabled ? .primary : .secondary)

                    Spacer()

                    Button {
                        var updated = track
                        updated.isEnabled.toggle()
                        timeline.tracks[index] = updated
                    } label: {
                        Image(systemName: track.isEnabled ? "eye" : "eye.slash")
                            .font(Typography.monoSmall)
                            .foregroundStyle(track.isEnabled ? .secondary : .tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Spacing.sm)
                .frame(height: trackHeight)

                Divider()
            }

        }
        .frame(width: headerWidth)
        .background(DesignColors.controlBackground)
    }

    private var trackContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(timeline.tracks.enumerated()), id: \.element.id) { _, track in
                trackArea(for: track)
                Divider()
            }
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
                    selection.clear()
                }

            segmentBlocks(for: track)
        }
        .frame(height: trackHeight)
        .opacity(track.isEnabled ? 1.0 : 0.5)
        .coordinateSpace(name: "trackArea")
    }

}

// MARK: - Snapping & Interaction Helpers

extension TimelineView {

    func isInteracting(with id: UUID, mode: SegmentInteractionMode) -> Bool {
        guard let interaction = activeSegmentInteraction else { return false }
        return interaction.id == id && interaction.mode == mode
    }

    func segmentDisplayStart(for id: UUID, fallback: TimeInterval) -> TimeInterval {
        guard let interaction = activeSegmentInteraction else { return fallback }
        if interaction.id == id { return interaction.previewStart }
        if let companion = interaction.companions.first(where: { $0.id == id }) {
            return companion.previewStart
        }
        return fallback
    }

    func segmentDisplayEnd(for id: UUID, fallback: TimeInterval) -> TimeInterval {
        guard let interaction = activeSegmentInteraction else { return fallback }
        if interaction.id == id { return interaction.previewEnd }
        if let companion = interaction.companions.first(where: { $0.id == id }) {
            return companion.previewEnd
        }
        return fallback
    }

    // snappedRange, commitInteraction, snapTargets, editBounds
    // are in TimelineView+MultiMove.swift

    func updateResizeCursor(_ isHovering: Bool) {
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

// TrackColor moved to DesignSystem/DesignColors.swift
