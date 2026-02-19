import SwiftUI

/// Main editor view
struct EditorMainView: View {

    // MARK: - Properties

    /// View model
    @StateObject private var viewModel: EditorViewModel

    /// Show export sheet
    @State private var showExportSheet = false

    /// Show save confirmation alert (for Home navigation)
    @State private var showSaveConfirmation = false

    /// Show save confirmation alert (for New Recording)
    @State private var showNewRecordingConfirmation = false

    /// Show the Smart generator panel
    @State private var showGeneratorPanel = false

    /// Local event monitor for Delete/Backspace key
    @State private var deleteKeyMonitor: Any?

    // MARK: - Initialization

    init(project: ScreenizeProject, projectURL: URL? = nil) {
        self._viewModel = StateObject(wrappedValue: EditorViewModel(project: project, projectURL: projectURL))
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            // Left: preview + timeline
            VStack(spacing: 0) {
                // Toolbar
                toolbar

                Divider()

                // Preview
                PreviewView(
                    previewEngine: viewModel.previewEngine,
                    currentTime: $viewModel.currentTime,
                    isPlaying: viewModel.isPlaying,
                    onPlayPauseToggle: {
                        viewModel.togglePlayback()
                    },
                    onSeek: { time in
                        await viewModel.seek(to: time)
                    }
                )
                .frame(maxHeight: .infinity)
                .padding()

                Divider()

                // Timeline
                TimelineView(
                    timeline: viewModel.timelineBinding,
                    duration: viewModel.duration,
                    currentTime: $viewModel.currentTime,
                    selection: $viewModel.selection,
                    onSegmentTimeRangeChange: { id, startTime, endTime in
                        viewModel.updateSegmentTimeRange(id, startTime: startTime, endTime: endTime)
                    },
                    onAddSegment: { trackType, time in
                        viewModel.addSegment(to: trackType, at: time)
                    },
                    onSegmentSelect: { trackType, id in
                        viewModel.selectSegment(id, trackType: trackType)
                    },
                    onSegmentToggleSelect: { trackType, id in
                        viewModel.toggleSegmentSelection(id, trackType: trackType)
                    },
                    onSeek: { time in
                        await viewModel.seek(to: time)
                    },
                    trimStart: viewModel.trimStartBinding,
                    trimEnd: viewModel.trimEndBinding,
                    onTrimChange: { start, end in
                        viewModel.setTrimRange(start: start, end: end)
                    }
                )
                .frame(height: 224)
            }

            // Right: inspector
            InspectorView(
                timeline: viewModel.timelineBinding,
                selection: $viewModel.selection,
                renderSettings: viewModel.renderSettingsBinding,
                isWindowMode: viewModel.isWindowMode,
                onSegmentChange: {
                    viewModel.notifySegmentChanged()
                },
                onDeleteSegment: { id, trackType in
                    viewModel.deleteSegment(id, from: trackType)
                }
            )
        }
        .frame(minWidth: 1000, minHeight: 600)
        .task {
            await viewModel.setup()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheetView(
                project: viewModel.project,
                exportEngine: viewModel.exportEngine,
                onDismiss: {
                    showExportSheet = false
                },
                onComplete: { url in
                    print("Export completed: \(url)")
                    showExportSheet = false
                }
            )
        }
        .alert("Unsaved Changes", isPresented: $showSaveConfirmation) {
            Button("Don't Save", role: .destructive) {
                returnToHome()
            }
            Button("Save") {
                saveProject()
                returnToHome()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to save the changes made to this project?")
        }
        .alert("Unsaved Changes", isPresented: $showNewRecordingConfirmation) {
            Button("Don't Save", role: .destructive) {
                startNewRecording()
            }
            Button("Save & Record") {
                saveProject()
                startNewRecording()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to save before starting a new recording?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorUndo)) { _ in
            viewModel.undo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorRedo)) { _ in
            viewModel.redo()
        }
        .onReceive(viewModel.undoStack.$canUndo) { canUndo in
            AppState.shared.canUndo = canUndo
        }
        .onReceive(viewModel.undoStack.$canRedo) { canRedo in
            AppState.shared.canRedo = canRedo
        }
        .onAppear {
            installDeleteKeyMonitor()
        }
        .onDisappear {
            removeDeleteKeyMonitor()
            AppState.shared.canUndo = false
            AppState.shared.canRedo = false
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            // Home button
            Button {
                if viewModel.hasUnsavedChanges {
                    showSaveConfirmation = true
                } else {
                    returnToHome()
                }
            } label: {
                Image(systemName: "house")
            }
            .buttonStyle(.plain)
            .help("Return to Home")

            // New Recording button
            Button {
                if viewModel.hasUnsavedChanges {
                    showNewRecordingConfirmation = true
                } else {
                    startNewRecording()
                }
            } label: {
                Image(systemName: "record.circle")
            }
            .buttonStyle(.plain)
            .help("New Recording")

            Divider()
                .frame(height: 20)

            // Undo
            Button {
                NotificationCenter.default.post(name: .editorUndo, object: nil)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.undoStack.canUndo)
            .help("Undo")

            // Redo
            Button {
                NotificationCenter.default.post(name: .editorRedo, object: nil)
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.undoStack.canRedo)
            .help("Redo")

            Divider()
                .frame(height: 20)

            // Add segment
            keyframeAddMenu

            // Delete all segments
            Button(role: .destructive) {
                viewModel.deleteAllSegments()
            } label: {
                Label("Delete All", systemImage: "trash")
            }
            .disabled(viewModel.project.timeline.totalSegmentCount == 0)

            Spacer()

            // Smart generator
            Button {
                showGeneratorPanel.toggle()
            } label: {
                Label("Smart", systemImage: "wand.and.stars")
            }
            .popover(isPresented: $showGeneratorPanel) {
                GeneratorPanelView(viewModel: viewModel)
            }

            Divider()
                .frame(height: 20)

            // Save
            Button {
                saveProject()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!viewModel.hasUnsavedChanges)

            // Export
            Button {
                showExportSheet = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)

            // Keyboard shortcuts help
            ShortcutHelpButton(context: .editor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Keyframe Add Menu

    private var keyframeAddMenu: some View {
        Menu {
            Button {
                viewModel.addSegment(to: .transform)
            } label: {
                Label("Camera Segment", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Button {
                viewModel.addSegment(to: .cursor)
            } label: {
                Label("Cursor Segment", systemImage: "cursorarrow")
            }

            Button {
                viewModel.addSegment(to: .keystroke)
            } label: {
                Label("Keystroke Segment", systemImage: "keyboard")
            }
        } label: {
            Label("Add Segment", systemImage: "plus.diamond")
        }
    }

    // MARK: - Actions

    private func saveProject() {
        Task {
            do {
                let savedURL = try await ProjectManager.shared.save(viewModel.project, to: viewModel.projectURL)
                viewModel.projectURL = savedURL
                viewModel.hasUnsavedChanges = false
            } catch {
                print("Failed to save project: \(error)")
            }
        }
    }

    // MARK: - Delete Key Monitor

    private func installDeleteKeyMonitor() {
        deleteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Delete (backspace) = keyCode 51, Forward Delete = keyCode 117
            guard event.keyCode == 51 || event.keyCode == 117 else {
                return event
            }

            // If a text field is focused, let the event pass through for normal editing
            if let firstResponder = NSApp.keyWindow?.firstResponder,
               firstResponder is NSTextView,
               (firstResponder as? NSTextView)?.superview is NSTextField {
                return event
            }

            // Delete all selected segments
            if !viewModel.selection.isEmpty {
                let selected = viewModel.selection.segments
                for ident in selected {
                    viewModel.deleteSegment(ident.id, from: ident.trackType)
                }
                return nil // consume the event
            }

            return event
        }
    }

    private func removeDeleteKeyMonitor() {
        if let monitor = deleteKeyMonitor {
            NSEvent.removeMonitor(monitor)
            deleteKeyMonitor = nil
        }
    }

   // MARK: - Navigation

    private func returnToHome() {
        viewModel.cleanup()
        AppState.shared.closeProject()
    }

    private func startNewRecording() {
        viewModel.cleanup()
        AppState.shared.startNewRecording()
    }

}

// MARK: - Generator Panel View

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
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.accentColor)
                Text("Smart Generation")
                    .font(.headline)
                Spacer()
            }

            Divider()

            // Per-type toggles
            VStack(alignment: .leading, spacing: 10) {
                ForEach(generatorOptions) { option in
                    Toggle(isOn: toggleBinding(for: option.type)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(option.name, systemImage: option.icon)
                                .font(.subheadline)
                            Text(option.description)
                                .font(.caption)
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
                    .font(.caption)
                    .foregroundColor(
                        result.hasPrefix("Failed") ? .red : .green
                    )
                    .padding(.vertical, 4)
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
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
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
