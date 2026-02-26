import Foundation
import AppKit
import CoreGraphics

/// Records mouse positions, clicks, scrolls, keyboard, and drag events during capture
final class MouseDataRecorder {
    // MARK: - Properties

    private var positions: [MousePosition] = []
    private var uiStateSamples: [UIStateSample] = []    // UI state samples (for Smart Zoom)

    private var isRecording = false
    private var recordingStartTime: TimeInterval = 0
    private var screenBounds: CGRect = .zero
    private var scaleFactor: CGFloat = 1.0  // Video scale factor
    private var coordinateConverter: CoordinateConverter?

    // Position sampling
    private var positionTimer: Timer?
    private var sampleInterval: TimeInterval = 1.0 / 60.0  // Default 60Hz, configurable

    // UI state sampling (for Smart Zoom)
    private var uiStateSampleTimer: Timer?
    private let uiStateSampleInterval: TimeInterval = 1.0  // 1Hz sampling

    // Event handlers
    private var clickHandler: ClickEventHandler?
    private var scrollHandler: ScrollEventHandler?
    private var keyboardHandler: KeyboardEventHandler?
    private var dragHandler: DragEventHandler?

    // Event monitor
    private let eventMonitor = EventMonitorManager()

    // For velocity calculation
    private var lastPosition: CGPoint = .zero
    private var lastPositionTime: TimeInterval = 0

    // Accessibility Inspector (for dynamic zoom)
    private let accessibilityInspector = AccessibilityInspector()

    private let lock = NSLock()

    // MARK: - Recording Control

    func startRecording(screenBounds: CGRect, scaleFactor: CGFloat = 1.0, captureFrameRate: Int = 60) {
        guard !isRecording else { return }

        // Cap mouse sampling at 120Hz (Timer resolution degrades beyond this)
        let mouseHz = min(captureFrameRate, 120)
        self.sampleInterval = 1.0 / Double(mouseHz)
        self.screenBounds = screenBounds
        self.scaleFactor = scaleFactor
        self.positions.removeAll()
        self.uiStateSamples.removeAll()
        self.recordingStartTime = ProcessInfo.processInfo.systemUptime
        self.lastPosition = NSEvent.mouseLocation
        self.lastPositionTime = recordingStartTime

        // Initialize CoordinateConverter
        let screenHeight = NSScreen.main?.frame.height ?? 0
        self.coordinateConverter = CoordinateConverter(
            captureBounds: screenBounds,
            screenHeight: screenHeight,
            scaleFactor: scaleFactor
        )

        // Initialize event handlers
        setupEventHandlers()
        setupEventMonitors()
        startPositionSampling()
        startUIStateSampling()

        isRecording = true
        Log.tracking.info("Mouse recording started (scaleFactor: \(scaleFactor))")
    }

    func stopRecording() -> MouseRecording {
        guard isRecording else {
            return MouseRecording(
                positions: [],
                clicks: [],
                scrollEvents: [],
                keyboardEvents: [],
                dragEvents: [],
                uiStateSamples: [],
                screenBounds: .zero,
                recordingDuration: 0,
                scaleFactor: 1.0
            )
        }

        isRecording = false
        stopPositionSampling()
        stopUIStateSampling()
        eventMonitor.removeAllMonitors()
        keyboardHandler?.stop()

        let duration = ProcessInfo.processInfo.systemUptime - recordingStartTime

        // Handle any unfinished clicks and drags
        clickHandler?.finalizePendingClicks()
        dragHandler?.finalizePendingDrag(screenBounds: screenBounds)

        // Lock to safely capture final arrays (timer callback may still be in-flight)
        lock.lock()
        let finalPositions = positions
        let finalUISamples = uiStateSamples
        lock.unlock()

        let recording = MouseRecording(
            positions: finalPositions,
            clicks: clickHandler?.getClicks() ?? [],
            scrollEvents: scrollHandler?.getScrollEvents() ?? [],
            keyboardEvents: keyboardHandler?.getKeyboardEvents() ?? [],
            dragEvents: dragHandler?.getDragEvents() ?? [],
            uiStateSamples: finalUISamples,
            screenBounds: screenBounds,
            recordingDuration: duration,
            scaleFactor: scaleFactor
        )

        let clicks = clickHandler?.getClicks().count ?? 0
        let scrolls = scrollHandler?.getScrollEvents().count ?? 0
        let keyboards = keyboardHandler?.getKeyboardEvents().count ?? 0
        let drags = dragHandler?.getDragEvents().count ?? 0

        Log.tracking.info("Mouse recording stopped - positions: \(finalPositions.count), clicks: \(clicks), scrolls: \(scrolls), keyboards: \(keyboards), drags: \(drags), UI samples: \(finalUISamples.count) (scaleFactor: \(self.scaleFactor))")

        // Position validation summary
        if !finalPositions.isEmpty {
            let ys = finalPositions.map { $0.y }
            let xs = finalPositions.map { $0.x }
            let minY = ys.min()!, maxY = ys.max()!, avgY = ys.reduce(0, +) / CGFloat(ys.count)
            let minX = xs.min()!, maxX = xs.max()!, avgX = xs.reduce(0, +) / CGFloat(xs.count)
            Log.tracking.debug("Position summary: X range [\(minX)...\(maxX)] avg=\(avgX), Y range [\(minY)...\(maxY)] avg=\(avgY)")
            Log.tracking.debug("screenBounds=\(String(describing: self.screenBounds)) (origin.y=\(self.screenBounds.origin.y), size=\(String(describing: self.screenBounds.size)))")
            if maxY > screenBounds.height * 1.05 {
                Log.tracking.warning("Y positions exceed screenBounds.height! Origin conversion likely incorrect.")
            }
        }

        // Clean up handlers
        clickHandler = nil
        scrollHandler = nil
        keyboardHandler = nil
        dragHandler = nil

        return recording
    }

    func pauseRecording() {
        stopPositionSampling()
        stopUIStateSampling()
    }

    func resumeRecording() {
        guard isRecording else { return }
        startPositionSampling()
        startUIStateSampling()
    }

    // MARK: - Event Handlers Setup

    private func setupEventHandlers() {
        clickHandler = ClickEventHandler(
            accessibilityInspector: accessibilityInspector,
            coordinateConverter: { [weak self] in self?.coordinateConverter },
            recordingStartTime: { [weak self] in self?.recordingStartTime ?? 0 }
        )

        scrollHandler = ScrollEventHandler(
            coordinateConverter: { [weak self] in self?.coordinateConverter },
            recordingStartTime: { [weak self] in self?.recordingStartTime ?? 0 }
        )

        keyboardHandler = KeyboardEventHandler(
            recordingStartTime: { [weak self] in self?.recordingStartTime ?? 0 }
        )

        dragHandler = DragEventHandler(
            coordinateConverter: { [weak self] in self?.coordinateConverter },
            recordingStartTime: { [weak self] in self?.recordingStartTime ?? 0 }
        )
    }

    // MARK: - Position Sampling

    private func startPositionSampling() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.sampleMousePosition()
        }
        RunLoop.current.add(positionTimer!, forMode: .common)
    }

    private func stopPositionSampling() {
        positionTimer?.invalidate()
        positionTimer = nil
    }

    // MARK: - UI State Sampling (for Smart Zoom)

    private func startUIStateSampling() {
        uiStateSampleTimer?.invalidate()
        // Collect the first sample immediately
        sampleUIState()

        uiStateSampleTimer = Timer.scheduledTimer(withTimeInterval: uiStateSampleInterval, repeats: true) { [weak self] _ in
            self?.sampleUIState()
        }
        RunLoop.current.add(uiStateSampleTimer!, forMode: .common)
    }

    private func stopUIStateSampling() {
        uiStateSampleTimer?.invalidate()
        uiStateSampleTimer = nil
    }

    /// Sample UI element information at the current cursor position
    private func sampleUIState() {
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timestamp = currentTime - recordingStartTime
        let mouseLocation = NSEvent.mouseLocation

        // Convert the screen coordinates to capture bounds
        let relativePosition = convertToScreenBounds(mouseLocation)

        // Use Accessibility API to gather UI element info under the cursor
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let accessibilityPoint = CGPoint(x: mouseLocation.x, y: screenHeight - mouseLocation.y)
        let elementInfo = accessibilityInspector.elementAt(screenPoint: accessibilityPoint)

        // Collect caret position for text input elements
        let caretBounds = accessibilityInspector.focusedElementCaretBounds()

        let sample = UIStateSample(
            timestamp: timestamp,
            cursorPosition: relativePosition,
            elementInfo: elementInfo,
            caretBounds: caretBounds
        )

        lock.lock()
        uiStateSamples.append(sample)
        lock.unlock()
    }

    private func sampleMousePosition() {
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timestamp = currentTime - recordingStartTime
        let mouseLocation = NSEvent.mouseLocation

        // Convert screen coordinates to capture bounds
        let relativePosition = convertToScreenBounds(mouseLocation)

        // Compute velocity
        let dt = currentTime - lastPositionTime
        var velocity: CGFloat = 0
        if dt > 0 {
            let dx = mouseLocation.x - lastPosition.x
            let dy = mouseLocation.y - lastPosition.y
            velocity = sqrt(dx * dx + dy * dy) / CGFloat(dt)
        }

        lock.lock()
        if positions.count < 3 {
            Log.tracking.debug("Mouse sample #\(self.positions.count): mouseLocation=\(String(describing: mouseLocation)), relative=\(String(describing: relativePosition)), screenBounds=\(String(describing: self.screenBounds))")
        }
        positions.append(MousePosition(
            timestamp: timestamp,
            x: relativePosition.x,
            y: relativePosition.y,
            velocity: velocity
        ))
        lock.unlock()

        lastPosition = mouseLocation
        lastPositionTime = currentTime
    }

    // MARK: - Event Monitors

    private func setupEventMonitors() {
        // Mouse click down events
        eventMonitor.addMonitor(
            identifier: "clickDown",
            events: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self = self else { return }
            self.clickHandler?.handleMouseDown(event, screenBounds: self.screenBounds)
        }

        // Mouse click up events
        eventMonitor.addMonitor(
            identifier: "clickUp",
            events: [.leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            self?.clickHandler?.handleMouseUp(event)
        }

        // Scroll events
        eventMonitor.addMonitor(
            identifier: "scroll",
            events: .scrollWheel
        ) { [weak self] event in
            guard let self = self else { return }
            self.scrollHandler?.handleScroll(event, screenBounds: self.screenBounds)
        }

        // Keyboard events (CGEventTap)
        keyboardHandler?.start()

        // Drag events
        eventMonitor.addMonitor(
            identifier: "drag",
            events: .leftMouseDragged
        ) { [weak self] event in
            guard let self = self else { return }
            self.dragHandler?.handleDrag(event, screenBounds: self.screenBounds)
        }
    }

    // MARK: - Coordinate Conversion

    private func convertToScreenBounds(_ screenPosition: CGPoint) -> CGPoint {
        guard let converter = coordinateConverter else {
        // Fallback: compute manually (before converter initialization)
            let relativeX = screenPosition.x - screenBounds.origin.x
            let relativeY = screenPosition.y - screenBounds.origin.y
            return CGPoint(x: relativeX, y: relativeY)
        }

        let capturePixel = converter.screenToCapturePixel(screenPosition)
        return capturePixel.toCGPoint()
    }

    deinit {
        _ = stopRecording()
    }
}

// MARK: - File URL Helper

extension MouseDataRecorder {
    /// Generate the mouse data URL corresponding to a video URL
    static func mouseDataURL(for videoURL: URL) -> URL {
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        let directory = videoURL.deletingLastPathComponent()
        return directory.appendingPathComponent("\(baseName)_mouse.json")
    }
}
