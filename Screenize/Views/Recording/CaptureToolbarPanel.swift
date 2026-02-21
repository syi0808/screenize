import AppKit
import SwiftUI

/// Unified floating panel for the entire capture/recording lifecycle
/// Transitions between: selecting target → countdown → recording
final class CaptureToolbarPanel: NSPanel {

    // MARK: - Properties

    private var hostingView: NSHostingView<CaptureToolbarView>?
    private var escapeMonitor: Any?
    private weak var coordinator: CaptureToolbarCoordinator?

    // MARK: - Initialization

    init(coordinator: CaptureToolbarCoordinator) {
        self.coordinator = coordinator
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        setupContent(coordinator: coordinator)
        positionOnScreen()
        installEscapeMonitor(coordinator: coordinator)
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

    private func setupContent(coordinator: CaptureToolbarCoordinator) {
        let view = CaptureToolbarView(coordinator: coordinator)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 56)
        self.contentView = hosting
        self.hostingView = hosting
    }

    private func positionOnScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen else { return }

        let screenFrame = screen.visibleFrame
        let panelSize = self.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.minY + 80
        )
        self.setFrameOrigin(origin)
    }

    // MARK: - Escape Key Monitor

    private func installEscapeMonitor(coordinator: CaptureToolbarCoordinator) {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak coordinator] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in
                    guard let coordinator else { return }
                    if case .countdown = coordinator.toolbarPhase {
                        coordinator.cancelCountdown()
                    } else if coordinator.toolbarPhase == .selecting {
                        coordinator.cancel()
                    }
                }
                return nil
            }
            _ = self
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    // MARK: - Public API

    @MainActor
    func show() {
        self.orderFrontRegardless()
    }

    @MainActor
    func dismiss() {
        removeEscapeMonitor()
        self.orderOut(nil)
    }

    // Toolbar needs key status to receive ESC
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Unified Capture Toolbar SwiftUI View

struct CaptureToolbarView: View {
    @ObservedObject var coordinator: CaptureToolbarCoordinator

    var body: some View {
        Group {
            switch coordinator.toolbarPhase {
            case .selecting:
                selectingContent
            case .countdown(let remaining):
                countdownContent(remaining: remaining)
            case .recording:
                recordingContent
            }
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.toolbarPhase)
    }

    // MARK: - Selecting Phase

    private var selectingContent: some View {
        HStack(spacing: 12) {
            ToolbarModeButton(
                icon: "display",
                label: "Entire Screen",
                isSelected: coordinator.captureMode == .entireScreen
            ) {
                coordinator.captureMode = .entireScreen
            }

            ToolbarModeButton(
                icon: "macwindow",
                label: "Window",
                isSelected: coordinator.captureMode == .window
            ) {
                coordinator.captureMode = .window
            }

            Divider()
                .frame(height: 28)

            Button {
                coordinator.confirmAndRecord()
            } label: {
                Text("Record")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(coordinator.hasValidTarget ? Color.red : Color.red.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!coordinator.hasValidTarget)

            Button {
                coordinator.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(toolbarBackground)
    }

    // MARK: - Countdown Phase

    private func countdownContent(remaining: Int) -> some View {
        HStack(spacing: 16) {
            Text("\(remaining)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 44)

            Button {
                coordinator.cancelCountdown()
            } label: {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(toolbarBackground)
    }

    // MARK: - Recording Phase

    private var recordingContent: some View {
        HStack(spacing: 12) {
            // Blinking red dot
            RecordingDot()

            // Duration
            Text(formattedDuration)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)

            if coordinator.isPaused {
                Text("PAUSED")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(3)
            }

            Spacer()

            // Pause/Resume
            Button {
                coordinator.togglePause()
            } label: {
                Image(systemName: coordinator.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .help(coordinator.isPaused ? "Resume" : "Pause")

            // Stop
            Button {
                coordinator.stopRecording()
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
        .background(toolbarBackground)
    }

    // MARK: - Shared

    private var toolbarBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }

    private var formattedDuration: String {
        let duration = coordinator.recordingDuration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Recording Dot (blinking)

private struct RecordingDot: View {
    @State private var isBlinking = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .opacity(isBlinking ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                value: isBlinking
            )
            .onAppear { isBlinking = true }
    }
}

// MARK: - Toolbar Mode Button

private struct ToolbarModeButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(isSelected ? .accentColor : .primary)
            .frame(width: 90, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.15)
                            : (isHovering ? Color.primary.opacity(0.05) : Color.clear)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
