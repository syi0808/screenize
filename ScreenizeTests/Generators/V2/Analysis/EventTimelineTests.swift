import XCTest
@testable import Screenize

final class EventTimelineTests: XCTestCase {

    // MARK: - Build: Empty Input

    func test_build_emptyMouseData_returnsEmptyTimeline() {
        let mouseData = MockMouseDataSource(duration: 5.0)
        let timeline = EventTimeline.build(from: mouseData)

        XCTAssertTrue(timeline.events.isEmpty)
        XCTAssertEqual(timeline.duration, 5.0)
    }

    // MARK: - Build: Clicks

    func test_build_clicksOnly_containsClickEvents() {
        let clicks = [
            ClickEventData(
                time: 1.0,
                position: NormalizedPoint(x: 0.3, y: 0.4),
                clickType: .leftDown,
                appBundleID: "com.test.app",
                elementInfo: nil
            ),
            ClickEventData(
                time: 2.5,
                position: NormalizedPoint(x: 0.6, y: 0.7),
                clickType: .leftDown,
                appBundleID: "com.test.app",
                elementInfo: nil
            ),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let timeline = EventTimeline.build(from: mouseData)

        let clickEvents = timeline.events.filter {
            if case .click = $0.kind { return true }
            return false
        }
        XCTAssertEqual(clickEvents.count, 2)
        XCTAssertEqual(clickEvents[0].time, 1.0)
        XCTAssertEqual(clickEvents[1].time, 2.5)
    }

    func test_build_allClickTypesIncluded() {
        let clicks = [
            ClickEventData(
                time: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown, appBundleID: nil, elementInfo: nil
            ),
            ClickEventData(
                time: 1.1, position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftUp, appBundleID: nil, elementInfo: nil
            ),
            ClickEventData(
                time: 2.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .rightDown, appBundleID: nil, elementInfo: nil
            ),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let timeline = EventTimeline.build(from: mouseData)

        let clickEvents = timeline.events.filter {
            if case .click = $0.kind { return true }
            return false
        }
        // All click types should be included (unlike ActivityCollector which filters leftDown only)
        XCTAssertEqual(clickEvents.count, 3)
    }

    func test_build_clickMetadata_containsAppBundleIDAndElementInfo() {
        let element = UIElementInfo(
            role: "AXButton", subrole: nil,
            frame: CGRect(x: 100, y: 200, width: 80, height: 30),
            title: "OK", isClickable: true, applicationName: "TestApp"
        )
        let clicks = [
            ClickEventData(
                time: 1.0,
                position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown,
                appBundleID: "com.test.app",
                elementInfo: element
            ),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let timeline = EventTimeline.build(from: mouseData)

        guard let event = timeline.events.first else {
            XCTFail("Expected at least one event")
            return
        }
        XCTAssertEqual(event.metadata.appBundleID, "com.test.app")
        XCTAssertEqual(event.metadata.elementInfo?.role, "AXButton")
    }

    // MARK: - Build: Keyboard Events

    func test_build_keyboardEvents_containsKeyDownAndKeyUp() {
        let kbdEvents = [
            KeyboardEventData(
                time: 1.0, keyCode: 0, eventType: .keyDown,
                modifiers: KeyboardEventData.ModifierFlags(rawValue: 0), character: "a"
            ),
            KeyboardEventData(
                time: 1.05, keyCode: 0, eventType: .keyUp,
                modifiers: KeyboardEventData.ModifierFlags(rawValue: 0), character: "a"
            ),
        ]
        let mouseData = MockMouseDataSource(keyboardEvents: kbdEvents)
        let timeline = EventTimeline.build(from: mouseData)

        let keyDowns = timeline.events.filter {
            if case .keyDown = $0.kind { return true }
            return false
        }
        let keyUps = timeline.events.filter {
            if case .keyUp = $0.kind { return true }
            return false
        }
        XCTAssertEqual(keyDowns.count, 1)
        XCTAssertEqual(keyUps.count, 1)
    }

    // MARK: - Build: Drag Events

    func test_build_dragEvents_containsDragStartAndEnd() {
        let drags = [
            DragEventData(
                startTime: 1.0, endTime: 2.0,
                startPosition: NormalizedPoint(x: 0.2, y: 0.3),
                endPosition: NormalizedPoint(x: 0.8, y: 0.7),
                dragType: .selection
            ),
        ]
        let mouseData = MockMouseDataSource(dragEvents: drags)
        let timeline = EventTimeline.build(from: mouseData)

        let dragStarts = timeline.events.filter {
            if case .dragStart = $0.kind { return true }
            return false
        }
        let dragEnds = timeline.events.filter {
            if case .dragEnd = $0.kind { return true }
            return false
        }
        XCTAssertEqual(dragStarts.count, 1)
        XCTAssertEqual(dragEnds.count, 1)
        XCTAssertEqual(dragStarts[0].time, 1.0)
        XCTAssertEqual(dragEnds[0].time, 2.0)
    }

    // MARK: - Build: Mouse Positions (Downsampling)

    func test_build_mouseMovesDownsampled_reducesEventCount() {
        // 60 positions over 1 second (60fps) → should downsample to ~10 events
        var positions: [MousePositionData] = []
        for i in 0..<60 {
            let time = Double(i) / 60.0
            positions.append(MousePositionData(
                time: time,
                position: NormalizedPoint(x: 0.5, y: 0.5),
                appBundleID: nil, elementInfo: nil
            ))
        }
        let mouseData = MockMouseDataSource(duration: 1.0, positions: positions)
        let timeline = EventTimeline.build(from: mouseData)

        let moveEvents = timeline.events.filter {
            if case .mouseMove = $0.kind { return true }
            return false
        }
        // At ~10Hz, expect ~10 events from 60 samples
        XCTAssertGreaterThanOrEqual(moveEvents.count, 8)
        XCTAssertLessThanOrEqual(moveEvents.count, 12)
    }

    // MARK: - Build: UIStateSamples

    func test_build_uiStateSamples_includesUIStateChangeEvents() {
        let samples = [
            UIStateSample(
                timestamp: 1.0,
                cursorPosition: CGPoint(x: 100, y: 200)
            ),
            UIStateSample(
                timestamp: 2.0,
                cursorPosition: CGPoint(x: 300, y: 400)
            ),
        ]
        let mouseData = MockMouseDataSource()
        let timeline = EventTimeline.build(from: mouseData, uiStateSamples: samples)

        let uiStateEvents = timeline.events.filter {
            if case .uiStateChange = $0.kind { return true }
            return false
        }
        XCTAssertEqual(uiStateEvents.count, 2)
    }

    // MARK: - Build: Mixed Events Sorted

    func test_build_mixedEvents_sortedByTime() {
        let clicks = [
            ClickEventData(
                time: 2.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown, appBundleID: nil, elementInfo: nil
            ),
        ]
        let kbdEvents = [
            KeyboardEventData(
                time: 1.0, keyCode: 0, eventType: .keyDown,
                modifiers: KeyboardEventData.ModifierFlags(rawValue: 0), character: "a"
            ),
        ]
        let drags = [
            DragEventData(
                startTime: 3.0, endTime: 4.0,
                startPosition: NormalizedPoint(x: 0.2, y: 0.3),
                endPosition: NormalizedPoint(x: 0.8, y: 0.7),
                dragType: .selection
            ),
        ]
        let mouseData = MockMouseDataSource(
            clicks: clicks, keyboardEvents: kbdEvents, dragEvents: drags
        )
        let timeline = EventTimeline.build(from: mouseData)

        // Events should be sorted by time: keyDown(1.0), click(2.0), dragStart(3.0), dragEnd(4.0)
        let times = timeline.events.map(\.time)
        XCTAssertEqual(times, times.sorted())
        XCTAssertGreaterThanOrEqual(timeline.events.count, 4)
    }

    // MARK: - Build: Edge Cases

    func test_build_singleEvent_works() {
        let clicks = [
            ClickEventData(
                time: 5.0, position: NormalizedPoint(x: 0.1, y: 0.9),
                clickType: .leftDown, appBundleID: nil, elementInfo: nil
            ),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let timeline = EventTimeline.build(from: mouseData)

        XCTAssertEqual(timeline.events.count, 1)
    }

    func test_build_duplicateTimestamps_preservesAll() {
        let clicks = [
            ClickEventData(
                time: 1.0, position: NormalizedPoint(x: 0.3, y: 0.3),
                clickType: .leftDown, appBundleID: nil, elementInfo: nil
            ),
            ClickEventData(
                time: 1.0, position: NormalizedPoint(x: 0.7, y: 0.7),
                clickType: .rightDown, appBundleID: nil, elementInfo: nil
            ),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let timeline = EventTimeline.build(from: mouseData)

        XCTAssertEqual(timeline.events.count, 2)
    }

    // MARK: - Query: events(in:)

    func test_eventsInRange_returnsEventsInBounds() {
        let clicks = [
            ClickEventData(
                time: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown, appBundleID: nil, elementInfo: nil
            ),
            ClickEventData(
                time: 3.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown, appBundleID: nil, elementInfo: nil
            ),
            ClickEventData(
                time: 5.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown, appBundleID: nil, elementInfo: nil
            ),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let timeline = EventTimeline.build(from: mouseData)

        let rangeEvents = timeline.events(in: 2.0...4.0)
        XCTAssertEqual(rangeEvents.count, 1)
        XCTAssertEqual(rangeEvents[0].time, 3.0)
    }

    func test_eventsInRange_emptyRange_returnsEmpty() {
        let clicks = [
            ClickEventData(
                time: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown, appBundleID: nil, elementInfo: nil
            ),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let timeline = EventTimeline.build(from: mouseData)

        let rangeEvents = timeline.events(in: 5.0...8.0)
        XCTAssertTrue(rangeEvents.isEmpty)
    }

    func test_eventsInRange_boundaryInclusive() {
        let clicks = [
            ClickEventData(
                time: 2.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown, appBundleID: nil, elementInfo: nil
            ),
            ClickEventData(
                time: 4.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                clickType: .leftDown, appBundleID: nil, elementInfo: nil
            ),
        ]
        let mouseData = MockMouseDataSource(clicks: clicks)
        let timeline = EventTimeline.build(from: mouseData)

        // Both boundary events should be included
        let rangeEvents = timeline.events(in: 2.0...4.0)
        XCTAssertEqual(rangeEvents.count, 2)
    }

    // MARK: - Query: lastMousePosition

    func test_lastMousePosition_returnsCorrectPosition() {
        let positions = [
            MousePositionData(
                time: 0.0, position: NormalizedPoint(x: 0.1, y: 0.1),
                appBundleID: nil, elementInfo: nil
            ),
            MousePositionData(
                time: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                appBundleID: nil, elementInfo: nil
            ),
            MousePositionData(
                time: 2.0, position: NormalizedPoint(x: 0.9, y: 0.9),
                appBundleID: nil, elementInfo: nil
            ),
        ]
        let mouseData = MockMouseDataSource(positions: positions)
        let timeline = EventTimeline.build(from: mouseData)

        let pos = timeline.lastMousePosition(before: 1.5)
        XCTAssertNotNil(pos)
        XCTAssertEqual(pos?.x, 0.5)
        XCTAssertEqual(pos?.y, 0.5)
    }

    func test_lastMousePosition_noPositionBeforeTime_returnsNil() {
        let positions = [
            MousePositionData(
                time: 5.0, position: NormalizedPoint(x: 0.5, y: 0.5),
                appBundleID: nil, elementInfo: nil
            ),
        ]
        let mouseData = MockMouseDataSource(positions: positions)
        let timeline = EventTimeline.build(from: mouseData)

        let pos = timeline.lastMousePosition(before: 1.0)
        XCTAssertNil(pos)
    }
}
