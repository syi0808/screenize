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
            y: screenFrame.minY + 60
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

    override func setFrameOrigin(_ point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(
            NSPoint(x: point.x + frame.width / 2, y: point.y + frame.height / 2)
        ) }) ?? NSScreen.main else {
            super.setFrameOrigin(point)
            return
        }

        let screenFrame = screen.visibleFrame
        let constrained = NSPoint(
            x: min(max(point.x, screenFrame.minX), screenFrame.maxX - frame.width),
            y: min(max(point.y, screenFrame.minY), screenFrame.maxY - frame.height)
        )
        super.setFrameOrigin(constrained)
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
        HStack(spacing: Spacing.sm) {
            ToolbarModeButton(
                icon: "display",
                label: L10n.string("recording.mode.entire_screen", defaultValue: "Entire Screen"),
                isSelected: coordinator.captureMode == .entireScreen
            ) {
                coordinator.captureMode = .entireScreen
            }

            ToolbarModeButton(
                icon: "macwindow",
                label: L10n.string("recording.mode.window", defaultValue: "Window"),
                isSelected: coordinator.captureMode == .window
            ) {
                coordinator.captureMode = .window
            }

            toolbarDivider

            ToolbarSystemAudioToggle()

            ToolbarMicMenu()

            ToolbarFrameRateMenu()

            toolbarDivider

            ToolbarIconButton(
                icon: "xmark",
                label: L10n.string("recording.action.close", defaultValue: "Close"),
                tooltip: L10n.string("recording.action.close", defaultValue: "Close"),
                action: coordinator.cancel
            )
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(toolbarBackground)
    }

    // MARK: - Recording Phase

    private var recordingContent: some View {
        HStack(spacing: Spacing.sm) {
            RecordingDot()

            Text(formattedDuration)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundColor(.white)

            if coordinator.isPaused {
                Text(L10n.string("recording.paused", defaultValue: "PAUSED"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.yellow.opacity(0.15))
                    )
            }

            Spacer(minLength: Spacing.sm)

            // Restart
            ToolbarIconButton(
                icon: "arrow.counterclockwise",
                label: L10n.string("recording.action.restart", defaultValue: "Restart"),
                tooltip: L10n.string("recording.action.restart.tooltip", defaultValue: "Restart Recording"),
                action: coordinator.restartRecording
            )

            // Pause/Resume
            ToolbarIconButton(
                icon: coordinator.isPaused ? "play.fill" : "pause.fill",
                label: coordinator.isPaused
                    ? L10n.string("recording.action.resume", defaultValue: "Resume")
                    : L10n.string("recording.action.pause", defaultValue: "Pause"),
                tooltip: coordinator.isPaused
                    ? L10n.string("recording.action.resume", defaultValue: "Resume")
                    : L10n.string("recording.action.pause", defaultValue: "Pause"),
                action: coordinator.togglePause
            )

            // Delete
            ToolbarIconButton(
                icon: "trash",
                label: L10n.string("recording.action.delete", defaultValue: "Delete"),
                tooltip: L10n.string("recording.action.delete.tooltip", defaultValue: "Delete Recording"),
                action: coordinator.deleteRecording
            )

            // Stop
            ToolbarIconButton(
                icon: "stop.fill",
                label: L10n.string("recording.action.stop", defaultValue: "Stop"),
                tooltip: L10n.string("recording.action.stop.tooltip", defaultValue: "Stop Recording"),
                action: coordinator.stopRecording
            )
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(minWidth: 280)
        .background(toolbarBackground)
    }

    // MARK: - Shared Components

    private var toolbarBackground: some View {
        RoundedRectangle(cornerRadius: CornerRadius.toolbar, style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.toolbar, style: .continuous)
                    .strokeBorder(Color.white.opacity(DesignOpacity.whisper), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(DesignOpacity.whisper), radius: 8, y: 3)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(DesignOpacity.light))
            .frame(width: 0.5, height: 20)
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
    let label: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white.opacity(isHovering ? DesignOpacity.opaque : DesignOpacity.strong))
            .frame(width: 44, height: 36)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? DesignOpacity.whisper : 0))
            )
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
            VStack(spacing: Spacing.xxs) {
                Image(systemName: isEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.system(size: 13, weight: .medium))
                Text(L10n.string("recording.system_audio", defaultValue: "System"))
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white.opacity(isEnabled
                ? (isHovering ? DesignOpacity.opaque : DesignOpacity.strong)
                : (isHovering ? DesignOpacity.strong : DesignOpacity.prominent)))
            .frame(width: 44, height: 36)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? DesignOpacity.whisper : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(
            isEnabled
                ? L10n.string("recording.system_audio.disable", defaultValue: "Disable System Audio")
                : L10n.string("recording.system_audio.enable", defaultValue: "Enable System Audio")
        )
    }
}

// MARK: - Toolbar Mic Menu

private struct ToolbarMicMenu: View {
    @AppStorage("isMicrophoneEnabled") private var isEnabled = false
    @AppStorage("selectedMicrophoneDeviceID") private var selectedDeviceID = ""
    @State private var availableDevices: [AVCaptureDevice] = []
    @State private var isHovering = false

    var body: some View {
        Button {
            showMenu()
        } label: {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: isEnabled ? "mic.fill" : "mic.slash")
                    .font(.system(size: 13, weight: .medium))
                Text(L10n.string("recording.microphone", defaultValue: "Mic"))
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white.opacity(isEnabled
                ? (isHovering ? DesignOpacity.opaque : DesignOpacity.strong)
                : (isHovering ? DesignOpacity.strong : DesignOpacity.prominent)))
            .frame(width: 44, height: 36)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? DesignOpacity.whisper : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(
            isEnabled
                ? L10n.string("recording.microphone.source", defaultValue: "Microphone Source")
                : L10n.string("recording.microphone.enable", defaultValue: "Enable Microphone")
        )
        .onAppear { refreshDevices() }
        .onReceive(
            NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)
        ) { _ in refreshDevices() }
        .onReceive(
            NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected)
        ) { _ in refreshDevices() }
    }

    private func showMenu() {
        refreshDevices()
        let menu = NSMenu()

        for device in availableDevices {
            let item = NSMenuItem(title: device.localizedName, action: nil, keyEquivalent: "")
            item.state = (isEnabled && selectedDeviceID == device.uniqueID) ? .on : .off
            item.target = nil
            let deviceID = device.uniqueID
            item.representedObject = deviceID
            item.action = #selector(ToolbarMenuActionTarget.micDeviceSelected(_:))
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let offItem = NSMenuItem(
            title: L10n.string("recording.microphone.off", defaultValue: "Off"),
            action: #selector(ToolbarMenuActionTarget.micOff(_:)),
            keyEquivalent: ""
        )
        offItem.state = isEnabled ? .off : .on
        menu.addItem(offItem)

        let target = ToolbarMenuActionTarget { deviceID in
            if let deviceID {
                selectedDeviceID = deviceID
                isEnabled = true
            } else {
                isEnabled = false
            }
        }
        // Keep target alive during menu tracking
        objc_setAssociatedObject(menu, "target", target, .OBJC_ASSOCIATION_RETAIN)
        for item in menu.items where !item.isSeparatorItem {
            item.target = target
        }

        let position = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: NSPoint(x: position.x, y: position.y), in: nil)
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

// MARK: - Toolbar Frame Rate Menu

private struct ToolbarFrameRateMenu: View {
    @AppStorage("captureFrameRate") private var frameRate = 60
    @State private var isHovering = false

    private let options = [30, 60, 120, 240]

    var body: some View {
        Button {
            showMenu()
        } label: {
            VStack(spacing: Spacing.xxs) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 13, weight: .medium))
                Text(L10n.renderSettingsFPS(frameRate))
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white.opacity(isHovering ? DesignOpacity.opaque : DesignOpacity.strong))
            .frame(width: 44, height: 36)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? DesignOpacity.whisper : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(L10n.string("recording.frame_rate.tooltip", defaultValue: "Capture Frame Rate"))
    }

    private func showMenu() {
        let menu = NSMenu()

        for fps in options {
            let item = NSMenuItem(
                title: L10n.renderSettingsFPS(fps),
                action: #selector(ToolbarMenuActionTarget.fpsSelected(_:)),
                keyEquivalent: ""
            )
            item.tag = fps
            item.state = (frameRate == fps) ? .on : .off
            menu.addItem(item)
        }

        let target = ToolbarMenuActionTarget { _ in }
        target.fpsHandler = { fps in
            self.frameRate = fps
        }
        objc_setAssociatedObject(menu, "target", target, .OBJC_ASSOCIATION_RETAIN)
        for item in menu.items {
            item.target = target
        }
        let position = NSEvent.mouseLocation
        menu.popUp(positioning: nil, at: NSPoint(x: position.x, y: position.y), in: nil)
    }
}

// MARK: - Menu Action Target

private final class ToolbarMenuActionTarget: NSObject {
    let micHandler: (String?) -> Void
    var fpsHandler: ((Int) -> Void)?

    init(micHandler: @escaping (String?) -> Void) {
        self.micHandler = micHandler
    }

    @objc func micDeviceSelected(_ sender: NSMenuItem) {
        micHandler(sender.representedObject as? String)
    }

    @objc func micOff(_ sender: NSMenuItem) {
        micHandler(nil)
    }

    @objc func fpsSelected(_ sender: NSMenuItem) {
        fpsHandler?(sender.tag)
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
            VStack(spacing: Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white.opacity(isSelected
                ? 1.0
                : (isHovering ? DesignOpacity.strong : DesignOpacity.prominent)))
            .frame(width: 88, height: 36)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if isSelected { return Color.white.opacity(DesignOpacity.faint) }
        if isHovering { return Color.white.opacity(DesignOpacity.whisper) }
        return Color.clear
    }
}
