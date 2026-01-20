import SwiftUI

/// Trim handle view
/// Allows dragging the trim start/end points on the timeline
struct TrimHandleView: View {
    /// Whether the handle represents the start or end point
    let isStart: Bool

    /// Whether the handle is currently being dragged
    @Binding var isDragging: Bool

    // MARK: - Constants

    private let handleWidth: CGFloat = 12
    private let handleColor = Color.yellow

    // MARK: - Body

    var body: some View {
        ZStack {
            // Vertical line
            Rectangle()
                .fill(handleColor)
                .frame(width: 2)

            // Handle grip (top and bottom)
            VStack {
                handleGrip
                Spacer()
                handleGrip
            }
        }
        .frame(width: handleWidth)
        .opacity(isDragging ? 1.0 : 0.8)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    // MARK: - Handle Grip

    private var handleGrip: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(handleColor)
            .frame(width: handleWidth, height: 20)
            .overlay(
                // Grip lines
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .frame(width: 6, height: 1)
                    }
                }
            )
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 100) {
        TrimHandleView(isStart: true, isDragging: .constant(false))
            .frame(height: 100)

        TrimHandleView(isStart: false, isDragging: .constant(true))
            .frame(height: 100)
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
