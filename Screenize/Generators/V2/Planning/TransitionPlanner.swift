import Foundation
import CoreGraphics

/// Determines transition styles between adjacent scenes based on center distance and intent.
struct TransitionPlanner {

    // MARK: - Public API

    /// Plan transitions between adjacent shot plans.
    /// Returns `shotPlans.count - 1` transition plans.
    /// - Parameter fromCenters: Optional actual end centers from simulation (overrides idealCenter).
    static func plan(
        shotPlans: [ShotPlan],
        fromCenters: [NormalizedPoint]? = nil,
        settings: TransitionSettings
    ) -> [TransitionPlan] {
        guard shotPlans.count >= 2 else { return [] }

        var transitions: [TransitionPlan] = []

        for i in 0..<(shotPlans.count - 1) {
            let from = shotPlans[i]
            let to = shotPlans[i + 1]
            let actualFromCenter = fromCenters?[i]
            let transition = planTransition(
                from: from, to: to,
                actualFromCenter: actualFromCenter,
                settings: settings
            )
            transitions.append(transition)
        }

        return transitions
    }

    // MARK: - Single Transition

    private static func planTransition(
        from: ShotPlan,
        to: ShotPlan,
        actualFromCenter: NormalizedPoint?,
        settings: TransitionSettings
    ) -> TransitionPlan {
        // App switch → cut
        if from.scene.primaryIntent == .switching || to.scene.primaryIntent == .switching {
            return TransitionPlan(
                fromScene: from.scene,
                toScene: to.scene,
                style: .cut,
                easing: .linear
            )
        }

        // Use actual end center from simulation when available (cursor-aware panning
        // may have moved the camera during the scene)
        let fromCenter = actualFromCenter ?? from.idealCenter

        let viewerZoom = max(from.idealZoom, 1.0)
        let viewportHalf = 0.5 / viewerZoom
        let dx = abs(fromCenter.x - to.idealCenter.x)
        let dy = abs(fromCenter.y - to.idealCenter.y)
        let viewportDistance = max(dx / viewportHalf, dy / viewportHalf)

        // When zoom levels are similar, extend directPan range to avoid unnecessary zoom-out-in
        let zoomDiff = abs(from.idealZoom - to.idealZoom)
        let effectiveGentleThreshold: CGFloat
        if zoomDiff < settings.sameZoomTolerance {
            // Same-zoom extension helps avoid unnecessary zoom-out/in at wide shots.
            // At high viewer zoom, keep threshold tight to avoid long "slide" transitions.
            let sameZoomBoost = max(0, min(1, (1.8 - viewerZoom) / 0.8))
            let adaptiveMultiplier = 1
                + (settings.sameZoomDistanceMultiplier - 1) * sameZoomBoost
            effectiveGentleThreshold = settings.gentlePanThreshold * adaptiveMultiplier
        } else {
            effectiveGentleThreshold = settings.gentlePanThreshold
        }

        let style: TransitionStyle
        let easing: EasingCurve

        if viewportDistance < settings.directPanThreshold {
            let t = viewportDistance / settings.directPanThreshold
            let duration = interpolate(
                range: settings.shortPanDurationRange, t: t
            )
            style = .directPan(duration: duration)
            easing = settings.panEasing
        } else if viewportDistance < effectiveGentleThreshold {
            let t = (viewportDistance - settings.directPanThreshold)
                / (effectiveGentleThreshold - settings.directPanThreshold)
            let duration = interpolate(
                range: settings.mediumPanDurationRange, t: t
            )
            style = .directPan(duration: duration)
            easing = settings.panEasing
        } else {
            let t = (viewportDistance - effectiveGentleThreshold)
                / (settings.fullZoomOutThreshold - effectiveGentleThreshold)
            let clamped = max(0, min(1, t))

            if from.idealZoom >= to.idealZoom {
                let duration = interpolate(
                    range: settings.zoomOutPanDurationRange, t: clamped
                )
                style = .zoomOutAndPan(duration: duration)
                easing = settings.zoomOutEasing
            } else {
                let duration = interpolate(
                    range: settings.zoomInPanDurationRange, t: clamped
                )
                style = .zoomInAndPan(duration: duration)
                easing = settings.zoomInEasing
            }
        }

        #if DEBUG
        let styleLabel: String
        switch style {
        case .directPan(let dur):
            styleLabel = String(format: "directPan(%.2fs)", dur)
        case .zoomOutAndPan(let dur):
            styleLabel = String(format: "zoomOutAndPan(%.2fs)", dur)
        case .zoomInAndPan(let dur):
            styleLabel = String(format: "zoomInAndPan(%.2fs)", dur)
        case .cut:
            styleLabel = "cut"
        }
        let effThreshLabel = zoomDiff < settings.sameZoomTolerance ? " (sameZoom)" : ""
        let msg = String(
            format: "[V2-Transition] viewerZ=%.2f vpDist=%.3f effThresh=%.2f%@ → %@",
            viewerZoom, viewportDistance, effectiveGentleThreshold, effThreshLabel, styleLabel
        )
        Log.generator.debug("\(msg)")
        #endif

        return TransitionPlan(
            fromScene: from.scene,
            toScene: to.scene,
            style: style,
            easing: easing
        )
    }

    /// Linear interpolation within a closed range.
    private static func interpolate(
        range: ClosedRange<TimeInterval>,
        t: CGFloat
    ) -> TimeInterval {
        let clamped = max(0, min(1, Double(t)))
        return range.lowerBound + (range.upperBound - range.lowerBound) * clamped
    }
}
