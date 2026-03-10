import Foundation
import CoreGraphics

/// Continuous 60Hz spring-damper physics simulation producing a smooth camera path.
///
/// Dead zone architecture: position targeting uses a dead zone around the camera center —
/// the camera only moves when the cursor exits the dead zone, and the target is the nearest
/// dead zone edge rather than the cursor itself. Adaptive spring response speeds up the camera
/// when the next user action is imminent. Zoom targets come from intent-derived waypoints
/// via a separate spring.
struct SpringDamperSimulator {

    private struct PositionTargeting {
        let target: NormalizedPoint
        let omega: CGFloat
        let damping: CGFloat
    }

    // MARK: - Public API

    /// Simulate a continuous camera path with dead zone targeting.
    /// - Parameters:
    ///   - cursorPositions: Smoothed mouse positions
    ///   - zoomWaypoints: Intent-derived zoom targets (position data ignored)
    ///   - intentSpans: Classified user intent spans for dead zone and adaptive response
    ///   - duration: Total recording duration
    ///   - settings: Physics simulation parameters
    /// - Returns: Time-sorted array of per-tick camera transforms
    static func simulate(
        cursorPositions: [MousePositionData],
        clickEvents: [ClickEventData] = [],
        keyboardEvents: [KeyboardEventData] = [],
        dragEvents: [DragEventData] = [],
        zoomWaypoints: [CameraWaypoint],
        intentSpans: [IntentSpan],
        duration: TimeInterval,
        settings: ContinuousCameraSettings
    ) -> [TimedTransform] {
        guard !cursorPositions.isEmpty, duration > 0 else { return [] }

        let dt = 1.0 / settings.tickRate
        let initialZoom = zoomWaypoints.first?.targetZoom ?? 1.0
        let startupState = StartupCameraPolicy.resolve(
            cursorPositions: cursorPositions,
            clickEvents: clickEvents,
            keyboardEvents: keyboardEvents,
            dragEvents: dragEvents,
            intentSpans: intentSpans,
            settings: settings.startup
        )

        let initialCenter = ShotPlanner.clampCenter(
            startupState.initialCenter,
            zoom: initialZoom
        )
        var state = CameraState(
            positionX: initialCenter.x,
            positionY: initialCenter.y,
            zoom: initialZoom
        )
        clampState(&state, settings: settings, dt: CGFloat(dt))

        var results: [TimedTransform] = []
        let estimatedCount = Int(duration * settings.tickRate) + 1
        results.reserveCapacity(estimatedCount)

        results.append(transformSample(from: state, at: 0))

        var cursorIndex = 0
        var zoomIndex = 0
        var prevZoomUrgencyMult: CGFloat = settings.urgencyMultipliers[
            zoomWaypoints.first?.urgency ?? .lazy
        ] ?? 1.0
        var zoomUrgencyTransitionStart: TimeInterval = 0
        var intentIndex = 0

        var t = dt
        let activationTolerance = dt * 0.5

        while t <= duration + dt * 0.5 {
            // Advance cursor index
            while cursorIndex + 1 < cursorPositions.count
                    && cursorPositions[cursorIndex + 1].time <= t {
                cursorIndex += 1
            }
            let cursorPos = cursorPositions[cursorIndex].position

            // Advance zoom waypoint index
            let previousZoomIndex = zoomIndex
            var activatedImmediate = false
            while zoomIndex + 1 < zoomWaypoints.count
                    && zoomWaypoints[zoomIndex + 1].time <= t + activationTolerance {
                zoomIndex += 1
                activatedImmediate = activatedImmediate
                    || zoomWaypoints[zoomIndex].urgency == .immediate
            }

            // Track zoom urgency transitions
            if zoomIndex != previousZoomIndex {
                prevZoomUrgencyMult = settings.urgencyMultipliers[
                    zoomWaypoints[previousZoomIndex].urgency
                ] ?? 1.0
                zoomUrgencyTransitionStart = t
            }

            // Determine zoom target
            let targetZoom: CGFloat
            if zoomWaypoints.isEmpty {
                targetZoom = 1.0
            } else {
                targetZoom = zoomWaypoints[zoomIndex].targetZoom
            }

            // Handle immediate zoom cuts (app switching)
            if activatedImmediate {
                state.zoom = targetZoom
                state.velocityZoom = 0
            }

            // Compute effective zoom urgency multiplier with blending
            let currentZoomMult = settings.urgencyMultipliers[
                zoomWaypoints.isEmpty ? .lazy : zoomWaypoints[zoomIndex].urgency
            ] ?? 1.0
            let effectiveZoomMult: CGFloat
            let blendDuration = settings.urgencyBlendDuration
            if blendDuration > 0.001 && t - zoomUrgencyTransitionStart < blendDuration {
                let linearProgress = CGFloat((t - zoomUrgencyTransitionStart) / blendDuration)
                let blendProgress = linearProgress * linearProgress * (3 - 2 * linearProgress)
                effectiveZoomMult = prevZoomUrgencyMult
                    + (currentZoomMult - prevZoomUrgencyMult) * blendProgress
            } else {
                effectiveZoomMult = currentZoomMult
            }

            // Advance intent span index
            while intentIndex + 1 < intentSpans.count
                    && intentSpans[intentIndex].endTime <= t {
                intentIndex += 1
            }

            let isTyping = isTypingIntent(intentSpans, at: intentIndex)

            // Dead zone targeting with hysteresis
            let dzResult = DeadZoneTarget.computeWithState(
                cursorPosition: cursorPos,
                cameraCenter: NormalizedPoint(
                    x: state.positionX, y: state.positionY
                ),
                zoom: state.zoom,
                isTyping: isTyping,
                wasActive: state.deadZoneActive,
                settings: settings.deadZone
            )
            let posTarget = dzResult.target
            state.deadZoneActive = dzResult.isActive

            // Zoom-coupled position targeting:
            // While zoom is actively transitioning, use the waypoint center
            // directly as position target so pan and zoom arrive together.
            // Once zoom settles, dead zone targeting takes over.
            let zoomDisplacement = abs(state.zoom - targetZoom)
            let isZoomTransitioning = zoomDisplacement
                > settings.zoomSettleThreshold
                && !zoomWaypoints.isEmpty
            let startupBiasActive = startupState.releaseTime.map { t < $0 } ?? true

            let positionTargeting = resolvePositionTargeting(
                zoomWaypoints: zoomWaypoints,
                zoomIndex: zoomIndex,
                targetZoom: targetZoom,
                effectiveZoomMult: effectiveZoomMult,
                isZoomTransitioning: isZoomTransitioning,
                startupBiasActive: startupBiasActive,
                initialCenter: initialCenter,
                posTarget: posTarget,
                time: t,
                intentSpans: intentSpans,
                settings: settings
            )

            let (newX, newVX) = springStep(
                current: state.positionX, velocity: state.velocityX,
                target: positionTargeting.target.x,
                omega: positionTargeting.omega,
                zeta: positionTargeting.damping,
                dt: CGFloat(dt)
            )
            let (newY, newVY) = springStep(
                current: state.positionY, velocity: state.velocityY,
                target: positionTargeting.target.y,
                omega: positionTargeting.omega,
                zeta: positionTargeting.damping,
                dt: CGFloat(dt)
            )

            // Zoom spring: targets intent-derived zoom with urgency scaling
            let zoomOmega = 2.0 * .pi / max(0.001, settings.zoomResponse * effectiveZoomMult)
            let zoomDamping = settings.zoomDampingRatio

            let (newZ, newVZ): (CGFloat, CGFloat)
            if activatedImmediate {
                newZ = state.zoom
                newVZ = 0
            } else {
                (newZ, newVZ) = springStep(
                    current: state.zoom, velocity: state.velocityZoom,
                    target: targetZoom,
                    omega: zoomOmega, zeta: zoomDamping, dt: CGFloat(dt)
                )
            }

            state.positionX = newX
            state.positionY = newY
            state.zoom = newZ
            state.velocityX = newVX
            state.velocityY = newVY
            state.velocityZoom = newVZ

            clampState(&state, settings: settings, dt: CGFloat(dt))
            results.append(transformSample(from: state, at: t))

            t += dt
        }

        return results
    }

    // MARK: - Helpers

    private static func resolvePositionTargeting(
        zoomWaypoints: [CameraWaypoint],
        zoomIndex: Int,
        targetZoom: CGFloat,
        effectiveZoomMult: CGFloat,
        isZoomTransitioning: Bool,
        startupBiasActive: Bool,
        initialCenter: NormalizedPoint,
        posTarget: NormalizedPoint,
        time: TimeInterval,
        intentSpans: [IntentSpan],
        settings: ContinuousCameraSettings
    ) -> PositionTargeting {
        if isZoomTransitioning {
            let waypointCenter = zoomWaypoints[zoomIndex].targetCenter
            let clampedCenter = ShotPlanner.clampCenter(waypointCenter, zoom: targetZoom)
            return PositionTargeting(
                target: clampedCenter,
                omega: 2.0 * .pi / max(0.001, settings.zoomResponse * effectiveZoomMult),
                damping: settings.zoomDampingRatio
            )
        }

        if startupBiasActive {
            return PositionTargeting(
                target: initialCenter,
                omega: 2.0 * .pi / max(0.001, settings.positionResponse),
                damping: settings.positionDampingRatio
            )
        }

        let timeToNext = AdaptiveResponse.findNextActionTime(
            after: time,
            intentSpans: intentSpans
        )
        let adaptiveResponse = AdaptiveResponse.compute(
            timeToNextAction: timeToNext,
            settings: settings.deadZone
        )
        return PositionTargeting(
            target: posTarget,
            omega: 2.0 * .pi / max(0.001, adaptiveResponse),
            damping: settings.positionDampingRatio
        )
    }

    /// Clamp camera state to valid bounds with soft pushback on center axes.
    private static func clampState(
        _ state: inout CameraState,
        settings: ContinuousCameraSettings,
        dt: CGFloat
    ) {
        if state.zoom < settings.minZoom {
            state.zoom = settings.minZoom
            state.velocityZoom = max(0, state.velocityZoom)
        } else if state.zoom > settings.maxZoom {
            state.zoom = settings.maxZoom
            state.velocityZoom = min(0, state.velocityZoom)
        }

        let clamped = ShotPlanner.clampCenter(
            NormalizedPoint(x: state.positionX, y: state.positionY),
            zoom: state.zoom
        )
        let overflowX = state.positionX - clamped.x
        let overflowY = state.positionY - clamped.y
        let stiffness = settings.boundaryStiffness
        let maxOverflow: CGFloat = 0.03

        if abs(overflowX) > 0.0001 {
            // Progressive velocity damping instead of sudden force
            let overflowRatio = min(1.0, abs(overflowX) / maxOverflow)
            let dampFactor = overflowRatio * 0.5
            state.velocityX *= max(0, 1.0 - dampFactor * dt * stiffness)
            state.velocityX -= overflowX * stiffness * 0.3 * dt
            if abs(overflowX) > maxOverflow {
                state.positionX = clamped.x + copysign(maxOverflow, overflowX)
            }
        }
        if abs(overflowY) > 0.0001 {
            let overflowRatio = min(1.0, abs(overflowY) / maxOverflow)
            let dampFactor = overflowRatio * 0.5
            state.velocityY *= max(0, 1.0 - dampFactor * dt * stiffness)
            state.velocityY -= overflowY * stiffness * 0.3 * dt
            if abs(overflowY) > maxOverflow {
                state.positionY = clamped.y + copysign(maxOverflow, overflowY)
            }
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

    private static func isTypingIntent(
        _ intentSpans: [IntentSpan],
        at index: Int
    ) -> Bool {
        guard index < intentSpans.count else { return false }
        if case .typing = intentSpans[index].intent {
            return true
        }
        return false
    }

    // MARK: - Spring Math

    /// Solve the damped harmonic oscillator analytically for one timestep.
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
            let zo = zeta * omega
            let decay = exp(-zo * dt)
            let coeffA = displacement
            let coeffB = v0 + zo * displacement
            let newPos = target + (coeffA + coeffB * dt) * decay
            let newVel = (coeffB - zo * (coeffA + coeffB * dt)) * decay
            return (newPos, newVel)
        } else {
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
