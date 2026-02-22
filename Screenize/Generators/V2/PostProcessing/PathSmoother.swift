import Foundation
import CoreGraphics

/// Removes high-frequency jitter from simulated camera path samples.
///
/// Uses a moving-average filter on `TimedTransform` samples within each scene segment.
/// Disabled by default — intended for future CursorFollowController output.
/// StaticHoldController produces identical start/end samples with no jitter.
struct PathSmoother {

    /// Smooth a simulated path using a moving-average filter.
    /// - Returns: New `SimulatedPath` with smoothed scene segment samples.
    ///   Transition segments pass through unchanged.
    static func smooth(
        _ path: SimulatedPath,
        settings: SmoothingSettings
    ) -> SimulatedPath {
        guard settings.enabled, !path.sceneSegments.isEmpty else {
            return path
        }

        let smoothedSegments = path.sceneSegments.map { segment in
            SimulatedSceneSegment(
                scene: segment.scene,
                shotPlan: segment.shotPlan,
                samples: smoothSamples(
                    segment.samples,
                    windowSize: settings.windowSize,
                    maxDeviation: settings.maxDeviation
                )
            )
        }

        return SimulatedPath(
            sceneSegments: smoothedSegments,
            transitionSegments: path.transitionSegments
        )
    }

    // MARK: - Private

    private static func smoothSamples(
        _ samples: [TimedTransform],
        windowSize: Int,
        maxDeviation: CGFloat
    ) -> [TimedTransform] {
        guard samples.count > 2 else { return samples }

        var result = samples
        let halfWindow = windowSize / 2

        // Keep first and last samples as anchors
        for i in 1..<(samples.count - 1) {
            let windowStart = max(0, i - halfWindow)
            let windowEnd = min(samples.count - 1, i + halfWindow)
            let windowCount = CGFloat(windowEnd - windowStart + 1)

            var avgZoom: CGFloat = 0
            var avgCenterX: CGFloat = 0
            var avgCenterY: CGFloat = 0
            for j in windowStart...windowEnd {
                avgZoom += samples[j].transform.zoom
                avgCenterX += samples[j].transform.center.x
                avgCenterY += samples[j].transform.center.y
            }
            avgZoom /= windowCount
            avgCenterX /= windowCount
            avgCenterY /= windowCount

            let original = samples[i].transform
            let zoomDiff = abs(original.zoom - avgZoom)
            let centerDiff = hypot(
                original.center.x - avgCenterX,
                original.center.y - avgCenterY
            )

            // Only smooth small deviations (jitter), not intentional movement
            if zoomDiff < maxDeviation && centerDiff < maxDeviation {
                result[i] = TimedTransform(
                    time: samples[i].time,
                    transform: TransformValue(
                        zoom: avgZoom,
                        center: NormalizedPoint(x: avgCenterX, y: avgCenterY)
                    )
                )
            }
        }

        return result
    }
}
