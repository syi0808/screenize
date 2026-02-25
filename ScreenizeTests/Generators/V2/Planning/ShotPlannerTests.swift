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
        let zoom = plans[0].idealZoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.clickingZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(zoom, defaultSettings.clickingZoomRange.upperBound)
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
        // Events at (0.2, 0.3) and (0.8, 0.7) → center is geometric midpoint (no recency bias)
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
        // Simple average: x=(0.2+0.8)/2=0.5, y=(0.3+0.7)/2=0.5
        let center = plans[0].idealCenter
        XCTAssertEqual(center.x, 0.5, accuracy: 0.03, "Center should be midpoint of events")
        XCTAssertEqual(center.y, 0.5, accuracy: 0.03, "Center should be midpoint of events")
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

    func test_plan_center_typing_usesFirstEventPosition() {
        // Typing: first mouse position from timeline should determine center,
        // so CursorFollowController starts where typing begins and pans forward.
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
        // Typing center should be near first event position
        let center = plans[0].idealCenter
        XCTAssertEqual(center.x, 0.3, accuracy: 0.15)
        XCTAssertEqual(center.y, 0.3, accuracy: 0.15)
    }

    // MARK: - Idle Scene Inheritance

    func test_plan_idleBetweenActions_decaysZoomTowardOne() {
        // Clicking → Idle → Typing → idle decays zoom toward 1.0
        let events = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.3, y: 0.4)),
            makeMouseMoveEvent(time: 1.5, position: NormalizedPoint(x: 0.35, y: 0.45)),
        ]
        let timeline = EventTimeline(events: events, duration: 10.0)
        let scenes = [
            makeScene(start: 0, end: 3, intent: .clicking),
            makeScene(start: 3, end: 5, intent: .idle),
            makeScene(start: 5, end: 10, intent: .typing(context: .codeEditor)),
        ]
        let plans = ShotPlanner.plan(
            scenes: scenes, screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let actionZoom = plans[0].idealZoom
        let idleZoom = plans[1].idealZoom
        // Idle zoom should be between action zoom and 1.0 (decayed)
        XCTAssertLessThan(idleZoom, actionZoom,
                          "Idle zoom should be less than action zoom")
        XCTAssertGreaterThan(idleZoom, 1.0,
                             "Idle zoom should be greater than 1.0")
        // Center should still be inherited from neighbor
        XCTAssertEqual(plans[1].idealCenter.x, plans[0].idealCenter.x, accuracy: 0.01)
        XCTAssertEqual(plans[1].idealCenter.y, plans[0].idealCenter.y, accuracy: 0.01)
    }

    func test_plan_idleAtStart_decaysZoomFromNextNonIdle() {
        // Idle → Clicking → idle at start decays from clicking
        let events = [
            makeMouseMoveEvent(time: 3.5, position: NormalizedPoint(x: 0.6, y: 0.7)),
            makeMouseMoveEvent(time: 4.0, position: NormalizedPoint(x: 0.65, y: 0.72)),
        ]
        let timeline = EventTimeline(events: events, duration: 8.0)
        let scenes = [
            makeScene(start: 0, end: 3, intent: .idle),
            makeScene(start: 3, end: 8, intent: .clicking),
        ]
        let plans = ShotPlanner.plan(
            scenes: scenes, screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let actionZoom = plans[1].idealZoom
        let idleZoom = plans[0].idealZoom
        // Idle zoom decays toward 1.0
        XCTAssertLessThan(idleZoom, actionZoom,
                          "Leading idle zoom should be less than action zoom")
        XCTAssertGreaterThanOrEqual(idleZoom, 1.0,
                                    "Leading idle zoom should be >= 1.0")
        // Center still inherited
        XCTAssertEqual(plans[0].idealCenter.x, plans[1].idealCenter.x, accuracy: 0.01)
    }

    func test_plan_multipleConsecutiveIdles_allDecayed() {
        // Clicking → Idle → Idle → Idle → all idles decayed but same value
        let events = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.4, y: 0.5)),
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.42, y: 0.52)),
        ]
        let timeline = EventTimeline(events: events, duration: 12.0)
        let scenes = [
            makeScene(start: 0, end: 3, intent: .clicking),
            makeScene(start: 3, end: 5, intent: .idle),
            makeScene(start: 5, end: 8, intent: .idle),
            makeScene(start: 8, end: 12, intent: .idle),
        ]
        let plans = ShotPlanner.plan(
            scenes: scenes, screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let actionZoom = plans[0].idealZoom
        for i in 1...3 {
            XCTAssertLessThan(plans[i].idealZoom, actionZoom,
                              "Idle \(i) should have decayed zoom")
            XCTAssertGreaterThanOrEqual(plans[i].idealZoom, 1.0,
                                        "Idle \(i) zoom should be >= 1.0")
        }
    }

    func test_plan_idleZoomDifferentFromActionZoom() {
        // The key test: idle and action scenes MUST have different zoom values
        let events = [
            makeMouseMoveEvent(time: 2.0, position: NormalizedPoint(x: 0.3, y: 0.4)),
            makeMouseMoveEvent(time: 3.0, position: NormalizedPoint(x: 0.35, y: 0.45)),
        ]
        let timeline = EventTimeline(events: events, duration: 10.0)
        let scenes = [
            makeScene(start: 0, end: 2, intent: .idle),
            makeScene(start: 2, end: 5, intent: .navigating),
            makeScene(start: 5, end: 8, intent: .idle),
            makeScene(start: 8, end: 10, intent: .idle),
        ]
        let plans = ShotPlanner.plan(
            scenes: scenes, screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let navZoom = plans[1].idealZoom
        // All idle zooms should differ from navigation zoom
        XCTAssertNotEqual(plans[0].idealZoom, navZoom, accuracy: 0.05,
                          "Idle zoom should differ from action zoom")
        XCTAssertNotEqual(plans[2].idealZoom, navZoom, accuracy: 0.05,
                          "Idle zoom should differ from action zoom")
    }

    func test_plan_allIdleScenes_stayAtZoomOne() {
        // All idle → no non-idle neighbor → stays at 1.0
        let scenes = [
            makeScene(start: 0, end: 3, intent: .idle),
            makeScene(start: 3, end: 6, intent: .idle),
            makeScene(start: 6, end: 10, intent: .idle),
        ]
        let plans = ShotPlanner.plan(
            scenes: scenes, screenBounds: screenBounds,
            eventTimeline: emptyTimeline, settings: defaultSettings
        )
        for plan in plans {
            XCTAssertEqual(plan.idealZoom, defaultSettings.idleZoom, accuracy: 0.01,
                           "All-idle recording should keep zoom at 1.0")
        }
    }

    func test_plan_nonIdleScenesUnchanged() {
        // Non-idle scenes should not be affected by idle inheritance
        let events = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.3, y: 0.3)),
            makeMouseMoveEvent(time: 1.5, position: NormalizedPoint(x: 0.35, y: 0.35)),
            makeMouseMoveEvent(time: 5.5, position: NormalizedPoint(x: 0.7, y: 0.7)),
            makeMouseMoveEvent(time: 6.5, position: NormalizedPoint(x: 0.72, y: 0.72)),
        ]
        let timeline = EventTimeline(events: events, duration: 10.0)
        let scenes = [
            makeScene(start: 0, end: 3, intent: .clicking),
            makeScene(start: 3, end: 5, intent: .idle),
            makeScene(start: 5, end: 10, intent: .navigating),
        ]
        let plansWithIdle = ShotPlanner.plan(
            scenes: scenes, screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        // Clicking and navigating should have their own zoom values
        let clickZoom = plansWithIdle[0].idealZoom
        XCTAssertGreaterThanOrEqual(clickZoom, defaultSettings.clickingZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(clickZoom, defaultSettings.clickingZoomRange.upperBound)
        let navZoom = plansWithIdle[2].idealZoom
        XCTAssertGreaterThanOrEqual(navZoom, defaultSettings.navigatingZoomRange.lowerBound)
        XCTAssertLessThanOrEqual(navZoom, defaultSettings.navigatingZoomRange.upperBound)
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
        // Small spread → zoom should be clamped to upper end of clicking range (2.5)
        // bbox ~0.05+padding*2=0.21 → targetAreaCoverage/0.21 = 3.33 → clamped to 2.5
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.clickingZoomRange.upperBound, accuracy: 0.01)
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

    func test_plan_singleEvent_usesIntentLowerBound() {
        // Single event → use intent range lower bound with singleEvent source
        let events = [
            makeMouseMoveEvent(time: 2.5, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .navigating)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.navigatingZoomRange.lowerBound, accuracy: 0.01)
        XCTAssertEqual(plans[0].zoomSource, .singleEvent)
    }

    func test_plan_singleClick_returnsIntentZoom() {
        let events: [UnifiedEvent] = [
            makeClickEvent(time: 2.5, position: NormalizedPoint(x: 0.6, y: 0.4)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .clicking)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        // Clicking uses clickingZoomRange
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.clickingZoomRange.lowerBound, accuracy: 0.01)
        XCTAssertEqual(plans[0].zoomSource, .singleEvent)
    }

    func test_plan_singleClick_centerOnClickPosition() {
        let events: [UnifiedEvent] = [
            makeClickEvent(time: 2.5, position: NormalizedPoint(x: 0.6, y: 0.4)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .clicking)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let center = plans[0].idealCenter
        XCTAssertEqual(center.x, 0.6, accuracy: 0.05,
                       "Single click center should be at click position")
        XCTAssertEqual(center.y, 0.4, accuracy: 0.05)
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

    // MARK: - Intent-Specific Event Filtering (Center)

    func test_plan_clickingCenter_prefersClickPositions() {
        // Mouse moves at far-away positions, clicks near (0.7, 0.6)
        let events: [UnifiedEvent] = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.1, y: 0.1)),
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.1, y: 0.2)),
            makeMouseMoveEvent(time: 1.5, position: NormalizedPoint(x: 0.15, y: 0.15)),
            makeMouseMoveEvent(time: 2.0, position: NormalizedPoint(x: 0.1, y: 0.1)),
            makeMouseMoveEvent(time: 2.5, position: NormalizedPoint(x: 0.12, y: 0.18)),
            makeClickEvent(time: 3.0, position: NormalizedPoint(x: 0.7, y: 0.6)),
            makeClickEvent(time: 4.0, position: NormalizedPoint(x: 0.72, y: 0.58)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .clicking)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let center = plans[0].idealCenter
        // Center should be near click positions (0.7, 0.6), NOT mouse average (~0.1, ~0.15)
        XCTAssertGreaterThan(center.x, 0.5,
                             "Clicking center X should be near clicks (0.7), not mouse moves (0.1)")
        XCTAssertGreaterThan(center.y, 0.4,
                             "Clicking center Y should be near clicks (0.6), not mouse moves (0.15)")
    }

    func test_plan_navigatingCenter_prefersClickPositions() {
        let events: [UnifiedEvent] = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.1, y: 0.9)),
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.15, y: 0.85)),
            makeClickEvent(time: 2.0, position: NormalizedPoint(x: 0.4, y: 0.5)),
            makeMouseMoveEvent(time: 2.5, position: NormalizedPoint(x: 0.1, y: 0.9)),
            makeClickEvent(time: 3.5, position: NormalizedPoint(x: 0.6, y: 0.5)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .navigating)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let center = plans[0].idealCenter
        // Center should be between clicks (~0.5, ~0.5), not biased by mouse moves at (0.1, 0.9)
        XCTAssertGreaterThan(center.x, 0.3, "Navigating center should be near click cluster")
        XCTAssertLessThan(center.y, 0.7, "Navigating center should not be pulled to mouse at y=0.9")
    }

    func test_plan_draggingCenter_prefersDragPositions() {
        let events: [UnifiedEvent] = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.1, y: 0.1)),
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.15, y: 0.1)),
            makeDragStartEvent(time: 2.0, position: NormalizedPoint(x: 0.6, y: 0.5)),
            makeMouseMoveEvent(time: 2.5, position: NormalizedPoint(x: 0.1, y: 0.1)),
            makeDragEndEvent(time: 3.0, position: NormalizedPoint(x: 0.8, y: 0.7)),
            makeMouseMoveEvent(time: 3.5, position: NormalizedPoint(x: 0.1, y: 0.1)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .dragging(.selection))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let center = plans[0].idealCenter
        // Center should be near drag area (~0.7, ~0.6), not mouse at (0.1, 0.1)
        XCTAssertGreaterThan(center.x, 0.4, "Dragging center should be near drag area")
        XCTAssertGreaterThan(center.y, 0.3, "Dragging center should be near drag area")
    }

    func test_plan_scrollingCenter_usesMousePositions() {
        // Scrolling: mouse position IS where the user is scrolling
        let events: [UnifiedEvent] = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.6, y: 0.5)),
            makeScrollEvent(time: 1.0, position: NormalizedPoint(x: 0.6, y: 0.5)),
            makeMouseMoveEvent(time: 1.5, position: NormalizedPoint(x: 0.62, y: 0.52)),
            makeScrollEvent(time: 2.0, position: NormalizedPoint(x: 0.62, y: 0.52)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .scrolling)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let center = plans[0].idealCenter
        // Mouse positions are relevant for scrolling — center near (0.6, 0.5)
        XCTAssertEqual(center.x, 0.61, accuracy: 0.1)
        XCTAssertEqual(center.y, 0.51, accuracy: 0.1)
    }

    // MARK: - Intent-Specific Event Filtering (Zoom)

    func test_plan_clickingZoom_bboxFromClicks() {
        // Clicks clustered in small area (0.1x0.1), mouse moves spread 0.8x0.8
        let events: [UnifiedEvent] = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.1, y: 0.1)),
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.9, y: 0.9)),
            makeMouseMoveEvent(time: 1.5, position: NormalizedPoint(x: 0.1, y: 0.9)),
            makeMouseMoveEvent(time: 2.0, position: NormalizedPoint(x: 0.9, y: 0.1)),
            makeClickEvent(time: 3.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            makeClickEvent(time: 4.0, position: NormalizedPoint(x: 0.55, y: 0.55)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .clicking)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        // Click bbox is tiny (~0.05 + padding=0.21) → zoom = 0.7/0.21 ≈ 3.3 → clamped to 2.5
        // Mouse bbox is huge (0.8) → zoom would be ~0.875 → irrelevant (only clicks used)
        XCTAssertEqual(plans[0].idealZoom, defaultSettings.clickingZoomRange.upperBound, accuracy: 0.01,
                       "Clicking zoom should use click bbox, clamped to range upper bound")
    }

    func test_plan_navigatingZoom_bboxFromClicks() {
        // Clicks at moderate spread, mouse moves spread everywhere
        let events: [UnifiedEvent] = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.05, y: 0.05)),
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.95, y: 0.95)),
            makeClickEvent(time: 2.0, position: NormalizedPoint(x: 0.4, y: 0.4)),
            makeClickEvent(time: 3.0, position: NormalizedPoint(x: 0.6, y: 0.6)),
            makeMouseMoveEvent(time: 3.5, position: NormalizedPoint(x: 0.05, y: 0.95)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .navigating)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        // Click bbox spread ~0.2 + padding → zoom should be moderate-high
        // Mouse bbox ~0.9 → zoom would be very low
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.navigatingZoomRange.lowerBound,
                                    "Zoom should be in navigating range from click bbox")
    }

    func test_plan_draggingZoom_bboxFromDragArea() {
        // Drag in small area, mouse spreads everywhere
        let events: [UnifiedEvent] = [
            makeMouseMoveEvent(time: 0.5, position: NormalizedPoint(x: 0.05, y: 0.05)),
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.95, y: 0.95)),
            makeDragStartEvent(time: 2.0, position: NormalizedPoint(x: 0.4, y: 0.4)),
            makeDragEndEvent(time: 3.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .dragging(.selection))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let zoom = plans[0].idealZoom
        // Drag bbox ~0.1 + padding → high zoom
        // Mouse bbox ~0.9 → very low zoom
        XCTAssertGreaterThanOrEqual(zoom, defaultSettings.draggingZoomRange.lowerBound,
                                    "Zoom should use drag bbox, not mouse bbox")
    }

    // MARK: - Centroid (No Recency Bias for Activity Center)

    func test_plan_clickingThreePositions_geometricCenter() {
        // Three symmetric clicks → center should be geometric centroid (0.5, 0.5)
        let events: [UnifiedEvent] = [
            makeClickEvent(time: 1.0, position: NormalizedPoint(x: 0.3, y: 0.3)),
            makeClickEvent(time: 2.0, position: NormalizedPoint(x: 0.5, y: 0.7)),
            makeClickEvent(time: 3.0, position: NormalizedPoint(x: 0.7, y: 0.3)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .clicking)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let center = plans[0].idealCenter
        // Simple average: x=(0.3+0.5+0.7)/3=0.5, y=(0.3+0.7+0.3)/3≈0.433
        XCTAssertEqual(center.x, 0.5, accuracy: 0.05,
                       "Clicking center should be geometric centroid, not recency-biased")
        XCTAssertEqual(center.y, 0.433, accuracy: 0.05,
                       "Clicking center should be geometric centroid, not recency-biased")
    }

    func test_plan_navigatingCenter_equalWeight() {
        // Two clicks → center should be midpoint, not biased to second
        let events: [UnifiedEvent] = [
            makeClickEvent(time: 1.0, position: NormalizedPoint(x: 0.3, y: 0.3)),
            makeClickEvent(time: 3.0, position: NormalizedPoint(x: 0.7, y: 0.7)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .navigating)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let center = plans[0].idealCenter
        // Simple average: (0.3+0.7)/2=0.5
        XCTAssertEqual(center.x, 0.5, accuracy: 0.03,
                       "Navigating center should be midpoint, not recency-biased")
        XCTAssertEqual(center.y, 0.5, accuracy: 0.03,
                       "Navigating center should be midpoint, not recency-biased")
    }

    func test_plan_draggingCenter_equalWeight() {
        let events: [UnifiedEvent] = [
            makeDragStartEvent(time: 1.0, position: NormalizedPoint(x: 0.3, y: 0.3)),
            makeDragEndEvent(time: 2.0, position: NormalizedPoint(x: 0.7, y: 0.7)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .dragging(.selection))
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let center = plans[0].idealCenter
        // Simple average: (0.3+0.7)/2=0.5
        XCTAssertEqual(center.x, 0.5, accuracy: 0.03,
                       "Dragging center should be midpoint of drag positions")
        XCTAssertEqual(center.y, 0.5, accuracy: 0.03)
    }

    // MARK: - Fallback Behavior

    func test_plan_clickingCenter_fallsBackWhenNoClicks() {
        // Edge case: clicking scene with only mouse move events
        let events: [UnifiedEvent] = [
            makeMouseMoveEvent(time: 1.0, position: NormalizedPoint(x: 0.3, y: 0.4)),
            makeMouseMoveEvent(time: 3.0, position: NormalizedPoint(x: 0.7, y: 0.6)),
        ]
        let timeline = EventTimeline(events: events, duration: 5.0)
        let scene = makeScene(intent: .clicking)
        let plans = ShotPlanner.plan(
            scenes: [scene], screenBounds: screenBounds,
            eventTimeline: timeline, settings: defaultSettings
        )
        let center = plans[0].idealCenter
        // Should fall back to all events (mouse moves) and compute simple average
        XCTAssertEqual(center.x, 0.5, accuracy: 0.03, "Fallback center should be midpoint")
        XCTAssertEqual(center.y, 0.5, accuracy: 0.03, "Fallback center should be midpoint")
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

    private func makeClickEvent(
        time: TimeInterval,
        position: NormalizedPoint
    ) -> UnifiedEvent {
        let clickData = ClickEventData(
            time: time, position: position, clickType: .leftDown
        )
        return UnifiedEvent(
            time: time,
            kind: .click(clickData),
            position: position,
            metadata: EventMetadata()
        )
    }

    private func makeDragStartEvent(
        time: TimeInterval,
        position: NormalizedPoint
    ) -> UnifiedEvent {
        let dragData = DragEventData(
            startTime: time, endTime: time + 1,
            startPosition: position, endPosition: position,
            dragType: .selection
        )
        return UnifiedEvent(
            time: time,
            kind: .dragStart(dragData),
            position: position,
            metadata: EventMetadata()
        )
    }

    private func makeDragEndEvent(
        time: TimeInterval,
        position: NormalizedPoint
    ) -> UnifiedEvent {
        let dragData = DragEventData(
            startTime: time - 1, endTime: time,
            startPosition: position, endPosition: position,
            dragType: .selection
        )
        return UnifiedEvent(
            time: time,
            kind: .dragEnd(dragData),
            position: position,
            metadata: EventMetadata()
        )
    }

    private func makeScrollEvent(
        time: TimeInterval,
        position: NormalizedPoint
    ) -> UnifiedEvent {
        UnifiedEvent(
            time: time,
            kind: .scroll(direction: .down, magnitude: 10),
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
