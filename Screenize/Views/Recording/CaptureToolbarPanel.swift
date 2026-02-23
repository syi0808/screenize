import AppKit
import AVFoundation
import SwiftUI

/// Unified floating panel for the entire capture/recording lifecycle
/// Transitions between: selecting target → recording
final class CaptureToolbarPanel: NSPanel {

    // MARK: - Properties

    private var hostingView: NSHostingView<CaptureToolbarView>?
    private var escapeMonitor: Any?
    private weak var coordinator: CaptureToolbarCoordinator?

    // MARK: - Initialization

    init(coordinator: CaptureToolbarCoordinator) {
        self.coordinator = coordinator
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 56),
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
        self.hasShadow = false
        self.isMovableByWindowBackground = true
    }

    private func setupContent(coordinator: CaptureToolbarCoordinator) {
        let view = CaptureToolbarView(coordinator: coordinator)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 280, height: 56)
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
                    if coordinator.toolbarPhase == .selecting {
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
            case .recording:
                recordingContent
            }
        }
        .motionSafeAnimation(.spring(response: 0.35, dampingFraction: 0.85), value: coordinator.toolbarPhase)
    }

    // MARK: - Selecting Phase

    private var selectingContent: some View {
        HStack(spacing: 8) {
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

            toolbarDivider

            ToolbarSystemAudioToggle()

            ToolbarMicMenu()

            toolbarDivider

            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(toolbarBackground)
    }

    // MARK: - Recording Phase

    private var recordingContent: some View {
        HStack(spacing: 10) {
            RecordingDot()

            Text(formattedDuration)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundColor(.white)

            if coordinator.isPaused {
                Text("PAUSED")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.yellow.opacity(0.15))
                    )
            }

            Spacer(minLength: 8)

            // Pause/Resume
            ToolbarIconButton(
                icon: coordinator.isPaused ? "play.fill" : "pause.fill",
                tooltip: coordinator.isPaused ? "Resume" : "Pause",
                action: coordinator.togglePause
            )

            // Stop — distinctive red square
            Button {
                coordinator.stopRecording()
            } label: {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop Recording")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: 220)
        .background(toolbarBackground)
    }

    // MARK: - Shared Components

    private var toolbarBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.ultraThickMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 0.5, height: 20)
    }

    private var closeButton: some View {
        Button {
            coordinator.cancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            .frame(width: 8, height: 8)
            .opacity(isBlinking ? 0.3 : 1.0)
            .motionSafeAnimation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isBlinking
            )
            .onAppear { isBlinking = true }
    }
}

// MARK: - Toolbar Icon Button

private struct ToolbarIconButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(isHovering ? 0.9 : 0.7))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tooltip)
    }
}

// MARK: - Toolbar System Audio Toggle

private struct ToolbarSystemAudioToggle: View {
    @AppStorage("isSystemAudioEnabled") private var isEnabled = true
    @State private var isHovering = false

    var body: some View {
        Button {
            isEnabled.toggle()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.system(size: 13, weight: .medium))
                Text("System")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.7) : .white.opacity(0.5))
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isEnabled ? "Disable System Audio" : "Enable System Audio")
    }
}

// MARK: - Toolbar Mic Menu

private struct ToolbarMicMenu: View {
    @AppStorage("isMicrophoneEnabled") private var isEnabled = false
    @AppStorage("selectedMicrophoneDeviceID") private var selectedDeviceID = ""
    @State private var availableDevices: [AVCaptureDevice] = []
    @State private var isHovering = false

    var body: some View {
        Menu {
            ForEach(availableDevices, id: \.uniqueID) { device in
                Button {
                    selectedDeviceID = device.uniqueID
                    isEnabled = true
                } label: {
                    if isEnabled && selectedDeviceID == device.uniqueID {
                        Label(device.localizedName, systemImage: "checkmark")
                    } else {
                        Text(device.localizedName)
                    }
                }
            }

            Divider()

            Button {
                isEnabled = false
            } label: {
                if !isEnabled {
                    Label("Off", systemImage: "checkmark")
                } else {
                    Text("Off")
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isEnabled ? "mic.fill" : "mic.slash")
                    .font(.system(size: 13, weight: .medium))
                Text("Mic")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isEnabled ? .red : .white.opacity(0.5))
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovering = $0 }
        .help(isEnabled ? "Microphone Source" : "Enable Microphone")
        .onAppear { refreshDevices() }
        .onReceive(
            NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)
        ) { _ in refreshDevices() }
        .onReceive(
            NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected)
        ) { _ in refreshDevices() }
    }

    private func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        availableDevices = discovery.devices
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
                    .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            .frame(width: 88, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected { return Color.white.opacity(0.15) }
        if isHovering { return Color.white.opacity(0.08) }
        return Color.clear
    }
}
