# Remove Segment-Based Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Remove the segment-based smart generation pipeline and restructure around continuous camera as the sole generation method.

**Architecture:** Delete SmartGeneratorV2 and all segment-only stages (SceneSegmenter, TransitionPlanner, CameraSimulator, PostProcessing, CameraTrackEmitter, SegmentOptimizer). Extract shared types from SmartGeneratorV2.swift into their consuming files. Rename V2/ to SmartGeneration/. Simplify entry points to always use ContinuousCameraGenerator.

**Tech Stack:** Swift, Xcode project (pbxproj), ScreenCaptureKit

**Note:** This is a deletion/refactoring task. No new features are being added. Build verification replaces traditional TDD — each task must build successfully before committing.

---

### Task 1: Extract shared types from SmartGeneratorV2.swift

Types defined in `SmartGeneratorV2.swift` are used by ContinuousCameraGenerator and must be extracted before the file is deleted.

**Files:**
- Create: `Screenize/Generators/V2/GeneratedTimeline.swift`
- Modify: `Screenize/Generators/V2/Planning/ShotPlanner.swift`
- Modify: `Screenize/Generators/V2/Emission/CursorTrackEmitter.swift`
- Modify: `Screenize/Generators/V2/Emission/KeystrokeTrackEmitter.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj`

**Step 1: Create GeneratedTimeline.swift**

Create `Screenize/Generators/V2/GeneratedTimeline.swift` with the `GeneratedTimeline` struct extracted from `SmartGeneratorV2.swift` (lines 320-326):

```swift
import Foundation

/// Output of the smart generation pipeline.
struct GeneratedTimeline {
    let cameraTrack: CameraTrack
    let cursorTrack: CursorTrackV2
    let keystrokeTrack: KeystrokeTrackV2
    /// Pre-computed continuous camera path at 60Hz.
    var continuousTransforms: [TimedTransform]?
}
```

**Step 2: Move ShotSettings to ShotPlanner.swift**

Copy `ShotSettings` struct (lines 354-380 of SmartGeneratorV2.swift) to the bottom of `ShotPlanner.swift`:

```swift
// MARK: - Settings

/// Per-intent zoom and center calculation settings.
struct ShotSettings {
    var typingCodeZoomRange: ClosedRange<CGFloat> = 2.0...2.5
    var typingTextFieldZoomRange: ClosedRange<CGFloat> = 2.2...2.8
    var typingTerminalZoomRange: ClosedRange<CGFloat> = 1.6...2.0
    var typingRichTextZoomRange: ClosedRange<CGFloat> = 1.8...2.2
    var clickingZoomRange: ClosedRange<CGFloat> = 1.5...2.5
    var navigatingZoomRange: ClosedRange<CGFloat> = 1.5...1.8
    var draggingZoomRange: ClosedRange<CGFloat> = 1.3...1.6
    var scrollingZoomRange: ClosedRange<CGFloat> = 1.3...1.5
    var readingZoomRange: ClosedRange<CGFloat> = 1.0...1.3
    var switchingZoom: CGFloat = 1.0
    var idleZoom: CGFloat = 1.0
    var targetAreaCoverage: CGFloat = 0.7
    var workAreaPadding: CGFloat = 0.08
    var minZoom: CGFloat = 1.0
    var maxZoom: CGFloat = 2.8
    var idleZoomDecay: CGFloat = 0.5
}
```

**Step 3: Move CursorEmissionSettings to CursorTrackEmitter.swift**

Add to bottom of `CursorTrackEmitter.swift`:

```swift
// MARK: - Settings

/// Cursor track emission settings.
struct CursorEmissionSettings {
    var cursorScale: CGFloat = 2.0
}
```

**Step 4: Move KeystrokeEmissionSettings to KeystrokeTrackEmitter.swift**

Add to bottom of `KeystrokeTrackEmitter.swift`:

```swift
// MARK: - Settings

/// Keystroke track emission settings.
struct KeystrokeEmissionSettings {
    var enabled: Bool = true
    var shortcutsOnly: Bool = true
    var displayDuration: TimeInterval = 1.5
    var fadeInDuration: TimeInterval = 0.15
    var fadeOutDuration: TimeInterval = 0.3
    var minInterval: TimeInterval = 0.05
}
```

**Step 5: Add GeneratedTimeline.swift to Xcode project**

Add to `project.pbxproj`:
- PBXBuildFile entry with new UUID (use `D5` prefix)
- PBXFileReference entry
- Add to V2 PBXGroup children (UUID `AC000001296A0001`)
- Add to PBXSourcesBuildPhase

**Step 6: Build verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

Note: SmartGeneratorV2.swift still exists and still compiles — the types are now duplicated temporarily. This is intentional; the old definitions will be deleted in Task 4.

**Step 7: Commit**

```
git add Screenize/Generators/V2/GeneratedTimeline.swift \
  Screenize/Generators/V2/Planning/ShotPlanner.swift \
  Screenize/Generators/V2/Emission/CursorTrackEmitter.swift \
  Screenize/Generators/V2/Emission/KeystrokeTrackEmitter.swift \
  Screenize.xcodeproj/project.pbxproj
git commit -m "refactor: extract shared types from SmartGeneratorV2"
```

---

### Task 2: Clean up SimulatedPath.swift → TimedTransform.swift

Remove segment-only types from SimulatedPath.swift, keeping only `TimedTransform`. Rename the file.

**Files:**
- Modify: `Screenize/Generators/V2/Types/SimulatedPath.swift` → rename to `TimedTransform.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj`

**Step 1: Replace file contents**

Replace entire `SimulatedPath.swift` contents with just `TimedTransform`:

```swift
import Foundation

/// A transform value at a specific point in time, used by the continuous camera pipeline.
struct TimedTransform: Codable, Equatable {
    let time: TimeInterval
    let transform: TransformValue
}
```

The removed types (`SimulatedPath`, `SimulatedSceneSegment`, `SimulatedTransitionSegment`) are only used by segment-only pipeline files that will be deleted in Task 4.

**Step 2: Rename file on disk**

```bash
mv Screenize/Generators/V2/Types/SimulatedPath.swift Screenize/Generators/V2/Types/TimedTransform.swift
```

**Step 3: Update pbxproj file reference**

In `project.pbxproj`, update the PBXFileReference for UUID `AB000006296A0001`:
- Change `SimulatedPath.swift` → `TimedTransform.swift` in both the `name` and `path` fields

**Step 4: Build verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

Note: SmartGeneratorV2.swift will have compile errors referencing the removed types, but since it still has `ShotSettings` etc. that are now duplicated, this may cause issues. If build fails, defer the file rename to Task 4 (delete everything at once). In that case, just do the content replacement without renaming.

**Step 5: Commit**

```
git add -A
git commit -m "refactor: clean SimulatedPath.swift to keep only TimedTransform"
```

---

### Task 3: Simplify entry points

Remove the `CameraGenerationMethod` toggle and always use `ContinuousCameraGenerator`.

**Files:**
- Modify: `Screenize/ViewModels/EditorViewModel.swift` (lines 27-29, 441-447)
- Modify: `Screenize/ViewModels/EditorViewModel+SmartGeneration.swift` (lines 58-82)
- Modify: `Screenize/Views/GeneratorPanelView.swift` (lines 58-64)
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraGenerator.swift` (line 6, doc comment)

**Step 1: Remove CameraGenerationMethod from EditorViewModel.swift**

Delete these sections:
- Line 27-29: `@Published var cameraGenerationMethod: CameraGenerationMethod = .continuousCamera`
- Lines 441-447: The entire `CameraGenerationMethod` enum

**Step 2: Simplify EditorViewModel+SmartGeneration.swift**

Replace the branching block (lines 58-82) with continuous camera only:

```swift
// 4. Run generation pipeline
let generated: GeneratedTimeline
let springConfig = project.timeline.cursorTrackV2?.springConfig ?? .default

var ccSettings = ContinuousCameraSettings()
ccSettings.springConfig = springConfig
generated = ContinuousCameraGenerator().generate(
    from: mouseDataSource,
    uiStateSamples: uiStateSamples,
    frameAnalysis: frameAnalysis,
    screenBounds: project.media.pixelSize,
    settings: ccSettings
)
```

Remove the `import` or reference to `SmartGeneratorV2` and `SmartGenerationSettings` if present.

**Step 3: Remove method picker from GeneratorPanelView.swift**

Delete lines 58-64 (the Picker block):
```swift
// Method picker
Picker("Method", selection: $viewModel.cameraGenerationMethod) {
    ForEach(CameraGenerationMethod.allCases, id: \.self) {
        Text($0.rawValue)
    }
}
.pickerStyle(.segmented)
```

**Step 4: Update ContinuousCameraGenerator doc comment**

In `ContinuousCameraGenerator.swift`, update the doc comment (line 6) that references SmartGeneratorV2:

Change: `/// Unlike SmartGeneratorV2 which uses discrete segments + transitions,`
To: `/// Produces a single unbroken physics-simulated camera path`

**Step 5: Build verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

Note: SmartGeneratorV2.swift and segment-only files still exist and compile, they're just unreferenced. This is fine — they'll be deleted in Task 4.

**Step 6: Commit**

```
git add Screenize/ViewModels/EditorViewModel.swift \
  Screenize/ViewModels/EditorViewModel+SmartGeneration.swift \
  Screenize/Views/GeneratorPanelView.swift \
  Screenize/Generators/ContinuousCamera/ContinuousCameraGenerator.swift
git commit -m "refactor: remove CameraGenerationMethod, always use continuous camera"
```

---

### Task 4: Delete segment-only files and update Xcode project

Delete all files exclusive to the segment-based pipeline, including their tests.

**Source files to delete (15):**
1. `Screenize/Generators/V2/SmartGeneratorV2.swift`
2. `Screenize/Generators/V2/Planning/SceneSegmenter.swift`
3. `Screenize/Generators/V2/Planning/TransitionPlanner.swift`
4. `Screenize/Generators/V2/Simulation/CameraSimulator.swift`
5. `Screenize/Generators/V2/Simulation/CameraController.swift`
6. `Screenize/Generators/V2/Simulation/StaticHoldController.swift`
7. `Screenize/Generators/V2/Simulation/CursorFollowController.swift`
8. `Screenize/Generators/V2/PostProcessing/PathSmoother.swift`
9. `Screenize/Generators/V2/PostProcessing/HoldEnforcer.swift`
10. `Screenize/Generators/V2/PostProcessing/TransitionRefiner.swift`
11. `Screenize/Generators/V2/PostProcessing/SegmentMerger.swift`
12. `Screenize/Generators/V2/Emission/CameraTrackEmitter.swift`
13. `Screenize/Generators/V2/Emission/SegmentOptimizer.swift`
14. `Screenize/Generators/V2/Types/TransitionPlan.swift`
15. `Screenize/Generators/ContinuousCamera/ContinuousTrackEmitter.swift`

**Test files to delete (12):**
1. `ScreenizeTests/Generators/V2/Planning/SceneSegmenterTests.swift`
2. `ScreenizeTests/Generators/V2/Planning/TransitionPlannerTests.swift`
3. `ScreenizeTests/Generators/V2/Simulation/CameraSimulatorTests.swift`
4. `ScreenizeTests/Generators/V2/Simulation/StaticHoldControllerTests.swift`
5. `ScreenizeTests/Generators/V2/Simulation/CursorFollowControllerTests.swift`
6. `ScreenizeTests/Generators/V2/PostProcessing/PathSmootherTests.swift`
7. `ScreenizeTests/Generators/V2/PostProcessing/HoldEnforcerTests.swift`
8. `ScreenizeTests/Generators/V2/PostProcessing/TransitionRefinerTests.swift`
9. `ScreenizeTests/Generators/V2/PostProcessing/SegmentMergerTests.swift`
10. `ScreenizeTests/Generators/V2/Emission/CameraTrackEmitterTests.swift`
11. `ScreenizeTests/Generators/V2/Emission/SegmentOptimizerTests.swift`
12. `ScreenizeTests/Generators/ContinuousCamera/ContinuousTrackEmitterTests.swift`

**Step 1: Delete source files from disk**

```bash
rm Screenize/Generators/V2/SmartGeneratorV2.swift
rm Screenize/Generators/V2/Planning/SceneSegmenter.swift
rm Screenize/Generators/V2/Planning/TransitionPlanner.swift
rm -rf Screenize/Generators/V2/Simulation/
rm -rf Screenize/Generators/V2/PostProcessing/
rm Screenize/Generators/V2/Emission/CameraTrackEmitter.swift
rm Screenize/Generators/V2/Emission/SegmentOptimizer.swift
rm Screenize/Generators/V2/Types/TransitionPlan.swift
rm Screenize/Generators/ContinuousCamera/ContinuousTrackEmitter.swift
```

**Step 2: Delete test files from disk**

```bash
rm ScreenizeTests/Generators/V2/Planning/SceneSegmenterTests.swift
rm ScreenizeTests/Generators/V2/Planning/TransitionPlannerTests.swift
rm -rf ScreenizeTests/Generators/V2/Simulation/
rm -rf ScreenizeTests/Generators/V2/PostProcessing/
rm ScreenizeTests/Generators/V2/Emission/CameraTrackEmitterTests.swift
rm ScreenizeTests/Generators/V2/Emission/SegmentOptimizerTests.swift
rm ScreenizeTests/Generators/ContinuousCamera/ContinuousTrackEmitterTests.swift
```

**Step 3: Update project.pbxproj — remove PBXBuildFile entries**

Remove these lines from the `/* Begin PBXBuildFile section */`:

| UUID | File |
|------|------|
| `AA000007296A0001` | SmartGeneratorV2.swift |
| `AE000001296A0001` | SceneSegmenter.swift |
| `AF000001296A0001` | SceneSegmenterTests.swift |
| `AE000003296A0001` | TransitionPlanner.swift |
| `AF000003296A0001` | TransitionPlannerTests.swift |
| `B0000001296A0001` | CameraController.swift |
| `B0000002296A0001` | StaticHoldController.swift |
| `B1000001296A0001` | StaticHoldControllerTests.swift |
| `B0000003296A0001` | CameraSimulator.swift |
| `B1000002296A0001` | CameraSimulatorTests.swift |
| `B0000004296A0001` | CursorFollowController.swift |
| `B1000003296A0001` | CursorFollowControllerTests.swift |
| `B6000001296A0001` | PathSmoother.swift |
| `B7000001296A0001` | PathSmootherTests.swift |
| `B6000002296A0001` | HoldEnforcer.swift |
| `B7000002296A0001` | HoldEnforcerTests.swift |
| `B6000003296A0001` | TransitionRefiner.swift |
| `B7000003296A0001` | TransitionRefinerTests.swift |
| `B6000004296A0001` | SegmentMerger.swift |
| `B7000004296A0001` | SegmentMergerTests.swift |
| `B2000001296A0001` | CameraTrackEmitter.swift |
| `B3000001296A0001` | CameraTrackEmitterTests.swift |
| `B2000004296A0001` | SegmentOptimizer.swift |
| `B3000004296A0001` | SegmentOptimizerTests.swift |
| `AA000005296A0001` | TransitionPlan.swift |
| `E7000004296A0001` | ContinuousTrackEmitter.swift |
| `E7000013296A0001` | ContinuousTrackEmitterTests.swift |

**Step 4: Update project.pbxproj — remove PBXFileReference entries**

Remove these from `/* Begin PBXFileReference section */`:

| UUID | File |
|------|------|
| `AB000007296A0001` | SmartGeneratorV2.swift |
| `AE100001296A0001` | SceneSegmenter.swift |
| `AF100001296A0001` | SceneSegmenterTests.swift |
| `AE100003296A0001` | TransitionPlanner.swift |
| `AF100003296A0001` | TransitionPlannerTests.swift |
| `B0100001296A0001` | CameraController.swift |
| `B0100002296A0001` | StaticHoldController.swift |
| `B1100001296A0001` | StaticHoldControllerTests.swift |
| `B0100003296A0001` | CameraSimulator.swift |
| `B1100002296A0001` | CameraSimulatorTests.swift |
| `B0100004296A0001` | CursorFollowController.swift |
| `B1100003296A0001` | CursorFollowControllerTests.swift |
| `B6100001296A0001` | PathSmoother.swift |
| `B7100001296A0001` | PathSmootherTests.swift |
| `B6100002296A0001` | HoldEnforcer.swift |
| `B7100002296A0001` | HoldEnforcerTests.swift |
| `B6100003296A0001` | TransitionRefiner.swift |
| `B7100003296A0001` | TransitionRefinerTests.swift |
| `B6100004296A0001` | SegmentMerger.swift |
| `B7100004296A0001` | SegmentMergerTests.swift |
| `B2100001296A0001` | CameraTrackEmitter.swift |
| `B3100001296A0001` | CameraTrackEmitterTests.swift |
| `B2100004296A0001` | SegmentOptimizer.swift |
| `B3100004296A0001` | SegmentOptimizerTests.swift |
| `AB000005296A0001` | TransitionPlan.swift |
| `E7100004296A0001` | ContinuousTrackEmitter.swift |
| `E7100013296A0001` | ContinuousTrackEmitterTests.swift |

**Step 5: Update project.pbxproj — remove/update PBXGroup entries**

Remove entire PBXGroup blocks for:
- `B0200001296A0001` (Simulation source)
- `B1200001296A0001` (Simulation tests)
- `B6200001296A0001` (PostProcessing source)
- `B7200001296A0001` (PostProcessing tests)

Update Planning source group (`AE200001296A0001`):
- Remove `AE100001296A0001` (SceneSegmenter)
- Remove `AE100003296A0001` (TransitionPlanner)
- Keep `AE100002296A0001` (ShotPlanner)

Update Planning test group (`AF200001296A0001`):
- Remove `AF100001296A0001` (SceneSegmenterTests)
- Remove `AF100003296A0001` (TransitionPlannerTests)
- Keep `AF100002296A0001` (ShotPlannerTests)

Update Emission source group (`B2200001296A0001`):
- Remove `B2100001296A0001` (CameraTrackEmitter)
- Remove `B2100004296A0001` (SegmentOptimizer)
- Keep CursorTrackEmitter + KeystrokeTrackEmitter

Update Emission test group (`B3200001296A0001`):
- Remove `B3100001296A0001` (CameraTrackEmitterTests)
- Remove `B3100004296A0001` (SegmentOptimizerTests)
- Keep remaining emitter tests

Update V2 source group (`AC000001296A0001`):
- Remove `AB000007296A0001` (SmartGeneratorV2.swift)
- Remove `B0200001296A0001` (Simulation group ref)
- Remove `B6200001296A0001` (PostProcessing group ref)

Update V2 test group (`AD200023296A0001`):
- Remove `B1200001296A0001` (Simulation test group ref)
- Remove `B7200001296A0001` (PostProcessing test group ref)

Update ContinuousCamera source group (`E7200001296A0001`):
- Remove `E7100004296A0001` (ContinuousTrackEmitter)

Update ContinuousCamera test group (`E7200002296A0001`):
- Remove `E7100013296A0001` (ContinuousTrackEmitterTests)

Update V2 Types group:
- Remove `AB000005296A0001` (TransitionPlan.swift)

**Step 6: Update project.pbxproj — remove PBXSourcesBuildPhase entries**

Remove all UUIDs listed in Step 3 from the appropriate PBXSourcesBuildPhase sections (app target and test target).

**Step 7: Build verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

If build fails, check for:
- References to deleted types in kept files
- Missing imports
- Stale pbxproj entries

**Step 8: Commit**

```
git add -A
git commit -m "refactor: delete segment-based pipeline files"
```

---

### Task 5: Rename V2/ → SmartGeneration/

Rename the directory on disk and update Xcode project references.

**Files:**
- Rename: `Screenize/Generators/V2/` → `Screenize/Generators/SmartGeneration/`
- Rename: `ScreenizeTests/Generators/V2/` → `ScreenizeTests/Generators/SmartGeneration/`
- Modify: `Screenize.xcodeproj/project.pbxproj`

**Step 1: Rename directories on disk**

```bash
mv Screenize/Generators/V2 Screenize/Generators/SmartGeneration
mv ScreenizeTests/Generators/V2 ScreenizeTests/Generators/SmartGeneration
```

**Step 2: Update pbxproj group paths**

Update V2 source PBXGroup (`AC000001296A0001`):
- Change `path = V2;` → `path = SmartGeneration;`
- Change `name` if present

Update V2 test PBXGroup (`AD200023296A0001`):
- Change `path = V2;` → `path = SmartGeneration;`
- Change `name` if present

**Step 3: Build verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```
git add -A
git commit -m "refactor: rename V2/ to SmartGeneration/"
```

---

### Task 6: Final verification and cleanup

**Step 1: Full build verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -20`
Expected: `BUILD SUCCEEDED`

**Step 2: Run tests**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug test 2>&1 | tail -20`
Expected: All tests pass (remaining tests for shared components + continuous camera)

**Step 3: Verify directory structure**

```bash
find Screenize/Generators -name "*.swift" | sort
```

Expected output:
```
Screenize/Generators/ContinuousCamera/ContinuousCameraGenerator.swift
Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift
Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift
Screenize/Generators/ContinuousCamera/WaypointGenerator.swift
Screenize/Generators/SmartGeneration/Analysis/EventTimeline.swift
Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift
Screenize/Generators/SmartGeneration/Emission/CursorTrackEmitter.swift
Screenize/Generators/SmartGeneration/Emission/KeystrokeTrackEmitter.swift
Screenize/Generators/SmartGeneration/GeneratedTimeline.swift
Screenize/Generators/SmartGeneration/Planning/ShotPlanner.swift
Screenize/Generators/SmartGeneration/SmoothedMouseDataSource.swift
Screenize/Generators/SmartGeneration/Types/Scene.swift
Screenize/Generators/SmartGeneration/Types/ShotPlan.swift
Screenize/Generators/SmartGeneration/Types/TimedTransform.swift
Screenize/Generators/SmartGeneration/Types/UnifiedEvent.swift
Screenize/Generators/SmartGeneration/Types/UserIntent.swift
```

Plus any other generator files at the root level (KeyframeGenerator.swift, RippleGenerator.swift, etc.)

**Step 4: Verify no stale references**

```bash
grep -r "SmartGeneratorV2" Screenize/ --include="*.swift"
grep -r "CameraGenerationMethod" Screenize/ --include="*.swift"
grep -r "SceneSegmenter\b" Screenize/ --include="*.swift"
grep -r "TransitionPlanner\b" Screenize/ --include="*.swift"
grep -r "CameraSimulator\b" Screenize/ --include="*.swift"
```

Expected: No matches (or only in comments that should be cleaned up)

**Step 5: Lint check**

Run: `./scripts/lint.sh`
Expected: No new violations introduced

**Step 6: Log work**

Run `/log-work` to document the completed refactoring.
