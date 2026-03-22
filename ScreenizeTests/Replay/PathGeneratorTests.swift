import XCTest
@testable import Screenize

final class PathGeneratorTests: XCTestCase {

    // MARK: - Bezier Determinism

    func testBezierDeterminism_sameStepId_produceSamePath() {
        let start = CGPoint(x: 100, y: 200)
        let end = CGPoint(x: 500, y: 400)
        let stepId = UUID()

        let path1 = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 300, stepId: stepId)
        let path2 = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 300, stepId: stepId)

        XCTAssertEqual(path1.count, path2.count)
        for (p1, p2) in zip(path1, path2) {
            XCTAssertEqual(p1.x, p2.x, accuracy: 0.001)
            XCTAssertEqual(p1.y, p2.y, accuracy: 0.001)
        }
    }

    func testBezierDeterminism_differentStepId_produceDifferentPaths() {
        let start = CGPoint(x: 100, y: 200)
        let end = CGPoint(x: 500, y: 400)
        let stepId1 = UUID()
        let stepId2 = UUID()

        let path1 = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 300, stepId: stepId1)
        let path2 = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 300, stepId: stepId2)

        // At least one intermediate point should differ (endpoints are always equal)
        let hasDifference = zip(path1.dropFirst().dropLast(), path2.dropFirst().dropLast())
            .contains { abs($0.0.x - $0.1.x) > 0.001 || abs($0.0.y - $0.1.y) > 0.001 }
        XCTAssertTrue(hasDifference, "Different stepIds should produce different paths")
    }

    // MARK: - Bezier Endpoints

    func testBezierEndpoints_firstPointIsStart() {
        let start = CGPoint(x: 50, y: 75)
        let end = CGPoint(x: 300, y: 600)
        let stepId = UUID()

        let points = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 200, stepId: stepId)

        XCTAssertFalse(points.isEmpty)
        XCTAssertEqual(points.first?.x ?? 0, start.x, accuracy: 0.001)
        XCTAssertEqual(points.first?.y ?? 0, start.y, accuracy: 0.001)
    }

    func testBezierEndpoints_lastPointIsEnd() {
        let start = CGPoint(x: 50, y: 75)
        let end = CGPoint(x: 300, y: 600)
        let stepId = UUID()

        let points = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 200, stepId: stepId)

        XCTAssertFalse(points.isEmpty)
        XCTAssertEqual(points.last?.x ?? 0, end.x, accuracy: 0.001)
        XCTAssertEqual(points.last?.y ?? 0, end.y, accuracy: 0.001)
    }

    // MARK: - Bezier Zero Distance

    func testBezierZeroDistance_returnsStartPoint() {
        let point = CGPoint(x: 250, y: 350)
        let stepId = UUID()

        let points = PathGenerator.generatePath(from: point, to: point, path: .auto, durationMs: 200, stepId: stepId)

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].x, point.x, accuracy: 0.001)
        XCTAssertEqual(points[0].y, point.y, accuracy: 0.001)
    }

    // MARK: - Bezier Point Count

    func testBezierPointCount_300ms_returns30Points() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 100, y: 100)
        let stepId = UUID()

        let points = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 300, stepId: stepId)

        XCTAssertEqual(points.count, 30)
    }

    func testBezierPointCount_10ms_returns1Point() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 100, y: 100)
        let stepId = UUID()

        let points = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 10, stepId: stepId)

        XCTAssertEqual(points.count, 1)
    }

    func testBezierPointCount_1ms_returns1Point() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 100, y: 100)
        let stepId = UUID()

        let points = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 1, stepId: stepId)

        XCTAssertEqual(points.count, 1, "durationMs=1 should return max(1, 1/10) = 1 point")
    }

    // MARK: - Catmull-Rom Passthrough

    func testCatmullRom_waypointsPresent_pathPassesThroughThem() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 400, y: 400)
        let waypoint = CGPoint(x: 200, y: 50)
        let stepId = UUID()

        let points = PathGenerator.generatePath(
            from: start,
            to: end,
            path: .waypoints(points: [waypoint]),
            durationMs: 300,
            stepId: stepId
        )

        // The waypoint should appear approximately in the output
        let tolerance: CGFloat = 5.0
        let hasWaypoint = points.contains { p in
            abs(p.x - waypoint.x) < tolerance && abs(p.y - waypoint.y) < tolerance
        }
        XCTAssertTrue(hasWaypoint, "Path should pass through the waypoint (within \(tolerance)px tolerance)")
    }

    func testCatmullRom_multipleWaypoints_allPresent() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 600, y: 0)
        let waypoints = [CGPoint(x: 150, y: 100), CGPoint(x: 300, y: -80), CGPoint(x: 450, y: 120)]
        let stepId = UUID()

        let points = PathGenerator.generatePath(
            from: start,
            to: end,
            path: .waypoints(points: waypoints),
            durationMs: 600,
            stepId: stepId
        )

        let tolerance: CGFloat = 5.0
        for wp in waypoints {
            let found = points.contains { p in
                abs(p.x - wp.x) < tolerance && abs(p.y - wp.y) < tolerance
            }
            XCTAssertTrue(found, "Path should pass through waypoint \(wp) within \(tolerance)px tolerance")
        }
    }

    // MARK: - Catmull-Rom Empty Waypoints

    func testCatmullRom_emptyWaypoints_producesLinePath() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 300, y: 0)
        let stepId = UUID()

        let points = PathGenerator.generatePath(
            from: start,
            to: end,
            path: .waypoints(points: []),
            durationMs: 300,
            stepId: stepId
        )

        XCTAssertEqual(points.count, 30)
        // First and last should be start/end
        XCTAssertEqual(points.first?.x ?? 0, start.x, accuracy: 0.001)
        XCTAssertEqual(points.last?.x ?? 0, end.x, accuracy: 0.001)
        // All y values should be near 0 (straight horizontal line)
        for p in points {
            XCTAssertEqual(p.y, 0, accuracy: 0.001)
        }
    }

    // MARK: - Ease-In-Out Values

    func testEaseInOut_t0_returns0() {
        XCTAssertEqual(PathGenerator.easeInOut(0.0), 0.0, accuracy: 0.0001)
    }

    func testEaseInOut_t1_returns1() {
        XCTAssertEqual(PathGenerator.easeInOut(1.0), 1.0, accuracy: 0.0001)
    }

    func testEaseInOut_t0_5_returns0_5() {
        XCTAssertEqual(PathGenerator.easeInOut(0.5), 0.5, accuracy: 0.0001)
    }

    func testEaseInOut_t0_25_lessThan0_25() {
        // Ease-in-out accelerates slowly then faster at t=0.25 (ease-in region)
        let result = PathGenerator.easeInOut(0.25)
        XCTAssertLessThan(result, 0.25, "easeInOut(0.25) should be less than 0.25 (slow start)")
    }

    // MARK: - Auto Path (nil treated as .auto)

    func testAutoPath_nilTreatedSameAsAuto_producesSameResult() {
        let start = CGPoint(x: 100, y: 100)
        let end = CGPoint(x: 400, y: 300)
        let stepId = UUID()

        let pathFromNil = PathGenerator.generatePath(from: start, to: end, path: nil, durationMs: 300, stepId: stepId)
        let pathFromAuto = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 300, stepId: stepId)

        XCTAssertEqual(pathFromNil.count, pathFromAuto.count)
        for (p1, p2) in zip(pathFromNil, pathFromAuto) {
            XCTAssertEqual(p1.x, p2.x, accuracy: 0.001)
            XCTAssertEqual(p1.y, p2.y, accuracy: 0.001)
        }
    }

    // MARK: - Additional edge cases

    func testBezierEndpoints_400ms_returns40Points() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 100, y: 100)

        let points = PathGenerator.generatePath(from: start, to: end, path: .auto, durationMs: 400, stepId: UUID())

        XCTAssertEqual(points.count, 40)
    }

    func testCatmullRom_endpoints_firstIsStart_lastIsEnd() {
        let start = CGPoint(x: 10, y: 20)
        let end = CGPoint(x: 200, y: 300)
        let waypoints = [CGPoint(x: 100, y: 50)]

        let points = PathGenerator.generatePath(
            from: start,
            to: end,
            path: .waypoints(points: waypoints),
            durationMs: 200,
            stepId: UUID()
        )

        XCTAssertFalse(points.isEmpty)
        XCTAssertEqual(points.first?.x ?? 0, start.x, accuracy: 0.001)
        XCTAssertEqual(points.first?.y ?? 0, start.y, accuracy: 0.001)
        XCTAssertEqual(points.last?.x ?? 0, end.x, accuracy: 0.001)
        XCTAssertEqual(points.last?.y ?? 0, end.y, accuracy: 0.001)
    }
}
