import Foundation
import AVFoundation
import ScreenCaptureKit
import IOKit.hid

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var screenCapturePermission: PermissionStatus = .unknown
    @Published private(set) var microphonePermission: PermissionStatus = .unknown
    @Published private(set) var inputMonitoringPermission: PermissionStatus = .unknown
    @Published private(set) var accessibilityPermission: PermissionStatus = .unknown

    enum PermissionStatus {
        case unknown
        case granted
        case denied
        case restricted
    }

    enum PermissionType {
        case screenRecording
        case microphone
        case inputMonitoring
        case accessibility
    }

    init() {
        checkScreenCapturePermission()
        checkMicrophonePermission()
        checkAccessibilityPermission()
        // Input Monitoring should be checked after the app has finished initializing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkInputMonitoringPermission()
        }
    }

    func checkCurrentPermissions() {
        checkScreenCapturePermission()
        checkMicrophonePermission()
        checkInputMonitoringPermission()
        checkAccessibilityPermission()
    }

    private func checkScreenCapturePermission() {
        if CGPreflightScreenCaptureAccess() {
            screenCapturePermission = .granted
        } else {
            screenCapturePermission = .unknown
        }
    }

    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .granted
        case .denied:
            microphonePermission = .denied
        case .restricted:
            microphonePermission = .restricted
        case .notDetermined:
            microphonePermission = .unknown
        @unknown default:
            microphonePermission = .unknown
        }
    }

    private func checkInputMonitoringPermission() {
        // 1. Preflight check (no dialog)
        if #available(macOS 14.0, *) {
            if CGPreflightListenEventAccess() {
                inputMonitoringPermission = .granted
                return
            }
        }

        // 2. Try creating a CGEventTap (no dialog)
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) {
            CGEvent.tapEnable(tap: tap, enable: false)
            inputMonitoringPermission = .granted
            return
        }

        // 3. IOHIDCheckAccess (no dialog, read-only check)
        let iohidStatus = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if iohidStatus.rawValue == 0 { // 0 = granted
            inputMonitoringPermission = .granted
            return
        }

        inputMonitoringPermission = .denied
    }

    func requestScreenCapturePermission() async -> Bool {
        #if DEBUG
        // Debug mode: only update the status after requesting permission (for UI testing)
        if CGPreflightScreenCaptureAccess() {
            screenCapturePermission = .granted
            return true
        }

        // Request permission (register the app in System Settings)
        let granted = CGRequestScreenCaptureAccess()
        screenCapturePermission = granted ? .granted : .denied

        if !granted {
            Log.permissions.warning("Screen recording permission is required. Enable Screenize under System Settings > Privacy & Security > Screen Recording.")
            openSystemPreferences()
        }
        return granted
        #else
        if CGPreflightScreenCaptureAccess() {
            screenCapturePermission = .granted
            return true
        }

        let granted = CGRequestScreenCaptureAccess()
        screenCapturePermission = granted ? .granted : .denied
        return granted
        #endif
    }

    func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.microphonePermission = granted ? .granted : .denied
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Request Input Monitoring permission (registers the app in System Settings)
    func requestInputMonitoringPermission() {
        // Request via IOKit (may show system dialog)
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        // Also request via CG API on macOS 14+
        if #available(macOS 14.0, *) {
            CGRequestListenEventAccess()
        }

        checkInputMonitoringPermission()
    }

    /// Request Accessibility permission (shows the system prompt)
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        checkAccessibilityPermission()
    }

    func requestAllPermissions() async -> Bool {
        let screenGranted = await requestScreenCapturePermission()
        let micGranted = await requestMicrophonePermission()
        requestInputMonitoringPermission()
        requestAccessibilityPermission()
        return screenGranted && micGranted
            && inputMonitoringPermission == .granted
            && accessibilityPermission == .granted
    }

    var allPermissionsGranted: Bool {
        screenCapturePermission == .granted
            && microphonePermission == .granted
            && inputMonitoringPermission == .granted
            && accessibilityPermission == .granted
    }

    var hasScreenCapturePermission: Bool {
        screenCapturePermission == .granted
    }

    var hasMicrophonePermission: Bool {
        microphonePermission == .granted
    }

    var hasInputMonitoringPermission: Bool {
        inputMonitoringPermission == .granted
    }

    var hasAccessibilityPermission: Bool {
        accessibilityPermission == .granted
    }

    private func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        accessibilityPermission = trusted ? .granted : .denied
    }

    func openSystemPreferences(for permission: PermissionType) {
        let urlString: String
        switch permission {
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func openSystemPreferences() {
        openSystemPreferences(for: .screenRecording)
    }
}
