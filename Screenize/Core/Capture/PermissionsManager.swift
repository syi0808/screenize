import Foundation
import AVFoundation
import ScreenCaptureKit
import IOKit.hid

@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var screenCapturePermission: PermissionStatus = .unknown
    @Published private(set) var microphonePermission: PermissionStatus = .unknown
    @Published private(set) var inputMonitoringPermission: PermissionStatus = .unknown

    enum PermissionStatus {
        case unknown
        case granted
        case denied
        case restricted
    }

    init() {
        checkScreenCapturePermission()
        checkMicrophonePermission()
        // Input Monitoring should be checked after the app has finished initializing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkInputMonitoringPermission()
        }
    }

    func checkCurrentPermissions() {
        checkScreenCapturePermission()
        checkMicrophonePermission()
        checkInputMonitoringPermission()
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
        let logPath = "/tmp/screenize_input_monitoring.log"
        func log(_ msg: String) {
            let entry = "\(Date()): \(msg)\n"
            if let data = entry.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logPath) {
                    if let handle = FileHandle(forWritingAtPath: logPath) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    FileManager.default.createFile(atPath: logPath, contents: data)
                }
            }
        }

        log("checkInputMonitoringPermission() called")

        // 1. Check preflight status
        var preflightResult = false
        if #available(macOS 14.0, *) {
            preflightResult = CGPreflightListenEventAccess()
        }
        log("CGPreflightListenEventAccess() = \(preflightResult)")

        // 2. Try creating a CGEventTap
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) {
            log("CGEvent.tapCreate(.listenOnly) = SUCCESS")
            CGEvent.tapEnable(tap: tap, enable: false)
            inputMonitoringPermission = .granted
            return
        }

        log("CGEvent.tapCreate(.listenOnly) = FAILED")

        // 3. Try IOHIDRequestAccess (IOKit path)
        let iohidCheck = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        log("IOHIDCheckAccess(ListenEvent) = \(iohidCheck.rawValue) (0=granted, 1=denied, 2=unknown)")

        let iohidResult = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        log("IOHIDRequestAccess(ListenEvent) = \(iohidResult)")

        let iohidCheckAfter = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        log("After IOHIDRequestAccess, check = \(iohidCheckAfter.rawValue)")

        // 4. Also request CGRequestListenEventAccess
        if #available(macOS 14.0, *) {
            log("Calling CGRequestListenEventAccess()...")
            CGRequestListenEventAccess()
            let afterRequest = CGPreflightListenEventAccess()
            log("After CGRequestListenEventAccess(), preflight = \(afterRequest)")
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
            print("⚠️ [DEBUG] Screen recording permission is required.")
            print("⚠️ Enable Screenize under System Settings > Privacy & Security > Screen Recording.")
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
        checkInputMonitoringPermission()
    }

    func requestAllPermissions() async -> Bool {
        let screenGranted = await requestScreenCapturePermission()
        let micGranted = await requestMicrophonePermission()
        requestInputMonitoringPermission()
        return screenGranted && micGranted && inputMonitoringPermission == .granted
    }

    var allPermissionsGranted: Bool {
        screenCapturePermission == .granted && microphonePermission == .granted && inputMonitoringPermission == .granted
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

    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
