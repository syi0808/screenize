import XCTest
import CoreGraphics
@testable import Screenize

final class AXTargetResolverTests: XCTestCase {

    // MARK: - Helpers

    private func makeTarget(
        role: String = "AXButton",
        axTitle: String? = "OK",
        axValue: String? = nil,
        path: [String] = ["AXWindow", "AXGroup", "AXButton"],
        positionHint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        absoluteCoord: CGPoint = CGPoint(x: 500, y: 400)
    ) -> AXTarget {
        AXTarget(
            role: role,
            axTitle: axTitle,
            axValue: axValue,
            path: path,
            positionHint: positionHint,
            absoluteCoord: absoluteCoord
        )
    }

    // MARK: - Strategy Selection

    func testResolveStrategiesAllFields() {
        // Target with all fields populated: path + title → all 4 strategies
        let target = makeTarget(
            axTitle: "OK",
            path: ["AXWindow", "AXGroup", "AXButton"]
        )
        let strategies = AXTargetResolver.availableStrategies(for: target)
        XCTAssertEqual(strategies, [.pathAndTitle, .titleOnly, .roleAndPosition, .coordinate])
    }

    func testResolveStrategiesNoTitle() {
        // Target with axTitle=nil → skip pathAndTitle and titleOnly
        let target = makeTarget(
            axTitle: nil,
            path: ["AXWindow", "AXGroup", "AXButton"]
        )
        let strategies = AXTargetResolver.availableStrategies(for: target)
        XCTAssertEqual(strategies, [.roleAndPosition, .coordinate])
    }

    func testResolveStrategiesNoPath() {
        // Target with empty path → skip pathAndTitle, keep titleOnly
        let target = makeTarget(
            axTitle: "OK",
            path: []
        )
        let strategies = AXTargetResolver.availableStrategies(for: target)
        XCTAssertEqual(strategies, [.titleOnly, .roleAndPosition, .coordinate])
    }

    func testResolveStrategiesMinimal() {
        // Target with only absoluteCoord meaningful → no title, no path, zero positionHint
        // According to spec: [coordinate] only when no title and positionHint is zero.
        let target = makeTarget(
            axTitle: nil,
            path: [],
            positionHint: .zero
        )
        let strategies = AXTargetResolver.availableStrategies(for: target)
        XCTAssertEqual(strategies, [.coordinate])
    }

    func testResolveStrategiesNoTitleWithPositionHint() {
        // Target with nil title, empty path, but non-zero positionHint → [roleAndPosition, coordinate]
        let target = AXTarget(
            role: "AXButton",
            axTitle: nil,
            axValue: nil,
            path: [],
            positionHint: CGPoint(x: 0.5, y: 0.5),
            absoluteCoord: CGPoint(x: 300, y: 200)
        )
        let strategies = AXTargetResolver.availableStrategies(for: target)
        XCTAssertEqual(strategies, [.roleAndPosition, .coordinate])
    }

    // MARK: - Position Hint Conversion

    func testPositionHintToAbsoluteCenter() {
        // (0.5, 0.5) with captureArea (100, 200, 800, 600) → (500, 500)
        let captureArea = CGRect(x: 100, y: 200, width: 800, height: 600)
        let hint = CGPoint(x: 0.5, y: 0.5)
        let result = AXTargetResolver.absolutePosition(from: hint, captureArea: captureArea)
        XCTAssertEqual(result.x, 500, accuracy: 0.001)
        XCTAssertEqual(result.y, 500, accuracy: 0.001)
    }

    func testPositionHintToAbsoluteTopLeft() {
        // (0, 0) → origin of captureArea
        let captureArea = CGRect(x: 100, y: 200, width: 800, height: 600)
        let hint = CGPoint(x: 0, y: 0)
        let result = AXTargetResolver.absolutePosition(from: hint, captureArea: captureArea)
        XCTAssertEqual(result.x, 100, accuracy: 0.001)
        XCTAssertEqual(result.y, 200, accuracy: 0.001)
    }

    func testPositionHintToAbsoluteBottomRight() {
        // (1, 1) → origin + size of captureArea
        let captureArea = CGRect(x: 100, y: 200, width: 800, height: 600)
        let hint = CGPoint(x: 1.0, y: 1.0)
        let result = AXTargetResolver.absolutePosition(from: hint, captureArea: captureArea)
        XCTAssertEqual(result.x, 900, accuracy: 0.001)
        XCTAssertEqual(result.y, 800, accuracy: 0.001)
    }

    func testPositionHintToAbsoluteZeroSizeCapture() {
        // Zero-size captureArea → always returns origin
        let captureArea = CGRect(x: 50, y: 75, width: 0, height: 0)
        let hint = CGPoint(x: 0.5, y: 0.5)
        let result = AXTargetResolver.absolutePosition(from: hint, captureArea: captureArea)
        XCTAssertEqual(result.x, 50, accuracy: 0.001)
        XCTAssertEqual(result.y, 75, accuracy: 0.001)
    }

    // MARK: - Path Component Parsing

    func testParsePathComponentSimpleRole() {
        let (role, index) = AXTargetResolver.parsePathComponent("AXButton")
        XCTAssertEqual(role, "AXButton")
        XCTAssertNil(index)
    }

    func testParsePathComponentWithIndex() {
        // "AXButton[2]" → role="AXButton", index=2
        let (role, index) = AXTargetResolver.parsePathComponent("AXButton[2]")
        XCTAssertEqual(role, "AXButton")
        XCTAssertEqual(index, 2)
    }

    func testParsePathComponentWithIndexZero() {
        let (role, index) = AXTargetResolver.parsePathComponent("AXGroup[0]")
        XCTAssertEqual(role, "AXGroup")
        XCTAssertEqual(index, 0)
    }

    func testParsePathComponentMalformedBrackets() {
        // "AXButton[abc]" → role="AXButton", index=nil (non-numeric)
        let (role, index) = AXTargetResolver.parsePathComponent("AXButton[abc]")
        XCTAssertEqual(role, "AXButton")
        XCTAssertNil(index)
    }

    func testParsePathComponentEmptyString() {
        let (role, index) = AXTargetResolver.parsePathComponent("")
        XCTAssertEqual(role, "")
        XCTAssertNil(index)
    }

    func testParsePathComponentUnclosedBracket() {
        // "AXButton[2" → treat as plain role
        let (role, index) = AXTargetResolver.parsePathComponent("AXButton[2")
        XCTAssertEqual(role, "AXButton[2")
        XCTAssertNil(index)
    }

    // MARK: - Resolver Instantiation

    func testResolverCanBeInstantiated() {
        let resolver = AXTargetResolver()
        XCTAssertNotNil(resolver)
    }

    // MARK: - Async resolve returns coordinate fallback for unreachable target

    func testResolveReturnsFallbackCoordinateForInvalidTarget() async {
        let resolver = AXTargetResolver()
        let target = makeTarget(
            role: "AXButton",
            axTitle: nil,
            path: [],
            positionHint: .zero,
            absoluteCoord: CGPoint(x: 123, y: 456)
        )
        let captureArea = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let result = await resolver.resolve(target: target, captureArea: captureArea)
        // Strategy chain with no title and no path falls to coordinate only
        switch result {
        case .coordinate(let point):
            XCTAssertEqual(point.x, 123, accuracy: 0.001)
            XCTAssertEqual(point.y, 456, accuracy: 0.001)
        case .element:
            XCTFail("Expected coordinate fallback, got element")
        case nil:
            XCTFail("Expected coordinate fallback, got nil")
        }
    }
}
