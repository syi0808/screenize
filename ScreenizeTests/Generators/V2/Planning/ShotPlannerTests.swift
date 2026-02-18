import XCTest
@testable import Screenize

final class ShotPlannerTests: XCTestCase {

    private let defaultSettings = ShotSettings()
    private let screenBounds = CGSize(width: 1920, height: 1080)

    // MARK: - Empty Input

    func test_plan_emptyScenes_returnsEmpty() {
        let plans = ShotPlanner.plan(
            scenes: [], screenBounds: screenBounds, settings: defaultSettings
        )
        XCTAssertTrue(plans.isEmpty)
    }

    // MARK: - Zoom by Intent

    func test_plan_typingCodeScene_zoomInRange() {
        let scene = makeScene(intent: .typing(context: .codeEditor))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        XCTAssertEqual(plans.count, 1)
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.typingCodeZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.typingCodeZoomRange.upperBound)
    }

    func test_plan_typingTextFieldScene_zoomInRange() {
        let scene = makeScene(intent: .typing(context: .textField))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.typingTextFieldZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.typingTextFieldZoomRange.upperBound)
    }

    func test_plan_typingTerminalScene_zoomInRange() {
        let scene = makeScene(intent: .typing(context: .terminal))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.typingTerminalZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.typingTerminalZoomRange.upperBound)
    }

    func test_plan_clickingScene_zoom() {
        let scene = makeScene(intent: .clicking)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.clickingZoom)
    }

    func test_plan_navigatingScene_zoomInRange() {
        let scene = makeScene(intent: .navigating)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.navigatingZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.navigatingZoomRange.upperBound)
    }

    func test_plan_draggingScene_zoomInRange() {
        let scene = makeScene(intent: .dragging(.selection))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.draggingZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.draggingZoomRange.upperBound)
    }

    func test_plan_scrollingScene_zoomInRange() {
        let scene = makeScene(intent: .scrolling)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.scrollingZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.scrollingZoomRange.upperBound)
    }

    func test_plan_idleScene_zoomIsOne() {
        let scene = makeScene(intent: .idle)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.idleZoom)
    }

    func test_plan_switchingScene_zoomIsOne() {
        let scene = makeScene(intent: .switching)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.switchingZoom)
    }

    // MARK: - Center Calculation

    func test_plan_idleCenter_isScreenCenter() {
        let scene = makeScene(intent: .idle)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        XCTAssertEqual(plans[0].idealCenter.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(plans[0].idealCenter.y, 0.5, accuracy: 0.01)
    }

    func test_plan_clickingCenter_followsFocusRegion() {
        let focusPos = NormalizedPoint(x: 0.3, y: 0.7)
        let scene = makeScene(
            intent: .clicking,
            focusRegions: [
                FocusRegion(
                    time: 0, region: CGRect(x: 0.29, y: 0.69, width: 0.02, height: 0.02),
                    confidence: 0.9, source: .cursorPosition
                )
            ]
        )
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        // Center should be near the focus region
        XCTAssertEqual(plans[0].idealCenter.x, 0.3, accuracy: 0.1)
        XCTAssertEqual(plans[0].idealCenter.y, 0.7, accuracy: 0.1)
    }

    func test_plan_centerClampedToViewport() {
        // Focus region near edge should be clamped
        let scene = makeScene(
            intent: .clicking,
            focusRegions: [
                FocusRegion(
                    time: 0, region: CGRect(x: 0.01, y: 0.01, width: 0.02, height: 0.02),
                    confidence: 0.9, source: .cursorPosition
                )
            ]
        )
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        let halfCrop = 0.5 / zoom
        // Center should be clamped so viewport stays in [0, 1]
        XCTAssertGreaterThanOrEqual(plans[0].idealCenter.x, halfCrop - 0.01)
        XCTAssertGreaterThanOrEqual(plans[0].idealCenter.y, halfCrop - 0.01)
    }

    // MARK: - Shot Type

    func test_plan_shotType_closeUpForHighZoom() {
        let scene = makeScene(intent: .typing(context: .textField))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        if zoom > 2.0 {
            if case .closeUp = plans[0].shotType {
                // expected
            } else {
                XCTFail("Expected closeUp for zoom \(zoom)")
            }
        }
    }

    func test_plan_shotType_wideForZoomOne() {
        let scene = makeScene(intent: .idle)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        if case .wide = plans[0].shotType {
            // expected
        } else {
            XCTFail("Expected wide for idle scene")
        }
    }

    func test_plan_shotType_mediumForMidZoom() {
        let scene = makeScene(intent: .navigating)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        if zoom > 1.0 && zoom <= 2.0 {
            if case .medium = plans[0].shotType {
                // expected
            } else {
                XCTFail("Expected medium for zoom \(zoom)")
            }
        }
    }

    // MARK: - Multiple Scenes

    func test_plan_multipleScenesProduceCorrectCount() {
        let scenes = [
            makeScene(start: 0, end: 3, intent: .clicking),
            makeScene(start: 3, end: 6, intent: .typing(context: .codeEditor)),
            makeScene(start: 6, end: 10, intent: .idle)
        ]
        let plans = ShotPlanner.plan(
            scenes: scenes, screenBounds: screenBounds, settings: defaultSettings
        )
        XCTAssertEqual(plans.count, 3)
    }

    // MARK: - Typing with Element-Based Zoom

    func test_plan_typingWithElement_zoomBasedOnElementSize() {
        let elementInfo = UIElementInfo(
            role: "AXTextArea",
            subrole: nil,
            frame: CGRect(x: 200, y: 300, width: 500, height: 400),
            title: nil,
            isClickable: false,
            applicationName: nil
        )
        let focusRegion = FocusRegion(
            time: 0,
            region: elementInfo.frame,
            confidence: 0.9,
            source: .activeElement(elementInfo)
        )
        let scene = makeScene(
            intent: .typing(context: .codeEditor),
            focusRegions: [focusRegion]
        )
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, settings: defaultSettings
        )
        // With an element frame, zoom should be based on element size
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.minZoom)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.maxZoom)
    }

    // MARK: - Helpers

    private func makeScene(
        start: TimeInterval = 0,
        end: TimeInterval = 5,
        intent: UserIntent,
        focusRegions: [FocusRegion] = []
    ) -> CameraScene {
        let defaultFocus: [FocusRegion]
        if focusRegions.isEmpty {
            defaultFocus = [
                FocusRegion(
                    time: start,
                    region: CGRect(x: 0.49, y: 0.49, width: 0.02, height: 0.02),
                    confidence: 0.9,
                    source: .cursorPosition
                )
            ]
        } else {
            defaultFocus = focusRegions
        }
        return CameraScene(
            startTime: start, endTime: end,
            primaryIntent: intent,
            focusRegions: defaultFocus
        )
    }
}
