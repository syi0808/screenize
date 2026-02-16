import Foundation
import CoreGraphics

// MARK: - Mouse Position

struct MousePosition: Codable {
    let timestamp: TimeInterval  // Recording start time reference (seconds)
    let x: CGFloat
    let y: CGFloat
    let velocity: CGFloat        // Movement speed (pixels/sec)

    init(timestamp: TimeInterval, x: CGFloat, y: CGFloat, velocity: CGFloat = 0) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.velocity = velocity
    }

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - Click Event

struct MouseClickEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval      // Click start time
    let x: CGFloat
    let y: CGFloat
    let type: ClickType
    let duration: TimeInterval       // Click duration (mouseUp - mouseDown)
    let targetElement: UIElementInfo?  // UI element clicked (via Accessibility API)

    init(
        timestamp: TimeInterval,
        x: CGFloat,
        y: CGFloat,
        type: ClickType,
        duration: TimeInterval = 0.1,
        targetElement: UIElementInfo? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.type = type
        self.duration = duration
        self.targetElement = targetElement
    }

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }

    var endTimestamp: TimeInterval {
        timestamp + duration
    }

    /// Check whether the click is active at a given time
    func isActive(at time: TimeInterval) -> Bool {
        time >= timestamp && time <= endTimestamp
    }

    /// Get a recommended zoom level based on the clicked element's size
    func recommendedZoomLevel(screenArea: CGFloat, minZoom: CGFloat = 1.5, maxZoom: CGFloat = 3.0) -> CGFloat? {
        targetElement?.recommendedZoomLevel(screenArea: screenArea, minZoom: minZoom, maxZoom: maxZoom)
    }
}

// MARK: - Scroll Event

struct ScrollEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval      // Scroll event timestamp
    let x: CGFloat                   // X position of the scroll
    let y: CGFloat                   // Y position of the scroll
    let deltaX: CGFloat              // Horizontal scroll amount (pixels)
    let deltaY: CGFloat              // Vertical scroll amount (pixels)
    let isTrackpad: Bool             // Indicates a trackpad (continuous scrolling)

    init(
        timestamp: TimeInterval,
        x: CGFloat,
        y: CGFloat,
        deltaX: CGFloat,
        deltaY: CGFloat,
        isTrackpad: Bool = false
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.isTrackpad = isTrackpad
    }

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }

    /// Scroll direction (up/down/left/right)
    var direction: ScrollDirection {
        if abs(deltaY) > abs(deltaX) {
            return deltaY > 0 ? .down : .up
        } else {
            return deltaX > 0 ? .right : .left
        }
    }
}

enum ScrollDirection: String, Codable {
    case up, down, left, right
}

// MARK: - Keyboard Event

struct KeyboardEvent: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval      // Keyboard event timestamp
    let type: KeyEventType           // keyDown / keyUp
    let keyCode: UInt16              // macOS key code
    let character: String?           // Entered character (if any)
    let modifiers: KeyModifiers      // Modifier key state

    init(
        timestamp: TimeInterval,
        type: KeyEventType,
        keyCode: UInt16,
        character: String? = nil,
        modifiers: KeyModifiers = KeyModifiers()
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.type = type
        self.keyCode = keyCode
        self.character = character
        self.modifiers = modifiers
    }

    /// Whether the key is a special key (used for shortcuts)
    var isSpecialKey: Bool {
        modifiers.hasAny || keyCode == 36 || keyCode == 53 // Enter, Escape
    }
}

enum KeyEventType: String, Codable {
    case keyDown
    case keyUp
}

struct KeyModifiers: Codable {
    let command: Bool
    let shift: Bool
    let option: Bool
    let control: Bool
    let function: Bool
    let capsLock: Bool

    init(
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false,
        function: Bool = false,
        capsLock: Bool = false
    ) {
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
        self.function = function
        self.capsLock = capsLock
    }

    var hasAny: Bool {
        command || shift || option || control || function
    }

    /// Convert from NSEvent.ModifierFlags
    static func from(flags: UInt) -> Self {
        Self(
            command: (flags & (1 << 20)) != 0,    // NSEvent.ModifierFlags.command
            shift: (flags & (1 << 17)) != 0,      // NSEvent.ModifierFlags.shift
            option: (flags & (1 << 19)) != 0,     // NSEvent.ModifierFlags.option
            control: (flags & (1 << 18)) != 0,    // NSEvent.ModifierFlags.control
            function: (flags & (1 << 23)) != 0,   // NSEvent.ModifierFlags.function
            capsLock: (flags & (1 << 16)) != 0    // NSEvent.ModifierFlags.capsLock
        )
    }
}

// MARK: - Drag Event (selection/drag)

struct DragEvent: Codable, Identifiable {
    let id: UUID
    let startTimestamp: TimeInterval   // Drag start time
    let endTimestamp: TimeInterval     // Drag end time
    let startX: CGFloat                // Start X position
    let startY: CGFloat                // Start Y position
    let endX: CGFloat                  // End X position
    let endY: CGFloat                  // End Y position
    let type: DragType                 // Drag type

    init(
        startTimestamp: TimeInterval,
        endTimestamp: TimeInterval,
        startX: CGFloat,
        startY: CGFloat,
        endX: CGFloat,
        endY: CGFloat,
        type: DragType = .selection
    ) {
        self.id = UUID()
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.startX = startX
        self.startY = startY
        self.endX = endX
        self.endY = endY
        self.type = type
    }

    var startPoint: CGPoint {
        CGPoint(x: startX, y: startY)
    }

    var endPoint: CGPoint {
        CGPoint(x: endX, y: endY)
    }

    var duration: TimeInterval {
        endTimestamp - startTimestamp
    }

    /// Drag distance (pixels)
    var distance: CGFloat {
        let dx = endX - startX
        let dy = endY - startY
        return sqrt(dx * dx + dy * dy)
    }

    /// Check whether a drag is active at a given time
    func isActive(at time: TimeInterval) -> Bool {
        time >= startTimestamp && time <= endTimestamp
    }
}

enum DragType: String, Codable {
    case selection   // Text/file selection
    case move        // Drag and drop
    case resize      // Window resize
}

// MARK: - UI State Sample (for Smart Zoom)

/// UI state sample (1Hz sampling)
/// Periodically records UI element info at the cursor position
struct UIStateSample: Codable, Identifiable {
    let id: UUID
    let timestamp: TimeInterval        // Sample time
    let cursorPosition: CGPoint        // Cursor position (screen coordinates)
    let elementInfo: UIElementInfo?    // UI element at the cursor
    let caretBounds: CGRect?           // Caret bounds for text inputs (if applicable)

    init(
        timestamp: TimeInterval,
        cursorPosition: CGPoint,
        elementInfo: UIElementInfo? = nil,
        caretBounds: CGRect? = nil
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.cursorPosition = cursorPosition
        self.elementInfo = elementInfo
        self.caretBounds = caretBounds
    }

    /// Detect context changes compared to the previous sample
    func detectContextChange(from previousSample: Self?, threshold: CGFloat = 3.0) -> ContextChange {
        guard let previous = previousSample else {
            return .none
        }

        // 1. Check for size change
        if let currentArea = elementInfo?.area,
           let previousArea = previous.elementInfo?.area,
           previousArea > 0 {
            let ratio = currentArea / previousArea
            if ratio > threshold {
                return .expansion(ratio: ratio)
            } else if ratio < 1.0 / threshold {
                return .contraction(ratio: ratio)
            }
        }

        // 2. Check for modal role changes
        let modalRoles: Set<String> = ["AXSheet", "AXDialog", "AXPopover", "AXMenu"]
        if let currentRole = elementInfo?.role,
           modalRoles.contains(currentRole) {
            if let previousRole = previous.elementInfo?.role,
               !modalRoles.contains(previousRole) {
                return .modalOpened(role: currentRole)
            }
        }

        return .none
    }

    /// Types of context changes
    enum ContextChange {
        case none
        case expansion(ratio: CGFloat)      // Element size increased (e.g., modal opened)
        case contraction(ratio: CGFloat)    // Element size decreased
        case modalOpened(role: String)      // Modal opened detected
    }
}

// MARK: - Mouse Recording (full recording data)

struct MouseRecording: Codable {
    let positions: [MousePosition]
    let clicks: [MouseClickEvent]
    let scrollEvents: [ScrollEvent]      // Scroll events
    let keyboardEvents: [KeyboardEvent]  // Keyboard events
    let dragEvents: [DragEvent]          // Drag events
    let uiStateSamples: [UIStateSample]  // UI state samples (1Hz, for Smart Zoom)
    let screenBounds: CGRect             // Capture bounds (screen coordinates)
    let recordingDuration: TimeInterval
    let frameRate: Int
    let scaleFactor: CGFloat             // Video scale factor (screen → video coordinates)
    let createdAt: Date

    init(
        positions: [MousePosition],
        clicks: [MouseClickEvent],
        scrollEvents: [ScrollEvent] = [],
        keyboardEvents: [KeyboardEvent] = [],
        dragEvents: [DragEvent] = [],
        uiStateSamples: [UIStateSample] = [],
        screenBounds: CGRect,
        recordingDuration: TimeInterval,
        frameRate: Int = 60,
        scaleFactor: CGFloat = 1.0
    ) {
        self.positions = positions
        self.clicks = clicks
        self.scrollEvents = scrollEvents
        self.keyboardEvents = keyboardEvents
        self.dragEvents = dragEvents
        self.uiStateSamples = uiStateSamples
        self.screenBounds = screenBounds
        self.recordingDuration = recordingDuration
        self.frameRate = frameRate
        self.scaleFactor = scaleFactor
        self.createdAt = Date()
    }

    // MARK: - Codable

    // MARK: - File Operations

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }

    static func load(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: data)
    }

    // MARK: - Query Methods

    /// Return the mouse position closest to the specified time
    func position(at time: TimeInterval) -> MousePosition? {
        guard !positions.isEmpty else { return nil }

        // Use binary search to find the closest position
        var low = 0
        var high = positions.count - 1

        while low < high {
            let mid = (low + high) / 2
            if positions[mid].timestamp < time {
                low = mid + 1
            } else {
                high = mid
            }
        }

        // Handle edge cases
        if low == 0 {
            return positions[0]
        }
        if low >= positions.count {
            return positions.last
        }

        // Return the closer of the two positions
        let prev = positions[low - 1]
        let next = positions[low]

        if abs(prev.timestamp - time) <= abs(next.timestamp - time) {
            return prev
        }
        return next
    }

    /// Return active click events at a given time
    func activeClicks(at time: TimeInterval) -> [MouseClickEvent] {
        clicks.filter { $0.isActive(at: time) }
    }

    /// Return mouse positions within a time range
    func positions(from startTime: TimeInterval, to endTime: TimeInterval) -> [MousePosition] {
        positions.filter { $0.timestamp >= startTime && $0.timestamp <= endTime }
    }

    // MARK: - Scroll Query Methods

    /// Return scroll events within a time range
    func scrollEvents(from startTime: TimeInterval, to endTime: TimeInterval) -> [ScrollEvent] {
        scrollEvents.filter { $0.timestamp >= startTime && $0.timestamp <= endTime }
    }

    /// Return the nearest scroll event at a given time (within tolerance)
    func scrollEvent(at time: TimeInterval, tolerance: TimeInterval = 0.1) -> ScrollEvent? {
        scrollEvents.first { abs($0.timestamp - time) <= tolerance }
    }

    // MARK: - Keyboard Query Methods

    /// Return keyboard events within a time range
    func keyboardEvents(from startTime: TimeInterval, to endTime: TimeInterval) -> [KeyboardEvent] {
        keyboardEvents.filter { $0.timestamp >= startTime && $0.timestamp <= endTime }
    }

    /// Return the nearest keyboard event at a given time (within tolerance)
    func keyboardEvent(at time: TimeInterval, tolerance: TimeInterval = 0.1) -> KeyboardEvent? {
        keyboardEvents.first { abs($0.timestamp - time) <= tolerance }
    }

    /// Return the modifier key state at a given time
    func modifierState(at time: TimeInterval) -> KeyModifiers {
        // Analyze all key events up to that time to compute current modifier state
        var state = KeyModifiers()
        let relevantEvents = keyboardEvents.filter { $0.timestamp <= time }

        for event in relevantEvents {
            if event.modifiers.hasAny {
                state = event.modifiers
            }
        }

        return state
    }

    // MARK: - Drag Query Methods

    /// Return drag events active at a given time
    func activeDrags(at time: TimeInterval) -> [DragEvent] {
        dragEvents.filter { $0.isActive(at: time) }
    }

    /// Return drag events within a time range
    func dragEvents(from startTime: TimeInterval, to endTime: TimeInterval) -> [DragEvent] {
        dragEvents.filter {
            ($0.startTimestamp >= startTime && $0.startTimestamp <= endTime) ||
            ($0.endTimestamp >= startTime && $0.endTimestamp <= endTime) ||
            ($0.startTimestamp <= startTime && $0.endTimestamp >= endTime)
        }
    }

    // MARK: - UI State Sample Query Methods

    /// Return the UI state sample closest to a given time
    func uiStateSample(at time: TimeInterval) -> UIStateSample? {
        guard !uiStateSamples.isEmpty else { return nil }

        // Use binary search to find the closest sample
        var low = 0
        var high = uiStateSamples.count - 1

        while low < high {
            let mid = (low + high) / 2
            if uiStateSamples[mid].timestamp < time {
                low = mid + 1
            } else {
                high = mid
            }
        }

        // Handle boundary cases
        if low == 0 {
            return uiStateSamples[0]
        }
        if low >= uiStateSamples.count {
            return uiStateSamples.last
        }

        // Return the closer sample
        let prev = uiStateSamples[low - 1]
        let next = uiStateSamples[low]

        if abs(prev.timestamp - time) <= abs(next.timestamp - time) {
            return prev
        }
        return next
    }

    /// Return UI state samples within a time range
    func uiStateSamples(from startTime: TimeInterval, to endTime: TimeInterval) -> [UIStateSample] {
        uiStateSamples.filter { $0.timestamp >= startTime && $0.timestamp <= endTime }
    }
}
