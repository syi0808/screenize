# Remove Segment-Based Pipeline, Keep Continuous Camera

**Date**: 2026-03-07
**Status**: Approved

## Goal

Remove the segment-based smart generation pipeline (SmartGeneratorV2) and keep only the continuous camera pipeline (ContinuousCameraGenerator). This simplifies the codebase and allows focused quality improvements on the continuous camera system. Segment-based functionality may be re-added later via an adapter pattern.

## Current State

Two parallel pipelines exist:
- **SmartGeneratorV2** (segment-based): 9-stage pipeline producing `CameraTrack` with discrete segments and explicit transitions
- **ContinuousCameraGenerator** (continuous camera): 6-stage pipeline producing `[TimedTransform]` at 60Hz via spring-damper physics

Default is already `continuousCamera`. A `CameraGenerationMethod` picker in GeneratorPanelView switches between them.

## Changes

### 1. Directory Restructure

Rename `Generators/V2/` to `Generators/SmartGeneration/`. Keep shared components, delete segment-only files.

**Target structure:**
```
Generators/
├── SmartGeneration/              (renamed from V2/)
│   ├── Analysis/
│   │   ├── EventTimeline.swift
│   │   └── IntentClassifier.swift
│   ├── Planning/
│   │   └── ShotPlanner.swift
│   ├── Emission/
│   │   ├── CursorTrackEmitter.swift
│   │   └── KeystrokeTrackEmitter.swift
│   ├── Types/
│   │   ├── UserIntent.swift
│   │   ├── Scene.swift
│   │   ├── ShotPlan.swift
│   │   ├── UnifiedEvent.swift
│   │   └── TimedTransform.swift
│   ├── SmoothedMouseDataSource.swift
│   └── GeneratedTimeline.swift
├── ContinuousCamera/
│   ├── ContinuousCameraGenerator.swift
│   ├── ContinuousCameraTypes.swift
│   ├── WaypointGenerator.swift
│   └── SpringDamperSimulator.swift
```

### 2. Shared Types Extraction

Extract from `SmartGeneratorV2.swift` before deleting it:
- `GeneratedTimeline` → `SmartGeneration/GeneratedTimeline.swift`
- `ShotSettings` → into `ShotPlanner.swift`
- `CursorEmissionSettings` → into `CursorTrackEmitter.swift`
- `KeystrokeEmissionSettings` → into `KeystrokeTrackEmitter.swift`
- `SmartGenerationSettings` → DELETE (segment-only)

Clean up `SimulatedPath.swift`:
- Keep `TimedTransform`, rename file to `TimedTransform.swift`
- Delete `SimulatedPath`, `SimulatedSceneSegment`, `SimulatedTransitionSegment`

### 3. Entry Point Simplification

- Remove `CameraGenerationMethod` enum from `EditorViewModel.swift`
- Remove branching logic in `EditorViewModel+SmartGeneration.swift`, always use `ContinuousCameraGenerator`
- Remove method picker from `GeneratorPanelView.swift`

### 4. Files to Delete (~15)

Segment-only pipeline:
1. `V2/SmartGeneratorV2.swift`
2. `V2/Planning/SceneSegmenter.swift`
3. `V2/Planning/TransitionPlanner.swift`
4. `V2/Simulation/CameraSimulator.swift`
5. `V2/Simulation/CameraController.swift`
6. `V2/Simulation/StaticHoldController.swift`
7. `V2/Simulation/CursorFollowController.swift`
8. `V2/PostProcessing/PathSmoother.swift`
9. `V2/PostProcessing/HoldEnforcer.swift`
10. `V2/PostProcessing/TransitionRefiner.swift`
11. `V2/PostProcessing/SegmentMerger.swift`
12. `V2/Emission/CameraTrackEmitter.swift`
13. `V2/Emission/SegmentOptimizer.swift`
14. `V2/Types/TransitionPlan.swift`

Unused continuous camera file:
15. `ContinuousCamera/ContinuousTrackEmitter.swift`

### 5. Backward Compatibility

- `FrameEvaluator+Transform.swift`: Keep both continuous and segment evaluation paths for existing saved projects
- `CameraTrack` type itself remains (used for display-only track in continuous camera)

## Out of Scope

- Quality improvements to continuous camera (ROI, zoom, spring animation)
- Re-adding segment-based functionality via adapter pattern (future work)
- Restructuring non-generator code
