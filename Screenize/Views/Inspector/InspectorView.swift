import SwiftUI

enum InspectorTab: String, CaseIterable {
    case settings = "Settings"
    case segment = "Segment"
}

/// Segment inspector view.
struct InspectorView: View {

    @Binding var timeline: Timeline
    @Binding var selectedSegmentID: UUID?
    @Binding var selectedSegmentTrackType: TrackType?
    @Binding var renderSettings: RenderSettings
    var isWindowMode: Bool
    var onSegmentChange: (() -> Void)?
    var onDeleteSegment: ((UUID, TrackType) -> Void)?

    @State private var selectedTab: InspectorTab = .segment

    var body: some View {
        VStack(spacing: 0) {
            if isWindowMode {
                Picker("Inspector Tab", selection: $selectedTab) {
                    ForEach(InspectorTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()
            }

            if isWindowMode && selectedTab == .settings {
                ScrollView {
                    SettingsInspector(settings: $renderSettings, timeline: $timeline, onChange: onSegmentChange)
                }
            } else {
                segmentInspector
            }
        }
        .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var segmentInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Segment")
                    .font(.headline)

                if let id = selectedSegmentID, let trackType = selectedSegmentTrackType {
                    LabeledContent("Track") { Text(trackName(trackType)) }

                    switch trackType {
                    case .transform:
                        cameraSection(segmentID: id)
                    case .cursor:
                        cursorSection(segmentID: id)
                    case .keystroke:
                        keystrokeSection(segmentID: id)
                    case .audio:
                        EmptyView()
                    }

                    Divider()

                    Button(role: .destructive) {
                        onDeleteSegment?(id, trackType)
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Segment")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No Selection")
                            .foregroundStyle(.secondary)
                        Text("Select a segment on the timeline to inspect it.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func cameraSection(segmentID: UUID) -> some View {
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

    private func zoomControl(
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

    private func positionControl(
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

    @ViewBuilder
    private func cursorSection(segmentID: UUID) -> some View {
        if let binding = cursorSegmentBinding(for: segmentID) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cursor")
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

                Picker("Style", selection: Binding(
                    get: { binding.wrappedValue.style },
                    set: { binding.wrappedValue.style = $0 }
                )) {
                    ForEach(CursorStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                Toggle("Visible", isOn: Binding(
                    get: { binding.wrappedValue.visible },
                    set: { binding.wrappedValue.visible = $0 }
                ))

                LabeledContent("Scale") {
                    Slider(value: Binding(
                        get: { Double(binding.wrappedValue.scale) },
                        set: { binding.wrappedValue.scale = CGFloat($0) }
                    ), in: 0.5...5)
                }
            }
        } else {
            Text("Cursor segment not found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func keystrokeSection(segmentID: UUID) -> some View {
        if let binding = keystrokeSegmentBinding(for: segmentID) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Keystroke")
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

                TextField("Display Text", text: Binding(
                    get: { binding.wrappedValue.displayText },
                    set: { binding.wrappedValue.displayText = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                LabeledContent("Fade In") {
                    Slider(value: Binding(
                        get: { binding.wrappedValue.fadeInDuration },
                        set: { binding.wrappedValue.fadeInDuration = $0 }
                    ), in: 0...1)
                }

                LabeledContent("Fade Out") {
                    Slider(value: Binding(
                        get: { binding.wrappedValue.fadeOutDuration },
                        set: { binding.wrappedValue.fadeOutDuration = $0 }
                    ), in: 0...1.5)
                }
            }
        } else {
            Text("Keystroke segment not found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func timeRangeFields(start: Binding<TimeInterval>, end: Binding<TimeInterval>) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("0.0", value: start, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("End")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("0.0", value: end, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

}

// MARK: - Segment Bindings

extension InspectorView {

    func cameraSegmentBinding(for id: UUID) -> Binding<CameraSegment>? {
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .transform }),
              case .camera(let track) = timeline.tracks[trackIndex],
              track.segments.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                if case .camera(let track) = self.timeline.tracks[trackIndex],
                   let segmentIndex = track.segments.firstIndex(where: { $0.id == id }) {
                    return track.segments[segmentIndex]
                }

                return CameraSegment(startTime: 0, endTime: 1, startTransform: .identity, endTransform: .identity)
            },
            set: { updated in
                if case .camera(var track) = self.timeline.tracks[trackIndex],
                   track.updateSegment(updated) {
                    self.timeline.tracks[trackIndex] = .camera(track)
                    self.onSegmentChange?()
                }
            }
        )
    }

    func cursorSegmentBinding(for id: UUID) -> Binding<CursorSegment>? {
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .cursor }),
              case .cursor(let track) = timeline.tracks[trackIndex],
              track.segments.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                if case .cursor(let track) = self.timeline.tracks[trackIndex],
                   let segmentIndex = track.segments.firstIndex(where: { $0.id == id }) {
                    return track.segments[segmentIndex]
                }

                return CursorSegment(startTime: 0, endTime: 1)
            },
            set: { updated in
                if case .cursor(var track) = self.timeline.tracks[trackIndex],
                   track.updateSegment(updated) {
                    self.timeline.tracks[trackIndex] = .cursor(track)
                    self.onSegmentChange?()
                }
            }
        )
    }

    func keystrokeSegmentBinding(for id: UUID) -> Binding<KeystrokeSegment>? {
        guard let trackIndex = timeline.tracks.firstIndex(where: { $0.trackType == .keystroke }),
              case .keystroke(let track) = timeline.tracks[trackIndex],
              track.segments.contains(where: { $0.id == id }) else {
            return nil
        }

        return Binding(
            get: {
                if case .keystroke(let track) = self.timeline.tracks[trackIndex],
                   let segmentIndex = track.segments.firstIndex(where: { $0.id == id }) {
                    return track.segments[segmentIndex]
                }

                return KeystrokeSegment(startTime: 0, endTime: 1, displayText: "")
            },
            set: { updated in
                if case .keystroke(var track) = self.timeline.tracks[trackIndex],
                   track.updateSegment(updated) {
                    self.timeline.tracks[trackIndex] = .keystroke(track)
                    self.onSegmentChange?()
                }
            }
        )
    }

    func trackName(_ trackType: TrackType) -> String {
        switch trackType {
        case .transform:
            return "Camera"
        case .cursor:
            return "Cursor"
        case .keystroke:
            return "Keystroke"
        case .audio:
            return "Audio"
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
