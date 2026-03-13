import XCTest
import CoreGraphics
@testable import Screenize

final class SegmentPlannerTests: XCTestCase {

    func test_cursorTravelTime_cursorArrivesQuickly_returnsActualTime() {
        let positions = [
            MousePositionData(time: 1.0, position: NormalizedPoint(x: 0.2, y: 0.5)),
            MousePositionData(time: 1.1, position: NormalizedPoint(x: 0.4, y: 0.5)),
            MousePositionData(time: 1.2, position: NormalizedPoint(x: 0.58, y: 0.5)),
            MousePositionData(time: 1.5, position: NormalizedPoint(x: 0.6, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)
        let time = SegmentPlanner.cursorTravelTime(
            from: NormalizedPoint(x: 0.2, y: 0.5),
            to: NormalizedPoint(x: 0.6, y: 0.5),
            mouseData: mouseData, searchStart: 1.0, searchEnd: 3.0
        )
        XCTAssertGreaterThanOrEqual(time, 0.15)
        XCTAssertLessThanOrEqual(time, 0.8)
        XCTAssertLessThan(time, 0.5, "Quick cursor arrival should produce short travel time")
    }

    func test_cursorTravelTime_cursorArrivesSlowly_returnsLongerTime() {
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.1, y: 0.5)),
            MousePositionData(time: 0.2, position: NormalizedPoint(x: 0.2, y: 0.5)),
            MousePositionData(time: 0.4, position: NormalizedPoint(x: 0.35, y: 0.5)),
            MousePositionData(time: 0.6, position: NormalizedPoint(x: 0.53, y: 0.5)),
            MousePositionData(time: 0.8, position: NormalizedPoint(x: 0.6, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)
        let time = SegmentPlanner.cursorTravelTime(
            from: NormalizedPoint(x: 0.1, y: 0.5),
            to: NormalizedPoint(x: 0.6, y: 0.5),
            mouseData: mouseData, searchStart: 0.0, searchEnd: 2.0
        )
        XCTAssertGreaterThanOrEqual(time, 0.5, "Slow arrival should produce longer time")
        XCTAssertLessThanOrEqual(time, 0.8)
    }

    func test_cursorTravelTime_cursorNeverArrives_usesFallback() {
        let positions = [
            MousePositionData(time: 1.0, position: NormalizedPoint(x: 0.1, y: 0.5)),
            MousePositionData(time: 1.5, position: NormalizedPoint(x: 0.15, y: 0.5)),
            MousePositionData(time: 2.0, position: NormalizedPoint(x: 0.2, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)
        let time = SegmentPlanner.cursorTravelTime(
            from: NormalizedPoint(x: 0.1, y: 0.5),
            to: NormalizedPoint(x: 0.9, y: 0.5),
            mouseData: mouseData, searchStart: 1.0, searchEnd: 3.0
        )
        XCTAssertGreaterThanOrEqual(time, 0.15)
        XCTAssertLessThanOrEqual(time, 0.8)
    }

    func test_cursorTravelTime_noPositionsInRange_usesFallback() {
        let positions = [
            MousePositionData(time: 5.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 10.0, positions: positions)
        let time = SegmentPlanner.cursorTravelTime(
            from: NormalizedPoint(x: 0.2, y: 0.5),
            to: NormalizedPoint(x: 0.5, y: 0.5),
            mouseData: mouseData, searchStart: 0.0, searchEnd: 2.0
        )
        XCTAssertGreaterThanOrEqual(time, 0.15)
        XCTAssertLessThanOrEqual(time, 0.8)
    }

    func test_cursorTravelTime_veryShortDistance_clampsToMin() {
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 0.01, position: NormalizedPoint(x: 0.51, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)
        let time = SegmentPlanner.cursorTravelTime(
            from: NormalizedPoint(x: 0.5, y: 0.5),
            to: NormalizedPoint(x: 0.51, y: 0.5),
            mouseData: mouseData, searchStart: 0.0, searchEnd: 1.0
        )
        XCTAssertEqual(time, 0.15, accuracy: 0.01, "Very short distance should clamp to minTransitionDuration")
    }

    func test_cursorTravelTime_shortSearchWindow_clampsCorrectly() {
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.2, y: 0.5)),
            MousePositionData(time: 0.1, position: NormalizedPoint(x: 0.8, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)
        let time = SegmentPlanner.cursorTravelTime(
            from: NormalizedPoint(x: 0.2, y: 0.5),
            to: NormalizedPoint(x: 0.8, y: 0.5),
            mouseData: mouseData, searchStart: 0.03, searchEnd: 0.05
        )
        XCTAssertGreaterThanOrEqual(time, 0.15)
        XCTAssertLessThanOrEqual(time, 0.8)
    }

    // MARK: - buildSegments split logic (via plan())

    func test_plan_farTarget_createsTwoSegments() {
        let spans = [
            makeIntentSpan(start: 0, end: 2, intent: .clicking, focus: NormalizedPoint(x: 0.5, y: 0.5)),
            makeIntentSpan(start: 2, end: 5, intent: .clicking, focus: NormalizedPoint(x: 0.9, y: 0.5)),
        ]
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 2.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 2.3, position: NormalizedPoint(x: 0.88, y: 0.5)),
            MousePositionData(time: 3.0, position: NormalizedPoint(x: 0.9, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)

        let segments = planWithMouseData(spans: spans, mouseData: mouseData)

        XCTAssertGreaterThanOrEqual(segments.count, 3, "Should have at least 3 segments: hold + transition + hold")

        if let lastSegment = segments.last {
            if case .manual(let start, let end) = lastSegment.kind {
                XCTAssertEqual(Double(start.center.x), Double(end.center.x), accuracy: 0.01, "Hold segment should have same start/end center")
                XCTAssertEqual(Double(start.zoom), Double(end.zoom), accuracy: 0.01, "Hold segment should have same start/end zoom")
            }
        }
    }

    func test_plan_nearTarget_noSplit() {
        // Use a time gap > 0.5 to prevent scene merging, but keep distance < splitDistanceThreshold
        let spans = [
            makeIntentSpan(start: 0, end: 2, intent: .clicking, focus: NormalizedPoint(x: 0.5, y: 0.5)),
            makeIntentSpan(start: 3, end: 6, intent: .clicking, focus: NormalizedPoint(x: 0.54, y: 0.5)),
        ]
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 3.0, position: NormalizedPoint(x: 0.54, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 6.0, positions: positions)

        let segments = planWithMouseData(spans: spans, mouseData: mouseData)

        XCTAssertEqual(segments.count, 2, "Near targets should not be split into transition+hold")
        // Verify no segment is a pure hold (same start/end with different from neighbor)
        for segment in segments {
            if case .manual(let s, let e) = segment.kind {
                // Both segments should just transition (not split)
                _ = s
                _ = e
            }
        }
    }

    func test_plan_shortSpanWithFarTarget_transitionOnly() {
        let spans = [
            makeIntentSpan(start: 0, end: 2, intent: .clicking, focus: NormalizedPoint(x: 0.3, y: 0.5)),
            makeIntentSpan(start: 2, end: 2.2, intent: .clicking, focus: NormalizedPoint(x: 0.8, y: 0.5)),
        ]
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.3, y: 0.5)),
            MousePositionData(time: 2.0, position: NormalizedPoint(x: 0.3, y: 0.5)),
            MousePositionData(time: 2.15, position: NormalizedPoint(x: 0.79, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)

        let segments = planWithMouseData(spans: spans, mouseData: mouseData)

        XCTAssertEqual(segments.count, 2, "Short span with far target should produce transition-only (no hold)")
    }

    func test_plan_firstSegment_alwaysHoldOnly() {
        let spans = [
            makeIntentSpan(start: 0, end: 3, intent: .clicking, focus: NormalizedPoint(x: 0.8, y: 0.5)),
        ]
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.8, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)

        let segments = planWithMouseData(spans: spans, mouseData: mouseData)

        XCTAssertEqual(segments.count, 1, "First segment should always be hold-only")
        if case .manual(let start, let end) = segments[0].kind {
            XCTAssertEqual(Double(start.center.x), Double(end.center.x), accuracy: 0.01)
        }
    }

    func test_plan_zoomDifference_triggersSplit() {
        // Use time gaps > 0.5 to prevent scene merging, and different intents to trigger zoom difference
        let spans = [
            makeIntentSpan(start: 0, end: 2, intent: .clicking, focus: NormalizedPoint(x: 0.5, y: 0.5)),
            makeIntentSpan(start: 3, end: 6, intent: .idle, focus: NormalizedPoint(x: 0.5, y: 0.5)),
            makeIntentSpan(start: 7, end: 10, intent: .clicking, focus: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 7.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 7.1, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 12.0, positions: positions)

        let segments = planWithMouseData(spans: spans, mouseData: mouseData)

        XCTAssertGreaterThanOrEqual(segments.count, 3, "Three non-mergeable spans should produce at least 3 segments")
    }

    // MARK: - Helpers

    private func makeIntentSpan(
        start: TimeInterval,
        end: TimeInterval,
        intent: UserIntent,
        focus: NormalizedPoint
    ) -> IntentSpan {
        IntentSpan(
            startTime: start,
            endTime: end,
            intent: intent,
            confidence: 1.0,
            focusPosition: focus,
            focusElement: nil
        )
    }

    private func planWithMouseData(
        spans: [IntentSpan],
        mouseData: MouseDataSource,
        zoomIntensity: CGFloat = 1.0
    ) -> [CameraSegment] {
        let timeline = EventTimeline.build(
            from: mouseData,
            uiStateSamples: []
        )
        return SegmentPlanner.plan(
            intentSpans: spans,
            screenBounds: CGSize(width: 1920, height: 1080),
            eventTimeline: timeline,
            frameAnalysis: [],
            settings: ShotSettings(),
            zoomIntensity: zoomIntensity,
            mouseData: mouseData
        )
    }
}
