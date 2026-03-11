# Camera Segment Kind Design

## Overview

Formalize the two camera segment behaviors (continuous and manual) into an explicit enum-based type system, replacing the current implicit `continuousTransforms: [TimedTransform]?` toggle pattern.

## Type System

### CameraSegmentKind

```swift
enum CameraSegmentKind: Codable, Equatable, Hashable {
    case continuous(transforms: [TimedTransform])
    case manual(
        startTransform: TransformValue,
        endTransform: TransformValue,
        interpolation: EasingCurve
    )
}
```

- **continuous**: Pre-computed camera path samples bound to absolute video time. No user-editable start/end position. Trimming adjusts `startTime`/`endTime` to crop the visible window; underlying transform data is unchanged.
- **manual**: User-editable start and end transforms with easing interpolation (including spring). Classic keyframe-to-keyframe segment.

### CameraSegment (revised)

```swift
struct CameraSegment: Codable, Identifiable, Equatable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var kind: CameraSegmentKind
    var transitionToNext: SegmentTransition

    var isContinuous: Bool {
        if case .continuous = kind { return true }
        return false
    }
}
```

**Removed fields**: `startTransform`, `endTransform`, `interpolation`, `continuousTransforms`, `mode`, `cursorFollow`.

### Coexistence

Both segment kinds live in the same `CameraTrack.segments: [CameraSegment]` array. Sorting and overlap rules remain unchanged. Transitions between heterogeneous segment types use cut (instant) transitions.

## FrameEvaluator Changes

`evaluateTransform(at:)` switches on `segment.kind`:

```swift
switch segment.kind {
case .continuous(let samples):
    return evaluateContinuousTransform(at: time, samples: samples)
case .manual(let startTransform, let endTransform, let interpolation):
    return evaluateManualTransform(
        at: time, segment: segment,
        startTransform: startTransform,
        endTransform: endTransform,
        interpolation: interpolation
    )
}
```

Existing evaluation logic (`evaluateContinuousTransform`, manual interpolation) remains unchanged — only extracted into `evaluateManualTransform` method.

## Generator Output

### Segment-based pipeline (SegmentCameraGenerator)

1. `SegmentPlanner` creates segments with `.manual(startTransform:endTransform:interpolation:)` kind
2. `SegmentSpringSimulator` reads manual targets, runs spring physics, replaces kind with `.continuous(transforms:)`

### Continuous pipeline (ContinuousCameraGenerator)

Generates a single `.continuous(transforms:)` segment spanning the full recording duration.

## Codable

`CameraSegmentKind` requires manual `Codable` implementation (associated-value enum):

```json
// continuous
{ "type": "continuous", "transforms": [...] }

// manual
{ "type": "manual", "startTransform": {...}, "endTransform": {...}, "interpolation": {...} }
```

No legacy migration required.

## Timeline UI

### Visual Distinction

- **Continuous segments**: Different accent color with subtle gradient/wave background pattern
- **Manual segments**: Solid background color (current style)
- Differentiation via `segment.isContinuous` in the segment view layer

### Inspector

- **Continuous selected**: Start time and end time only (read-write)
- **Manual selected**: Start time, end time, start transform, end transform, interpolation (all read-write)

## Scope of Changes

### Modified files

- `Segments.swift` — `CameraSegment` struct, new `CameraSegmentKind` enum
- `FrameEvaluator+Transform.swift` — switch-based dispatch, extract `evaluateManualTransform`
- `SegmentPlanner.swift` — emit `.manual` kind
- `SegmentSpringSimulator.swift` — read manual targets, write `.continuous` kind
- `ContinuousCameraGenerator.swift` — emit `.continuous` kind
- Timeline segment views — background style branch on `isContinuous`
- Inspector views — property visibility branch on `isContinuous`

### Unchanged

- `CameraTrack` array management, sorting, overlap prevention
- `evaluateContinuousTransform` internal logic
- `evaluateManualTransform` internal logic (just extracted)
- Track.swift protocol and conformance
