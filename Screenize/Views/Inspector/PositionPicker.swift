import SwiftUI

/// Position picker
struct PositionPicker: View {

    @Binding var x: CGFloat
    @Binding var y: CGFloat

    var color: Color = .orange
    var onChange: (() -> Void)?

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

                Circle()
                    .fill(color)
                    .frame(width: isDragging ? 20 : 16, height: isDragging ? 20 : 16)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: color.opacity(0.5), radius: isDragging ? 8 : 4)
                    .position(
                        x: x * size.width,
                        y: y * size.height
                    )
                    .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        x = max(0, min(1, value.location.x / size.width))
                        y = max(0, min(1, value.location.y / size.height))
                        onChange?()
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }
}
