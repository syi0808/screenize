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
    private let sampleInterval: TimeInterval = 1.0 / 60.0  // 60Hz sampling

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

    func startRecording(screenBounds: CGRect, scaleFactor: CGFloat = 1.0) {
        guard !isRecording else { return }

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
        print("🖱️ [MouseDataRecorder] Recording started (scaleFactor: \(scaleFactor))")
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

        let recording = MouseRecording(
            positions: positions,
            clicks: clickHandler?.getClicks() ?? [],
            scrollEvents: scrollHandler?.getScrollEvents() ?? [],
            keyboardEvents: keyboardHandler?.getKeyboardEvents() ?? [],
            dragEvents: dragHandler?.getDragEvents() ?? [],
            uiStateSamples: uiStateSamples,
            screenBounds: screenBounds,
            recordingDuration: duration,
            scaleFactor: scaleFactor
        )

        let clicks = clickHandler?.getClicks().count ?? 0
        let scrolls = scrollHandler?.getScrollEvents().count ?? 0
        let keyboards = keyboardHandler?.getKeyboardEvents().count ?? 0
        let drags = dragHandler?.getDragEvents().count ?? 0

        print("🖱️ [MouseDataRecorder] Recording stopped - positions: \(positions.count), clicks: \(clicks), scrolls: \(scrolls), keyboards: \(keyboards), drags: \(drags), UI samples: \(uiStateSamples.count) (scaleFactor: \(scaleFactor))")

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
