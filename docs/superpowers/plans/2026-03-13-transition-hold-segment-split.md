# Transition/Hold Segment Split Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split camera segments into transition (moving) + hold (stationary) segments so the camera arrives at the target before the cursor leaves the viewport.

**Architecture:** `SegmentPlanner.buildSegments()` compares each segment's target with `previousEnd`. If distance/zoom difference exceeds thresholds, it creates a short transition segment (duration based on cursor travel time from mouse data) followed by a hold segment. `SegmentSpringSimulator` is unchanged — short transition segments naturally produce fast spring movement.

**Tech Stack:** Swift, XCTest, CoreGraphics

**Spec:** `docs/superpowers/specs/2026-03-13-transition-hold-segment-split-design.md`

---

## Chunk 1: cursorTravelTime + buildSegments split logic

### Task 1: Add `cursorTravelTime` to SegmentPlanner

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift`
- Modify: `ScreenizeTests/Generators/SegmentCamera/SegmentCameraGeneratorTests.swift` (reuse for planner tests)

- [ ] **Step 1: Write tests for cursorTravelTime**

Add a new test class `SegmentPlannerTests` in a new file. Tests cover: cursor arrives quickly, cursor arrives slowly, cursor never arrives (fallback), short search window, no positions in range.

```swift
import XCTest
import CoreGraphics
@testable import Screenize

final class SegmentPlannerTests: XCTestCase {

    // MARK: - cursorTravelTime

    func test_cursorTravelTime_cursorArrivesQuickly_returnsActualTime() {
        // Cursor moves from (0.2, 0.5) to (0.6, 0.5) in 0.2s
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
            mouseData: mouseData,
            searchStart: 1.0,
            searchEnd: 3.0
        )

        // Cursor arrives within arrivalRadius (0.08) of target at t=1.2 (0.58 is within 0.08 of 0.6)
        // Travel time = 1.2 - 1.0 = 0.2s, but clamped to min 0.15s
        XCTAssertGreaterThanOrEqual(time, 0.15, "Should be at least minTransitionDuration")
        XCTAssertLessThanOrEqual(time, 0.8, "Should be at most maxTransitionDuration")
        XCTAssertLessThan(time, 0.5, "Quick cursor arrival should produce short travel time")
    }

    func test_cursorTravelTime_cursorArrivesSlowly_returnsLongerTime() {
        // Cursor takes 0.6s to arrive
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
            mouseData: mouseData,
            searchStart: 0.0,
            searchEnd: 2.0
        )

        // Cursor within 0.08 of 0.6 at t=0.6 (position 0.53, distance = 0.07 < 0.08)
        XCTAssertGreaterThanOrEqual(time, 0.5, "Slow arrival should produce longer time")
        XCTAssertLessThanOrEqual(time, 0.8, "Should be clamped to max")
    }

    func test_cursorTravelTime_cursorNeverArrives_usesFallback() {
        // Cursor stays far from target
        let positions = [
            MousePositionData(time: 1.0, position: NormalizedPoint(x: 0.1, y: 0.5)),
            MousePositionData(time: 1.5, position: NormalizedPoint(x: 0.15, y: 0.5)),
            MousePositionData(time: 2.0, position: NormalizedPoint(x: 0.2, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)

        let time = SegmentPlanner.cursorTravelTime(
            from: NormalizedPoint(x: 0.1, y: 0.5),
            to: NormalizedPoint(x: 0.9, y: 0.5),
            mouseData: mouseData,
            searchStart: 1.0,
            searchEnd: 3.0
        )

        // Distance = 0.8, fallback = 0.8 * 1.0 = 0.8s (clamped to max 0.8)
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
            mouseData: mouseData,
            searchStart: 0.0,
            searchEnd: 2.0
        )

        // Distance = 0.3, fallback = 0.3 * 1.0 = 0.3s
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
            mouseData: mouseData,
            searchStart: 0.0,
            searchEnd: 1.0
        )

        XCTAssertEqual(time, 0.15, accuracy: 0.01, "Very short distance should clamp to minTransitionDuration")
    }

    func test_cursorTravelTime_shortSearchWindow_clampsCorrectly() {
        // Search window is only 0.05s — no positions fall within it
        let positions = [
            MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.2, y: 0.5)),
            MousePositionData(time: 0.1, position: NormalizedPoint(x: 0.8, y: 0.5)),
        ]
        let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)

        let time = SegmentPlanner.cursorTravelTime(
            from: NormalizedPoint(x: 0.2, y: 0.5),
            to: NormalizedPoint(x: 0.8, y: 0.5),
            mouseData: mouseData,
            searchStart: 0.03,
            searchEnd: 0.05
        )

        // No positions in [0.03, 0.05] → fallback. Distance 0.6, fallback = 0.6s
        XCTAssertGreaterThanOrEqual(time, 0.15)
        XCTAssertLessThanOrEqual(time, 0.8)
    }
}
```

- [ ] **Step 2: Create test file and add to Xcode project**

Create `ScreenizeTests/Generators/SegmentCamera/SegmentPlannerTests.swift`. Add to `project.pbxproj` under `ScreenizeTests` target in the existing `SegmentCamera` group. Use a new unique hex prefix (not in: 1A, 2A, 98, A1, A7, A8, AA-AF, B0-B3, B5-B7, C0-C9, CA-CC, D1-D4, D8, E0-E3, E5-E7, F0-F4, F7, FD, FE).

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentPlannerTests 2>&1 | tail -20`
Expected: Compilation error — `cursorTravelTime` doesn't exist.

- [ ] **Step 4: Implement cursorTravelTime**

Add to `SegmentPlanner.swift` (inside the struct, after `focusCenter`):

```swift
// MARK: - Cursor Travel Time

private static let splitDistanceThreshold: CGFloat = 0.05
private static let splitZoomThreshold: CGFloat = 0.1
static let arrivalRadius: CGFloat = 0.08
private static let minTransitionDuration: TimeInterval = 0.15
private static let maxTransitionDuration: TimeInterval = 0.8
private static let minHoldDuration: TimeInterval = 0.1
private static let fallbackSpeedFactor: TimeInterval = 1.0

/// Compute how long the cursor takes to arrive near the target position.
///
/// Scans mouse positions from `searchStart` forward, looking for when the cursor
/// enters `arrivalRadius` of `targetPosition`. Falls back to distance-based
/// estimate if cursor never arrives.
static func cursorTravelTime(
    from startPosition: NormalizedPoint,
    to targetPosition: NormalizedPoint,
    mouseData: MouseDataSource,
    searchStart: TimeInterval,
    searchEnd: TimeInterval
) -> TimeInterval {
    let positions = mouseData.positions.filter {
        $0.time >= searchStart && $0.time <= searchEnd
    }

    // Scan for arrival within radius
    for pos in positions {
        let dx = pos.position.x - targetPosition.x
        let dy = pos.position.y - targetPosition.y
        let dist = sqrt(dx * dx + dy * dy)
        if dist <= arrivalRadius {
            let elapsed = pos.time - searchStart
            return min(max(elapsed, minTransitionDuration), maxTransitionDuration)
        }
    }

    // Fallback: distance-based estimate
    let dx = targetPosition.x - startPosition.x
    let dy = targetPosition.y - startPosition.y
    let distance = sqrt(dx * dx + dy * dy)
    let fallback = Double(distance) * fallbackSpeedFactor
    return min(max(fallback, minTransitionDuration), maxTransitionDuration)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentPlannerTests 2>&1 | tail -20`
Expected: All 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentPlanner.swift ScreenizeTests/Generators/SegmentCamera/SegmentPlannerTests.swift Screenize.xcodeproj/project.pbxproj
git commit -m "feat: add cursorTravelTime to SegmentPlanner"
```

---

### Task 2: Implement segment split logic in buildSegments

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift:14-21,140-173`
- Modify: `ScreenizeTests/Generators/SegmentCamera/SegmentPlannerTests.swift`

- [ ] **Step 1: Write tests for segment split behavior**

Add to `SegmentPlannerTests.swift`:

```swift
// MARK: - buildSegments split logic (via plan())

func test_plan_farTarget_createsTwoSegments() {
    // Two intent spans: first at (0.5, 0.5), second far away at (0.9, 0.5)
    // Second should produce transition + hold = 2 segments
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

    // First span: hold only (first segment, no previousEnd)
    // Second span: transition + hold (far target)
    XCTAssertGreaterThanOrEqual(segments.count, 3, "Should have at least 3 segments: hold + transition + hold")

    // Last segment should be a hold (start == end)
    if let lastSegment = segments.last {
        if case .manual(let start, let end, _) = lastSegment.kind {
            XCTAssertEqual(start.center.x, end.center.x, accuracy: 0.01, "Hold segment should have same start/end center")
            XCTAssertEqual(start.zoom, end.zoom, accuracy: 0.01, "Hold segment should have same start/end zoom")
        }
    }
}

func test_plan_nearTarget_createsSingleSegment() {
    // Two intent spans at nearly the same position
    let spans = [
        makeIntentSpan(start: 0, end: 2, intent: .clicking, focus: NormalizedPoint(x: 0.5, y: 0.5)),
        makeIntentSpan(start: 2, end: 5, intent: .clicking, focus: NormalizedPoint(x: 0.52, y: 0.5)),
    ]
    let positions = [
        MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
        MousePositionData(time: 2.0, position: NormalizedPoint(x: 0.52, y: 0.5)),
    ]
    let mouseData = MockMouseDataSource(duration: 5.0, positions: positions)

    let segments = planWithMouseData(spans: spans, mouseData: mouseData)

    // Both near: hold only for each = 2 segments
    XCTAssertEqual(segments.count, 2, "Near targets should produce hold-only segments")
}

func test_plan_shortSpanWithFarTarget_transitionOnly() {
    // Intent span is 0.2s, far target — hold would be < minHoldDuration
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

    // Second span: transition only (hold too short), so 2 total segments
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
    if case .manual(let start, let end, _) = segments[0].kind {
        XCTAssertEqual(start.center.x, end.center.x, accuracy: 0.01)
    }
}

func test_plan_zoomDifference_triggersSplit() {
    // Same position but different zoom levels (clicking vs idle-inherited)
    let spans = [
        makeIntentSpan(start: 0, end: 2, intent: .clicking, focus: NormalizedPoint(x: 0.5, y: 0.5)),
        makeIntentSpan(start: 2, end: 5, intent: .idle, focus: NormalizedPoint(x: 0.5, y: 0.5)),
        makeIntentSpan(start: 5, end: 8, intent: .clicking, focus: NormalizedPoint(x: 0.5, y: 0.5)),
    ]
    let positions = [
        MousePositionData(time: 0.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
        MousePositionData(time: 5.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
        MousePositionData(time: 5.1, position: NormalizedPoint(x: 0.5, y: 0.5)),
    ]
    let mouseData = MockMouseDataSource(duration: 10.0, positions: positions)

    let segments = planWithMouseData(spans: spans, mouseData: mouseData)

    // idle→clicking typically has zoom difference (idle ~1.0, clicking ~1.8, diff > 0.1)
    // Verify that at least one segment is a hold (start == end) indicating a split occurred
    let holdSegments = segments.filter {
        if case .manual(let s, let e, _) = $0.kind {
            return abs(s.center.x - e.center.x) < 0.001 && abs(s.zoom - e.zoom) < 0.001
        }
        return false
    }
    // Should have hold segments from splits (at least first segment + hold after transition)
    XCTAssertGreaterThanOrEqual(holdSegments.count, 1, "Should have at least one hold segment from zoom difference split")
    XCTAssertGreaterThanOrEqual(segments.count, 3, "Three spans should produce at least 3 segments")
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

/// Helper to call SegmentPlanner.plan() with mouse data.
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentPlannerTests 2>&1 | tail -20`
Expected: Compilation error — `plan()` doesn't accept `mouseData` parameter yet.

- [ ] **Step 3: Implement split logic**

Modify `SegmentPlanner.swift`:

**3a. Add `mouseData` parameter to `plan()`:**

Change line 14-21 from:
```swift
static func plan(
    intentSpans: [IntentSpan],
    screenBounds: CGSize,
    eventTimeline: EventTimeline,
    frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
    settings: ShotSettings,
    zoomIntensity: CGFloat = 1.0
) -> [CameraSegment] {
```
To:
```swift
static func plan(
    intentSpans: [IntentSpan],
    screenBounds: CGSize,
    eventTimeline: EventTimeline,
    frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
    settings: ShotSettings,
    zoomIntensity: CGFloat = 1.0,
    mouseData: MouseDataSource? = nil
) -> [CameraSegment] {
```

**3b. Pass mouseData to buildSegments (line 48):**

Change:
```swift
return buildSegments(from: shotPlans, zoomIntensity: zoomIntensity)
```
To:
```swift
return buildSegments(from: shotPlans, zoomIntensity: zoomIntensity, mouseData: mouseData)
```

**3c. Rewrite `buildSegments` (lines 140-173):**

```swift
/// Convert shot plans to chained CameraSegments.
/// When mouseData is provided, splits segments into transition + hold
/// when the camera needs to move a significant distance.
private static func buildSegments(
    from plans: [ShotPlan],
    zoomIntensity: CGFloat,
    mouseData: MouseDataSource? = nil
) -> [CameraSegment] {
    guard !plans.isEmpty else { return [] }

    var segments: [CameraSegment] = []
    var previousEnd: TransformValue?

    for plan in plans {
        let rawZoom = plan.idealZoom
        let zoom = max(1.0, 1.0 + (rawZoom - 1.0) * zoomIntensity)
        let center = ShotPlanner.clampCenter(plan.idealCenter, zoom: zoom)
        let endTransform = TransformValue(zoom: zoom, center: center)

        let startTransform = previousEnd ?? endTransform
        let spanStart = plan.scene.startTime
        let spanEnd = plan.scene.endTime

        let needsSplit: Bool = {
            guard previousEnd != nil, let _ = mouseData else { return false }
            let dx = startTransform.center.x - endTransform.center.x
            let dy = startTransform.center.y - endTransform.center.y
            let distance = sqrt(dx * dx + dy * dy)
            let zoomDiff = abs(startTransform.zoom - endTransform.zoom)
            return distance > splitDistanceThreshold || zoomDiff > splitZoomThreshold
        }()

        if needsSplit, let mouseData = mouseData {
            let travelTime = cursorTravelTime(
                from: startTransform.center,
                to: endTransform.center,
                mouseData: mouseData,
                searchStart: spanStart,
                searchEnd: spanEnd
            )

            let transitionEnd = spanStart + travelTime
            let holdDuration = spanEnd - transitionEnd

            if holdDuration >= minHoldDuration {
                // Transition + hold
                let transition = CameraSegment(
                    startTime: spanStart,
                    endTime: transitionEnd,
                    kind: .manual(
                        startTransform: startTransform,
                        endTransform: endTransform,
                        interpolation: .easeInOut
                    ),
                    transitionToNext: SegmentTransition(duration: 0, easing: .linear)
                )
                let hold = CameraSegment(
                    startTime: transitionEnd,
                    endTime: spanEnd,
                    kind: .manual(
                        startTransform: endTransform,
                        endTransform: endTransform,
                        interpolation: .linear
                    ),
                    transitionToNext: SegmentTransition(duration: 0, easing: .linear)
                )
                segments.append(transition)
                segments.append(hold)
            } else {
                // Transition only (span too short for hold)
                let transition = CameraSegment(
                    startTime: spanStart,
                    endTime: spanEnd,
                    kind: .manual(
                        startTransform: startTransform,
                        endTransform: endTransform,
                        interpolation: .easeInOut
                    ),
                    transitionToNext: SegmentTransition(duration: 0, easing: .linear)
                )
                segments.append(transition)
            }
        } else {
            // Hold only (no movement needed or no mouse data)
            let segment = CameraSegment(
                startTime: spanStart,
                endTime: spanEnd,
                kind: .manual(
                    startTransform: startTransform,
                    endTransform: endTransform,
                    interpolation: .easeInOut
                ),
                transitionToNext: SegmentTransition(duration: 0, easing: .linear)
            )
            segments.append(segment)
        }

        previousEnd = endTransform
    }

    return segments
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentPlannerTests 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentPlanner.swift ScreenizeTests/Generators/SegmentCamera/SegmentPlannerTests.swift
git commit -m "feat: split segments into transition + hold in SegmentPlanner"
```

---

### Task 3: Wire mouseData into SegmentCameraGenerator pipeline

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift:49-56`

- [ ] **Step 1: Pass effectiveMouseData to plan()**

In `SegmentCameraGenerator.swift`, change the `plan()` call (lines 49-56):

From:
```swift
let rawSegments = SegmentPlanner.plan(
    intentSpans: intentSpans,
    screenBounds: screenBounds,
    eventTimeline: timeline,
    frameAnalysis: frameAnalysis,
    settings: settings.shot,
    zoomIntensity: settings.zoomIntensity
)
```

To:
```swift
let rawSegments = SegmentPlanner.plan(
    intentSpans: intentSpans,
    screenBounds: screenBounds,
    eventTimeline: timeline,
    frameAnalysis: frameAnalysis,
    settings: settings.shot,
    zoomIntensity: settings.zoomIntensity,
    mouseData: effectiveMouseData
)
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all segment tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentPlannerTests -only-testing:ScreenizeTests/SegmentCameraGeneratorTests -only-testing:ScreenizeTests/SegmentSpringSimulatorTests 2>&1 | tail -20`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift
git commit -m "feat: wire mouseData into segment planning pipeline"
```

---

### Task 4: Full build and integration verification

- [ ] **Step 1: Run full build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run all tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | tail -30`
Expected: All tests pass (except known pre-existing failures in IntentClassifierTests, EventStreamAdapterTests, WaypointGeneratorTests).

- [ ] **Step 3: Run lint**

Run: `./scripts/lint.sh`
Expected: No new serious violations.
