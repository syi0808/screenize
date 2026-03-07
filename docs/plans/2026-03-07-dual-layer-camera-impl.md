# Dual-Layer Camera Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve camera quality to Screen Studio level by implementing a dual-layer camera (Macro framing + Micro tracking).

**Architecture:** Separate camera into slow Macro layer (framing/zoom) and fast Micro layer (cursor tracking). Macro uses existing intent pipeline with improved spring params. Micro adds dead-zone-based offset tracking. Cursor rendering switches to camera-space smoothing.

**Tech Stack:** Swift, CoreGraphics, XCTest. All changes in `Generators/ContinuousCamera/` and `Render/`.

**Design doc:** `docs/plans/2026-03-07-dual-layer-camera-design.md`

---

## Phase 1: Macro Layer Improvements

### Task 1: Update Spring Parameters in ContinuousCameraSettings

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift:46-84`
- Test: `ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift`

**Step 1: Update the test for new default values**

In `WaypointGeneratorTests.swift`, update `test_settings_defaultValues` (line 482):

```swift
func test_settings_defaultValues() {
    let settings = ContinuousCameraSettings()
    XCTAssertEqual(settings.positionDampingRatio, 1.0, accuracy: 0.001)
    XCTAssertEqual(settings.positionResponse, 0.8, accuracy: 0.001)
    XCTAssertEqual(settings.zoomDampingRatio, 1.0, accuracy: 0.001)
    XCTAssertEqual(settings.zoomResponse, 0.8, accuracy: 0.001)
    XCTAssertEqual(settings.tickRate, 60.0, accuracy: 0.001)
    XCTAssertEqual(settings.minZoom, 1.0, accuracy: 0.001)
    XCTAssertEqual(settings.maxZoom, 2.8, accuracy: 0.001)
    XCTAssertEqual(settings.zoomIntensity, 1.0, accuracy: 0.001)
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/WaypointGeneratorTests/test_settings_defaultValues 2>&1 | tail -5`
Expected: FAIL (old values 0.92/0.4/0.95/0.5 don't match new 1.0/0.8/1.0/0.8)

**Step 3: Update default parameters**

In `ContinuousCameraTypes.swift`, update `ContinuousCameraSettings` (lines 48-54):

```swift
struct ContinuousCameraSettings {
    /// Damping ratio for position springs (1.0 = critical, <1 = underdamped).
    var positionDampingRatio: CGFloat = 1.0
    /// Response time in seconds for position springs.
    var positionResponse: CGFloat = 0.8
    /// Damping ratio for zoom spring.
    var zoomDampingRatio: CGFloat = 1.0
    /// Response time in seconds for zoom spring.
    var zoomResponse: CGFloat = 0.8
```

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/WaypointGeneratorTests/test_settings_defaultValues 2>&1 | tail -5`
Expected: PASS

**Step 5: Also fix SpringDamperSimulatorTests that depend on old params**

The `test_simulate_criticallyDamped_noZoomOvershoot` test (line 60) explicitly sets damping to 1.0, so it still passes. But `test_simulate_highUrgency_convergesFasterThanLazy` may need accuracy adjustment since response times changed. Run all SpringDamperSimulator tests:

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SpringDamperSimulatorTests 2>&1 | tail -20`

Fix any failures by adjusting test thresholds if needed (the logic should still hold — high urgency converges faster than lazy regardless of base response time).

**Step 6: Commit**

```
git add -A && git commit -m "feat: unify zoom-pan response times for macro layer"
```

---

### Task 2: Remove Detail Waypoints from WaypointGenerator

Detail waypoints (typing caret tracking, click anchors) will move to the Micro layer in Phase 2. For now, remove them from macro waypoint generation.

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/WaypointGenerator.swift:54-113`
- Test: `ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift`

**Step 1: Update tests — detail waypoint tests should expect NO detail waypoints**

In `WaypointGeneratorTests.swift`, replace `test_generate_typingWithCaretMovement_addsDetailWaypoints` (line 286) and `test_generate_clickingWithMultipleClicks_addsDetailWaypoints` (line 339):

```swift
func test_generate_typingWithCaretMovement_noDetailWaypoints() {
    let spans = [
        makeIntentSpan(
            start: 0,
            end: 4,
            intent: .typing(context: .codeEditor),
            focus: NormalizedPoint(x: 0.3, y: 0.4)
        )
    ]
    let timeline = EventTimeline(
        events: [
            makeTypingEvent(
                time: 0.4,
                position: NormalizedPoint(x: 0.3, y: 0.4),
                caretCenter: NormalizedPoint(x: 0.3, y: 0.4)
            ),
            makeTypingEvent(
                time: 1.4,
                position: NormalizedPoint(x: 0.8, y: 0.8),
                caretCenter: NormalizedPoint(x: 0.8, y: 0.8)
            ),
            makeTypingEvent(
                time: 2.4,
                position: NormalizedPoint(x: 0.82, y: 0.82),
                caretCenter: NormalizedPoint(x: 0.82, y: 0.82)
            )
        ],
        duration: 4.0
    )

    let waypoints = WaypointGenerator.generate(
        from: spans,
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: timeline,
        frameAnalysis: [],
        settings: defaultSettings
    )

    let typingWaypoints = waypoints.filter {
        if case .typing = $0.source { return true }
        return false
    }
    // Only 1 entry waypoint, no detail waypoints
    XCTAssertEqual(typingWaypoints.count, 1,
                   "Macro layer should not emit detail waypoints")
}

func test_generate_clickingWithMultipleClicks_noDetailWaypoints() {
    let spans = [
        makeIntentSpan(
            start: 1.0,
            end: 4.0,
            intent: .clicking,
            focus: NormalizedPoint(x: 0.25, y: 0.25)
        )
    ]
    let timeline = EventTimeline(
        events: [
            makeClickEvent(
                time: 1.2,
                position: NormalizedPoint(x: 0.22, y: 0.25)
            ),
            makeClickEvent(
                time: 2.1,
                position: NormalizedPoint(x: 0.58, y: 0.62)
            ),
            makeClickEvent(
                time: 3.2,
                position: NormalizedPoint(x: 0.78, y: 0.70)
            )
        ],
        duration: 4.0
    )

    let waypoints = WaypointGenerator.generate(
        from: spans,
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: timeline,
        frameAnalysis: [],
        settings: defaultSettings
    )

    let clickWaypoints = waypoints.filter {
        if case .clicking = $0.source { return true }
        return false
    }
    // Only 1 entry waypoint, no detail waypoints
    XCTAssertEqual(clickWaypoints.count, 1,
                   "Macro layer should not emit detail waypoints")
}
```

**Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/WaypointGeneratorTests/test_generate_typingWithCaretMovement_noDetailWaypoints -only-testing:ScreenizeTests/WaypointGeneratorTests/test_generate_clickingWithMultipleClicks_noDetailWaypoints 2>&1 | tail -10`
Expected: FAIL (old code still emits detail waypoints)

**Step 3: Remove detail waypoint emission from WaypointGenerator.generate()**

In `WaypointGenerator.swift`, remove lines 93-110 (the detail waypoint block inside the second pass loop). The loop body becomes:

```swift
// Second pass: emit entry waypoints only (detail tracking moved to Micro layer).
for (index, span) in intentSpans.enumerated() {
    let transform: TransformValue
    if case .idle = span.intent {
        let inherited = resolveIdleZoom(
            at: index,
            spans: intentSpans,
            baseTransforms: baseTransforms,
            settings: settings
        )
        transform = TransformValue(
            zoom: inherited,
            center: computeCenter(for: span, zoom: inherited)
        )
    } else {
        transform = baseTransforms[index]
            ?? preferredTransform(
                for: span,
                screenBounds: screenBounds,
                eventTimeline: eventTimeline,
                frameAnalysis: frameAnalysis,
                settings: settings
            )
    }

    let baseUrgency = urgency(for: span.intent)
    let entryTime = max(
        0,
        span.startTime - entryLeadTime(for: baseUrgency)
    )
    let waypoint = CameraWaypoint(
        time: entryTime,
        targetZoom: transform.zoom,
        targetCenter: transform.center,
        urgency: baseUrgency,
        source: span.intent
    )
    waypoints.append(waypoint)
}
```

The private functions `typingDetailWaypoints`, `activityDetailWaypoints`, `detailAnchorEvents`, `caretBounds`, and `normalizeFrame` can be kept for now (Micro layer may reuse them in Phase 2) or removed. Prefer keeping them to avoid breaking compilation if other code references them.

**Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/WaypointGeneratorTests 2>&1 | tail -20`
Expected: All PASS

**Step 5: Commit**

```
git add -A && git commit -m "feat: remove detail waypoints from macro layer"
```

---

### Task 3: Implement Urgency Blending in SpringDamperSimulator

Instead of instant urgency switches, blend the effective urgency over 0.3s when transitioning between waypoints.

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift`
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`
- Test: `ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift`

**Step 1: Write the failing test**

Add to `SpringDamperSimulatorTests.swift`:

```swift
func test_simulate_urgencyTransition_smoothResponseChange() {
    // Waypoint 1: lazy (slow response), Waypoint 2: high (fast response)
    let wp1 = makeWaypoint(time: 0, zoom: 1.5, x: 0.3, y: 0.5, urgency: .lazy)
    let wp2 = makeWaypoint(time: 2, zoom: 2.0, x: 0.7, y: 0.5, urgency: .high)

    let result = SpringDamperSimulator.simulate(
        waypoints: [wp1, wp2], duration: 4.0, settings: defaultSettings
    )

    // At the transition point (t=2.0), the camera should NOT immediately
    // jump to high-urgency response. Check that velocity change is gradual.
    let samplesAroundTransition = result.filter { $0.time >= 1.9 && $0.time <= 2.3 }
    guard samplesAroundTransition.count >= 3 else {
        XCTFail("Need samples around transition")
        return
    }

    // Compute acceleration (velocity change rate) around transition
    var maxAccelChange: CGFloat = 0
    for i in 2..<samplesAroundTransition.count {
        let dt = samplesAroundTransition[i].time - samplesAroundTransition[i - 1].time
        let dt2 = samplesAroundTransition[i - 1].time - samplesAroundTransition[i - 2].time
        guard dt > 0, dt2 > 0 else { continue }
        let v1 = (samplesAroundTransition[i].transform.center.x
                   - samplesAroundTransition[i - 1].transform.center.x) / CGFloat(dt)
        let v0 = (samplesAroundTransition[i - 1].transform.center.x
                   - samplesAroundTransition[i - 2].transform.center.x) / CGFloat(dt2)
        maxAccelChange = max(maxAccelChange, abs(v1 - v0))
    }

    // With urgency blending, acceleration change should be bounded
    // (no sudden jerk from instant urgency switch)
    XCTAssertLessThan(maxAccelChange, 5.0,
                      "Urgency transition should be gradual, not instant")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SpringDamperSimulatorTests/test_simulate_urgencyTransition_smoothResponseChange 2>&1 | tail -5`

**Step 3: Add urgency blend duration to settings**

In `ContinuousCameraTypes.swift`, add to `ContinuousCameraSettings`:

```swift
/// Duration in seconds over which urgency transitions are blended.
var urgencyBlendDuration: TimeInterval = 0.3
```

**Step 4: Implement urgency blending in SpringDamperSimulator**

In `SpringDamperSimulator.swift`, modify the `simulate` method. Add state tracking for urgency blending after `var waypointIndex = 0` (line 50):

```swift
var prevUrgency: WaypointUrgency = waypoints[0].urgency
var urgencyTransitionStart: TimeInterval = 0
```

After the waypoint advancement block (after line 62), add urgency blending before computing spring parameters:

```swift
// Blend urgency over transition duration
let activeUrgency = activeWP.urgency
if activeUrgency != prevUrgency {
    // Start a new urgency transition if waypoint just changed
    if waypointIndex > 0 && abs(activeWP.time - t) < dt * 1.5 {
        urgencyTransitionStart = t
        prevUrgency = activeUrgency
    }
}
```

Replace the urgency multiplier computation (line 87) with blended version:

```swift
let blendDuration = settings.urgencyBlendDuration
let blendProgress: CGFloat
if blendDuration > 0.001 && t - urgencyTransitionStart < blendDuration {
    blendProgress = CGFloat((t - urgencyTransitionStart) / blendDuration)
} else {
    blendProgress = 1.0
}

let currentMult = settings.urgencyMultipliers[lookAheadTarget.urgency] ?? 1.0
let prevMult = settings.urgencyMultipliers[prevUrgency] ?? 1.0
let effectiveMult = prevMult + (currentMult - prevMult) * blendProgress
```

Then use `effectiveMult` instead of `urgencyMult`:

```swift
let posOmega = 2.0 * .pi / max(0.001, settings.positionResponse * effectiveMult)
let zoomOmega = 2.0 * .pi / max(0.001, settings.zoomResponse * effectiveMult)
```

**Important:** Track `prevUrgency` correctly — update it when a new waypoint activates, not every frame. The implementation needs careful placement within the waypoint advancement loop. When `waypointIndex` changes, record the old urgency and transition start time.

Refactored waypoint advancement with urgency tracking:

```swift
var activatedImmediate = false
let previousWaypointIndex = waypointIndex
while waypointIndex + 1 < waypoints.count
        && waypoints[waypointIndex + 1].time <= t + activationTolerance {
    waypointIndex += 1
    activatedImmediate = activatedImmediate
        || waypoints[waypointIndex].urgency == .immediate
}

// Track urgency transitions
if waypointIndex != previousWaypointIndex {
    prevUrgency = waypoints[previousWaypointIndex].urgency
    urgencyTransitionStart = t
}
```

**Step 5: Run test to verify it passes**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SpringDamperSimulatorTests 2>&1 | tail -20`
Expected: All PASS

**Step 6: Commit**

```
git add -A && git commit -m "feat: implement urgency blending for smooth transitions"
```

---

### Task 4: Implement Soft Clamping in SpringDamperSimulator

Replace hard velocity reset at boundaries with pushback force.

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift:180-207`
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`
- Test: `ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift`

**Step 1: Write the failing test**

Add to `SpringDamperSimulatorTests.swift`:

```swift
func test_simulate_nearBoundary_velocityNotZeroed() {
    // Camera moving toward edge should decelerate gradually, not stop instantly
    let wp1 = makeWaypoint(time: 0, zoom: 2.0, x: 0.5, y: 0.5, urgency: .normal)
    let wp2 = makeWaypoint(time: 1, zoom: 2.0, x: 0.95, y: 0.5, urgency: .normal)

    let result = SpringDamperSimulator.simulate(
        waypoints: [wp1, wp2], duration: 3.0, settings: defaultSettings
    )

    // Find samples near the right boundary (at zoom 2.0, max center.x = 0.75)
    let nearBoundary = result.filter {
        $0.transform.center.x > 0.70 && $0.time > 1.0
    }
    guard nearBoundary.count >= 3 else { return }

    // Check velocity continuity near boundary — no instant zeroing
    var hadSuddenStop = false
    for i in 1..<nearBoundary.count {
        let dt = nearBoundary[i].time - nearBoundary[i - 1].time
        guard dt > 0 else { continue }
        let v = (nearBoundary[i].transform.center.x
                  - nearBoundary[i - 1].transform.center.x) / CGFloat(dt)
        let vPrev: CGFloat
        if i >= 2 {
            let dt2 = nearBoundary[i - 1].time - nearBoundary[i - 2].time
            guard dt2 > 0 else { continue }
            vPrev = (nearBoundary[i - 1].transform.center.x
                      - nearBoundary[i - 2].transform.center.x) / CGFloat(dt2)
        } else {
            continue
        }
        // If velocity drops by >90% in one frame, that's a sudden stop
        if abs(vPrev) > 0.1 && abs(v) / abs(vPrev) < 0.1 {
            hadSuddenStop = true
        }
    }
    XCTAssertFalse(hadSuddenStop,
                   "Velocity near boundary should decelerate gradually")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SpringDamperSimulatorTests/test_simulate_nearBoundary_velocityNotZeroed 2>&1 | tail -5`

**Step 3: Add boundary stiffness to settings**

In `ContinuousCameraTypes.swift`, add to `ContinuousCameraSettings`:

```swift
/// Stiffness of the soft boundary pushback force. Higher = harder boundary.
var boundaryStiffness: CGFloat = 80.0
```

**Step 4: Replace hard clamping with soft clamping**

In `SpringDamperSimulator.swift`, replace `clampState` (lines 181-207):

```swift
/// Apply soft boundary forces instead of hard clamping.
/// Position is gently pushed back when exceeding valid bounds.
/// Zoom is still hard-clamped (zoom boundaries should feel firm).
private static func clampState(
    _ state: inout CameraState,
    settings: ContinuousCameraSettings,
    dt: CGFloat
) {
    // Hard clamp zoom (zoom boundaries should feel firm)
    if state.zoom < settings.minZoom {
        state.zoom = settings.minZoom
        state.velocityZoom = max(0, state.velocityZoom)
    } else if state.zoom > settings.maxZoom {
        state.zoom = settings.maxZoom
        state.velocityZoom = min(0, state.velocityZoom)
    }

    // Soft clamp center — apply pushback force proportional to overflow
    let clamped = ShotPlanner.clampCenter(
        NormalizedPoint(x: state.positionX, y: state.positionY),
        zoom: state.zoom
    )
    let overflowX = state.positionX - clamped.x
    let overflowY = state.positionY - clamped.y
    let stiffness = settings.boundaryStiffness

    if abs(overflowX) > 0.0001 {
        state.velocityX -= overflowX * stiffness * dt
        // Ensure position doesn't diverge too far
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
```

**Step 5: Update all clampState call sites to pass dt**

In `simulate()`, update:
- Line 35: `clampState(&state, settings: settings, dt: CGFloat(dt))`
- Line 74: `clampState(&state, settings: settings, dt: CGFloat(dt))`
- Line 119: `clampState(&state, settings: settings, dt: CGFloat(dt))`

**Step 6: Update existing boundary tests**

The `test_simulate_centerClampedToViewportBounds` test (line 249) checks that center stays within bounds. With soft clamping, there may be slight overshoot. Update tolerance:

```swift
func test_simulate_centerClampedToViewportBounds() {
    let wp = makeWaypoint(time: 0, zoom: 2.5, x: 0.95, y: 0.95, urgency: .normal)
    let result = SpringDamperSimulator.simulate(
        waypoints: [wp], duration: 2.0, settings: defaultSettings
    )
    for sample in result {
        let halfCrop = 0.5 / sample.transform.zoom
        // Allow slight overshoot from soft clamping (max 0.05)
        XCTAssertGreaterThanOrEqual(sample.transform.center.x, halfCrop - 0.06)
        XCTAssertLessThanOrEqual(sample.transform.center.x, 1.0 - halfCrop + 0.06)
        XCTAssertGreaterThanOrEqual(sample.transform.center.y, halfCrop - 0.06)
        XCTAssertLessThanOrEqual(sample.transform.center.y, 1.0 - halfCrop + 0.06)
    }
}
```

**Step 7: Run all tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SpringDamperSimulatorTests 2>&1 | tail -20`
Expected: All PASS

**Step 8: Commit**

```
git add -A && git commit -m "feat: implement soft clamping at boundaries"
```

---

### Task 5: Build verification for Phase 1

**Step 1: Run full test suite**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | tail -30`
Expected: All tests PASS

**Step 2: Run lint**

Run: `./scripts/lint.sh`
Expected: No new violations

**Step 3: Commit and tag Phase 1 complete**

```
git add -A && git commit -m "chore: Phase 1 complete — macro layer improvements"
```

---

## Phase 2: Micro Layer Addition

### Task 6: Create MicroTracker with Dead Zone

**Files:**
- Create: `Screenize/Generators/ContinuousCamera/MicroTracker.swift`
- Create: `ScreenizeTests/Generators/ContinuousCamera/MicroTrackerTests.swift`
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift` (add settings)

**Step 1: Add MicroTrackerSettings to ContinuousCameraTypes.swift**

```swift
/// Configuration for the micro tracking layer.
struct MicroTrackerSettings {
    /// Dead zone as fraction of viewport half-size. Micro offset inactive within this zone.
    var deadZoneRatio: CGFloat = 0.4
    /// Maximum micro offset as fraction of viewport half-size.
    var maxOffsetRatio: CGFloat = 0.3
    /// Spring damping ratio for micro offset.
    var dampingRatio: CGFloat = 0.85
    /// Spring response time in seconds.
    var response: CGFloat = 0.15
}
```

Add to `ContinuousCameraSettings`:

```swift
/// Micro tracking layer settings.
var micro = MicroTrackerSettings()
```

**Step 2: Write failing tests for MicroTracker**

Create `ScreenizeTests/Generators/ContinuousCamera/MicroTrackerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import Screenize

final class MicroTrackerTests: XCTestCase {

    private let defaultSettings = MicroTrackerSettings()

    // MARK: - Dead Zone

    func test_cursorInDeadZone_offsetIsZero() {
        var tracker = MicroTracker(settings: defaultSettings)
        let macroCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let zoom: CGFloat = 2.0
        // Cursor at macro center — well within dead zone
        let cursor = NormalizedPoint(x: 0.5, y: 0.5)

        tracker.update(cursorPosition: cursor, macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60)
        // Run several frames to let spring settle
        for _ in 0..<60 {
            tracker.update(cursorPosition: cursor, macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60)
        }

        XCTAssertEqual(tracker.offset.x, 0, accuracy: 0.001)
        XCTAssertEqual(tracker.offset.y, 0, accuracy: 0.001)
    }

    func test_cursorOutsideDeadZone_offsetMovesTowardCursor() {
        var tracker = MicroTracker(settings: defaultSettings)
        let macroCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let zoom: CGFloat = 2.0
        // At zoom 2.0, viewportHalf = 0.25, deadZone = 0.25 * 0.4 = 0.10
        // Cursor at 0.7 is 0.2 away from center, exceeding deadZone
        let cursor = NormalizedPoint(x: 0.7, y: 0.5)

        for _ in 0..<120 {
            tracker.update(cursorPosition: cursor, macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60)
        }

        XCTAssertGreaterThan(tracker.offset.x, 0.05,
                             "Offset should move toward cursor when outside dead zone")
    }

    // MARK: - Offset Limit

    func test_offset_clampedToMaxRatio() {
        var tracker = MicroTracker(settings: defaultSettings)
        let macroCenter = NormalizedPoint(x: 0.3, y: 0.5)
        let zoom: CGFloat = 2.0
        // Cursor very far from macro center
        let cursor = NormalizedPoint(x: 0.9, y: 0.5)
        let viewportHalf = 0.5 / zoom
        let maxOffset = viewportHalf * defaultSettings.maxOffsetRatio

        for _ in 0..<300 {
            tracker.update(cursorPosition: cursor, macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60)
        }

        XCTAssertLessThanOrEqual(abs(tracker.offset.x), maxOffset + 0.01,
                                 "Offset should be clamped to max ratio")
    }

    // MARK: - Macro Transition Compensation

    func test_macroTransition_compensatesOffset() {
        var tracker = MicroTracker(settings: defaultSettings)
        let zoom: CGFloat = 2.0
        let cursor = NormalizedPoint(x: 0.7, y: 0.5)

        // Build up offset toward cursor
        for _ in 0..<120 {
            tracker.update(
                cursorPosition: cursor,
                macroCenter: NormalizedPoint(x: 0.5, y: 0.5),
                zoom: zoom,
                dt: 1.0 / 60
            )
        }
        let offsetBefore = tracker.offset
        let effectiveCenterBefore = NormalizedPoint(
            x: 0.5 + offsetBefore.x,
            y: 0.5 + offsetBefore.y
        )

        // Macro center shifts — compensate to keep effective center stable
        let newMacroCenter = NormalizedPoint(x: 0.6, y: 0.5)
        tracker.compensateForMacroTransition(
            oldCenter: NormalizedPoint(x: 0.5, y: 0.5),
            newCenter: newMacroCenter
        )
        let effectiveCenterAfter = NormalizedPoint(
            x: newMacroCenter.x + tracker.offset.x,
            y: newMacroCenter.y + tracker.offset.y
        )

        XCTAssertEqual(effectiveCenterBefore.x, effectiveCenterAfter.x, accuracy: 0.001,
                       "Effective center should not jump after macro transition")
    }

    // MARK: - Idle Returns to Zero

    func test_idle_offsetReturnsToZero() {
        var tracker = MicroTracker(settings: defaultSettings)
        let macroCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let zoom: CGFloat = 2.0

        // Build up offset
        for _ in 0..<60 {
            tracker.update(
                cursorPosition: NormalizedPoint(x: 0.7, y: 0.5),
                macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60
            )
        }
        XCTAssertGreaterThan(abs(tracker.offset.x), 0.01)

        // Now set idle (cursor at center)
        for _ in 0..<300 {
            tracker.update(
                cursorPosition: macroCenter,
                macroCenter: macroCenter, zoom: zoom, dt: 1.0 / 60,
                isIdle: true
            )
        }

        XCTAssertEqual(tracker.offset.x, 0, accuracy: 0.005,
                       "Offset should return to zero during idle")
    }
}
```

**Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/MicroTrackerTests 2>&1 | tail -5`
Expected: FAIL (MicroTracker doesn't exist yet)

**Step 4: Implement MicroTracker**

Create `Screenize/Generators/ContinuousCamera/MicroTracker.swift`:

```swift
import Foundation
import CoreGraphics

/// Micro tracking layer for the dual-layer camera system.
///
/// Tracks cursor/caret within the macro frame by computing a small offset.
/// Uses a dead zone to avoid reacting to small movements near frame center.
/// The offset is spring-animated for smooth following.
struct MicroTracker {

    private let settings: MicroTrackerSettings
    private(set) var offset: (x: CGFloat, y: CGFloat) = (0, 0)
    private var velocityX: CGFloat = 0
    private var velocityY: CGFloat = 0

    init(settings: MicroTrackerSettings) {
        self.settings = settings
    }

    /// Update micro offset based on cursor position relative to macro center.
    mutating func update(
        cursorPosition: NormalizedPoint,
        macroCenter: NormalizedPoint,
        zoom: CGFloat,
        dt: CGFloat,
        isIdle: Bool = false
    ) {
        let viewportHalf = 0.5 / max(zoom, 1.0)
        let deadZone = viewportHalf * settings.deadZoneRatio
        let maxOffset = viewportHalf * settings.maxOffsetRatio

        let targetOffset: (x: CGFloat, y: CGFloat)

        if isIdle {
            targetOffset = (0, 0)
        } else {
            let relX = cursorPosition.x - macroCenter.x
            let relY = cursorPosition.y - macroCenter.y

            let excessX = abs(relX) - deadZone
            let excessY = abs(relY) - deadZone

            var tx: CGFloat = 0
            var ty: CGFloat = 0
            if excessX > 0 { tx = copysign(excessX, relX) }
            if excessY > 0 { ty = copysign(excessY, relY) }

            // Clamp to max offset
            tx = max(-maxOffset, min(maxOffset, tx))
            ty = max(-maxOffset, min(maxOffset, ty))

            targetOffset = (tx, ty)
        }

        // Spring step for each axis
        let omega = 2.0 * .pi / max(0.001, settings.response)
        let zeta = settings.dampingRatio

        let (newX, newVX) = SpringDamperSimulator.springStep(
            current: offset.x, velocity: velocityX,
            target: targetOffset.x,
            omega: omega, zeta: zeta, dt: dt
        )
        let (newY, newVY) = SpringDamperSimulator.springStep(
            current: offset.y, velocity: velocityY,
            target: targetOffset.y,
            omega: omega, zeta: zeta, dt: dt
        )

        offset = (
            max(-maxOffset, min(maxOffset, newX)),
            max(-maxOffset, min(maxOffset, newY))
        )
        velocityX = newVX
        velocityY = newVY
    }

    /// Compensate micro offset when macro center changes to avoid visual jump.
    mutating func compensateForMacroTransition(
        oldCenter: NormalizedPoint,
        newCenter: NormalizedPoint
    ) {
        offset.x -= (newCenter.x - oldCenter.x)
        offset.y -= (newCenter.y - oldCenter.y)
    }
}
```

**Step 5: Add files to Xcode project**

Add `MicroTracker.swift` and `MicroTrackerTests.swift` to `Screenize.xcodeproj/project.pbxproj`. Follow the memory note on Xcode project file management — pick unique hex ID prefixes not already used (check existing prefixes first).

**Step 6: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/MicroTrackerTests 2>&1 | tail -20`
Expected: All PASS

**Step 7: Commit**

```
git add -A && git commit -m "feat: add MicroTracker with dead zone and offset spring"
```

---

### Task 7: Integrate MicroTracker into ContinuousCameraGenerator

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraGenerator.swift`
- Modify: `Screenize/Generators/ContinuousCamera/WaypointGenerator.swift` (expose detail waypoint data for micro)
- Test: `ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift`

**Step 1: Write the failing test**

Add to `ContinuousCameraGeneratorTests.swift`:

```swift
func test_generate_clickSequence_cameraFollowsClicks() {
    // Multiple clicks at different positions — camera should track them
    let mouseData = makeClickingMouseData(clicks: [
        (time: 0.5, x: 0.3, y: 0.5),
        (time: 2.0, x: 0.7, y: 0.5),
        (time: 3.5, x: 0.3, y: 0.5)
    ])
    let result = ContinuousCameraGenerator().generate(
        from: mouseData,
        uiStateSamples: [],
        frameAnalysis: [],
        screenBounds: CGSize(width: 1920, height: 1080),
        settings: ContinuousCameraSettings()
    )
    guard let transforms = result.continuousTransforms, !transforms.isEmpty else {
        XCTFail("Expected continuous transforms")
        return
    }

    // At t=2.5 (after second click at x=0.7), camera center should be pulled right
    let atSecondClick = transforms.first { $0.time >= 2.5 }
    XCTAssertNotNil(atSecondClick)
    if let sample = atSecondClick {
        XCTAssertGreaterThan(sample.transform.center.x, 0.45,
                             "Camera should follow click position via micro tracking")
    }
}
```

**Step 2: Run test to verify current behavior**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ContinuousCameraGeneratorTests/test_generate_clickSequence_cameraFollowsClicks 2>&1 | tail -5`

**Step 3: Integrate MicroTracker into the pipeline**

In `ContinuousCameraGenerator.swift`, modify `generate()`. After Step 5 (simulate continuous camera path), add micro layer processing:

```swift
// Step 5b: Apply micro tracking layer
let microSamples = Self.applyMicroTracking(
    macroSamples: rawSamples,
    mouseData: effectiveMouseData,
    intentSpans: intentSpans,
    settings: settings
)
```

Then use `microSamples` instead of `rawSamples` for Step 6.

Implement the static method:

```swift
/// Apply micro tracking offset to macro camera samples.
private static func applyMicroTracking(
    macroSamples: [TimedTransform],
    mouseData: MouseDataSource,
    intentSpans: [IntentSpan],
    settings: ContinuousCameraSettings
) -> [TimedTransform] {
    guard !macroSamples.isEmpty else { return macroSamples }

    var tracker = MicroTracker(settings: settings.micro)
    let dt: CGFloat = 1.0 / CGFloat(settings.tickRate)

    return macroSamples.map { sample in
        let cursorPos = mouseData.interpolatedPosition(at: sample.time)
        let macroCenter = sample.transform.center
        let zoom = sample.transform.zoom

        // Determine if current time is in an idle span
        let isIdle = intentSpans.contains {
            $0.intent == .idle && sample.time >= $0.startTime && sample.time <= $0.endTime
        }

        tracker.update(
            cursorPosition: cursorPos,
            macroCenter: macroCenter,
            zoom: zoom,
            dt: dt,
            isIdle: isIdle
        )

        let finalCenter = ShotPlanner.clampCenter(
            NormalizedPoint(
                x: macroCenter.x + tracker.offset.x,
                y: macroCenter.y + tracker.offset.y
            ),
            zoom: zoom
        )

        return TimedTransform(
            time: sample.time,
            transform: TransformValue(zoom: zoom, center: finalCenter)
        )
    }
}
```

Note: `mouseData.interpolatedPosition(at:)` — check if this method exists on `MouseDataSource`. If not, use the nearest position from the mouse data. Explore the `MouseDataSource` protocol to find the correct API.

**Step 4: Handle UserIntent equality for idle check**

`UserIntent` may not conform to `Equatable`. Use pattern matching instead:

```swift
let isIdle = intentSpans.contains { span in
    if case .idle = span.intent,
       sample.time >= span.startTime,
       sample.time <= span.endTime {
        return true
    }
    return false
}
```

**Step 5: Run all tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ContinuousCameraGeneratorTests 2>&1 | tail -20`
Expected: All PASS

**Step 6: Commit**

```
git add -A && git commit -m "feat: integrate MicroTracker into camera pipeline"
```

---

### Task 8: Build verification for Phase 2

**Step 1: Run full test suite**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | tail -30`

**Step 2: Run lint**

Run: `./scripts/lint.sh`

**Step 3: Commit**

```
git add -A && git commit -m "chore: Phase 2 complete — micro tracking layer"
```

---

## Phase 3: Cursor Rendering Improvements

### Task 9: Camera-Space Cursor Smoothing

**Files:**
- Modify: `Screenize/Render/MousePositionInterpolator.swift`
- Modify: `Screenize/Render/SpringCursorSimulator.swift`
- Modify: `Screenize/Render/FrameEvaluator+Cursor.swift`
- Test: Existing cursor interpolation tests (find with `Grep` for `MousePositionInterpolator` or `SpringCursorSimulator` in test files)

**Step 1: Explore existing cursor evaluation code**

Read `FrameEvaluator+Cursor.swift` to understand how cursor position is currently computed and how camera transform is (or isn't) involved. Also read `MousePositionInterpolator.swift` and `SpringCursorSimulator.swift` for the smoothing pipeline.

**Step 2: Modify SpringCursorSimulator to accept camera-relative input**

The key change: instead of smoothing absolute cursor positions, smooth the cursor position relative to the current camera center. This requires passing the camera center to the smoothing step.

In `SpringCursorSimulator`, add a method or modify the existing step method:

```swift
/// Step the spring in camera-relative space.
/// - Parameters:
///   - rawPosition: Absolute cursor position in normalized coordinates
///   - cameraCenter: Current camera center
///   - dt: Time step
/// - Returns: Smoothed position in absolute coordinates
mutating func stepRelative(
    rawPosition: NormalizedPoint,
    cameraCenter: NormalizedPoint,
    dt: CGFloat
) -> NormalizedPoint {
    // Convert to camera space
    let relX = rawPosition.x - cameraCenter.x
    let relY = rawPosition.y - cameraCenter.y

    // Spring step in camera space
    let (newX, newVX) = springStep(current: stateX, velocity: velX, target: relX, dt: dt)
    let (newY, newVY) = springStep(current: stateY, velocity: velY, target: relY, dt: dt)

    stateX = newX; velX = newVX
    stateY = newY; velY = newVY

    // Convert back to absolute
    return NormalizedPoint(x: cameraCenter.x + newX, y: cameraCenter.y + newY)
}
```

**Step 3: Update FrameEvaluator+Cursor.swift to pass camera transform**

When evaluating cursor position, the camera transform at the same time should be available. Pass it through so the cursor interpolator can use camera-relative smoothing.

**Step 4: Update SpringCursorSimulator parameters**

```swift
dampingRatio: 0.90    // was 0.85 — less overshoot
response: 0.06        // was 0.08 — slightly faster
adaptiveMaxVelocity: 4.0  // was 3.0
adaptiveMinScale: 0.4     // was 0.3
```

**Step 5: Add idle stabilization to SpringCursorSimulator**

When cursor velocity drops below threshold, blend target toward current smoothed position:

```swift
private var idleBlendFactor: CGFloat = 0

// In step method, before spring calculation:
let velocity = hypot(rawPosition.x - lastRawX, rawPosition.y - lastRawY) / dt
if velocity < idleThreshold {
    idleBlendFactor = min(idleBlendFactor + dt * 3.0, 0.95)
} else {
    idleBlendFactor = 0
}
let effectiveTarget = NormalizedPoint(
    x: target.x * (1 - idleBlendFactor) + current.x * idleBlendFactor,
    y: target.y * (1 - idleBlendFactor) + current.y * idleBlendFactor
)
```

**Step 6: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | tail -30`

**Step 7: Commit**

```
git add -A && git commit -m "feat: camera-space cursor smoothing with idle stabilization"
```

---

### Task 10: Build verification for Phase 3

**Step 1: Run full test suite**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | tail -30`

**Step 2: Run lint**

Run: `./scripts/lint.sh`

**Step 3: Build the app**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`

**Step 4: Commit**

```
git add -A && git commit -m "chore: Phase 3 complete — cursor rendering improvements"
```

---

## Phase 4: Parameter Tuning

### Task 11: Tune Parameters with Real Recordings

This phase is manual and iterative. After Phases 1-3, build and run the app to test with real recordings.

**Tunable parameters and their locations:**

| Parameter | File | Default | Description |
|-----------|------|---------|-------------|
| `positionDampingRatio` | ContinuousCameraTypes.swift | 1.0 | Macro pan damping |
| `positionResponse` | ContinuousCameraTypes.swift | 0.8 | Macro pan speed |
| `zoomResponse` | ContinuousCameraTypes.swift | 0.8 | Macro zoom speed |
| `urgencyBlendDuration` | ContinuousCameraTypes.swift | 0.3 | Transition smoothness |
| `boundaryStiffness` | ContinuousCameraTypes.swift | 80.0 | Edge pushback force |
| `micro.deadZoneRatio` | ContinuousCameraTypes.swift | 0.4 | Dead zone size |
| `micro.maxOffsetRatio` | ContinuousCameraTypes.swift | 0.3 | Max micro movement |
| `micro.dampingRatio` | ContinuousCameraTypes.swift | 0.85 | Micro tracking feel |
| `micro.response` | ContinuousCameraTypes.swift | 0.15 | Micro tracking speed |

**Tuning strategy:**
1. Record 3+ diverse screen recordings (typing, clicking, mixed)
2. Generate auto-zoom and preview
3. Compare with Screen Studio output for same recording
4. Adjust parameters, rebuild, repeat

**Step 1: After tuning, commit final parameters**

```
git add -A && git commit -m "feat: tune dual-layer camera parameters"
```
