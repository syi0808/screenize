import XCTest
@testable import Screenize

final class KeystrokeTrackEmitterTests: XCTestCase {

    // MARK: - Disabled

    func test_emit_disabled_returnsEmptyTrack() {
        var settings = KeystrokeEmissionSettings()
        settings.enabled = false
        let timeline = makeTimeline(events: [])
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertTrue(track.segments.isEmpty)
    }

    // MARK: - Zero Duration

    func test_emit_zeroDuration_returnsEmptyTrack() {
        let settings = KeystrokeEmissionSettings()
        let timeline = makeTimeline(events: [])
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 0, settings: settings
        )
        XCTAssertTrue(track.segments.isEmpty)
    }

    // MARK: - No Events

    func test_emit_noKeyDownEvents_returnsEmptyTrack() {
        let settings = KeystrokeEmissionSettings()
        let timeline = makeTimeline(events: [])
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertTrue(track.segments.isEmpty)
    }

    // MARK: - Shortcuts Only Mode

    func test_emit_shortcutsOnly_ignoresRegularKeys() {
        var settings = KeystrokeEmissionSettings()
        settings.shortcutsOnly = true
        let events = [
            makeKeyDownEvent(time: 1.0, keyCode: 0, character: "a", modifiers: [])
        ]
        let timeline = makeTimeline(events: events)
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertTrue(track.segments.isEmpty)
    }

    func test_emit_shortcutsOnly_includesModifiedKeys() {
        var settings = KeystrokeEmissionSettings()
        settings.shortcutsOnly = true
        let events = [
            makeKeyDownEvent(time: 1.0, keyCode: 0, character: "a", modifiers: [.command])
        ]
        let timeline = makeTimeline(events: events)
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertEqual(track.segments.count, 1)
        XCTAssertEqual(track.segments[0].displayText, "⌘A")
    }

    func test_emit_shortcutsOnlyFalse_includesRegularKeys() {
        var settings = KeystrokeEmissionSettings()
        settings.shortcutsOnly = false
        let events = [
            makeKeyDownEvent(time: 1.0, keyCode: 0, character: "a", modifiers: [])
        ]
        let timeline = makeTimeline(events: events)
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertEqual(track.segments.count, 1)
        XCTAssertEqual(track.segments[0].displayText, "A")
    }

    // MARK: - Recording Stop Hotkey Removal

    func test_emit_removesTrailingRecordingStopHotkey() {
        var settings = KeystrokeEmissionSettings()
        settings.shortcutsOnly = false
        let events = [
            makeKeyDownEvent(time: 1.0, keyCode: 0, character: "a", modifiers: []),
            // Cmd+Shift+2 (keyCode 19) — recording stop hotkey
            makeKeyDownEvent(time: 9.0, keyCode: 19, character: nil, modifiers: [.command, .shift])
        ]
        let timeline = makeTimeline(events: events)
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        // Only the "A" key should remain
        XCTAssertEqual(track.segments.count, 1)
        XCTAssertEqual(track.segments[0].displayText, "A")
    }

    // MARK: - Auto-Repeat Filtering

    func test_emit_autoRepeatFiltering_skipsRapidKeys() {
        var settings = KeystrokeEmissionSettings()
        settings.shortcutsOnly = false
        settings.minInterval = 0.1
        let events = [
            makeKeyDownEvent(time: 1.0, keyCode: 0, character: "a", modifiers: []),
            makeKeyDownEvent(time: 1.03, keyCode: 0, character: "a", modifiers: []),
            makeKeyDownEvent(time: 1.06, keyCode: 0, character: "a", modifiers: [])
        ]
        let timeline = makeTimeline(events: events)
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        // Only first key kept (others within minInterval)
        XCTAssertEqual(track.segments.count, 1)
    }

    func test_emit_autoRepeatFiltering_allowsSpacedKeys() {
        var settings = KeystrokeEmissionSettings()
        settings.shortcutsOnly = false
        settings.minInterval = 0.05
        let events = [
            makeKeyDownEvent(time: 1.0, keyCode: 0, character: "a", modifiers: []),
            makeKeyDownEvent(time: 2.0, keyCode: 0, character: "b", modifiers: [])
        ]
        let timeline = makeTimeline(events: events)
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertEqual(track.segments.count, 2)
    }

    // MARK: - Modifier Key Filtering

    func test_emit_ignoresStandaloneModifierKeys() {
        var settings = KeystrokeEmissionSettings()
        settings.shortcutsOnly = false
        let events = [
            // keyCode 55 = Command key
            makeKeyDownEvent(time: 1.0, keyCode: 55, character: nil, modifiers: [.command])
        ]
        let timeline = makeTimeline(events: events)
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertTrue(track.segments.isEmpty)
    }

    // MARK: - Special Keys

    func test_emit_specialKeys_displayCorrectName() {
        var settings = KeystrokeEmissionSettings()
        settings.shortcutsOnly = false
        let events = [
            makeKeyDownEvent(time: 1.0, keyCode: 36, character: nil, modifiers: []),  // Return
            makeKeyDownEvent(time: 2.0, keyCode: 48, character: nil, modifiers: []),  // Tab
            makeKeyDownEvent(time: 3.0, keyCode: 49, character: nil, modifiers: []),  // Space
            makeKeyDownEvent(time: 4.0, keyCode: 53, character: nil, modifiers: [])   // Escape
        ]
        let timeline = makeTimeline(events: events)
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertEqual(track.segments.count, 4)
        XCTAssertEqual(track.segments[0].displayText, "Return")
        XCTAssertEqual(track.segments[1].displayText, "Tab")
        XCTAssertEqual(track.segments[2].displayText, "Space")
        XCTAssertEqual(track.segments[3].displayText, "Escape")
    }

    // MARK: - Modifier Symbols

    func test_modifierSymbols_allModifiers() {
        let flags: KeyboardEventData.ModifierFlags = [.control, .option, .shift, .command]
        let symbols = KeystrokeTrackEmitter.modifierSymbols(from: flags)
        XCTAssertEqual(symbols, "⌃⌥⇧⌘")
    }

    func test_modifierSymbols_commandOnly() {
        let flags: KeyboardEventData.ModifierFlags = [.command]
        let symbols = KeystrokeTrackEmitter.modifierSymbols(from: flags)
        XCTAssertEqual(symbols, "⌘")
    }

    func test_modifierSymbols_noModifiers() {
        let flags = KeyboardEventData.ModifierFlags([])
        let symbols = KeystrokeTrackEmitter.modifierSymbols(from: flags)
        XCTAssertEqual(symbols, "")
    }

    // MARK: - Display Name

    func test_displayName_regularCharacter() {
        let name = KeystrokeTrackEmitter.displayName(for: 0, character: "a")
        XCTAssertEqual(name, "A")
    }

    func test_displayName_controlCharacter_recoversLetter() {
        // Control+C produces Unicode value 0x03 → should recover to "C"
        let ctrlC = String(Unicode.Scalar(0x03))
        let name = KeystrokeTrackEmitter.displayName(for: 8, character: ctrlC)
        XCTAssertEqual(name, "C")
    }

    func test_displayName_modifierKeyCode_returnsNil() {
        let name = KeystrokeTrackEmitter.displayName(for: 55, character: nil)
        XCTAssertNil(name)
    }

    func test_displayName_arrowKeys() {
        XCTAssertEqual(KeystrokeTrackEmitter.displayName(for: 123, character: nil), "←")
        XCTAssertEqual(KeystrokeTrackEmitter.displayName(for: 124, character: nil), "→")
        XCTAssertEqual(KeystrokeTrackEmitter.displayName(for: 125, character: nil), "↓")
        XCTAssertEqual(KeystrokeTrackEmitter.displayName(for: 126, character: nil), "↑")
    }

    func test_displayName_functionKeys() {
        XCTAssertEqual(KeystrokeTrackEmitter.displayName(for: 122, character: nil), "F1")
        XCTAssertEqual(KeystrokeTrackEmitter.displayName(for: 111, character: nil), "F12")
    }

    // MARK: - Segment Timing

    func test_emit_segmentTiming_matchesSettings() {
        var settings = KeystrokeEmissionSettings()
        settings.shortcutsOnly = false
        settings.displayDuration = 2.0
        settings.fadeInDuration = 0.2
        settings.fadeOutDuration = 0.4
        let events = [
            makeKeyDownEvent(time: 3.0, keyCode: 0, character: "x", modifiers: [])
        ]
        let timeline = makeTimeline(events: events)
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertEqual(track.segments.count, 1)
        XCTAssertEqual(track.segments[0].startTime, 3.0, accuracy: 0.001)
        XCTAssertEqual(track.segments[0].endTime, 5.0, accuracy: 0.001)
        XCTAssertEqual(track.segments[0].fadeInDuration, 0.2, accuracy: 0.001)
        XCTAssertEqual(track.segments[0].fadeOutDuration, 0.4, accuracy: 0.001)
    }

    // MARK: - Track Name

    func test_emit_trackName() {
        let settings = KeystrokeEmissionSettings()
        let timeline = makeTimeline(events: [])
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertEqual(track.name, "Keystroke (Smart V2)")
    }

    // MARK: - Multiple Modifier Combinations

    func test_emit_controlOptionShiftCommand_displayText() {
        var settings = KeystrokeEmissionSettings()
        settings.shortcutsOnly = true
        let events = [
            makeKeyDownEvent(
                time: 1.0, keyCode: 0, character: "a",
                modifiers: [.control, .option, .shift, .command]
            )
        ]
        let timeline = makeTimeline(events: events)
        let track = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline, duration: 10.0, settings: settings
        )
        XCTAssertEqual(track.segments.count, 1)
        XCTAssertEqual(track.segments[0].displayText, "⌃⌥⇧⌘A")
    }

    // MARK: - Helpers

    private func makeKeyDownEvent(
        time: TimeInterval,
        keyCode: UInt16,
        character: String?,
        modifiers: KeyboardEventData.ModifierFlags
    ) -> UnifiedEvent {
        let data = KeyboardEventData(
            time: time,
            keyCode: keyCode,
            eventType: .keyDown,
            modifiers: modifiers,
            character: character
        )
        return UnifiedEvent(
            time: time,
            kind: .keyDown(data),
            position: NormalizedPoint(x: 0.5, y: 0.5),
            metadata: EventMetadata()
        )
    }

    private func makeTimeline(events: [UnifiedEvent]) -> EventTimeline {
        let duration = events.map(\.time).max() ?? 10.0
        return EventTimeline(events: events, duration: duration)
    }
}
