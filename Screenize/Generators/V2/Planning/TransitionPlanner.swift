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
        // Scale distance by zoom so that at higher zoom, transitions feel proportionally farther
        let maxZoom = max(from.idealZoom, to.idealZoom)
        let distance = rawDistance * maxZoom

        let style: TransitionStyle
        let easing: EasingCurve

        if distance < settings.shortPanMaxDistance {
            // Short direct pan
            let t = distance / settings.shortPanMaxDistance
            let duration = interpolate(
                range: settings.shortPanDurationRange, t: t
            )
            style = .directPan(duration: duration)
            easing = settings.panEasing
        } else if distance < settings.mediumPanMaxDistance {
            // Medium direct pan
            let t = (distance - settings.shortPanMaxDistance)
                / (settings.mediumPanMaxDistance - settings.shortPanMaxDistance)
            let duration = interpolate(
                range: settings.mediumPanDurationRange, t: t
            )
            style = .directPan(duration: duration)
            easing = settings.panEasing
        } else {
            // Far → zoom out and in
            style = .zoomOutAndIn(
                outDuration: settings.zoomOutDuration,
                inDuration: settings.zoomInDuration
            )
            easing = settings.zoomOutEasing
        }

        #if DEBUG
        let styleLabel: String
        switch style {
        case .directPan(let dur): styleLabel = String(format: "directPan(%.2fs)", dur)
        case .zoomOutAndIn(let o, let i): styleLabel = String(format: "zoomOut+In(%.2f+%.2fs)", o, i)
        case .cut: styleLabel = "cut"
        }
        print(String(
            format: "[V2-Transition] raw=%.3f zoom=%.2f eff=%.3f → %@",
            rawDistance, maxZoom, distance, styleLabel
        ))
        #endif

        return TransitionPlan(
            fromScene: from.scene,
            toScene: to.scene,
            style: style,
            easing: easing,
            zoomOutEasing: settings.zoomOutEasing,
            zoomInEasing: settings.zoomInEasing
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
