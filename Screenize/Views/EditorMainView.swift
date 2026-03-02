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
    @State private var keyMonitor: Any?

    /// Show save error alert
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""

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
                    onBatchSegmentTimeRangeChange: { changes in
                        viewModel.batchUpdateSegmentTimeRanges(changes)
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
                    Log.export.info("Export completed: \(url)")
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
        .alert("Save Error", isPresented: $showSaveErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorUndo)) { _ in
            viewModel.undo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorRedo)) { _ in
            viewModel.redo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorCopy)) { _ in
            viewModel.copySelectedSegments()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorPaste)) { _ in
            viewModel.pasteSegments()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorDuplicate)) { _ in
            viewModel.duplicateSelectedSegments()
        }
        .onReceive(viewModel.undoStack.$canUndo) { canUndo in
            AppState.shared.canUndo = canUndo
        }
        .onReceive(viewModel.undoStack.$canRedo) { canRedo in
            AppState.shared.canRedo = canRedo
        }
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
            AppState.shared.canUndo = false
            AppState.shared.canRedo = false
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: Spacing.lg) {
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
            .buttonStyle(ToolbarIconButtonStyle())
            .help("Return to Home")
            .accessibilityLabel("Home")

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
            .buttonStyle(ToolbarIconButtonStyle())
            .help("New Recording")
            .accessibilityLabel("New Recording")

            Divider()
                .frame(height: Spacing.xl)

            // Undo
            Button {
                NotificationCenter.default.post(name: .editorUndo, object: nil)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .disabled(!viewModel.undoStack.canUndo)
            .help("Undo")
            .accessibilityLabel("Undo")
            .accessibilityHint("Undo last editing action")

            // Redo
            Button {
                NotificationCenter.default.post(name: .editorRedo, object: nil)
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .disabled(!viewModel.undoStack.canRedo)
            .help("Redo")
            .accessibilityLabel("Redo")
            .accessibilityHint("Redo last undone action")

            Divider()
                .frame(height: Spacing.xl)

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
                .frame(height: Spacing.xl)

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
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(DesignColors.windowBackground)
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
                Log.project.error("Failed to save project: \(error)")
                saveErrorMessage = "Failed to save project: \(error.localizedDescription)"
                showSaveErrorAlert = true
            }
        }
    }

    // MARK: - Key Monitor

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // If a text field is focused, let the event pass through for normal editing
            if let firstResponder = NSApp.keyWindow?.firstResponder,
               firstResponder is NSTextView,
               (firstResponder as? NSTextView)?.superview is NSTextField {
                return event
            }

            let hasCommand = event.modifierFlags.contains(.command)

            // Space bar = keyCode 49 → Play/Pause
            if event.keyCode == 49 && !hasCommand {
                viewModel.togglePlayback()
                return nil
            }

            // Delete (backspace) = keyCode 51, Forward Delete = keyCode 117
            if event.keyCode == 51 || event.keyCode == 117 {
                if !viewModel.selection.isEmpty {
                    let selected = viewModel.selection.segments
                    for ident in selected {
                        viewModel.deleteSegment(ident.id, from: ident.trackType)
                    }
                    return nil
                }
                return event
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
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
