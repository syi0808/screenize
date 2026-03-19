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
        .alert(L10n.string("editor.alert.unsaved_changes.title", defaultValue: "Unsaved Changes"), isPresented: $showSaveConfirmation) {
            Button(L10n.string("editor.alert.unsaved_changes.discard", defaultValue: "Don't Save"), role: .destructive) {
                returnToHome()
            }
            Button(L10n.string("editor.alert.unsaved_changes.save", defaultValue: "Save")) {
                saveProject()
                returnToHome()
            }
            Button(L10n.string("editor.alert.unsaved_changes.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string(
                "editor.alert.unsaved_changes.message",
                defaultValue: "Do you want to save the changes made to this project?"
            ))
        }
        .alert(
            L10n.string("editor.alert.unsaved_changes.title", defaultValue: "Unsaved Changes"),
            isPresented: $showNewRecordingConfirmation
        ) {
            Button(L10n.string("editor.alert.unsaved_changes.discard", defaultValue: "Don't Save"), role: .destructive) {
                startNewRecording()
            }
            Button(L10n.string("editor.alert.new_recording.save_and_record", defaultValue: "Save & Record")) {
                saveProject()
                startNewRecording()
            }
            Button(L10n.string("editor.alert.unsaved_changes.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string(
                "editor.alert.new_recording.message",
                defaultValue: "Do you want to save before starting a new recording?"
            ))
        }
        .alert(L10n.string("editor.alert.save_error.title", defaultValue: "Save Error"), isPresented: $showSaveErrorAlert) {
            Button(L10n.commonOK, role: .cancel) {}
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
        .onReceive(NotificationCenter.default.publisher(for: .regenerateTimeline)) { _ in
            Task {
                await viewModel.runSmartGeneration()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .projectGenerationSettingsChanged)) { notification in
            if let settings = notification.userInfo?["settings"] as? GenerationSettings {
                viewModel.project.generationSettings = settings
                viewModel.hasUnsavedChanges = true
            }
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
            .help(L10n.string("editor.toolbar.home.help", defaultValue: "Return to Home"))
            .accessibilityLabel(L10n.string("editor.toolbar.home.label", defaultValue: "Home"))

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
            .help(L10n.string("editor.toolbar.new_recording", defaultValue: "New Recording"))
            .accessibilityLabel(L10n.string("editor.toolbar.new_recording", defaultValue: "New Recording"))

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
            .help(L10n.string("app.menu.undo", defaultValue: "Undo"))
            .accessibilityLabel(L10n.string("app.menu.undo", defaultValue: "Undo"))
            .accessibilityHint(L10n.string("editor.toolbar.undo.hint", defaultValue: "Undo last editing action"))

            // Redo
            Button {
                NotificationCenter.default.post(name: .editorRedo, object: nil)
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .disabled(!viewModel.undoStack.canRedo)
            .help(L10n.string("app.menu.redo", defaultValue: "Redo"))
            .accessibilityLabel(L10n.string("app.menu.redo", defaultValue: "Redo"))
            .accessibilityHint(L10n.string("editor.toolbar.redo.hint", defaultValue: "Redo last undone action"))

            Divider()
                .frame(height: Spacing.xl)

            // Add segment
            keyframeAddMenu

            // Delete all segments
            Button(role: .destructive) {
                viewModel.deleteAllSegments()
            } label: {
                Label(L10n.string("editor.toolbar.delete_all", defaultValue: "Delete All"), systemImage: "trash")
            }
            .disabled(viewModel.project.timeline.totalSegmentCount == 0)

            Spacer()

            // Smart generator
            Button {
                showGeneratorPanel.toggle()
            } label: {
                Label(L10n.string("editor.toolbar.smart", defaultValue: "Smart"), systemImage: "wand.and.stars")
            }
            .popover(isPresented: $showGeneratorPanel) {
                GeneratorPanelView(viewModel: viewModel)
            }

            // Advanced generation settings
            Button {
                GenerationSettingsWindowController.shared.showWindow()
            } label: {
                Image(systemName: "gearshape.2")
            }
            .help(L10n.string(
                "editor.toolbar.advanced_generation_settings",
                defaultValue: "Advanced Generation Settings"
            ))

            Divider()
                .frame(height: Spacing.xl)

            // Save
            Button {
                saveProject()
            } label: {
                Label(L10n.string("editor.toolbar.save", defaultValue: "Save"), systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!viewModel.hasUnsavedChanges)

            // Export
            Button {
                showExportSheet = true
            } label: {
                Label(L10n.string("editor.toolbar.export", defaultValue: "Export"), systemImage: "square.and.arrow.up")
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
                Label(
                    L10n.string("editor.segment.camera", defaultValue: "Camera Segment"),
                    systemImage: "arrow.up.left.and.arrow.down.right"
                )
            }

            Button {
                viewModel.addSegment(to: .cursor)
            } label: {
                Label(L10n.string("editor.segment.cursor", defaultValue: "Cursor Segment"), systemImage: "cursorarrow")
            }

            Button {
                viewModel.addSegment(to: .keystroke)
            } label: {
                Label(L10n.string("editor.segment.keystroke", defaultValue: "Keystroke Segment"), systemImage: "keyboard")
            }
        } label: {
            Label(L10n.string("editor.segment.add", defaultValue: "Add Segment"), systemImage: "plus.diamond")
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
                saveErrorMessage = L10n.failedToSaveProject(detail: error.localizedDescription)
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
