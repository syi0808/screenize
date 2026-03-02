import SwiftUI
import UniformTypeIdentifiers

/// Export sheet view
struct ExportSheetView: View {

    // MARK: - Properties

    /// Project
    let project: ScreenizeProject

    /// Export engine
    @ObservedObject var exportEngine: ExportEngine

    /// Dismiss callback
    var onDismiss: (() -> Void)?

    /// Completion callback
    var onComplete: ((URL) -> Void)?

    // MARK: - State

    @State var renderSettings: RenderSettings
    @State private var outputURL: URL?
    @State private var isExporting = false

    // Custom resolution state
    @State var isCustomResolution: Bool
    @State var customWidth: Int
    @State var customHeight: Int
    @State var resolutionValidationError: String?

    // Custom frame rate state
    @State var isCustomFrameRate: Bool
    @State var customFPS: Int
    @State var frameRateValidationError: String?

    // Export error state
    @State private var showExportErrorAlert = false
    @State private var exportErrorMessage = ""

    // MARK: - Initialization

    init(
        project: ScreenizeProject,
        exportEngine: ExportEngine,
        onDismiss: (() -> Void)? = nil,
        onComplete: ((URL) -> Void)? = nil
    ) {
        self.project = project
        self.exportEngine = exportEngine
        self.onDismiss = onDismiss
        self.onComplete = onComplete
        self._renderSettings = State(initialValue: project.renderSettings)

        // Detect existing custom resolution
        if case .custom(let w, let h) = project.renderSettings.outputResolution {
            self._isCustomResolution = State(initialValue: true)
            self._customWidth = State(initialValue: w)
            self._customHeight = State(initialValue: h)
        } else {
            self._isCustomResolution = State(initialValue: false)
            self._customWidth = State(initialValue: 1920)
            self._customHeight = State(initialValue: 1080)
        }
        self._resolutionValidationError = State(initialValue: nil)

        // Detect existing custom frame rate
        let presetFPS = [24, 30, 60, 120, 240]
        if case .fixed(let fps) = project.renderSettings.outputFrameRate,
           !presetFPS.contains(fps) {
            self._isCustomFrameRate = State(initialValue: true)
            self._customFPS = State(initialValue: fps)
        } else {
            self._isCustomFrameRate = State(initialValue: false)
            self._customFPS = State(initialValue: 60)
        }
        self._frameRateValidationError = State(initialValue: nil)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            if isExporting {
                // Export in progress
                exportProgressView
            } else {
                // Settings form
                settingsForm
            }

            Divider()

            // Footer buttons
            footer
        }
        .frame(width: 400)
        .alert("Export Error", isPresented: $showExportErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "square.and.arrow.up")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text(renderSettings.exportFormat == .gif ? "Export GIF" : "Export Video")
                .font(Typography.heading)

            Spacer()

            Button {
                onDismiss?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isExporting)
        }
        .padding(Spacing.lg)
    }

    // MARK: - Export Progress View

    private var exportProgressView: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            // Progress circle
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(DesignOpacity.light), lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: exportEngine.progress.progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .motionSafeAnimation(AnimationTokens.linearFast, value: exportEngine.progress.progress)

                Text("\(exportEngine.progress.percentComplete)%")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }

            // Status text
            Text(exportEngine.progress.statusText)
                .font(Typography.heading)
                .accessibilityLabel("Export status: \(exportEngine.progress.statusText)")

            // Statistics
            if let stats = exportEngine.statistics {
                VStack(spacing: Spacing.xs) {
                    Text("Processing: \(String(format: "%.1f", stats.processingFPS)) fps")

                    if let remaining = stats.estimatedRemainingTime {
                        Text("Remaining: \(formatDuration(remaining))")
                    }
                }
                .font(Typography.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(Spacing.lg)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isExporting {
                Button("Cancel") {
                    cancelExport()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Cancel") {
                    onDismiss?()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if !isExporting {
                Button("Export") {
                    showSavePanel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(hasValidationError)
            } else if exportEngine.progress.isCompleted {
                Button("Done") {
                    if let url = exportEngine.progress.outputURL {
                        onComplete?(url)
                    }
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Spacing.lg)
    }

    // MARK: - File Picker

    private func showSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [renderSettings.exportUTType]
        let baseName = project.media.videoURL
            .deletingPathExtension().lastPathComponent
        panel.nameFieldStringValue = "\(baseName)_edited.\(renderSettings.fileExtension)"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputURL = url
        startExport()
    }

    // MARK: - Actions

    private func startExport() {
        guard let outputURL = outputURL else { return }

        isExporting = true

        // Create a project with the updated settings
        var exportProject = project
        exportProject.renderSettings = renderSettings

        Task {
            do {
                let resultURL = try await exportEngine.export(project: exportProject, to: outputURL)
                await MainActor.run {
                    onComplete?(resultURL)
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportErrorMessage = "Export failed: \(error.localizedDescription)"
                    showExportErrorAlert = true
                    Log.export.error("Export error: \(error)")
                }
            }
        }
    }

    private func cancelExport() {
        exportEngine.cancel()
        isExporting = false
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Inline Export Progress View

/// Export progress view displayed inside the editor
struct InlineExportProgressView: View {

    @ObservedObject var exportEngine: ExportEngine

    var onCancel: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Progress bar
            ProgressView(value: exportEngine.progress.progress)
                .progressViewStyle(.linear)

            // Percentage
            Text("\(exportEngine.progress.percentComplete)%")
                .font(Typography.mono)
                .foregroundColor(.secondary)
                .frame(width: 36, alignment: .trailing)

            // Cancel button
            Button {
                onCancel?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(DesignColors.controlBackground)
        .cornerRadius(CornerRadius.lg)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var engine = ExportEngine()

        var body: some View {
            ExportSheetView(
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
                    timeline: Timeline(),
                    renderSettings: RenderSettings()
                ),
                exportEngine: engine
            )
        }
    }

    return PreviewWrapper()
}
