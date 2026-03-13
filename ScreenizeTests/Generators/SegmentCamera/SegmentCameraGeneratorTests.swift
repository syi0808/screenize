import XCTest
import CoreGraphics
@testable import Screenize

final class SegmentCameraGeneratorTests: XCTestCase {

    // MARK: - cursorSpeeds

    func test_cursorSpeeds_fastMovingCursor_returnsHighSpeed() {
        let positions = [
            MousePositionData(time: 1.0, position: NormalizedPoint(x: 0.2, y: 0.5)),
            MousePositionData(time: 1.1, position: NormalizedPoint(x: 0.3, y: 0.5)),
            MousePositionData(time: 1.2, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 1.3, position: NormalizedPoint(x: 0.7, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)
        let segment = makeSegment(start: 1.0, end: 3.0)
        let speeds = SegmentCameraGenerator.cursorSpeeds(for: [segment], mouseData: mouseData)
        XCTAssertNotNil(speeds[segment.id])
        XCTAssertGreaterThan(speeds[segment.id]!, 0.8, "Fast cursor should produce speed > 0.8")
    }

    func test_cursorSpeeds_slowMovingCursor_returnsLowSpeed() {
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 0.1, position: NormalizedPoint(x: 0.505, y: 0.5)),
            MousePositionData(time: 0.2, position: NormalizedPoint(x: 0.51, y: 0.5)),
            MousePositionData(time: 0.3, position: NormalizedPoint(x: 0.52, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)
        let segment = makeSegment(start: 0.0, end: 2.0)
        let speeds = SegmentCameraGenerator.cursorSpeeds(for: [segment], mouseData: mouseData)
        XCTAssertNotNil(speeds[segment.id])
        XCTAssertLessThan(speeds[segment.id]!, 0.3, "Slow cursor should produce speed < 0.3")
    }

    func test_cursorSpeeds_noSamplesInWindow_returnsZero() {
        let positions = [
            MousePositionData(time: 5.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 10.0, positions: positions)
        let segment = makeSegment(start: 1.0, end: 3.0)
        let speeds = SegmentCameraGenerator.cursorSpeeds(for: [segment], mouseData: mouseData)
        XCTAssertEqual(speeds[segment.id], 0)
    }

    func test_cursorSpeeds_oneSampleInWindow_returnsZero() {
        let positions = [
            MousePositionData(time: 1.1, position: NormalizedPoint(x: 0.5, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)
        let segment = makeSegment(start: 1.0, end: 3.0)
        let speeds = SegmentCameraGenerator.cursorSpeeds(for: [segment], mouseData: mouseData)
        XCTAssertEqual(speeds[segment.id], 0)
    }

    func test_cursorSpeeds_multipleSegments_returnsSpeedPerSegment() {
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.1, y: 0.5)),
            MousePositionData(time: 0.15, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 0.3, position: NormalizedPoint(x: 0.9, y: 0.5)),
            MousePositionData(time: 2.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 2.15, position: NormalizedPoint(x: 0.51, y: 0.5)),
            MousePositionData(time: 2.3, position: NormalizedPoint(x: 0.52, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)
        let seg1 = makeSegment(start: 0.0, end: 1.5)
        let seg2 = makeSegment(start: 2.0, end: 4.0)
        let speeds = SegmentCameraGenerator.cursorSpeeds(for: [seg1, seg2], mouseData: mouseData)
        XCTAssertGreaterThan(speeds[seg1.id]!, speeds[seg2.id]!, "Fast segment should have higher speed")
    }

    func test_cursorSpeeds_shortSegment_usesFullDuration() {
        let positions = [
            MousePositionData(time: 1.0, position: NormalizedPoint(x: 0.2, y: 0.5)),
            MousePositionData(time: 1.05, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 1.1, position: NormalizedPoint(x: 0.8, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)
        let segment = makeSegment(start: 1.0, end: 1.1)
        let speeds = SegmentCameraGenerator.cursorSpeeds(for: [segment], mouseData: mouseData)
        XCTAssertNotNil(speeds[segment.id])
        XCTAssertGreaterThan(speeds[segment.id]!, 0, "Short segment should still compute speed")
    }

    // MARK: - Helpers

    private func makeSegment(
        start: TimeInterval,
        end: TimeInterval
    ) -> CameraSegment {
        CameraSegment(
            startTime: start,
            endTime: end,
            kind: .manual(
                startTransform: TransformValue(zoom: 1.5, center: NormalizedPoint(x: 0.3, y: 0.4)),
                endTransform: TransformValue(zoom: 1.8, center: NormalizedPoint(x: 0.6, y: 0.7))
            )
        )
    }
}
