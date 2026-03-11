# Segment-Based Smart Generation Design

## Overview

Add a segment-based smart generation mode alongside the existing ContinuousCamera mode. Instead of producing a single CameraSegment with 60Hz physics-simulated samples, this mode generates multiple discrete CameraSegments with explicit start/end transforms and easing curves — editable by the user in the timeline.

## Pipeline

Reuses the existing analysis layer (EventTimeline, IntentClassifier), then diverges:

```
EventTimeline → IntentClassifier → [shared]
    ↓
SegmentPlanner (new)
    1. Merge IntentSpans: coalesce short spans, merge similar intents
    2. Compute zoom/center per span via ShotPlanner
    3. Chain segments: startTransform = previous endTransform
    ↓
GeneratedTimeline (CameraTrack with multiple CameraSegments)
```

## Components

### SegmentPlanner (new)

- **Input:** `[IntentSpan]`, `MouseDataSource`
- **Output:** `[CameraSegment]`
- **Responsibilities:**
  - Merge short IntentSpans below minimum duration threshold
  - Merge consecutive spans with the same intent type
  - Use ShotPlanner to compute zoom level and center position for each span
  - Ensure segment continuity: each segment's startTransform equals the previous segment's endTransform
  - Assign appropriate EasingCurve per segment

### SegmentCameraGenerator (new)

- Same interface as ContinuousCameraGenerator
- Shares EventTimeline → IntentClassifier pipeline
- Calls SegmentPlanner instead of WaypointGenerator + SpringDamperSimulator
- Reuses CursorTrackEmitter and KeystrokeTrackEmitter as-is

### Generated CameraSegments

- `mode: .manual` (not continuous)
- `continuousTransforms: nil` (no 60Hz samples)
- `startTransform` / `endTransform` with `interpolation: EasingCurve`
- User can edit zoom, position, and easing of each segment in the timeline

## Mode Selection

- Add mode enum to GenerationSettings: `.continuous` / `.segmentBased`
- Add mode picker to existing generation settings UI
- Default: `.continuous` (preserves current behavior)

## Reused Code

- EventTimeline, IntentClassifier (full analysis layer)
- ShotPlanner (zoom/center computation)
- CursorTrackEmitter, KeystrokeTrackEmitter (cursor/keystroke tracks)
- GeneratedTimeline (output structure)

## Unchanged Code

- ContinuousCameraGenerator, SpringDamperSimulator (continuous mode preserved)
- FrameEvaluator (already supports segment-based rendering)
