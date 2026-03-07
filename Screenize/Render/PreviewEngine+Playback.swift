import Foundation

// MARK: - Playback Control

extension PreviewEngine {

    /// Start playback
    func play() {
        guard !isPlaying else { return }

        // When starting playback at the trim end, jump to the trim start
        if currentTime >= effectiveTrimEnd {
            isSeeking = true
            currentTime = effectiveTrimStart
            isSeeking = false
        }

        // If the time is before the trim start, clamp to the trim start
        if currentTime < effectiveTrimStart {
            isSeeking = true
            currentTime = effectiveTrimStart
            isSeeking = false
        }

        // Reposition the sequential reader to current time
        renderCoordinator.seek(to: currentTime)

        isPlaying = true

        // Start vsync-driven playback
        displayLinkDriver.start(fromVideoTime: currentTime, frameRate: frameRate)

        // Start audio playback locked to the same mach-time anchor
        audioPlayer.play(
            fromVideoTime: displayLinkDriver.playbackAnchorVideoTime,
            hostTime: displayLinkDriver.playbackAnchorMachTime
        )
    }

    /// Pause playback
    func pause() {
        isPlaying = false
        displayLinkDriver.stop()
        audioPlayer.pause()
    }

    /// Toggle playback/pause
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Seek to a specific time (clamped to trim range)
    func seek(to time: TimeInterval) async {
        let clampedTime = max(effectiveTrimStart, min(effectiveTrimEnd, time))

        isSeeking = true
        renderGeneration += 1
        frameExtractor?.cancelAllPendingRequests()
        renderCoordinator.seek(to: clampedTime)
        currentTime = clampedTime
        isSeeking = false

        if !isPlaying {
            scrubController.scrub(to: clampedTime)
            Task { await audioPlayer.seek(to: clampedTime) }
        } else {
            // During playback, update the display link anchor
            displayLinkDriver.updateAnchor(videoTime: clampedTime)
            audioPlayer.play(
                fromVideoTime: displayLinkDriver.playbackAnchorVideoTime,
                hostTime: displayLinkDriver.playbackAnchorMachTime
            )
        }
    }

    /// Jump to the start (trim start)
    func seekToStart() async {
        await seek(to: effectiveTrimStart)
    }

    /// Jump to the end (trim end)
    func seekToEnd() async {
        await seek(to: effectiveTrimEnd)
    }
}
