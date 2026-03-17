import Foundation
import AVFoundation

/// Captures all settings needed to replay a scenario with recording.
struct ReplayConfiguration {
    let captureTarget: CaptureTarget
    let backgroundStyle: BackgroundStyle
    let frameRate: Int
    let isSystemAudioEnabled: Bool
    let isMicrophoneEnabled: Bool
    let microphoneDevice: AVCaptureDevice?
}
