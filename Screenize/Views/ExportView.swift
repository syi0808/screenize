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
    @State private var showFilePicker = false

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
        .fileExporter(
            isPresented: $showFilePicker,
            document: ExportDocument(),
            contentType: .mpeg4Movie,
            defaultFilename: "\(project.media.videoURL.deletingPathExtension().lastPathComponent)_edited"
        ) { result in
            switch result {
            case .success(let url):
                outputURL = url
                startExport()
            case .failure(let error):
                print("File picker error: \(error)")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "square.and.arrow.up")
                .font(.title2)
                .foregroundColor(.accentColor)

            Text("Export Video")
                .font(.headline)

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
        .padding()
    }

    // MARK: - Settings Form

    private var settingsForm: some View {
        Form {
            // Preset
            Section("Preset") {
                PresetPickerView(settings: $renderSettings)
            }

            // Resolution
            Section("Resolution") {
                Picker("Output Size", selection: $renderSettings.outputResolution) {
                    ForEach(OutputResolution.allCases, id: \.self) { resolution in
                        Text(resolution.displayName).tag(resolution)
                    }
                }
            }

            // Frame rate
            Section("Frame Rate") {
                Picker("Frame Rate", selection: $renderSettings.outputFrameRate) {
                    ForEach(OutputFrameRate.allCases, id: \.self) { rate in
                        Text(rate.displayName).tag(rate)
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
                    .font(.caption)
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
                estimatedFileSize
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Estimated File Size

    private var estimatedFileSize: some View {
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
        .font(.caption)
    }

    // MARK: - Export Progress View

    private var exportProgressView: some View {
        VStack(spacing: 20) {
            Spacer()

            // Progress circle
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: exportEngine.progress.progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: exportEngine.progress.progress)

                Text("\(exportEngine.progress.percentComplete)%")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }

            // Status text
            Text(exportEngine.progress.statusText)
                .font(.headline)

            // Statistics
            if let stats = exportEngine.statistics {
                VStack(spacing: 4) {
                    Text("Processing: \(String(format: "%.1f", stats.processingFPS)) fps")

                    if let remaining = stats.estimatedRemainingTime {
                        Text("Remaining: \(formatDuration(remaining))")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
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
                    showFilePicker = true
                }
                .buttonStyle(.borderedProminent)
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
        .padding()
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

// MARK: - Export Document (for file exporter)

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.mpeg4Movie]

    init() {}

    init(configuration: ReadConfiguration) throws {
        // Not used for export
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Return empty wrapper - actual content written by export engine
        return FileWrapper(regularFileWithContents: Data())
    }
}

// MARK: - Inline Export Progress View

/// Export progress view displayed inside the editor
struct InlineExportProgressView: View {

    @ObservedObject var exportEngine: ExportEngine

    var onCancel: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Progress bar
            ProgressView(value: exportEngine.progress.progress)
                .progressViewStyle(.linear)

            // Percentage
            Text("\(exportEngine.progress.percentComplete)%")
                .font(.system(size: 11, design: .monospaced))
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
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
                    timeline: Timeline(),
                    renderSettings: RenderSettings()
                ),
                exportEngine: engine
            )
        }
    }

    return PreviewWrapper()
}
