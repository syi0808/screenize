import SwiftUI

/// Time ruler at the top of the timeline
struct TimeRulerView: View {

    // MARK: - Properties

    /// Total duration (seconds)
    let duration: TimeInterval

    /// Current time (seconds)
    let currentTime: TimeInterval

    /// Seconds per pixel (zoom level)
    let pixelsPerSecond: CGFloat

    /// Scroll offset
    let scrollOffset: CGFloat

    /// Callback for time taps
    var onTimeTap: ((TimeInterval) -> Void)?

    // MARK: - Constants

    private let rulerHeight: CGFloat = 24
    private let majorTickHeight: CGFloat = 12
    private let minorTickHeight: CGFloat = 6

    // MARK: - Body

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                // Background
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor))

                // Ticks
                Canvas { context, size in
                    drawRuler(context: context, size: size)
                }

                // Current time marker
                currentTimeMarker
            }
        }
        .frame(height: rulerHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let time = timeFromPosition(value.location.x)
                    onTimeTap?(time)
                }
        )
    }

    // MARK: - Subviews

    private var currentTimeMarker: some View {
        let xPosition = positionFromTime(currentTime) - scrollOffset

        return Triangle()
            .fill(Color.accentColor)
            .frame(width: 10, height: 8)
            .offset(x: xPosition - 5, y: rulerHeight - 8)
    }

    // MARK: - Drawing

    private func drawRuler(context: GraphicsContext, size: CGSize) {
        let visibleStartTime = scrollOffset / pixelsPerSecond
        let visibleEndTime = (scrollOffset + size.width) / pixelsPerSecond

        // Calculate appropriate tick intervals
        let (majorInterval, minorInterval) = calculateTickIntervals()

        // Minor ticks
        var time = floor(visibleStartTime / minorInterval) * minorInterval
        while time <= visibleEndTime {
            let x = positionFromTime(time) - scrollOffset

            if x >= 0 && x <= size.width {
                let isMajor = time.truncatingRemainder(dividingBy: majorInterval) < 0.001

                if !isMajor {
                    let tickPath = Path { path in
                        path.move(to: CGPoint(x: x, y: rulerHeight - minorTickHeight))
                        path.addLine(to: CGPoint(x: x, y: rulerHeight))
                    }
                    context.stroke(tickPath, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                }
            }

            time += minorInterval
        }

        // Major ticks with labels
        time = floor(visibleStartTime / majorInterval) * majorInterval
        while time <= visibleEndTime {
            let x = positionFromTime(time) - scrollOffset

            if x >= 0 && x <= size.width {
                // Major tick
                let tickPath = Path { path in
                    path.move(to: CGPoint(x: x, y: rulerHeight - majorTickHeight))
                    path.addLine(to: CGPoint(x: x, y: rulerHeight))
                }
                context.stroke(tickPath, with: .color(.secondary), lineWidth: 1)

                // Time label
                let label = formatTime(time)
                let text = Text(label)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                context.draw(text, at: CGPoint(x: x + 3, y: 6), anchor: .leading)
            }

            time += majorInterval
        }
    }

    // MARK: - Helpers

    /// Determine suitable tick intervals
    private func calculateTickIntervals() -> (major: TimeInterval, minor: TimeInterval) {
        // Choose intervals based on seconds per pixel
        let secondsPerPixel = 1.0 / Double(pixelsPerSecond)

        // Ensure major ticks are at least 50 pixels apart
        let minMajorInterval = secondsPerPixel * 50

        let intervals: [(major: TimeInterval, minor: TimeInterval)] = [
            (0.1, 0.02),    // 100ms / 20ms
            (0.5, 0.1),     // 500ms / 100ms
            (1.0, 0.2),     // 1s / 200ms
            (2.0, 0.5),     // 2s / 500ms
            (5.0, 1.0),     // 5s / 1s
            (10.0, 2.0),    // 10s / 2s
            (30.0, 5.0),    // 30s / 5s
            (60.0, 10.0),   // 1m / 10s
            (300.0, 60.0),  // 5m / 1m
        ]

        for interval in intervals {
            if interval.major >= minMajorInterval {
                return interval
            }
        }

        return intervals.last!
    }

    /// Convert time to an X position
    private func positionFromTime(_ time: TimeInterval) -> CGFloat {
        CGFloat(time) * pixelsPerSecond
    }

    /// Convert an X position to time
    private func timeFromPosition(_ x: CGFloat) -> TimeInterval {
        max(0, min(duration, Double(x + scrollOffset) / Double(pixelsPerSecond)))
    }

    /// Format the time string
    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let milliseconds = Int((time - Double(totalSeconds)) * 10)

        if duration >= 60 {
            return String(format: "%d:%02d.%d", minutes, seconds, milliseconds)
        } else {
            return String(format: "%d.%d", seconds, milliseconds)
        }
    }
}

// MARK: - Triangle Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        TimeRulerView(
            duration: 30,
            currentTime: 5.5,
            pixelsPerSecond: 50,
            scrollOffset: 0
        )

        Divider()

        TimeRulerView(
            duration: 120,
            currentTime: 45,
            pixelsPerSecond: 20,
            scrollOffset: 0
        )
    }
    .frame(width: 600)
    .padding()
}
