import SwiftUI

/// Keyframe marker view
struct KeyframeMarkerView: View {

    // MARK: - Properties

    /// Keyframe ID
    let id: UUID

    /// Keyframe time
    let time: TimeInterval

    /// Whether the marker is selected
    let isSelected: Bool

    /// Marker color
    let color: Color

    /// Marker size
    var size: CGFloat = 12

    /// Selection callback
    var onSelect: (() -> Void)?

    /// Time change callback (drag)
    var onTimeChange: ((TimeInterval) -> Void)?

    // MARK: - State

    @State private var isHovering = false

    // MARK: - Body

    var body: some View {
        Diamond()
            .fill(markerColor)
            .frame(width: size, height: size)
            .overlay(
                Diamond()
                    .stroke(strokeColor, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? color.opacity(0.5) : .clear, radius: 4)
            .scaleEffect(isHovering || isSelected ? 1.2 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .onHover { hovering in
                isHovering = hovering
            }
            .onTapGesture {
                onSelect?()
            }
            .help("Time: \(String(format: "%.2f", time))s")
    }

    // MARK: - Computed Properties

    private var markerColor: Color {
        if isSelected {
            return color
        } else if isHovering {
            return color.opacity(0.9)
        } else {
            return color.opacity(0.7)
        }
    }

    private var strokeColor: Color {
        isSelected ? .white : color.opacity(0.3)
    }
}

// MARK: - Diamond Shape

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Draggable Keyframe Marker

/// Draggable keyframe marker
struct DraggableKeyframeMarker: View {

    // MARK: - Properties

    let id: UUID
    let time: TimeInterval
    let isSelected: Bool
    let color: Color
    let pixelsPerSecond: CGFloat
    let scrollOffset: CGFloat
    let duration: TimeInterval

    var onSelect: (() -> Void)?
    var onTimeChange: ((TimeInterval) -> Void)?
    var onDragEnd: (() -> Void)?

    // MARK: - State

    @State private var isDragging = false
    @State private var dragTime: TimeInterval = 0

    // MARK: - Body

    var body: some View {
        KeyframeMarkerView(
            id: id,
            time: displayTime,
            isSelected: isSelected || isDragging,
            color: color,
            onSelect: onSelect
        )
        .gesture(dragGesture)
    }

    // MARK: - Computed Properties

    private var displayTime: TimeInterval {
        isDragging ? dragTime : time
    }

    // MARK: - Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("trackContent"))
            .onChanged { value in
                isDragging = true
                let newTime = timeFromPosition(value.location.x)
                dragTime = newTime
                onTimeChange?(newTime)
            }
            .onEnded { _ in
                isDragging = false
                onDragEnd?()
            }
    }

    // MARK: - Helpers

    private func timeFromPosition(_ x: CGFloat) -> TimeInterval {
        let adjustedX = x + scrollOffset
        return max(0, min(duration, Double(adjustedX) / Double(pixelsPerSecond)))
    }
}

// MARK: - Keyframe Range Selection

/// Highlight a range between two keyframes
struct KeyframeRangeView: View {

    let startTime: TimeInterval
    let endTime: TimeInterval
    let pixelsPerSecond: CGFloat
    let scrollOffset: CGFloat
    let color: Color
    let height: CGFloat

    var body: some View {
        let startX = CGFloat(startTime) * pixelsPerSecond - scrollOffset
        let endX = CGFloat(endTime) * pixelsPerSecond - scrollOffset
        let width = endX - startX

        Rectangle()
            .fill(color.opacity(0.15))
            .frame(width: max(0, width), height: height)
            .offset(x: startX)
    }
}

// MARK: - Track Keyframe Colors

/// Keyframe colors by track type
enum KeyframeColor {
    static let transform = Color.blue
    static let ripple = Color.purple
    static let cursor = Color.orange
    static let keystroke = Color.cyan

    static func color(for trackType: TrackType) -> Color {
        switch trackType {
        case .transform:
            return transform
        case .ripple:
            return ripple
        case .cursor:
            return cursor
        case .keystroke:
            return keystroke
        case .audio:
            return Color.green  // Reserved for future audio track support
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Default markers
        HStack(spacing: 20) {
            KeyframeMarkerView(
                id: UUID(),
                time: 0,
                isSelected: false,
                color: KeyframeColor.transform
            )

            KeyframeMarkerView(
                id: UUID(),
                time: 1,
                isSelected: true,
                color: KeyframeColor.transform
            )

            KeyframeMarkerView(
                id: UUID(),
                time: 2,
                isSelected: false,
                color: KeyframeColor.ripple
            )

            KeyframeMarkerView(
                id: UUID(),
                time: 3,
                isSelected: false,
                color: KeyframeColor.cursor
            )
        }

        Divider()

        // Draggable marker demo
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 40)

            DraggableKeyframeMarker(
                id: UUID(),
                time: 2.0,
                isSelected: false,
                color: KeyframeColor.transform,
                pixelsPerSecond: 50,
                scrollOffset: 0,
                duration: 10
            )
            .offset(y: 0)
        }
        .frame(width: 500, height: 40)
    }
    .padding()
}
