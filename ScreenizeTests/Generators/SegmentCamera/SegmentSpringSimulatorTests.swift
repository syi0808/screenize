import XCTest
import CoreGraphics
@testable import Screenize

final class SegmentSpringSimulatorTests: XCTestCase {

    func test_simulate_fastCursorSpeed_producesQuickerArrival() {
        let segment = makeSegment(
            start: 0, end: 2.0,
            startCenter: NormalizedPoint(x: 0.2, y: 0.5),
            endCenter: NormalizedPoint(x: 0.8, y: 0.5),
            startZoom: 1.5, endZoom: 1.8
        )
        let config = SegmentSpringSimulator.Config()
        let resultNormal = SegmentSpringSimulator.simulate(segments: [segment], config: config)
        let resultFast = SegmentSpringSimulator.simulate(
            segments: [segment], config: config, cursorSpeeds: [segment.id: 1.0]
        )

        guard case .continuous(let transformsNormal) = resultNormal[0].kind,
              case .continuous(let transformsFast) = resultFast[0].kind else {
            XCTFail("Expected continuous segments"); return
        }
        let midIndex = transformsNormal.count / 4
        let normalX = transformsNormal[midIndex].transform.center.x
        let fastX = transformsFast[midIndex].transform.center.x
        XCTAssertGreaterThan(
            fastX, normalX,
            "Fast cursor speed should make camera arrive sooner"
        )
    }

    func test_simulate_slowCursorSpeed_noChangeFromDefault() {
        let segment = makeSegment(
            start: 0, end: 2.0,
            startCenter: NormalizedPoint(x: 0.3, y: 0.5),
            endCenter: NormalizedPoint(x: 0.7, y: 0.5),
            startZoom: 1.5, endZoom: 1.5
        )
        let config = SegmentSpringSimulator.Config()
        let resultDefault = SegmentSpringSimulator.simulate(
            segments: [segment], config: config
        )
        let resultSlow = SegmentSpringSimulator.simulate(
            segments: [segment], config: config, cursorSpeeds: [segment.id: 0.1]
        )

        guard case .continuous(let tDefault) = resultDefault[0].kind,
              case .continuous(let tSlow) = resultSlow[0].kind else {
            XCTFail("Expected continuous segments"); return
        }
        let midIndex = tDefault.count / 4
        XCTAssertEqual(
            tDefault[midIndex].transform.center.x,
            tSlow[midIndex].transform.center.x,
            accuracy: 0.001,
            "Slow cursor speed should not change behavior"
        )
    }

    func test_simulate_noCursorSpeeds_behavesAsDefault() {
        let segment = makeSegment(
            start: 0, end: 1.0,
            startCenter: NormalizedPoint(x: 0.3, y: 0.5),
            endCenter: NormalizedPoint(x: 0.7, y: 0.5),
            startZoom: 1.5, endZoom: 1.5
        )
        let config = SegmentSpringSimulator.Config()
        let resultEmpty = SegmentSpringSimulator.simulate(
            segments: [segment], config: config, cursorSpeeds: [:]
        )
        let resultDefault = SegmentSpringSimulator.simulate(
            segments: [segment], config: config
        )

        guard case .continuous(let tEmpty) = resultEmpty[0].kind,
              case .continuous(let tOrig) = resultDefault[0].kind else {
            XCTFail("Expected continuous segments"); return
        }
        let midIndex = tEmpty.count / 2
        XCTAssertEqual(
            tEmpty[midIndex].transform.center.x,
            tOrig[midIndex].transform.center.x,
            accuracy: 0.001,
            "Empty cursorSpeeds should behave identically to default"
        )
    }

    func test_simulate_minResponseFloor_preventsExtremeSpeed() {
        let segment = makeSegment(
            start: 0, end: 0.5,
            startCenter: NormalizedPoint(x: 0.1, y: 0.5),
            endCenter: NormalizedPoint(x: 0.9, y: 0.5),
            startZoom: 1.5, endZoom: 1.5
        )
        let config = SegmentSpringSimulator.Config()
        let result = SegmentSpringSimulator.simulate(
            segments: [segment], config: config, cursorSpeeds: [segment.id: 5.0]
        )

        guard case .continuous(let transforms) = result[0].kind else {
            XCTFail("Expected continuous segment"); return
        }
        for t in transforms {
            XCTAssertFalse(t.transform.center.x.isNaN)
            XCTAssertFalse(t.transform.center.y.isNaN)
            XCTAssertFalse(t.transform.zoom.isNaN)
            XCTAssertGreaterThanOrEqual(
                Double(t.transform.zoom), Double(config.minZoom)
            )
            XCTAssertLessThanOrEqual(
                Double(t.transform.zoom), Double(config.maxZoom)
            )
        }
    }

    // MARK: - Helpers

    private func makeSegment(
        start: TimeInterval, end: TimeInterval,
        startCenter: NormalizedPoint, endCenter: NormalizedPoint,
        startZoom: CGFloat, endZoom: CGFloat
    ) -> CameraSegment {
        CameraSegment(
            startTime: start, endTime: end,
            kind: .manual(
                startTransform: TransformValue(zoom: startZoom, center: startCenter),
                endTransform: TransformValue(zoom: endZoom, center: endCenter)
            )
        )
    }
}
