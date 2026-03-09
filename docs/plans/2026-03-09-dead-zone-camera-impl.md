# Dead Zone Camera Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace always-follow cursor tracking with viewport-aware dead zone targeting and adaptive spring response.

**Architecture:** SpringDamperSimulator's position target changes from "always cursor" to "viewport-edge-triggered partial correction." IntentSpans are passed into the simulator to enable adaptive spring response based on time-to-next-action. MicroTracker idle re-centering is removed from the pipeline.

**Tech Stack:** Swift, CoreGraphics, XCTest

**Design doc:** `docs/plans/2026-03-09-dead-zone-camera-design.md`

---

### Task 1: Add Dead Zone Settings to ContinuousCameraTypes

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`

**Step 1: Add DeadZoneSettings struct and update ContinuousCameraSettings**

Add a new settings struct for dead zone parameters and replace old position spring defaults.

```swift
// Add after MicroTrackerSettings struct (line 14):

// MARK: - Dead Zone Settings

/// Configuration for viewport-aware dead zone camera targeting.
struct DeadZoneSettings {
    /// Fraction of viewport that is the safe zone (no camera movement). 0.75 = 75%.
    var safeZoneFraction: CGFloat = 0.75
    /// Safe zone fraction during typing (smaller = more responsive to caret movement).
    var safeZoneFractionTyping: CGFloat = 0.60
    /// Width of gradient transition band between safe and trigger zones (fraction of viewport).
    var gradientBandWidth: CGFloat = 0.10
    /// Partial correction fraction. 0 = minimal movement, 1 = center cursor.
    var correctionFraction: CGFloat = 0.60
    /// Correction fraction during typing (more aggressive caret following).
    var correctionFractionTyping: CGFloat = 0.80
    /// Minimum spring response time (when next action is imminent).
    var minResponse: CGFloat = 0.20
    /// Maximum spring response time (when next action is far away).
    var maxResponse: CGFloat = 0.50
    /// Time-to-next-action threshold below which minResponse is used.
    var responseFastThreshold: TimeInterval = 0.5
    /// Time-to-next-action threshold above which maxResponse is used.
    var responseSlowThreshold: TimeInterval = 2.0
}
```

In `ContinuousCameraSettings`, change these defaults:
- `positionDampingRatio`: 0.80 → 1.0
- `positionResponse`: 0.12 → 0.35 (fallback, adaptive response overrides this)
- Remove `positionLookahead` property
- Add `var deadZone = DeadZoneSettings()`

**Step 2: Run build to verify compilation**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: Build succeeds (positionLookahead removal will cause errors in SpringDamperSimulator — that's expected, fixed in Task 3)

**Step 3: Commit**

```
feat: add DeadZoneSettings and update position spring defaults
```

---

### Task 2: Write Dead Zone Targeting Tests

**Files:**
- Create: `ScreenizeTests/Generators/ContinuousCamera/DeadZoneTargetTests.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj` (add new test file)

**Step 1: Write tests for dead zone target computation**

These tests verify a pure function `DeadZoneTarget.compute()` that will be implemented in Task 3. Tests cover:

```swift
import XCTest
@testable import Screenize

final class DeadZoneTargetTests: XCTestCase {

    // MARK: - Safe Zone (camera holds still)

    func test_cursorInSafeZone_targetIsCurrentCenter() {
        // Cursor at (0.5, 0.5), camera at (0.5, 0.5), zoom 2.0
        // Viewport = 0.5 wide, safe zone = 75% of 0.5 = 0.375
        // Safe zone covers camera center ± 0.1875
        // Cursor is at center → well within safe zone
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.5, y: 0.5),
            cameraCenter: NormalizedPoint(x: 0.5, y: 0.5),
            zoom: 2.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        XCTAssertEqual(result.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.y, 0.5, accuracy: 0.001)
    }

    func test_cursorSlightlyOffCenter_stillInSafeZone() {
        // Camera at (0.5, 0.5), zoom 2.0
        // Viewport half-size = 0.25 per axis
        // Safe zone half-size = 0.25 * 0.75 = 0.1875
        // Cursor at (0.6, 0.5) → offset = 0.1 < 0.1875 → safe
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.6, y: 0.5),
            cameraCenter: NormalizedPoint(x: 0.5, y: 0.5),
            zoom: 2.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        XCTAssertEqual(result.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.y, 0.5, accuracy: 0.001)
    }

    // MARK: - Trigger Zone (camera moves with partial correction)

    func test_cursorInTriggerZone_targetMovesPartially() {
        // Camera at (0.5, 0.5), zoom 2.0
        // Viewport half = 0.25, safe half = 0.1875
        // Cursor at (0.73, 0.5) → offset = 0.23 > 0.1875 → trigger zone
        // Camera should move, but NOT center on cursor
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.73, y: 0.5),
            cameraCenter: NormalizedPoint(x: 0.5, y: 0.5),
            zoom: 2.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        // Target should move right (> 0.5) but not to 0.73
        XCTAssertGreaterThan(result.x, 0.5)
        XCTAssertLessThan(result.x, 0.73)
        // Y unchanged
        XCTAssertEqual(result.y, 0.5, accuracy: 0.001)
    }

    func test_cursorOutsideViewport_targetPullsInside() {
        // Camera at (0.5, 0.5), zoom 2.0
        // Viewport edge at 0.75
        // Cursor at (0.8, 0.5) → outside viewport
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.8, y: 0.5),
            cameraCenter: NormalizedPoint(x: 0.5, y: 0.5),
            zoom: 2.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        // Target should move right enough to bring cursor inside
        XCTAssertGreaterThan(result.x, 0.5)
    }

    // MARK: - Gradient Band (smooth transition)

    func test_cursorInGradientBand_targetBlended() {
        // At the gradient boundary between safe and trigger,
        // the target should be between "hold" and "full correction"
        let settings = DeadZoneSettings()
        let safeEdge = 0.5 + 0.25 * settings.safeZoneFraction  // 0.6875
        let triggerStart = safeEdge + 0.25 * settings.gradientBandWidth * 0.5
        // Put cursor right at the gradient midpoint
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: triggerStart, y: 0.5),
            cameraCenter: NormalizedPoint(x: 0.5, y: 0.5),
            zoom: 2.0,
            isTyping: false,
            settings: settings
        )
        // Should be somewhere between hold (0.5) and full correction
        // Exact value depends on gradient math, but should NOT be exactly 0.5
        // and should NOT be as much as trigger zone correction
        XCTAssertGreaterThanOrEqual(result.x, 0.5)
    }

    // MARK: - Typing Mode

    func test_typingMode_smallerSafeZone() {
        // Same cursor position, but typing mode has smaller safe zone (60% vs 75%)
        // A position that's safe in normal mode might be trigger in typing mode
        let cursorPos = NormalizedPoint(x: 0.67, y: 0.5)
        let center = NormalizedPoint(x: 0.5, y: 0.5)

        let normalResult = DeadZoneTarget.compute(
            cursorPosition: cursorPos, cameraCenter: center,
            zoom: 2.0, isTyping: false, settings: DeadZoneSettings()
        )
        let typingResult = DeadZoneTarget.compute(
            cursorPosition: cursorPos, cameraCenter: center,
            zoom: 2.0, isTyping: true, settings: DeadZoneSettings()
        )
        // Normal: cursor at 0.67, safe edge at 0.6875 → safe → hold at 0.5
        XCTAssertEqual(normalResult.x, 0.5, accuracy: 0.01)
        // Typing: safe edge at 0.65 → trigger → target moves
        XCTAssertGreaterThan(typingResult.x, 0.5)
    }

    func test_typingMode_higherCorrectionFraction() {
        // In trigger zone, typing should correct more (0.8) than normal (0.6)
        let cursorPos = NormalizedPoint(x: 0.74, y: 0.5)
        let center = NormalizedPoint(x: 0.5, y: 0.5)

        let normalResult = DeadZoneTarget.compute(
            cursorPosition: cursorPos, cameraCenter: center,
            zoom: 2.0, isTyping: false, settings: DeadZoneSettings()
        )
        let typingResult = DeadZoneTarget.compute(
            cursorPosition: cursorPos, cameraCenter: center,
            zoom: 2.0, isTyping: true, settings: DeadZoneSettings()
        )
        // Typing correction should be closer to cursor than normal
        XCTAssertGreaterThan(typingResult.x, normalResult.x)
    }

    // MARK: - Zoom 1.0x (no movement)

    func test_zoom1x_targetAlwaysCenter() {
        // At zoom 1.0, entire screen visible → target is always (0.5, 0.5)
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.8, y: 0.2),
            cameraCenter: NormalizedPoint(x: 0.3, y: 0.7),
            zoom: 1.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        XCTAssertEqual(result.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.y, 0.5, accuracy: 0.001)
    }

    // MARK: - Boundary Clamping

    func test_targetClampedToValidBounds() {
        // Even with correction, target should stay within valid viewport center bounds
        let result = DeadZoneTarget.compute(
            cursorPosition: NormalizedPoint(x: 0.95, y: 0.95),
            cameraCenter: NormalizedPoint(x: 0.8, y: 0.8),
            zoom: 2.0,
            isTyping: false,
            settings: DeadZoneSettings()
        )
        // At zoom 2.0, valid center range is 0.25...0.75
        XCTAssertLessThanOrEqual(result.x, 0.75)
        XCTAssertLessThanOrEqual(result.y, 0.75)
    }
}
```

**Step 2: Add test file to Xcode project**

Add `DeadZoneTargetTests.swift` to `Screenize.xcodeproj/project.pbxproj` in the test target.

**Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/DeadZoneTargetTests 2>&1 | grep -E "(Test Case|error:)" | head -20`
Expected: Compilation error — `DeadZoneTarget` not defined yet

**Step 4: Commit**

```
test: add dead zone target computation tests
```

---

### Task 3: Implement DeadZoneTarget

**Files:**
- Create: `Screenize/Generators/ContinuousCamera/DeadZoneTarget.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj` (add new source file)

**Step 1: Implement the pure targeting function**

```swift
import Foundation
import CoreGraphics

/// Computes the camera position target based on viewport-aware dead zone logic.
///
/// When cursor is within the safe zone (center of viewport), camera holds still.
/// When cursor approaches viewport edges, camera moves just enough to maintain
/// visibility with partial correction (not centering).
enum DeadZoneTarget {

    /// Compute the position target for the camera spring.
    /// - Parameters:
    ///   - cursorPosition: Current cursor position in normalized coordinates
    ///   - cameraCenter: Current camera center position
    ///   - zoom: Current zoom level
    ///   - isTyping: Whether the current intent is typing (uses tighter safe zone)
    ///   - settings: Dead zone configuration
    /// - Returns: Target position for the camera spring
    static func compute(
        cursorPosition: NormalizedPoint,
        cameraCenter: NormalizedPoint,
        zoom: CGFloat,
        isTyping: Bool,
        settings: DeadZoneSettings
    ) -> NormalizedPoint {
        // At zoom 1.0, entire screen visible — no position movement needed
        guard zoom > 1.001 else {
            return NormalizedPoint(x: 0.5, y: 0.5)
        }

        let viewportHalf = 0.5 / zoom
        let safeFraction = isTyping ? settings.safeZoneFractionTyping : settings.safeZoneFraction
        let correction = isTyping ? settings.correctionFractionTyping : settings.correctionFraction
        let safeHalf = viewportHalf * safeFraction
        let gradientHalf = viewportHalf * settings.gradientBandWidth

        // Compute cursor offset from camera center
        let offsetX = cursorPosition.x - cameraCenter.x
        let offsetY = cursorPosition.y - cameraCenter.y

        let targetX = axisTarget(
            offset: offsetX,
            cameraPos: cameraCenter.x,
            cursorPos: cursorPosition.x,
            viewportHalf: viewportHalf,
            safeHalf: safeHalf,
            gradientHalf: gradientHalf,
            correction: correction
        )
        let targetY = axisTarget(
            offset: offsetY,
            cameraPos: cameraCenter.y,
            cursorPos: cursorPosition.y,
            viewportHalf: viewportHalf,
            safeHalf: safeHalf,
            gradientHalf: gradientHalf,
            correction: correction
        )

        return ShotPlanner.clampCenter(
            NormalizedPoint(x: targetX, y: targetY),
            zoom: zoom
        )
    }

    /// Compute target for a single axis.
    private static func axisTarget(
        offset: CGFloat,
        cameraPos: CGFloat,
        cursorPos: CGFloat,
        viewportHalf: CGFloat,
        safeHalf: CGFloat,
        gradientHalf: CGFloat,
        correction: CGFloat
    ) -> CGFloat {
        let absOffset = abs(offset)

        // Safe zone: hold still
        if absOffset <= safeHalf {
            return cameraPos
        }

        // Minimal correction: move camera so cursor sits at safe zone edge
        let minimalTarget = cursorPos - copysign(safeHalf, offset)
        // Ideal correction: center cursor in viewport
        let idealTarget = cursorPos

        // Partial correction between minimal and ideal
        let correctedTarget = minimalTarget + (idealTarget - minimalTarget) * correction

        // Gradient band: blend between hold and corrected
        let gradientEnd = safeHalf + gradientHalf
        if absOffset < gradientEnd && gradientHalf > 0.001 {
            let gradientProgress = (absOffset - safeHalf) / gradientHalf
            let smoothProgress = gradientProgress * gradientProgress * (3 - 2 * gradientProgress)
            return cameraPos + (correctedTarget - cameraPos) * smoothProgress
        }

        // Full trigger zone or outside viewport
        return correctedTarget
    }
}
```

**Step 2: Add file to Xcode project**

Add `DeadZoneTarget.swift` to `Screenize.xcodeproj/project.pbxproj` in the main target.

**Step 3: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/DeadZoneTargetTests 2>&1 | grep -E "(Test Case|Executed)" | tail -15`
Expected: All tests pass

**Step 4: Commit**

```
feat: implement DeadZoneTarget viewport-aware targeting
```

---

### Task 4: Write Adaptive Response Tests

**Files:**
- Create: `ScreenizeTests/Generators/ContinuousCamera/AdaptiveResponseTests.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj`

**Step 1: Write tests for adaptive spring response computation**

```swift
import XCTest
@testable import Screenize

final class AdaptiveResponseTests: XCTestCase {

    func test_nextActionFarAway_slowResponse() {
        let settings = DeadZoneSettings()
        let response = AdaptiveResponse.compute(
            timeToNextAction: 3.0,
            settings: settings
        )
        XCTAssertEqual(response, settings.maxResponse, accuracy: 0.001)
    }

    func test_nextActionImminent_fastResponse() {
        let settings = DeadZoneSettings()
        let response = AdaptiveResponse.compute(
            timeToNextAction: 0.2,
            settings: settings
        )
        XCTAssertEqual(response, settings.minResponse, accuracy: 0.001)
    }

    func test_nextActionMidRange_interpolatedResponse() {
        let settings = DeadZoneSettings()
        // Midpoint between 0.5s and 2.0s = 1.25s
        let response = AdaptiveResponse.compute(
            timeToNextAction: 1.25,
            settings: settings
        )
        // Should be between min and max
        XCTAssertGreaterThan(response, settings.minResponse)
        XCTAssertLessThan(response, settings.maxResponse)
    }

    func test_noNextAction_slowResponse() {
        let settings = DeadZoneSettings()
        let response = AdaptiveResponse.compute(
            timeToNextAction: nil,
            settings: settings
        )
        XCTAssertEqual(response, settings.maxResponse, accuracy: 0.001)
    }

    func test_findNextActionTime_skipsIdleAndReading() {
        let spans = [
            makeSpan(start: 0, end: 2, intent: .idle),
            makeSpan(start: 2, end: 4, intent: .reading),
            makeSpan(start: 4, end: 6, intent: .clicking),
        ]
        let nextTime = AdaptiveResponse.findNextActionTime(
            after: 1.0,
            intentSpans: spans
        )
        XCTAssertEqual(nextTime, 4.0, accuracy: 0.001)
    }

    func test_findNextActionTime_noFutureAction_returnsNil() {
        let spans = [
            makeSpan(start: 0, end: 2, intent: .clicking),
            makeSpan(start: 2, end: 5, intent: .idle),
        ]
        let nextTime = AdaptiveResponse.findNextActionTime(
            after: 3.0,
            intentSpans: spans
        )
        XCTAssertNil(nextTime)
    }

    func test_findNextActionTime_typingIsAction() {
        let spans = [
            makeSpan(start: 0, end: 2, intent: .idle),
            makeSpan(start: 2, end: 5, intent: .typing(context: .codeEditor)),
        ]
        let nextTime = AdaptiveResponse.findNextActionTime(
            after: 1.0,
            intentSpans: spans
        )
        XCTAssertEqual(nextTime, 2.0, accuracy: 0.001)
    }

    private func makeSpan(
        start: TimeInterval, end: TimeInterval, intent: UserIntent
    ) -> IntentSpan {
        IntentSpan(
            startTime: start,
            endTime: end,
            intent: intent,
            confidence: 1.0,
            focusPosition: NormalizedPoint(x: 0.5, y: 0.5),
            focusElement: nil
        )
    }
}
```

**Step 2: Add test file to Xcode project, run tests to verify failure**

Expected: Compilation error — `AdaptiveResponse` not defined

**Step 3: Commit**

```
test: add adaptive spring response tests
```

---

### Task 5: Implement AdaptiveResponse

**Files:**
- Create: `Screenize/Generators/ContinuousCamera/AdaptiveResponse.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj`

**Step 1: Implement adaptive response computation**

```swift
import Foundation
import CoreGraphics

/// Computes adaptive spring response time based on time-to-next-action.
///
/// Since smart generation is post-processing, we can look ahead in the intent
/// timeline to know when the next meaningful action occurs. Camera moves faster
/// when the next action is imminent, slower when there's plenty of time.
enum AdaptiveResponse {

    /// Compute spring response time based on time until next action.
    static func compute(
        timeToNextAction: TimeInterval?,
        settings: DeadZoneSettings
    ) -> CGFloat {
        guard let timeToNext = timeToNextAction else {
            return settings.maxResponse
        }

        if timeToNext <= settings.responseFastThreshold {
            return settings.minResponse
        }
        if timeToNext >= settings.responseSlowThreshold {
            return settings.maxResponse
        }

        // Linear interpolation between thresholds
        let progress = (timeToNext - settings.responseFastThreshold)
            / (settings.responseSlowThreshold - settings.responseFastThreshold)
        return settings.minResponse + CGFloat(progress) * (settings.maxResponse - settings.minResponse)
    }

    /// Find the start time of the next meaningful action after the given time.
    /// Skips idle and reading spans since they don't require camera repositioning.
    static func findNextActionTime(
        after time: TimeInterval,
        intentSpans: [IntentSpan]
    ) -> TimeInterval? {
        for span in intentSpans {
            guard span.startTime > time else { continue }
            switch span.intent {
            case .idle, .reading:
                continue
            default:
                return span.startTime
            }
        }
        return nil
    }
}
```

**Step 2: Add file to Xcode project, run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/AdaptiveResponseTests 2>&1 | grep -E "(Test Case|Executed)" | tail -10`
Expected: All tests pass

**Step 3: Commit**

```
feat: implement AdaptiveResponse for time-to-next-action spring speed
```

---

### Task 6: Rewrite SpringDamperSimulator Position Targeting

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift`

This is the core change. The `simulate()` method signature gains an `intentSpans` parameter. Position targeting changes from "always cursor" to dead zone + adaptive response.

**Step 1: Update simulate() signature and targeting logic**

Changes to `simulate()`:
1. Add `intentSpans: [IntentSpan]` parameter
2. Start position at (0.5, 0.5) instead of first cursor position
3. Remove velocity lookahead block (lines 63-85)
4. Replace cursor-tracking target (lines 134-147) with dead zone target
5. Compute adaptive response per tick

Key code replacements:

**Initial state** (replace lines 30-36):
```swift
var state = CameraState(
    positionX: 0.5,
    positionY: 0.5,
    zoom: initialZoom
)
```

**Remove** the `previousCursorPos` variable (line 50) and entire velocity lookahead block (lines 63-85). Keep `rawCursorPos` as `cursorPos`.

**Add intent span index tracking** (after zoom variables, ~line 50):
```swift
var intentIndex = 0
```

**Replace position spring target** (replace lines 134-147):
```swift
// Advance intent span index
while intentIndex + 1 < intentSpans.count
        && intentSpans[intentIndex].endTime <= t {
    intentIndex += 1
}

// Determine if currently typing
let isTyping: Bool
if intentIndex < intentSpans.count {
    if case .typing = intentSpans[intentIndex].intent {
        isTyping = true
    } else {
        isTyping = false
    }
} else {
    isTyping = false
}

// Dead zone targeting
let posTarget = DeadZoneTarget.compute(
    cursorPosition: cursorPos,
    cameraCenter: NormalizedPoint(x: state.positionX, y: state.positionY),
    zoom: state.zoom,
    isTyping: isTyping,
    settings: settings.deadZone
)

// Adaptive spring response
let timeToNext = AdaptiveResponse.findNextActionTime(
    after: t,
    intentSpans: intentSpans
)
let adaptiveResponse = AdaptiveResponse.compute(
    timeToNextAction: timeToNext,
    settings: settings.deadZone
)

let posOmega = 2.0 * .pi / max(0.001, adaptiveResponse)
let posDamping = settings.positionDampingRatio

let (newX, newVX) = springStep(
    current: state.positionX, velocity: state.velocityX,
    target: posTarget.x,
    omega: posOmega, zeta: posDamping, dt: CGFloat(dt)
)
let (newY, newVY) = springStep(
    current: state.positionY, velocity: state.velocityY,
    target: posTarget.y,
    omega: posOmega, zeta: posDamping, dt: CGFloat(dt)
)
```

**Step 2: Update doc comment for simulate()**

Update to reflect dead zone architecture instead of "cursor-driven."

**Step 3: Run build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: Build errors in callers (ContinuousCameraGenerator, tests) — fixed in next tasks

**Step 4: Commit**

```
feat: rewrite SpringDamperSimulator with dead zone targeting
```

---

### Task 7: Update ContinuousCameraGenerator

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraGenerator.swift`

**Step 1: Pass intentSpans to simulator, remove MicroTracker**

Changes:
1. Pass `intentSpans` to `SpringDamperSimulator.simulate()`
2. Remove Step 6 (applyIdleRecentering call) — pipe rawSamples directly to zoom intensity
3. Update pipeline doc comment (remove step 6, renumber)

Replace Step 5 call (line 63-68):
```swift
// Step 5: Simulate camera path with dead zone targeting
let rawSamples = SpringDamperSimulator.simulate(
    cursorPositions: effectiveMouseData.positions,
    zoomWaypoints: waypoints,
    intentSpans: intentSpans,
    duration: duration,
    settings: settings
)
```

Remove Step 6 entirely (lines 70-75). Change line 78-79:
```swift
// Step 6: Apply post-hoc zoom intensity directly to samples
let samples = Self.applyZoomIntensity(
    to: rawSamples, intensity: settings.zoomIntensity
)
```

Remove or keep the `applyIdleRecentering` method (it's private, can be deleted for cleanliness).

**Step 2: Run build**

Expected: Build succeeds (test compilation may still fail — fixed in Task 8)

**Step 3: Commit**

```
feat: remove MicroTracker from pipeline, pass intentSpans to simulator
```

---

### Task 8: Update Existing Tests

**Files:**
- Modify: `ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift`
- Modify: `ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift`
- Modify: `ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift`

**Step 1: Update SpringDamperSimulatorTests**

All calls to `SpringDamperSimulator.simulate()` need the new `intentSpans:` parameter. Add empty array `intentSpans: []` to each call as the simplest fix — with no intent spans, adaptive response defaults to maxResponse.

Also update `test_simulate_startPosition_matchesFirstCursorPosition`:
- Old: asserts first sample matches first cursor position
- New: asserts first sample is at (0.5, 0.5) — the new start position

Update `test_settings_defaultValues` in WaypointGeneratorTests:
- `positionDampingRatio` → 1.0
- `positionResponse` → 0.35
- Remove `positionLookahead` assertion

**Step 2: Update ContinuousCameraGeneratorTests**

If any tests reference MicroTracker behavior or the old pipeline step count, update accordingly.

**Step 3: Run full test suite**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | grep -E "(Test Case.*passed|Test Case.*failed|Executed)" | tail -20`
Expected: All tests pass

**Step 4: Commit**

```
test: update existing tests for dead zone architecture
```

---

### Task 9: Build Verification + Final Cleanup

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift` (remove unused `micro` property if desired)

**Step 1: Full build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 2: Full test suite**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | grep -E "(Test Case.*failed|Executed)" | tail -5`
Expected: All tests pass, 0 failures

**Step 3: Lint**

Run: `./scripts/lint.sh 2>&1 | tail -10`
Expected: No new violations

**Step 4: Commit any cleanup**

```
chore: cleanup unused MicroTracker references in settings
```
