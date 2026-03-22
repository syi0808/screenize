import Foundation
import CoreGraphics

// MARK: - Scenario

/// Root model for scenario.json — describes a scripted sequence of UI steps.
struct Scenario: Codable, Equatable {
    var version: Int = 1
    /// Bundle identifier of the target application (optional context hint).
    var appContext: String?
    /// Original capture area from rehearsal (CG coordinates). Used to compute
    /// coordinate offsets when the target window has moved since rehearsal.
    var rehearsalBounds: CGRect?
    var steps: [ScenarioStep]

    init(
        version: Int = 1,
        appContext: String? = nil,
        rehearsalBounds: CGRect? = nil,
        steps: [ScenarioStep]
    ) {
        self.version = version
        self.appContext = appContext
        self.rehearsalBounds = rehearsalBounds
        self.steps = steps
    }

    /// Total playback duration in seconds (sum of all step durations).
    var totalDuration: TimeInterval {
        steps.reduce(0.0) { $0 + $1.durationSeconds }
    }

    /// Returns the step that is active at the given cumulative time, or nil if out of range.
    func step(at time: TimeInterval) -> ScenarioStep? {
        guard time >= 0 else { return nil }
        var cursor: TimeInterval = 0
        for step in steps {
            let nextCursor = cursor + step.durationSeconds
            if time < nextCursor {
                return step
            }
            cursor = nextCursor
        }
        return nil
    }

    /// Returns the cumulative start time (in seconds) for the step at the given index.
    /// If the index is out of bounds, returns totalDuration.
    func startTime(forStepAt index: Int) -> TimeInterval {
        guard index >= 0, index < steps.count else { return totalDuration }
        return steps.prefix(index).reduce(0.0) { $0 + $1.durationSeconds }
    }
}

// MARK: - ScenarioStep

/// A single scripted action within a Scenario.
struct ScenarioStep: Codable, Identifiable, Equatable {
    let id: UUID
    var type: StepType
    var description: String
    var durationMs: Int

    // Type-specific fields (all optional; presence depends on step type)

    /// Target UI element — used by click, double_click, right_click, scroll, mouse_down, mouse_up.
    var target: AXTarget?
    /// Mouse movement path — used by mouse_move.
    var path: MousePath?
    /// Raw event time range in the source recording — used by mouse_move (Generate from recording).
    var rawTimeRange: TimeRange?
    /// Application bundle ID — used by activate_app.
    var app: String?
    /// Key combination string (e.g. "cmd+s") — used by keyboard.
    var keyCombo: String?
    /// Text content to type — used by type_text.
    var content: String?
    /// Per-keystroke delay in milliseconds — used by type_text.
    var typingSpeedMs: Int?
    /// Scroll direction — used by scroll.
    var direction: ScrollDirection?
    /// Scroll amount in pixels — used by scroll.
    var amount: Int?

    /// Duration converted to seconds.
    var durationSeconds: TimeInterval { Double(durationMs) / 1000.0 }

    // MARK: Step Types

    enum StepType: String, Codable, CaseIterable {
        case mouseMove = "mouse_move"
        case activateApp = "activate_app"
        case click
        case doubleClick = "double_click"
        case rightClick = "right_click"
        case mouseDown = "mouse_down"
        case mouseUp = "mouse_up"
        case scroll
        case keyboard
        case typeText = "type_text"
        case wait
    }

    enum ScrollDirection: String, Codable {
        case up, down, left, right
    }

    // Memberwise initializer with all optional fields defaulting to nil
    init(
        id: UUID = UUID(),
        type: StepType,
        description: String,
        durationMs: Int,
        target: AXTarget? = nil,
        path: MousePath? = nil,
        rawTimeRange: TimeRange? = nil,
        app: String? = nil,
        keyCombo: String? = nil,
        content: String? = nil,
        typingSpeedMs: Int? = nil,
        direction: ScrollDirection? = nil,
        amount: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.description = description
        self.durationMs = durationMs
        self.target = target
        self.path = path
        self.rawTimeRange = rawTimeRange
        self.app = app
        self.keyCombo = keyCombo
        self.content = content
        self.typingSpeedMs = typingSpeedMs
        self.direction = direction
        self.amount = amount
    }
}

// MARK: - AXTarget

/// Accessibility element reference used to identify a UI target.
/// Coordinates use CG top-left origin.
struct AXTarget: Codable, Equatable {
    /// Accessibility role string (e.g. "AXButton").
    var role: String
    /// AXTitle attribute value.
    var axTitle: String?
    /// AXValue attribute value.
    var axValue: String?
    /// Hierarchy path of AX roles from root to this element.
    var path: [String]
    /// Position hint in 0–1 normalized coordinates (CG top-left origin).
    var positionHint: CGPoint
    /// Absolute screen coordinates in CG pixels (top-left origin).
    var absoluteCoord: CGPoint
}

// MARK: - MousePath

/// Describes the trajectory of a mouse movement step.
enum MousePath: Codable, Equatable {
    /// Let the playback engine choose a natural path automatically.
    case auto
    /// Explicit waypoints in 0–1 normalized coordinates (CG top-left origin).
    case waypoints(points: [CGPoint])

    // MARK: Custom Codable

    // Encodes as:
    //   "auto"  — for the auto case
    //   { "type": "waypoints", "points": [{"x": …, "y": …}, …] }  — for waypoints

    private enum CodingKeys: String, CodingKey {
        case type, points
    }

    init(from decoder: Decoder) throws {
        // Try decoding as a plain string first ("auto")
        if let singleValue = try? decoder.singleValueContainer(),
           let string = try? singleValue.decode(String.self) {
            if string == "auto" {
                self = .auto
                return
            }
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Unknown MousePath string: \(string)")
            )
        }

        // Otherwise expect a keyed container with "type" + "points"
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeName = try container.decode(String.self, forKey: .type)
        switch typeName {
        case "waypoints":
            let points = try container.decode([CGPoint].self, forKey: .points)
            self = .waypoints(points: points)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Unknown MousePath type: \(typeName)")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .auto:
            var container = encoder.singleValueContainer()
            try container.encode("auto")
        case .waypoints(let points):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("waypoints", forKey: .type)
            try container.encode(points, forKey: .points)
        }
    }
}

// MARK: - TimeRange

/// An inclusive millisecond time range within a recording.
struct TimeRange: Codable, Equatable {
    let startMs: Int
    let endMs: Int
}

// MARK: - ScenarioRawEvents

/// Root model for scenario-raw.json — stores raw input events captured during recording.
struct ScenarioRawEvents: Codable, Equatable {
    var version: Int = 1
    /// ISO 8601 timestamp when recording started.
    var startTimestamp: String
    /// Screen area captured (CG coordinates, pixels).
    var captureArea: CGRect
    var events: [RawEvent]

    init(version: Int = 1, startTimestamp: String, captureArea: CGRect, events: [RawEvent]) {
        self.version = version
        self.startTimestamp = startTimestamp
        self.captureArea = captureArea
        self.events = events
    }
}

// MARK: - RawEvent

/// A single raw input event captured during recording.
struct RawEvent: Codable, Equatable {
    /// Milliseconds since recording start.
    let timeMs: Int
    let type: RawEventType

    // Type-specific optional fields
    var x: Double?
    var y: Double?
    /// Mouse button: "left" or "right".
    var button: String?
    var deltaX: Double?
    var deltaY: Double?
    var keyCode: UInt16?
    var characters: String?
    var modifiers: [String]?
    var bundleId: String?
    var appName: String?
    var ax: RawAXInfo?

    enum RawEventType: String, Codable {
        case mouseMove = "mouse_move"
        case mouseDown = "mouse_down"
        case mouseUp = "mouse_up"
        case scroll
        case keyDown = "key_down"
        case keyUp = "key_up"
        case appActivated = "app_activated"
    }

    init(
        timeMs: Int,
        type: RawEventType,
        x: Double? = nil,
        y: Double? = nil,
        button: String? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil,
        keyCode: UInt16? = nil,
        characters: String? = nil,
        modifiers: [String]? = nil,
        bundleId: String? = nil,
        appName: String? = nil,
        ax: RawAXInfo? = nil
    ) {
        self.timeMs = timeMs
        self.type = type
        self.x = x
        self.y = y
        self.button = button
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.keyCode = keyCode
        self.characters = characters
        self.modifiers = modifiers
        self.bundleId = bundleId
        self.appName = appName
        self.ax = ax
    }
}

// MARK: - RawAXInfo

/// Accessibility context captured at the time of a raw event.
struct RawAXInfo: Codable, Equatable {
    let role: String
    let axTitle: String?
    let axValue: String?
    let axDescription: String?
    /// Hierarchy path of AX roles from root to this element.
    let path: [String]
    /// Element frame in screen coordinates (CG pixels, top-left origin).
    let frame: CGRect
}
