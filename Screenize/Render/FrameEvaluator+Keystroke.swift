import Foundation
import CoreGraphics

// MARK: - Keystroke Evaluation

extension FrameEvaluator {

    /// Evaluate the keystroke overlay track
    func evaluateKeystrokes(at time: TimeInterval) -> [ActiveKeystroke] {
        guard let track = timeline.keystrokeTrackV2, track.isEnabled else {
            return []
        }

        return track.activeSegments(at: time).map { segment in
            ActiveKeystroke(
                displayText: segment.displayText,
                opacity: keystrokeOpacity(for: segment, at: time),
                progress: CGFloat((time - segment.startTime) / max(0.001, segment.endTime - segment.startTime)),
                position: segment.position
            )
        }
    }

    func keystrokeOpacity(for segment: KeystrokeSegment, at time: TimeInterval) -> CGFloat {
        let elapsed = time - segment.startTime
        let remaining = segment.endTime - time

        if segment.fadeInDuration > 0, elapsed < segment.fadeInDuration {
            return CGFloat(elapsed / segment.fadeInDuration)
        }

        if segment.fadeOutDuration > 0, remaining < segment.fadeOutDuration {
            return CGFloat(remaining / segment.fadeOutDuration)
        }

        return 1.0
    }
}
