import SwiftUI
import CoreGraphics
import CoreMedia

/// Live preview view for recording (V1 style)
struct RecordingPreviewView: View {
    @ObservedObject var appState: AppState
    @StateObject private var previewModel = RecordingPreviewViewModel()

    /// Whether window mode is active (apply background, rounded corners, shadow, padding)
    private var isWindowMode: Bool {
        appState.selectedTarget?.isWindow == true
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Display the background preview only in window mode
                if isWindowMode {
                    BackgroundPreview(backgroundStyle: appState.backgroundStyle)
                }

                // Screen content preview
                if let image = previewModel.previewImage {
                    if isWindowMode {
                        // Window mode: background + rounded corners + shadow + padding
                        Image(decorative: image, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                            .padding(40)
                    } else {
                        // Full-screen mode: show only the frame without effects
                        Image(decorative: image, scale: 1.0)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                } else {
                    PlaceholderPreview(appState: appState, isWindowMode: isWindowMode)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            previewModel.startPreview(appState: appState)
        }
        .onDisappear {
            previewModel.stopPreview()
        }
        .onChange(of: appState.selectedTarget?.id) { _ in
            // Restart the preview when the source changes
            Task {
                await previewModel.restartPreview(appState: appState)
            }
        }
    }
}

// MARK: - Preview View Model

@MainActor
final class RecordingPreviewViewModel: ObservableObject {
    @Published var previewImage: CGImage?

    private var captureManager: ScreenCaptureManager?
    private var isRunning = false

    func startPreview(appState: AppState) {
        guard !isRunning, let target = appState.selectedTarget else { return }

        // Skip starting the preview capture while recording (handled by RecordingCoordinator)
        guard !appState.isRecording else { return }

        isRunning = true

        Task {
            do {
                captureManager = ScreenCaptureManager()
                captureManager?.delegate = self

                let config = CaptureConfiguration.forTarget(target, scaleFactor: 1.0)
                try await captureManager?.startCapture(target: target, configuration: config)
            } catch {
                print("Failed to start preview: \(error)")
                isRunning = false
            }
        }
    }

    func stopPreview() {
        guard isRunning else { return }

        Task {
            await captureManager?.stopCapture()
            captureManager = nil
            isRunning = false
        }
    }

    /// Restart the preview when the source changes
    func restartPreview(appState: AppState) async {
        // Stop the current preview
        if isRunning {
            await captureManager?.stopCapture()
            captureManager = nil
            isRunning = false
            previewImage = nil
        }

        // Start previewing the new source
        guard let target = appState.selectedTarget else { return }
        guard !appState.isRecording else { return }

        isRunning = true

        do {
            captureManager = ScreenCaptureManager()
            captureManager?.delegate = self

            let config = CaptureConfiguration.forTarget(target, scaleFactor: 1.0)
            try await captureManager?.startCapture(target: target, configuration: config)
        } catch {
            print("Failed to restart preview: \(error)")
            isRunning = false
        }
    }
}

extension RecordingPreviewViewModel: ScreenCaptureDelegate {
    nonisolated func captureManager(_ manager: ScreenCaptureManager, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()

        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            Task { @MainActor in
                self.previewImage = cgImage
            }
        }
    }

    nonisolated func captureManager(_ manager: ScreenCaptureManager, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        // Not used for preview
    }

    nonisolated func captureManager(_ manager: ScreenCaptureManager, didStopWithError error: Error?) {
        Task { @MainActor in
            self.isRunning = false
            if let error = error {
                print("Preview stopped with error: \(error)")
            }
        }
    }
}

// MARK: - Background Preview

private struct BackgroundPreview: View {
    let backgroundStyle: BackgroundStyle

    var body: some View {
        Group {
            switch backgroundStyle {
            case .solid(let color):
                color

            case .gradient(let style):
                LinearGradient(
                    colors: style.colors,
                    startPoint: style.startPoint,
                    endPoint: style.endPoint
                )

            case .image(let url):
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Placeholder Preview

private struct PlaceholderPreview: View {
    @ObservedObject var appState: AppState
    let isWindowMode: Bool

    var body: some View {
        if let target = appState.selectedTarget {
            placeholderContent(for: target)
        }
    }

    @ViewBuilder
    private func placeholderContent(for target: CaptureTarget) -> some View {
        if isWindowMode {
            // Window mode: rounded corners + shadow + padding
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .aspectRatio(CGFloat(target.width) / CGFloat(target.height), contentMode: .fit)
                .overlay { placeholderOverlay(for: target) }
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                .padding(40)
        } else {
            // Full-screen mode: show the full frame without effects
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .aspectRatio(CGFloat(target.width) / CGFloat(target.height), contentMode: .fit)
                .overlay { placeholderOverlay(for: target) }
        }
    }

    @ViewBuilder
    private func placeholderOverlay(for target: CaptureTarget) -> some View {
        VStack(spacing: 12) {
            Image(systemName: targetIcon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text(target.displayName)
                .font(.headline)

            Text("\(target.width) x \(target.height)")
                .font(.caption)
                .foregroundColor(.secondary)

            if !appState.isRecording {
                Text("Press Record to start capturing")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private var targetIcon: String {
        guard let target = appState.selectedTarget else { return "display" }
        switch target {
        case .display: return "display"
        case .window: return "macwindow"
        case .region: return "rectangle.dashed"
        }
    }
}

// MARK: - Preview

#Preview {
    RecordingPreviewView(appState: AppState.shared)
        .frame(width: 800, height: 600)
}
