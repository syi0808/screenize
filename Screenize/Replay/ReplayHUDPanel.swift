import AppKit
import SwiftUI

// MARK: - ReplayHUDPanel

/// Floating HUD panel shown during scenario replay.
/// Displays replay progress, error states, manual mode, rehearsal timer, and countdown.
/// Uses a global ESC key monitor since Screenize windows are minimized during replay.
@available(macOS 15.0, *)
final class ReplayHUDPanel: NSPanel {

    // MARK: - Properties

    private var hostingView: NSHostingView<ReplayHUDView>?
    private var escapeMonitor: Any?

    // MARK: - Initialization

    init(player: ScenarioPlayer) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        setupContent(player: player)
        positionOnScreen()
        installEscapeMonitor(player: player)
    }

    // MARK: - Configuration

    private func configurePanel() {
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
    }

    private func setupContent(player: ScenarioPlayer) {
        let view = ReplayHUDView(player: player)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 48)
        contentView = hosting
        hostingView = hosting
    }

    private func positionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.maxY - 60
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Escape Key Monitor

    private func installEscapeMonitor(player: ScenarioPlayer) {
        // Use GLOBAL monitor (not local) — Screenize windows are minimized during replay
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC
                Task { @MainActor in
                    await player.stop()
                }
            }
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
        orderFrontRegardless()
    }

    @MainActor
    func dismiss() {
        removeEscapeMonitor()
        orderOut(nil)
    }

    // MARK: - Frame Clamping

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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Cleanup

    deinit {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}

// MARK: - ReplayHUDView

@available(macOS 15.0, *)
struct ReplayHUDView: View {
    @ObservedObject var player: ScenarioPlayer
    @State private var rehearsalDuration: TimeInterval = 0
    @State private var rehearsalTimer: Timer?
    @State private var previousState: ScenarioPlayer.PlaybackState = .idle

    var body: some View {
        Group {
            switch player.state {
            case .idle, .completed:
                EmptyView()

            case .playing:
                playingContent

            case .error(let stepIndex, let message):
                errorContent(stepIndex: stepIndex, message: message)

            case .paused(.doManually):
                manualContent

            case .paused(.userRequested):
                EmptyView() // ESC stops — not used for pause

            case .waitingForUser:
                waitingContent

            case .countdown(let n):
                countdownContent(n: n)

            case .rehearsing:
                rehearsingContent
            }
        }
        .frame(minWidth: 300, maxWidth: 500)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        .onChange(of: player.state) { newState in
            if newState == .waitingForUser, previousState != .waitingForUser {
                NSSound.beep()
            }
            previousState = newState
        }
    }

    // MARK: - Playing

    private var playingContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.fill").foregroundStyle(.green)
            Text("Replaying").fontWeight(.medium)
            Text("Step \(player.currentStepIndex + 1)/\(player.totalStepCount)")
                .font(.caption).foregroundStyle(.secondary)
            Text(player.currentStepDescription)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Stop") {
                Task { await player.stop() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Error

    private func errorContent(stepIndex: Int, message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Step \(stepIndex + 1) failed").fontWeight(.medium).font(.caption)
                Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Skip") { player.skip() }.buttonStyle(.bordered).font(.caption)
            Button("Do Manually") { player.doManually() }.buttonStyle(.bordered).font(.caption)
            Button("Stop") {
                Task { await player.stop() }
            }.buttonStyle(.bordered).font(.caption)
        }
    }

    // MARK: - Manual Mode

    private var manualContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
            Text("Manual mode — Step \(player.currentStepIndex + 1)").fontWeight(.medium).font(.caption)
            Spacer()
            Button("Continue") { player.continueAfterManual() }.buttonStyle(.borderedProminent).font(.caption)
            Button("Stop") {
                Task { await player.stop() }
            }.buttonStyle(.bordered).font(.caption)
        }
    }

    // MARK: - Waiting for User (Re-rehearse)

    private var waitingContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard").foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your turn").fontWeight(.medium)
                Text("Step \(player.currentStepIndex + 1) — \(player.currentStepDescription)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                player.startRehearsal()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent).font(.caption)
            Button("Stop") {
                Task { await player.stop() }
            }.buttonStyle(.bordered).font(.caption)
        }
    }

    // MARK: - Countdown

    private func countdownContent(n: Int) -> some View {
        HStack {
            Spacer()
            Text("\(n)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.teal)
            Spacer()
        }
    }

    // MARK: - Rehearsing

    private var rehearsingContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard").foregroundStyle(.teal)
            Text("Rehearsing").fontWeight(.medium)
            // Pulsing green dot
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .opacity(rehearsalDuration.truncatingRemainder(dividingBy: 1.2) < 0.6 ? 1.0 : 0.3)
            Text(formatDuration(rehearsalDuration))
                .font(.caption.monospacedDigit())
            Spacer()
            Button("Stop") {
                Task { await player.stop() }
            }.buttonStyle(.bordered).font(.caption)
        }
        .onAppear {
            rehearsalDuration = 0
            rehearsalTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                rehearsalDuration += 0.1
            }
        }
        .onDisappear {
            rehearsalTimer?.invalidate()
            rehearsalTimer = nil
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
