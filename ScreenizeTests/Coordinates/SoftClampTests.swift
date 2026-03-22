import XCTest
@testable import Screenize

final class SoftClampTests: XCTestCase {

    private let accuracy: CGFloat = 1e-6

    // MARK: - Scalar clamp

    func test_softClamp_interiorValue_unchanged() {
        // A value well inside the bounds should pass through unmodified.
        let result = SoftClamp.clamp(value: 0.5, min: 0.2, max: 0.8, cushion: 0.1)
        XCTAssertEqual(result, 0.5, accuracy: accuracy)
    }

    func test_softClamp_atBoundary_reachesLimit() {
        // At exactly the boundary the smoothstep should output 1.0,
        // so the result equals the boundary.
        let lower = SoftClamp.clamp(value: 0.0, min: 0.0, max: 1.0, cushion: 0.2)
        XCTAssertEqual(lower, 0.0, accuracy: accuracy)

        let upper = SoftClamp.clamp(value: 1.0, min: 0.0, max: 1.0, cushion: 0.2)
        XCTAssertEqual(upper, 1.0, accuracy: accuracy)
    }

    func test_softClamp_inCushionZone_easedTowardBoundary() {
        // A value inside the lower cushion zone should be eased —
        // it should be >= the boundary but less than the raw clamped value.
        let cushion: CGFloat = 0.2
        let rawValue: CGFloat = 0.1  // halfway into the cushion zone
        let result = SoftClamp.clamp(value: rawValue, min: 0.0, max: 1.0, cushion: cushion)

        // smoothstep(0.5) = 0.5, so result = 0 + 0.2 * 0.5 = 0.1
        // But smoothstep(0.5) = 0.5*0.5*(3-1) = 0.5, so 0.2*0.5 = 0.1
        // The eased value should equal 0.1 for the midpoint of the cushion.
        XCTAssertEqual(result, 0.1, accuracy: accuracy)

        // Test a point at 25% into the cushion (t=0.25)
        let quarterResult = SoftClamp.clamp(value: 0.05, min: 0.0, max: 1.0, cushion: cushion)
        // smoothstep(0.25) = 0.0625 * 2.5 = 0.15625, result = 0.2 * 0.15625 = 0.03125
        XCTAssertEqual(quarterResult, 0.03125, accuracy: accuracy)
        // Eased value should be less than raw value (pulled toward boundary)
        XCTAssertLessThan(quarterResult, 0.05)
    }

    func test_softClamp_beyondBoundary_clampedToLimit() {
        // Values outside the bounds should be hard-clamped to the boundary.
        let below = SoftClamp.clamp(value: -0.5, min: 0.0, max: 1.0, cushion: 0.2)
        XCTAssertEqual(below, 0.0, accuracy: accuracy)

        let above = SoftClamp.clamp(value: 1.5, min: 0.0, max: 1.0, cushion: 0.2)
        XCTAssertEqual(above, 1.0, accuracy: accuracy)
    }

    func test_softClamp_symmetricTopBoundary() {
        // Upper cushion should mirror the lower cushion behavior.
        let cushion: CGFloat = 0.2
        // 75% into the range = 25% from upper boundary = t=0.25 in upper cushion
        let result = SoftClamp.clamp(value: 0.95, min: 0.0, max: 1.0, cushion: cushion)
        // t = (1.0 - 0.95) / 0.2 = 0.25
        // smoothstep(0.25) = 0.15625
        // result = 1.0 - 0.2 * 0.15625 = 0.96875
        XCTAssertEqual(result, 0.96875, accuracy: accuracy)

        // At the midpoint of the upper cushion (t=0.5)
        let midResult = SoftClamp.clamp(value: 0.9, min: 0.0, max: 1.0, cushion: cushion)
        // t = (1.0 - 0.9) / 0.2 = 0.5, smoothstep(0.5) = 0.5
        // result = 1.0 - 0.2 * 0.5 = 0.9
        XCTAssertEqual(midResult, 0.9, accuracy: accuracy)
    }

    func test_softClamp_zeroCushion_hardClamp() {
        // Zero cushion should produce hard clamping.
        let result = SoftClamp.clamp(value: 0.3, min: 0.25, max: 0.75, cushion: 0.0)
        XCTAssertEqual(result, 0.3, accuracy: accuracy)

        let clamped = SoftClamp.clamp(value: 0.1, min: 0.25, max: 0.75, cushion: 0.0)
        XCTAssertEqual(clamped, 0.25, accuracy: accuracy)

        let negativeCushion = SoftClamp.clamp(value: 0.1, min: 0.25, max: 0.75, cushion: -0.1)
        XCTAssertEqual(negativeCushion, 0.25, accuracy: accuracy)
    }

    // MARK: - Center clamp

    func test_softClamp_clampCenter_atZoom() {
        // At zoom 2.0, viewportHalf = 0.25, bounds = [0.25, 0.75]
        // Center at (0.5, 0.5) should be unchanged.
        let center = SoftClamp.clampCenter(
            NormalizedPoint(x: 0.5, y: 0.5), zoom: 2.0
        )
        XCTAssertEqual(center.x, 0.5, accuracy: accuracy)
        XCTAssertEqual(center.y, 0.5, accuracy: accuracy)

        // Center at (0.0, 0.0) should be clamped to the lower bound (0.25).
        let cornerCenter = SoftClamp.clampCenter(
            NormalizedPoint(x: 0.0, y: 0.0), zoom: 2.0
        )
        XCTAssertEqual(cornerCenter.x, 0.25, accuracy: accuracy)
        XCTAssertEqual(cornerCenter.y, 0.25, accuracy: accuracy)

        // At zoom 1.0, always returns (0.5, 0.5).
        let noZoom = SoftClamp.clampCenter(
            NormalizedPoint(x: 0.1, y: 0.9), zoom: 1.0
        )
        XCTAssertEqual(noZoom.x, 0.5, accuracy: accuracy)
        XCTAssertEqual(noZoom.y, 0.5, accuracy: accuracy)

        // At zoom 4.0, viewportHalf = 0.125, bounds = [0.125, 0.875]
        // Center at (0.5, 0.5) should be unchanged.
        let zoom4 = SoftClamp.clampCenter(
            NormalizedPoint(x: 0.5, y: 0.5), zoom: 4.0
        )
        XCTAssertEqual(zoom4.x, 0.5, accuracy: accuracy)
        XCTAssertEqual(zoom4.y, 0.5, accuracy: accuracy)
    }
}
