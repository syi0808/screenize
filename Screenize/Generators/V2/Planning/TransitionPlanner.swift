import Foundation
import CoreGraphics

/// Determines transition styles between adjacent scenes based on center distance and intent.
struct TransitionPlanner {

    // MARK: - Public API

    /// Plan transitions between adjacent shot plans.
    /// Returns `shotPlans.count - 1` transition plans.
    static func plan(
        shotPlans: [ShotPlan],
        settings: TransitionSettings
    ) -> [TransitionPlan] {
        guard shotPlans.count >= 2 else { return [] }

        var transitions: [TransitionPlan] = []

        for i in 0..<(shotPlans.count - 1) {
            let from = shotPlans[i]
            let to = shotPlans[i + 1]
            let transition = planTransition(from: from, to: to, settings: settings)
            transitions.append(transition)
        }

        return transitions
    }

    // MARK: - Single Transition

    private static func planTransition(
        from: ShotPlan,
        to: ShotPlan,
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

        let rawDistance = from.idealCenter.distance(to: to.idealCenter)
        let maxZoom = max(from.idealZoom, to.idealZoom)

        // Viewport-relative distance: how many viewport-widths away is the target?
        // At zoom Z, viewport covers 1/Z of the screen in each axis.
        // viewportDistance ~1.0 means the target center is at the viewport edge.
        let viewportHalf = 0.5 / maxZoom
        let dx = abs(from.idealCenter.x - to.idealCenter.x)
        let dy = abs(from.idealCenter.y - to.idealCenter.y)
        let viewportDistance = max(dx / viewportHalf, dy / viewportHalf)

        let style: TransitionStyle
        let easing: EasingCurve

        if viewportDistance < settings.directPanThreshold {
            // Target is well within current viewport — smooth direct pan
            let t = viewportDistance / settings.directPanThreshold
            let duration = interpolate(
                range: settings.shortPanDurationRange, t: t
            )
            style = .directPan(duration: duration)
            easing = settings.panEasing
        } else if viewportDistance < settings.gentlePanThreshold {
            // Target is near viewport edge or slightly outside — direct pan with longer duration
            let t = (viewportDistance - settings.directPanThreshold)
                / (settings.gentlePanThreshold - settings.directPanThreshold)
            let duration = interpolate(
                range: settings.mediumPanDurationRange, t: t
            )
            style = .directPan(duration: duration)
            easing = settings.panEasing
        } else {
            // Target is well outside viewport — zoom+pan transition
            let t = (viewportDistance - settings.gentlePanThreshold)
                / (settings.fullZoomOutThreshold - settings.gentlePanThreshold)
            let clamped = max(0, min(1, t))

            // Choose zoom direction based on which scene is more zoomed in
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
        print(String(
            format: "[V2-Transition] raw=%.3f maxZ=%.2f vpDist=%.3f → %@",
            rawDistance, maxZoom, viewportDistance, styleLabel
        ))
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
