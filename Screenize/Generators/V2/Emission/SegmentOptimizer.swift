import Foundation
import CoreGraphics

/// Optimizes a final CameraTrack by merging adjacent similar segments.
///
/// Scans sorted CameraSegments and merges consecutive pairs where all transform
/// differences are below the configured thresholds. Operates post-emission
/// on CameraSegments (not SimulatedPath).
struct SegmentOptimizer {

    static func optimize(
        _ track: CameraTrack,
        settings: OptimizationSettings
    ) -> CameraTrack {
        guard settings.mergeConsecutiveHolds,
              track.segments.count > 1 else {
            return track
        }

        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        var merged: [CameraSegment] = [sorted[0]]

        for i in 1..<sorted.count {
            let current = sorted[i]
            let last = merged[merged.count - 1]

            if canMerge(last, with: current, settings: settings) {
                merged[merged.count - 1] = CameraSegment(
                    startTime: last.startTime,
                    endTime: current.endTime,
                    startTransform: last.startTransform,
                    endTransform: current.endTransform,
                    interpolation: last.interpolation
                )
            } else {
                merged.append(current)
            }
        }

        return CameraTrack(
            id: track.id,
            name: track.name,
            isEnabled: track.isEnabled,
            segments: merged
        )
    }

    // MARK: - Private

    private static func canMerge(
        _ a: CameraSegment,
        with b: CameraSegment,
        settings: OptimizationSettings
    ) -> Bool {
        // Check time adjacency (no gap)
        guard abs(a.endTime - b.startTime) < 0.01 else { return false }

        // Check junction continuity: a.end ≈ b.start
        let junctionZoomDiff = abs(
            a.endTransform.zoom - b.startTransform.zoom
        )
        let junctionCenterDiffX = abs(
            a.endTransform.center.x - b.startTransform.center.x
        )
        let junctionCenterDiffY = abs(
            a.endTransform.center.y - b.startTransform.center.y
        )

        guard junctionZoomDiff < settings.negligibleZoomDiff,
              junctionCenterDiffX < settings.negligibleCenterDiff,
              junctionCenterDiffY < settings.negligibleCenterDiff
        else { return false }

        // Check per-segment internal change instead of overall drift.
        // This allows merging segments that individually are nearly static
        // even if they've drifted cumulatively (e.g. typing micro-pans).
        let aInternalZoomDiff = abs(a.startTransform.zoom - a.endTransform.zoom)
        let bInternalZoomDiff = abs(b.startTransform.zoom - b.endTransform.zoom)
        let aInternalCenterDiffX = abs(
            a.startTransform.center.x - a.endTransform.center.x
        )
        let aInternalCenterDiffY = abs(
            a.startTransform.center.y - a.endTransform.center.y
        )
        let bInternalCenterDiffX = abs(
            b.startTransform.center.x - b.endTransform.center.x
        )
        let bInternalCenterDiffY = abs(
            b.startTransform.center.y - b.endTransform.center.y
        )

        let bothNearlyStatic =
            max(aInternalZoomDiff, bInternalZoomDiff) < settings.negligibleZoomDiff
            && max(aInternalCenterDiffX, bInternalCenterDiffX) < settings.negligibleCenterDiff
            && max(aInternalCenterDiffY, bInternalCenterDiffY) < settings.negligibleCenterDiff

        return bothNearlyStatic
    }
}
