import SwiftUI

/// Transform keyframe inspector
struct TransformInspector: View {

    // MARK: - Properties

    /// The keyframe being edited
    @Binding var keyframe: TransformKeyframe

    /// Maximum zoom level
    var maxZoom: CGFloat = 5.0

    /// Change callback
    var onChange: (() -> Void)?

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            header

            Divider()

            // Time
            timeSection

            Divider()

            // Zoom
            zoomSection

            Divider()

            // Center
            centerSection

            Divider()

            // Easing
            easingSection

            Spacer()
        }
        .padding(12)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .foregroundColor(TrackColor.transform)

            Text("Transform Keyframe")
                .font(.headline)

            Spacer()
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            HStack {
                TextField("", value: $keyframe.time, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit { onChange?() }

                Text("s")
                    .foregroundColor(.secondary)

                Spacer()

                // Button to jump to the current frame (implemented externally)
            }
        }
    }

    private var zoomSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Zoom")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(Int(keyframe.zoom * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                // Slider
                Slider(value: $keyframe.zoom, in: 1.0...maxZoom, step: 0.1)

                // Manual entry
                TextField("", value: Binding(
                    get: { Double(keyframe.zoom) },
                    set: { keyframe.zoom = CGFloat($0); onChange?() }
                ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
            }

            // Preset button
            HStack(spacing: 8) {
                ForEach([1.0, 1.5, 2.0, 3.0], id: \.self) { zoom in
                    Button("\(Int(zoom * 100))%") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            keyframe.zoom = zoom
                        }
                        onChange?()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var centerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Center Position")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            // Visual center picker
            CenterPointPicker(
                centerX: $keyframe.centerX,
                centerY: $keyframe.centerY,
                onChange: onChange
            )
            .frame(height: 120)

            // Numeric input
            VStack(spacing: 8) {
                HStack {
                    Text("X")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Slider(value: $keyframe.centerX, in: 0...1)

                    TextField("", value: Binding(
                        get: { Double(keyframe.centerX) },
                        set: { keyframe.centerX = CGFloat($0); onChange?() }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }

                HStack {
                    Text("Y")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Slider(value: $keyframe.centerY, in: 0...1)

                    TextField("", value: Binding(
                        get: { Double(keyframe.centerY) },
                        set: { keyframe.centerY = CGFloat($0); onChange?() }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                }
            }

            // Reset center button
            Button("Reset to Center") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    keyframe.centerX = 0.5
                    keyframe.centerY = 0.5
                }
                onChange?()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var easingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            EasingPicker(easing: Binding(
                get: { keyframe.easing },
                set: { keyframe.easing = $0; onChange?() }
            ))

            LargeEasingCurvePreview(curve: keyframe.easing)
        }
    }
}

// MARK: - Center Point Picker

/// Visual center picker
struct CenterPointPicker: View {

    @Binding var centerX: CGFloat
    @Binding var centerY: CGFloat

    var onChange: (() -> Void)?

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
        // Background (indicates the viewport ratio)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )

        // Grid
                gridLines(in: size)

        // Crosshairs
                crosshair(in: size)

        // Display the center point
                centerPoint(in: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        updateCenter(from: value.location, in: size)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
    }

    private func gridLines(in size: CGSize) -> some View {
        Canvas { context, _ in
            let lineColor = Color.secondary.opacity(0.2)

            // 3x3 grid
            for i in 1..<3 {
                // Vertical lines
                let x = size.width * CGFloat(i) / 3
                let vPath = Path { path in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(vPath, with: .color(lineColor), lineWidth: 0.5)

                // Horizontal lines
                let y = size.height * CGFloat(i) / 3
                let hPath = Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(hPath, with: .color(lineColor), lineWidth: 0.5)
            }
        }
    }

    private func crosshair(in size: CGSize) -> some View {
        let x = centerX * size.width
        // Flip Y axis: convert from CoreImage bottom-left to SwiftUI top-left
        let y = (1 - centerY) * size.height

        return ZStack {
            // Vertical line
            Rectangle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: 1)
                .offset(x: x - size.width / 2)

            // Horizontal line
            Rectangle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(height: 1)
                .offset(y: y - size.height / 2)
        }
    }

    private func centerPoint(in size: CGSize) -> some View {
        let x = centerX * size.width
        // Flip Y axis: convert from CoreImage bottom-left to SwiftUI top-left
        let y = (1 - centerY) * size.height

        return Circle()
            .fill(Color.accentColor)
            .frame(width: isDragging ? 16 : 12, height: isDragging ? 16 : 12)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.3), radius: 2)
            .position(x: x, y: y)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
    }

    private func updateCenter(from location: CGPoint, in size: CGSize) {
        let newX = max(0, min(1, location.x / size.width))
        // Flip Y axis: convert from SwiftUI top-left to CoreImage bottom-left
        let newY = max(0, min(1, 1 - (location.y / size.height)))

        centerX = newX
        centerY = newY
        onChange?()
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var keyframe = TransformKeyframe(
            time: 2.5,
            zoom: 2.0,
            centerX: 0.3,
            centerY: 0.4,
            easing: .easeOut
        )

        var body: some View {
            TransformInspector(keyframe: $keyframe) {
                print("Changed: zoom=\(keyframe.zoom), center=(\(keyframe.centerX), \(keyframe.centerY))")
            }
            .frame(width: 280)
        }
    }

    return PreviewWrapper()
}
