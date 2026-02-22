import Foundation
import AVFoundation
import CoreMedia

/// Audio preview player
/// Provides synchronized audio playback during preview using AVPlayer.
/// Locks playback to DisplayLinkDriver's mach-time anchor for frame-accurate sync.
@MainActor
final class AudioPreviewPlayer {

    // MARK: - Properties

    private var systemAudioPlayer: AVPlayer?
    private var micAudioPlayer: AVPlayer?

    private var systemAudioVolume: Float = 1.0
    private var micAudioVolume: Float = 1.0

    private var isSetUp = false

    // MARK: - Setup

    /// Set up audio players for system audio and mic audio
    /// - Parameters:
    ///   - videoURL: URL of the video file (contains system audio track)
    ///   - micAudioURL: URL of the mic audio sidecar file (optional)
    ///   - renderSettings: Current render settings for volume levels
    func setup(videoURL: URL, micAudioURL: URL?, renderSettings: RenderSettings) async {
        cleanup()

        // System audio: use the video file's audio track
        let systemAsset = AVAsset(url: videoURL)
        let hasSysAudio: Bool
        do {
            let audioTracks = try await systemAsset.loadTracks(withMediaType: .audio)
            hasSysAudio = !audioTracks.isEmpty
        } catch {
            hasSysAudio = false
        }

        if hasSysAudio {
            let playerItem = AVPlayerItem(asset: systemAsset)
            let player = AVPlayer(playerItem: playerItem)
            player.volume = renderSettings.includeSystemAudio ? renderSettings.systemAudioVolume : 0
            systemAudioPlayer = player
        }

        // Mic audio: use the sidecar file
        if let micURL = micAudioURL, FileManager.default.fileExists(atPath: micURL.path) {
            let micAsset = AVAsset(url: micURL)
            let hasMicAudio: Bool
            do {
                let audioTracks = try await micAsset.loadTracks(withMediaType: .audio)
                hasMicAudio = !audioTracks.isEmpty
            } catch {
                hasMicAudio = false
            }

            if hasMicAudio {
                let playerItem = AVPlayerItem(asset: micAsset)
                let player = AVPlayer(playerItem: playerItem)
                player.volume = renderSettings.includeMicrophoneAudio ? renderSettings.microphoneAudioVolume : 0
                micAudioPlayer = player
            }
        }

        systemAudioVolume = renderSettings.systemAudioVolume
        micAudioVolume = renderSettings.microphoneAudioVolume

        isSetUp = true
    }

    // MARK: - Playback Control

    /// Start playback synchronized to a mach-time anchor
    /// - Parameters:
    ///   - videoTime: The video time at the anchor point
    ///   - hostTime: The mach_absolute_time at the anchor point
    func play(fromVideoTime videoTime: TimeInterval, hostTime: UInt64) {
        let cmTime = CMTime(seconds: videoTime, preferredTimescale: 600)
        let cmHostTime = CMClockMakeHostTimeFromSystemUnits(hostTime)

        if let player = systemAudioPlayer {
            player.setRate(1.0, time: cmTime, atHostTime: cmHostTime)
        }
        if let player = micAudioPlayer {
            player.setRate(1.0, time: cmTime, atHostTime: cmHostTime)
        }
    }

    /// Pause audio playback
    func pause() {
        systemAudioPlayer?.pause()
        micAudioPlayer?.pause()
    }

    /// Seek audio to a specific time
    /// - Parameter time: Target video time
    func seek(to time: TimeInterval) async {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        let tolerance = CMTime.zero

        await withTaskGroup(of: Void.self) { group in
            if let player = systemAudioPlayer {
                group.addTask {
                    await player.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
                }
            }
            if let player = micAudioPlayer {
                group.addTask {
                    await player.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance)
                }
            }
        }
    }

    /// Update volume levels from render settings
    /// - Parameter renderSettings: Current render settings
    func updateVolumes(renderSettings: RenderSettings) {
        systemAudioVolume = renderSettings.systemAudioVolume
        micAudioVolume = renderSettings.microphoneAudioVolume

        systemAudioPlayer?.volume = renderSettings.includeSystemAudio ? renderSettings.systemAudioVolume : 0
        micAudioPlayer?.volume = renderSettings.includeMicrophoneAudio ? renderSettings.microphoneAudioVolume : 0
    }

    // MARK: - Cleanup

    func cleanup() {
        systemAudioPlayer?.pause()
        micAudioPlayer?.pause()
        systemAudioPlayer = nil
        micAudioPlayer = nil
        isSetUp = false
    }
}
