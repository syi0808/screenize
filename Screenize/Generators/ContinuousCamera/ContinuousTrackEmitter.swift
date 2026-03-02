import Foundation
import CoreGraphics

/// Converts continuous per-tick camera samples into non-overlapping CameraSegments.
///
/// Uses a greedy merge algorithm: accumulates samples into a segment until the
/// transform changes significantly, then starts a new segment. Since all segments
/// come from a single continuous path, overlap is structurally impossible.
struct ContinuousTrackEmitter {

    /// Zoom change threshold to start a new segment.
    static let zoomThreshold: CGFloat = 0.02

    /// Center change threshold (per axis) to start a new segment.
    static let centerThreshold: CGFloat = 0.01

    // MARK: - Public API

    /// Emit a CameraTrack from continuous samples.
    /// - Parameter samples: Time-sorted camera transforms from SpringDamperSimulator
    /// - Returns: CameraTrack with non-overlapping segments
    static func emit(from samples: [TimedTransform]) -> CameraTrack {
        guard samples.count >= 2 else {
            if let single = samples.first {
                let segment = CameraSegment(
                    startTime: single.time,
                    endTime: single.time + 0.001,
                    startTransform: single.transform,
                    endTransform: single.transform,
                    interpolation: .linear,
                    mode: .manual,
                    transitionToNext: .cut
                )
                return CameraTrack(segments: [segment])
            }
            return CameraTrack(segments: [])
        }

        var segments: [CameraSegment] = []
        var segStartIndex = 0

        for i in 1..<samples.count {
            let start = samples[segStartIndex]
            let current = samples[i]

            let zoomDiff = abs(current.transform.zoom - start.transform.zoom)
            let centerDiffX = abs(current.transform.center.x - start.transform.center.x)
            let centerDiffY = abs(current.transform.center.y - start.transform.center.y)

            let shouldSplit = zoomDiff > zoomThreshold
                || centerDiffX > centerThreshold
                || centerDiffY > centerThreshold

            if shouldSplit {
                // Emit segment from segStart to previous sample
                let prev = samples[i - 1]
                let segment = CameraSegment(
                    startTime: start.time,
                    endTime: prev.time,
                    startTransform: start.transform,
                    endTransform: prev.transform,
                    interpolation: .linear,
                    mode: .manual,
                    transitionToNext: .cut
                )
                if segment.startTime < segment.endTime {
                    segments.append(segment)
                }
                // Start new segment from previous sample (ensures continuity)
                segStartIndex = i - 1
            }
        }

        // Emit final segment
        let start = samples[segStartIndex]
        let last = samples[samples.count - 1]
        if start.time < last.time {
            let segment = CameraSegment(
                startTime: start.time,
                endTime: last.time,
                startTransform: start.transform,
                endTransform: last.transform,
                interpolation: .linear,
                mode: .manual,
                transitionToNext: .cut
            )
            segments.append(segment)
        } else if segments.isEmpty, let first = samples.first, let last = samples.last {
            // All samples are identical — emit a single hold segment
            segments.append(CameraSegment(
                startTime: first.time,
                endTime: last.time,
                startTransform: first.transform,
                endTransform: last.transform,
                interpolation: .linear,
                mode: .manual,
                transitionToNext: .cut
            ))
        }

        return CameraTrack(segments: segments)
    }
}
