# Smart Generation Quality Improvements Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve smart generation quality by coupling spring response to cursor speed (segment-based) and eliminating unnecessary zoom oscillation (continuous).

**Architecture:** Two independent changes — (1) pre-compute cursor velocity per segment in `SegmentCameraGenerator` and pass to `SegmentSpringSimulator` for adaptive response, (2) add post-processing pass in `WaypointGenerator` to detect and remove unnecessary zoomOut waypoints between active intents.

**Tech Stack:** Swift, XCTest, CoreGraphics

**Spec:** `docs/superpowers/specs/2026-03-13-smart-generation-quality-improvements-design.md`

---

## Chunk 1: Cursor Speed-Coupled Spring Response

### Task 1: Add `cursorSpeeds(for:mouseData:)` to SegmentCameraGenerator

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift`
- Create: `ScreenizeTests/Generators/SegmentCamera/SegmentCameraGeneratorTests.swift`

- [ ] **Step 1: Write tests for cursorSpeeds computation**

Create the test file. Tests cover: normal speed, fast cursor, slow cursor, segment with < 2 samples, empty segments.

```swift
import XCTest
import CoreGraphics
@testable import Screenize

final class SegmentCameraGeneratorTests: XCTestCase {

    private let generator = SegmentCameraGenerator()

    // MARK: - cursorSpeeds

    func test_cursorSpeeds_fastMovingCursor_returnsHighSpeed() {
        // Cursor moves 0.5 normalized units in 0.3 seconds = ~1.67 units/s
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
        // Cursor barely moves: 0.02 units in 0.3s = ~0.067 units/s
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
        // No positions in segment time range
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
            // Segment 1: fast
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.1, y: 0.5)),
            MousePositionData(time: 0.15, position: NormalizedPoint(x: 0.5, y: 0.5)),
            MousePositionData(time: 0.3, position: NormalizedPoint(x: 0.9, y: 0.5)),
            // Segment 2: slow
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
        // Segment only 0.1s long — window should be capped to segment end
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
                endTransform: TransformValue(zoom: 1.8, center: NormalizedPoint(x: 0.6, y: 0.7)),
                interpolation: .easeInOut
            ),
            transitionToNext: SegmentTransition(duration: 0, easing: .linear)
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentCameraGeneratorTests 2>&1 | tail -20`
Expected: Compilation error — `cursorSpeeds` method doesn't exist yet.

- [ ] **Step 3: Implement `cursorSpeeds(for:mouseData:)`**

Add to `SegmentCameraGenerator` as a static method (so tests can call it directly):

```swift
// Add after the generate() method, before closing brace of class

/// Compute cursor velocity at the start of each segment.
/// Returns a dictionary mapping segment ID to speed in normalized units/sec.
/// Speed is net displacement over the first 0.3s (or segment duration if shorter).
static func cursorSpeeds(
    for segments: [CameraSegment],
    mouseData: MouseDataSource
) -> [UUID: CGFloat] {
    let sampleWindow: TimeInterval = 0.3
    var result: [UUID: CGFloat] = [:]

    for segment in segments {
        let windowEnd = min(segment.startTime + sampleWindow, segment.endTime)
        let samples = mouseData.positions.filter {
            $0.time >= segment.startTime && $0.time <= windowEnd
        }

        guard samples.count >= 2,
              let first = samples.first,
              let last = samples.last else {
            result[segment.id] = 0
            continue
        }

        let timeDelta = last.time - first.time
        guard timeDelta > 0.001 else {
            result[segment.id] = 0
            continue
        }

        let dx = last.position.x - first.position.x
        let dy = last.position.y - first.position.y
        let distance = sqrt(dx * dx + dy * dy)
        result[segment.id] = distance / CGFloat(timeDelta)
    }

    return result
}
```

- [ ] **Step 4: Add test file to Xcode project**

Add `SegmentCameraGeneratorTests.swift` to `project.pbxproj` under the `ScreenizeTests` target. Create the `SegmentCamera` group under `ScreenizeTests/Generators/` if it doesn't exist.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentCameraGeneratorTests 2>&1 | tail -30`
Expected: All 6 tests pass.

- [ ] **Step 6: Commit**

```bash
git add ScreenizeTests/Generators/SegmentCamera/SegmentCameraGeneratorTests.swift Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift Screenize.xcodeproj/project.pbxproj
git commit -m "feat: add cursorSpeeds computation to SegmentCameraGenerator"
```

---

### Task 2: Apply cursor speed factor in SegmentSpringSimulator

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentSpringSimulator.swift:23-26,62-69`
- Create: `ScreenizeTests/Generators/SegmentCamera/SegmentSpringSimulatorTests.swift`

- [ ] **Step 1: Write tests for speed-coupled spring response**

```swift
import XCTest
import CoreGraphics
@testable import Screenize

final class SegmentSpringSimulatorTests: XCTestCase {

    // MARK: - Cursor Speed Factor

    func test_simulate_fastCursorSpeed_producesQuickerArrival() {
        // Two identical segments, one with fast cursor speed, one without
        let segment = makeSegment(
            start: 0, end: 2.0,
            startCenter: NormalizedPoint(x: 0.2, y: 0.5),
            endCenter: NormalizedPoint(x: 0.8, y: 0.5),
            startZoom: 1.5, endZoom: 1.8
        )

        let config = SegmentSpringSimulator.Config()

        // Without speed factor (default)
        let resultNormal = SegmentSpringSimulator.simulate(
            segments: [segment], config: config
        )
        // With fast cursor speed
        let resultFast = SegmentSpringSimulator.simulate(
            segments: [segment], config: config,
            cursorSpeeds: [segment.id: 1.0]
        )

        // Both should produce continuous segments
        guard case .continuous(let transformsNormal) = resultNormal[0].kind,
              case .continuous(let transformsFast) = resultFast[0].kind else {
            XCTFail("Expected continuous segments")
            return
        }

        // At 0.5s mark, fast version should be closer to target (0.8)
        let midIndex = transformsNormal.count / 4  // ~0.5s into 2s segment
        let normalX = transformsNormal[midIndex].transform.center.x
        let fastX = transformsFast[midIndex].transform.center.x

        XCTAssertGreaterThan(fastX, normalX,
            "Fast cursor speed should make camera arrive sooner (closer to target at 0.5s)")
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
            segments: [segment], config: config,
            cursorSpeeds: [segment.id: 0.1]
        )

        guard case .continuous(let tDefault) = resultDefault[0].kind,
              case .continuous(let tSlow) = resultSlow[0].kind else {
            XCTFail("Expected continuous segments")
            return
        }

        // Slow speed (< 0.3) should produce factor 1.0 — identical to default
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
            segments: [segment], config: config,
            cursorSpeeds: [:]
        )
        let resultDefault = SegmentSpringSimulator.simulate(
            segments: [segment], config: config
        )

        guard case .continuous(let tEmpty) = resultEmpty[0].kind,
              case .continuous(let tOrig) = resultDefault[0].kind else {
            XCTFail("Expected continuous segments")
            return
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
        // Even with very high cursor speed, response should not go below minResponse
        let segment = makeSegment(
            start: 0, end: 0.5,
            startCenter: NormalizedPoint(x: 0.1, y: 0.5),
            endCenter: NormalizedPoint(x: 0.9, y: 0.5),
            startZoom: 1.5, endZoom: 1.5
        )

        let config = SegmentSpringSimulator.Config()

        // Very high speed — should still produce valid, non-jerky output
        let result = SegmentSpringSimulator.simulate(
            segments: [segment], config: config,
            cursorSpeeds: [segment.id: 5.0]
        )

        guard case .continuous(let transforms) = result[0].kind else {
            XCTFail("Expected continuous segment")
            return
        }

        // Verify output is valid: no NaN, values stay in bounds
        for t in transforms {
            XCTAssertFalse(t.transform.center.x.isNaN)
            XCTAssertFalse(t.transform.center.y.isNaN)
            XCTAssertFalse(t.transform.zoom.isNaN)
            XCTAssertGreaterThanOrEqual(t.transform.zoom, config.minZoom)
            XCTAssertLessThanOrEqual(t.transform.zoom, config.maxZoom)
        }
    }

    // MARK: - Helpers

    private func makeSegment(
        start: TimeInterval,
        end: TimeInterval,
        startCenter: NormalizedPoint,
        endCenter: NormalizedPoint,
        startZoom: CGFloat,
        endZoom: CGFloat
    ) -> CameraSegment {
        CameraSegment(
            startTime: start,
            endTime: end,
            kind: .manual(
                startTransform: TransformValue(zoom: startZoom, center: startCenter),
                endTransform: TransformValue(zoom: endZoom, center: endCenter),
                interpolation: .easeInOut
            ),
            transitionToNext: SegmentTransition(duration: 0, easing: .linear)
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentSpringSimulatorTests 2>&1 | tail -20`
Expected: Compilation error — `simulate` doesn't accept `cursorSpeeds` parameter yet.

- [ ] **Step 3: Implement cursor speed factor in simulate()**

Modify `SegmentSpringSimulator.swift`:

1. Add `cursorSpeeds` parameter to `simulate()` signature (line 23-26):

```swift
static func simulate(
    segments: [CameraSegment],
    config: Config = Config(),
    cursorSpeeds: [UUID: CGFloat] = [:]
) -> [CameraSegment] {
```

2. Add speed factor helper (inside the struct, before `simulate`):

```swift
/// Maps cursor speed (normalized units/sec) to a response factor.
/// Slow (< 0.3): 1.0, Medium (0.3–0.8): linear 1.0→0.5, Fast (> 0.8): 0.5
private static func speedFactor(for speed: CGFloat) -> CGFloat {
    let slowThreshold: CGFloat = 0.3
    let fastThreshold: CGFloat = 0.8
    let minFactor: CGFloat = 0.5

    if speed <= slowThreshold { return 1.0 }
    if speed >= fastThreshold { return minFactor }
    // Linear interpolation between thresholds
    let t = (speed - slowThreshold) / (fastThreshold - slowThreshold)
    return 1.0 - t * (1.0 - minFactor)
}
```

3. Apply factor in the per-segment response calculation (replace lines 65-67):

```swift
let segmentDuration = CGFloat(segment.endTime - segment.startTime)
let factor = speedFactor(for: cursorSpeeds[segment.id] ?? 0)
let minResponse: CGFloat = 0.15
let adaptedPosResponse = max(minResponse, max(config.positionResponse, segmentDuration * 0.4) * factor)
let adaptedZoomResponse = max(minResponse, max(config.zoomResponse, segmentDuration * 0.45) * factor)
```

- [ ] **Step 4: Add test file to Xcode project**

Add `SegmentSpringSimulatorTests.swift` to `project.pbxproj` under the `ScreenizeTests` target, in the `SegmentCamera` group.

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentSpringSimulatorTests 2>&1 | tail -30`
Expected: All 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentSpringSimulator.swift ScreenizeTests/Generators/SegmentCamera/SegmentSpringSimulatorTests.swift Screenize.xcodeproj/project.pbxproj
git commit -m "feat: apply cursor speed factor to spring response in SegmentSpringSimulator"
```

---

### Task 3: Wire cursor speeds into SegmentCameraGenerator pipeline

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift:58-70`

- [ ] **Step 1: Update generate() to compute and pass cursor speeds**

In `SegmentCameraGenerator.swift`, between step 4 (line 56) and step 5 (line 58), add cursor speed computation and pass to simulate:

```swift
// Step 4.5: Compute cursor speeds for adaptive spring response
let speeds = SegmentCameraGenerator.cursorSpeeds(
    for: rawSegments,
    mouseData: effectiveMouseData
)

// Step 5: Spring-simulate segment transitions
let segments = SegmentSpringSimulator.simulate(
    segments: rawSegments,
    config: SegmentSpringSimulator.Config(
        positionDampingRatio: settings.positionDampingRatio,
        positionResponse: settings.positionResponse,
        zoomDampingRatio: settings.zoomDampingRatio,
        zoomResponse: settings.zoomResponse,
        tickRate: settings.tickRate,
        minZoom: settings.minZoom,
        maxZoom: settings.maxZoom
    ),
    cursorSpeeds: speeds
)
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all segment-related tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentCameraGeneratorTests -only-testing:ScreenizeTests/SegmentSpringSimulatorTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift
git commit -m "feat: wire cursor speed computation into segment generation pipeline"
```

---

## Chunk 2: Zoom Transition Optimizer

### Task 4: Add `optimizeZoomTransitions` to WaypointGenerator

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/WaypointGenerator.swift`
- Modify: `ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift`

- [ ] **Step 1: Write tests for zoom transition optimization**

Add to existing `WaypointGeneratorTests.swift`:

```swift
// MARK: - Zoom Transition Optimization

func test_optimizeZoomTransitions_nearbyClicks_removesIntermediateZoomOut() {
    // Click at 0.3,0.5 → idle → click at 0.35,0.5 (distance 0.05 < nearThreshold 0.15)
    let spans = [
        makeIntentSpan(start: 1, end: 2, intent: .clicking, focus: NormalizedPoint(x: 0.3, y: 0.5)),
        makeIntentSpan(start: 2, end: 3, intent: .idle, focus: NormalizedPoint(x: 0.3, y: 0.5)),
        makeIntentSpan(start: 3, end: 4, intent: .clicking, focus: NormalizedPoint(x: 0.35, y: 0.5)),
    ]
    let waypoints = WaypointGenerator.generate(
        from: spans,
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: nil,
        frameAnalysis: [],
        settings: defaultSettings
    )

    // Should have no idle/zoomOut waypoint between the two clicks
    let idleWaypoints = waypoints.filter {
        if case .idle = $0.source { return true }
        return false
    }
    XCTAssertEqual(idleWaypoints.count, 0, "Nearby clicks should eliminate intermediate idle waypoint")
}

func test_optimizeZoomTransitions_farApartClicks_keepsReducedZoomOut() {
    // Click at 0.1,0.5 → idle (long gap) → click at 0.9,0.5 (distance 0.8 > farThreshold)
    let spans = [
        makeIntentSpan(start: 1, end: 2, intent: .clicking, focus: NormalizedPoint(x: 0.1, y: 0.5)),
        makeIntentSpan(start: 4, end: 6, intent: .idle, focus: NormalizedPoint(x: 0.5, y: 0.5)),
        makeIntentSpan(start: 6, end: 7, intent: .clicking, focus: NormalizedPoint(x: 0.9, y: 0.5)),
    ]
    let waypoints = WaypointGenerator.generate(
        from: spans,
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: nil,
        frameAnalysis: [],
        settings: defaultSettings
    )

    // Idle waypoint should still exist but with reduced zoom
    let idleWaypoints = waypoints.filter {
        if case .idle = $0.source { return true }
        return false
    }
    XCTAssertEqual(idleWaypoints.count, 1, "Far-apart clicks should keep idle waypoint")
    if let idleWP = idleWaypoints.first {
        XCTAssertGreaterThan(idleWP.targetZoom, 1.0,
            "Reduced zoom should be above 1.0 (partial zoom-out, not full)")
    }
}

func test_optimizeZoomTransitions_quickSuccession_removesZoomOut() {
    // Click at 0.2,0.5 → short idle → click at 0.45,0.5
    // Distance 0.25 (< farThreshold 0.35), time gap 0.5s (< quickThreshold 1.5s)
    let spans = [
        makeIntentSpan(start: 1, end: 1.5, intent: .clicking, focus: NormalizedPoint(x: 0.2, y: 0.5)),
        makeIntentSpan(start: 1.5, end: 2, intent: .idle, focus: NormalizedPoint(x: 0.3, y: 0.5)),
        makeIntentSpan(start: 2, end: 2.5, intent: .clicking, focus: NormalizedPoint(x: 0.45, y: 0.5)),
    ]
    let waypoints = WaypointGenerator.generate(
        from: spans,
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: nil,
        frameAnalysis: [],
        settings: defaultSettings
    )

    let idleWaypoints = waypoints.filter {
        if case .idle = $0.source { return true }
        return false
    }
    XCTAssertEqual(idleWaypoints.count, 0, "Quick succession should remove idle waypoint")
}

func test_optimizeZoomTransitions_differentZoomLevels_keepsZoomOut() {
    // Click (zoom ~1.8) → idle → typing (zoom ~2.0+), zoom diff > 0.3
    let spans = [
        makeIntentSpan(start: 1, end: 2, intent: .clicking, focus: NormalizedPoint(x: 0.3, y: 0.5)),
        makeIntentSpan(start: 2, end: 2.5, intent: .idle, focus: NormalizedPoint(x: 0.3, y: 0.5)),
        makeIntentSpan(start: 2.5, end: 5, intent: .typing(context: .textField), focus: NormalizedPoint(x: 0.35, y: 0.5)),
    ]
    let waypoints = WaypointGenerator.generate(
        from: spans,
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: nil,
        frameAnalysis: [],
        settings: defaultSettings
    )

    // Check that the zoom levels of clicking vs typing are different enough
    let clickWP = waypoints.first { if case .clicking = $0.source { return true }; return false }
    let typingWP = waypoints.first { if case .typing = $0.source { return true }; return false }

    // If zoom levels differ by >= 0.3, the idle waypoint should be kept
    if let c = clickWP, let t = typingWP, abs(c.targetZoom - t.targetZoom) >= 0.3 {
        let idleWaypoints = waypoints.filter {
            if case .idle = $0.source { return true }
            return false
        }
        XCTAssertGreaterThanOrEqual(idleWaypoints.count, 1,
            "Different zoom levels should preserve idle waypoint for natural transition")
    }
}

func test_optimizeZoomTransitions_singleClick_noChange() {
    let spans = [
        makeIntentSpan(start: 1, end: 2, intent: .clicking, focus: NormalizedPoint(x: 0.5, y: 0.5)),
    ]
    let waypoints = WaypointGenerator.generate(
        from: spans,
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: nil,
        frameAnalysis: [],
        settings: defaultSettings
    )

    // Should have waypoints — no crash, no triplet to optimize
    XCTAssertGreaterThanOrEqual(waypoints.count, 1)
}

func test_optimizeZoomTransitions_threeConsecutiveClicks_removesAllIdleWaypoints() {
    // Click → idle → click → idle → click, all nearby
    let spans = [
        makeIntentSpan(start: 1, end: 1.5, intent: .clicking, focus: NormalizedPoint(x: 0.3, y: 0.5)),
        makeIntentSpan(start: 1.5, end: 2, intent: .idle, focus: NormalizedPoint(x: 0.3, y: 0.5)),
        makeIntentSpan(start: 2, end: 2.5, intent: .clicking, focus: NormalizedPoint(x: 0.32, y: 0.5)),
        makeIntentSpan(start: 2.5, end: 3, intent: .idle, focus: NormalizedPoint(x: 0.32, y: 0.5)),
        makeIntentSpan(start: 3, end: 3.5, intent: .clicking, focus: NormalizedPoint(x: 0.34, y: 0.5)),
    ]
    let waypoints = WaypointGenerator.generate(
        from: spans,
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: nil,
        frameAnalysis: [],
        settings: defaultSettings
    )

    let idleWaypoints = waypoints.filter {
        if case .idle = $0.source { return true }
        return false
    }
    XCTAssertEqual(idleWaypoints.count, 0, "All intermediate idle waypoints should be removed for nearby consecutive clicks")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/WaypointGeneratorTests 2>&1 | tail -20`
Expected: New tests fail (idle waypoints still present).

- [ ] **Step 3: Add isActiveIntent helper and optimizeZoomTransitions**

Add to `WaypointGenerator.swift`, before the closing brace of the struct:

```swift
// MARK: - Zoom Transition Optimization

private static let nearThreshold: CGFloat = 0.15
private static let farThreshold: CGFloat = 0.35
private static let quickThreshold: TimeInterval = 1.5
private static let zoomSimilarityThreshold: CGFloat = 0.3
private static let zoomReductionFactor: CGFloat = 0.7

/// Whether this intent is an active (zoom-in) intent.
private static func isActiveIntent(_ intent: UserIntent) -> Bool {
    switch intent {
    case .clicking, .navigating, .scrolling: return true
    case .typing: return true
    case .dragging: return true
    case .idle, .reading, .switching: return false
    }
}

/// Post-process waypoints to remove unnecessary zoomOut between active intents.
///
/// Detects zoomIn→zoomOut→zoomIn triplets and removes or reduces the
/// intermediate zoomOut based on distance and time thresholds.
static func optimizeZoomTransitions(_ waypoints: inout [CameraWaypoint]) {
    guard waypoints.count >= 3 else { return }

    var i = 0
    while i + 2 < waypoints.count {
        let first = waypoints[i]
        let mid = waypoints[i + 1]
        let third = waypoints[i + 2]

        // Check triplet pattern: active → passive → active
        guard isActiveIntent(first.source),
              !isActiveIntent(mid.source),
              isActiveIntent(third.source) else {
            i += 1
            continue
        }

        // Guard: zoom levels must be similar
        guard abs(first.targetZoom - third.targetZoom) < zoomSimilarityThreshold else {
            i += 1
            continue
        }

        let dx = first.targetCenter.x - third.targetCenter.x
        let dy = first.targetCenter.y - third.targetCenter.y
        let distance = sqrt(dx * dx + dy * dy)
        let timeGap = third.time - first.time

        if distance < nearThreshold {
            // Near: remove zoomOut entirely
            waypoints.remove(at: i + 1)
            // Re-evaluate from i-1 (or stay at i if at start)
            i = max(0, i - 1)
        } else if distance < farThreshold && timeGap < quickThreshold {
            // Medium distance + quick succession: remove zoomOut
            waypoints.remove(at: i + 1)
            i = max(0, i - 1)
        } else {
            // Far/slow: reduce zoom instead of full zoomOut
            let reducedZoom = max(first.targetZoom * zoomReductionFactor, 1.0)
            waypoints[i + 1] = CameraWaypoint(
                time: mid.time,
                targetZoom: reducedZoom,
                targetCenter: mid.targetCenter,
                urgency: mid.urgency,
                source: mid.source
            )
            i += 1
        }
    }
}
```

- [ ] **Step 4: Wire optimizer into generate()**

In `WaypointGenerator.generate()`, change the return statement (line 94):

Replace:
```swift
return sortAndCoalesce(waypoints)
```

With:
```swift
var result = sortAndCoalesce(waypoints)
optimizeZoomTransitions(&result)
return result
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/WaypointGeneratorTests 2>&1 | tail -30`
Expected: All tests pass (including existing tests — no regressions).

- [ ] **Step 6: Commit**

```bash
git add Screenize/Generators/ContinuousCamera/WaypointGenerator.swift ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift
git commit -m "feat: add zoom transition optimizer to eliminate unnecessary zoomOut between active intents"
```

---

### Task 5: Full build and integration verification

**Files:** None (verification only)

- [ ] **Step 1: Run full build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | tail -30`
Expected: All tests pass, no regressions.

- [ ] **Step 3: Run lint**

Run: `./scripts/lint.sh`
Expected: No new violations (existing violations are acceptable).
