import Foundation
import SwiftUI
import ScreenCaptureKit
import AVFoundation

/// Capture source selection, audio settings, and frame rate preferences.
@MainActor
final class CaptureSettings: ObservableObject {

    // MARK: - Audio Settings

    @AppStorage("isMicrophoneEnabled") var isMicrophoneEnabled: Bool = false
    @AppStorage("isSystemAudioEnabled") var isSystemAudioEnabled: Bool = true
    @AppStorage("selectedMicrophoneDeviceID") var selectedMicrophoneDeviceID: String = ""

    // MARK: - Frame Rate

    @AppStorage("captureFrameRate") var captureFrameRate: Int = 60

    // MARK: - Source Selection

    @Published var selectedTarget: CaptureTarget?
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []

    // MARK: - Background Style

    // Note: BackgroundStyle doesn't support @AppStorage directly
    var backgroundStyle: BackgroundStyle = .solid(.gray)

    // MARK: - Computed Properties

    /// Resolve the persisted microphone device ID to an AVCaptureDevice.
    /// Returns nil if the saved device is unavailable (disconnected, etc.).
    var selectedMicrophoneDevice: AVCaptureDevice? {
        guard !selectedMicrophoneDeviceID.isEmpty else { return nil }
        return AVCaptureDevice(uniqueID: selectedMicrophoneDeviceID)
    }

    // MARK: - Source Refresh

    func refreshAvailableSources() async {
        // Request permission if missing
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                Log.permissions.debug("Permission wait sleep cancelled: \(error.localizedDescription)")
            }

            if !CGPreflightScreenCaptureAccess() {
                return
            }
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            availableDisplays = content.displays
            let excludedBundleIDs: Set<String> = [
                Bundle.main.bundleIdentifier ?? "com.screenize.Screenize",
                "com.apple.dock",
                "com.apple.controlcenter",
                "com.apple.systemuiserver",
                "com.apple.notificationcenterui",
                "com.apple.WindowManager",
            ]

            availableWindows = content.windows.filter { window in
                guard let app = window.owningApplication else {
                    return false
                }
                return !excludedBundleIDs.contains(app.bundleIdentifier)
                    && window.frame.width >= 50
                    && window.frame.height >= 50
            }

            Log.ui.info("Sources refreshed - displays: \(self.availableDisplays.count), windows: \(self.availableWindows.count)")
        } catch {
            Log.ui.error("Failed to refresh sources: \(error)")
        }
    }
}
