import Foundation

// MARK: - Polyrecorder Event Stream Models (Screen Studio Compatible)

/// Mouse movement event in polyrecorder event stream format.
/// Coordinates: display-local pixel, top-left origin, y increasing downwards.
struct PolyMouseMoveEvent: Codable {
    let type: String
    let processTimeMs: Int64
    let unixTimeMs: Int64
    let x: Double
    let y: Double
    let cursorId: String?
    let activeModifiers: [String]
    let button: String?
}

/// Mouse click event in polyrecorder event stream format.
struct PolyMouseClickEvent: Codable {
    let type: String
    let processTimeMs: Int64
    let unixTimeMs: Int64
    let x: Double
    let y: Double
    let button: String
    let cursorId: String?
    let activeModifiers: [String]

    // Element info at click position (optional for backward compat with old JSON)
    let elementRole: String?
    let elementSubrole: String?
    let elementTitle: String?
    let elementAppName: String?
    let elementFrameX: Double?
    let elementFrameY: Double?
    let elementFrameW: Double?
    let elementFrameH: Double?
    let elementIsClickable: Bool?
}

/// Keystroke event in polyrecorder event stream format.
struct PolyKeystrokeEvent: Codable {
    let type: String
    let processTimeMs: Int64
    let unixTimeMs: Int64
    let keyCode: UInt16?
    let character: String?
    let isARepeat: Bool
    let activeModifiers: [String]
}

/// UI state sample event in polyrecorder event stream format.
/// Captures UI element information at cursor position (1Hz sampling).
struct PolyUIStateEvent: Codable {
    let processTimeMs: Int64
    let unixTimeMs: Int64
    let cursorX: Double        // pixel, top-left origin
    let cursorY: Double
    let elementRole: String?
    let elementSubrole: String?
    let elementTitle: String?
    let elementAppName: String?
    let elementFrameX: Double?
    let elementFrameY: Double?
    let elementFrameW: Double?
    let elementFrameH: Double?
    let elementIsClickable: Bool?
    let caretX: Double?
    let caretY: Double?
    let caretW: Double?
    let caretH: Double?
}

// MARK: - Active Modifiers Conversion

enum ActiveModifiersConverter {
    static func toStrings(from modifiers: KeyModifiers) -> [String] {
        var result: [String] = []
        if modifiers.command { result.append("command") }
        if modifiers.shift { result.append("shift") }
        if modifiers.option { result.append("option") }
        if modifiers.control { result.append("control") }
        if modifiers.function { result.append("function") }
        if modifiers.capsLock { result.append("capsLock") }
        return result
    }
}
