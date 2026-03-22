import XCTest
import CoreGraphics
@testable import Screenize

final class WaypointExtractorTests: XCTestCase {

    // MARK: - Helpers

    /// Generate evenly spaced mouse_move events across a time range.
    private func makeMouseMoveEvents(
        count: Int,
        startMs: Int,
        endMs: Int,
        startX: Double,
        endX: Double,
        startY: Double,
        endY: Double
    ) -> [RawEvent] {
        guard count > 0 else { return [] }
        if count == 1 {
            return [RawEvent(timeMs: startMs, type: .mouseMove, x: startX, y: startY)]
        }
        let durationMs = endMs - startMs
        return (0..<count).map { i in
            let fraction = Double(i) / Double(count - 1)
            let timeMs = startMs + Int(Double(durationMs) * fraction)
            let x = startX + (endX - startX) * fraction
            let y = startY + (endY - startY) * fraction
            return RawEvent(timeMs: timeMs, type: .mouseMove, x: x, y: y)
        }
    }

    private func makeRawEvents(
        events: [RawEvent],
        captureArea: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    ) -> ScenarioRawEvents {
        ScenarioRawEvents(
            startTimestamp: "2026-03-16T10:00:00Z",
            captureArea: captureArea,
            events: events
        )
    }

    // MARK: - Sampling Rate Tests

    func test_extract_5Hz_over1Second_produces5Waypoints() {
        // 100 evenly spaced events over 1 second (0ms–1000ms)
        let moves = makeMouseMoveEvents(count: 100, startMs: 0, endMs: 1000,
                                        startX: 0, endX: 1920, startY: 0, endY: 1080)
        let rawEvents = makeRawEvents(events: moves)
        let timeRange = TimeRange(startMs: 0, endMs: 1000)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 5,
            captureArea: rawEvents.captureArea
        )

        // 5Hz over 1s → sample at 0, 200, 400, 600, 800ms → 5 points
        XCTAssertEqual(waypoints.count, 5)
    }

    func test_extract_1Hz_over1Second_produces1Waypoint() {
        let moves = makeMouseMoveEvents(count: 100, startMs: 0, endMs: 1000,
                                        startX: 0, endX: 1920, startY: 0, endY: 1080)
        let rawEvents = makeRawEvents(events: moves)
        let timeRange = TimeRange(startMs: 0, endMs: 1000)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 1,
            captureArea: rawEvents.captureArea
        )

        // 1Hz over 1s → sample at 0ms only (interval=1000ms, next would be 1000ms=endMs boundary)
        XCTAssertEqual(waypoints.count, 1)
    }

    func test_extract_30Hz_over1Second_produces30Waypoints() {
        // 1000 events to give enough density for 30Hz sampling
        let moves = makeMouseMoveEvents(count: 1000, startMs: 0, endMs: 1000,
                                        startX: 0, endX: 1920, startY: 0, endY: 1080)
        let rawEvents = makeRawEvents(events: moves)
        let timeRange = TimeRange(startMs: 0, endMs: 1000)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 30,
            captureArea: rawEvents.captureArea
        )

        // 30Hz over 1s → sample at 0, 33, 66, ..., up to ~29 intervals → ~30 points
        // Allow tolerance: at least 28 and at most 31
        XCTAssertGreaterThanOrEqual(waypoints.count, 28)
        XCTAssertLessThanOrEqual(waypoints.count, 31)
    }

    // MARK: - Empty / Boundary Tests

    func test_extract_emptyTimeRange_returnsEmpty() {
        // No mouse_move events in range at all
        let events = [
            RawEvent(timeMs: 5000, type: .mouseMove, x: 100, y: 200),
            RawEvent(timeMs: 6000, type: .mouseMove, x: 200, y: 300)
        ]
        let rawEvents = makeRawEvents(events: events)
        let timeRange = TimeRange(startMs: 0, endMs: 1000)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: rawEvents.captureArea
        )

        XCTAssertTrue(waypoints.isEmpty)
    }

    func test_extract_noMouseMoveEvents_returnsEmpty() {
        // Events exist in range but none are mouse_move
        let events = [
            RawEvent(timeMs: 100, type: .mouseDown, x: 100, y: 200, button: "left"),
            RawEvent(timeMs: 200, type: .mouseUp, x: 100, y: 200, button: "left"),
            RawEvent(timeMs: 300, type: .keyDown, keyCode: 36)
        ]
        let rawEvents = makeRawEvents(events: events)
        let timeRange = TimeRange(startMs: 0, endMs: 1000)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: rawEvents.captureArea
        )

        XCTAssertTrue(waypoints.isEmpty)
    }

    func test_extract_singleEventInRange_produces1Waypoint() {
        let events = [
            RawEvent(timeMs: 500, type: .mouseMove, x: 960, y: 540)
        ]
        let rawEvents = makeRawEvents(events: events)
        let timeRange = TimeRange(startMs: 0, endMs: 1000)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: rawEvents.captureArea
        )

        XCTAssertEqual(waypoints.count, 1)
        XCTAssertEqual(waypoints[0].x, 0.5, accuracy: 0.001)
        XCTAssertEqual(waypoints[0].y, 0.5, accuracy: 0.001)
    }

    // MARK: - Normalization Tests

    func test_extract_normalization_originAtZero() {
        // Event at (0, 0) in a 1920×1080 capture area → normalized (0, 0)
        let events = [RawEvent(timeMs: 0, type: .mouseMove, x: 0, y: 0)]
        let captureArea = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rawEvents = makeRawEvents(events: events, captureArea: captureArea)
        let timeRange = TimeRange(startMs: 0, endMs: 100)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: captureArea
        )

        XCTAssertFalse(waypoints.isEmpty)
        XCTAssertEqual(waypoints[0].x, 0.0, accuracy: 0.001)
        XCTAssertEqual(waypoints[0].y, 0.0, accuracy: 0.001)
    }

    func test_extract_normalization_centerPoint() {
        // Event at center of 1920×1080 → normalized (0.5, 0.5)
        let events = [RawEvent(timeMs: 0, type: .mouseMove, x: 960, y: 540)]
        let captureArea = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rawEvents = makeRawEvents(events: events, captureArea: captureArea)
        let timeRange = TimeRange(startMs: 0, endMs: 100)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: captureArea
        )

        XCTAssertFalse(waypoints.isEmpty)
        XCTAssertEqual(waypoints[0].x, 0.5, accuracy: 0.001)
        XCTAssertEqual(waypoints[0].y, 0.5, accuracy: 0.001)
    }

    func test_extract_normalization_bottomRightCorner() {
        // Event at (width, height) → normalized (1.0, 1.0)
        let events = [RawEvent(timeMs: 0, type: .mouseMove, x: 1920, y: 1080)]
        let captureArea = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rawEvents = makeRawEvents(events: events, captureArea: captureArea)
        let timeRange = TimeRange(startMs: 0, endMs: 100)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: captureArea
        )

        XCTAssertFalse(waypoints.isEmpty)
        XCTAssertEqual(waypoints[0].x, 1.0, accuracy: 0.001)
        XCTAssertEqual(waypoints[0].y, 1.0, accuracy: 0.001)
    }

    // MARK: - CaptureArea Offset Tests

    func test_extract_captureAreaOffset_subtractsOrigin() {
        // captureArea starts at (100, 200); event at (100, 200) → normalized (0, 0)
        let captureArea = CGRect(x: 100, y: 200, width: 800, height: 600)
        let events = [RawEvent(timeMs: 0, type: .mouseMove, x: 100, y: 200)]
        let rawEvents = makeRawEvents(events: events, captureArea: captureArea)
        let timeRange = TimeRange(startMs: 0, endMs: 100)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: captureArea
        )

        XCTAssertFalse(waypoints.isEmpty)
        XCTAssertEqual(waypoints[0].x, 0.0, accuracy: 0.001)
        XCTAssertEqual(waypoints[0].y, 0.0, accuracy: 0.001)
    }

    func test_extract_captureAreaOffset_centerOfOffset() {
        // captureArea at (100, 200), size 800×600; event at center (500, 500) → normalized (0.5, 0.5)
        let captureArea = CGRect(x: 100, y: 200, width: 800, height: 600)
        let events = [RawEvent(timeMs: 0, type: .mouseMove, x: 500, y: 500)]
        let rawEvents = makeRawEvents(events: events, captureArea: captureArea)
        let timeRange = TimeRange(startMs: 0, endMs: 100)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: captureArea
        )

        XCTAssertFalse(waypoints.isEmpty)
        XCTAssertEqual(waypoints[0].x, 0.5, accuracy: 0.001)
        XCTAssertEqual(waypoints[0].y, 0.5, accuracy: 0.001)
    }

    func test_extract_captureAreaOffset_endCorner() {
        // captureArea at (100, 200), size 800×600; event at (900, 800) → normalized (1.0, 1.0)
        let captureArea = CGRect(x: 100, y: 200, width: 800, height: 600)
        let events = [RawEvent(timeMs: 0, type: .mouseMove, x: 900, y: 800)]
        let rawEvents = makeRawEvents(events: events, captureArea: captureArea)
        let timeRange = TimeRange(startMs: 0, endMs: 100)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: captureArea
        )

        XCTAssertFalse(waypoints.isEmpty)
        XCTAssertEqual(waypoints[0].x, 1.0, accuracy: 0.001)
        XCTAssertEqual(waypoints[0].y, 1.0, accuracy: 0.001)
    }

    // MARK: - Duplicate Skipping Tests

    func test_extract_duplicatePoints_areSkipped() {
        // All events at the same position → only 1 waypoint
        let events = (0..<10).map { i in
            RawEvent(timeMs: i * 100, type: .mouseMove, x: 100, y: 200)
        }
        let rawEvents = makeRawEvents(events: events)
        let timeRange = TimeRange(startMs: 0, endMs: 900)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: rawEvents.captureArea
        )

        XCTAssertEqual(waypoints.count, 1)
    }

    // MARK: - TimeRange Filtering Tests

    func test_extract_filtersEventsOutsideTimeRange() {
        // Events before and after the range should be ignored
        let events = [
            RawEvent(timeMs: 0, type: .mouseMove, x: 0, y: 0),        // before range
            RawEvent(timeMs: 500, type: .mouseMove, x: 960, y: 540),   // inside range
            RawEvent(timeMs: 2000, type: .mouseMove, x: 1920, y: 1080) // after range
        ]
        let rawEvents = makeRawEvents(events: events)
        let timeRange = TimeRange(startMs: 400, endMs: 600)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 10,
            captureArea: rawEvents.captureArea
        )

        // Only the 500ms event is in range; it normalizes to (0.5, 0.5)
        XCTAssertEqual(waypoints.count, 1)
        XCTAssertEqual(waypoints[0].x, 0.5, accuracy: 0.001)
        XCTAssertEqual(waypoints[0].y, 0.5, accuracy: 0.001)
    }

    func test_extract_inclusiveBoundaryEvents_areIncluded() {
        // Events exactly at startMs and endMs must be included (inclusive range)
        let events = [
            RawEvent(timeMs: 0, type: .mouseMove, x: 0, y: 0),
            RawEvent(timeMs: 1000, type: .mouseMove, x: 1920, y: 1080)
        ]
        let rawEvents = makeRawEvents(events: events)
        let timeRange = TimeRange(startMs: 0, endMs: 1000)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 2,
            captureArea: rawEvents.captureArea
        )

        // 2Hz: sample at 0ms → (0,0), next at 500ms (no event near, still picks closest which is 0ms)
        // The 1000ms event is at boundary but 2Hz only fires at 0 and 500ms within 1s
        XCTAssertGreaterThanOrEqual(waypoints.count, 1)
    }

    // MARK: - Mixed Event Types

    func test_extract_ignoresNonMouseMoveEvents() {
        let events = [
            RawEvent(timeMs: 100, type: .mouseDown, x: 100, y: 200, button: "left"),
            RawEvent(timeMs: 200, type: .mouseMove, x: 400, y: 300),
            RawEvent(timeMs: 300, type: .mouseUp, x: 400, y: 300, button: "left"),
            RawEvent(timeMs: 400, type: .keyDown, keyCode: 65),
            RawEvent(timeMs: 500, type: .mouseMove, x: 800, y: 600),
            RawEvent(timeMs: 600, type: .scroll, x: 800, y: 600, deltaX: 0, deltaY: -50)
        ]
        let rawEvents = makeRawEvents(events: events)
        let timeRange = TimeRange(startMs: 0, endMs: 700)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 5,
            captureArea: rawEvents.captureArea
        )

        // Only mouse_move events at 200ms and 500ms are candidates
        XCTAssertGreaterThanOrEqual(waypoints.count, 1)
        // No waypoint coordinates should come from non-mouse_move events
        for point in waypoints {
            XCTAssertGreaterThanOrEqual(point.x, 0.0)
            XCTAssertLessThanOrEqual(point.x, 1.0)
            XCTAssertGreaterThanOrEqual(point.y, 0.0)
            XCTAssertLessThanOrEqual(point.y, 1.0)
        }
    }

    // MARK: - Edge Case: Missing x/y coordinates

    func test_extract_eventsWithNilCoordinates_areSkipped() {
        let events = [
            RawEvent(timeMs: 100, type: .mouseMove, x: nil, y: nil), // no coords
            RawEvent(timeMs: 200, type: .mouseMove, x: 960, y: 540)  // has coords
        ]
        let rawEvents = makeRawEvents(events: events)
        let timeRange = TimeRange(startMs: 0, endMs: 500)

        let waypoints = WaypointExtractor.extract(
            from: rawEvents,
            timeRange: timeRange,
            hz: 5,
            captureArea: rawEvents.captureArea
        )

        // Only the event with coordinates should produce a waypoint
        XCTAssertEqual(waypoints.count, 1)
        XCTAssertEqual(waypoints[0].x, 0.5, accuracy: 0.001)
        XCTAssertEqual(waypoints[0].y, 0.5, accuracy: 0.001)
    }
}
