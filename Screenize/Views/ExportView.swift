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

    @State private var renderSettings: RenderSettings
    @State private var outputURL: URL?
    @State private var isExporting = false

    // Custom resolution state
    @State private var isCustomResolution: Bool
    @State private var customWidth: Int
    @State private var customHeight: Int
    @State private var resolutionValidationError: String?

    // Custom frame rate state
    @State private var isCustomFrameRate: Bool
    @State private var customFPS: Int
    @State private var frameRateValidationError: String?

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

    // MARK: - Settings Form

    private var settingsForm: some View {
        Form {
            // Preset
            Section("Preset") {
                PresetPickerView(settings: $renderSettings)
            }

            // Format
            Section("Format") {
                Picker("Format", selection: $renderSettings.exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            if renderSettings.exportFormat == .video {
                // Resolution
                Section("Resolution") {
                    Picker("Output Size", selection: resolutionPickerBinding) {
                        ForEach(OutputResolution.allCases, id: \.self) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                        Text("Custom").tag(OutputResolution.custom(width: 0, height: 0))
                    }

                    if isCustomResolution {
                        HStack(spacing: 8) {
                            TextField("Width", value: $customWidth, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: customWidth) { _ in applyCustomResolution() }

                            Text("\u{00d7}")
                                .foregroundColor(.secondary)

                            TextField("Height", value: $customHeight, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: customHeight) { _ in applyCustomResolution() }
                        }

                        if let error = resolutionValidationError {
                            Text(error)
                                .font(Typography.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Frame rate
                Section("Frame Rate") {
                    Picker("Frame Rate", selection: frameRatePickerBinding) {
                        ForEach(OutputFrameRate.allCases, id: \.self) { rate in
                            Text(rate.displayName).tag(rate)
                        }
                        Text("Custom").tag(OutputFrameRate.fixed(-1))
                    }

                    if isCustomFrameRate {
                        HStack(spacing: 8) {
                            TextField("FPS", value: $customFPS, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: customFPS) { _ in applyCustomFrameRate() }

                            Text("fps")
                                .foregroundColor(.secondary)
                        }

                        if let error = frameRateValidationError {
                            Text(error)
                                .font(Typography.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Codec
                Section("Codec") {
                    Picker("Video Codec", selection: $renderSettings.codec) {
                        ForEach(VideoCodec.allCases, id: \.self) { codec in
                            Text(codec.displayName).tag(codec)
                        }
                    }

                    Text(renderSettings.codec.displayName)
                        .font(Typography.caption)
                        .foregroundColor(.secondary)
                }

                // Quality
                Section("Quality") {
                    Picker("Quality", selection: $renderSettings.quality) {
                        ForEach(ExportQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }

                    // Estimated file size
                    estimatedVideoFileSize
                }

                // Color Space
                Section("Color Space") {
                    Picker("Color Space", selection: $renderSettings.outputColorSpace) {
                        ForEach(OutputColorSpace.allCases, id: \.self) { cs in
                            Text(cs.displayName).tag(cs)
                        }
                    }

                    if renderSettings.outputColorSpace.isWideGamut {
                        Text("Wide gamut preserves colors outside sRGB range")
                            .font(Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if renderSettings.exportFormat == .gif {
                // GIF Settings
                Section("GIF Settings") {
                    HStack {
                        Text("Frame Rate")
                        Spacer()
                        Text("\(renderSettings.gifSettings.frameRate) fps")
                            .foregroundColor(.secondary)
                    }
                    Slider(
                        value: gifFrameRateBinding,
                        in: 5...30,
                        step: 1
                    )

                    Picker("Max Width", selection: $renderSettings.gifSettings.maxWidth) {
                        Text("480px").tag(480)
                        Text("640px").tag(640)
                        Text("800px").tag(800)
                        Text("960px").tag(960)
                        Text("1280px").tag(1280)
                    }

                    Picker("Loop", selection: $renderSettings.gifSettings.loopCount) {
                        Text("Infinite").tag(0)
                        Text("Once").tag(1)
                        Text("Twice").tag(2)
                        Text("3 times").tag(3)
                    }

                    // Estimated file size
                    gifEstimatedFileSize
                }

                if let warning = gifFileSizeWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(Typography.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Estimated File Size

    private var estimatedVideoFileSize: some View {
        let sourceSize = project.media.pixelSize
        let outputSize = renderSettings.outputResolution.size(sourceSize: sourceSize)
        let bitRate = renderSettings.quality.bitRate(for: outputSize)
        let estimatedBytes = Int64(Double(bitRate) * project.media.duration / 8)

        return HStack {
            Text("Estimated size:")
                .foregroundColor(.secondary)

            Text(ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file))
                .fontWeight(.medium)
        }
        .font(Typography.caption)
    }

    // MARK: - GIF Helpers

    private var gifFrameRateBinding: Binding<Double> {
        Binding(
            get: { Double(renderSettings.gifSettings.frameRate) },
            set: { renderSettings.gifSettings.frameRate = Int($0) }
        )
    }

    private var gifEstimatedFileSize: some View {
        let duration = project.timeline.trimmedDuration
        let estimated = renderSettings.gifSettings.estimatedFileSize(duration: duration)

        return HStack {
            Text("Estimated size:")
                .foregroundColor(.secondary)

            Text(ByteCountFormatter.string(fromByteCount: estimated, countStyle: .file))
                .fontWeight(.medium)
        }
        .font(Typography.caption)
    }

    private var gifFileSizeWarning: String? {
        let duration = project.timeline.trimmedDuration
        let estimated = renderSettings.gifSettings.estimatedFileSize(duration: duration)
        let estimatedMB = Double(estimated) / 1_048_576.0

        if duration > 30 {
            return "Recording exceeds 30s. GIF files for long recordings will be very large (\(String(format: "%.0f", estimatedMB)) MB estimated)."
        }
        if renderSettings.gifSettings.maxWidth > 960 {
            return "High resolution GIFs produce very large files (\(String(format: "%.0f", estimatedMB)) MB estimated). Consider reducing max width."
        }
        if estimatedMB > 50 {
            return "Estimated file size exceeds 50 MB. Consider reducing frame rate, max width, or trimming the recording."
        }
        return nil
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

    // MARK: - Picker Bindings

    private var resolutionPickerBinding: Binding<OutputResolution> {
        Binding(
            get: {
                if isCustomResolution {
                    return .custom(width: 0, height: 0)
                }
                return renderSettings.outputResolution
            },
            set: { newValue in
                if case .custom = newValue {
                    isCustomResolution = true
                    applyCustomResolution()
                } else {
                    isCustomResolution = false
                    resolutionValidationError = nil
                    renderSettings.outputResolution = newValue
                }
            }
        )
    }

    private var frameRatePickerBinding: Binding<OutputFrameRate> {
        Binding(
            get: {
                if isCustomFrameRate {
                    return .fixed(-1)
                }
                return renderSettings.outputFrameRate
            },
            set: { newValue in
                if case .fixed(-1) = newValue {
                    isCustomFrameRate = true
                    applyCustomFrameRate()
                } else {
                    isCustomFrameRate = false
                    frameRateValidationError = nil
                    renderSettings.outputFrameRate = newValue
                }
            }
        )
    }

    // MARK: - Validation

    private var hasValidationError: Bool {
        resolutionValidationError != nil || frameRateValidationError != nil
    }

    private func applyCustomResolution() {
        resolutionValidationError = nil

        guard customWidth >= 2 else {
            resolutionValidationError = "Width must be at least 2"
            return
        }
        guard customHeight >= 2 else {
            resolutionValidationError = "Height must be at least 2"
            return
        }
        guard customWidth <= 7680 else {
            resolutionValidationError = "Width cannot exceed 7680"
            return
        }
        guard customHeight <= 4320 else {
            resolutionValidationError = "Height cannot exceed 4320"
            return
        }

        // Ensure even dimensions for AVAssetWriter
        let w = customWidth.isMultiple(of: 2) ? customWidth : customWidth + 1
        let h = customHeight.isMultiple(of: 2) ? customHeight : customHeight + 1
        renderSettings.outputResolution = .custom(width: w, height: h)
    }

    private func applyCustomFrameRate() {
        frameRateValidationError = nil

        guard customFPS >= 1 else {
            frameRateValidationError = "Frame rate must be at least 1"
            return
        }
        guard customFPS <= 240 else {
            frameRateValidationError = "Frame rate cannot exceed 240"
            return
        }

        renderSettings.outputFrameRate = .fixed(customFPS)
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
                    // Handle the error
                    print("Export error: \(error)")
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
