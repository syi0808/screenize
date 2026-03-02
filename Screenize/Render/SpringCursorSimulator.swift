import Foundation
import CoreGraphics

// MARK: - Spring Cursor Configuration

/// Configuration for spring-based cursor smoothing.
/// Controls how the rendered cursor "follows" the actual recorded cursor position
/// using damped harmonic oscillator dynamics.
struct SpringCursorConfig: Codable, Equatable, Hashable {

    /// Damping ratio: 1.0 = critically damped (no overshoot),
    /// < 1.0 = underdamped (subtle overshoot), > 1.0 = overdamped (sluggish)
    var dampingRatio: CGFloat

    /// Response time in seconds. Lower = snappier, higher = more lag.
    /// Maps to natural frequency: omega = 2*pi / response
    var response: CGFloat

    /// Reduce lag for fast cursor movements
    var adaptiveResponse: Bool

    /// Maximum velocity (normalized units/sec) at which response is fully reduced.
    /// Only used when adaptiveResponse is true.
    var adaptiveMaxVelocity: CGFloat

    /// Minimum response multiplier for adaptive mode.
    /// At max velocity, response drops to this fraction of the base response.
    var adaptiveMinScale: CGFloat

    static let `default` = Self(
        dampingRatio: 0.85,
        response: 0.08,
        adaptiveResponse: true,
        adaptiveMaxVelocity: 3.0,
        adaptiveMinScale: 0.3
    )

    /// Passthrough (effectively no smoothing)
    static let none = Self(
        dampingRatio: 1.0,
        response: 0.001,
        adaptiveResponse: false,
        adaptiveMaxVelocity: 3.0,
        adaptiveMinScale: 0.3
    )
}

// MARK: - Spring Cursor Simulator

/// Simulates a 2D spring system where the rendered cursor chases the actual cursor position.
/// Uses an analytical damped harmonic oscillator solution per timestep for deterministic,
/// stable results at any frame rate.
struct SpringCursorSimulator {

    /// Apply spring-following simulation to resampled cursor positions.
    /// - Parameters:
    ///   - positions: Cursor positions (typically from Catmull-Rom resampling)
    ///   - config: Spring configuration parameters
    /// - Returns: Spring-smoothed positions with the same timestamps
    static func simulate(
        _ positions: [RenderMousePosition],
        config: SpringCursorConfig
    ) -> [RenderMousePosition] {
        guard positions.count >= 2 else { return positions }

        var springX = positions[0].position.x
        var springY = positions[0].position.y
        var velX: CGFloat = 0
        var velY: CGFloat = 0

        var result: [RenderMousePosition] = []
        result.reserveCapacity(positions.count)
        result.append(positions[0])

        for i in 1..<positions.count {
            let target = positions[i].position
            let dt = CGFloat(positions[i].timestamp - positions[i - 1].timestamp)

            guard dt > 0.0001 else {
                result.append(RenderMousePosition(
                    timestamp: positions[i].timestamp,
                    x: springX, y: springY,
                    velocity: positions[i].velocity
                ))
                continue
            }

            let effectiveResponse = computeEffectiveResponse(
                config: config, velX: velX, velY: velY
            )
            let omega = 2.0 * .pi / max(0.001, effectiveResponse)
            let zeta = config.dampingRatio

            let (newX, newVX) = springStep(
                current: springX, velocity: velX,
                target: target.x, omega: omega, zeta: zeta, dt: dt
            )
            let (newY, newVY) = springStep(
                current: springY, velocity: velY,
                target: target.y, omega: omega, zeta: zeta, dt: dt
            )

            springX = newX
            springY = newY
            velX = newVX
            velY = newVY

            let springVelocity = sqrt(velX * velX + velY * velY)
            result.append(RenderMousePosition(
                timestamp: positions[i].timestamp,
                x: springX, y: springY,
                velocity: springVelocity
            ))
        }

        return result
    }

    // MARK: - Private

    /// Compute the effective response time, reducing lag for fast movements when adaptive mode is on
    private static func computeEffectiveResponse(
        config: SpringCursorConfig,
        velX: CGFloat,
        velY: CGFloat
    ) -> CGFloat {
        guard config.adaptiveResponse else { return config.response }

        let speed = sqrt(velX * velX + velY * velY)
        let normalizedSpeed = min(speed / max(0.001, config.adaptiveMaxVelocity), 1.0)
        let scale = 1.0 - (1.0 - config.adaptiveMinScale) * normalizedSpeed
        return config.response * scale
    }

    /// Solve the damped harmonic oscillator analytically for one timestep.
    /// Assumes the target is constant within the timestep (exponential integrator).
    /// - Returns: (newPosition, newVelocity)
    private static func springStep(
        current x0: CGFloat,
        velocity v0: CGFloat,
        target: CGFloat,
        omega: CGFloat,
        zeta: CGFloat,
        dt: CGFloat
    ) -> (position: CGFloat, velocity: CGFloat) {
        let displacement = x0 - target

        if zeta >= 1.0 {
            return criticallyDampedStep(
                displacement: displacement, velocity: v0,
                target: target, omega: omega, zeta: zeta, dt: dt
            )
        } else {
            return underdampedStep(
                displacement: displacement, velocity: v0,
                target: target, omega: omega, zeta: zeta, dt: dt
            )
        }
    }

    /// Critically damped or overdamped spring step (zeta >= 1)
    /// x(t) = target + (A + B*t) * e^(-zo*t)
    /// where A = x0 - target, B = v0 + zo*A
    private static func criticallyDampedStep(
        displacement: CGFloat,
        velocity: CGFloat,
        target: CGFloat,
        omega: CGFloat,
        zeta: CGFloat,
        dt: CGFloat
    ) -> (position: CGFloat, velocity: CGFloat) {
        let zo = zeta * omega
        let decay = exp(-zo * dt)

        let coeffA = displacement
        let coeffB = velocity + zo * displacement

        let newPos = target + (coeffA + coeffB * dt) * decay
        let newVel = (coeffB - zo * (coeffA + coeffB * dt)) * decay
        return (newPos, newVel)
    }

    /// Underdamped spring step (zeta < 1)
    /// x(t) = target + decay * [A*cos(wd*t) + B*sin(wd*t)]
    /// where wd = omega*sqrt(1 - zeta^2), A = x0 - target, B = (v0 + zo*A) / wd
    private static func underdampedStep(
        displacement: CGFloat,
        velocity: CGFloat,
        target: CGFloat,
        omega: CGFloat,
        zeta: CGFloat,
        dt: CGFloat
    ) -> (position: CGFloat, velocity: CGFloat) {
        let wd = omega * sqrt(1.0 - zeta * zeta)
        let zo = zeta * omega
        let decay = exp(-zo * dt)

        let coeffA = displacement
        let coeffB = (velocity + zo * displacement) / wd

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
