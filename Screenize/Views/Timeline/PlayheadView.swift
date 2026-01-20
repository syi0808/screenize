import SwiftUI

/// Timeline playhead (current time indicator)
struct PlayheadView: View {

    // MARK: - Properties

    /// Current time (seconds)
    let currentTime: TimeInterval

    /// Pixels per second
    let pixelsPerSecond: CGFloat

    /// Scroll offset
    let scrollOffset: CGFloat

    /// Timeline height
    let timelineHeight: CGFloat

    /// Indicates whether dragging is active
    @Binding var isDragging: Bool

    /// Callback invoked when time changes
    var onTimeChange: ((TimeInterval) -> Void)?

    // MARK: - Constants

    private let headWidth: CGFloat = 12
    private let headHeight: CGFloat = 16
    private let lineWidth: CGFloat = 1.5

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let xPosition = positionFromTime(currentTime) - scrollOffset

            // Only show when within the visible range
            if xPosition >= -headWidth && xPosition <= geometry.size.width + headWidth {
                ZStack(alignment: .top) {
                    // Vertical line
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: lineWidth)
                        .offset(x: xPosition - lineWidth / 2)

                    // Playhead (triangle + rectangle)
                    PlayheadHead(isDragging: isDragging)
                        .fill(Color.accentColor)
                        .frame(width: headWidth, height: headHeight)
                        .offset(x: xPosition - headWidth / 2)
                        .gesture(dragGesture(in: geometry))
                }
            }
        }
        .frame(height: timelineHeight)
    }

    // MARK: - Gesture

    private func dragGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                let time = timeFromPosition(value.location.x, in: geometry)
                onTimeChange?(time)
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    // MARK: - Helpers

    private func positionFromTime(_ time: TimeInterval) -> CGFloat {
        CGFloat(time) * pixelsPerSecond
    }

    private func timeFromPosition(_ x: CGFloat, in geometry: GeometryProxy) -> TimeInterval {
        let adjustedX = x + scrollOffset
        return max(0, Double(adjustedX) / Double(pixelsPerSecond))
    }
}

// MARK: - PlayheadHead Shape

private struct PlayheadHead: Shape {

    let isDragging: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let cornerRadius: CGFloat = 2
        let triangleHeight: CGFloat = 6

        // Rounded rectangle at the top
        let rectHeight = rect.height - triangleHeight
        let roundedRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rectHeight)

        path.addRoundedRect(in: roundedRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))

        // Triangle at the bottom
        path.move(to: CGPoint(x: rect.minX, y: rectHeight))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rectHeight))
        path.closeSubpath()

        return path
    }
}

// MARK: - Standalone Playhead Line (for overlay)

/// Render only the playhead line (for track area overlays)
struct PlayheadLine: View {

    let currentTime: TimeInterval
    let pixelsPerSecond: CGFloat
    let scrollOffset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let xPosition = positionFromTime(currentTime) - scrollOffset

            if xPosition >= 0 && xPosition <= geometry.size.width {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 1.5)
                    .offset(x: xPosition - 0.75)
            }
        }
    }

    private func positionFromTime(_ time: TimeInterval) -> CGFloat {
        CGFloat(time) * pixelsPerSecond
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var currentTime: TimeInterval = 5.0
        @State private var isDragging = false

        var body: some View {
            VStack {
                Text("Current Time: \(String(format: "%.2f", currentTime))s")
                    .font(.headline)

                ZStack {
                    // Background
                    Color(nsColor: .controlBackgroundColor)

                    // Faked tracks
                    VStack(spacing: 0) {
                        ForEach(0..<3) { _ in
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 40)
                            Divider()
                        }
                    }

                    // Playhead
                    PlayheadView(
                        currentTime: currentTime,
                        pixelsPerSecond: 50,
                        scrollOffset: 0,
                        timelineHeight: 130,
                        isDragging: $isDragging,
                        onTimeChange: { time in
                            currentTime = time
                        }
                    )
                }
                .frame(width: 600, height: 130)
                .border(Color.gray)
            }
            .padding()
        }
    }

    return PreviewWrapper()
}
