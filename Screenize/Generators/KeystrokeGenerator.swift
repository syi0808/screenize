import Foundation

/// Keystroke overlay keyframe generator
/// Analyzes recorded keyboard events to auto-generate keystroke overlay keyframes
final class KeystrokeGenerator: KeyframeGenerator {
    typealias Output = KeystrokeTrack

    let name = "Keystroke"
    let description = "Generate overlay keyframes from keyboard input events"

    func generate(from mouseData: MouseDataSource, settings: GeneratorSettings) -> KeystrokeTrack {
        let keystrokeSettings = settings.keystroke
        guard keystrokeSettings.enabled else {
            return KeystrokeTrack(name: "Keystroke (Auto)", keyframes: [])
        }

        var keyframes: [KeystrokeKeyframe] = []
        var events = mouseData.keyboardEvents.filter { $0.eventType == .keyDown }

        // Remove the last event if it matches the recording stop hotkey (Cmd+Shift+2, keyCode 19)
        if let last = events.last,
           last.keyCode == 19,
           last.modifiers.contains(.command),
           last.modifiers.contains(.shift) {
            events.removeLast()
        }

        for event in events {
            // Ignore standalone modifier key presses
            guard let keyName = Self.displayName(for: event.keyCode, character: event.character) else {
                continue
            }

            // Shortcuts-only mode: ignore regular key presses without modifiers
            if keystrokeSettings.shortcutsOnly && !event.modifiers.hasModifiers {
                continue
            }

            // Auto-repeat filtering (same key within minInterval)
            if let lastKF = keyframes.last,
               event.time - lastKF.time < keystrokeSettings.minInterval {
                continue
            }

            let modSymbols = Self.modifierSymbols(from: event.modifiers)
            let displayText = modSymbols + keyName

            let keyframe = KeystrokeKeyframe(
                time: event.time,
                displayText: displayText,
                duration: keystrokeSettings.displayDuration,
                fadeInDuration: keystrokeSettings.fadeInDuration,
                fadeOutDuration: keystrokeSettings.fadeOutDuration
            )
            keyframes.append(keyframe)
        }

        return KeystrokeTrack(name: "Keystroke (Auto)", isEnabled: true, keyframes: keyframes)
    }

    // MARK: - Key Display Name

    /// Convert macOS keyCode to display string
    /// Returns nil for modifier keys (not displayed alone)
    private static func displayName(for keyCode: UInt16, character: String?) -> String? {
        switch keyCode {
        // Special keys
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 71: return "Clear"
        case 76: return "Enter"
        case 117: return "⌦"  // Forward Delete
        // Arrow keys
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        // Function keys
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        // Home/End/Page
        case 115: return "Home"
        case 119: return "End"
        case 116: return "Page Up"
        case 121: return "Page Down"
        // Ignore standalone modifier key presses
        case 54, 55: return nil  // Command (left/right)
        case 56, 60: return nil  // Shift (left/right)
        case 58, 61: return nil  // Option (left/right)
        case 59, 62: return nil  // Control (left/right)
        case 63: return nil      // Fn
        default:
            // Regular character key
            if let char = character, !char.isEmpty {
                // Control modifier produces non-printable control characters (U+0001-U+001A).
                // Recover the intended letter by mapping back to printable ASCII.
                if let scalar = char.unicodeScalars.first, scalar.value < 0x20 {
                    let letterValue = scalar.value + 0x40  // e.g., 0x03 → 0x43 ('C')
                    return Unicode.Scalar(letterValue).map { String($0) }
                }
                return char.uppercased()
            }
            return nil
        }
    }

    // MARK: - Modifier Symbols

    /// Build modifier key symbol string (macOS standard order: ⌃⌥⇧⌘)
    private static func modifierSymbols(from modifiers: KeyboardEventData.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option)  { symbols += "⌥" }
        if modifiers.contains(.shift)   { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }
}
