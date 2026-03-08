# Cursor-Driven Camera Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Invert camera architecture from intent-driven positioning to cursor-driven positioning, where intent only controls zoom level.

**Architecture:** Dual-layer spring system. Layer 1 (fast spring, ~0.15s) always tracks cursor position. Layer 2 (slow spring, ~2.5s) provides idle re-centering correction. Zoom driven separately by intent classification via waypoints. This replaces the current waypoint-center + cursor-blend approach.

**Tech Stack:** Swift, CoreGraphics, XCTest

**Design doc:** `docs/plans/2026-03-08-cursor-driven-camera-design.md`

---

## Overview of Changes

| File | Change Type | Summary |
|------|-------------|---------|
| `ContinuousCameraTypes.swift` | Modify | Remove cursor blend settings, add cursor-driven settings |
| `SpringDamperSimulator.swift` | Major rewrite | Target cursor directly, waypoints only for zoom |
| `MicroTracker.swift` | Major rewrite | Repurpose as idle re-centering layer |
| `WaypointGenerator.swift` | Simplify | Remove center computation from public API, keep zoom-only |
| `ContinuousCameraGenerator.swift` | Modify | Update pipeline orchestration |
| `SpringDamperSimulatorTests.swift` | Rewrite | New tests for cursor-driven behavior |
| `MicroTrackerTests.swift` | Rewrite | New tests for idle re-centering |

---

### Task 1: Update Settings Types

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`

**Step 1: Update MicroTrackerSettings for idle re-centering**

Replace the current `MicroTrackerSettings` struct. Remove dead zone and max offset (no longer needed). Add idle detection threshold and re-centering spring parameters.

```swift
/// Configuration for the idle re-centering layer (Layer 2).
struct MicroTrackerSettings {
    /// Cursor velocity threshold (normalized units/sec) below which idle re-centering activates.
    var idleVelocityThreshold: CGFloat = 0.05
    /// Spring damping ratio for idle re-centering.
    var dampingRatio: CGFloat = 1.0
    /// Spring response time in seconds for idle re-centering.
    var response: CGFloat = 2.5
}
```

**Step 2: Update ContinuousCameraSettings**

Remove `cursorFollowWeight`, `idleCursorFollowDecay`, `idleCursorFollowFloor` (cursor is now the primary target, no blending needed). Update `positionResponse` to faster value for cursor tracking.

In `ContinuousCameraSettings`:
- Change `positionDampingRatio` default: `1.0` → `0.85` (slight underdamp for natural feel)
- Change `positionResponse` default: `0.8` → `0.15` (fast cursor tracking)
- Change `zoomResponse` default: `0.8` → `0.7`
- Remove `cursorFollowWeight` property
- Remove `idleCursorFollowDecay` property
- Remove `idleCursorFollowFloor` property
- Remove comments for removed properties

**Step 3: Verify build compiles (expect errors in SpringDamperSimulator — that's fine, we fix it next)**

---

### Task 2: Rewrite SpringDamperSimulator

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift`
- Test: `ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift`

The simulator changes from "target waypoint centers blended with cursor" to "target cursor position directly, waypoints only provide zoom targets."

**Step 1: Write failing tests for cursor-driven behavior**

Replace the contents of `SpringDamperSimulatorTests.swift` with tests for the new behavior:

```swift
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
        // Cursor moves from left to right
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
        // Camera should be near cursor end position (0.7), with some spring lag
        XCTAssertGreaterThan(last.transform.center.x, 0.6,
                             "Camera should follow cursor")
    }

    func test_simulate_cursorJump_cameraSmooths() {
        // Cursor jumps instantly from 0.3 to 0.7 at t=1.0
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

        // Verify smooth transition (no single-frame jumps > 0.1)
        for i in 1..<result.count {
            let dx = abs(result[i].transform.center.x - result[i - 1].transform.center.x)
            XCTAssertLessThan(dx, 0.1, "Camera should smooth cursor jumps at t=\(result[i].time)")
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
                           urgency: .high, source: .typing(.codeEditor))
        ]
        let result = SpringDamperSimulator.simulate(
            cursorPositions: positions,
            zoomWaypoints: zoomWPs,
            duration: 5.0,
            settings: defaultSettings
        )
        // Check smooth zoom transitions
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
                           urgency: .high, source: .typing(.codeEditor))
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
        // Cursor makes a zigzag pattern
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
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SpringDamperSimulatorTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: Compilation errors (API signature changed)

**Step 3: Rewrite SpringDamperSimulator.simulate()**

Replace the entire `simulate()` method and remove cursor-blend logic. New signature and implementation:

```swift
struct SpringDamperSimulator {

    // MARK: - Public API

    /// Simulate a continuous cursor-driven camera path.
    /// - Parameters:
    ///   - cursorPositions: Smoothed mouse positions (primary camera target)
    ///   - zoomWaypoints: Intent-derived zoom targets (position data ignored)
    ///   - duration: Total recording duration
    ///   - settings: Physics simulation parameters
    /// - Returns: Time-sorted array of per-tick camera transforms
    static func simulate(
        cursorPositions: [MousePositionData],
        zoomWaypoints: [CameraWaypoint],
        duration: TimeInterval,
        settings: ContinuousCameraSettings
    ) -> [TimedTransform] {
        guard !cursorPositions.isEmpty, duration > 0 else { return [] }

        let dt = 1.0 / settings.tickRate
        let first = cursorPositions[0]

        // Initial zoom from first waypoint or default 1.0
        let initialZoom = zoomWaypoints.first?.targetZoom ?? 1.0

        var state = CameraState(
            positionX: first.position.x,
            positionY: first.position.y,
            zoom: initialZoom
        )
        clampState(&state, settings: settings, dt: CGFloat(dt))

        var results: [TimedTransform] = []
        let estimatedCount = Int(duration * settings.tickRate) + 1
        results.reserveCapacity(estimatedCount)

        // Emit initial sample
        results.append(transformSample(from: state, at: 0))

        var cursorIndex = 0
        var zoomIndex = 0

        // Zoom urgency blending state
        var prevZoomUrgencyMult: CGFloat = settings.urgencyMultipliers[
            zoomWaypoints.first?.urgency ?? .lazy
        ] ?? 1.0
        var zoomUrgencyTransitionStart: TimeInterval = 0

        var t = dt
        let activationTolerance = dt * 0.5

        while t <= duration + dt * 0.5 {
            // Advance cursor index to nearest position at or before current time
            while cursorIndex + 1 < cursorPositions.count
                    && cursorPositions[cursorIndex + 1].time <= t {
                cursorIndex += 1
            }
            let cursorPos = cursorPositions[cursorIndex].position

            // Advance zoom waypoint index
            let previousZoomIndex = zoomIndex
            var activatedImmediate = false
            while zoomIndex + 1 < zoomWaypoints.count
                    && zoomWaypoints[zoomIndex + 1].time <= t + activationTolerance {
                zoomIndex += 1
                activatedImmediate = activatedImmediate
                    || zoomWaypoints[zoomIndex].urgency == .immediate
            }

            // Track zoom urgency transitions
            if zoomIndex != previousZoomIndex {
                prevZoomUrgencyMult = settings.urgencyMultipliers[
                    zoomWaypoints[previousZoomIndex].urgency
                ] ?? 1.0
                zoomUrgencyTransitionStart = t
            }

            // Determine zoom target
            let targetZoom: CGFloat
            if zoomWaypoints.isEmpty {
                targetZoom = 1.0
            } else {
                targetZoom = zoomWaypoints[zoomIndex].targetZoom
            }

            // Handle immediate zoom cuts (app switching)
            if activatedImmediate {
                state.zoom = targetZoom
                state.velocityZoom = 0
            }

            // Compute effective zoom urgency multiplier with blending
            let currentZoomMult = settings.urgencyMultipliers[
                zoomWaypoints.isEmpty ? .lazy : zoomWaypoints[zoomIndex].urgency
            ] ?? 1.0
            let effectiveZoomMult: CGFloat
            let blendDuration = settings.urgencyBlendDuration
            if blendDuration > 0.001 && t - zoomUrgencyTransitionStart < blendDuration {
                let linearProgress = CGFloat((t - zoomUrgencyTransitionStart) / blendDuration)
                let blendProgress = linearProgress * linearProgress * (3 - 2 * linearProgress)
                effectiveZoomMult = prevZoomUrgencyMult
                    + (currentZoomMult - prevZoomUrgencyMult) * blendProgress
            } else {
                effectiveZoomMult = currentZoomMult
            }

            // Position spring: always targets cursor
            let posOmega = 2.0 * .pi / max(0.001, settings.positionResponse)
            let posDamping = settings.positionDampingRatio

            let (newX, newVX) = springStep(
                current: state.positionX, velocity: state.velocityX,
                target: cursorPos.x,
                omega: posOmega, zeta: posDamping, dt: CGFloat(dt)
            )
            let (newY, newVY) = springStep(
                current: state.positionY, velocity: state.velocityY,
                target: cursorPos.y,
                omega: posOmega, zeta: posDamping, dt: CGFloat(dt)
            )

            // Zoom spring: targets intent-derived zoom with urgency scaling
            let zoomOmega = 2.0 * .pi / max(0.001, settings.zoomResponse * effectiveZoomMult)
            let zoomDamping = settings.zoomDampingRatio

            let (newZ, newVZ): (CGFloat, CGFloat)
            if activatedImmediate {
                // Already snapped zoom above
                newZ = state.zoom
                newVZ = 0
            } else {
                (newZ, newVZ) = springStep(
                    current: state.zoom, velocity: state.velocityZoom,
                    target: targetZoom,
                    omega: zoomOmega, zeta: zoomDamping, dt: CGFloat(dt)
                )
            }

            state.positionX = newX
            state.positionY = newY
            state.zoom = newZ
            state.velocityX = newVX
            state.velocityY = newVY
            state.velocityZoom = newVZ

            clampState(&state, settings: settings, dt: CGFloat(dt))
            results.append(transformSample(from: state, at: t))

            t += dt
        }

        return results
    }

    // MARK: - Helpers

    /// Clamp camera state to valid bounds with soft pushback on center axes.
    private static func clampState(
        _ state: inout CameraState,
        settings: ContinuousCameraSettings,
        dt: CGFloat
    ) {
        // Hard clamp zoom
        if state.zoom < settings.minZoom {
            state.zoom = settings.minZoom
            state.velocityZoom = max(0, state.velocityZoom)
        } else if state.zoom > settings.maxZoom {
            state.zoom = settings.maxZoom
            state.velocityZoom = min(0, state.velocityZoom)
        }

        // Soft clamp center
        let clamped = ShotPlanner.clampCenter(
            NormalizedPoint(x: state.positionX, y: state.positionY),
            zoom: state.zoom
        )
        let overflowX = state.positionX - clamped.x
        let overflowY = state.positionY - clamped.y
        let stiffness = settings.boundaryStiffness

        if abs(overflowX) > 0.0001 {
            state.velocityX -= overflowX * stiffness * dt
            let maxOverflow: CGFloat = 0.05
            if abs(overflowX) > maxOverflow {
                state.positionX = clamped.x + copysign(maxOverflow, overflowX)
            }
        }
        if abs(overflowY) > 0.0001 {
            state.velocityY -= overflowY * stiffness * dt
            let maxOverflow: CGFloat = 0.05
            if abs(overflowY) > maxOverflow {
                state.positionY = clamped.y + copysign(maxOverflow, overflowY)
            }
        }
    }

    /// Create a TimedTransform sample from current camera state.
    private static func transformSample(
        from state: CameraState,
        at time: TimeInterval
    ) -> TimedTransform {
        TimedTransform(
            time: time,
            transform: TransformValue(
                zoom: state.zoom,
                center: NormalizedPoint(x: state.positionX, y: state.positionY)
            )
        )
    }

    // MARK: - Spring Math

    /// Solve the damped harmonic oscillator analytically for one timestep.
    static func springStep(
        current x0: CGFloat,
        velocity v0: CGFloat,
        target: CGFloat,
        omega: CGFloat,
        zeta: CGFloat,
        dt: CGFloat
    ) -> (position: CGFloat, velocity: CGFloat) {
        let displacement = x0 - target

        if zeta >= 1.0 {
            let zo = zeta * omega
            let decay = exp(-zo * dt)
            let coeffA = displacement
            let coeffB = v0 + zo * displacement
            let newPos = target + (coeffA + coeffB * dt) * decay
            let newVel = (coeffB - zo * (coeffA + coeffB * dt)) * decay
            return (newPos, newVel)
        } else {
            let wd = omega * sqrt(1.0 - zeta * zeta)
            let zo = zeta * omega
            let decay = exp(-zo * dt)
            let coeffA = displacement
            let coeffB = (v0 + zo * displacement) / wd
            let cosVal = cos(wd * dt)
            let sinVal = sin(wd * dt)
            let newPos = target + decay * (coeffA * cosVal + coeffB * sinVal)
            let newVel = decay * (
                (-zo) * (coeffA * cosVal + coeffB * sinVal)
                + (-coeffA * wd * sinVal + coeffB * wd * cosVal)
            )
            return (newPos, newVel)
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SpringDamperSimulatorTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All PASS

**Step 5: Commit**

```
feat: rewrite SpringDamperSimulator for cursor-driven targeting

Camera now targets cursor position directly instead of blending
waypoint centers with cursor. Waypoints only provide zoom targets.
Position spring (0.15s) follows cursor, zoom spring (0.7s) follows
intent-derived zoom levels.
```

---

### Task 3: Rewrite MicroTracker as Idle Re-centering Layer

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/MicroTracker.swift`
- Test: `ScreenizeTests/Generators/ContinuousCamera/MicroTrackerTests.swift`

**Step 1: Write failing tests for idle re-centering**

Replace `MicroTrackerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import Screenize

final class MicroTrackerTests: XCTestCase {

    private let defaultSettings = MicroTrackerSettings()

    // MARK: - Active Movement: No Correction

    func test_activeCursor_noCorrectionApplied() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0

        // Cursor moving at high velocity (well above idle threshold)
        for i in 0..<60 {
            let t = CGFloat(i) / 60.0
            let cursorX = 0.3 + t * 0.4  // moving from 0.3 to 0.7
            let cameraCenter = NormalizedPoint(x: 0.3 + t * 0.35, y: 0.5)  // slightly behind
            tracker.update(
                cursorPosition: NormalizedPoint(x: cursorX, y: 0.5),
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }

        // During active movement, correction should be near zero
        XCTAssertEqual(tracker.correction.x, 0, accuracy: 0.01,
                       "No re-centering during active movement")
    }

    // MARK: - Idle: Slow Re-centering

    func test_idleCursor_slowlyRecenters() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.6, y: 0.5)
        // Camera is offset from cursor (spring lag from previous movement)
        let cameraCenter = NormalizedPoint(x: 0.5, y: 0.5)

        // Simulate 3 seconds of idle (cursor stationary)
        for _ in 0..<180 {
            tracker.update(
                cursorPosition: cursor,
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }

        // Correction should move toward cursor (positive x direction)
        XCTAssertGreaterThan(tracker.correction.x, 0.01,
                             "Should re-center toward cursor during idle")
    }

    func test_idleCursor_correctionConvergesOnOffset() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.6, y: 0.5)
        let cameraCenter = NormalizedPoint(x: 0.5, y: 0.5)

        // Long idle period — should fully converge
        for _ in 0..<600 {
            tracker.update(
                cursorPosition: cursor,
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }

        // Correction should approach the full offset (0.1)
        XCTAssertEqual(tracker.correction.x, 0.1, accuracy: 0.02,
                       "Correction should converge to fill gap between camera and cursor")
    }

    // MARK: - Transition from Idle to Active

    func test_idleToActive_correctionDecays() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0
        let cameraCenter = NormalizedPoint(x: 0.5, y: 0.5)

        // Build up correction during idle
        for _ in 0..<300 {
            tracker.update(
                cursorPosition: NormalizedPoint(x: 0.6, y: 0.5),
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }
        let idleCorrection = tracker.correction.x
        XCTAssertGreaterThan(idleCorrection, 0.01)

        // Now cursor starts moving again
        for i in 0..<120 {
            let cursorX = 0.6 + CGFloat(i) / 60.0 * 0.1
            tracker.update(
                cursorPosition: NormalizedPoint(x: cursorX, y: 0.5),
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }

        // Correction should decay toward zero during active movement
        XCTAssertLessThan(abs(tracker.correction.x), idleCorrection,
                          "Correction should decay when cursor becomes active")
    }

    // MARK: - Smoothness

    func test_correction_changesGradually() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.7, y: 0.5)
        let cameraCenter = NormalizedPoint(x: 0.5, y: 0.5)

        var corrections: [CGFloat] = []
        for _ in 0..<120 {
            tracker.update(
                cursorPosition: cursor,
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
            corrections.append(tracker.correction.x)
        }

        for i in 1..<corrections.count {
            let jump = abs(corrections[i] - corrections[i - 1])
            XCTAssertLessThan(jump, 0.02,
                              "Correction should change smoothly (jump=\(jump) at frame \(i))")
        }
    }

    // MARK: - Boundary Awareness

    func test_correction_respectsViewportBounds() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.5
        // Camera near edge, cursor beyond edge
        let cameraCenter = NormalizedPoint(x: 0.8, y: 0.5)
        let cursor = NormalizedPoint(x: 0.95, y: 0.5)

        for _ in 0..<600 {
            tracker.update(
                cursorPosition: cursor,
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: 1.0 / 60
            )
        }

        // Final position (camera + correction) should be within viewport bounds
        let finalX = cameraCenter.x + tracker.correction.x
        let halfCrop = 0.5 / zoom
        XCTAssertLessThanOrEqual(finalX, 1.0 - halfCrop + 0.02,
                                 "Re-centered position should respect viewport bounds")
    }
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/MicroTrackerTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: Compilation errors (API changed)

**Step 3: Rewrite MicroTracker**

```swift
import Foundation
import CoreGraphics

/// Idle re-centering layer (Layer 2) for the dual-layer camera system.
///
/// When cursor velocity drops below threshold (idle), slowly applies a
/// correction offset to drift the camera center toward the cursor.
/// When cursor is actively moving, correction decays toward zero
/// (Layer 1's fast spring handles tracking).
struct MicroTracker {

    private let settings: MicroTrackerSettings
    private(set) var correction: (x: CGFloat, y: CGFloat) = (0, 0)
    private var velocityX: CGFloat = 0
    private var velocityY: CGFloat = 0

    /// Tracks cursor velocity for idle detection.
    private var previousCursorPosition: NormalizedPoint?

    init(settings: MicroTrackerSettings) {
        self.settings = settings
    }

    /// Update re-centering correction based on cursor activity.
    /// - Parameters:
    ///   - cursorPosition: Current cursor position (normalized)
    ///   - cameraCenter: Current camera center from Layer 1 (before correction)
    ///   - zoom: Current zoom level
    ///   - dt: Time step
    mutating func update(
        cursorPosition: NormalizedPoint,
        cameraCenter: NormalizedPoint,
        zoom: CGFloat,
        dt: CGFloat
    ) {
        // Compute cursor velocity for idle detection
        let cursorVelocity: CGFloat
        if let prev = previousCursorPosition {
            let dx = cursorPosition.x - prev.x
            let dy = cursorPosition.y - prev.y
            cursorVelocity = sqrt(dx * dx + dy * dy) / max(dt, 0.001)
        } else {
            cursorVelocity = 0
        }
        previousCursorPosition = cursorPosition

        let isIdle = cursorVelocity < settings.idleVelocityThreshold

        // Target: during idle, correct toward cursor; during active, decay to zero
        let targetX: CGFloat
        let targetY: CGFloat
        if isIdle {
            // Gap between camera center and cursor
            targetX = cursorPosition.x - cameraCenter.x
            targetY = cursorPosition.y - cameraCenter.y

            // Clamp target to viewport bounds
            let halfCrop = 0.5 / max(zoom, 1.0)
            let maxCenterX = 1.0 - halfCrop
            let minCenterX = halfCrop
            let maxCenterY = 1.0 - halfCrop
            let minCenterY = halfCrop

            let clampedTargetX: CGFloat
            if cameraCenter.x + targetX > maxCenterX {
                clampedTargetX = maxCenterX - cameraCenter.x
            } else if cameraCenter.x + targetX < minCenterX {
                clampedTargetX = minCenterX - cameraCenter.x
            } else {
                clampedTargetX = targetX
            }

            let clampedTargetY: CGFloat
            if cameraCenter.y + targetY > maxCenterY {
                clampedTargetY = maxCenterY - cameraCenter.y
            } else if cameraCenter.y + targetY < minCenterY {
                clampedTargetY = minCenterY - cameraCenter.y
            } else {
                clampedTargetY = targetY
            }

            let omega = 2.0 * .pi / max(0.001, settings.response)
            let zeta = settings.dampingRatio

            let (newX, newVX) = SpringDamperSimulator.springStep(
                current: correction.x, velocity: velocityX,
                target: clampedTargetX,
                omega: omega, zeta: zeta, dt: dt
            )
            let (newY, newVY) = SpringDamperSimulator.springStep(
                current: correction.y, velocity: velocityY,
                target: clampedTargetY,
                omega: omega, zeta: zeta, dt: dt
            )

            correction = (newX, newY)
            velocityX = newVX
            velocityY = newVY
        } else {
            // Active: decay correction toward zero
            let decayOmega = 2.0 * .pi / max(0.001, settings.response * 0.5)
            let decayZeta: CGFloat = 1.0

            let (newX, newVX) = SpringDamperSimulator.springStep(
                current: correction.x, velocity: velocityX,
                target: 0,
                omega: decayOmega, zeta: decayZeta, dt: dt
            )
            let (newY, newVY) = SpringDamperSimulator.springStep(
                current: correction.y, velocity: velocityY,
                target: 0,
                omega: decayOmega, zeta: decayZeta, dt: dt
            )

            correction = (newX, newY)
            velocityX = newVX
            velocityY = newVY
        }
    }
}
```

**Step 4: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/MicroTrackerTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All PASS

**Step 5: Commit**

```
feat: repurpose MicroTracker as idle re-centering layer

Remove dead zone and max offset concepts. New behavior:
cursor idle → slowly drift camera toward cursor (2.5s spring).
cursor active → correction decays to zero (Layer 1 handles tracking).
```

---

### Task 4: Simplify WaypointGenerator (Zoom-Only Waypoints)

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/WaypointGenerator.swift`
- Test: `ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift`

The WaypointGenerator still needs to produce waypoints, but their `targetCenter` is no longer used by the simulator for positioning. We keep the center computation for diagnostic purposes and for the display track, but the simulator only reads `targetZoom` and `urgency`.

**Step 1: No structural changes needed to WaypointGenerator**

The WaypointGenerator's public API doesn't need to change. The simulator simply ignores `targetCenter` now. The center data is still useful for:
- Display track visualization in the timeline UI
- Diagnostic output
- Future features (e.g., establishing shots)

No code changes to WaypointGenerator itself. However, update the tests to verify behavior hasn't regressed.

**Step 2: Run existing WaypointGenerator tests to ensure they still pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/WaypointGeneratorTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All PASS (WaypointGenerator API unchanged)

**Step 3: Commit (skip if no changes needed)**

---

### Task 5: Update ContinuousCameraGenerator Pipeline

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraGenerator.swift`
- Test: `ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift`

**Step 1: Update generate() to use new API**

The key changes:
1. Pass cursor positions directly to `SpringDamperSimulator.simulate()` (new signature)
2. Pass waypoints as zoom-only source
3. Update `applyMicroTracking()` to use new MicroTracker API (correction-based, no intent spans needed)

```swift
class ContinuousCameraGenerator {

    func generate(
        from mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample],
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        screenBounds: CGSize,
        settings: ContinuousCameraSettings
    ) -> GeneratedTimeline {
        // Step 1: Pre-smooth mouse positions
        let effectiveMouseData: MouseDataSource
        if let springConfig = settings.springConfig {
            effectiveMouseData = SmoothedMouseDataSource(
                wrapping: mouseData,
                springConfig: springConfig
            )
        } else {
            effectiveMouseData = mouseData
        }

        let duration = effectiveMouseData.duration

        // Step 2: Build event timeline
        let timeline = EventTimeline.build(
            from: effectiveMouseData,
            uiStateSamples: uiStateSamples
        )

        // Step 3: Classify intents (for zoom decisions only)
        let intentSpans = IntentClassifier.classify(
            events: timeline,
            uiStateSamples: uiStateSamples
        )

        // Step 4: Generate zoom waypoints from intents
        let waypoints = WaypointGenerator.generate(
            from: intentSpans,
            screenBounds: screenBounds,
            eventTimeline: timeline,
            frameAnalysis: frameAnalysis,
            settings: settings
        )

        // Step 5: Simulate cursor-driven camera path
        let rawSamples = SpringDamperSimulator.simulate(
            cursorPositions: effectiveMouseData.positions,
            zoomWaypoints: waypoints,
            duration: duration,
            settings: settings
        )

        // Step 6: Apply idle re-centering layer
        let recenterSamples = Self.applyIdleRecentering(
            samples: rawSamples,
            mouseData: effectiveMouseData,
            settings: settings
        )

        // Step 7: Apply post-hoc zoom intensity
        let samples = Self.applyZoomIntensity(
            to: recenterSamples, intensity: settings.zoomIntensity
        )

        // Step 8: Create display track
        let displayTrack = Self.createDisplayTrack(from: samples, duration: duration)

        #if DEBUG
        Self.dumpDiagnostics(
            intentSpans: intentSpans,
            waypoints: waypoints,
            sampleCount: samples.count,
            duration: duration
        )
        #endif

        // Step 9: Emit cursor and keystroke tracks
        let cursorTrack = CursorTrackEmitter.emit(
            duration: duration,
            settings: settings.cursor
        )
        let keystrokeTrack = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline,
            duration: duration,
            settings: settings.keystroke
        )

        return GeneratedTimeline(
            cameraTrack: displayTrack,
            cursorTrack: cursorTrack,
            keystrokeTrack: keystrokeTrack,
            continuousTransforms: samples
        )
    }

    // MARK: - Idle Re-centering (Layer 2)

    /// Apply idle re-centering correction to camera samples.
    private static func applyIdleRecentering(
        samples: [TimedTransform],
        mouseData: MouseDataSource,
        settings: ContinuousCameraSettings
    ) -> [TimedTransform] {
        guard !samples.isEmpty else { return samples }

        let positions = mouseData.positions
        var tracker = MicroTracker(settings: settings.micro)
        let dt: CGFloat = 1.0 / CGFloat(settings.tickRate)
        var posIndex = 0

        return samples.map { sample in
            while posIndex + 1 < positions.count
                    && positions[posIndex + 1].time <= sample.time {
                posIndex += 1
            }
            let cursorPos = posIndex < positions.count
                ? positions[posIndex].position
                : sample.transform.center

            let cameraCenter = sample.transform.center
            let zoom = sample.transform.zoom

            tracker.update(
                cursorPosition: cursorPos,
                cameraCenter: cameraCenter,
                zoom: zoom,
                dt: dt
            )

            let finalCenter = ShotPlanner.clampCenter(
                NormalizedPoint(
                    x: cameraCenter.x + tracker.correction.x,
                    y: cameraCenter.y + tracker.correction.y
                ),
                zoom: zoom
            )

            return TimedTransform(
                time: sample.time,
                transform: TransformValue(zoom: zoom, center: finalCenter)
            )
        }
    }

    // MARK: - Zoom Intensity (unchanged)

    private static func applyZoomIntensity(
        to samples: [TimedTransform], intensity: CGFloat
    ) -> [TimedTransform] {
        guard abs(intensity - 1.0) > 0.001 else { return samples }
        return samples.map { sample in
            let newZoom = max(1.0, 1.0 + (sample.transform.zoom - 1.0) * intensity)
            let clamped = ShotPlanner.clampCenter(sample.transform.center, zoom: newZoom)
            return TimedTransform(
                time: sample.time,
                transform: TransformValue(zoom: newZoom, center: clamped)
            )
        }
    }

    // MARK: - Display Track (unchanged)

    private static func createDisplayTrack(
        from samples: [TimedTransform],
        duration: TimeInterval
    ) -> CameraTrack {
        guard let first = samples.first, let last = samples.last else {
            return CameraTrack(segments: [])
        }
        let segment = CameraSegment(
            startTime: first.time,
            endTime: max(first.time + 0.001, last.time > 0 ? last.time : duration),
            startTransform: first.transform,
            endTransform: last.transform
        )
        return CameraTrack(segments: [segment])
    }

    // MARK: - Diagnostics (unchanged)

    #if DEBUG
    private static func dumpDiagnostics(
        intentSpans: [IntentSpan],
        waypoints: [CameraWaypoint],
        sampleCount: Int,
        duration: TimeInterval
    ) {
        print("[ContinuousCamera] === Diagnostics ===")
        print("[ContinuousCamera] Duration: \(String(format: "%.1f", duration))s")
        print("[ContinuousCamera] IntentSpans: \(intentSpans.count)")
        print("[ContinuousCamera] Waypoints (zoom-only): \(waypoints.count)")
        for (i, wp) in waypoints.enumerated() {
            let t = String(format: "t=%.2f", wp.time)
            let zoom = String(format: "zoom=%.2f", wp.targetZoom)
            print("[ContinuousCamera]   [\(i)] \(t) \(zoom) urgency=\(wp.urgency)")
        }
        print("[ContinuousCamera] Samples: \(sampleCount) (cursor-driven, no segments)")
        print("[ContinuousCamera] === End Diagnostics ===")
    }
    #endif
}
```

**Step 2: Run all ContinuousCamera tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ContinuousCameraGeneratorTests -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All PASS

**Step 3: Run full test suite**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' 2>&1 | tail -50`
Expected: All PASS

**Step 4: Commit**

```
feat: update pipeline for cursor-driven camera architecture

ContinuousCameraGenerator now passes cursor positions directly to
SpringDamperSimulator. MicroTracker applies idle re-centering as
Layer 2. Intent classification only drives zoom decisions.
```

---

### Task 6: Build Verification and Cleanup

**Step 1: Full project build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

**Step 2: Lint check**

Run: `./scripts/lint.sh`
Expected: No new violations (fix any introduced)

**Step 3: Run full test suite one final time**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' 2>&1 | tail -50`
Expected: All tests pass

**Step 4: Commit any cleanup**

---

## Parameter Reference (for future tuning)

After implementation, these parameters control the camera feel:

| Parameter | Location | Default | Effect |
|-----------|----------|---------|--------|
| `positionResponse` | ContinuousCameraSettings | 0.15s | How quickly camera follows cursor |
| `positionDampingRatio` | ContinuousCameraSettings | 0.85 | Underdamp = slight overshoot = natural |
| `zoomResponse` | ContinuousCameraSettings | 0.7s | Zoom transition speed |
| `zoomDampingRatio` | ContinuousCameraSettings | 1.0 | Critical = no zoom bounce |
| `micro.response` | MicroTrackerSettings | 2.5s | Idle re-centering speed |
| `micro.dampingRatio` | MicroTrackerSettings | 1.0 | Critical = smooth drift |
| `micro.idleVelocityThreshold` | MicroTrackerSettings | 0.05 | When to start re-centering |
| `boundaryStiffness` | ContinuousCameraSettings | 30.0 | Edge pushback force |
| `urgencyMultipliers` | ContinuousCameraSettings | varies | Zoom speed per intent type |
