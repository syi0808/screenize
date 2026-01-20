import SwiftUI

/// Main editor view
struct EditorMainView: View {

    // MARK: - Properties

    /// View model
    @StateObject private var viewModel: EditorViewModel

    /// Show export sheet
    @State private var showExportSheet = false

    /// Show save confirmation alert
    @State private var showSaveConfirmation = false

    /// Show the Smart generator panel
    @State private var showGeneratorPanel = false

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
                    selectedKeyframeID: $viewModel.selectedKeyframeID,
                    selectedTrackType: $viewModel.selectedTrackType,
                    onKeyframeChange: { id, time in
                        viewModel.updateKeyframeTime(id, to: time)
                    },
                    onAddKeyframe: { trackType, time in
                        viewModel.addKeyframe(to: trackType, at: time)
                    },
                    onKeyframeSelect: { trackType, id in
                        viewModel.selectKeyframe(id, trackType: trackType)
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
                selectedKeyframeID: $viewModel.selectedKeyframeID,
                selectedTrackType: $viewModel.selectedTrackType,
                renderSettings: viewModel.renderSettingsBinding,
                isWindowMode: viewModel.isWindowMode,
                onKeyframeChange: {
                    viewModel.notifyKeyframeChanged()
                },
                onDeleteKeyframe: { id, trackType in
                    viewModel.deleteKeyframe(id, from: trackType)
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
                // Close without saving
            }
            Button("Save") {
                // Save and close
                saveProject()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to save the changes made to this project?")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 16) {
            // Playback controls
            playbackControls

            Divider()
                .frame(height: 20)

            // Add keyframe
            keyframeAddMenu

            // Delete all keyframes
            Button(role: .destructive) {
                viewModel.deleteAllKeyframes()
            } label: {
                Label("Delete All", systemImage: "trash")
            }
            .disabled(viewModel.project.timeline.transformTrack?.keyframes.isEmpty != false
                      && viewModel.project.timeline.rippleTrack?.keyframes.isEmpty != false
                      && viewModel.project.timeline.cursorTrack?.styleKeyframes?.isEmpty != false)

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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 8) {
            // To start
            Button {
                Task {
                    await viewModel.seekToStart()
                }
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.plain)

            // Previous frame
            Button {
                Task {
                    await viewModel.stepBackward()
                }
            } label: {
                Image(systemName: "backward.frame.fill")
            }
            .buttonStyle(.plain)

            // Play/Pause
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            // Next frame
            Button {
                Task {
                    await viewModel.stepForward()
                }
            } label: {
                Image(systemName: "forward.frame.fill")
            }
            .buttonStyle(.plain)

            // To end
            Button {
                Task {
                    await viewModel.seekToEnd()
                }
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .buttonStyle(.plain)

            // Time display
            Text(formatTime(viewModel.currentTime))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
        }
    }

    // MARK: - Keyframe Add Menu

    private var keyframeAddMenu: some View {
        Menu {
            Button {
                viewModel.addKeyframe(to: .transform)
            } label: {
                Label("Transform Keyframe", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            Button {
                viewModel.addKeyframe(to: .ripple)
            } label: {
                Label("Ripple Keyframe", systemImage: "circles.hexagonpath")
            }

            Button {
                viewModel.addKeyframe(to: .cursor)
            } label: {
                Label("Cursor Keyframe", systemImage: "cursorarrow")
            }

            Button {
                viewModel.addKeyframe(to: .keystroke)
            } label: {
                Label("Keystroke Keyframe", systemImage: "keyboard")
            }
        } label: {
            Label("Add Keyframe", systemImage: "plus.diamond")
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

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let frames = Int((time - Double(totalSeconds)) * viewModel.frameRate)

        return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }
}

// MARK: - Generator Panel View

/// Smart generator panel
struct GeneratorPanelView: View {

    @ObservedObject var viewModel: EditorViewModel

    @State private var isGenerating: Bool = false
    @State private var generationResult: String?
    @Environment(\.dismiss) private var dismiss

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

            // Description
            VStack(alignment: .leading, spacing: 8) {
                Text("Automatically generate keyframes from mouse data and video analysis:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Label("Smart zoom (auto-focus on activity)", systemImage: "sparkle.magnifyingglass")
                    Label("Stable zoom during continuous sessions", systemImage: "cursorarrow.motionlines")
                    Label("Scene change detection for zoom transitions", systemImage: "eye")
                    Label("Click ripple effects", systemImage: "circles.hexagonpath")
                    Label("Keystroke overlays for keyboard shortcuts", systemImage: "keyboard")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Divider()

            // Display generation result
            if let result = generationResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.vertical, 4)
            }

            // Generation button
            Button {
                Task {
                    await generateAllKeyframes()
                }
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isGenerating ? "Generating..." : "Generate All Keyframes")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)

            // Helper text
            Text("Generated keyframes can be freely edited in the timeline.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 320)
    }

    @MainActor
    private func generateAllKeyframes() async {
        guard !isGenerating else { return }

        isGenerating = true
        generationResult = nil

        // Use EditorViewModel's Smart Zoom generation
        await viewModel.runSmartGeneration()

        // Display the result counts
        let transformCount = viewModel.project.timeline.transformTrack?.keyframes.count ?? 0
        let rippleCount = viewModel.project.timeline.rippleTrack?.keyframes.count ?? 0
        let cursorCount = viewModel.project.timeline.cursorTrack?.styleKeyframes?.count ?? 0
        let keystrokeCount = viewModel.project.timeline.keystrokeTrack?.keyframes.count ?? 0

        if let error = viewModel.errorMessage {
            generationResult = "Failed: \(error)"
        } else {
            generationResult = "\(transformCount) transform, \(rippleCount) ripple, \(cursorCount) cursor, \(keystrokeCount) keystroke"
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
                videoURL: URL(fileURLWithPath: "/test.mp4"),
                mouseDataURL: URL(fileURLWithPath: "/test.json"),
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
                    AnyTrack(TransformTrack(
                        id: UUID(),
                        name: "Transform",
                        isEnabled: true,
                        keyframes: [
                            TransformKeyframe(time: 0, zoom: 1.0, centerX: 0.5, centerY: 0.5),
                            TransformKeyframe(time: 5, zoom: 2.0, centerX: 0.3, centerY: 0.4),
                        ]
                    )),
                    AnyTrack(RippleTrack(
                        id: UUID(),
                        name: "Ripple",
                        isEnabled: true,
                        keyframes: []
                    )),
                    AnyTrack(CursorTrack(
                        id: UUID(),
                        name: "Cursor",
                        isEnabled: true
                    )),
                ],
                duration: 30
            ),
            renderSettings: RenderSettings()
        )
    )
}
