import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Segment Block Rendering

extension TimelineView {

    @ViewBuilder
    func segmentBlocks(for track: AnySegmentTrack) -> some View {
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
        case .audio(let audioTrack):
            let ranges = audioTrack.segments.map {
                SegmentRange(id: $0.id, start: $0.startTime, end: $0.endTime)
            }

            ForEach(audioTrack.segments) { segment in
                segmentBlock(
                    trackType: .audio,
                    id: segment.id,
                    start: segment.startTime,
                    end: segment.endTime,
                    ranges: ranges,
                    editBounds: editBounds(from: ranges, excluding: segment.id, currentStart: segment.startTime, currentEnd: segment.endTime)
                )
            }
        }
    }

    func segmentBlock(
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
        let color = DesignColors.trackColor(for: trackType)
        let isSelected = selection.contains(id)
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
            if NSEvent.modifierFlags.contains(.shift) {
                onSegmentToggleSelect?(trackType, id)
            } else {
                onSegmentSelect?(trackType, id)
            }
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
    func segmentHandleView(
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

}
