import SwiftUI

enum InspectorTab: String, CaseIterable {
    case settings = "Settings"
    case segment = "Segment"
}

/// Segment inspector view.
struct InspectorView: View {

    @Binding var timeline: Timeline
    @Binding var selection: SegmentSelection
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
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

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
        .background(DesignColors.windowBackground)
    }

    private var segmentInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Segment")
                    .font(Typography.heading)

                if let selected = selection.single {
                    LabeledContent("Track") { Text(trackName(selected.trackType)) }

                    switch selected.trackType {
                    case .transform:
                        cameraSection(segmentID: selected.id)
                    case .cursor:
                        cursorSection(segmentID: selected.id)
                    case .keystroke:
                        keystrokeSection(segmentID: selected.id)
                    case .audio:
                        audioSection(segmentID: selected.id)
                    }

                    Divider()

                    Button(role: .destructive) {
                        onDeleteSegment?(selected.id, selected.trackType)
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Segment")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else if selection.count > 1 {
                    DesignEmptyState(
                        icon: "rectangle.stack",
                        title: "\(selection.count) Segments Selected"
                    )
                    .padding(.top, Spacing.xxxl - Spacing.sm)

                    Divider()

                    Button(role: .destructive) {
                        let selected = selection.segments
                        for ident in selected {
                            onDeleteSegment?(ident.id, ident.trackType)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete \(selection.count) Segments")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    DesignEmptyState(
                        icon: "sidebar.right",
                        title: "No Selection",
                        subtitle: "Select a segment on the timeline to inspect it."
                    )
                    .padding(.top, Spacing.xxxl - Spacing.sm)
                }
            }
            .padding(Spacing.md)
        }
    }

    // MARK: - Cursor Section

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

    // MARK: - Keystroke Section

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

    // MARK: - Audio Section

    @ViewBuilder
    private func audioSection(segmentID: UUID) -> some View {
        if let binding = audioSegmentBinding(for: segmentID) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio")
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

                LabeledContent("Volume") {
                    HStack(spacing: 8) {
                        Slider(value: Binding(
                            get: { Double(binding.wrappedValue.volume) },
                            set: { binding.wrappedValue.volume = Float($0) }
                        ), in: 0...1)
                        Text("\(Int(binding.wrappedValue.volume * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                Toggle("Muted", isOn: Binding(
                    get: { binding.wrappedValue.isMuted },
                    set: { binding.wrappedValue.isMuted = $0 }
                ))
            }
        } else {
            Text("Audio segment not found")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Shared Helpers

    func timeRangeFields(start: Binding<TimeInterval>, end: Binding<TimeInterval>) -> some View {
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
