import XCTest
import CoreGraphics
@testable import Screenize

final class CoordinateScenarioHelpersTests: XCTestCase {

    // MARK: - cgNormalizedToNormalized

    func testCGNormalizedToNormalized_midPoint() {
        // (0.5, 0.2) in CG (top-left origin) → NormalizedPoint(x: 0.5, y: 0.8) (bottom-left origin)
        let input = CGPoint(x: 0.5, y: 0.2)
        let result = CoordinateConverter.cgNormalizedToNormalized(input)
        XCTAssertEqual(result.x, 0.5, accuracy: 1e-10)
        XCTAssertEqual(result.y, 0.8, accuracy: 1e-10)
    }

    func testCGNormalizedToNormalized_topLeftMapsToBottomLeft() {
        // (0.0, 0.0) is top-left in CG → should become bottom-left NormalizedPoint(x: 0.0, y: 1.0)
        let input = CGPoint(x: 0.0, y: 0.0)
        let result = CoordinateConverter.cgNormalizedToNormalized(input)
        XCTAssertEqual(result.x, 0.0, accuracy: 1e-10)
        XCTAssertEqual(result.y, 1.0, accuracy: 1e-10)
    }

    func testCGNormalizedToNormalized_bottomRightMapsToTopRight() {
        // (1.0, 1.0) is bottom-right in CG → should become NormalizedPoint(x: 1.0, y: 0.0) (top-right in bottom-left space)
        let input = CGPoint(x: 1.0, y: 1.0)
        let result = CoordinateConverter.cgNormalizedToNormalized(input)
        XCTAssertEqual(result.x, 1.0, accuracy: 1e-10)
        XCTAssertEqual(result.y, 0.0, accuracy: 1e-10)
    }

    // MARK: - normalizedToCGNormalized

    func testNormalizedToCGNormalized_midPoint() {
        // NormalizedPoint(x: 0.5, y: 0.8) → CGPoint(x: 0.5, y: 0.2)
        let input = NormalizedPoint(x: 0.5, y: 0.8)
        let result = CoordinateConverter.normalizedToCGNormalized(input)
        XCTAssertEqual(result.x, 0.5, accuracy: 1e-10)
        XCTAssertEqual(result.y, 0.2, accuracy: 1e-10)
    }

    // MARK: - Round-trip

    func testRoundTrip_cgNormalizedThroughNormalized() {
        let points: [CGPoint] = [
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: 1.0, y: 1.0),
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.25, y: 0.75),
            CGPoint(x: 0.9, y: 0.1)
        ]

        for point in points {
            let normalized = CoordinateConverter.cgNormalizedToNormalized(point)
            let restored = CoordinateConverter.normalizedToCGNormalized(normalized)
            XCTAssertEqual(restored.x, point.x, accuracy: 1e-10, "Round-trip failed for x at \(point)")
            XCTAssertEqual(restored.y, point.y, accuracy: 1e-10, "Round-trip failed for y at \(point)")
        }
    }

    // MARK: - Identity at center

    func testCenter_isInvariant() {
        // (0.5, 0.5) in CG normalized → NormalizedPoint(x: 0.5, y: 0.5); center is invariant under Y-flip
        let input = CGPoint(x: 0.5, y: 0.5)
        let result = CoordinateConverter.cgNormalizedToNormalized(input)
        XCTAssertEqual(result.x, 0.5, accuracy: 1e-10)
        XCTAssertEqual(result.y, 0.5, accuracy: 1e-10)
    }
}
