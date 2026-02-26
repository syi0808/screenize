import Foundation
import CoreGraphics

/// Keyboard event handler (uses CGEventTap)
final class KeyboardEventHandler {

    // MARK: - Properties

    private var keyboardEvents: [KeyboardEvent] = []
    private let lock = NSLock()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let recordingStartTime: () -> TimeInterval

    // MARK: - Initialization

    init(recordingStartTime: @escaping () -> TimeInterval) {
        self.recordingStartTime = recordingStartTime
    }

    deinit {
        stop()
    }

    // MARK: - Event Tap Setup

    func start() {
        // Check and request Input Monitoring permissions
        if #available(macOS 14.0, *) {
            if !CGPreflightListenEventAccess() {
                CGRequestListenEventAccess()
                Log.tracking.warning("Input Monitoring permission requested - allow it in System Settings and restart the app")
                return
            }
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo = userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let handler = Unmanaged<KeyboardEventHandler>.fromOpaque(userInfo).takeUnretainedValue()
                handler.handleKeyboardEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        ) else {
            Log.tracking.error("Failed to create keyboard event tap - enable Screenize under System Settings > Privacy & Security > Input Monitoring")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Log.tracking.info("Keyboard event tap configured")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
    }

    // MARK: - Event Handling

    private func handleKeyboardEvent(type: CGEventType, event: CGEvent) {
        let currentTime = ProcessInfo.processInfo.systemUptime
        let timestamp = currentTime - recordingStartTime()

        let eventType: KeyEventType
        switch type {
        case .keyDown:
            eventType = .keyDown
        case .keyUp:
            eventType = .keyUp
        default:
            return
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let modifiers = KeyModifiers(
            command: flags.contains(.maskCommand),
            shift: flags.contains(.maskShift),
            option: flags.contains(.maskAlternate),
            control: flags.contains(.maskControl),
            function: flags.contains(.maskSecondaryFn),
            capsLock: flags.contains(.maskAlphaShift)
        )

        // Extract string from the UniChar buffer
        var unicodeString = [UniChar](repeating: 0, count: 4)
        var length: Int = 0
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &unicodeString)
        let character = length > 0 ? String(utf16CodeUnits: unicodeString, count: length) : nil

        let keyboardEvent = KeyboardEvent(
            timestamp: timestamp,
            type: eventType,
            keyCode: keyCode,
            character: character,
            modifiers: modifiers
        )

        lock.lock()
        keyboardEvents.append(keyboardEvent)
        lock.unlock()
    }

    // MARK: - Results

    func getKeyboardEvents() -> [KeyboardEvent] {
        lock.lock()
        defer { lock.unlock() }
        return keyboardEvents
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        keyboardEvents.removeAll()
    }
}
