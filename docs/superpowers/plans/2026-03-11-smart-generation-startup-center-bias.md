# Smart Generation Startup Center Bias Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make smart generation start from the screen center by default, then release into normal tracking on the first meaningful action.

**Architecture:** Add a small startup policy helper that computes initial camera center and startup release timing from early mouse and event data. Keep `WaypointGenerator` and the existing continuous camera physics pipeline intact; only the simulator's startup state and early position targeting change.

**Tech Stack:** Swift, XCTest, continuous camera generator, spring-damper simulation

---

## File Structure

- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`
  Add startup-policy configuration so thresholds live beside existing dead-zone settings.
- Create: `Screenize/Generators/ContinuousCamera/StartupCameraPolicy.swift`
  Pure helper that detects the first meaningful action and computes startup bias state.
- Modify: `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift`
  Use startup policy output for initial center and early-tick target selection.
- Test: `ScreenizeTests/Generators/ContinuousCamera/StartupCameraPolicyTests.swift`
  Unit coverage for action detection, jitter rejection, and release timing.
- Modify: `ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift`
  Integration coverage for centered startup and fast release.
- Modify: `ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift`
  End-to-end coverage that generated timelines begin with a centered establishing shot in quiet-start scenarios.

## Chunk 1: Startup Policy Unit

### Task 1: Add startup settings to continuous camera types

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`

- [ ] **Step 1: Write the failing test**

Add a startup-settings assertion in `StartupCameraPolicyTests.swift` that verifies default configuration exists and prefers center-bias behavior.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/StartupCameraPolicyTests/test_defaultSettings_defineStartupBias test`
Expected: FAIL because startup policy types do not exist.

- [ ] **Step 3: Write minimal implementation**

Add a focused startup settings type, for example:

```swift
struct StartupCameraSettings {
    var enabled: Bool = true
    var initialCenter = NormalizedPoint(x: 0.5, y: 0.5)
    var deliberateMotionDistance: CGFloat = 0.08
    var deliberateMotionWindow: TimeInterval = 0.35
    var jitterDistance: CGFloat = 0.02
}
```

Wire it into `ContinuousCameraSettings`.

- [ ] **Step 4: Run test to verify it passes**

Run the same targeted test.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift ScreenizeTests/Generators/ContinuousCamera/StartupCameraPolicyTests.swift
git commit -m "feat: add startup camera settings"
```

### Task 2: Build startup policy helper

**Files:**
- Create: `Screenize/Generators/ContinuousCamera/StartupCameraPolicy.swift`
- Test: `ScreenizeTests/Generators/ContinuousCamera/StartupCameraPolicyTests.swift`

- [ ] **Step 1: Write the failing tests**

Add tests for:

- no actions -> bias remains centered with no release time
- click at `t=0.12` -> release time equals click time
- drag start -> release time equals drag start
- typing intent in early spans -> release time equals typing start
- small initial cursor jitter -> no release
- large early cursor movement -> release at first threshold-crossing timestamp

Example helper shape:

```swift
func test_clickReleasesStartupBiasImmediately() {
    let policy = StartupCameraPolicy.resolve(
        cursorPositions: positions,
        clickEvents: [ClickEventData(...)],
        keyboardEvents: [],
        dragEvents: [],
        intentSpans: [],
        settings: settings
    )

    XCTAssertEqual(policy.initialCenter, NormalizedPoint(x: 0.5, y: 0.5))
    XCTAssertEqual(policy.releaseTime, 0.12, accuracy: 0.001)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/StartupCameraPolicyTests test`
Expected: FAIL because `StartupCameraPolicy` does not exist.

- [ ] **Step 3: Write minimal implementation**

Implement a pure helper that returns a resolved startup state:

```swift
struct ResolvedStartupCameraState {
    let initialCenter: NormalizedPoint
    let releaseTime: TimeInterval?
}
```

Detection order:

1. earliest click time
2. earliest drag start
3. earliest typing span start
4. earliest deliberate cursor movement in the startup window

Ignore sub-threshold jitter.

- [ ] **Step 4: Run test to verify it passes**

Run the same targeted test command.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/ContinuousCamera/StartupCameraPolicy.swift ScreenizeTests/Generators/ContinuousCamera/StartupCameraPolicyTests.swift
git commit -m "feat: add startup camera policy"
```

## Chunk 2: Simulator Integration

### Task 3: Start simulator from policy center

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift`
- Modify: `ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift`

- [ ] **Step 1: Write the failing test**

Replace the current first-sample expectation that matches `cursorPositions[0]` with a quiet-start test that expects the first sample center to be `(0.5, 0.5)`.

Example:

```swift
func test_simulate_quietStart_beginsAtScreenCenter() {
    let positions = [
        MousePositionData(time: 0, position: NormalizedPoint(x: 0.1, y: 0.9))
    ]

    let result = SpringDamperSimulator.simulate(
        cursorPositions: positions,
        zoomWaypoints: [],
        intentSpans: [],
        duration: 1.0,
        settings: defaultSettings
    )

    XCTAssertEqual(result.first?.transform.center.x, 0.5, accuracy: 0.001)
    XCTAssertEqual(result.first?.transform.center.y, 0.5, accuracy: 0.001)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/SpringDamperSimulatorTests/test_simulate_quietStart_beginsAtScreenCenter test`
Expected: FAIL because simulator currently starts from first cursor position.

- [ ] **Step 3: Write minimal implementation**

Change simulator startup to resolve initial center through `StartupCameraPolicy`. Use `releaseTime` to keep positional targeting centered until release, then fall back to current dead-zone logic.

- [ ] **Step 4: Run test to verify it passes**

Run the same targeted test.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift
git commit -m "feat: bias smart generation startup to center"
```

### Task 4: Verify immediate release behavior

**Files:**
- Modify: `ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift`

- [ ] **Step 1: Write the failing test**

Add tests proving startup bias releases quickly:

- immediate click near `t=0`
- early deliberate cursor move without click

Check that samples shortly after release start moving toward the live target instead of staying centered.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/SpringDamperSimulatorTests test`
Expected: FAIL on the new release tests until release timing is honored.

- [ ] **Step 3: Write minimal implementation**

Honor startup release timing inside the per-tick target selection path. Before release, force `effectivePosTarget` to startup center except when zoom-transition logic must still use waypoint center. After release, restore current dead-zone and adaptive-response behavior.

- [ ] **Step 4: Run test to verify it passes**

Run the same test suite.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift
git commit -m "feat: release startup center bias on first action"
```

## Chunk 3: Generator-Level Regression Coverage

### Task 5: Update generator expectations for establishing shot

**Files:**
- Modify: `ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift`

- [ ] **Step 1: Write the failing test**

Update the fixture-based startup assertion to require a centered opening shot when the source fixture does not begin with a meaningful action.

Example:

```swift
XCTAssertEqual(first.transform.center.x, 0.5, accuracy: 0.05)
XCTAssertEqual(first.transform.center.y, 0.5, accuracy: 0.05)
```

Add a second generator-level test with an immediate click fixture or synthetic input proving that fast-start interactions still release early.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/ContinuousCameraGeneratorTests test`
Expected: FAIL until generator output reflects startup policy.

- [ ] **Step 3: Write minimal implementation**

If needed, thread click / keyboard / drag inputs more explicitly into simulator startup resolution. Keep all logic in the continuous camera layer; do not add ad-hoc behavior in `EditorViewModel`.

- [ ] **Step 4: Run test to verify it passes**

Run the same generator test suite.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift
git commit -m "test: cover centered smart generation startup"
```

### Task 6: Full verification and cleanup

**Files:**
- Modify: any touched files from previous tasks if verification exposes gaps

- [ ] **Step 1: Run focused camera tests**

Run:

```bash
xcodebuild test -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' \
  -only-testing:ScreenizeTests/StartupCameraPolicyTests \
  -only-testing:ScreenizeTests/SpringDamperSimulatorTests \
  -only-testing:ScreenizeTests/ContinuousCameraGeneratorTests
```

Expected: PASS.

- [ ] **Step 2: Run full build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run lint**

Run: `./scripts/lint.sh`
Expected: exit code 0.

- [ ] **Step 4: Commit final verification fixes**

```bash
git add Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift \
  Screenize/Generators/ContinuousCamera/StartupCameraPolicy.swift \
  Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift \
  ScreenizeTests/Generators/ContinuousCamera/StartupCameraPolicyTests.swift \
  ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift \
  ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift
git commit -m "chore: verify smart generation startup center bias"
```

Plan complete and saved to `docs/superpowers/plans/2026-03-11-smart-generation-startup-center-bias.md`. Ready to execute?
