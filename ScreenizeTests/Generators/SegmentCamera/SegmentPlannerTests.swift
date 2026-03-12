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
}
