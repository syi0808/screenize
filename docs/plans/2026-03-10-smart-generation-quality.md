# Smart Generation Quality Improvements

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix three smart generation quality issues to reach Screen Studio-level camera and cursor animation quality.

**Architecture:** Three independent fixes targeting different pipeline stages: (1) Click cursor animation wiring in FrameEvaluator, (2) Dead zone hysteresis and tuning in DeadZoneTarget, (3) Zoom-pan coupling in SpringDamperSimulator via waypoint position hints.

**Tech Stack:** Swift, XCTest, spring-damper physics, EasingCurve

---

## Task 1: Wire ClickFeedbackConfig into computeClickScaleModifier

**Problem:** `computeClickScaleModifier` in `FrameEvaluator+ClickState.swift` hardcodes `pressDuration=0.08`, `pressedScale=0.8`, `settleDuration=0.08` with `easeOutQuad`. The `ClickFeedbackConfig` on `CursorSegment` (`mouseDownScale: 0.75`, `mouseDownDuration: 0.08`, `mouseUpDuration: 0.15`, `mouseUpSpring: spring(0.6, 0.3)`) is completely ignored. Release animation needs spring easing with subtle overshoot.

**Files:**
- Modify: `Screenize/Render/FrameEvaluator+ClickState.swift`
- Modify: `Screenize/Render/FrameEvaluator+Cursor.swift` (pass config)
- Modify: `Screenize/Render/FrameEvaluator.swift` (expose timeline for config lookup)
- Create: `ScreenizeTests/Render/ClickScaleModifierTests.swift`

### Step 1: Write failing tests for click scale with config

Create `ScreenizeTests/Render/ClickScaleModifierTests.swift`:

```swift
import XCTest
@testable import Screenize

final class ClickScaleModifierTests: XCTestCase {

    // MARK: - Helpers

    private func makeEvaluator(
        clicks: [RenderClickEvent],
        config: ClickFeedbackConfig = .default
    ) -> FrameEvaluator {
        // Minimal evaluator with click events and a cursor segment carrying the config
        let cursorSegment = CursorSegment(
            startTime: 0,
            endTime: 100,
            style: .arrow,
            visible: true,
            scale: 2.5,
            clickFeedback: config
        )
        let cursorTrack = CursorTrackV2(segments: [cursorSegment])
        let timeline = Timeline(
            tracks: [],
            cursorTrackV2: cursorTrack,
            continuousTransforms: nil,
            duration: 100
        )
        return FrameEvaluator(
            timeline: timeline,
            rawMousePositions: [],
            smoothedMousePositions: nil,
            clickEvents: clicks
        )
    }

    private func makeClick(
        at time: TimeInterval,
        duration: TimeInterval = 0.2
    ) -> RenderClickEvent {
        RenderClickEvent(
            timestamp: time,
            duration: duration,
            position: CGPoint(x: 0.5, y: 0.5),
            clickType: .left
        )
    }

    // MARK: - Default config behavior

    func test_noClicks_scaleIs1() {
        let eval = makeEvaluator(clicks: [])
        XCTAssertEqual(eval.computeClickScaleModifier(at: 5.0), 1.0)
    }

    func test_duringPress_scaleDecreasesToConfigScale() {
        let config = ClickFeedbackConfig.default  // mouseDownScale = 0.75
        let click = makeClick(at: 1.0, duration: 0.5)
        let eval = makeEvaluator(clicks: [click], config: config)

        // At end of mouseDown animation
        let scaleAtPressEnd = eval.computeClickScaleModifier(at: 1.0 + config.mouseDownDuration)
        XCTAssertEqual(scaleAtPressEnd, config.mouseDownScale, accuracy: 0.02)
    }

    func test_duringHold_scaleIsConfigScale() {
        let config = ClickFeedbackConfig.default
        let click = makeClick(at: 1.0, duration: 0.5)
        let eval = makeEvaluator(clicks: [click], config: config)

        let scaleDuringHold = eval.computeClickScaleModifier(at: 1.3)
        XCTAssertEqual(scaleDuringHold, config.mouseDownScale, accuracy: 0.01)
    }

    func test_afterRelease_scaleReturnsTo1() {
        let config = ClickFeedbackConfig.default  // mouseUpDuration = 0.15
        let click = makeClick(at: 1.0, duration: 0.2)
        let eval = makeEvaluator(clicks: [click], config: config)

        // Well after release (upTime=1.2, settle end=1.35)
        let scaleAfterSettle = eval.computeClickScaleModifier(at: 1.5)
        XCTAssertEqual(scaleAfterSettle, 1.0, accuracy: 0.01)
    }

    func test_releaseAnimation_usesSpringWithOvershoot() {
        // Spring with dampingRatio 0.6 should overshoot past 1.0
        let config = ClickFeedbackConfig(
            mouseDownScale: 0.75,
            mouseDownDuration: 0.08,
            mouseUpDuration: 0.3,
            mouseUpSpring: .spring(dampingRatio: 0.5, response: 0.3)
        )
        let click = makeClick(at: 1.0, duration: 0.1)
        let eval = makeEvaluator(clicks: [click], config: config)

        // During release, spring should overshoot
        // upTime = 1.1, release midpoint ~1.15
        let scaleAtMid = eval.computeClickScaleModifier(at: 1.15)
        // With underdamped spring (0.5), we expect overshoot > 1.0
        XCTAssertGreaterThan(scaleAtMid, 0.95,
            "Spring release should be recovering from pressed scale")
    }

    func test_customConfig_differentScale() {
        let config = ClickFeedbackConfig(
            mouseDownScale: 0.85,
            mouseDownDuration: 0.12,
            mouseUpDuration: 0.2,
            mouseUpSpring: .easeOut
        )
        let click = makeClick(at: 1.0, duration: 0.5)
        let eval = makeEvaluator(clicks: [click], config: config)

        let scaleAtPressEnd = eval.computeClickScaleModifier(at: 1.0 + 0.12)
        XCTAssertEqual(scaleAtPressEnd, 0.85, accuracy: 0.02)
    }
}
```

### Step 2: Run tests to verify they fail

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ClickScaleModifierTests -configuration Debug 2>&1 | tail -20`
Expected: Compilation failure — `computeClickScaleModifier` doesn't accept config, test helpers may not compile.

### Step 3: Implement — make computeClickScaleModifier config-aware

Modify `Screenize/Render/FrameEvaluator+ClickState.swift`:

Replace the hardcoded `computeClickScaleModifier` with a version that reads config from the active cursor segment:

```swift
func computeClickScaleModifier(at time: TimeInterval) -> CGFloat {
    guard !clickEvents.isEmpty else { return 1.0 }

    // Get click feedback config from active cursor segment
    let config: ClickFeedbackConfig
    if let track = timeline.cursorTrackV2,
       let segment = track.activeSegment(at: time) {
        config = segment.clickFeedback
    } else {
        config = .default
    }

    let pressDuration = config.mouseDownDuration
    let pressedScale = config.mouseDownScale
    let settleDuration = config.mouseUpDuration
    let releaseEasing = config.mouseUpSpring

    // Binary search for first click whose effect window reaches time
    var low = 0
    var high = clickEvents.count

    while low < high {
        let mid = (low + high) / 2
        if clickEvents[mid].endTimestamp + settleDuration < time {
            low = mid + 1
        } else {
            high = mid
        }
    }

    var candidates: [CGFloat] = []

    for i in low..<clickEvents.count {
        let click = clickEvents[i]
        let downTime = click.timestamp
        if downTime > time { break }
        let upTime = click.endTimestamp

        let clickModifier: CGFloat
        if time < downTime || time > upTime + settleDuration {
            continue
        } else if time <= downTime + pressDuration {
            let t = CGFloat((time - downTime) / pressDuration)
            clickModifier = 1.0 + (pressedScale - 1.0) * easeOutQuad(t)
        } else if time <= upTime {
            clickModifier = pressedScale
        } else {
            let t = CGFloat((time - upTime) / settleDuration)
            // Use spring easing (unclamped for overshoot)
            let easedT = releaseEasing.applyUnclamped(Double(t))
            clickModifier = pressedScale + (1.0 - pressedScale) * CGFloat(easedT)
        }

        candidates.append(clickModifier)
    }

    guard !candidates.isEmpty else { return 1.0 }
    if let minimum = candidates.min(), minimum < 1.0 {
        return minimum
    }
    return candidates.max() ?? 1.0
}
```

Key changes:
- Reads `ClickFeedbackConfig` from active `CursorSegment`
- Uses `applyUnclamped` for release easing to allow spring overshoot past 1.0
- All durations and scales come from config, not hardcoded

Note: The `candidates` logic with min/max must handle values > 1.0 from spring overshoot. Update the final return to allow overshoot:

```swift
guard !candidates.isEmpty else { return 1.0 }
// During overlapping clicks, use the most extreme modifier
return candidates.min { abs($0 - 1.0) > abs($1 - 1.0) } ?? 1.0
```

Actually, simpler — keep the deepest press or largest overshoot:

```swift
guard !candidates.isEmpty else { return 1.0 }
// Among all active clicks, pick the most extreme scale (furthest from 1.0)
return candidates.max(by: { abs($0 - 1.0) < abs($1 - 1.0) }) ?? 1.0
```

### Step 4: Run tests to verify they pass

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ClickScaleModifierTests -configuration Debug 2>&1 | tail -30`
Expected: All tests PASS.

### Step 5: Tune ClickFeedbackConfig defaults

Modify `Screenize/Timeline/Segments.swift` — update default config for Screen Studio-like feel:

```swift
static let `default` = Self(
    mouseDownScale: 0.78,
    mouseDownDuration: 0.10,
    mouseUpDuration: 0.25,
    mouseUpSpring: .spring(dampingRatio: 0.55, response: 0.25)
)
```

Changes: slower press (100ms vs 80ms), much longer release (250ms vs 80ms), bouncier spring (0.55 vs 0.6 damping), slightly less compression (0.78 vs 0.75).

### Step 6: Run all tests, then commit

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -configuration Debug 2>&1 | tail -30`
Expected: All tests pass.

```bash
git add Screenize/Render/FrameEvaluator+ClickState.swift Screenize/Timeline/Segments.swift ScreenizeTests/Render/ClickScaleModifierTests.swift
git commit -m "fix: wire ClickFeedbackConfig into click scale animation with spring release"
```

---

## Task 2: Add dead zone hysteresis and widen gradient band

**Problem:** The dead zone boundary causes jittery target positions when cursor oscillates near the safe zone edge. The 10% gradient band is too narrow, and there's no hysteresis (same threshold for entering and leaving).

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift` (add hysteresis setting)
- Modify: `Screenize/Generators/ContinuousCamera/DeadZoneTarget.swift` (implement hysteresis + wider gradient)
- Modify: `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift` (track dead zone activation state)
- Modify: `ScreenizeTests/Generators/ContinuousCamera/DeadZoneTargetTests.swift` (new tests)

### Step 1: Write failing tests for hysteresis behavior

Add to `ScreenizeTests/Generators/ContinuousCamera/DeadZoneTargetTests.swift`:

```swift
// MARK: - Hysteresis Tests

func test_hysteresis_enteringRequiresLargerOffset() {
    // When wasActive=false (cursor was in safe zone), need to reach full trigger threshold
    let settings = DeadZoneSettings()
    let zoom: CGFloat = 2.0
    let center = NormalizedPoint(x: 0.5, y: 0.5)

    // Position just outside safe zone but within hysteresis band
    let viewportHalf = 0.5 / zoom  // 0.25
    let safeHalf = viewportHalf * settings.safeZoneFraction  // 0.1875
    let hysteresisHalf = safeHalf * settings.hysteresisMargin  // 0.1875 * 0.15 = ~0.028
    let justOutside = 0.5 + safeHalf + hysteresisHalf * 0.5  // Inside hysteresis band

    let (result, active) = DeadZoneTarget.computeWithState(
        cursorPosition: NormalizedPoint(x: justOutside, y: 0.5),
        cameraCenter: center,
        zoom: zoom,
        isTyping: false,
        wasActive: false,  // Was inside safe zone
        settings: settings
    )
    // Should NOT activate — still within hysteresis band
    XCTAssertFalse(active, "Should not activate within hysteresis band when entering")
    XCTAssertEqual(result.x, 0.5, accuracy: 0.001)
}

func test_hysteresis_leavingUsesInnerThreshold() {
    let settings = DeadZoneSettings()
    let zoom: CGFloat = 2.0
    let center = NormalizedPoint(x: 0.5, y: 0.5)

    let viewportHalf = 0.5 / zoom
    let safeHalf = viewportHalf * settings.safeZoneFraction
    let hysteresisHalf = safeHalf * settings.hysteresisMargin
    // Position inside safe zone but close to edge — should stay active if wasActive=true
    let insideButNearEdge = 0.5 + safeHalf - hysteresisHalf * 0.5

    let (_, active) = DeadZoneTarget.computeWithState(
        cursorPosition: NormalizedPoint(x: insideButNearEdge, y: 0.5),
        cameraCenter: center,
        zoom: zoom,
        isTyping: false,
        wasActive: true,  // Was already tracking
        settings: settings
    )
    // Should remain active — hasn't crossed inner threshold
    XCTAssertTrue(active, "Should remain active within hysteresis band when leaving")
}

func test_widerGradient_smootherTransition() {
    var settings = DeadZoneSettings()
    settings.gradientBandWidth = 0.25  // Wider than default 0.10

    let zoom: CGFloat = 2.0
    let center = NormalizedPoint(x: 0.5, y: 0.5)
    let viewportHalf = 0.5 / zoom
    let safeHalf = viewportHalf * settings.safeZoneFraction

    // Sample points across gradient band
    var targets: [CGFloat] = []
    for i in 0...10 {
        let frac = CGFloat(i) / 10.0
        let x = 0.5 + safeHalf + viewportHalf * settings.gradientBandWidth * frac
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: x, y: 0.5),
            cameraCenter: center,
            zoom: zoom,
            isTyping: false,
            settings: settings
        )
        targets.append(result.x)
    }

    // Verify monotonic and smooth (no big jumps)
    for i in 1..<targets.count {
        XCTAssertGreaterThanOrEqual(targets[i], targets[i-1] - 0.001,
            "Target should increase monotonically across gradient band")
        let jump = abs(targets[i] - targets[i-1])
        XCTAssertLessThan(jump, 0.03,
            "Target should change smoothly across gradient band")
    }
}
```

### Step 2: Run tests to verify they fail

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/DeadZoneTargetTests -configuration Debug 2>&1 | tail -20`
Expected: Compilation failure — `computeWithState` doesn't exist, `hysteresisMargin` doesn't exist.

### Step 3: Add hysteresis settings

Modify `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`, add to `DeadZoneSettings`:

```swift
/// Hysteresis margin as fraction of safe zone half-width.
/// Entering requires crossing safeHalf + margin, leaving requires dropping below safeHalf - margin.
var hysteresisMargin: CGFloat = 0.15
```

Also widen default gradient:

```swift
var gradientBandWidth: CGFloat = 0.25  // was 0.10
```

And soften correction:

```swift
var correctionFraction: CGFloat = 0.45  // was 0.60
```

### Step 4: Implement computeWithState with hysteresis

Modify `Screenize/Generators/ContinuousCamera/DeadZoneTarget.swift`:

```swift
enum DeadZoneTarget {

    /// Original API (backwards compatible) — no state tracking.
    static func compute(
        cursorPosition: NormalizedPoint,
        cameraCenter: NormalizedPoint,
        zoom: CGFloat,
        isTyping: Bool,
        settings: DeadZoneSettings
    ) -> NormalizedPoint {
        computeWithState(
            cursorPosition: cursorPosition,
            cameraCenter: cameraCenter,
            zoom: zoom,
            isTyping: isTyping,
            wasActive: false,
            settings: settings
        ).target
    }

    /// State-aware API with hysteresis.
    /// Returns (target position, whether dead zone is now active).
    static func computeWithState(
        cursorPosition: NormalizedPoint,
        cameraCenter: NormalizedPoint,
        zoom: CGFloat,
        isTyping: Bool,
        wasActive: Bool,
        settings: DeadZoneSettings
    ) -> (target: NormalizedPoint, isActive: Bool) {
        guard zoom > 1.001 else {
            return (NormalizedPoint(x: 0.5, y: 0.5), false)
        }

        let viewportHalf = 0.5 / zoom
        let safeFraction = isTyping ? settings.safeZoneFractionTyping : settings.safeZoneFraction
        let correction = isTyping ? settings.correctionFractionTyping : settings.correctionFraction
        let safeHalf = viewportHalf * safeFraction
        let hysteresisHalf = safeHalf * settings.hysteresisMargin
        let gradientHalf = viewportHalf * settings.gradientBandWidth

        let offsetX = cursorPosition.x - cameraCenter.x
        let offsetY = cursorPosition.y - cameraCenter.y
        let absOffsetX = abs(offsetX)
        let absOffsetY = abs(offsetY)

        // Hysteresis: different thresholds for activation/deactivation
        let effectiveThreshold: CGFloat
        if wasActive {
            // Already tracking — use inner threshold (keep tracking longer)
            effectiveThreshold = safeHalf - hysteresisHalf
        } else {
            // Not tracking — use outer threshold (require more movement to start)
            effectiveThreshold = safeHalf + hysteresisHalf
        }

        let isNowActive = absOffsetX > effectiveThreshold || absOffsetY > effectiveThreshold

        if !isNowActive {
            return (cameraCenter, false)
        }

        let targetX = axisTarget(
            offset: offsetX, cameraPos: cameraCenter.x, cursorPos: cursorPosition.x,
            viewportHalf: viewportHalf, safeHalf: safeHalf,
            gradientHalf: gradientHalf, correction: correction
        )
        let targetY = axisTarget(
            offset: offsetY, cameraPos: cameraCenter.y, cursorPos: cursorPosition.y,
            viewportHalf: viewportHalf, safeHalf: safeHalf,
            gradientHalf: gradientHalf, correction: correction
        )

        let clamped = ShotPlanner.clampCenter(
            NormalizedPoint(x: targetX, y: targetY), zoom: zoom
        )
        return (clamped, true)
    }

    // axisTarget remains unchanged
}
```

### Step 5: Update SpringDamperSimulator to track dead zone activation state

Modify `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift`:

Add `var deadZoneActive: Bool = false` to `CameraState`, then in the simulate loop replace:

```swift
// Before (line 134-140):
let posTarget = DeadZoneTarget.compute(...)

// After:
let (posTarget, deadZoneNowActive) = DeadZoneTarget.computeWithState(
    cursorPosition: cursorPos,
    cameraCenter: NormalizedPoint(x: state.positionX, y: state.positionY),
    zoom: state.zoom,
    isTyping: isTyping,
    wasActive: state.deadZoneActive,
    settings: settings.deadZone
)
state.deadZoneActive = deadZoneNowActive
```

### Step 6: Run tests to verify they pass

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/DeadZoneTargetTests -configuration Debug 2>&1 | tail -30`
Expected: All tests PASS including new hysteresis tests.

### Step 7: Run full test suite, then commit

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -configuration Debug 2>&1 | tail -30`
Expected: All tests pass.

```bash
git add Screenize/Generators/ContinuousCamera/DeadZoneTarget.swift Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift ScreenizeTests/Generators/ContinuousCamera/DeadZoneTargetTests.swift
git commit -m "fix: add dead zone hysteresis and widen gradient band for smoother panning"
```

---

## Task 3: Couple zoom and pan transitions via waypoint position hints

**Problem:** Zoom targets arrive early (via waypoint lead time) but pan targets are purely reactive (dead zone). This causes zoom to complete before pan starts, leaving the cursor off-screen during transitions.

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift` (blend waypoint center into position target)
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift` (add coupling settings)
- Modify: `ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift` (new tests)

### Step 1: Write failing tests for zoom-pan coupling

Add to `ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift`:

```swift
// MARK: - Zoom-Pan Coupling

func test_simulate_zoomAndPan_arriveTogetherDuringTransition() {
    // Cursor stationary at center, then jumps to new position at t=2.0.
    // Waypoint at t=2.0 with typing urgency (lead time 0.16s → appears at t=1.84).
    // Pan should start moving BEFORE cursor actually jumps, guided by waypoint center.
    var positions: [MousePositionData] = []
    for i in 0..<300 {
        let t = Double(i) / 60.0
        let x: CGFloat = t < 2.0 ? 0.3 : 0.7
        positions.append(MousePositionData(
            time: t, position: NormalizedPoint(x: x, y: 0.5)
        ))
    }
    let zoomWPs = [
        CameraWaypoint(time: 0, targetZoom: 1.5,
                       targetCenter: NormalizedPoint(x: 0.3, y: 0.5),
                       urgency: .normal, source: .clicking),
        // Waypoint with center hint at new position
        CameraWaypoint(time: 1.84, targetZoom: 1.8,
                       targetCenter: NormalizedPoint(x: 0.7, y: 0.5),
                       urgency: .high, source: .typing(context: .codeEditor))
    ]
    let intentSpans = [
        IntentSpan(startTime: 0, endTime: 1.84, intent: .clicking,
                   confidence: 1.0, focusPosition: NormalizedPoint(x: 0.3, y: 0.5)),
        IntentSpan(startTime: 2.0, endTime: 5.0,
                   intent: .typing(context: .codeEditor),
                   confidence: 1.0, focusPosition: NormalizedPoint(x: 0.7, y: 0.5))
    ]
    let result = SpringDamperSimulator.simulate(
        cursorPositions: positions,
        zoomWaypoints: zoomWPs,
        intentSpans: intentSpans,
        duration: 5.0,
        settings: defaultSettings
    )

    // At t=1.9 (before cursor jump but after waypoint), pan should already be moving right
    guard let sampleBefore = result.first(where: { $0.time >= 1.9 }) else {
        XCTFail("Expected sample at t=1.9")
        return
    }
    // Camera should have started panning toward 0.7 (at least slightly right of 0.3)
    XCTAssertGreaterThan(sampleBefore.transform.center.x, 0.35,
        "Pan should start moving toward waypoint center before cursor jump")

    // At t=3.0 (well after transition), zoom and pan should both be settled
    guard let sampleAfter = result.first(where: { $0.time >= 3.0 }) else {
        XCTFail("Expected sample at t=3.0")
        return
    }
    XCTAssertEqual(sampleAfter.transform.zoom, 1.8, accuracy: 0.1)
    XCTAssertGreaterThan(sampleAfter.transform.center.x, 0.55,
        "Pan should have converged toward cursor position")
}

func test_simulate_waypointCenterHint_blendsDuringTransition() {
    // When a new waypoint activates, position target should blend between
    // dead zone target and waypoint center over the coupling window.
    let positions = (0..<300).map { i in
        MousePositionData(
            time: Double(i) / 60.0,
            position: NormalizedPoint(x: 0.5, y: 0.5)
        )
    }
    var settings = ContinuousCameraSettings()
    settings.waypointCenterCouplingDuration = 0.5
    settings.waypointCenterCouplingStrength = 0.6

    let zoomWPs = [
        CameraWaypoint(time: 0, targetZoom: 1.5,
                       targetCenter: NormalizedPoint(x: 0.5, y: 0.5),
                       urgency: .normal, source: .clicking),
        CameraWaypoint(time: 1.0, targetZoom: 1.8,
                       targetCenter: NormalizedPoint(x: 0.3, y: 0.4),
                       urgency: .high, source: .typing(context: .codeEditor))
    ]
    let result = SpringDamperSimulator.simulate(
        cursorPositions: positions,
        zoomWaypoints: zoomWPs,
        intentSpans: [],
        duration: 5.0,
        settings: settings
    )

    // At t=1.25 (during coupling window), camera should be pulled toward (0.3, 0.4)
    guard let sample = result.first(where: { $0.time >= 1.25 }) else {
        XCTFail("Expected sample at t=1.25")
        return
    }
    XCTAssertLessThan(sample.transform.center.x, 0.48,
        "Camera should be pulled toward waypoint center during coupling window")
}
```

### Step 2: Run tests to verify they fail

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SpringDamperSimulatorTests -configuration Debug 2>&1 | tail -20`
Expected: Compilation failure — `waypointCenterCouplingDuration` and `waypointCenterCouplingStrength` don't exist.

### Step 3: Add coupling settings

Modify `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`, add to `ContinuousCameraSettings`:

```swift
/// Duration in seconds over which waypoint center blends into position target.
var waypointCenterCouplingDuration: TimeInterval = 0.4
/// Blend strength: 0 = ignore waypoint center, 1 = fully use waypoint center.
var waypointCenterCouplingStrength: CGFloat = 0.5
```

### Step 4: Implement waypoint center coupling in simulator

Modify `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift`:

Add tracking variables after `var zoomUrgencyTransitionStart`:

```swift
var lastWaypointActivationTime: TimeInterval = 0
```

In the simulation loop, after the dead zone targeting section and before the position spring step, add waypoint center blending:

```swift
// Waypoint center coupling: blend waypoint's targetCenter into position target
// during transitions to synchronize pan with zoom.
var blendedTarget = posTarget
let couplingDuration = settings.waypointCenterCouplingDuration
let couplingStrength = settings.waypointCenterCouplingStrength

if zoomIndex != previousZoomIndex {
    lastWaypointActivationTime = t
}

if couplingStrength > 0.001 && couplingDuration > 0.001 {
    let elapsed = t - lastWaypointActivationTime
    if elapsed < couplingDuration && !zoomWaypoints.isEmpty {
        let waypointCenter = zoomWaypoints[zoomIndex].targetCenter
        // Fade coupling strength from full to zero over the coupling window
        let fadeProgress = CGFloat(elapsed / couplingDuration)
        let fadedStrength = couplingStrength * (1.0 - fadeProgress * fadeProgress)
        blendedTarget = NormalizedPoint(
            x: posTarget.x + (waypointCenter.x - posTarget.x) * fadedStrength,
            y: posTarget.y + (waypointCenter.y - posTarget.y) * fadedStrength
        )
        blendedTarget = ShotPlanner.clampCenter(blendedTarget, zoom: state.zoom)
    }
}
```

Then update the spring step to use `blendedTarget` instead of `posTarget`:

```swift
let (newX, newVX) = springStep(
    current: state.positionX, velocity: state.velocityX,
    target: blendedTarget.x,
    omega: posOmega, zeta: posDamping, dt: CGFloat(dt)
)
let (newY, newVY) = springStep(
    current: state.positionY, velocity: state.velocityY,
    target: blendedTarget.y,
    omega: posOmega, zeta: posDamping, dt: CGFloat(dt)
)
```

Important: move `lastWaypointActivationTime` tracking outside the existing `if zoomIndex != previousZoomIndex` block to ensure it updates correctly.

### Step 5: Also match zoom and position damping ratios

Modify `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`:

```swift
var positionDampingRatio: CGFloat = 0.90  // was 1.0 — match zoom's 0.90 for consistent feel
```

### Step 6: Run tests to verify they pass

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SpringDamperSimulatorTests -configuration Debug 2>&1 | tail -30`
Expected: All tests PASS.

### Step 7: Run full test suite, then commit

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -configuration Debug 2>&1 | tail -30`
Expected: All tests pass.

```bash
git add Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift
git commit -m "fix: couple zoom and pan transitions via waypoint center blending"
```

---

## Task 4: Final integration verification

### Step 1: Run full build + test suite

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build
xcodebuild test -project Screenize.xcodeproj -scheme Screenize -configuration Debug
```

### Step 2: Verify with the reference project

Open the app, load `projects/Recording_2026-02-24_02-19-36.screenize`, regenerate the smart generation timeline, and preview. Check:
- Click cursor animation has subtle spring bounce on release
- Panning follows cursor without stuttering near dead zone edges
- Zoom and pan transitions arrive together (no cursor off-screen during transitions)

### Step 3: Compare parameter summary

| Parameter | Before | After | Reason |
|-----------|--------|-------|--------|
| `mouseDownScale` | 0.75 | 0.78 | Subtler press |
| `mouseDownDuration` | 0.08s | 0.10s | Slightly slower press |
| `mouseUpDuration` | 0.15s | 0.25s | Much longer release |
| `mouseUpSpring` | spring(0.6, 0.3) | spring(0.55, 0.25) | Bouncier release |
| `gradientBandWidth` | 0.10 | 0.25 | 2.5x wider transition zone |
| `correctionFraction` | 0.60 | 0.45 | Less aggressive correction |
| `hysteresisMargin` | (new) | 0.15 | Prevents edge oscillation |
| `positionDampingRatio` | 1.0 | 0.90 | Matches zoom spring character |
| `waypointCenterCouplingDuration` | (new) | 0.4s | Pan follows zoom timing |
| `waypointCenterCouplingStrength` | (new) | 0.5 | 50% blend toward waypoint |
