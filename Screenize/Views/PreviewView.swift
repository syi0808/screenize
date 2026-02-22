import SwiftUI
import CoreGraphics
import Metal

/// Video preview view
struct PreviewView: View {

    // MARK: - Properties

    /// Preview engine
    @ObservedObject var previewEngine: PreviewEngine

    /// Current time (two-way binding)
    @Binding var currentTime: TimeInterval

    /// Playback state
    let isPlaying: Bool

    /// Callback to toggle playback
    var onPlayPauseToggle: (() -> Void)?

    /// Seek callback
    var onSeek: ((TimeInterval) async -> Void)?

    // MARK: - State

    @State private var showControls = true
    @State private var controlsHideTimer: Timer?

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            let aspectRatio = previewEngine.videoAspectRatio
            let containerSize = geometry.size

            // Calculate video size to fit the container
            let videoSize: CGSize = {
                let containerAspect = containerSize.width / containerSize.height
                if aspectRatio > containerAspect {
                    // Wider than tall: fit by width
                    let width = containerSize.width
                    let height = width / aspectRatio
                    return CGSize(width: width, height: height)
                } else {
                    // Taller than wide: fit by height
                    let height = containerSize.height
                    let width = height * aspectRatio
                    return CGSize(width: width, height: height)
                }
            }()

            ZStack {
                // Background
                Color.black

                // Video frame (GPU-resident Metal texture)
                if previewEngine.currentTexture != nil {
                    MetalPreviewView(
                        texture: previewEngine.currentTexture,
                        generation: previewEngine.displayGeneration
                    )
                } else if previewEngine.isLoading {
                    loadingView
                } else if let errorMessage = previewEngine.errorMessage {
                    errorView(errorMessage)
                } else {
                    placeholderView
                }

                // Render error banner
                if let renderError = previewEngine.lastRenderError {
                    renderErrorBanner(renderError)
                }

                // Controls overlay
                if showControls {
                    controlsOverlay
                }
            }
            .frame(width: videoSize.width, height: videoSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
                resetControlsTimer()
            }
            .onHover { hovering in
                if hovering {
                    showControls = true
                    resetControlsTimer()
                }
            }
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading preview...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red.opacity(0.7))

            Text("Preview failed")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            Text(message)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 24)
        }
    }

    // MARK: - Placeholder View

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No preview available")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            Spacer()

            // Bottom control bar
            VStack(spacing: 8) {
                // Progress bar
                progressBar

                // Control buttons
                HStack(spacing: 16) {
                    // Play/Pause
                    Button {
                        onPlayPauseToggle?()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white)

                    // Current time display
                    Text(formatTime(currentTime))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)

                    Text("/")
                        .foregroundColor(.white.opacity(0.5))

                    Text(formatTime(previewEngine.duration))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))

                    Spacer()

                    // Frame display
                    Text("Frame \(previewEngine.currentFrameNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .transition(.opacity)
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 4)

                // Progress fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * previewEngine.progress, height: 4)

                // Draggable hit area
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let progress = max(0, min(1, value.location.x / geometry.size.width))
                                let newTime = progress * previewEngine.duration
                                currentTime = newTime
                            }
                            .onEnded { value in
                                let progress = max(0, min(1, value.location.x / geometry.size.width))
                                let newTime = progress * previewEngine.duration
                                Task {
                                    await onSeek?(newTime)
                                }
                            }
                    )
            }
        }
        .frame(height: 20)
        .padding(.horizontal, 12)
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let frames = Int((time - Double(totalSeconds)) * 60)

        return String(format: "%02d:%02d:%02d", minutes, seconds, frames)
    }

    private func resetControlsTimer() {
        controlsHideTimer?.invalidate()

        if !isPlaying {
            return
        }

        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls = false
            }
        }
    }
    // MARK: - Render Error Banner

    private func renderErrorBanner(_ error: RenderError) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)

                Text("Render error at frame \(error.frameIndex)")
                    .font(.caption.bold())
                    .foregroundColor(.white)

                Spacer()

                Button {
                    previewEngine.clearRenderError()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.85))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Mini Preview (for timeline hover)

/// Mini preview shown on timeline hover
struct MiniPreviewView: View {

    let frame: CGImage?
    let time: TimeInterval

    var body: some View {
        VStack(spacing: 4) {
            if let frame = frame {
                Image(frame, scale: 1, label: Text("Mini Preview"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 90)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 160, height: 90)
            }

            Text(formatTime(time))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 8)
        )
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @StateObject private var engine = PreviewEngine()
        @State private var currentTime: TimeInterval = 5.0

        var body: some View {
            PreviewView(
                previewEngine: engine,
                currentTime: $currentTime,
                isPlaying: false,
                onPlayPauseToggle: {
                    print("Toggle playback")
                },
                onSeek: { time in
                    print("Seek to \(time)")
                }
            )
            .frame(width: 640, height: 360)
            .padding()
        }
    }

    return PreviewWrapper()
}
