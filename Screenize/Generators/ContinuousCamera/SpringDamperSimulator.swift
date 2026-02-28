import Foundation
import CoreGraphics

/// Continuous 60Hz spring-damper physics simulation producing a smooth camera path.
///
/// Given a series of camera waypoints, simulates a single continuous camera trajectory
/// using damped harmonic oscillators for position (X, Y) and zoom independently.
/// Unlike the segment-based pipeline, this produces one unbroken path with no
/// discrete transitions.
struct SpringDamperSimulator {

    // MARK: - Public API

    /// Simulate a continuous camera path from waypoints.
    /// - Parameters:
    ///   - waypoints: Target camera states sorted by time
    ///   - duration: Total recording duration
    ///   - settings: Physics simulation parameters
    /// - Returns: Time-sorted array of per-tick camera transforms
    static func simulate(
        waypoints: [CameraWaypoint],
        duration: TimeInterval,
        settings: ContinuousCameraSettings
    ) -> [TimedTransform] {
        guard !waypoints.isEmpty, duration > 0 else { return [] }

        let dt = 1.0 / settings.tickRate
        let first = waypoints[0]

        var state = CameraState(
            positionX: first.targetCenter.x,
            positionY: first.targetCenter.y,
            zoom: first.targetZoom
        )
        clampState(&state, settings: settings)

        var results: [TimedTransform] = []
        let estimatedCount = Int(duration * settings.tickRate) + 1
        results.reserveCapacity(estimatedCount)

        // Emit initial sample
        results.append(TimedTransform(
            time: 0,
            transform: TransformValue(
                zoom: state.zoom,
                center: NormalizedPoint(x: state.positionX, y: state.positionY)
            )
        ))

        var waypointIndex = 0
        var t = dt
        let activationTolerance = dt * 0.5

        while t <= duration + dt * 0.5 {
            // Advance to current active waypoint (last one with time <= t)
            var activatedImmediate = false
            while waypointIndex + 1 < waypoints.count
                    && waypoints[waypointIndex + 1].time <= t + activationTolerance {
                waypointIndex += 1
                activatedImmediate = activatedImmediate
                    || waypoints[waypointIndex].urgency == .immediate
            }

            let activeWP = waypoints[waypointIndex]

            // Switching/app-change waypoints should feel like a hard cut.
            if activatedImmediate {
                state.positionX = activeWP.targetCenter.x
                state.positionY = activeWP.targetCenter.y
                state.zoom = activeWP.targetZoom
                state.velocityX = 0
                state.velocityY = 0
                state.velocityZoom = 0
                clampState(&state, settings: settings)
                results.append(transformSample(from: state, at: t))
                t += dt
                continue
            }

            let lookAheadTarget = anticipatoryTarget(
                active: activeWP,
                next: waypointIndex + 1 < waypoints.count
                    ? waypoints[waypointIndex + 1]
                    : nil,
                currentTime: t
            )
            let urgencyMult = settings.urgencyMultipliers[lookAheadTarget.urgency] ?? 1.0

            // Compute effective spring parameters
            let posOmega = 2.0 * .pi / max(0.001, settings.positionResponse * urgencyMult)
            let zoomOmega = 2.0 * .pi / max(0.001, settings.zoomResponse * urgencyMult)
            let posDamping = settings.positionDampingRatio
            let zoomDamping = settings.zoomDampingRatio

            // Spring step for each axis
            let (newX, newVX) = springStep(
                current: state.positionX, velocity: state.velocityX,
                target: lookAheadTarget.center.x,
                omega: posOmega, zeta: posDamping, dt: CGFloat(dt)
            )
            let (newY, newVY) = springStep(
                current: state.positionY, velocity: state.velocityY,
                target: lookAheadTarget.center.y,
                omega: posOmega, zeta: posDamping, dt: CGFloat(dt)
            )
            let (newZ, newVZ) = springStep(
                current: state.zoom, velocity: state.velocityZoom,
                target: lookAheadTarget.zoom,
                omega: zoomOmega, zeta: zoomDamping, dt: CGFloat(dt)
            )

            state.positionX = newX
            state.positionY = newY
            state.zoom = newZ
            state.velocityX = newVX
            state.velocityY = newVY
            state.velocityZoom = newVZ

            clampState(&state, settings: settings)
            results.append(transformSample(from: state, at: t))

            t += dt
        }

        return results
    }

    // MARK: - Helpers

    private static func anticipatoryTarget(
        active: CameraWaypoint,
        next: CameraWaypoint?,
        currentTime: TimeInterval
    ) -> (zoom: CGFloat, center: NormalizedPoint, urgency: WaypointUrgency) {
        guard let next else {
            return (active.targetZoom, active.targetCenter, active.urgency)
        }
        guard next.urgency != .immediate else {
            // App switching should cut at the activation time, not pre-pan.
            return (active.targetZoom, active.targetCenter, active.urgency)
        }

        let lead = anticipationLeadTime(for: next.urgency)
        let start = next.time - lead
        guard currentTime >= start, currentTime < next.time, lead > 0.0001 else {
            return (active.targetZoom, active.targetCenter, active.urgency)
        }

        let alpha = CGFloat((currentTime - start) / lead)
        let blendedZoom = active.targetZoom
            + (next.targetZoom - active.targetZoom) * alpha
        let blendedCenter = active.targetCenter.interpolated(
            to: next.targetCenter,
            amount: alpha
        )
        let blendedUrgency = max(active.urgency, next.urgency)
        return (blendedZoom, blendedCenter, blendedUrgency)
    }

    private static func anticipationLeadTime(
        for urgency: WaypointUrgency
    ) -> TimeInterval {
        switch urgency {
        case .immediate:
            return 0.24
        case .high:
            return 0.16
        case .normal:
            return 0.10
        case .lazy:
            return 0.0
        }
    }

    /// Clamp camera state to valid bounds, zeroing velocity on clamped axes.
    private static func clampState(
        _ state: inout CameraState,
        settings: ContinuousCameraSettings
    ) {
        // Clamp zoom to bounds
        if state.zoom < settings.minZoom {
            state.zoom = settings.minZoom
            state.velocityZoom = 0
        } else if state.zoom > settings.maxZoom {
            state.zoom = settings.maxZoom
            state.velocityZoom = 0
        }

        // Clamp center to keep viewport in [0, 1]
        let clamped = ShotPlanner.clampCenter(
            NormalizedPoint(x: state.positionX, y: state.positionY),
            zoom: state.zoom
        )
        if abs(clamped.x - state.positionX) > 0.0001 {
            state.positionX = clamped.x
            state.velocityX = 0
        }
        if abs(clamped.y - state.positionY) > 0.0001 {
            state.positionY = clamped.y
            state.velocityY = 0
        }
    }

    /// Create a TimedTransform sample from current camera state.
    private static func transformSample(
        from state: CameraState,
        at time: TimeInterval
    ) -> TimedTransform {
        TimedTransform(
            time: time,
            transform: TransformValue(
                zoom: state.zoom,
                center: NormalizedPoint(x: state.positionX, y: state.positionY)
            )
        )
    }

    // MARK: - Spring Math

    /// Solve the damped harmonic oscillator analytically for one timestep.
    /// Duplicated from SpringCursorSimulator since its springStep is private.
    static func springStep(
        current x0: CGFloat,
        velocity v0: CGFloat,
        target: CGFloat,
        omega: CGFloat,
        zeta: CGFloat,
        dt: CGFloat
    ) -> (position: CGFloat, velocity: CGFloat) {
        let displacement = x0 - target

        if zeta >= 1.0 {
            // Critically damped / overdamped
            let zo = zeta * omega
            let decay = exp(-zo * dt)
            let coeffA = displacement
            let coeffB = v0 + zo * displacement
            let newPos = target + (coeffA + coeffB * dt) * decay
            let newVel = (coeffB - zo * (coeffA + coeffB * dt)) * decay
            return (newPos, newVel)
        } else {
            // Underdamped
            let wd = omega * sqrt(1.0 - zeta * zeta)
            let zo = zeta * omega
            let decay = exp(-zo * dt)
            let coeffA = displacement
            let coeffB = (v0 + zo * displacement) / wd
            let cosVal = cos(wd * dt)
            let sinVal = sin(wd * dt)
            let newPos = target + decay * (coeffA * cosVal + coeffB * sinVal)
            let newVel = decay * (
                (-zo) * (coeffA * cosVal + coeffB * sinVal)
                + (-coeffA * wd * sinVal + coeffB * wd * cosVal)
            )
            return (newPos, newVel)
        }
    }
}
