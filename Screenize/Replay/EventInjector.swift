import Foundation
import CoreGraphics
import AppKit

/// Injects CGEvents into the system for replaying scenario steps.
/// Static creation methods are pure and testable; instance methods perform actual injection.
final class EventInjector {

    private let injectionQueue = DispatchQueue(label: "com.screenize.eventInjector", qos: .userInteractive)
    private var pathTimer: DispatchSourceTimer?
    private var isCancelled = false

    // MARK: - Event Creation (static, testable)

    /// Create a mouse move event to the target position.
    static func createMouseMoveEvent(to point: CGPoint) -> CGEvent? {
        return CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
    }

    /// Create a left click pair (mouseDown + mouseUp). Pass clickCount = 2 for double-click.
    static func createLeftClickEvents(at point: CGPoint, clickCount: Int = 1) -> [CGEvent] {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return []
        }
        down.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        up.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        return [down, up]
    }

    /// Create a right click pair (mouseDown + mouseUp).
    static func createRightClickEvents(at point: CGPoint) -> [CGEvent] {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right),
              let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) else {
            return []
        }
        return [down, up]
    }

    /// Create a mouse down event for the specified button (default: left).
    static func createMouseDownEvent(at point: CGPoint, button: CGMouseButton = .left) -> CGEvent? {
        let type: CGEventType = button == .right ? .rightMouseDown : .leftMouseDown
        return CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
    }

    /// Create a mouse up event for the specified button (default: left).
    static func createMouseUpEvent(at point: CGPoint, button: CGMouseButton = .left) -> CGEvent? {
        let type: CGEventType = button == .right ? .rightMouseUp : .leftMouseUp
        return CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
    }

    /// Create a keyboard event with the given keyCode, modifier flags, and key direction.
    static func createKeyboardEvent(keyCode: UInt16, flags: CGEventFlags, isDown: Bool) -> CGEvent? {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isDown) else {
            return nil
        }
        event.flags = flags
        return event
    }

    /// Create a scroll wheel event using pixel units.
    static func createScrollEvent(deltaX: Int32, deltaY: Int32) -> CGEvent? {
        // axis1 = vertical (deltaY), axis2 = horizontal (deltaX)
        return CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0)
    }

    // MARK: - Event Injection

    /// Post a single CGEvent directly to the system via the HID event tap.
    func injectEvent(_ event: CGEvent) {
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Path Injection (mouse_move replay)

    /// Inject a sequence of mouse move events at 10 ms intervals using a DispatchSourceTimer.
    func injectPath(_ points: [CGPoint]) async {
        guard !points.isEmpty else { return }
        isCancelled = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var index = 0
            let timer = DispatchSource.makeTimerSource(queue: injectionQueue)
            pathTimer = timer

            timer.setEventHandler { [weak self] in
                guard let self = self else {
                    timer.cancel()
                    continuation.resume()
                    return
                }
                guard !self.isCancelled, index < points.count else {
                    timer.cancel()
                    continuation.resume()
                    return
                }
                if let event = EventInjector.createMouseMoveEvent(to: points[index]) {
                    self.injectEvent(event)
                }
                index += 1
            }

            timer.schedule(deadline: .now(), repeating: .milliseconds(10))
            timer.resume()
        }
    }

    /// Cancel an in-progress path injection.
    func cancelPathInjection() {
        isCancelled = true
        pathTimer?.cancel()
    }

    // MARK: - High-Level Step Injection

    /// Move to and perform a left click at the target point.
    func injectClick(at point: CGPoint) async {
        for event in EventInjector.createLeftClickEvents(at: point) {
            injectEvent(event)
        }
    }

    /// Perform a double-click at the target point.
    func injectDoubleClick(at point: CGPoint) async {
        for event in EventInjector.createLeftClickEvents(at: point, clickCount: 2) {
            injectEvent(event)
        }
    }

    /// Perform a right-click at the target point.
    func injectRightClick(at point: CGPoint) async {
        for event in EventInjector.createRightClickEvents(at: point) {
            injectEvent(event)
        }
    }

    /// Inject a mouse down event at the target point (left button by default).
    func injectMouseDown(at point: CGPoint) async {
        if let event = EventInjector.createMouseDownEvent(at: point) {
            injectEvent(event)
        }
    }

    /// Inject a mouse up event at the target point (left button by default).
    func injectMouseUp(at point: CGPoint) async {
        if let event = EventInjector.createMouseUpEvent(at: point) {
            injectEvent(event)
        }
    }

    /// Parse a combo string like "cmd+c" and inject the corresponding keyboard events.
    /// Supported modifiers: cmd, shift, option, ctrl.
    func injectKeyCombo(_ combo: String) async {
        let parts = combo.lowercased().split(separator: "+").map(String.init)
        guard let keyChar = parts.last else { return }
        let modifierStrings = parts.dropLast()

        var flags: CGEventFlags = []
        for mod in modifierStrings {
            switch mod {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift":          flags.insert(.maskShift)
            case "option", "alt":  flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default: break
            }
        }

        guard let keyCode = keyCodeForCharacter(keyChar) else { return }

        if let downEvent = EventInjector.createKeyboardEvent(keyCode: keyCode, flags: flags, isDown: true) {
            injectEvent(downEvent)
        }
        if let upEvent = EventInjector.createKeyboardEvent(keyCode: keyCode, flags: flags, isDown: false) {
            injectEvent(upEvent)
        }
    }

    /// Type text character by character with the specified delay between keystrokes (in milliseconds).
    func injectTypeText(_ text: String, speedMs: Int) async {
        let delayNanoseconds = UInt64(speedMs) * 1_000_000
        for char in text {
            guard let keyCode = keyCodeForCharacter(String(char).lowercased()) else { continue }
            let flags: CGEventFlags = char.isUppercase ? [.maskShift] : []
            if let downEvent = EventInjector.createKeyboardEvent(keyCode: keyCode, flags: flags, isDown: true) {
                injectEvent(downEvent)
            }
            if let upEvent = EventInjector.createKeyboardEvent(keyCode: keyCode, flags: flags, isDown: false) {
                injectEvent(upEvent)
            }
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
        }
    }

    /// Inject a scroll wheel event with the given deltas.
    func injectScroll(deltaX: Int, deltaY: Int) async {
        if let event = EventInjector.createScrollEvent(deltaX: Int32(deltaX), deltaY: Int32(deltaY)) {
            injectEvent(event)
        }
    }

    /// Bring an application to the front by its bundle identifier.
    func injectActivateApp(bundleId: String) async {
        let apps = NSWorkspace.shared.runningApplications
        if let app = apps.first(where: { $0.bundleIdentifier == bundleId }) {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

    // MARK: - Private Helpers

    /// Map a single-character string or named key to its macOS virtual key code.
    private func keyCodeForCharacter(_ character: String) -> UInt16? {
        let keyMap: [String: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
            "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
            "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
            "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
            ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
            " ": 49, "space": 49,
            "return": 36, "enter": 36,
            "tab": 48,
            "delete": 51, "backspace": 51,
            "escape": 53, "esc": 53,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118,
            "f5": 96, "f6": 97, "f7": 98, "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111
        ]
        return keyMap[character]
    }
}
