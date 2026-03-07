import XCTest
@testable import Screenize

final class SmoothedMouseDataSourceTests: XCTestCase {

    // MARK: - Pass-through Properties

    func testPassThroughProperties() {
        let click = ClickEventData(
            time: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5),
            clickType: .leftDown
        )
        let kbd = KeyboardEventData(
            time: 2.0,
            keyCode: 0,
            eventType: .keyDown,
            modifiers: [],
            character: "a"
        )
        let drag = DragEventData(
            startTime: 3.0, endTime: 4.0,
            startPosition: NormalizedPoint(x: 0.1, y: 0.1),
            endPosition: NormalizedPoint(x: 0.9, y: 0.9),
            dragType: .selection
        )
        let source = MockMouseDataSource(
            duration: 10.0,
            frameRate: 60.0,
            positions: makeLinearPositions(count: 100, duration: 10.0),
            clicks: [click],
            keyboardEvents: [kbd],
            dragEvents: [drag]
        )

        let smoothed = SmoothedMouseDataSource(wrapping: source)

        XCTAssertEqual(smoothed.duration, 10.0)
        XCTAssertEqual(smoothed.frameRate, 60.0)
        XCTAssertEqual(smoothed.clicks.count, 1)
        XCTAssertEqual(smoothed.clicks[0].time, 1.0)
        XCTAssertEqual(smoothed.keyboardEvents.count, 1)
        XCTAssertEqual(smoothed.keyboardEvents[0].time, 2.0)
        XCTAssertEqual(smoothed.dragEvents.count, 1)
        XCTAssertEqual(smoothed.dragEvents[0].startTime, 3.0)
    }

    // MARK: - Smoothing Applied

    func testSmoothingModifiesPositions() {
        // Create positions with a sharp direction change that smoothing should alter
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.1, y: 0.5)),
            MousePositionData(time: 0.1, position: NormalizedPoint(x: 0.2, y: 0.5)),
            MousePositionData(time: 0.2, position: NormalizedPoint(x: 0.3, y: 0.5)),
            MousePositionData(time: 0.3, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 0.4, position: NormalizedPoint(x: 0.7, y: 0.5)),
            MousePositionData(time: 0.5, position: NormalizedPoint(x: 0.7, y: 0.3)),
            MousePositionData(time: 0.6, position: NormalizedPoint(x: 0.7, y: 0.1)),
            MousePositionData(time: 0.7, position: NormalizedPoint(x: 0.5, y: 0.1)),
            MousePositionData(time: 0.8, position: NormalizedPoint(x: 0.3, y: 0.1)),
            MousePositionData(time: 0.9, position: NormalizedPoint(x: 0.1, y: 0.1)),
            MousePositionData(time: 1.0, position: NormalizedPoint(x: 0.1, y: 0.3)),
        ]

        let source = MockMouseDataSource(
            duration: 1.0,
            frameRate: 60.0,
            positions: positions
        )

        let smoothed = SmoothedMouseDataSource(
            wrapping: source,
            springConfig: .default
        )

        // Smoothed output should have positions (resampled at 60Hz)
        XCTAssertGreaterThan(smoothed.positions.count, 0)

        // At least some positions should differ from raw input
        // (spring smoothing with dampingRatio 0.85 causes slight lag)
        var hasDifference = false
        for smoothedPos in smoothed.positions {
            // Find nearest raw position by time
            if let rawPos = positions.min(by: {
                abs($0.time - smoothedPos.time) < abs($1.time - smoothedPos.time)
            }) {
                let dx = abs(smoothedPos.position.x - rawPos.position.x)
                let dy = abs(smoothedPos.position.y - rawPos.position.y)
                if dx > 0.001 || dy > 0.001 {
                    hasDifference = true
                    break
                }
            }
        }
        XCTAssertTrue(hasDifference, "Smoothing should produce at least some different positions")
    }

    // MARK: - Metadata Preservation

    func testMetadataPreservedFromNearestOriginal() {
        let positions = [
            MousePositionData(
                time: 0.0,
                position: NormalizedPoint(x: 0.3, y: 0.5),
                appBundleID: "com.apple.Xcode",
                elementInfo: nil
            ),
            MousePositionData(
                time: 0.5,
                position: NormalizedPoint(x: 0.5, y: 0.5),
                appBundleID: "com.apple.Xcode",
                elementInfo: nil
            ),
            MousePositionData(
                time: 1.0,
                position: NormalizedPoint(x: 0.7, y: 0.5),
                appBundleID: "com.apple.Safari",
                elementInfo: nil
            ),
        ]

        let source = MockMouseDataSource(
            duration: 1.0,
            frameRate: 30.0,
            positions: positions
        )

        let smoothed = SmoothedMouseDataSource(wrapping: source)

        // Check that early positions inherit appBundleID from Xcode
        let earlyPositions = smoothed.positions.filter { $0.time < 0.3 }
        for pos in earlyPositions {
            XCTAssertEqual(pos.appBundleID, "com.apple.Xcode")
        }

        // Check that late positions inherit appBundleID from Safari
        let latePositions = smoothed.positions.filter { $0.time > 0.8 }
        for pos in latePositions {
            XCTAssertEqual(pos.appBundleID, "com.apple.Safari")
        }
    }

    // MARK: - Edge Cases

    func testEmptyPositionsPassThrough() {
        let source = MockMouseDataSource(
            duration: 5.0,
            frameRate: 60.0,
            positions: []
        )

        let smoothed = SmoothedMouseDataSource(wrapping: source)
        XCTAssertEqual(smoothed.positions.count, 0)
    }

    func testSinglePositionPassThrough() {
        let pos = MousePositionData(
            time: 0.0,
            position: NormalizedPoint(x: 0.5, y: 0.5),
            appBundleID: "com.test"
        )
        let source = MockMouseDataSource(
            duration: 1.0,
            frameRate: 60.0,
            positions: [pos]
        )

        let smoothed = SmoothedMouseDataSource(wrapping: source)
        XCTAssertEqual(smoothed.positions.count, 1)
        XCTAssertEqual(smoothed.positions[0].appBundleID, "com.test")
    }

    // MARK: - Chronological Order

    func testOutputIsChronologicallySorted() {
        let source = MockMouseDataSource(
            duration: 2.0,
            frameRate: 60.0,
            positions: makeLinearPositions(count: 200, duration: 2.0)
        )

        let smoothed = SmoothedMouseDataSource(wrapping: source)

        for i in 1..<smoothed.positions.count {
            XCTAssertGreaterThanOrEqual(
                smoothed.positions[i].time,
                smoothed.positions[i - 1].time,
                "Positions must be in chronological order"
            )
        }
    }

    // MARK: - Helpers

    private func makeLinearPositions(count: Int, duration: TimeInterval) -> [MousePositionData] {
        (0..<count).map { i in
            let t = duration * Double(i) / Double(count - 1)
            let progress = CGFloat(i) / CGFloat(count - 1)
            return MousePositionData(
                time: t,
                position: NormalizedPoint(x: progress, y: 0.5)
            )
        }
    }
}
