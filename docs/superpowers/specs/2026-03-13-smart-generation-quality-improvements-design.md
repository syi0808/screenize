# Smart Generation Quality Improvements

## Overview

Two improvements to the smart generation pipeline to make camera behavior more natural and context-aware.

## Problem 1: Segment-Based — Cursor Exits Viewport

### Current Behavior

In `SegmentSpringSimulator`, the spring response is adapted based on segment duration only:

```swift
adaptedResponse = max(baseResponse, duration * 0.4~0.45)
```

This ignores cursor movement speed. When the cursor moves fast at the start of a segment, the camera reacts too slowly and the cursor leaves the visible viewport before the camera catches up. This breaks visual continuity.

### Solution: Cursor Speed-Coupled Spring Response

Couple the spring response to cursor velocity measured at the beginning of each segment.

**Architecture — pre-compute speeds before simulation:**
- `SegmentCameraGenerator` already wraps `mouseData` in `SmoothedMouseDataSource` at step 1 (stored as `effectiveMouseData`)
- Cursor speeds are computed from `effectiveMouseData` after segments are planned (step 4) and before simulation (step 5)
- Speeds are passed as `[UUID: CGFloat]` dictionary (segment ID → speed in normalized units/sec)
- `simulate()` signature changes: `simulate(segments:config:cursorSpeeds:)` with `cursorSpeeds` defaulting to `[:]` for backward compatibility

**Cursor speed calculation:**
```swift
// In SegmentCameraGenerator, between step 4 and step 5
func cursorSpeeds(for segments: [CameraSegment], mouseData: MouseDataSource) -> [UUID: CGFloat]
```
- `mouseData` parameter uses `MouseDataSource` protocol (both raw and smoothed conform)
- For each segment, sample mouse positions within `segment.startTime ..< min(segment.startTime + 0.3, segment.endTime)`
- Compute **net displacement** velocity: straight-line distance from first to last sample position, divided by sample duration
  - Net displacement (not path length) — we care about how far the cursor moves from its starting point, which determines how fast the camera needs to reposition
- If segment has < 2 samples in the window, return 0 (no speed data)

**Response factor mapping:**
| Cursor Speed (units/s) | Factor | Effect |
|------------------------|--------|--------|
| < 0.3 (slow) | 1.0 | No change from current behavior |
| 0.3 – 0.8 (medium) | 1.0 → 0.5 (linear interpolation) | Progressively faster response |
| > 0.8 (fast) | 0.5 | Maximum speedup (2x faster) |

**Adapted response formula:**
```
factor = cursorSpeeds[segment.id] mapped through table above (default 1.0 if missing)
adaptedResponse = max(baseResponse * factor, minResponse)
```
- `minResponse` floor (0.15s) prevents unnaturally snappy motion
- Factor multiplies the existing duration-based response, preserving current tuning as baseline

**Changes:**
- `SegmentCameraGenerator.generate()` — compute cursor speeds from `effectiveMouseData`, pass to `simulate()`
- `SegmentSpringSimulator.simulate()` — add `cursorSpeeds: [UUID: CGFloat] = [:]` parameter, apply factor in per-segment response calculation
- New function in `SegmentCameraGenerator`: `cursorSpeeds(for:mouseData:) -> [UUID: CGFloat]`
- No changes to spring step physics or segment structure

## Problem 2: Continuous — Unnecessary ZoomOut Between Clicks

### Current Behavior

`WaypointGenerator` generates waypoints per intent span independently. When idle/reading spans occur between click spans, they emit zoom=1.0 waypoints. This causes repetitive zoomIn→zoomOut→zoomIn cycles even when clicks are close together or in rapid succession.

### Solution: Post-Processing Zoom Transition Optimizer

Add a post-processing pass after waypoint generation that detects and removes unnecessary zoomOut waypoints.

**Waypoint classification:**
- A waypoint is **"zoomIn"** if its `source` intent is an active intent: `.clicking`, `.navigating`, `.typing(any)`, `.dragging(any)`, `.scrolling`
- A waypoint is **"zoomOut"** if its `source` intent is a passive intent: `.idle`, `.reading`, `.switching`
- Classification is based on `CameraWaypoint.source` (UserIntent), ignoring associated values for this classification

**Detection pattern:** Three consecutive waypoints where: first is zoomIn, second is zoomOut, third is zoomIn.

**Decision criteria for removing the intermediate zoomOut:**

| Condition | Action |
|-----------|--------|
| Distance < `nearThreshold` (0.15 normalized) | Remove zoomOut |
| Distance < `farThreshold` (0.35) AND time < `quickThreshold` (1.5s) | Remove zoomOut |
| Distance ≥ `farThreshold` AND time ≥ `quickThreshold` | Reduce zoomOut: set zoom to `max(firstWaypoint.targetZoom * 0.7, 1.0)` |

- **Distance**: normalized Euclidean distance between first and third waypoint centers
- **Time**: time gap between first and third waypoint timestamps
- `firstWaypoint.targetZoom * 0.7` means "zoom out 30% from the previous active zoom, but never below 1.0"

**Intent transition guard — zoom level similarity check:**
- Only remove zoomOut when the flanking zoomIn waypoints have **similar target zoom levels**: `abs(first.targetZoom - third.targetZoom) < 0.3`
- This replaces a rigid category check — if zoom levels are similar, it's safe to maintain zoom regardless of intent type
- If zoom levels differ significantly (e.g., clicking at 1.8 → typing at 2.2), keep the zoomOut to allow a natural transition between zoom ranges

**When zoomOut is removed:**
- Delete the zoomOut waypoint from the array entirely
- The spring simulator naturally interpolates between the two remaining zoomIn waypoints, producing a smooth pan at the maintained zoom level
- No replacement waypoint needed

**Sequential triplet evaluation:**
- Scan from index 0 upward
- After removing a zoomOut at index `i`, the next evaluation starts at index `i-1` (the previous zoomIn is now adjacent to the next zoomIn, which may form a new triplet with the following waypoint)
- This correctly handles 4+ alternating waypoints (zoomIn, zoomOut, zoomIn, zoomOut, zoomIn → all intermediate zoomOuts evaluated)

**Edge cases:**
- Last click in sequence (no following zoomIn): skip — no triplet to evaluate
- Single isolated click: no triplet exists, unaffected

**Placement in pipeline:**
```swift
// In WaypointGenerator.generate()
var result = sortAndCoalesce(waypoints)
optimizeZoomTransitions(&result)
return result
```
- Called **after** `sortAndCoalesce()` so waypoints are already sorted by time and deduplicated
- `optimizeZoomTransitions` operates on the final sorted array

**Implementation:**
```swift
// In WaypointGenerator
private static func optimizeZoomTransitions(_ waypoints: inout [CameraWaypoint])
```
- Thresholds defined as static constants for easy tuning

## Design Constraints

- Both changes are additive — no modification to existing spring physics or core waypoint generation logic
- Threshold values are initial estimates; will need tuning with real recordings
- Both features should be independently toggleable if needed for A/B comparison
