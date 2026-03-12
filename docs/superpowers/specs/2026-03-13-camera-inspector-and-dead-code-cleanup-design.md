# Camera Inspector & Dead Code Cleanup

## Summary

Fix camera segment inspector to show editable options for manual segments, add informational text for continuous segments, and remove dead code (`interpolation`, `transitionToNext`, `SegmentTransition`).

## Problem

1. **Manual camera segments show no options**: The smart generation pipeline (SegmentPlanner) creates `.manual` segments, but SegmentSpringSimulator converts them all to `.continuous`. The inspector only shows zoom/position controls for `.manual` segments, so users never see them.
2. **Continuous segments feel empty**: Only time range fields are shown — no other content.
3. **Dead code**: `interpolation` in `CameraSegmentKind.manual` and `transitionToNext` in `CameraSegment`/`CursorSegment` are never used by the render pipeline (FrameEvaluator, Renderer). The spring simulator handles both interpolation and transitions via velocity carry-over.

## Design

### 1. Keep segments as `.manual` — defer spring simulation to cache

**Current flow:**
```
SegmentPlanner (.manual) → SegmentSpringSimulator → .continuous (stored in timeline)
```

**New flow:**
```
SegmentPlanner (.manual) → stored in timeline as .manual
                         → spring simulation runs separately, result cached
                         → cache invalidated on segment edit, regenerated on demand
```

#### Cache architecture

- **Location**: New `SpringSimulationCache` class, owned by `EditorViewModel`.
- **Key**: Cache is keyed by a version counter on the camera track. Any mutation increments the version and invalidates the cache.
- **Storage**: `[UUID: [TimedTransform]]` — maps segment ID to its simulated transforms.
- **Invalidation scope**: The entire track is re-simulated on any edit, because `SegmentSpringSimulator` carries velocity between segments. Editing segment N affects all subsequent segments.
- **Trigger**: `onSegmentChange` callback (already wired from inspector) calls `EditorViewModel.invalidateSpringCache()`, which clears the cache. Next preview frame request triggers lazy re-simulation.
- **Sync vs async**: Synchronous. Spring simulation is fast (~1ms for typical segment counts). No need for async complexity.
- **FrameEvaluator access**: `FrameEvaluator` receives an optional `SpringSimulationCache` reference. When evaluating a `.manual` segment, it checks the cache for pre-computed transforms. If found, uses `evaluateContinuousTransform`. If not found (cache miss or empty), falls back to hardcoded `easeInOut` interpolation via `evaluateManualTransform`.

#### SegmentCameraGenerator change

- `SegmentCameraGenerator` stores `.manual` segments in the timeline (no longer calls `SegmentSpringSimulator.simulate()` inline).
- `ContinuousCameraGenerator` is unaffected — it already produces `.continuous` segments natively.
- The initial spring cache is populated by `EditorViewModel` after generation completes.

### 2. Manual camera segment inspector

Already implemented in `InspectorView+CameraSection.swift`. Once segments remain `.manual`, the existing UI activates:
- Start/End Zoom sliders (1.0x–5.0x)
- Start/End Position pickers (CenterPointPicker + X/Y fields)
- Start/End time fields

No new UI needed — just unblocking the existing code.

### 3. Continuous camera segment inspector

For continuous segments (e.g., from ContinuousCameraGenerator), show an informational message below the time fields:

```swift
if binding.wrappedValue.isContinuous {
    Label("Continuous segment has no configurable options.", systemImage: "info.circle")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

### 4. Dead code removal

#### Remove `interpolation` from `CameraSegmentKind.manual`

**Before:**
```swift
case manual(startTransform: TransformValue, endTransform: TransformValue, interpolation: EasingCurve)
```

**After:**
```swift
case manual(startTransform: TransformValue, endTransform: TransformValue)
```

**Backward compatibility**: The custom `Codable` implementation in `Segments.swift` must use `decodeIfPresent` for `interpolation` and ignore the value. This ensures existing `.screenize` project files with `"interpolation"` in their JSON still load correctly.

**Files affected (source):**
- `Segments.swift` — enum definition, Codable implementation (use `decodeIfPresent`)
- `SegmentPlanner.swift` — all `.manual(...)` construction sites
- `SegmentSpringSimulator.swift` — pattern matches on `.manual`
- `FrameEvaluator+Transform.swift` — `evaluateManualTransform` no longer receives `interpolation`; hardcode `.easeInOut`
- `InspectorView+CameraSection.swift` — `extractTransform` and `updateTransform` pattern matches
- `InspectorView+SegmentBindings.swift` — pattern matches
- `GeneratorPanelView.swift` — pattern matches

**Files affected (tests):**
- `SegmentSpringSimulatorTests.swift`
- `SegmentCameraGeneratorTests.swift`
- `SegmentPlannerTests.swift`
- `ContinuousCameraGeneratorTests.swift`

**FrameEvaluator fallback**: When `.manual` is rendered without spring cache, use `EasingCurve.easeInOut` as the default interpolation (hardcoded in `evaluateManualTransform`). This matches all existing construction sites in `SegmentPlanner` which already use `.easeInOut`.

#### Remove `transitionToNext` from `CameraSegment`

**Backward compatibility**: `CameraSegment` currently uses auto-synthesized Codable. After removing `transitionToNext`, add a custom `init(from decoder:)` that uses `decodeIfPresent` for `transitionToNext` (and discards it) so old project files still load.

**Files affected:**
- `Segments.swift` — remove property and init parameter, add custom `init(from:)` with `decodeIfPresent`
- `SegmentPlanner.swift` — remove from all construction sites
- `EditorViewModel+Clipboard.swift` — remove from duplicate/paste construction (clipboard still works; the field was only copied, never acted on)

#### Remove `transitionToNext` from `CursorSegment`

Also dead (not used in render). Same treatment.

**Backward compatibility**: `CursorSegment` also uses auto-synthesized Codable. Same approach — add custom `init(from:)` with `decodeIfPresent` for `transitionToNext`.

**Files affected:**
- `Segments.swift` — remove property and init parameter, add custom `init(from:)` with `decodeIfPresent`
- `EditorViewModel+Clipboard.swift` — remove from duplicate/paste construction

#### Remove `SegmentTransition` type

With no consumers left, delete the `SegmentTransition` struct entirely from `Segments.swift`.

## Implementation Order

1. **Dead code removal first** — smallest blast radius, cleans up noise
2. **Spring cache layer** — the core architectural change (new `SpringSimulationCache`, wire into `FrameEvaluator` and `EditorViewModel`)
3. **Inspector UI unblocking** — falls out naturally from step 2 (manual segments now persist, controls activate)
4. **Continuous segment info label** — trivial UI addition

## Out of Scope

- Exposing `CursorFollowConfig` or `ClickFeedbackConfig` in inspector
- Adding new segment types
- Refactoring FrameEvaluator architecture
