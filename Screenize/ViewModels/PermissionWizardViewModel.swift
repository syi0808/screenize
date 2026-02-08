import Foundation
import Combine

/// Permission step in the setup wizard
enum PermissionStep: Int, CaseIterable {
    case screenRecording = 0
    case microphone
    case inputMonitoring
    case accessibility

    var title: String {
        switch self {
        case .screenRecording: return "Screen Recording"
        case .microphone: return "Microphone"
        case .inputMonitoring: return "Input Monitoring"
        case .accessibility: return "Accessibility"
        }
    }

    var icon: String {
        switch self {
        case .screenRecording: return "rectangle.inset.filled.and.person.filled"
        case .microphone: return "mic.fill"
        case .inputMonitoring: return "keyboard"
        case .accessibility: return "accessibility"
        }
    }

    var description: String {
        switch self {
        case .screenRecording:
            return "Capture your display or application windows."
        case .microphone:
            return "Capture audio during screen recordings."
        case .inputMonitoring:
            return "Track keyboard, mouse, and scroll events."
        case .accessibility:
            return "Detect UI elements for Smart Zoom targeting."
        }
    }

    var permissionType: PermissionsManager.PermissionType {
        switch self {
        case .screenRecording: return .screenRecording
        case .microphone: return .microphone
        case .inputMonitoring: return .inputMonitoring
        case .accessibility: return .accessibility
        }
    }

    var requiresRestart: Bool {
        switch self {
        case .screenRecording, .inputMonitoring: return true
        case .microphone, .accessibility: return false
        }
    }
}

/// Drives the permission setup wizard UI
@MainActor
final class PermissionWizardViewModel: ObservableObject {

    // MARK: - Dependencies

    let permissionsManager: PermissionsManager

    // MARK: - Private

    private var pollingCancellable: AnyCancellable?
    private var permissionsCancellable: AnyCancellable?

    // MARK: - Computed Properties

    var allPermissionsGranted: Bool {
        permissionsManager.allPermissionsGranted
    }

    // MARK: - Initialization

    init(permissionsManager: PermissionsManager = AppState.shared.permissionsManager) {
        self.permissionsManager = permissionsManager
        permissionsCancellable = permissionsManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    // MARK: - Polling

    func startPolling() {
        permissionsManager.checkCurrentPermissions()
        pollingCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.permissionsManager.checkCurrentPermissions()
            }
    }

    func stopPolling() {
        pollingCancellable?.cancel()
        pollingCancellable = nil
    }

    // MARK: - Permission Requests

    func requestPermission(for step: PermissionStep) async {
        switch step {
        case .screenRecording:
            _ = await permissionsManager.requestScreenCapturePermission()
            if permissionsManager.screenCapturePermission != .granted {
                openSystemSettings(for: step)
            }
        case .microphone:
            _ = await permissionsManager.requestMicrophonePermission()
            if permissionsManager.microphonePermission != .granted {
                openSystemSettings(for: step)
            }
        case .inputMonitoring:
            permissionsManager.requestInputMonitoringPermission()
            if permissionsManager.inputMonitoringPermission != .granted {
                openSystemSettings(for: step)
            }
        case .accessibility:
            permissionsManager.requestAccessibilityPermission()
            if permissionsManager.accessibilityPermission != .granted {
                openSystemSettings(for: step)
            }
        }
    }

    func openSystemSettings(for step: PermissionStep) {
        permissionsManager.openSystemPreferences(for: step.permissionType)
    }

    func status(for step: PermissionStep) -> PermissionsManager.PermissionStatus {
        switch step {
        case .screenRecording: return permissionsManager.screenCapturePermission
        case .microphone: return permissionsManager.microphonePermission
        case .inputMonitoring: return permissionsManager.inputMonitoringPermission
        case .accessibility: return permissionsManager.accessibilityPermission
        }
    }
}
