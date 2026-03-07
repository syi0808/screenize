import Foundation
import CoreGraphics

/// Easing curve types
/// Defines how interpolation happens between keyframes
enum EasingCurve: Codable, Equatable, Hashable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    /// Cubic Bezier curve
    case cubicBezier(p1x: CGFloat, p1y: CGFloat, p2x: CGFloat, p2y: CGFloat)

    /// Spring animation
    /// - dampingRatio: Damping ratio (0–1: underdamped with bounce, 1: critically damped, >1: overdamped)
    /// - response: Response time (approximate oscillation period in seconds)
    case spring(dampingRatio: CGFloat, response: CGFloat)

    /// Apply the easing function
    /// - Parameters:
    ///   - t: Progress (0.0–1.0)
    ///   - duration: Actual duration of the keyframe segment in seconds (used by spring easing)
    /// - Returns: Eased value (0.0–1.0)
    func apply(_ t: CGFloat, duration: CGFloat = 1.0) -> CGFloat {
        // Clamp the input
        let clampedT = clamp(t, min: 0, max: 1)

        let result: CGFloat
        switch self {
        case .linear:
            result = clampedT

        case .easeIn:
            // Square function (acceleration)
            result = clampedT * clampedT

        case .easeOut:
            // Inverted square function (deceleration)
            result = clampedT * (2 - clampedT)

        case .easeInOut:
            // Accelerate then decelerate
            if clampedT < 0.5 {
                result = 2 * clampedT * clampedT
            } else {
                result = -1 + (4 - 2 * clampedT) * clampedT
            }

        case .cubicBezier(let p1x, let p1y, let p2x, let p2y):
            // Compute the Cubic Bezier curve
            result = cubicBezierValue(t: clampedT, p1x: p1x, p1y: p1y, p2x: p2x, p2y: p2y)

        case .spring:
            result = springValue(t: clampedT, duration: duration)
        }

        // Clamp the output to 0–1
        return clamp(result, min: 0, max: 1)
    }

    /// Return the raw value without clamping
    func applyUnclamped(_ t: Double) -> Double {
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t
        case .easeOut:
            return t * (2 - t)
        case .easeInOut:
            return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
        case .cubicBezier(let p1x, let p1y, let p2x, let p2y):
            return Double(cubicBezierValue(t: CGFloat(t), p1x: p1x, p1y: p1y, p2x: p2x, p2y: p2y))
        case .spring(let zeta, let responseParam):
            let omega = 2.0 * .pi / max(0.01, Double(responseParam))
            let raw = Double(springRawValue(
                zeta: CGFloat(zeta), omega: CGFloat(omega), actualTime: CGFloat(t)
            ))
            let endVal = Double(springRawValue(
                zeta: CGFloat(zeta), omega: CGFloat(omega), actualTime: 1.0
            ))
            guard abs(endVal) > 0.001 else { return t }
            return raw / endVal
        }
    }

    /// Compute the derivative (velocity) of the easing function
    /// Used for calculating motion blur intensity
    /// - Parameters:
    ///   - t: Progress (0.0–1.0)
    ///   - duration: Actual duration of the keyframe segment in seconds
    /// - Returns: Instantaneous velocity at the point (normalized, 1.0 equals linear speed)
    func derivative(_ t: CGFloat, duration: CGFloat = 1.0) -> CGFloat {
        let clampedT = clamp(t, min: 0, max: 1)

        switch self {
        case .linear:
            // f(t) = t → f'(t) = 1
            return 1.0

        case .easeIn:
            // f(t) = t² → f'(t) = 2t
            return 2.0 * clampedT

        case .easeOut:
            // f(t) = 2t - t² → f'(t) = 2 - 2t
            return 2.0 - 2.0 * clampedT

        case .easeInOut:
            // t < 0.5: f(t) = 2t² → f'(t) = 4t
            // t >= 0.5: f(t) = -1 + 4t - 2t² → f'(t) = 4 - 4t
            if clampedT < 0.5 {
                return 4.0 * clampedT
            } else {
                return 4.0 - 4.0 * clampedT
            }

        case .cubicBezier(let p1x, let p1y, let p2x, let p2y):
            return cubicBezierDerivative(t: clampedT, p1x: p1x, p1y: p1y, p2x: p2x, p2y: p2y)

        case .spring:
            return springDerivative(t: clampedT, duration: duration)
        }
    }

    /// Calculate the spring derivative with respect to normalized t.
    /// Returns d(value)/d(t_normalized) where t_normalized is in [0, 1].
    private func springDerivative(t: CGFloat, duration: CGFloat) -> CGFloat {
        guard case .spring(let zeta, let responseParam) = self else { return 1.0 }
        let omega = 2.0 * .pi / max(0.01, responseParam)
        let actualTime = t * duration

        let rawDeriv: CGFloat
        if zeta >= 1.0 {
            // Critically damped: d/dt[1 - (1+ζωt)e^(-ζωt)] = (ζω)²t·e^(-ζωt)
            let zo = zeta * omega
            let decay = exp(-zo * actualTime)
            rawDeriv = zo * zo * actualTime * decay
        } else {
            // Underdamped: derivative of 1 - e^(-ζωt)(cos(ωd·t) + (ζω/ωd)sin(ωd·t))
            let wd = omega * sqrt(1.0 - zeta * zeta)
            let zo = zeta * omega
            let decay = exp(-zo * actualTime)
            let cosVal = cos(wd * actualTime)
            let sinVal = sin(wd * actualTime)
            let ratio = zo / wd
            // d/dt = e^(-ζωt) * [(ζω)(cos + ratio·sin) + (wd·sin - ratio·wd·cos)]
            //       = e^(-ζωt) * [ζω·cos + ζω·ratio·sin + wd·sin - ratio·wd·cos]
            //       = e^(-ζωt) * [(ζω - ratio·wd)cos + (ζω·ratio + wd)sin]
            // Since ratio = ζω/wd: ratio·wd = ζω, ζω·ratio = (ζω)²/wd
            //       = e^(-ζωt) * [0·cos + ((ζω)²/wd + wd)sin]
            //       = e^(-ζωt) * (omega²/wd) * sin(wd·t)
            rawDeriv = decay * (omega * omega / wd) * sinVal
        }

        // Normalize: d(normalized_value)/d(t_norm) = rawDeriv * duration / endValue
        let endValue = springRawValue(
            zeta: zeta, omega: omega, actualTime: duration
        )
        guard abs(endValue) > 0.001 else { return 1.0 }
        return rawDeriv * duration / endValue
    }

    /// Calculate the cubic Bezier derivative
    private func cubicBezierDerivative(t: CGFloat, p1x: CGFloat, p1y: CGFloat, p2x: CGFloat, p2y: CGFloat) -> CGFloat {
        // Solve for t corresponding to x (Newton-Raphson)
        let epsilon: CGFloat = 0.0001
        var x = t

        for _ in 0..<10 {
            let xValue = bezierX(x, p1x: p1x, p2x: p2x)
            let diff = xValue - t
            if abs(diff) < epsilon { break }
            let dx = bezierXDerivative(x, p1x: p1x, p2x: p2x)
            if abs(dx) < epsilon { break }
            x -= diff / dx
        }

        // dy/dt = (dy/dx) where x is the bezier parameter
        let dyDx = bezierYDerivative(x, p1y: p1y, p2y: p2y)
        let dxDt = bezierXDerivative(x, p1x: p1x, p2x: p2x)

        guard abs(dxDt) > epsilon else { return 1.0 }
        return dyDx / dxDt
    }

    private func bezierYDerivative(_ t: CGFloat, p1y: CGFloat, p2y: CGFloat) -> CGFloat {
        let t2 = t * t
        let mt = 1 - t
        return 3 * mt * mt * p1y + 6 * mt * t * (p2y - p1y) + 3 * t2 * (1 - p2y)
    }

    // MARK: - Private Helpers

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    /// Damped harmonic oscillator spring calculation.
    /// Uses stored dampingRatio and response parameters.
    /// - Parameters:
    ///   - t: Normalized progress (0.0–1.0)
    ///   - duration: Actual duration of the keyframe segment in seconds
    /// - Returns: Normalized spring value (0.0 at t=0, 1.0 at t=1)
    private func springValue(t: CGFloat, duration: CGFloat) -> CGFloat {
        guard case .spring(let zeta, let responseParam) = self else { return t }
        let omega = 2.0 * .pi / max(0.01, responseParam)
        let actualTime = t * duration

        let rawValue = springRawValue(
            zeta: zeta, omega: omega, actualTime: actualTime
        )
        let endValue = springRawValue(
            zeta: zeta, omega: omega, actualTime: duration
        )

        // Normalize so value = 1.0 at t = 1.0
        guard abs(endValue) > 0.001 else { return t }
        return rawValue / endValue
    }

    /// Raw damped harmonic oscillator value (not normalized to [0,1] at end).
    private func springRawValue(
        zeta: CGFloat, omega: CGFloat, actualTime: CGFloat
    ) -> CGFloat {
        if zeta >= 1.0 {
            // Critically damped or overdamped
            let zo = zeta * omega
            let decay = exp(-zo * actualTime)
            return 1.0 - (1.0 + zo * actualTime) * decay
        } else {
            // Underdamped (oscillatory)
            let wd = omega * sqrt(1.0 - zeta * zeta)
            let zo = zeta * omega
            let decay = exp(-zo * actualTime)
            return 1.0 - decay * (
                cos(wd * actualTime)
                + (zo / wd) * sin(wd * actualTime)
            )
        }
    }

    /// Compute the Cubic Bezier curve
    /// P0 = (0, 0), P1 = (p1x, p1y), P2 = (p2x, p2y), P3 = (1, 1)
    private func cubicBezierValue(t: CGFloat, p1x: CGFloat, p1y: CGFloat, p2x: CGFloat, p2y: CGFloat) -> CGFloat {
        // Use Newton-Raphson to find the x value corresponding to t
        let epsilon: CGFloat = 0.0001
        var x = t

        for _ in 0..<10 {
            let xValue = bezierX(x, p1x: p1x, p2x: p2x)
            let diff = xValue - t
            if abs(diff) < epsilon {
                break
            }
            let derivative = bezierXDerivative(x, p1x: p1x, p2x: p2x)
            if abs(derivative) < epsilon {
                break
            }
            x -= diff / derivative
        }

        return bezierY(x, p1y: p1y, p2y: p2y)
    }

    private func bezierX(_ t: CGFloat, p1x: CGFloat, p2x: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        let mt = 1 - t
        let mt2 = mt * mt
        return 3 * mt2 * t * p1x + 3 * mt * t2 * p2x + t3
    }

    private func bezierY(_ t: CGFloat, p1y: CGFloat, p2y: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        let mt = 1 - t
        let mt2 = mt * mt
        return 3 * mt2 * t * p1y + 3 * mt * t2 * p2y + t3
    }

    private func bezierXDerivative(_ t: CGFloat, p1x: CGFloat, p2x: CGFloat) -> CGFloat {
        let t2 = t * t
        let mt = 1 - t
        return 3 * mt * mt * p1x + 6 * mt * t * (p2x - p1x) + 3 * t2 * (1 - p2x)
    }

    // MARK: - Presets

    /// Common easing presets
    static let smooth = Self.easeInOut
    static let accelerate = Self.easeIn
    static let decelerate = Self.easeOut

    /// CSS standard easing
    static let cssEase = Self.cubicBezier(p1x: 0.25, p1y: 0.1, p2x: 0.25, p2y: 1.0)
    static let cssEaseIn = Self.cubicBezier(p1x: 0.42, p1y: 0, p2x: 1, p2y: 1)
    static let cssEaseOut = Self.cubicBezier(p1x: 0, p1y: 0, p2x: 0.58, p2y: 1)
    static let cssEaseInOut = Self.cubicBezier(p1x: 0.42, p1y: 0, p2x: 0.58, p2y: 1)

    /// Spring presets
    /// Base spring (smooth deceleration, no bounce)
    static let springDefault = Self.spring(dampingRatio: 1.0, response: 0.8)
    /// Gentle spring (no bounce, slower)
    static let springSmooth = Self.spring(dampingRatio: 1.0, response: 1.0)
    /// Elastic spring (slight bounce)
    static let springBouncy = Self.spring(dampingRatio: 0.75, response: 0.9)
    /// Quick spring (responsive)
    static let springSnappy = Self.spring(dampingRatio: 0.95, response: 0.5)

    // MARK: - Display

    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .easeIn: return "Ease In"
        case .easeOut: return "Ease Out"
        case .easeInOut: return "Ease In Out"
        case .cubicBezier: return "Custom Bezier"
        case .spring(let damping, _):
            if damping >= 1.0 {
                return "Spring (Smooth)"
            } else if damping >= 0.7 {
                return "Spring"
            } else {
                return "Spring (Bouncy)"
            }
        }
    }

    /// Check if this curve is a spring
    var isSpring: Bool {
        if case .spring = self { return true }
        return false
    }
}

// MARK: - Codable

extension EasingCurve {
    private enum CodingKeys: String, CodingKey {
        case type, p1x, p1y, p2x, p2y, dampingRatio, response
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "linear":
            self = .linear
        case "easeIn":
            self = .easeIn
        case "easeOut":
            self = .easeOut
        case "easeInOut":
            self = .easeInOut
        case "cubicBezier":
            let p1x = try container.decode(CGFloat.self, forKey: .p1x)
            let p1y = try container.decode(CGFloat.self, forKey: .p1y)
            let p2x = try container.decode(CGFloat.self, forKey: .p2x)
            let p2y = try container.decode(CGFloat.self, forKey: .p2y)
            self = .cubicBezier(p1x: p1x, p1y: p1y, p2x: p2x, p2y: p2y)
        case "spring":
            let dampingRatio = try container.decode(CGFloat.self, forKey: .dampingRatio)
            let response = try container.decode(CGFloat.self, forKey: .response)
            self = .spring(dampingRatio: dampingRatio, response: response)
        default:
            self = .linear
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .linear:
            try container.encode("linear", forKey: .type)
        case .easeIn:
            try container.encode("easeIn", forKey: .type)
        case .easeOut:
            try container.encode("easeOut", forKey: .type)
        case .easeInOut:
            try container.encode("easeInOut", forKey: .type)
        case .cubicBezier(let p1x, let p1y, let p2x, let p2y):
            try container.encode("cubicBezier", forKey: .type)
            try container.encode(p1x, forKey: .p1x)
            try container.encode(p1y, forKey: .p1y)
            try container.encode(p2x, forKey: .p2x)
            try container.encode(p2y, forKey: .p2y)
        case .spring(let dampingRatio, let response):
            try container.encode("spring", forKey: .type)
            try container.encode(dampingRatio, forKey: .dampingRatio)
            try container.encode(response, forKey: .response)
        }
    }
}
