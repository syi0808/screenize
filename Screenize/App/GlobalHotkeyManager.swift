import Foundation
import Carbon

/// Global hotkey manager using the Carbon RegisterEventHotKey API
/// Controls recording start/stop with Cmd+Shift+2 without needing app focus
@MainActor
final class GlobalHotkeyManager {

    // MARK: - Singleton

    static let shared = GlobalHotkeyManager()

    // MARK: - Properties

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var onHotkeyPressed: (() -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Register the global hotkey and callback
    func register(onToggleRecording: @escaping () -> Void) {
        self.onHotkeyPressed = onToggleRecording
        registerCarbonHotkey()
    }

    /// Unregister the hotkey (usually at app shutdown)
    func unregister() {
        if let hotkeyRef = hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }
        if let handlerRef = eventHandlerRef {
            RemoveEventHandler(handlerRef)
            self.eventHandlerRef = nil
        }
    }

    // MARK: - Carbon Event Registration

    private func registerCarbonHotkey() {
        // Define the event type
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Install the event handler
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            Log.ui.error("Failed to install event handler: \(status)")
            return
        }

        // Register the Cmd+Shift+2 hotkey
        let hotkeyID = EventHotKeyID(
            signature: OSType(0x4653_4B59),  // 'FSKY'
            id: 1
        )

        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_2),
            UInt32(cmdKey | shiftKey),
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard regStatus == noErr else {
            Log.ui.error("Failed to register hotkey: \(regStatus)")
            return
        }
    }

    /// Called from the Carbon callback
    nonisolated fileprivate func handleHotkeyEvent() {
        Task { @MainActor in
            self.onHotkeyPressed?()
        }
    }
}

// MARK: - Carbon C Callback

/// Carbon event handler (global C function)
private func carbonHotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return OSStatus(eventNotHandledErr) }

    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData)
        .takeUnretainedValue()
    manager.handleHotkeyEvent()

    return noErr
}
