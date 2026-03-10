# Smart Generation Startup Center Bias Design

**Date:** 2026-03-11

**Goal:** Make smart generation start from the screen center by default, while still allowing immediate tracking once the first meaningful action begins.

## Context

Screenize's smart generation pipeline already defines a default waypoint at `t=0` with `center=(0.5, 0.5)` and `zoom=1.0`. In practice, that establishing shot is short-lived because `SpringDamperSimulator` initializes the camera center from `cursorPositions[0]`.

That makes recordings feel unstable when the cursor happens to begin near an edge or corner. The desired behavior is more conservative: start from center in most cases, but do not delay or blunt obvious user intent once recording activity actually begins.

## Scope

In scope:

- Add a startup camera policy that prefers the centered opening shot.
- Release that startup bias on the first meaningful action.
- Keep the existing dead-zone, urgency, and zoom-coupling behavior after release.
- Add tests for startup policy detection and simulator integration.

Out of scope:

- Redesigning intent classification beyond what is needed to detect startup release.
- Adding new UI for this behavior in the current iteration.
- Refactoring unrelated smart generation pipeline stages.

## Recommended Approach

Introduce a small startup policy layer in the continuous camera pipeline.

This layer should compute two things before simulation begins:

1. The initial camera center.
2. The time when startup bias should be released.

The policy starts at screen center and keeps positional targeting center-biased until the first meaningful action occurs. Once released, the simulator falls back to the existing cursor-driven dead-zone behavior without changing the rest of the camera architecture.

This keeps the change tightly scoped and avoids degrading the current camera feel after the opening moment.

## Design

### 1. Startup Bias Rule

Smart generation should begin with a centered establishing shot:

- Initial camera center = `NormalizedPoint(x: 0.5, y: 0.5)`
- Initial zoom continues to follow the first waypoint / existing zoom behavior

The startup bias remains active until the first meaningful action. While it is active, the simulator should not let the initial raw cursor position pull the camera off-center just because the pointer started near an edge.

### 2. Meaningful Action Definition

Startup bias should release on the first meaningful action. The recommended definition is:

- Any click interaction
- Typing start / typing intent
- Drag start
- A deliberate cursor move that exceeds jitter thresholds

The deliberate move check exists to avoid holding center forever in recordings that start with purposeful pointer motion but no click yet. It should ignore small jitter and pointer settling noise near the start of capture.

### 3. Simulator Integration

The new behavior should be implemented as a thin policy layer around the existing simulator, not a rewrite of the dead-zone system.

Expected flow:

1. `WaypointGenerator` keeps emitting the existing default center waypoint.
2. A startup policy helper inspects early cursor and event data.
3. `SpringDamperSimulator` initializes from the startup policy instead of directly using `cursorPositions[0]`.
4. While startup bias is still active, position targeting stays center-biased.
5. Once release time is reached, normal dead-zone targeting resumes unchanged.

This limits the code change to startup state calculation and the simulator's early-tick target selection.

### 4. Behavioral Guarantees

The change should preserve the current feel outside the opening window:

- If recording starts quietly, the opening shot stays near center.
- If recording starts with an obvious click, typing, or drag, startup bias releases immediately.
- If recording starts with a strong cursor movement, startup bias releases once that movement crosses the deliberate-motion threshold.
- Zoom transitions continue to use current waypoint urgency and zoom-pan coupling rules.

The policy should affect position tracking only. Zoom logic should remain structurally unchanged to keep regressions localized.

## File Impact

Primary files:

- `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift`
- `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`

Likely support files:

- `Screenize/Generators/ContinuousCamera/StartupCameraPolicy.swift` (new helper for startup detection and release timing)

Tests:

- `ScreenizeTests/Generators/ContinuousCamera/StartupCameraPolicyTests.swift`
- `ScreenizeTests/Generators/ContinuousCamera/SpringDamperSimulatorTests.swift`
- `ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift`

## Risks

- If the deliberate-motion threshold is too low, startup bias will release from normal capture jitter and fail to improve the opening shot.
- If the threshold is too high, the camera may feel late to respond in recordings that begin with pointer movement but no click.
- Applying the policy to zoom as well as position would increase regression risk; the design intentionally avoids that.

## Verification

Manual verification:

- Recording with cursor starting in a corner but no immediate action should open centered.
- Recording with an immediate click or typing action should begin tracking without visible delay.
- Recording with only idle motion should stay visually stable at the start.

Code verification:

- Run startup policy unit tests for action detection and jitter rejection.
- Run simulator tests covering centered startup, immediate release, and no-action scenarios.
- Build: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`
- Lint: `./scripts/lint.sh`

## Acceptance Criteria

- Smart generation no longer starts by immediately snapping camera center to the first raw cursor position in ordinary cases.
- The opening shot stays centered until the first meaningful action.
- Immediate user intent still releases tracking without a forced intro hold.
- Existing post-start camera behavior remains unchanged.
