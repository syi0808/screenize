import XCTest
@testable import Screenize

final class ShotPlannerTests: XCTestCase {

    private let defaultSettings = ShotSettings()
    private let screenBounds = CGSize(width: 1920, height: 1080)
    private let emptyTimeline = EventTimeline(events: [], duration: 10.0)

    // MARK: - Empty Input

    func test_plan_emptyScenes_returnsEmpty() {
        let plans = ShotPlanner.plan(
            scenes: [], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        XCTAssertTrue(plans.isEmpty)
    }

    // MARK: - Zoom by Intent

    func test_plan_typingCodeScene_zoomInRange() {
        let scene = makeScene(intent: .typing(context: .codeEditor))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        XCTAssertEqual(plans.count, 1)
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.typingCodeZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.typingCodeZoomRange.upperBound)
    }

    func test_plan_typingTextFieldScene_zoomInRange() {
        let scene = makeScene(intent: .typing(context: .textField))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.typingTextFieldZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.typingTextFieldZoomRange.upperBound)
    }

    func test_plan_typingTerminalScene_zoomInRange() {
        let scene = makeScene(intent: .typing(context: .terminal))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.typingTerminalZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.typingTerminalZoomRange.upperBound)
    }

    func test_plan_clickingScene_zoom() {
        let scene = makeScene(intent: .clicking)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.clickingZoom)
    }

    func test_plan_navigatingScene_zoomInRange() {
        let scene = makeScene(intent: .navigating)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.navigatingZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.navigatingZoomRange.upperBound)
    }

    func test_plan_draggingScene_zoomInRange() {
        let scene = makeScene(intent: .dragging(.selection))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.draggingZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.draggingZoomRange.upperBound)
    }

    func test_plan_scrollingScene_zoomInRange() {
        let scene = makeScene(intent: .scrolling)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.scrollingZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.scrollingZoomRange.upperBound)
    }

    func test_plan_idleScene_zoomIsOne() {
        let scene = makeScene(intent: .idle)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.idleZoom)
    }

    func test_plan_switchingScene_zoomIsOne() {
        let scene = makeScene(intent: .switching)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.switchingZoom)
    }

    // MARK: - Center Calculation

    func test_plan_idleCenter_isScreenCenter() {
        let scene = makeScene(intent: .idle)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
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
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
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
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
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
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
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
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
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
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
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
            scenes: scenes, screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
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
            scenes: [scene], screenBounds: screenBounds, eventTimeline: emptyTimeline, settings: defaultSettings
        )
        // With an element frame, zoom should be based on element size
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.minZoom)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.maxZoom)
    }

    // MARK: - Event-Based Center

    func test_plan_center_usesEventPositions() {
        // Events at (0.2, 0.3) and (0.8, 0.7) → center biased toward latter (recency)
        let events = [
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.2, y: 0.3)),
            makeMouseMoveEvent(time: 3.0, position: NormalizedPoint(x: 0.8, y: 0.7)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .clicking)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        // With recency bias (weight 1.0, 1.5), center should be closer to (0.8, 0.7)
        let center = plans[0].idealCenter
        XCTAssertGreaterThan(center.x, 0.5, "Center X should be biased toward later event at 0.8")
        XCTAssertGreaterThan(center.y, 0.5, "Center Y should be biased toward later event at 0.7")
    }

    func test_plan_center_noEvents_fallsToFocusRegion() {
        // Empty timeline → uses FocusRegion-based center (existing behavior)
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
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: emptyTimeline, settings: defaultSettings
        )
        XCTAssertEqual(plans[0].idealCenter.x, 0.3, accuracy: 0.1)
        XCTAssertEqual(plans[0].idealCenter.y, 0.7, accuracy: 0.1)
    }

    func test_plan_center_typing_usesLastEventPosition() {
        // Typing: last mouse position from timeline should determine center
        let events = [
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.3, y: 0.3)),
            makeMouseMoveEvent(time: 4.0, position: NormalizedPoint(x: 0.7, y: 0.6)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .typing(context: .codeEditor))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        // Typing center should be near last event position
        let center = plans[0].idealCenter
        XCTAssertEqual(center.x, 0.7, accuracy: 0.15)
        XCTAssertEqual(center.y, 0.6, accuracy: 0.15)
    }

    // MARK: - Activity Bounding Box Zoom

    func test_plan_activityBBox_smallSpread_highZoom() {
        // Events clustered in a small 0.1x0.1 area → high zoom
        let events = [
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            makeMouseMoveEvent(time: 2.0, position: NormalizedPoint(x: 0.55, y: 0.55)),
            makeMouseMoveEvent(time: 3.0, position: NormalizedPoint(x: 0.52, y: 0.48)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .clicking)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        // Small spread → zoom should be near upper end of clicking range (2.0)
        // bbox ~0.05+padding*2=0.21 → targetAreaCoverage/0.21 = 3.33 → clamped to 2.0
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.clickingZoom, accuracy: 0.01)
    }

    func test_plan_activityBBox_largeSpread_lowZoom() {
        // Events spread across 0.5x0.5 area → lower zoom
        let events = [
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.2, y: 0.2)),
            makeMouseMoveEvent(time: 2.0, position: NormalizedPoint(x: 0.7, y: 0.7)),
            makeMouseMoveEvent(time: 3.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .navigating)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        // bbox ~0.5+padding*2=0.66 → targetAreaCoverage/0.66 = 1.06 → clamped to navigating lower (1.5)
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.navigatingZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.navigatingZoomRange.upperBound)
    }

    func test_plan_elementBasedTakesPriority() {
        // Element data AND events both present → element wins
        let elementInfo = UIElementInfo(
            role: "AXTextArea", subrole: nil,
            frame: CGRect(x: 200, y: 300, width: 500, height: 400),
            title: nil, isClickable: false, applicationName: nil
        )
        let focusRegion = FocusRegion(
            time: 0, region: elementInfo.frame,
            confidence: 0.9, source: .activeElement(elementInfo)
        )
        let events = [
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.1, y: 0.1)),
            makeMouseMoveEvent(time: 2.0, position: NormalizedPoint(x: 0.9, y: 0.9)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(
            intent: .typing(context: .codeEditor),
            focusRegions: [focusRegion]
        )

        let plansWithEvents = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let plansWithoutEvents = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: emptyTimeline, settings: defaultSettings
        )
        // Element-based zoom should produce same result regardless of events
        XCTAssertEqual(plansWithEvents[0].idealZoom, plansWithoutEvents[0].idealZoom, accuracy: 0.01)
    }

    func test_plan_noEventsInRange_fallsToMidpoint() {
        // Empty timeline → midpoint fallback (same as before)
        let scene = makeScene(intent: .navigating)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: emptyTimeline, settings: defaultSettings
        )
        let expectedMidpoint = (defaultSettings.navigatingZoomRange.lowerBound
            + defaultSettings.navigatingZoomRange.upperBound) / 2
        XCTAssertEqual(plans[0].idealZoom, expectedMidpoint, accuracy: 0.01)
    }

    func test_plan_singleEvent_fallsToMidpoint() {
        // Single event = zero-area bbox → falls to midpoint
        let events = [
            makeMouseMoveEvent(time: 2.5, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .navigating)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let expectedMidpoint = (defaultSettings.navigatingZoomRange.lowerBound
            + defaultSettings.navigatingZoomRange.upperBound) / 2
        XCTAssertEqual(plans[0].idealZoom, expectedMidpoint, accuracy: 0.01)
    }

    func test_plan_bboxZoomClampedToIntentRange() {
        // Very small spread → computed zoom would exceed intent range upper bound
        // Should be clamped to intent range
        let events = [
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            makeMouseMoveEvent(time: 2.0, position: NormalizedPoint(x: 0.51, y: 0.51)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .scrolling) // scrolling range: 1.3...1.5
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        // bbox is tiny → computed zoom would be huge → clamped to scrolling upper (1.5)
        XCTAssertLessThanOrEqual(plans[0].idealZoom, defaultSettings.scrollingZoomRange.upperBound)
    }

    // MARK: - Helpers

    private func makeMouseMoveEvent(
        time: TimeInterval,
        position: NormalizedPoint
    ) -> UnifiedEvent {
        UnifiedEvent(
            time: time,
            kind: .mouseMove,
            position: position,
            metadata: EventMetadata()
        )
    }

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
