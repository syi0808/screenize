import Foundation

/// Emits a KeystrokeTrackV2 from EventTimeline keyDown events.
struct KeystrokeTrackEmitter {

    // MARK: - Public API

    /// Emit a keystroke track from event timeline keyboard events.
    static func emit(
        eventTimeline: EventTimeline,
        duration: TimeInterval,
        settings: KeystrokeEmissionSettings
    ) -> KeystrokeTrackV2 {
        guard settings.enabled else {
            return KeystrokeTrackV2(name: "Keystroke (Smart V2)", segments: [])
        }

        guard duration > 0 else {
            return KeystrokeTrackV2(name: "Keystroke (Smart V2)", segments: [])
        }

        // Extract keyDown events from timeline
        let allEvents = eventTimeline.events(in: 0...duration)
        var keyDownEvents: [(time: TimeInterval, data: KeyboardEventData)] = []
        for event in allEvents {
            if case .keyDown(let data) = event.kind {
                keyDownEvents.append((time: event.time, data: data))
            }
        }

        // Remove trailing recording stop hotkey (Cmd+Shift+2, keyCode 19)
        if let last = keyDownEvents.last,
           last.data.modifiers.contains(.command),
           last.data.modifiers.contains(.shift) {
            if last.data.keyCode == 19 {
                // New recordings: exact keyCode match
                keyDownEvents.removeLast()
            } else if last.data.keyCode == 0 && (duration - last.time) < 0.5 {
                // Old recordings (keyCode lost): Cmd+Shift near recording end
                keyDownEvents.removeLast()
            }
        }

        var segments: [KeystrokeSegment] = []

        for entry in keyDownEvents {
            // Ignore standalone modifier key presses
            guard let keyName = displayName(
                for: entry.data.keyCode,
                character: entry.data.character
            ) else {
                continue
            }

            // Shortcuts-only mode: skip regular keys without modifiers
            if settings.shortcutsOnly && !entry.data.modifiers.hasModifiers {
                continue
            }

            // Auto-repeat filtering (same key within minInterval)
            if let lastSeg = segments.last,
               entry.time - lastSeg.startTime < settings.minInterval {
                continue
            }

            let modSymbols = modifierSymbols(from: entry.data.modifiers)
            let displayText = modSymbols + keyName

            let segment = KeystrokeSegment(
                startTime: entry.time,
                endTime: entry.time + settings.displayDuration,
                displayText: displayText,
                fadeInDuration: settings.fadeInDuration,
                fadeOutDuration: settings.fadeOutDuration
            )
            segments.append(segment)
        }

        return KeystrokeTrackV2(
            name: "Keystroke (Smart V2)",
            isEnabled: true,
            segments: segments
        )
    }

    // MARK: - Key Display Name

    /// Convert macOS keyCode to display string.
    /// Returns nil for modifier keys (not displayed alone).
    static func displayName(
        for keyCode: UInt16, character: String?
    ) -> String? {
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

    /// Build modifier key symbol string (macOS standard order: ⌃⌥⇧⌘).
    static func modifierSymbols(
        from modifiers: KeyboardEventData.ModifierFlags
    ) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option)  { symbols += "⌥" }
        if modifiers.contains(.shift)   { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }
}
