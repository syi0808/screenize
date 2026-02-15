import SwiftUI

/// Timeline main view
/// Combines the time ruler, tracks, and playhead display
struct TimelineView: View {

    // MARK: - Properties

    /// Timeline model
    @Binding var timeline: Timeline

    /// Total duration (seconds)
    let duration: TimeInterval

    /// Current time
    @Binding var currentTime: TimeInterval

    /// Selected keyframe ID
    @Binding var selectedKeyframeID: UUID?

    /// Selected track type
    @Binding var selectedTrackType: TrackType?

    /// Keyframe change callback
    var onKeyframeChange: ((UUID, TimeInterval) -> Void)?

    /// Keyframe addition callback
    var onAddKeyframe: ((TrackType, TimeInterval) -> Void)?

    /// Keyframe selection callback (track type + ID)
    var onKeyframeSelect: ((TrackType, UUID) -> Void)?

    /// Time seek callback (keeps PreviewEngine synchronized)
    var onSeek: ((TimeInterval) async -> Void)?

    /// Trim start time
    @Binding var trimStart: TimeInterval

    /// Trim end time (uses duration when nil)
    @Binding var trimEnd: TimeInterval?

    /// Trim change callback
    var onTrimChange: ((TimeInterval, TimeInterval?) -> Void)?

    // MARK: - State

    /// Seconds per pixel (zoom level)
    @State private var pixelsPerSecond: CGFloat = 50

    /// Scroll offset
    @State private var scrollOffset: CGFloat = 0

    /// Whether the playhead is being dragged
    @State private var isPlayheadDragging = false

    /// Timeline area width (excluding the header)
    @State private var timelineAreaWidth: CGFloat = 0

    /// Track if the trim start handle is being dragged
    @State private var isDraggingTrimStart = false

    /// Track if the trim end handle is being dragged
    @State private var isDraggingTrimEnd = false

    // MARK: - Constants

    private let minPixelsPerSecond: CGFloat = 10
    private let maxPixelsPerSecond: CGFloat = 200
    private let rulerHeight: CGFloat = 24
    private let trackHeight: CGFloat = 40

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Zoom controls and time display
            toolbar

            Divider()

            // Timeline body
            GeometryReader { geometry in
                let headerWidth = TrackRowView<TransformTrack>.headerWidth
                let availableWidth = geometry.size.width - headerWidth - 1 // 1px for Divider
                let contentWidth = max(availableWidth, CGFloat(duration) * pixelsPerSecond)

                HStack(spacing: 0) {
                    // Left: track header area
                    trackHeaders

                    Divider()

                    // Right: scrollable timeline area
                    HorizontalScrollViewWithVerticalWheel {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                // Time ruler
                                TimeRulerView(
                                    duration: duration,
                                    currentTime: currentTime,
                                    pixelsPerSecond: pixelsPerSecond,
                                    scrollOffset: 0,
                                    onTimeTap: { time in
                                        currentTime = time
                                        Task {
                                            await onSeek?(time)
                                        }
                                    }
                                )

                                Divider()

                                // Track keyframe area
                                trackContent
                            }

                            // Trim overlay
                            trimOverlay

                            // Playhead (full height)
                            PlayheadLine(
                                currentTime: currentTime,
                                pixelsPerSecond: pixelsPerSecond,
                                scrollOffset: 0
                            )
                            .offset(y: rulerHeight)
                        }
                        .frame(width: contentWidth)
                    }
                    .background(GeometryReader { scrollGeometry in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: scrollGeometry.frame(in: .named("timeline")).origin.x
                            )
                    })
                    .coordinateSpace(name: "timeline")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                        scrollOffset = -offset
                    }
                }
                .onChange(of: geometry.size.width) { newWidth in
                    timelineAreaWidth = newWidth - headerWidth - 1
                }
                .onAppear {
                    timelineAreaWidth = availableWidth
                    // Always fit when entering the editor page
                    if duration > 0 {
                        fitToView()
                    }
                }
            }
        }
        .onChange(of: duration) { newDuration in
            // Refit when the duration changes (e.g., after loading a new file)
            if newDuration > 0 && timelineAreaWidth > 0 {
                fitToView()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Spacer()

            // Zoom controls
            HStack(spacing: 8) {
                Button {
                    zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .disabled(pixelsPerSecond <= minPixelsPerSecond)

                // Zoom slider
                Slider(
                    value: $pixelsPerSecond,
                    in: minPixelsPerSecond...maxPixelsPerSecond
                )
                .frame(width: 100)

                Button {
                    zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.plain)
                .disabled(pixelsPerSecond >= maxPixelsPerSecond)

                // Fit to view
                Button {
                    fitToView()
                } label: {
                    Image(systemName: "arrow.left.and.right.square")
                }
                .buttonStyle(.plain)
                .help("Fit timeline to view")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Track Headers

    private var trackHeaders: some View {
        VStack(spacing: 0) {
            // Spacer for the time ruler height
            Color.clear
                .frame(height: rulerHeight)

            Divider()

            // Track headers
            ForEach(Array(timeline.tracks.enumerated()), id: \.element.id) { index, track in
                trackHeaderRow(for: track, at: index)
                Divider()
            }

            Spacer()
        }
        .frame(width: TrackRowView<TransformTrack>.headerWidth)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func trackHeaderRow(for track: AnyTrack, at index: Int) -> some View {
        HStack(spacing: 8) {
            // Track icon
            Image(systemName: trackIcon(for: track.trackType))
                .foregroundColor(KeyframeColor.color(for: track.trackType))
                .frame(width: 16)

            // Track name
            Text(track.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundColor(track.isEnabled ? .primary : .secondary)

            Spacer()

            // Enable/disable toggle
            Button {
                var updatedTrack = track
                updatedTrack.isEnabled.toggle()
                timeline.tracks[index] = updatedTrack
            } label: {
                Image(systemName: track.isEnabled ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(track.isEnabled ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: trackHeight)
    }

    // MARK: - Track Content

    private var trackContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(timeline.tracks.enumerated()), id: \.element.id) { index, track in
                trackKeyframeArea(for: track, at: index)
                Divider()
            }

            Spacer()
        }
    }

    private func trackKeyframeArea(for track: AnyTrack, at index: Int) -> some View {
        ZStack(alignment: .leading) {
            // Background grid
            TimelineGridView(
                duration: duration,
                pixelsPerSecond: pixelsPerSecond,
                scrollOffset: 0,
                height: trackHeight
            )
            .opacity(track.isEnabled ? 1.0 : 0.5)

            // Double-click to add keyframe (placed in the background)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    // Inside NSScrollView, location is relative to the entire content, so scrollOffset is unnecessary
                    let time = max(0, min(duration, Double(location.x) / Double(pixelsPerSecond)))
                    onAddKeyframe?(track.trackType, time)
                }
                .onTapGesture(count: 1) {
                    selectedKeyframeID = nil
                    selectedTrackType = nil
                }

            // Keyframe markers (placed above everything so they are clickable)
            keyframeMarkers(for: track)
                .opacity(track.isEnabled ? 1.0 : 0.5)
        }
        .frame(height: trackHeight)
        .coordinateSpace(name: "trackContent")
    }

    @ViewBuilder
    private func keyframeMarkers(for track: AnyTrack) -> some View {
        let color = KeyframeColor.color(for: track.trackType)

        switch track {
        case .transform(let transformTrack):
            ForEach(transformTrack.keyframes) { keyframe in
                DraggableKeyframeMarker(
                    id: keyframe.id,
                    time: keyframe.time,
                    isSelected: selectedKeyframeID == keyframe.id,
                    color: color,
                    pixelsPerSecond: pixelsPerSecond,
                    scrollOffset: 0,
                    duration: duration,
                    onSelect: {
                        selectedKeyframeID = keyframe.id
                        selectedTrackType = .transform
                        onKeyframeSelect?(.transform, keyframe.id)
                    },
                    onTimeChange: { newTime in
                        onKeyframeChange?(keyframe.id, newTime)
                    }
                )
                .opacity(isTimeInTrimRange(keyframe.time) ? 1.0 : 0.3)
                .position(x: CGFloat(keyframe.time) * pixelsPerSecond, y: trackHeight / 2)
            }

        case .cursor(let cursorTrack):
            if let keyframes = cursorTrack.styleKeyframes {
                ForEach(keyframes) { keyframe in
                    DraggableKeyframeMarker(
                        id: keyframe.id,
                        time: keyframe.time,
                        isSelected: selectedKeyframeID == keyframe.id,
                        color: color,
                        pixelsPerSecond: pixelsPerSecond,
                        scrollOffset: 0,
                        duration: duration,
                        onSelect: {
                            selectedKeyframeID = keyframe.id
                            selectedTrackType = .cursor
                            onKeyframeSelect?(.cursor, keyframe.id)
                        },
                        onTimeChange: { newTime in
                            onKeyframeChange?(keyframe.id, newTime)
                        }
                    )
                    .opacity(isTimeInTrimRange(keyframe.time) ? 1.0 : 0.3)
                    .position(x: CGFloat(keyframe.time) * pixelsPerSecond, y: trackHeight / 2)
                }
            }

        case .keystroke(let keystrokeTrack):
            ForEach(keystrokeTrack.keyframes) { keyframe in
                DraggableKeyframeMarker(
                    id: keyframe.id,
                    time: keyframe.time,
                    isSelected: selectedKeyframeID == keyframe.id,
                    color: color,
                    pixelsPerSecond: pixelsPerSecond,
                    scrollOffset: 0,
                    duration: duration,
                    onSelect: {
                        selectedKeyframeID = keyframe.id
                        selectedTrackType = .keystroke
                        onKeyframeSelect?(.keystroke, keyframe.id)
                    },
                    onTimeChange: { newTime in
                        onKeyframeChange?(keyframe.id, newTime)
                    }
                )
                .opacity(isTimeInTrimRange(keyframe.time) ? 1.0 : 0.3)
                .position(x: CGFloat(keyframe.time) * pixelsPerSecond, y: trackHeight / 2)
            }
        }
    }

    // MARK: - Helpers

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

    private func zoomIn() {
        pixelsPerSecond = min(maxPixelsPerSecond, pixelsPerSecond * 1.5)
    }

    private func zoomOut() {
        pixelsPerSecond = max(minPixelsPerSecond, pixelsPerSecond / 1.5)
    }

    private func fitToView() {
        guard duration > 0 else { return }
        let availableWidth = timelineAreaWidth > 0 ? timelineAreaWidth : 600
        pixelsPerSecond = max(minPixelsPerSecond, min(maxPixelsPerSecond, availableWidth / CGFloat(duration)))
    }

    // MARK: - Trim Overlay

    /// Trim overlay (inactive areas + handles)
    private var trimOverlay: some View {
        let effectiveTrimStart = trimStart
        let effectiveTrimEnd = trimEnd ?? duration

        let startX = CGFloat(effectiveTrimStart) * pixelsPerSecond
        let endX = CGFloat(effectiveTrimEnd) * pixelsPerSecond

        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Inactive area before the trim (left)
                if effectiveTrimStart > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: startX)
                        .allowsHitTesting(false)
                }

                // Inactive area after the trim (right)
                if effectiveTrimEnd < duration {
                    Rectangle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: CGFloat(duration - effectiveTrimEnd) * pixelsPerSecond)
                        .offset(x: endX)
                        .allowsHitTesting(false)
                }

                // Start trim handle
                TrimHandleView(isStart: true, isDragging: $isDraggingTrimStart)
                    .frame(height: geometry.size.height)
                    .offset(x: startX - 6) // Center the handle
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDraggingTrimStart = true
                                let newTime = max(0, Double(value.location.x) / Double(pixelsPerSecond))
                                // Maintain a minimum of 0.1 seconds
                                let clampedTime = min(newTime, effectiveTrimEnd - 0.1)
                                trimStart = max(0, clampedTime)
                            }
                            .onEnded { _ in
                                isDraggingTrimStart = false
                                onTrimChange?(trimStart, trimEnd)
                            }
                    )

                // End trim handle
                TrimHandleView(isStart: false, isDragging: $isDraggingTrimEnd)
                    .frame(height: geometry.size.height)
                    .offset(x: endX - 6) // Center the handle
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDraggingTrimEnd = true
                                let newTime = min(duration, Double(value.location.x) / Double(pixelsPerSecond))
                                // Maintain a minimum of 0.1 seconds
                                let clampedTime = max(newTime, effectiveTrimStart + 0.1)
                                trimEnd = min(duration, clampedTime)
                            }
                            .onEnded { _ in
                                isDraggingTrimEnd = false
                                onTrimChange?(trimStart, trimEnd)
                            }
                    )
            }
        }
        .offset(y: rulerHeight) // Position below the ruler
    }

    /// Check whether a given time falls within the trim range
    private func isTimeInTrimRange(_ time: TimeInterval) -> Bool {
        let effectiveTrimEnd = trimEnd ?? duration
        return time >= trimStart && time <= effectiveTrimEnd
    }
}

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var timeline = Timeline(
            tracks: [
                AnyTrack(TransformTrack(
                    id: UUID(),
                    name: "Transform",
                    isEnabled: true,
                    keyframes: [
                        TransformKeyframe(time: 0, zoom: 1.0, centerX: 0.5, centerY: 0.5),
                        TransformKeyframe(time: 2, zoom: 2.0, centerX: 0.3, centerY: 0.4),
                        TransformKeyframe(time: 5, zoom: 1.5, centerX: 0.7, centerY: 0.6),
                        TransformKeyframe(time: 8, zoom: 1.0, centerX: 0.5, centerY: 0.5),
                    ]
                )),
                AnyTrack(CursorTrack(
                    id: UUID(),
                    name: "Cursor",
                    isEnabled: true
                )),
            ],
            duration: 10
        )
        @State private var currentTime: TimeInterval = 2.5
        @State private var selectedKeyframeID: UUID?
        @State private var selectedTrackType: TrackType? = .transform
        @State private var trimStart: TimeInterval = 1.0
        @State private var trimEnd: TimeInterval? = 8.0

        var body: some View {
            VStack {
                Text("Selected: \(selectedKeyframeID?.uuidString.prefix(8) ?? "None")")
                    .font(.caption)

                TimelineView(
                    timeline: $timeline,
                    duration: 10,
                    currentTime: $currentTime,
                    selectedKeyframeID: $selectedKeyframeID,
                    selectedTrackType: $selectedTrackType,
                    onKeyframeChange: { id, time in
                        print("Keyframe \(id) moved to \(time)")
                    },
                    onAddKeyframe: { type, time in
                        print("Add \(type) keyframe at \(time)")
                    },
                    trimStart: $trimStart,
                    trimEnd: $trimEnd,
                    onTrimChange: { start, end in
                        print("Trim changed: \(start) - \(String(describing: end))")
                    }
                )
                .frame(height: 200)
            }
            .frame(width: 800)
            .padding()
        }
    }

    return PreviewWrapper()
}
