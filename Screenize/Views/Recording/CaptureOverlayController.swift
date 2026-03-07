import AppKit
import ScreenCaptureKit
import SwiftUI

/// Manages overlay windows for the capture toolbar's visual feedback
/// - Entire Screen mode: dim overlays on all screens, un-dim hovered screen
/// - Window mode: blue tint overlay on hovered window
@MainActor
final class CaptureOverlayController {

    // MARK: - Callbacks

    var onScreenHovered: ((SCDisplay?) -> Void)?
    var onWindowHovered: ((SCWindow?) -> Void)?
    var onRecordClicked: (() -> Void)?

    // MARK: - Private Properties

    private var screenOverlays: [CGDirectDisplayID: NSWindow] = [:]
    private var windowHighlightWindow: NSWindow?
    private var recordOverlayPanel: NSPanel?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var currentMode: CaptureMode = .window

    private var availableDisplays: [SCDisplay] = []
    private var availableWindows: [SCWindow] = []

    private var lastHoveredDisplayID: CGDirectDisplayID?
    private var lastHoveredWindowID: CGWindowID?

    /// Bundle IDs excluded from window detection
    private static let excludedBundleIDs: Set<String> = [
        Bundle.main.bundleIdentifier ?? "com.screenize.Screenize",
        "com.apple.dock",
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
    ]

    // MARK: - Public API

    /// Activate overlays and start mouse tracking
    func activate(mode: CaptureMode, displays: [SCDisplay], windows: [SCWindow]) {
        self.currentMode = mode
        self.availableDisplays = displays
        self.availableWindows = windows

        createOverlays(for: mode)
        startMouseTracking()

        // Trigger initial hover with current cursor position
        handleMouseMoved(NSEvent.mouseLocation)
    }

    /// Switch between entire screen and window modes
    func updateMode(_ mode: CaptureMode) {
        guard mode != currentMode else { return }
        removeOverlays()
        currentMode = mode
        lastHoveredDisplayID = nil
        lastHoveredWindowID = nil
        createOverlays(for: mode)
    }

    /// Remove all overlays and stop tracking
    func deactivate() {
        stopMouseTracking()
        removeOverlays()
        lastHoveredDisplayID = nil
        lastHoveredWindowID = nil
    }

    // MARK: - Overlay Creation

    private func createOverlays(for mode: CaptureMode) {
        switch mode {
        case .entireScreen:
            createScreenOverlays()
        case .window:
            createWindowHighlight()
        }
    }

    private func createScreenOverlays() {
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.3)
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.hasShadow = false
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()

            let id = displayID(for: screen)
            screenOverlays[id] = window
        }
    }

    private func createWindowHighlight() {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        window.isOpaque = false
        window.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15)
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.hasShadow = false
        windowHighlightWindow = window
    }

    private func removeOverlays() {
        for overlay in screenOverlays.values {
            overlay.orderOut(nil)
        }
        screenOverlays.removeAll()

        windowHighlightWindow?.orderOut(nil)
        windowHighlightWindow = nil

        recordOverlayPanel?.orderOut(nil)
        recordOverlayPanel = nil
    }

    // MARK: - Record Overlay Button

    private func createRecordOverlayPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let buttonView = RecordOverlayButtonView { [weak self] in
            self?.onRecordClicked?()
        }
        let hosting = NSHostingView(rootView: buttonView)
        hosting.frame = NSRect(x: 0, y: 0, width: 72, height: 72)
        panel.contentView = hosting

        return panel
    }

    private func showRecordOverlay(centeredIn frame: NSRect) {
        // Recreate panel each time for entrance animation replay
        recordOverlayPanel?.orderOut(nil)
        recordOverlayPanel = nil

        let panel = createRecordOverlayPanel()
        self.recordOverlayPanel = panel

        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - panelSize.width / 2,
            y: frame.midY - panelSize.height / 2
        )
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func hideRecordOverlay() {
        recordOverlayPanel?.orderOut(nil)
    }

    // MARK: - Mouse Tracking

    private func startMouseTracking() {
        // Global monitor captures mouse movement from other apps
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseMoved(NSEvent.mouseLocation)
            }
        }

        // Local monitor captures mouse movement within Screenize windows (e.g. toolbar panel)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMoved(NSEvent.mouseLocation)
            }
            return event
        }
    }

    private func stopMouseTracking() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }
    }

    private func handleMouseMoved(_ point: NSPoint) {
        switch currentMode {
        case .entireScreen:
            handleScreenHover(at: point)
        case .window:
            handleWindowHover(at: point)
        }
    }

    // MARK: - Screen Detection

    private func handleScreenHover(at point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return
        }

        let hoveredID = displayID(for: screen)
        guard hoveredID != lastHoveredDisplayID else { return }

        lastHoveredDisplayID = hoveredID
        updateScreenOverlays(hoveredDisplayID: hoveredID)
        showRecordOverlay(centeredIn: screen.frame)

        let scDisplay = matchDisplay(for: screen)
        onScreenHovered?(scDisplay)
    }

    private func updateScreenOverlays(hoveredDisplayID: CGDirectDisplayID?) {
        for (id, overlay) in screenOverlays {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                if id == hoveredDisplayID {
                    overlay.animator().backgroundColor = NSColor.clear
                } else {
                    overlay.animator().backgroundColor = NSColor.black.withAlphaComponent(0.3)
                }
            }
        }
    }

    private func matchDisplay(for screen: NSScreen) -> SCDisplay? {
        let screenID = displayID(for: screen)
        return availableDisplays.first { $0.displayID == screenID }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            ?? CGMainDisplayID()
    }

    // MARK: - Window Detection

    private func handleWindowHover(at point: NSPoint) {
        // Convert AppKit coords (bottom-left origin) to CG coords (top-left origin)
        guard let primaryScreen = NSScreen.screens.first else { return }
        let cgPoint = CGPoint(x: point.x, y: primaryScreen.frame.height - point.y)

        guard let windowInfo = detectWindow(at: cgPoint) else {
            if lastHoveredWindowID != nil {
                lastHoveredWindowID = nil
                windowHighlightWindow?.orderOut(nil)
                hideRecordOverlay()
                onWindowHovered?(nil)
            }
            return
        }

        let (windowID, cgBounds) = windowInfo
        guard windowID != lastHoveredWindowID else { return }

        lastHoveredWindowID = windowID

        // Convert CG bounds (top-left origin) back to AppKit coords (bottom-left origin)
        let appKitFrame = NSRect(
            x: cgBounds.origin.x,
            y: primaryScreen.frame.height - cgBounds.origin.y - cgBounds.height,
            width: cgBounds.width,
            height: cgBounds.height
        )

        // Position and show the highlight window
        if let highlight = windowHighlightWindow {
            highlight.setFrame(appKitFrame, display: true, animate: false)
            highlight.orderFrontRegardless()
        }

        showRecordOverlay(centeredIn: appKitFrame)

        let scWindow = availableWindows.first { $0.windowID == windowID }
        onWindowHovered?(scWindow)
    }

    /// Detect the topmost qualifying window at a given CG point
    private func detectWindow(at cgPoint: CGPoint) -> (CGWindowID, CGRect)? {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for info in windowInfoList {
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }

            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            guard bounds.contains(cgPoint) else { continue }

            // Skip small windows
            guard bounds.width >= 100, bounds.height >= 100 else { continue }

            // Check owning application
            guard let app = NSRunningApplication(processIdentifier: ownerPID) else { continue }

            // Skip non-regular apps (daemons, agents)
            guard app.activationPolicy == .regular else { continue }

            // Skip excluded bundles
            if let bundleID = app.bundleIdentifier,
               Self.excludedBundleIDs.contains(bundleID) {
                continue
            }

            // Skip windows with excluded titles
            if let title = info[kCGWindowName as String] as? String {
                let lower = title.lowercased()
                if lower.hasPrefix("display ") || lower.contains("backstop") {
                    continue
                }
            }

            // Found a qualifying window
            return (windowID, bounds)
        }

        return nil
    }
}

// MARK: - Record Overlay Button View

private struct RecordOverlayButtonView: View {
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @State private var appeared = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer glass ring
                Circle()
                    .strokeBorder(
                        Color.white.opacity(isHovering ? 0.4 : 0.25),
                        lineWidth: 1.5
                    )
                    .frame(width: 56, height: 56)

                // Red gradient fill
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 52, height: 52)

                // Inner record dot
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            .shadow(
                color: isHovering ? Color.red.opacity(0.4) : Color.clear,
                radius: 12
            )
            .scaleEffect(isPressed ? 0.95 : (isHovering ? 1.08 : 1.0))
            .scaleEffect(appeared ? 1.0 : 0.5)
            .opacity(appeared ? 1.0 : 0)
        }
        .buttonStyle(.plain)
        .frame(width: 72, height: 72)
        .onHover { hovering in
            withMotionSafeAnimation(AnimationTokens.quick) {
                isHovering = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withMotionSafeAnimation(AnimationTokens.quick) { isPressed = true }
                }
                .onEnded { _ in
                    withMotionSafeAnimation(AnimationTokens.quick) { isPressed = false }
                }
        )
        .onAppear {
            withMotionSafeAnimation(AnimationTokens.springy) {
                appeared = true
            }
        }
    }
}
