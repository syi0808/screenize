# Transition/Hold Segment Split

## Overview

Split camera segments into separate transition (moving) and hold (stationary) segments so the camera arrives at the target position before the user starts interacting, preventing the cursor from leaving the viewport.

## Problem

Currently `SegmentPlanner.buildSegments()` creates one `.manual(start, end, easeInOut)` segment per shot plan. The segment spans the entire intent duration, so the camera eases in and out across the full time range. When the cursor moves fast at the start, the camera lags behind because it's spreading the transition across too much time.

## Design Principles

- Camera segments are user-facing, editable units — no hidden internal logic
- Each segment should have a single clear purpose: either "move to target" or "stay at target"
- Spring-based animation for all camera movement (via `SegmentSpringSimulator`)
- Continuous camera segments are black-box — internal logic is acceptable there

## Solution

### Segment Split Logic in `SegmentPlanner.buildSegments()`

For each shot plan, compare `previousEnd` transform with the current target transform:

**No split needed (hold only):**
- When distance between `previousEnd.center` and `target.center` is below `splitDistanceThreshold` (0.05 normalized units) AND zoom difference is below `splitZoomThreshold` (0.1)
- Create a single hold segment spanning the full intent duration

**Split needed (transition + hold):**
- When distance or zoom difference exceeds thresholds
- Create a transition segment followed by a hold segment
- Exception: if the hold segment would be shorter than `minHoldDuration` (0.1s), create transition-only (no hold) — transition endTime extends to intent span's endTime

### Transition Segment

- `kind: .manual(startTransform: previousEnd, endTransform: target, interpolation: .easeInOut)`
- Duration determined by **cursor travel time**: how long the cursor takes to arrive near the target position in the mouse data
- `startTime`: previous segment's endTime (= intent span's startTime)
- `endTime`: startTime + cursor travel time (clamped)
- `SegmentSpringSimulator` converts this to `.continuous(transforms:)` with spring physics — the short duration naturally produces a fast, responsive spring

### Cursor Travel Time Calculation

New function in `SegmentPlanner`:

```swift
static func cursorTravelTime(
    from startPosition: NormalizedPoint,
    to targetPosition: NormalizedPoint,
    mouseData: MouseDataSource,
    searchStart: TimeInterval,
    searchEnd: TimeInterval
) -> TimeInterval
```

- Scan `mouseData.positions` array (time-sorted `[MousePositionData]`) from `searchStart` forward
- `targetPosition` is the **zoom-intensity-adjusted, clamped center** (same value used for the segment's `endTransform.center`) — this ensures we measure travel time to where the camera actually needs to be
- Find when cursor arrives within `arrivalRadius` (0.08 normalized) of `targetPosition`
- Return elapsed time from `searchStart` to arrival
- Clamp result: `minTransitionDuration (0.15s) ... maxTransitionDuration (0.8s)`
- If cursor never arrives within `searchEnd` (e.g., target is derived from UI element, not cursor): use fallback duration `min(max(distance * fallbackSpeedFactor, minTransitionDuration), maxTransitionDuration)`

### Hold Segment

- `kind: .manual(startTransform: target, endTransform: target, interpolation: .linear)`
- `startTransform == endTransform` → camera target is fixed
- `startTime`: transition segment's endTime
- `endTime`: intent span's endTime

**Spring velocity carry-over:** `SegmentSpringSimulator` carries velocity between segments. When the hold segment starts, residual velocity from the transition causes the camera to slightly overshoot and settle back to target. This is acceptable and produces natural-feeling motion (like a camera arriving and settling). Settling is best-effort — short hold segments may not fully settle, and residual velocity will carry into the next transition segment. This is fine because the next transition will absorb it naturally. No velocity reset is needed.

### MouseDataSource Threading

`SegmentPlanner.plan()` needs access to mouse data for cursor travel time calculation:
- Add `mouseData: MouseDataSource` parameter to `plan()`
- Pass through to `buildSegments(from:zoomIntensity:mouseData:)`
- `SegmentCameraGenerator` already has `effectiveMouseData` — pass it to `plan()`

### First Segment Edge Case

- First segment has no `previousEnd` — currently uses `startTransform = endTransform`
- With split logic: first segment also has no transition needed (same position), so it becomes a hold-only segment
- This matches current behavior

## Changes

- `SegmentPlanner.plan()` — add `mouseData` parameter
- `SegmentPlanner.buildSegments()` — implement split logic with distance/zoom thresholds
- New function: `SegmentPlanner.cursorTravelTime(from:to:mouseData:searchStart:searchEnd:)`
- `SegmentCameraGenerator.generate()` — pass `effectiveMouseData` to `plan()`
- `SegmentSpringSimulator` — no changes needed

## Constants

| Name | Value | Purpose |
|------|-------|---------|
| `splitDistanceThreshold` | 0.05 | Min center distance to trigger split |
| `splitZoomThreshold` | 0.1 | Min zoom difference to trigger split |
| `arrivalRadius` | 0.08 | How close cursor must be to count as "arrived" |
| `minTransitionDuration` | 0.15s | Floor for transition segment duration |
| `maxTransitionDuration` | 0.8s | Ceiling for transition segment duration |
| `minHoldDuration` | 0.1s | Min hold duration; if less, omit hold segment |
| `fallbackSpeedFactor` | 1.0 | seconds per normalized unit for distance-based fallback |
