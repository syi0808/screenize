import SwiftUI

/// Smart generator panel with per-type selection
struct GeneratorPanelView: View {

    @ObservedObject var viewModel: EditorViewModel

    @State private var isGenerating: Bool = false
    @State private var generationResult: String?
    @State private var selectedTypes: Set<TrackType> = [
        .transform, .cursor, .keystroke
    ]

    private struct GeneratorOption: Identifiable {
        let type: TrackType
        let name: String
        let description: String
        let icon: String
        var id: TrackType { type }
    }

    private let generatorOptions: [GeneratorOption] = [
        GeneratorOption(
            type: .transform,
            name: "Smart Zoom",
            description: "Auto-focus and zoom on activity",
            icon: "sparkle.magnifyingglass"
        ),
        GeneratorOption(
            type: .cursor,
            name: "Cursor Style",
            description: "Cursor movement based on clicks",
            icon: "cursorarrow.motionlines"
        ),
        GeneratorOption(
            type: .keystroke,
            name: "Keystroke",
            description: "Keyboard shortcut overlays",
            icon: "keyboard"
        )
    ]

    private var allSelected: Bool {
        selectedTypes.count == generatorOptions.count
    }

    private var buttonLabel: String {
        if isGenerating { return "Generating..." }
        if allSelected { return "Generate All Segments" }
        return "Generate Selected (\(selectedTypes.count))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            SectionHeader(title: "Smart Generation", icon: "wand.and.stars")

            // Method picker
            Picker("Method", selection: $viewModel.cameraGenerationMethod) {
                ForEach(CameraGenerationMethod.allCases, id: \.self) {
                    Text($0.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            // Per-type toggles
            VStack(alignment: .leading, spacing: Spacing.xl - Spacing.sm) {
                ForEach(generatorOptions) { option in
                    Toggle(isOn: toggleBinding(for: option.type)) {
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Label(option.name, systemImage: option.icon)
                                .font(Typography.subheading)
                            Text(option.description)
                                .font(Typography.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(isGenerating)
                }
            }

            Divider()

            // Generation result
            if let result = generationResult {
                Text(result)
                    .font(Typography.caption)
                    .foregroundColor(
                        result.hasPrefix("Failed") ? DesignColors.destructive : DesignColors.success
                    )
                    .padding(.vertical, Spacing.xs)
            }

            // Generation button
            Button {
                Task { await generateKeyframes() }
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(buttonLabel)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || selectedTypes.isEmpty)

            // Helper text
            Text("Selected types replace existing keyframes. Unselected types are preserved.")
                .font(Typography.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(Spacing.xl)
        .frame(width: 320)
    }

    private func toggleBinding(for type: TrackType) -> Binding<Bool> {
        Binding(
            get: { selectedTypes.contains(type) },
            set: { isOn in
                if isOn {
                    selectedTypes.insert(type)
                } else {
                    selectedTypes.remove(type)
                }
            }
        )
    }

    @MainActor
    private func generateKeyframes() async {
        guard !isGenerating, !selectedTypes.isEmpty else { return }

        isGenerating = true
        generationResult = nil

        await viewModel.runSmartGeneration(for: selectedTypes)

        if let error = viewModel.errorMessage {
            generationResult = "Failed: \(error)"
        } else {
            let parts = generatorOptions.compactMap { option -> String? in
                guard selectedTypes.contains(option.type) else { return nil }
                let count: Int
                switch option.type {
                case .transform:
                    count = viewModel.project.timeline.cameraTrack?.segments.count ?? 0
                case .cursor:
                    count = viewModel.project.timeline.cursorTrackV2?.segments.count ?? 0
                case .keystroke:
                    count = viewModel.project.timeline.keystrokeTrackV2?.segments.count ?? 0
                case .audio:
                    return nil
                }
                return "\(count) \(option.name.lowercased())"
            }
            generationResult = parts.joined(separator: ", ")
        }

        isGenerating = false
    }
}

// MARK: - Preview

#Preview {
    EditorMainView(
        project: ScreenizeProject(
            name: "Test Project",
            media: MediaAsset(
                videoRelativePath: "recording/recording.mp4",
                mouseDataRelativePath: "recording/recording.mouse.json",
                packageRootURL: URL(fileURLWithPath: "/test.screenize"),
                pixelSize: CGSize(width: 1920, height: 1080),
                frameRate: 60,
                duration: 30
            ),
            captureMeta: CaptureMeta(
                boundsPt: CGRect(x: 0, y: 0, width: 960, height: 540),
                scaleFactor: 2.0
            ),
            timeline: Timeline(
                tracks: [
                    AnySegmentTrack.camera(CameraTrack(
                        id: UUID(),
                        name: "Camera",
                        isEnabled: true,
                        segments: [
                            CameraSegment(startTime: 0, endTime: 5, startTransform: .identity, endTransform: .identity),
                        ]
                    )),
                    AnySegmentTrack.cursor(CursorTrackV2(
                        id: UUID(),
                        name: "Cursor",
                        isEnabled: true,
                        segments: [
                            CursorSegment(startTime: 0, endTime: 30),
                        ]
                    )),
                ],
                duration: 30
            ),
            renderSettings: RenderSettings()
        )
    )
}
