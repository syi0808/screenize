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

**Cursor speed calculation:**
- Sample mouse positions from `SmoothedMouseDataSource` within the segment's time range
- Compute average velocity (normalized units/sec) over the first ~0.3 seconds of the segment
- This captures the initial cursor speed that the camera needs to match

**Response factor mapping:**
| Cursor Speed (units/s) | Factor | Effect |
|------------------------|--------|--------|
| < 0.3 (slow) | 1.0 | No change from current behavior |
| 0.3 – 0.8 (medium) | 1.0 → 0.5 (linear) | Progressively faster response |
| > 0.8 (fast) | 0.5 | Maximum speedup (2x faster) |

**Adapted response formula:**
```
adaptedResponse = max(baseResponse * factor, minResponse)
```
- `minResponse` floor (e.g., 0.15s) prevents unnaturally snappy motion
- Factor multiplies the existing duration-based response, preserving current tuning as baseline

**Changes:**
- `SegmentSpringSimulator.simulate()` — modify per-segment response calculation
- New function: `cursorSpeed(for:in:) -> CGFloat` — extracts velocity from mouse data for a segment's time range
- No changes to spring step physics or segment structure

## Problem 2: Continuous — Unnecessary ZoomOut Between Clicks

### Current Behavior

`WaypointGenerator` generates waypoints per intent span independently. When idle/reading spans occur between click spans, they emit zoom=1.0 waypoints. This causes repetitive zoomIn→zoomOut→zoomIn cycles even when clicks are close together or in rapid succession.

### Solution: Post-Processing Zoom Transition Optimizer

Add a post-processing pass after waypoint generation that detects and removes unnecessary zoomOut waypoints.

**Detection pattern:** zoomIn → zoomOut → zoomIn triplet in the waypoint sequence.

**Decision criteria for removing the intermediate zoomOut:**

| Condition | Action |
|-----------|--------|
| Distance < `nearThreshold` (0.15 normalized) | Remove zoomOut — maintain zoom + pan |
| Distance < `farThreshold` (0.35) AND time < `quickThreshold` (1.5s) | Remove zoomOut — fast succession override |
| Distance ≥ `farThreshold` AND time ≥ `quickThreshold` | Keep zoomOut (or reduce to 70% of previous zoom instead of full 1.0) |

- **Distance**: normalized Euclidean distance between previous and next click positions
- **Time**: duration of the zoomOut span (previous span end → next span start)

**Edge cases:**
- 3+ consecutive clicks: evaluate pairs sequentially from front to back
- Last click in sequence: keep the trailing zoomOut for natural ending
- Click → typing transition: keep zoomOut since typing uses different zoom levels

**Implementation:**
```
New function: WaypointGenerator.optimizeZoomTransitions(_ waypoints: inout [Waypoint])
```
- Called at the end of `generate()` as a post-processing step
- Existing waypoint generation logic remains unchanged
- Pan waypoints within removed zoomOut spans are preserved for smooth camera movement
- Thresholds defined as constants for easy tuning

## Design Constraints

- Both changes are additive — no modification to existing spring physics or waypoint generation logic
- Threshold values are initial estimates; will need tuning with real recordings
- Both features should be independently toggleable if needed for A/B comparison
