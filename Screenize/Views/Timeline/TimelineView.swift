import SwiftUI

/// Segment timeline view.
struct TimelineView: View {

    @Binding var timeline: Timeline
    let duration: TimeInterval
    @Binding var currentTime: TimeInterval
    @Binding var selectedKeyframeID: UUID?
    @Binding var selectedTrackType: TrackType?

    var onKeyframeChange: ((UUID, TimeInterval) -> Void)?
    var onAddKeyframe: ((TrackType, TimeInterval) -> Void)?
    var onKeyframeSelect: ((TrackType, UUID) -> Void)?
    var onSeek: ((TimeInterval) async -> Void)?

    @Binding var trimStart: TimeInterval
    @Binding var trimEnd: TimeInterval?
    var onTrimChange: ((TimeInterval, TimeInterval?) -> Void)?

    @State private var pixelsPerSecond: CGFloat = 50
    @State private var timelineAreaWidth: CGFloat = 0
    @State private var isDraggingTrimStart = false
    @State private var isDraggingTrimEnd = false

    private let minPixelsPerSecond: CGFloat = 10
    private let maxPixelsPerSecond: CGFloat = 200
    private let rulerHeight: CGFloat = 24
    private let trackHeight: CGFloat = 40
    private let headerWidth: CGFloat = 120

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

                Slider(value: $pixelsPerSecond, in: minPixelsPerSecond...maxPixelsPerSecond)
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
                    Image(systemName: trackIcon(for: track.trackType))
                        .foregroundColor(KeyframeColor.color(for: track.trackType))
                        .frame(width: 16)

                    Text(track.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(track.isEnabled ? .primary : .secondary)

                    Spacer()

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
                    onAddKeyframe?(track.trackType, time)
                }
                .onTapGesture {
                    selectedKeyframeID = nil
                    selectedTrackType = nil
                }

            segmentBlocks(for: track)
        }
        .frame(height: trackHeight)
        .opacity(track.isEnabled ? 1.0 : 0.5)
    }

    @ViewBuilder
    private func segmentBlocks(for track: AnySegmentTrack) -> some View {
        switch track {
        case .camera(let cameraTrack):
            ForEach(cameraTrack.segments) { segment in
                segmentBlock(trackType: .transform, id: segment.id, start: segment.startTime, end: segment.endTime)
            }
        case .cursor(let cursorTrack):
            ForEach(cursorTrack.segments) { segment in
                segmentBlock(trackType: .cursor, id: segment.id, start: segment.startTime, end: segment.endTime)
            }
        case .keystroke(let keystrokeTrack):
            ForEach(keystrokeTrack.segments) { segment in
                segmentBlock(trackType: .keystroke, id: segment.id, start: segment.startTime, end: segment.endTime)
            }
        }
    }

    private func segmentBlock(trackType: TrackType, id: UUID, start: TimeInterval, end: TimeInterval) -> some View {
        let x = CGFloat(start) * pixelsPerSecond
        let width = max(6, CGFloat(end - start) * pixelsPerSecond)
        let color = KeyframeColor.color(for: trackType)

        return RoundedRectangle(cornerRadius: 4)
            .fill(color.opacity(selectedKeyframeID == id ? 0.9 : 0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(selectedKeyframeID == id ? Color.white : Color.clear, lineWidth: 1)
            )
            .frame(width: width, height: 22)
            .position(x: x + width / 2, y: trackHeight / 2)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let deltaTime = Double(value.translation.width / pixelsPerSecond)
                        let segmentDuration = end - start
                        let newStart = max(0, min(duration - segmentDuration, start + deltaTime))
                        onKeyframeChange?(id, newStart)
                    }
                    .onEnded { _ in
                        onKeyframeSelect?(trackType, id)
                        selectedKeyframeID = id
                        selectedTrackType = trackType
                    }
            )
            .onTapGesture {
                onKeyframeSelect?(trackType, id)
                selectedKeyframeID = id
                selectedTrackType = trackType
            }
            .opacity(isSegmentInTrimRange(start: start, end: end) ? 1.0 : 0.3)
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
        pixelsPerSecond = max(minPixelsPerSecond, min(maxPixelsPerSecond, availableWidth / CGFloat(duration)))
    }

    private func trackIcon(for type: TrackType) -> String {
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

    private func isSegmentInTrimRange(start: TimeInterval, end: TimeInterval) -> Bool {
        let effectiveTrimEnd = trimEnd ?? duration
        return end > trimStart && start < effectiveTrimEnd
    }
}
