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

                if binding.wrappedValue.isContinuous {
                    Label(
                        "Continuous segment has no configurable options.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                } else {
                    manualCameraControls(segment: binding)
                }
            }
        } else {
            Text("Camera segment not found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func cameraTrack() -> CameraTrack? {
        for track in timeline.tracks {
            if case .camera(let cameraTrack) = track {
                return cameraTrack
            }
        }
        return nil
    }

    @ViewBuilder
    private func manualCameraControls(segment: Binding<CameraSegment>) -> some View {
        if case .manual = segment.wrappedValue.kind {
            zoomControl(label: "Start Zoom", segment: segment, isStart: true)
            zoomControl(label: "End Zoom", segment: segment, isStart: false)
            Divider()
            positionControl(label: "Start Position", segment: segment, isStart: true)

            copyFromPreviousButton(segment: segment)

            positionControl(label: "End Position", segment: segment, isStart: false)

            copyFromNextButton(segment: segment)
        }
    }

    @ViewBuilder
    private func copyFromPreviousButton(segment: Binding<CameraSegment>) -> some View {
        let prevTransform: TransformValue? = {
            guard let track = cameraTrack(),
                  let prevSegment = track.previousManualSegment(before: segment.wrappedValue.id),
                  case .manual(_, let endTransform) = prevSegment.kind else { return nil }
            return endTransform
        }()

        Button {
            if let transform = prevTransform {
                var updated = segment.wrappedValue
                if case .manual(_, let currentEnd) = updated.kind {
                    updated.kind = .manual(startTransform: transform, endTransform: currentEnd)
                    segment.wrappedValue = updated
                }
            }
        } label: {
            Label("Copy from Previous", systemImage: "arrow.left")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .disabled(prevTransform == nil)
    }

    @ViewBuilder
    private func copyFromNextButton(segment: Binding<CameraSegment>) -> some View {
        let nextTransform: TransformValue? = {
            guard let track = cameraTrack(),
                  let nextSegment = track.nextManualSegment(after: segment.wrappedValue.id),
                  case .manual(let startTransform, _) = nextSegment.kind else { return nil }
            return startTransform
        }()

        Button {
            if let transform = nextTransform {
                var updated = segment.wrappedValue
                if case .manual(let currentStart, _) = updated.kind {
                    updated.kind = .manual(startTransform: currentStart, endTransform: transform)
                    segment.wrappedValue = updated
                }
            }
        } label: {
            Label("Copy from Next", systemImage: "arrow.right")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .disabled(nextTransform == nil)
    }

    func zoomControl(
        label: String,
        segment: Binding<CameraSegment>,
        isStart: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let currentZoom = extractTransform(from: segment.wrappedValue, isStart: isStart).zoom

            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(currentZoom * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(extractTransform(from: segment.wrappedValue, isStart: isStart).zoom) },
                    set: { newZoom in
                        updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                            TransformValue(zoom: CGFloat(newZoom), center: transform.center)
                        }
                    }
                ), in: 1...5, step: 0.1)
                TextField("", value: Binding(
                    get: { Double(extractTransform(from: segment.wrappedValue, isStart: isStart).zoom) },
                    set: { newZoom in
                        updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                            TransformValue(zoom: max(1, min(5, CGFloat(newZoom))), center: transform.center)
                        }
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
        isStart: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            CenterPointPicker(
                centerX: Binding(
                    get: { extractTransform(from: segment.wrappedValue, isStart: isStart).center.x },
                    set: { newX in
                        updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                            TransformValue(zoom: transform.zoom, center: NormalizedPoint(x: newX, y: transform.center.y))
                        }
                    }
                ),
                centerY: Binding(
                    get: { extractTransform(from: segment.wrappedValue, isStart: isStart).center.y },
                    set: { newY in
                        updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                            TransformValue(zoom: transform.zoom, center: NormalizedPoint(x: transform.center.x, y: newY))
                        }
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
                    get: { Double(extractTransform(from: segment.wrappedValue, isStart: isStart).center.x) },
                    set: { newX in
                        updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                            TransformValue(
                                zoom: transform.zoom,
                                center: NormalizedPoint(x: max(0, min(1, CGFloat(newX))), y: transform.center.y)
                            )
                        }
                        onSegmentChange?()
                    }
                ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                Text("Y")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
                TextField("", value: Binding(
                    get: { Double(extractTransform(from: segment.wrappedValue, isStart: isStart).center.y) },
                    set: { newY in
                        updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                            TransformValue(
                                zoom: transform.zoom,
                                center: NormalizedPoint(x: transform.center.x, y: max(0, min(1, CGFloat(newY))))
                            )
                        }
                        onSegmentChange?()
                    }
                ), format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Transform Helpers

    private func extractTransform(from segment: CameraSegment, isStart: Bool) -> TransformValue {
        guard case .manual(let startTransform, let endTransform) = segment.kind else {
            return .identity
        }
        return isStart ? startTransform : endTransform
    }

    private func updateTransform(
        in segment: inout CameraSegment,
        isStart: Bool,
        update: (TransformValue) -> TransformValue
    ) {
        guard case .manual(var startTransform, var endTransform) = segment.kind else {
            return
        }
        if isStart {
            startTransform = update(startTransform)
        } else {
            endTransform = update(endTransform)
        }
        segment.kind = .manual(
            startTransform: startTransform,
            endTransform: endTransform
        )
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
