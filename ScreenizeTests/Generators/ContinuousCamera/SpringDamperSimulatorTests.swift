import XCTest
@testable import Screenize

final class SpringDamperSimulatorTests: XCTestCase {

    private let defaultSettings = ContinuousCameraSettings()

    // MARK: - Empty Input

    func test_simulate_emptyWaypoints_returnsEmpty() {
        let result = SpringDamperSimulator.simulate(
            waypoints: [], duration: 5.0, settings: defaultSettings
        )
        XCTAssertTrue(result.isEmpty)
    }

    func test_simulate_zeroDuration_returnsEmpty() {
        let wp = makeWaypoint(time: 0, zoom: 2.0, x: 0.5, y: 0.5, urgency: .normal)
        let result = SpringDamperSimulator.simulate(
            waypoints: [wp], duration: 0, settings: defaultSettings
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Convergence

    func test_simulate_singleWaypoint_convergesOnTarget() {
        let wp = makeWaypoint(time: 0, zoom: 2.0, x: 0.4, y: 0.6, urgency: .normal)
        let result = SpringDamperSimulator.simulate(
            waypoints: [wp], duration: 5.0, settings: defaultSettings
        )
        XCTAssertFalse(result.isEmpty)

        // After 5 seconds the camera should have converged on the target
        guard let last = result.last else { return }
        XCTAssertEqual(last.transform.zoom, 2.0, accuracy: 0.05,
                       "Zoom should converge on target")
        XCTAssertEqual(last.transform.center.x, 0.4, accuracy: 0.02,
                       "X should converge on target")
        XCTAssertEqual(last.transform.center.y, 0.6, accuracy: 0.02,
                       "Y should converge on target")
    }

    func test_simulate_startPosition_matchesFirstWaypoint() {
        let wp = makeWaypoint(time: 0, zoom: 1.5, x: 0.3, y: 0.7, urgency: .normal)
        let result = SpringDamperSimulator.simulate(
            waypoints: [wp], duration: 1.0, settings: defaultSettings
        )
        guard let first = result.first else {
            XCTFail("Expected at least one sample")
            return
        }
        XCTAssertEqual(first.transform.zoom, 1.5, accuracy: 0.001)
        XCTAssertEqual(first.transform.center.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(first.transform.center.y, 0.7, accuracy: 0.001)
    }

    // MARK: - No Overshoot (Critically Damped / Overdamped)

    func test_simulate_criticallyDamped_noZoomOvershoot() {
        var settings = ContinuousCameraSettings()
        settings.positionDampingRatio = 1.0  // critically damped
        settings.zoomDampingRatio = 1.0

        let wp = makeWaypoint(time: 0, zoom: 2.0, x: 0.5, y: 0.5, urgency: .normal)
        let result = SpringDamperSimulator.simulate(
            waypoints: [wp], duration: 3.0, settings: settings
        )

        // Zoom should never exceed target (no overshoot with damping >= 1.0)
        for sample in result {
            XCTAssertLessThanOrEqual(sample.transform.zoom, 2.0 + 0.01,
                                    "Zoom should not overshoot target with critical damping")
        }
    }

    // MARK: - Velocity Continuity

    func test_simulate_twoWaypoints_smoothTransition() {
        let wp1 = makeWaypoint(time: 0, zoom: 1.5, x: 0.3, y: 0.5, urgency: .normal)
        let wp2 = makeWaypoint(time: 2, zoom: 2.0, x: 0.7, y: 0.5, urgency: .normal)
        let result = SpringDamperSimulator.simulate(
            waypoints: [wp1, wp2], duration: 5.0, settings: defaultSettings
        )

        // Check velocity continuity: no sudden jumps in position
        for i in 1..<result.count {
            let dt = result[i].time - result[i - 1].time
            guard dt > 0 else { continue }
            let dx = abs(result[i].transform.center.x - result[i - 1].transform.center.x)
            let dy = abs(result[i].transform.center.y - result[i - 1].transform.center.y)
            let dz = abs(result[i].transform.zoom - result[i - 1].transform.zoom)
            // At 60Hz with dt ~= 0.0167, reasonable max step is ~0.05 for smooth motion
            XCTAssertLessThan(dx, 0.1, "Position X jump too large at t=\(result[i].time)")
            XCTAssertLessThan(dy, 0.1, "Position Y jump too large at t=\(result[i].time)")
            XCTAssertLessThan(dz, 0.2, "Zoom jump too large at t=\(result[i].time)")
        }
    }

    // MARK: - Zoom Clamping

    func test_simulate_zoomClampedToMinMax() {
        var settings = ContinuousCameraSettings()
        settings.minZoom = 1.0
        settings.maxZoom = 2.5

        let wp = makeWaypoint(time: 0, zoom: 2.5, x: 0.5, y: 0.5, urgency: .normal)
        let result = SpringDamperSimulator.simulate(
            waypoints: [wp], duration: 3.0, settings: settings
        )

        for sample in result {
            XCTAssertGreaterThanOrEqual(sample.transform.zoom, settings.minZoom - 0.001)
            XCTAssertLessThanOrEqual(sample.transform.zoom, settings.maxZoom + 0.001)
        }
    }

    // MARK: - Urgency Speed

    func test_simulate_highUrgency_convergesFasterThanLazy() {
        let targetZoom: CGFloat = 2.0
        let targetX: CGFloat = 0.4

        let wpHigh = makeWaypoint(time: 0, zoom: targetZoom, x: targetX, y: 0.5, urgency: .high)
        let wpLazy = makeWaypoint(time: 0, zoom: targetZoom, x: targetX, y: 0.5, urgency: .lazy)

        // Start from zoom=1 (not at target) by using an initial waypoint that differs
        let initWP = makeWaypoint(time: 0, zoom: 1.0, x: 0.5, y: 0.5, urgency: .lazy)

        let highResult = SpringDamperSimulator.simulate(
            waypoints: [initWP, wpHigh], duration: 2.0, settings: defaultSettings
        )
        let lazyResult = SpringDamperSimulator.simulate(
            waypoints: [initWP, wpLazy], duration: 2.0, settings: defaultSettings
        )

        // At t=1.0 high urgency should be closer to target than lazy
        let highAt1 = highResult.first { $0.time >= 0.5 }
        let lazyAt1 = lazyResult.first { $0.time >= 0.5 }

        if let h = highAt1, let l = lazyAt1 {
            let highDist = abs(h.transform.zoom - targetZoom)
            let lazyDist = abs(l.transform.zoom - targetZoom)
            XCTAssertLessThan(highDist, lazyDist,
                              "High urgency should converge faster than lazy")
        }
    }

    // MARK: - Center Clamping

    func test_simulate_centerClampedToViewportBounds() {
        // Target near edge at high zoom — should be clamped
        let wp = makeWaypoint(time: 0, zoom: 2.5, x: 0.95, y: 0.95, urgency: .normal)
        let result = SpringDamperSimulator.simulate(
            waypoints: [wp], duration: 2.0, settings: defaultSettings
        )
        for sample in result {
            let halfCrop = 0.5 / sample.transform.zoom
            XCTAssertGreaterThanOrEqual(sample.transform.center.x, halfCrop - 0.01)
            XCTAssertLessThanOrEqual(sample.transform.center.x, 1.0 - halfCrop + 0.01)
            XCTAssertGreaterThanOrEqual(sample.transform.center.y, halfCrop - 0.01)
            XCTAssertLessThanOrEqual(sample.transform.center.y, 1.0 - halfCrop + 0.01)
        }
    }

    // MARK: - Sample Count

    func test_simulate_sampleCountMatchesTickRate() {
        let wp = makeWaypoint(time: 0, zoom: 1.5, x: 0.5, y: 0.5, urgency: .normal)
        let duration = 2.0
        let result = SpringDamperSimulator.simulate(
            waypoints: [wp], duration: duration, settings: defaultSettings
        )
        let expectedCount = Int(duration * defaultSettings.tickRate) + 1
        // Allow +-2 for floating point rounding in stride
        XCTAssertEqual(result.count, expectedCount, accuracy: 2)
    }

    // MARK: - Spring Step Math

    func test_springStep_criticallyDamped_decays() {
        let (pos, vel) = SpringDamperSimulator.springStep(
            current: 1.0, velocity: 0,
            target: 0.5, omega: 10.0, zeta: 1.0, dt: 0.1
        )
        // Position should move toward target
        XCTAssertLessThan(pos, 1.0)
        XCTAssertGreaterThan(pos, 0.5)
        // Velocity should be negative (moving toward target)
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
            time: time,
            targetZoom: zoom,
            targetCenter: NormalizedPoint(x: x, y: y),
            urgency: urgency,
            source: .idle
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
