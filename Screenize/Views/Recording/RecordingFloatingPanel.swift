import AppKit
import SwiftUI

/// Floating panel shown during recording with stop/pause controls
/// Displays above all windows without stealing focus
final class RecordingFloatingPanel: NSPanel {

    // MARK: - Properties

    private var hostingView: NSHostingView<RecordingFloatingView>?

    // MARK: - Initialization

    init(appState: AppState) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        setupContent(appState: appState)
        positionOnScreen()
    }

    // MARK: - Configuration

    private func configurePanel() {
        self.level = .floating
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
    }

    private func setupContent(appState: AppState) {
        let view = RecordingFloatingView(appState: appState)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 48)
        self.contentView = hosting
        self.hostingView = hosting
    }

    private func positionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = self.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.minY + 60
        )
        self.setFrameOrigin(origin)
    }

    // MARK: - Public API

    @MainActor
    func show() {
        self.orderFrontRegardless()
    }

    @MainActor
    func dismiss() {
        self.orderOut(nil)
    }

    // Does not take focus
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Recording Floating SwiftUI View

struct RecordingFloatingView: View {
    @ObservedObject var appState: AppState

    @State private var isBlinking = false

    var body: some View {
        HStack(spacing: 12) {
            // Recording indicator (red dot)
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(isBlinking ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isBlinking)

            // Recording duration
            Text(formattedDuration)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)

            if appState.isPaused {
                Text("PAUSED")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(3)
            }

            Spacer()

            // Pause/Resume button
            Button {
                appState.togglePause()
            } label: {
                Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .help(appState.isPaused ? "Resume" : "Pause")

            // Stop button
            Button {
                Task {
                    await appState.stopRecording()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .help("Stop Recording")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.85))
        )
        .onAppear {
            isBlinking = true
        }
    }

    private var formattedDuration: String {
        let duration = appState.recordingDuration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
