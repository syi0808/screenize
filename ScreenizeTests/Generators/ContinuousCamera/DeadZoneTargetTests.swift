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
        // Cursor at 0.68: offset 0.18 exceeds typing hysteresis threshold
        // (~0.1725) but stays within normal threshold (~0.2156).
        let cursorPos = NormalizedPoint(x: 0.68, y: 0.5)
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

    // MARK: - Hysteresis Tests

    func test_hysteresis_enteringRequiresLargerOffset() {
        // At zoom 2.0: viewportHalf=0.25, safeHalf=0.1875
        // hysteresisHalf = 0.1875 * 0.15 = 0.028125
        // Enter threshold = 0.1875 + 0.028125 = 0.215625
        // Cursor at offset 0.20 — outside safe zone but within
        // hysteresis band. wasActive=false → should NOT activate.
        let settings = DeadZoneSettings()
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        let cursor = NormalizedPoint(x: 0.70, y: 0.5) // offset 0.20
        let result = DeadZoneTarget.computeWithState(
            cursorPosition: cursor,
            cameraCenter: center,
            zoom: 2.0,
            isTyping: false,
            wasActive: false,
            settings: settings
        )
        XCTAssertFalse(result.isActive)
        XCTAssertEqual(result.target.x, 0.5, accuracy: 0.001)
    }

    func test_hysteresis_leavingUsesInnerThreshold() {
        // Leave threshold = safeHalf - hysteresisHalf
        //                 = 0.1875 - 0.028125 = 0.159375
        // Cursor at offset 0.17 — inside safe zone by the original
        // threshold but above the inner hysteresis threshold.
        // wasActive=true → should STAY active.
        let settings = DeadZoneSettings()
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        let cursor = NormalizedPoint(x: 0.67, y: 0.5) // offset 0.17
        let result = DeadZoneTarget.computeWithState(
            cursorPosition: cursor,
            cameraCenter: center,
            zoom: 2.0,
            isTyping: false,
            wasActive: true,
            settings: settings
        )
        XCTAssertTrue(result.isActive)
    }

    func test_hysteresis_fullyOutside_activatesRegardlessOfState() {
        // Cursor well outside safe zone (offset 0.24 > 0.2156)
        let settings = DeadZoneSettings()
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        let cursor = NormalizedPoint(x: 0.74, y: 0.5)
        let fromInactive = DeadZoneTarget.computeWithState(
            cursorPosition: cursor,
            cameraCenter: center,
            zoom: 2.0,
            isTyping: false,
            wasActive: false,
            settings: settings
        )
        let fromActive = DeadZoneTarget.computeWithState(
            cursorPosition: cursor,
            cameraCenter: center,
            zoom: 2.0,
            isTyping: false,
            wasActive: true,
            settings: settings
        )
        XCTAssertTrue(fromInactive.isActive)
        XCTAssertTrue(fromActive.isActive)
    }

    func test_hysteresis_fullyInside_deactivatesRegardlessOfState() {
        // Cursor well inside safe zone (offset 0.05 < 0.159375)
        let settings = DeadZoneSettings()
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        let cursor = NormalizedPoint(x: 0.55, y: 0.5)
        let fromInactive = DeadZoneTarget.computeWithState(
            cursorPosition: cursor,
            cameraCenter: center,
            zoom: 2.0,
            isTyping: false,
            wasActive: false,
            settings: settings
        )
        let fromActive = DeadZoneTarget.computeWithState(
            cursorPosition: cursor,
            cameraCenter: center,
            zoom: 2.0,
            isTyping: false,
            wasActive: true,
            settings: settings
        )
        XCTAssertFalse(fromInactive.isActive)
        XCTAssertFalse(fromActive.isActive)
    }

    func test_widerGradient_smootherTransition() {
        // Sample multiple points across the gradient band and verify
        // monotonic, increasing target offsets.
        let settings = DeadZoneSettings()
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        let zoom: CGFloat = 2.0
        let viewportHalf = 0.5 / zoom // 0.25
        let safeHalf = viewportHalf * settings.safeZoneFraction // 0.1875
        let hysteresisHalf = safeHalf * settings.hysteresisMargin
        let gradientEnd = safeHalf + viewportHalf * settings.gradientBandWidth

        // Start just past the enter threshold so wasActive=false activates
        let enterThreshold = safeHalf + hysteresisHalf
        let step = (gradientEnd - enterThreshold) / 5.0
        var previousX: CGFloat = 0.5
        for i in 1...5 {
            let offset = enterThreshold + step * CGFloat(i)
            let cursor = NormalizedPoint(x: 0.5 + offset, y: 0.5)
            let result = DeadZoneTarget.computeWithState(
                cursorPosition: cursor,
                cameraCenter: center,
                zoom: zoom,
                isTyping: false,
                wasActive: true,
                settings: settings
            )
            XCTAssertGreaterThanOrEqual(
                result.target.x, previousX,
                "Target should increase monotonically at offset \(offset)"
            )
            previousX = result.target.x
        }
    }
}
