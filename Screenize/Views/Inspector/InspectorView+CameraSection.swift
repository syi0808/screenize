import SwiftUI

// MARK: - Camera Section

extension InspectorView {

    @ViewBuilder
    func cameraSection(segmentID: UUID) -> some View {
        if let binding = cameraSegmentBinding(for: segmentID) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Camera")
                    .font(.subheadline.weight(.medium))

                timeRangeFields(
                    start: Binding(
                        get: { binding.wrappedValue.startTime },
                        set: { binding.wrappedValue.startTime = $0 }
                    ),
                    end: Binding(
                        get: { binding.wrappedValue.endTime },
                        set: { binding.wrappedValue.endTime = $0 }
                    )
                )

                // Start Zoom
                zoomControl(
                    label: "Start Zoom",
                    segment: binding,
                    keyPath: \.startTransform
                )

                // End Zoom
                zoomControl(
                    label: "End Zoom",
                    segment: binding,
                    keyPath: \.endTransform
                )

                Divider()

                // Start Position
                positionControl(
                    label: "Start Position",
                    segment: binding,
                    keyPath: \.startTransform
                )

                // End Position
                positionControl(
                    label: "End Position",
                    segment: binding,
                    keyPath: \.endTransform
                )
            }
        } else {
            Text("Camera segment not found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    func zoomControl(
        label: String,
        segment: Binding<CameraSegment>,
        keyPath: WritableKeyPath<CameraSegment, TransformValue>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(segment.wrappedValue[keyPath: keyPath].zoom * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(segment.wrappedValue[keyPath: keyPath].zoom) },
                    set: {
                        let current = segment.wrappedValue[keyPath: keyPath]
                        segment.wrappedValue[keyPath: keyPath] = TransformValue(
                            zoom: CGFloat($0), center: current.center
                        )
                    }
                ), in: 1...5, step: 0.1)
                TextField("", value: Binding(
                    get: { Double(segment.wrappedValue[keyPath: keyPath].zoom) },
                    set: {
                        let current = segment.wrappedValue[keyPath: keyPath]
                        segment.wrappedValue[keyPath: keyPath] = TransformValue(
                            zoom: max(1, min(5, CGFloat($0))), center: current.center
                        )
                    }
                ), format: .number.precision(.fractionLength(1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
            }
        }
    }

    func positionControl(
        label: String,
        segment: Binding<CameraSegment>,
        keyPath: WritableKeyPath<CameraSegment, TransformValue>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            CenterPointPicker(
                centerX: Binding(
                    get: { segment.wrappedValue[keyPath: keyPath].center.x },
                    set: { newX in
                        let current = segment.wrappedValue[keyPath: keyPath]
                        segment.wrappedValue[keyPath: keyPath] = TransformValue(
                            zoom: current.zoom,
                            center: NormalizedPoint(x: newX, y: current.center.y)
                        )
                    }
                ),
                centerY: Binding(
                    get: { segment.wrappedValue[keyPath: keyPath].center.y },
                    set: { newY in
                        let current = segment.wrappedValue[keyPath: keyPath]
                        segment.wrappedValue[keyPath: keyPath] = TransformValue(
                            zoom: current.zoom,
                            center: NormalizedPoint(x: current.center.x, y: newY)
                        )
                    }
                ),
                onChange: onSegmentChange
            )
            .frame(height: 100)

            HStack(spacing: 8) {
                Text("X")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                TextField("", value: Binding(
                    get: { Double(segment.wrappedValue[keyPath: keyPath].center.x) },
                    set: { newX in
                        let current = segment.wrappedValue[keyPath: keyPath]
                        segment.wrappedValue[keyPath: keyPath] = TransformValue(
                            zoom: current.zoom,
                            center: NormalizedPoint(
                                x: max(0, min(1, CGFloat(newX))),
                                y: current.center.y
                            )
                        )
                        onSegmentChange?()
                    }
                ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                Text("Y")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                TextField("", value: Binding(
                    get: { Double(segment.wrappedValue[keyPath: keyPath].center.y) },
                    set: { newY in
                        let current = segment.wrappedValue[keyPath: keyPath]
                        segment.wrappedValue[keyPath: keyPath] = TransformValue(
                            zoom: current.zoom,
                            center: NormalizedPoint(
                                x: current.center.x,
                                y: max(0, min(1, CGFloat(newY)))
                            )
                        )
                        onSegmentChange?()
                    }
                ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

// MARK: - Center Point Picker

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
            .motionSafeAnimation(AnimationTokens.quick, value: isDragging)
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
