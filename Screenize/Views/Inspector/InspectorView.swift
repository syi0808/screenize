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
                    LabeledContent("ID") {
                        Text(id.uuidString.prefix(8))
                            .font(.system(.caption, design: .monospaced))
                    }

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

                LabeledContent("Start Zoom") {
                    Slider(value: Binding(
                        get: { Double(binding.wrappedValue.startTransform.zoom) },
                        set: { binding.wrappedValue.startTransform = TransformValue(zoom: CGFloat($0), center: binding.wrappedValue.startTransform.center) }
                    ), in: 1...5)
                }

                LabeledContent("End Zoom") {
                    Slider(value: Binding(
                        get: { Double(binding.wrappedValue.endTransform.zoom) },
                        set: { binding.wrappedValue.endTransform = TransformValue(zoom: CGFloat($0), center: binding.wrappedValue.endTransform.center) }
                    ), in: 1...5)
                }
            }
        } else {
            Text("Camera segment not found")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func cameraSegmentBinding(for id: UUID) -> Binding<CameraSegment>? {
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

    private func cursorSegmentBinding(for id: UUID) -> Binding<CursorSegment>? {
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

    private func keystrokeSegmentBinding(for id: UUID) -> Binding<KeystrokeSegment>? {
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

    private func trackName(_ trackType: TrackType) -> String {
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
