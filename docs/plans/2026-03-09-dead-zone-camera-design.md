# Dead Zone Camera Design

**Date:** 2026-03-09
**Status:** Approved
**Supersedes:** 2026-03-08-cursor-driven-camera-design.md (always-follow approach)

## Problem

The cursor-driven camera architecture (commit `590efc2`) always tracks cursor position via a fast spring (0.12s). This causes:

1. **Jitter** — every micro-tremor of the cursor becomes camera movement
2. **Over-aggressive centering** — camera constantly tries to center cursor, feels unnatural
3. **Static-like movement** — underdamped spring (0.80) creates oscillation on small movements
4. **No stability** — camera never holds still, always chasing cursor

The old CursorFollowController was better because it only moved when cursor exited the viewport, used debouncing and partial correction. But we want to keep the continuous physics engine rather than regressing to segment-based pans.

## Solution

**Viewport-aware dead zone targeting + adaptive spring response.**

Keep the 60Hz spring-damper physics engine but change WHEN and HOW FAST the camera moves:
- **Dead zone**: camera stays still when cursor is within safe area of viewport
- **Partial correction**: when camera moves, it doesn't center cursor — just ensures visibility
- **Adaptive response**: spring speed depends on time until next action (post-hoc look-ahead)

## Architecture

### Dead Zone Targeting

```
viewport size = 1.0 / zoom (per axis)
safe zone = 75% of viewport (center region) — 60% during typing
trigger zone = remaining 25% (edges)
gradient band = 10% transition between safe and trigger

Per tick:
  cursor in safe zone   → target = current camera position (hold still)
  cursor in gradient    → target = blend(hold, correction) by gradient progress
  cursor in trigger zone → target = partial correction position
  cursor outside viewport → target = pull cursor back inside
```

### Partial Correction

When cursor enters trigger zone:
1. `idealCenter` = position that centers cursor in viewport
2. `minimalCenter` = position that places cursor at safe zone boundary (minimum movement)
3. `target = lerp(minimalCenter, idealCenter, correctionFraction)`
   - Default correctionFraction = 0.6
   - During typing: correctionFraction = 0.8

### Adaptive Spring Response

Since this is post-processing, we know the full event timeline. Spring response scales with time until next meaningful action:

```
time to next action ≥ 2.0s  → response = 0.5s (slow, deliberate)
time to next action 0.5-2.0s → response = lerp(0.2s, 0.5s) proportionally
time to next action < 0.5s  → response = 0.2s (arrive quickly)
no next action               → response = 0.5s (slow)
```

"Meaningful action" = click, typing start, drag start, app switch (from IntentSpan).
Idle and reading spans are skipped when searching for next action.

Spring damping is always **critically damped (1.0)** — no overshoot, no oscillation.

### Typing Caret Tracking

During typing IntentSpans:
- Track **caret position** (from UIStateSample.caretX/Y) instead of mouse cursor
- Fallback to mouse cursor if caret data unavailable
- Safe zone shrinks from 75% → 60% (more responsive to line changes)
- correctionFraction increases from 0.6 → 0.8

### Start Position

1. Camera starts at **(0.5, 0.5), zoom 1.0x**
2. First meaningful IntentSpan triggers move+zoom to that location
3. Movement speed follows adaptive response rules

### Zoom 1.0x Behavior

When zoom = 1.0x, skip dead zone logic entirely. Position target is always (0.5, 0.5) since the entire screen is visible.

## What Gets Removed

- **MicroTracker call** in ContinuousCameraGenerator (Step 6) — dead zone makes idle re-centering unnecessary
- **Velocity lookahead** in SpringDamperSimulator — amplifies noise, unnecessary with dead zones
- **Underdamped position spring** — replaced with critical damping (1.0)

## What Gets Kept

- IntentClassifier, WaypointGenerator, ShotPlanner — unchanged
- Zoom spring (0.55s response, 0.90 damping) — unchanged
- SmoothedMouseDataSource (Catmull-Rom only) — unchanged
- SpringDamperSimulator physics engine — kept, targeting logic changed
- MicroTracker.swift — file kept, pipeline call removed
- Soft boundary clamping — kept

## Data Flow

```
Cursor → Catmull-Rom Resample
              ↓
         Dead Zone Check (viewport-aware)
              │
         safe zone  → target = current camera center (hold)
         gradient   → target = blend(hold, correction)
         trigger    → target = partial correction (0.6 / 0.8)
         outside    → target = pull inside
              │
              ↓
         Adaptive Spring (response = f(time to next action), damping = 1.0)
              ↓
         Boundary Clamp
              ↓
         [TimedTransform] at 60Hz

Intent Classification (parallel)
    → Zoom waypoints (unchanged)
    → Zoom spring (unchanged)
    → Also provides IntentSpans for adaptive response lookup
```

## Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| safeZoneFraction | 0.75 | 75% of viewport is safe (no camera movement) |
| safeZoneFractionTyping | 0.60 | 60% during typing (more responsive) |
| gradientBandWidth | 0.10 | 10% smooth transition at safe zone boundary |
| correctionFraction | 0.60 | Partial correction (don't center cursor) |
| correctionFractionTyping | 0.80 | More aggressive during typing |
| positionDampingRatio | 1.0 | Critically damped (no overshoot) |
| minResponse | 0.20 | Fastest spring (next action imminent) |
| maxResponse | 0.50 | Slowest spring (next action far away) |
| responseFastThreshold | 0.5s | Below this time-to-action → min response |
| responseSlowThreshold | 2.0s | Above this time-to-action → max response |

## Files Modified

| File | Change |
|------|--------|
| `SpringDamperSimulator.swift` | Dead zone target logic, adaptive response, remove velocity lookahead |
| `ContinuousCameraTypes.swift` | Add dead zone parameters, remove positionLookahead, damping → 1.0 |
| `ContinuousCameraGenerator.swift` | Remove MicroTracker call, pass IntentSpans to simulator, start at (0.5, 0.5) |
| `WaypointGeneratorTests.swift` | Update default value assertions |
