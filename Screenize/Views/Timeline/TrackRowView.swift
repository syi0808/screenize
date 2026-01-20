import SwiftUI

/// Track row view (header + keyframe area)
struct TrackRowView<T: Track>: View {

    // MARK: - Properties

    /// Track
    @Binding var track: T

    /// Track type
    let trackType: TrackType

    /// Timeline duration
    let duration: TimeInterval

    /// Seconds per pixel
    let pixelsPerSecond: CGFloat

    /// Scroll offset
    let scrollOffset: CGFloat

    /// Selected keyframe ID
    @Binding var selectedKeyframeID: UUID?

    /// Keyframe selection callback
    var onKeyframeSelect: ((UUID) -> Void)?

    /// Keyframe time change callback
    var onKeyframeTimeChange: ((UUID, TimeInterval) -> Void)?

    /// Keyframe addition callback
    var onAddKeyframe: ((TimeInterval) -> Void)?

    // MARK: - Constants

    static var headerWidth: CGFloat { 120 }
    static var rowHeight: CGFloat { 40 }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Track header
            trackHeader

            Divider()

            // Keyframe area
            keyframeArea
        }
        .frame(height: Self.rowHeight)
        .background(trackBackground)
    }

    // MARK: - Track Header

    private var trackHeader: some View {
        HStack(spacing: 8) {
            // Track icon
            Image(systemName: trackIcon)
                .foregroundColor(trackColor)
                .frame(width: 16)

            // Track name
            Text(track.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundColor(track.isEnabled ? .primary : .secondary)

            Spacer()

            // Enable toggle
            Button {
                track.isEnabled.toggle()
            } label: {
                Image(systemName: track.isEnabled ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(track.isEnabled ? .secondary : .tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(width: Self.headerWidth)
        .opacity(track.isEnabled ? 1.0 : 0.6)
    }

    // MARK: - Keyframe Area

    private var keyframeArea: some View {
        GeometryReader { _ in
            ZStack(alignment: .leading) {
                // Background grid
                TimelineGridView(
                    duration: duration,
                    pixelsPerSecond: pixelsPerSecond,
                    scrollOffset: scrollOffset,
                    height: Self.rowHeight
                )

                // Keyframe markers (handled differently per track type)
                keyframeMarkers

                // Double-click to add a keyframe
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { location in
                        let time = timeFromPosition(location.x)
                        onAddKeyframe?(time)
                    }
            }
        }
        .clipped()
    }

    // MARK: - Keyframe Markers

    @ViewBuilder
    private var keyframeMarkers: some View {
        // Render keyframes per track type
        // Keyframe data comes from the track itself
        if let transformTrack = track as? TransformTrack {
            ForEach(transformTrack.keyframes) { keyframe in
                DraggableKeyframeMarker(
                    id: keyframe.id,
                    time: keyframe.time,
                    isSelected: selectedKeyframeID == keyframe.id,
                    color: trackColor,
                    pixelsPerSecond: pixelsPerSecond,
                    scrollOffset: scrollOffset,
                    duration: duration,
                    onSelect: { onKeyframeSelect?(keyframe.id) },
                    onTimeChange: { newTime in
                        onKeyframeTimeChange?(keyframe.id, newTime)
                    }
                )
                .position(x: 6, y: Self.rowHeight / 2)
            }
        } else if let rippleTrack = track as? RippleTrack {
            ForEach(rippleTrack.keyframes) { keyframe in
                DraggableKeyframeMarker(
                    id: keyframe.id,
                    time: keyframe.time,
                    isSelected: selectedKeyframeID == keyframe.id,
                    color: trackColor,
                    pixelsPerSecond: pixelsPerSecond,
                    scrollOffset: scrollOffset,
                    duration: duration,
                    onSelect: { onKeyframeSelect?(keyframe.id) },
                    onTimeChange: { newTime in
                        onKeyframeTimeChange?(keyframe.id, newTime)
                    }
                )
                .position(x: 6, y: Self.rowHeight / 2)
            }
        } else if let cursorTrack = track as? CursorTrack {
            ForEach(cursorTrack.styleKeyframes ?? []) { keyframe in
                DraggableKeyframeMarker(
                    id: keyframe.id,
                    time: keyframe.time,
                    isSelected: selectedKeyframeID == keyframe.id,
                    color: trackColor,
                    pixelsPerSecond: pixelsPerSecond,
                    scrollOffset: scrollOffset,
                    duration: duration,
                    onSelect: { onKeyframeSelect?(keyframe.id) },
                    onTimeChange: { newTime in
                        onKeyframeTimeChange?(keyframe.id, newTime)
                    }
                )
                .position(x: 6, y: Self.rowHeight / 2)
            }
        }
    }

    // MARK: - Computed Properties

    private var trackColor: Color {
        KeyframeColor.color(for: trackType)
    }

    private var trackIcon: String {
        switch trackType {
        case .transform:
            return "arrow.up.left.and.arrow.down.right"
        case .ripple:
            return "circles.hexagonpath"
        case .cursor:
            return "cursorarrow"
        case .keystroke:
            return "keyboard"
        case .audio:
            return "waveform"
        }
    }

    private var trackBackground: some View {
        track.isEnabled
            ? Color(nsColor: .controlBackgroundColor)
            : Color(nsColor: .controlBackgroundColor).opacity(0.5)
    }

    // MARK: - Helpers

    private func timeFromPosition(_ x: CGFloat) -> TimeInterval {
        let time = Double(x + scrollOffset) / Double(pixelsPerSecond)
        return max(0, min(duration, time))
    }
}

// MARK: - Timeline Grid View

/// Timeline background grid
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

        // Vertical lines every second
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

// MARK: - Generic Track Row (Type-erased version)

/// Type-erased track row view
struct AnyTrackRowView: View {

    @Binding var track: AnyTrack
    let duration: TimeInterval
    let pixelsPerSecond: CGFloat
    let scrollOffset: CGFloat
    @Binding var selectedKeyframeID: UUID?

    var onKeyframeSelect: ((UUID) -> Void)?
    var onKeyframeTimeChange: ((UUID, TimeInterval) -> Void)?
    var onAddKeyframe: ((TimeInterval) -> Void)?

    var body: some View {
        switch track {
        case .transform(var transformTrack):
            TrackRowView(
                track: Binding(
                    get: { transformTrack },
                    set: { newValue in
                        transformTrack = newValue
                        track = .transform(newValue)
                    }
                ),
                trackType: .transform,
                duration: duration,
                pixelsPerSecond: pixelsPerSecond,
                scrollOffset: scrollOffset,
                selectedKeyframeID: $selectedKeyframeID,
                onKeyframeSelect: onKeyframeSelect,
                onKeyframeTimeChange: onKeyframeTimeChange,
                onAddKeyframe: onAddKeyframe
            )

        case .ripple(var rippleTrack):
            TrackRowView(
                track: Binding(
                    get: { rippleTrack },
                    set: { newValue in
                        rippleTrack = newValue
                        track = .ripple(newValue)
                    }
                ),
                trackType: .ripple,
                duration: duration,
                pixelsPerSecond: pixelsPerSecond,
                scrollOffset: scrollOffset,
                selectedKeyframeID: $selectedKeyframeID,
                onKeyframeSelect: onKeyframeSelect,
                onKeyframeTimeChange: onKeyframeTimeChange,
                onAddKeyframe: onAddKeyframe
            )

        case .cursor(var cursorTrack):
            TrackRowView(
                track: Binding(
                    get: { cursorTrack },
                    set: { newValue in
                        cursorTrack = newValue
                        track = .cursor(newValue)
                    }
                ),
                trackType: .cursor,
                duration: duration,
                pixelsPerSecond: pixelsPerSecond,
                scrollOffset: scrollOffset,
                selectedKeyframeID: $selectedKeyframeID,
                onKeyframeSelect: onKeyframeSelect,
                onKeyframeTimeChange: onKeyframeTimeChange,
                onAddKeyframe: onAddKeyframe
            )

        case .keystroke(var keystrokeTrack):
            TrackRowView(
                track: Binding(
                    get: { keystrokeTrack },
                    set: { newValue in
                        keystrokeTrack = newValue
                        track = .keystroke(newValue)
                    }
                ),
                trackType: .keystroke,
                duration: duration,
                pixelsPerSecond: pixelsPerSecond,
                scrollOffset: scrollOffset,
                selectedKeyframeID: $selectedKeyframeID,
                onKeyframeSelect: onKeyframeSelect,
                onKeyframeTimeChange: onKeyframeTimeChange,
                onAddKeyframe: onAddKeyframe
            )
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var track = TransformTrack(
            id: UUID(),
            name: "Transform",
            isEnabled: true,
            keyframes: [
                TransformKeyframe(time: 0, zoom: 1.0, centerX: 0.5, centerY: 0.5),
                TransformKeyframe(time: 2, zoom: 2.0, centerX: 0.3, centerY: 0.4),
                TransformKeyframe(time: 5, zoom: 1.5, centerX: 0.7, centerY: 0.6),
            ]
        )
        @State private var selectedID: UUID?

        var body: some View {
            VStack(spacing: 0) {
                TrackRowView(
                    track: $track,
                    trackType: .transform,
                    duration: 10,
                    pixelsPerSecond: 50,
                    scrollOffset: 0,
                    selectedKeyframeID: $selectedID,
                    onKeyframeSelect: { id in
                        selectedID = id
                    },
                    onAddKeyframe: { time in
                        print("Add keyframe at \(time)")
                    }
                )

                Divider()
            }
            .frame(width: 600)
        }
    }

    return PreviewWrapper()
}
