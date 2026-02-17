import AppKit
import SwiftUI

/// Countdown overlay panel shown before recording starts
/// Displays above all windows without stealing focus
final class CountdownPanel: NSPanel {

    // MARK: - Properties

    private var countdownHostingView: NSHostingView<CountdownOverlayView>?
    private var countdownValue: Int = 3
    private var timer: Timer?
    private var onComplete: (() -> Void)?
    private var onCancel: (() -> Void)?
    private var localMonitor: Any?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
    }

    // MARK: - Configuration

    private func configurePanel() {
        self.level = .screenSaver
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = false
    }

    private func centerOnMainScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = self.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.midY - panelSize.height / 2
        )
        self.setFrameOrigin(origin)
    }

    // MARK: - Public API

    /// Start the countdown
    @MainActor
    func startCountdown(
        seconds: Int = 3,
        onComplete: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.countdownValue = seconds
        self.onComplete = onComplete
        self.onCancel = onCancel

        // Set up SwiftUI content
        let countdownView = CountdownOverlayView(
            countdownValue: countdownValue,
            totalSeconds: seconds
        )
        let hostingView = NSHostingView(rootView: countdownView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        self.contentView = hostingView
        self.countdownHostingView = hostingView

        // Show the panel
        centerOnMainScreen()
        self.orderFrontRegardless()

        // Install an Escape key monitor
        installEscapeMonitor()

        // Start the timer
        startTimer()
    }

    /// Cancel the countdown and close the panel
    @MainActor
    func cancelCountdown() {
        stopTimer()
        removeEscapeMonitor()
        dismiss()
        onCancel?()
        onCancel = nil
        onComplete = nil
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func tick() {
        countdownValue -= 1

        if countdownValue <= 0 {
            stopTimer()
            removeEscapeMonitor()
            dismiss()
            onComplete?()
            onComplete = nil
            onCancel = nil
        } else {
            updateCountdownView()
        }
    }

    @MainActor
    private func updateCountdownView() {
        let updatedView = CountdownOverlayView(
            countdownValue: countdownValue,
            totalSeconds: 3
        )
        countdownHostingView?.rootView = updatedView
    }

    @MainActor
    private func dismiss() {
        self.orderOut(nil)
    }

    // MARK: - Escape Key Monitor

    private func installEscapeMonitor() {
        // Panel cannot become key, so use a local monitor instead of global
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                Task { @MainActor in
                    self?.cancelCountdown()
                }
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    // Does not take focus
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Countdown SwiftUI View

struct CountdownOverlayView: View {
    let countdownValue: Int
    let totalSeconds: Int

    var body: some View {
        ZStack {
            // Translucent circular background
            Circle()
                .fill(Color.black.opacity(0.75))
                .frame(width: 160, height: 160)

            // Progress ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 150, height: 150)
                .rotationEffect(.degrees(-90))

            // Countdown number
            Text("\(countdownValue)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 200, height: 200)
    }

    private var progress: CGFloat {
        CGFloat(countdownValue) / CGFloat(totalSeconds)
    }
}
