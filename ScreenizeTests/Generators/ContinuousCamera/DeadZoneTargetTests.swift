import XCTest
@testable import Screenize

final class DeadZoneTargetTests: XCTestCase {

    func test_cursorInSafeZone_targetIsCurrentCenter() {
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.5, y: 0.5),
            cameraCenter: NormalizedPoint(x: 0.5, y: 0.5),
            zoom: 2.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        XCTAssertEqual(result.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.y, 0.5, accuracy: 0.001)
    }

    func test_cursorSlightlyOffCenter_stillInSafeZone() {
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.6, y: 0.5),
            cameraCenter: NormalizedPoint(x: 0.5, y: 0.5),
            zoom: 2.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        XCTAssertEqual(result.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.y, 0.5, accuracy: 0.001)
    }

    func test_cursorInTriggerZone_targetMovesPartially() {
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.73, y: 0.5),
            cameraCenter: NormalizedPoint(x: 0.5, y: 0.5),
            zoom: 2.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        XCTAssertGreaterThan(result.x, 0.5)
        XCTAssertLessThan(result.x, 0.73)
        XCTAssertEqual(result.y, 0.5, accuracy: 0.001)
    }

    func test_cursorOutsideViewport_targetPullsInside() {
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.8, y: 0.5),
            cameraCenter: NormalizedPoint(x: 0.5, y: 0.5),
            zoom: 2.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        XCTAssertGreaterThan(result.x, 0.5)
    }

    func test_cursorInGradientBand_targetBlended() {
        let settings = DeadZoneSettings()
        let safeEdge = 0.5 + 0.25 * settings.safeZoneFraction
        let triggerStart = safeEdge + 0.25 * settings.gradientBandWidth * 0.5
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: triggerStart, y: 0.5),
            cameraCenter: NormalizedPoint(x: 0.5, y: 0.5),
            zoom: 2.0,
            isTyping: false,
            settings: settings
        )
        XCTAssertGreaterThanOrEqual(result.x, 0.5)
    }

    func test_typingMode_smallerSafeZone() {
        let cursorPos = NormalizedPoint(x: 0.67, y: 0.5)
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        let normalResult = DeadZoneTarget.compute(
            cursorPosition: cursorPos, cameraCenter: center,
            zoom: 2.0, isTyping: false, settings: DeadZoneSettings()
        )
        let typingResult = DeadZoneTarget.compute(
            cursorPosition: cursorPos, cameraCenter: center,
            zoom: 2.0, isTyping: true, settings: DeadZoneSettings()
        )
        XCTAssertEqual(normalResult.x, 0.5, accuracy: 0.01)
        XCTAssertGreaterThan(typingResult.x, 0.5)
    }

    func test_typingMode_higherCorrectionFraction() {
        let cursorPos = NormalizedPoint(x: 0.74, y: 0.5)
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        let normalResult = DeadZoneTarget.compute(
            cursorPosition: cursorPos, cameraCenter: center,
            zoom: 2.0, isTyping: false, settings: DeadZoneSettings()
        )
        let typingResult = DeadZoneTarget.compute(
            cursorPosition: cursorPos, cameraCenter: center,
            zoom: 2.0, isTyping: true, settings: DeadZoneSettings()
        )
        XCTAssertGreaterThan(typingResult.x, normalResult.x)
    }

    func test_zoom1x_targetAlwaysCenter() {
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.8, y: 0.2),
            cameraCenter: NormalizedPoint(x: 0.3, y: 0.7),
            zoom: 1.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        XCTAssertEqual(result.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.y, 0.5, accuracy: 0.001)
    }

    func test_targetClampedToValidBounds() {
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.95, y: 0.95),
            cameraCenter: NormalizedPoint(x: 0.8, y: 0.8),
            zoom: 2.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        XCTAssertLessThanOrEqual(result.x, 0.75)
        XCTAssertLessThanOrEqual(result.y, 0.75)
    }
}
