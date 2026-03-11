# Spring Target Segments Design

## Problem

Segment-based smart generation produces poor quality results:
- IntentClassifier merges multiple distinct events into overly broad segments (e.g., 3 clicks across different screen areas become one 4-second "navigating" segment)
- Easing curves (easeInOut/easeOut) feel sluggish compared to continuous mode's spring physics
- Camera barely appears to move because long segments + slow easing = minimal visual feedback

## Solution: Spring Target Segments

Each segment defines a **spring target** (the `endTransform`). The camera moves toward the target using spring physics, preserving velocity across segment boundaries for natural motion continuity.

## Design

### 1. Finer Segment Splitting

**Current:** IntentClassifier merges clicks within 2.0s into "navigating" spans, producing giant segments.

**Change:** Split at the event level. Each distinct user action (click, typing session start, scroll burst) generates its own segment. Only merge when events occur at the same position (within a distance threshold) AND within a short time window.

**Merge criteria (both must be true):**
- Normalized distance between events < 0.05 (same area)
- Time gap < 0.5s (rapid repetition, e.g., double-click)

**Affected files:**
- `SegmentPlanner.swift` — scene merging logic (`mergeShortScenes`)
- Possibly `IntentClassifier.swift` — reduce aggressive span merging

### 2. Spring-Based Interpolation

**Current:** Segments use `interpolation: .easeInOut` to blend `startTransform → endTransform`.

**Change:** Segments use spring physics. The `endTransform` becomes the spring's rest position. At segment start, the spring inherits velocity from the previous segment's end state.

**Spring parameters (matching continuous mode):**
- Position: `dampingRatio: 0.90, response: 0.35`
- Zoom: `dampingRatio: 0.90, response: 0.55`

**No `transitionToNext` gap:** When a new segment starts, the spring target simply changes. Velocity carries over, creating seamless transitions without explicit transition durations.

**Affected files:**
- `SegmentPlanner.swift` — set `interpolation: .spring(dampingRatio: 0.90, response: 0.35)`, set `transitionToNext.duration: 0`
- `SegmentCameraGenerator.swift` — after planning segments, run spring simulation to pre-compute `continuousTransforms` for each segment

### 3. Pre-computed Spring Simulation

After `SegmentPlanner` produces segments, run a spring simulation across all segments to generate per-frame `continuousTransforms`. This is similar to how continuous mode works but anchored to editable segment targets.

**Process:**
1. Initialize spring state: position = first segment's startTransform, velocity = 0
2. For each frame (at tickRate 60 Hz):
   - Determine active segment → spring target = segment's `endTransform`
   - Step spring simulation (position + zoom)
   - Record `TimedTransform(time, transformValue)`
3. Store results in each segment's `continuousTransforms` array

**When user edits a segment** (moves target, changes duration), re-run simulation from that segment onward.

**Affected files:**
- `SegmentCameraGenerator.swift` — add spring simulation pass after segment planning
- `CameraSegment` already has `continuousTransforms: [TimedTransform]?` field

### 4. Rendering Integration

**Current:** `FrameEvaluator` interpolates between `startTransform` and `endTransform` using the segment's easing curve.

**Change:** When `continuousTransforms` is populated, look up the nearest pre-computed transform instead of interpolating. This path already exists for continuous mode segments.

**Affected files:**
- `FrameEvaluator` — should already handle `continuousTransforms` lookup; verify and fix if needed

## Example: Test Recording

Recording: 8 seconds, 5 clicks at different screen positions.

**Before (current):**
```
[idle 0.37s][navigating 3.98s][typing 2.58s][reading 1.11s]
4 segments, easeInOut, camera barely moves
```

**After (spring targets):**
```
[idle][click1][click2][click3][click4][click5][idle]
7 segments, spring physics, camera snaps to each click with natural motion
Velocity carries between segments for fluid transitions
```

## Non-Goals

- Changing continuous mode behavior
- Modifying the timeline UI or segment editor
- Adding new track types
- Changing cursor or keystroke track generation
