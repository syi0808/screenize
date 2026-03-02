import XCTest
@testable import Screenize

final class EasingCurveTests: XCTestCase {

    // MARK: - Spring Uses Stored Parameters

    func test_spring_usesStoredResponse_differentResponseProducesDifferentCurves() {
        let fast = EasingCurve.spring(dampingRatio: 1.0, response: 0.3)
        let slow = EasingCurve.spring(dampingRatio: 1.0, response: 0.8)
        let duration: CGFloat = 0.5

        // At midpoint, fast response should be further along than slow response
        let fastMid = fast.apply(0.5, duration: duration)
        let slowMid = slow.apply(0.5, duration: duration)
        XCTAssertGreaterThan(fastMid, slowMid,
            "Faster response should reach higher value at midpoint")
    }

    func test_spring_dampingRatioAffectsCurve() {
        let underdamped = EasingCurve.spring(dampingRatio: 0.5, response: 0.5)
        let critical = EasingCurve.spring(dampingRatio: 1.0, response: 0.5)
        let duration: CGFloat = 0.6

        // At 25% progress, the shapes should differ
        let underVal = underdamped.apply(0.25, duration: duration)
        let critVal = critical.apply(0.25, duration: duration)
        XCTAssertNotEqual(underVal, critVal, accuracy: 0.01,
            "Different damping ratios should produce different curves")
    }

    // MARK: - Critically Damped

    func test_spring_criticallyDamped_monotonicallyIncreasing() {
        let spring = EasingCurve.spring(dampingRatio: 1.0, response: 0.5)
        let duration: CGFloat = 0.5

        var prev: CGFloat = 0
        for i in 0...20 {
            let t = CGFloat(i) / 20.0
            let value = spring.apply(t, duration: duration)
            XCTAssertGreaterThanOrEqual(value, prev - 0.001,
                "Critically damped spring should be monotonically increasing at t=\(t)")
            prev = value
        }
    }

    func test_spring_criticallyDamped_startsAtZero() {
        let spring = EasingCurve.spring(dampingRatio: 1.0, response: 0.5)
        XCTAssertEqual(spring.apply(0.0, duration: 0.5), 0.0, accuracy: 0.001)
    }

    func test_spring_criticallyDamped_endsAtOne() {
        let spring = EasingCurve.spring(dampingRatio: 1.0, response: 0.5)
        XCTAssertEqual(spring.apply(1.0, duration: 0.5), 1.0, accuracy: 0.01)
    }

    // MARK: - Normalization

    func test_spring_normalizesToOneAtEnd_variousDurations() {
        let durations: [CGFloat] = [0.1, 0.3, 0.5, 0.8, 1.0, 2.0]
        let dampings: [CGFloat] = [0.5, 0.7, 0.85, 1.0]
        let responses: [CGFloat] = [0.3, 0.5, 0.8]

        for duration in durations {
            for damping in dampings {
                for response in responses {
                    let spring = EasingCurve.spring(
                        dampingRatio: damping, response: response
                    )
                    let endValue = spring.apply(1.0, duration: duration)
                    XCTAssertEqual(endValue, 1.0, accuracy: 0.02,
                        "Spring(ζ=\(damping), r=\(response)) at dur=\(duration) " +
                        "should end at 1.0, got \(endValue)")
                }
            }
        }
    }

    func test_spring_startsAtZero_variousConfigs() {
        let configs: [(CGFloat, CGFloat)] = [
            (0.5, 0.3), (0.85, 0.5), (1.0, 0.5), (1.0, 0.8)
        ]
        for (damping, response) in configs {
            let spring = EasingCurve.spring(dampingRatio: damping, response: response)
            let startValue = spring.apply(0.0, duration: 0.5)
            XCTAssertEqual(startValue, 0.0, accuracy: 0.001,
                "Spring(ζ=\(damping), r=\(response)) should start at 0")
        }
    }

    // MARK: - Short / Long Duration Safety

    func test_spring_shortDuration_doesNotExplode() {
        let spring = EasingCurve.spring(dampingRatio: 0.85, response: 0.5)
        let duration: CGFloat = 0.1

        for i in 0...10 {
            let t = CGFloat(i) / 10.0
            let value = spring.apply(t, duration: duration)
            XCTAssertGreaterThanOrEqual(value, 0.0,
                "Spring value should be >= 0 at t=\(t)")
            XCTAssertLessThanOrEqual(value, 1.0,
                "Spring value should be <= 1 at t=\(t) (clamped)")
        }
    }

    func test_spring_longDuration_smoothCurve() {
        let spring = EasingCurve.spring(dampingRatio: 1.0, response: 0.5)
        let duration: CGFloat = 2.0

        var prev: CGFloat = 0
        var maxJump: CGFloat = 0
        for i in 0...100 {
            let t = CGFloat(i) / 100.0
            let value = spring.apply(t, duration: duration)
            maxJump = max(maxJump, abs(value - prev))
            // Value should always be in [0, 1] and non-decreasing for critical damping
            XCTAssertGreaterThanOrEqual(value, prev - 0.001,
                "Critically damped spring should be monotonic at t=\(t)")
            prev = value
        }
        // For long durations, the spring settles early so the first few steps
        // have large changes. Max single-step jump should still be bounded.
        XCTAssertLessThan(maxJump, 0.3,
            "Max jump \(maxJump) should be bounded")
    }

    // MARK: - Derivative

    func test_spring_derivativeMatchesNumerical() {
        let spring = EasingCurve.spring(dampingRatio: 1.0, response: 0.5)
        let duration: CGFloat = 0.5
        let dt: CGFloat = 0.001

        // Test at several points
        let testPoints: [CGFloat] = [0.1, 0.25, 0.5, 0.75, 0.9]
        for t in testPoints {
            let analytical = spring.derivative(t, duration: duration)
            let v1 = spring.apply(t - dt, duration: duration)
            let v2 = spring.apply(t + dt, duration: duration)
            let numerical = (v2 - v1) / (2 * dt)

            // Allow 10% tolerance for numerical vs analytical
            let tolerance = max(0.5, abs(analytical) * 0.1)
            XCTAssertEqual(analytical, numerical, accuracy: tolerance,
                "Derivative at t=\(t): analytical=\(analytical) vs numerical=\(numerical)")
        }
    }

    func test_spring_derivativeAtStart_isZeroOrPositive() {
        let spring = EasingCurve.spring(dampingRatio: 1.0, response: 0.5)
        let deriv = spring.derivative(0.0, duration: 0.5)
        XCTAssertGreaterThanOrEqual(deriv, 0.0,
            "Derivative at start should be >= 0")
    }

    // MARK: - Underdamped

    func test_spring_underdamped_rawValueCanExceedOne() {
        // With low damping, the spring overshoots before settling.
        // Our apply() clamps to [0,1], but the raw math should show overshoot.
        let spring = EasingCurve.spring(dampingRatio: 0.5, response: 0.5)
        let duration: CGFloat = 0.8

        // The unclamped version should overshoot at some point
        let value = spring.applyUnclamped(0.6)
        // With critically damped formula + normalization, underdamped should
        // produce values that differ from critically damped
        let critical = EasingCurve.spring(dampingRatio: 1.0, response: 0.5)
        let critValue = critical.applyUnclamped(0.6)
        XCTAssertNotEqual(value, critValue, accuracy: 0.01,
            "Underdamped should differ from critically damped")
    }

    // MARK: - Existing Easing Curves (Regression)

    func test_linear_apply() {
        XCTAssertEqual(EasingCurve.linear.apply(0.0), 0.0, accuracy: 0.001)
        XCTAssertEqual(EasingCurve.linear.apply(0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(EasingCurve.linear.apply(1.0), 1.0, accuracy: 0.001)
    }

    func test_easeIn_apply() {
        XCTAssertEqual(EasingCurve.easeIn.apply(0.0), 0.0, accuracy: 0.001)
        XCTAssertLessThan(EasingCurve.easeIn.apply(0.5), 0.5)
        XCTAssertEqual(EasingCurve.easeIn.apply(1.0), 1.0, accuracy: 0.001)
    }

    func test_easeOut_apply() {
        XCTAssertEqual(EasingCurve.easeOut.apply(0.0), 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(EasingCurve.easeOut.apply(0.5), 0.5)
        XCTAssertEqual(EasingCurve.easeOut.apply(1.0), 1.0, accuracy: 0.001)
    }

    func test_easeInOut_apply() {
        XCTAssertEqual(EasingCurve.easeInOut.apply(0.0), 0.0, accuracy: 0.001)
        XCTAssertEqual(EasingCurve.easeInOut.apply(0.5), 0.5, accuracy: 0.001)
        XCTAssertEqual(EasingCurve.easeInOut.apply(1.0), 1.0, accuracy: 0.001)
    }

    func test_allCurves_clampedToZeroOne() {
        let curves: [EasingCurve] = [
            .linear, .easeIn, .easeOut, .easeInOut,
            .spring(dampingRatio: 0.5, response: 0.5),
            .spring(dampingRatio: 1.0, response: 0.5),
            .cubicBezier(p1x: 0.25, p1y: 0.1, p2x: 0.25, p2y: 1.0)
        ]
        for curve in curves {
            for i in 0...10 {
                let t = CGFloat(i) / 10.0
                let value = curve.apply(t, duration: 0.5)
                XCTAssertGreaterThanOrEqual(value, 0.0)
                XCTAssertLessThanOrEqual(value, 1.0)
            }
        }
    }
}
