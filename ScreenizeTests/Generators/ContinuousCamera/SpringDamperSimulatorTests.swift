import XCTest
@testable import Screenize

final class SpringDamperSimulatorTests: XCTestCase {

    private let defaultSettings = ContinuousCameraSettings()

    // MARK: - Empty Input

    func test_simulate_emptyPositions_returnsEmpty() {
        let result = SpringDamperSimulator.simulate(
            cursorPositions: [],
            zoomWaypoints: [],
            duration: 5.0,
            settings: defaultSettings
        )
        XCTAssertTrue(result.isEmpty)
    }

    func test_simulate_zeroDuration_returnsEmpty() {
        let positions = [MousePositionData(time: 0, position: NormalizedPoint(x: 0.5, y: 0.5))]
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: [],
            duration: 0,
            settings: defaultSettings
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Cursor Following

    func test_simulate_stationaryCursor_convergesOnPosition() {
        let positions = (0..<300).map { i in
            MousePositionData(time: Double(i) / 60.0, position: NormalizedPoint(x: 0.4, y: 0.6))
        }
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: [],
            duration: 5.0,
            settings: defaultSettings
        )
        XCTAssertFalse(result.isEmpty)
        guard let last = result.last else { return }
        XCTAssertEqual(last.transform.center.x, 0.4, accuracy: 0.02)
        XCTAssertEqual(last.transform.center.y, 0.6, accuracy: 0.02)
    }

    func test_simulate_movingCursor_cameraFollows() {
        let positions = (0..<180).map { i -> MousePositionData in
            let t = Double(i) / 60.0
            let x = 0.3 + 0.4 * CGFloat(t / 3.0)
            return MousePositionData(time: t, position: NormalizedPoint(x: x, y: 0.5))
        }
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: [],
            duration: 3.0,
            settings: defaultSettings
        )
        guard let last = result.last else { return }
        XCTAssertGreaterThan(last.transform.center.x, 0.6,
                             "Camera should follow cursor")
    }

    func test_simulate_cursorJump_cameraSmooths() {
        var positions: [MousePositionData] = []
        for i in 0..<60 {
            positions.append(MousePositionData(
                time: Double(i) / 60.0,
                position: NormalizedPoint(x: 0.3, y: 0.5)
            ))
        }
        for i in 60..<180 {
            positions.append(MousePositionData(
                time: Double(i) / 60.0,
                position: NormalizedPoint(x: 0.7, y: 0.5)
            ))
        }

        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: [],
            duration: 3.0,
            settings: defaultSettings
        )

        for i in 1..<result.count {
            let dx = abs(result[i].transform.center.x - result[i - 1].transform.center.x)
            XCTAssertLessThan(dx, 0.25, "Camera should smooth cursor jumps at t=\(result[i].time)")
        }
    }

    func test_simulate_startPosition_matchesFirstCursorPosition() {
        let positions = [
            MousePositionData(time: 0, position: NormalizedPoint(x: 0.4, y: 0.6))
        ]
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: [],
            duration: 1.0,
            settings: defaultSettings
        )
        guard let first = result.first else {
            XCTFail("Expected at least one sample")
            return
        }
        XCTAssertEqual(first.transform.center.x, 0.4, accuracy: 0.001)
        XCTAssertEqual(first.transform.center.y, 0.6, accuracy: 0.001)
    }

    // MARK: - Zoom from Waypoints

    func test_simulate_zoomWaypoint_zoomConverges() {
        let positions = (0..<300).map { i in
            MousePositionData(time: Double(i) / 60.0, position: NormalizedPoint(x: 0.5, y: 0.5))
        }
        let zoomWPs = [CameraWaypoint(
            time: 0, targetZoom: 2.0,
            targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
            urgency: .normal, source: .clicking
        )]
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: zoomWPs,
            duration: 5.0,
            settings: defaultSettings
        )
        guard let last = result.last else { return }
        XCTAssertEqual(last.transform.zoom, 2.0, accuracy: 0.05)
    }

    func test_simulate_multipleZoomWaypoints_transitionsSmooth() {
        let positions = (0..<300).map { i in
            MousePositionData(time: Double(i) / 60.0, position: NormalizedPoint(x: 0.5, y: 0.5))
        }
        let zoomWPs = [
            CameraWaypoint(time: 0, targetZoom: 1.5, targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
                           urgency: .normal, source: .clicking),
            CameraWaypoint(time: 2.0, targetZoom: 2.0, targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
                           urgency: .high, source: .typing(context: .codeEditor))
        ]
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: zoomWPs,
            duration: 5.0,
            settings: defaultSettings
        )
        for i in 1..<result.count {
            let dz = abs(result[i].transform.zoom - result[i - 1].transform.zoom)
            XCTAssertLessThan(dz, 0.2, "Zoom transition should be smooth at t=\(result[i].time)")
        }
    }

    func test_simulate_noZoomWaypoints_defaultsToZoom1() {
        let positions = (0..<60).map { i in
            MousePositionData(time: Double(i) / 60.0, position: NormalizedPoint(x: 0.5, y: 0.5))
        }
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: [],
            duration: 1.0,
            settings: defaultSettings
        )
        for sample in result {
            XCTAssertEqual(sample.transform.zoom, 1.0, accuracy: 0.01)
        }
    }

    // MARK: - Zoom Clamping

    func test_simulate_zoomClampedToMinMax() {
        var settings = ContinuousCameraSettings()
        settings.minZoom = 1.0
        settings.maxZoom = 2.5
        let positions = (0..<300).map { i in
            MousePositionData(time: Double(i) / 60.0, position: NormalizedPoint(x: 0.5, y: 0.5))
        }
        let zoomWPs = [CameraWaypoint(
            time: 0, targetZoom: 3.0,
            targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
            urgency: .normal, source: .clicking
        )]
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: zoomWPs,
            duration: 5.0,
            settings: settings
        )
        for sample in result {
            XCTAssertLessThanOrEqual(sample.transform.zoom, settings.maxZoom + 0.001)
            XCTAssertGreaterThanOrEqual(sample.transform.zoom, settings.minZoom - 0.001)
        }
    }

    // MARK: - Immediate Waypoint (App Switch)

    func test_simulate_immediateWaypoint_snapsZoom() {
        let positions = (0..<120).map { i in
            MousePositionData(time: Double(i) / 60.0, position: NormalizedPoint(x: 0.5, y: 0.5))
        }
        let zoomWPs = [
            CameraWaypoint(time: 0, targetZoom: 1.0,
                           targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
                           urgency: .lazy, source: .idle),
            CameraWaypoint(time: 1.0, targetZoom: 2.0,
                           targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
                           urgency: .immediate, source: .switching)
        ]
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: zoomWPs,
            duration: 2.0,
            settings: defaultSettings
        )
        guard let sampleAfterSwitch = result.first(where: { $0.time >= 1.0 }) else {
            XCTFail("Expected sample after switch")
            return
        }
        XCTAssertEqual(sampleAfterSwitch.transform.zoom, 2.0, accuracy: 0.001)
    }

    // MARK: - Urgency Speed

    func test_simulate_highUrgencyZoom_convergesFasterThanLazy() {
        let positions = (0..<120).map { i in
            MousePositionData(time: Double(i) / 60.0, position: NormalizedPoint(x: 0.5, y: 0.5))
        }

        let highWPs = [
            CameraWaypoint(time: 0, targetZoom: 1.0,
                           targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
                           urgency: .lazy, source: .idle),
            CameraWaypoint(time: 0.1, targetZoom: 2.0,
                           targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
                           urgency: .high, source: .typing(context: .codeEditor))
        ]
        let lazyWPs = [
            CameraWaypoint(time: 0, targetZoom: 1.0,
                           targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
                           urgency: .lazy, source: .idle),
            CameraWaypoint(time: 0.1, targetZoom: 2.0,
                           targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
                           urgency: .lazy, source: .idle)
        ]

        let highResult = SpringDamperSimulator.simulate(
            cursorPositions: positions, zoomWaypoints: highWPs,
            duration: 2.0, settings: defaultSettings
        )
        let lazyResult = SpringDamperSimulator.simulate(
            cursorPositions: positions, zoomWaypoints: lazyWPs,
            duration: 2.0, settings: defaultSettings
        )

        let highAt1 = highResult.first { $0.time >= 1.0 }
        let lazyAt1 = lazyResult.first { $0.time >= 1.0 }

        if let h = highAt1, let l = lazyAt1 {
            let highDist = abs(h.transform.zoom - 2.0)
            let lazyDist = abs(l.transform.zoom - 2.0)
            XCTAssertLessThan(highDist, lazyDist)
        }
    }

    // MARK: - Boundary Clamping

    func test_simulate_cursorAtEdge_cameraClamped() {
        let positions = (0..<300).map { i in
            MousePositionData(time: Double(i) / 60.0, position: NormalizedPoint(x: 0.95, y: 0.95))
        }
        let zoomWPs = [CameraWaypoint(
            time: 0, targetZoom: 2.5,
            targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
            urgency: .normal, source: .clicking
        )]
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: zoomWPs,
            duration: 5.0,
            settings: defaultSettings
        )
        for sample in result {
            let halfCrop = 0.5 / sample.transform.zoom
            XCTAssertGreaterThanOrEqual(sample.transform.center.x, halfCrop - 0.06)
            XCTAssertLessThanOrEqual(sample.transform.center.x, 1.0 - halfCrop + 0.06)
        }
    }

    // MARK: - Sample Count

    func test_simulate_sampleCountMatchesTickRate() {
        let positions = [MousePositionData(time: 0, position: NormalizedPoint(x: 0.5, y: 0.5))]
        let duration = 2.0
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: [],
            duration: duration,
            settings: defaultSettings
        )
        let expectedCount = Int(duration * defaultSettings.tickRate) + 1
        XCTAssertEqual(result.count, expectedCount, accuracy: 2)
    }

    // MARK: - Velocity Continuity

    func test_simulate_positionChanges_areContinuous() {
        let positions = (0..<180).map { i -> MousePositionData in
            let t = Double(i) / 60.0
            let x = 0.5 + 0.2 * sin(CGFloat(t) * 2.0)
            return MousePositionData(time: t, position: NormalizedPoint(x: x, y: 0.5))
        }
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: [],
            duration: 3.0,
            settings: defaultSettings
        )
        for i in 1..<result.count {
            let dx = abs(result[i].transform.center.x - result[i - 1].transform.center.x)
            let dy = abs(result[i].transform.center.y - result[i - 1].transform.center.y)
            XCTAssertLessThan(dx, 0.1, "Position X jump too large at t=\(result[i].time)")
            XCTAssertLessThan(dy, 0.1, "Position Y jump too large at t=\(result[i].time)")
        }
    }

    // MARK: - Spring Step Math

    func test_springStep_criticallyDamped_decays() {
        let (pos, vel) = SpringDamperSimulator.springStep(
            current: 1.0, velocity: 0,
            target: 0.5, omega: 10.0, zeta: 1.0, dt: 0.1
        )
        XCTAssertLessThan(pos, 1.0)
        XCTAssertGreaterThan(pos, 0.5)
        XCTAssertLessThan(vel, 0)
    }

    func test_springStep_underdamped_decays() {
        let (pos, _) = SpringDamperSimulator.springStep(
            current: 1.0, velocity: 0,
            target: 0.5, omega: 10.0, zeta: 0.7, dt: 0.1
        )
        XCTAssertLessThan(pos, 1.0)
    }

    // MARK: - Helpers

    private func makeWaypoint(
        time: TimeInterval,
        zoom: CGFloat,
        x: CGFloat,
        y: CGFloat,
        urgency: WaypointUrgency
    ) -> CameraWaypoint {
        CameraWaypoint(
            time: time, targetZoom: zoom,
            targetCenter: NormalizedPoint(x: x, y: y),
            urgency: urgency, source: .idle
        )
    }
}

// XCTAssertEqual for Int with accuracy
private func XCTAssertEqual(
    _ actual: Int, _ expected: Int, accuracy: Int,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertTrue(
        abs(actual - expected) <= accuracy,
        "Expected \(expected) +/- \(accuracy), got \(actual)",
        file: file, line: line
    )
}
