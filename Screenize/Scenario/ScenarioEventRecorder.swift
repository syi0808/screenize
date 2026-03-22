import Foundation
import AppKit

// MARK: - ScenarioEventRecorder

/// Records raw input events during rehearsal mode.
/// Runs alongside MouseDataRecorder; produces a ScenarioRawEvents value on stop.
final class ScenarioEventRecorder {

    // MARK: - Dependencies

    private let eventMonitor = EventMonitorManager()
    private let accessibilityInspector = AccessibilityInspector()
    private let axQueue = DispatchQueue(label: "com.screenize.scenario.ax", qos: .userInitiated)

    // MARK: - State

    private var events: [RawEvent] = []
    private var startTime: Date?
    private var captureArea: CGRect = .zero
    private var isPaused = false
    private var pauseStartTime: Int?    // timeMs when pause started
    private var totalPauseMs: Int = 0   // accumulated pause time

    // AX debounce
    private var lastAXQueryTimeMs: Int = 0

    // Mouse move throttle (~30 Hz; one sample per 33 ms)
    private var lastMouseMoveTimeMs: Int = 0

    private let lock = NSLock()

    // MARK: - Public API

    /// Start recording events for the given capture area.
    func startRecording(captureArea: CGRect) {
        lock.withLock {
            self.captureArea = captureArea
            self.events = []
            self.totalPauseMs = 0
            self.isPaused = false
            self.pauseStartTime = nil
            self.lastAXQueryTimeMs = 0
            self.lastMouseMoveTimeMs = 0
            self.startTime = Date()
        }
        setupEventMonitors()
    }

    /// Pause recording. Events received while paused are discarded.
    func pauseRecording() {
        lock.withLock {
            guard !isPaused, let start = startTime else { return }
            isPaused = true
            pauseStartTime = Self.calculateTimeMs(since: start, totalPauseMs: totalPauseMs)
        }
    }

    /// Resume a previously paused recording. Elapsed pause time is accumulated.
    func resumeRecording() {
        lock.withLock {
            guard isPaused, let start = startTime else { return }
            if let pauseStart = pauseStartTime {
                let now = Self.calculateTimeMs(since: start, totalPauseMs: totalPauseMs)
                totalPauseMs += (now - pauseStart)
            }
            isPaused = false
            pauseStartTime = nil
        }
    }

    /// Stop recording and return all collected events.
    func stopRecording() -> ScenarioRawEvents {
        eventMonitor.removeAllMonitors()
        // Note: NSWorkspace notification observer is removed in deinit per SwiftLint convention.

        let (capturedEvents, area, start) = lock.withLock {
            (events, captureArea, startTime ?? Date())
        }

        // Sort by timeMs to fix out-of-order events caused by async AX queries
        let sortedEvents = capturedEvents.sorted { $0.timeMs < $1.timeMs }

        let formatter = ISO8601DateFormatter()
        return ScenarioRawEvents(
            startTimestamp: formatter.string(from: start),
            captureArea: area,
            events: sortedEvents
        )
    }

    // MARK: - Time Calculation

    /// Current recording time in ms, accounting for accumulated pauses.
    static func calculateTimeMs(since startTime: Date, totalPauseMs: Int) -> Int {
        let elapsed = Date().timeIntervalSince(startTime)
        return max(0, Int(elapsed * 1000) - totalPauseMs)
    }

    /// Returns true when an AX query should be skipped (debounce interval: 50 ms).
    static func shouldDebounceAX(currentTimeMs: Int, lastAXQueryTimeMs: Int) -> Bool {
        return (currentTimeMs - lastAXQueryTimeMs) < 50
    }

    // MARK: - Event Monitor Setup

    private func setupEventMonitors() {
        // Mouse down (left + right)
        eventMonitor.addMonitor(identifier: "scenarioMouseDown", events: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleMouseDown(event)
        }

        // Mouse up (left + right)
        eventMonitor.addMonitor(identifier: "scenarioMouseUp", events: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
        }

        // Mouse movement — throttled to ~30 Hz inside handler
        eventMonitor.addMonitor(identifier: "scenarioMouseMove",
                                events: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.handleMouseMove(event)
        }

        // Scroll wheel
        eventMonitor.addMonitor(identifier: "scenarioScroll", events: [.scrollWheel]) { [weak self] event in
            self?.handleScroll(event)
        }

        // Key down
        eventMonitor.addMonitor(identifier: "scenarioKeyDown", events: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }

        // Key up
        eventMonitor.addMonitor(identifier: "scenarioKeyUp", events: [.keyUp]) { [weak self] event in
            self?.handleKeyUp(event)
        }

        // App activation — via NSWorkspace (not NSEvent)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared
        )
    }

    // MARK: - Event Handlers

    private func handleMouseDown(_ nsEvent: NSEvent) {
        guard let (timeMs, start, pauseMs) = guardActive() else { return }
        let cgPoint = convertToCG(NSEvent.mouseLocation)

        var rawEvent = RawEvent(
            timeMs: timeMs,
            type: .mouseDown,
            x: cgPoint.x,
            y: cgPoint.y,
            button: nsEvent.type == .rightMouseDown ? "right" : "left"
        )

        let shouldQueryAX = lock.withLock { () -> Bool in
            if !Self.shouldDebounceAX(currentTimeMs: timeMs, lastAXQueryTimeMs: lastAXQueryTimeMs) {
                lastAXQueryTimeMs = timeMs
                return true
            }
            return false
        }

        if shouldQueryAX {
            let screenPoint = cgPoint
            axQueue.async { [weak self] in
                guard let self else { return }
                if let axInfo = self.accessibilityInspector.scenarioElementAt(screenPoint: screenPoint) {
                    rawEvent.ax = RawAXInfo(
                        role: axInfo.element.role,
                        axTitle: axInfo.element.title,
                        axValue: axInfo.axValue,
                        axDescription: axInfo.axDescription,
                        path: axInfo.path,
                        frame: axInfo.element.frame
                    )
                }
                self.recordEvent(rawEvent)
            }
            return
        }

        _ = (start, pauseMs)  // suppress unused-variable warning; values captured above
        recordEvent(rawEvent)
    }

    private func handleMouseUp(_ nsEvent: NSEvent) {
        guard let (timeMs, _, _) = guardActive() else { return }
        let cgPoint = convertToCG(NSEvent.mouseLocation)
        let rawEvent = RawEvent(
            timeMs: timeMs,
            type: .mouseUp,
            x: cgPoint.x,
            y: cgPoint.y,
            button: nsEvent.type == .rightMouseUp ? "right" : "left"
        )
        recordEvent(rawEvent)
    }

    private func handleMouseMove(_ nsEvent: NSEvent) {
        guard let (timeMs, _, _) = guardActive() else { return }

        // Throttle to ~30 Hz (33 ms between samples)
        let shouldRecord = lock.withLock { () -> Bool in
            guard (timeMs - lastMouseMoveTimeMs) >= 33 else { return false }
            lastMouseMoveTimeMs = timeMs
            return true
        }
        guard shouldRecord else { return }

        let cgPoint = convertToCG(NSEvent.mouseLocation)
        let rawEvent = RawEvent(timeMs: timeMs, type: .mouseMove, x: cgPoint.x, y: cgPoint.y)
        recordEvent(rawEvent)
    }

    private func handleScroll(_ nsEvent: NSEvent) {
        guard let (timeMs, _, _) = guardActive() else { return }
        let cgPoint = convertToCG(NSEvent.mouseLocation)
        var rawEvent = RawEvent(
            timeMs: timeMs,
            type: .scroll,
            x: cgPoint.x,
            y: cgPoint.y,
            deltaX: Double(nsEvent.scrollingDeltaX),
            deltaY: Double(nsEvent.scrollingDeltaY)
        )

        let shouldQueryAX = lock.withLock { () -> Bool in
            if !Self.shouldDebounceAX(currentTimeMs: timeMs, lastAXQueryTimeMs: lastAXQueryTimeMs) {
                lastAXQueryTimeMs = timeMs
                return true
            }
            return false
        }

        if shouldQueryAX {
            let screenPoint = cgPoint
            axQueue.async { [weak self] in
                guard let self else { return }
                if let axInfo = self.accessibilityInspector.scenarioElementAt(screenPoint: screenPoint) {
                    rawEvent.ax = RawAXInfo(
                        role: axInfo.element.role,
                        axTitle: axInfo.element.title,
                        axValue: axInfo.axValue,
                        axDescription: axInfo.axDescription,
                        path: axInfo.path,
                        frame: axInfo.element.frame
                    )
                }
                self.recordEvent(rawEvent)
            }
            return
        }

        recordEvent(rawEvent)
    }

    private func handleKeyDown(_ nsEvent: NSEvent) {
        guard let (timeMs, _, _) = guardActive() else { return }
        let rawEvent = RawEvent(
            timeMs: timeMs,
            type: .keyDown,
            keyCode: nsEvent.keyCode,
            characters: nsEvent.charactersIgnoringModifiers,
            modifiers: modifierStrings(from: nsEvent.modifierFlags)
        )
        recordEvent(rawEvent)
    }

    private func handleKeyUp(_ nsEvent: NSEvent) {
        guard let (timeMs, _, _) = guardActive() else { return }
        let rawEvent = RawEvent(
            timeMs: timeMs,
            type: .keyUp,
            keyCode: nsEvent.keyCode,
            characters: nsEvent.charactersIgnoringModifiers,
            modifiers: modifierStrings(from: nsEvent.modifierFlags)
        )
        recordEvent(rawEvent)
    }

    @objc private func handleAppActivated(_ notification: Notification) {
        guard let (timeMs, _, _) = guardActive() else { return }
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        let rawEvent = RawEvent(
            timeMs: timeMs,
            type: .appActivated,
            bundleId: app?.bundleIdentifier,
            appName: app?.localizedName
        )
        recordEvent(rawEvent)
    }

    // MARK: - Helpers

    /// Returns (timeMs, startTime, totalPauseMs) when recording is active, nil otherwise.
    private func guardActive() -> (Int, Date, Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard !isPaused, let start = startTime else { return nil }
        let timeMs = Self.calculateTimeMs(since: start, totalPauseMs: totalPauseMs)
        return (timeMs, start, totalPauseMs)
    }

    private func recordEvent(_ event: RawEvent) {
        lock.withLock { events.append(event) }
    }

    /// Convert AppKit screen point (bottom-left origin) to CG pixel point (top-left origin).
    private func convertToCG(_ appKitPoint: CGPoint) -> CGPoint {
        guard let screenHeight = NSScreen.main?.frame.height else { return appKitPoint }
        return CGPoint(x: appKitPoint.x, y: screenHeight - appKitPoint.y)
    }

    /// Map NSEvent modifier flags to an array of readable strings.
    private func modifierStrings(from flags: NSEvent.ModifierFlags) -> [String]? {
        var result: [String] = []
        if flags.contains(.command) { result.append("cmd") }
        if flags.contains(.shift) { result.append("shift") }
        if flags.contains(.option) { result.append("opt") }
        if flags.contains(.control) { result.append("ctrl") }
        if flags.contains(.function) { result.append("fn") }
        return result.isEmpty ? nil : result
    }

    deinit {
        eventMonitor.removeAllMonitors()
        NotificationCenter.default.removeObserver(self)
    }
}
