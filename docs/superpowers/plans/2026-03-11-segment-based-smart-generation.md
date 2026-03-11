# Segment-Based Smart Generation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a segment-based smart generation mode that produces multiple editable CameraSegments from intent-classified mouse data, alongside the existing continuous camera mode.

**Architecture:** Reuses the existing EventTimeline + IntentClassifier analysis pipeline. A new `SegmentPlanner` merges short/similar IntentSpans, uses ShotPlanner to compute zoom/center per span, and chains segments with matching start/end transforms. A new `SegmentCameraGenerator` orchestrates the pipeline. A `GenerationMode` enum in GenerationSettings lets the user choose between continuous and segment-based.

**Tech Stack:** Swift, CoreGraphics, SwiftUI

---

## File Structure

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Screenize/Generators/SegmentCamera/SegmentPlanner.swift` | Merge IntentSpans, compute zoom/center via ShotPlanner, produce `[CameraSegment]` |
| Create | `Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift` | Orchestrate segment-based pipeline (parallel to ContinuousCameraGenerator) |
| Modify | `Screenize/Generators/GenerationSettings.swift` | Add `GenerationMode` enum and `mode` property |
| Modify | `Screenize/ViewModels/EditorViewModel+SmartGeneration.swift` | Branch on generation mode |
| Modify | `Screenize/Views/GeneratorPanelView.swift` | Add mode picker UI |
| Modify | `Screenize.xcodeproj/project.pbxproj` | Register new files |

---

## Chunk 1: Core Pipeline

### Task 1: Add GenerationMode to GenerationSettings

**Files:**
- Modify: `Screenize/Generators/GenerationSettings.swift:1-17`

- [ ] **Step 1: Add GenerationMode enum and mode property**

Add before the `GenerationSettings` struct definition:

```swift
/// Smart generation mode selection.
enum GenerationMode: String, Codable, CaseIterable {
    case continuous
    case segmentBased
}
```

Add `mode` property to `GenerationSettings`:

```swift
struct GenerationSettings: Codable, Equatable {
    var mode: GenerationMode = .continuous
    var cameraMotion = CameraMotionSettings()
    // ... rest unchanged
}
```

> **Migration note:** `GenerationSettings` is `Codable` and persisted. Existing saved settings lacking the `mode` key will use the default `.continuous` via Swift's synthesized `Decodable` — no migration code needed.

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```
git add Screenize/Generators/GenerationSettings.swift
git commit -m "feat: add GenerationMode enum to GenerationSettings"
```

---

### Task 2: Create SegmentPlanner

**Files:**
- Create: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift`

This is the core logic: takes IntentSpans, merges short/similar ones, uses ShotPlanner for zoom/center, and produces chained CameraSegments.

- [ ] **Step 1: Create SegmentPlanner.swift**

```swift
import Foundation
import CoreGraphics

/// Converts intent spans into discrete, editable camera segments.
///
/// Pipeline:
/// 1. Convert IntentSpans to CameraScenes
/// 2. Merge short/similar scenes
/// 3. Plan shots via ShotPlanner
/// 4. Build chained CameraSegments (each start = previous end)
struct SegmentPlanner {

    /// Minimum scene duration. Scenes shorter than this are merged with neighbors.
    static let minimumSceneDuration: TimeInterval = 1.0

    /// Plan camera segments from classified intent spans.
    static func plan(
        intentSpans: [IntentSpan],
        screenBounds: CGSize,
        eventTimeline: EventTimeline,
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        settings: ShotSettings,
        zoomIntensity: CGFloat = 1.0
    ) -> [CameraSegment] {
        guard !intentSpans.isEmpty else { return [] }

        // Step 1: Convert IntentSpans to CameraScenes
        let scenes = intentSpans.map { span in
            CameraScene(
                startTime: span.startTime,
                endTime: span.endTime,
                primaryIntent: span.intent,
                focusRegions: makeFocusRegions(from: span),
                contextChange: span.contextChange
            )
        }

        // Step 2: Merge short/similar scenes
        let merged = mergeScenes(scenes)

        // Step 3: Plan shots
        let shotPlans = ShotPlanner.plan(
            scenes: merged,
            screenBounds: screenBounds,
            eventTimeline: eventTimeline,
            frameAnalysis: frameAnalysis,
            settings: settings
        )

        // Step 4: Build chained camera segments
        return buildSegments(from: shotPlans, zoomIntensity: zoomIntensity)
    }

    // MARK: - Focus Regions

    private static func makeFocusRegions(from span: IntentSpan) -> [FocusRegion] {
        let midTime = (span.startTime + span.endTime) / 2
        let pos = span.focusPosition
        let pointSize: CGFloat = 0.01
        let region = CGRect(
            x: pos.x - pointSize / 2,
            y: pos.y - pointSize / 2,
            width: pointSize,
            height: pointSize
        )

        if let element = span.focusElement {
            return [
                FocusRegion(
                    time: midTime,
                    region: element.normalizedFrame,
                    confidence: 0.9,
                    source: .activeElement(element)
                )
            ]
        }

        return [
            FocusRegion(
                time: midTime,
                region: region,
                confidence: 0.7,
                source: .cursorPosition
            )
        ]
    }

    // MARK: - Scene Merging

    /// Merge scenes that are too short or have the same intent as their neighbor.
    private static func mergeScenes(_ scenes: [CameraScene]) -> [CameraScene] {
        guard scenes.count > 1 else { return scenes }

        var result: [CameraScene] = [scenes[0]]

        for i in 1..<scenes.count {
            let current = scenes[i]
            let previous = result[result.count - 1]

            let shouldMerge: Bool = {
                // Merge if current scene is too short
                let currentDuration = current.endTime - current.startTime
                if currentDuration < minimumSceneDuration {
                    return true
                }

                // Merge if same intent type as previous
                if intentKey(current.primaryIntent) == intentKey(previous.primaryIntent) {
                    return true
                }

                return false
            }()

            if shouldMerge {
                // Extend previous scene to cover current
                let merged = CameraScene(
                    id: previous.id,
                    startTime: previous.startTime,
                    endTime: current.endTime,
                    primaryIntent: previous.primaryIntent,
                    focusRegions: previous.focusRegions + current.focusRegions,
                    appContext: previous.appContext,
                    contextChange: current.contextChange ?? previous.contextChange
                )
                result[result.count - 1] = merged
            } else {
                result.append(current)
            }
        }

        return result
    }

    /// Intent classification key for merging. Groups similar intents.
    private static func intentKey(_ intent: UserIntent) -> String {
        switch intent {
        case .typing: return "typing"
        case .clicking: return "clicking"
        case .navigating: return "navigating"
        case .dragging: return "dragging"
        case .scrolling: return "scrolling"
        case .switching: return "switching"
        case .reading: return "reading"
        case .idle: return "idle"
        }
    }

    // MARK: - Segment Building

    /// Convert shot plans to chained CameraSegments.
    private static func buildSegments(
        from plans: [ShotPlan],
        zoomIntensity: CGFloat
    ) -> [CameraSegment] {
        guard !plans.isEmpty else { return [] }

        var segments: [CameraSegment] = []
        var previousEnd: TransformValue?

        for plan in plans {
            let rawZoom = plan.idealZoom
            let zoom = max(1.0, 1.0 + (rawZoom - 1.0) * zoomIntensity)
            let center = ShotPlanner.clampCenter(plan.idealCenter, zoom: zoom)
            let endTransform = TransformValue(zoom: zoom, center: center)

            let startTransform = previousEnd ?? endTransform

            let easing = easingForIntent(plan.scene.primaryIntent)

            let segment = CameraSegment(
                startTime: plan.scene.startTime,
                endTime: plan.scene.endTime,
                startTransform: startTransform,
                endTransform: endTransform,
                interpolation: easing,
                mode: .manual,
                continuousTransforms: nil
            )

            segments.append(segment)
            previousEnd = endTransform
        }

        return segments
    }

    /// Choose easing curve based on intent type.
    private static func easingForIntent(_ intent: UserIntent) -> EasingCurve {
        switch intent {
        case .switching:
            return .easeInOut
        case .idle, .reading:
            return .easeOut
        default:
            return .easeInOut
        }
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

Add `SegmentPlanner.swift` and create the `SegmentCamera` group in `Screenize.xcodeproj/project.pbxproj`.

Required entries (4 per file + 1 group):

1. **Check existing UUID prefixes** — run:
   ```
   grep -oE '[A-F0-9]{2}[0-9]{6}' Screenize.xcodeproj/project.pbxproj | sed 's/\(..\).*/\1/' | sort -u
   ```
   Pick a prefix NOT in the output (e.g., `D5` or `D6`).

2. **PBXFileReference** — add in the `/* Begin PBXFileReference section */`:
   ```
   D5000001296A0001 /* SegmentPlanner.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SegmentPlanner.swift; sourceTree = "<group>"; };
   ```

3. **PBXBuildFile** — add in `/* Begin PBXBuildFile section */`:
   ```
   D5000002296A0001 /* SegmentPlanner.swift in Sources */ = {isa = PBXBuildFile; fileRef = D5000001296A0001 /* SegmentPlanner.swift */; };
   ```

4. **PBXGroup for SegmentCamera** — add in `/* Begin PBXGroup section */`:
   ```
   D5000003296A0001 /* SegmentCamera */ = {
       isa = PBXGroup;
       children = (
           D5000001296A0001 /* SegmentPlanner.swift */,
       );
       path = SegmentCamera;
       sourceTree = "<group>";
   };
   ```

5. **Add SegmentCamera group** as child of the Generators group (find its `children` array and add `D5000003296A0001 /* SegmentCamera */`)

6. **PBXSourcesBuildPhase** — add `D5000002296A0001` to the `files` array in the Sources build phase

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```
git add Screenize/Generators/SegmentCamera/SegmentPlanner.swift Screenize.xcodeproj/project.pbxproj
git commit -m "feat: add SegmentPlanner for segment-based camera generation"
```

---

### Task 3: Create SegmentCameraGenerator

**Files:**
- Create: `Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift`

Orchestrates the segment-based pipeline, mirroring ContinuousCameraGenerator's interface but producing discrete segments.

- [ ] **Step 1: Create SegmentCameraGenerator.swift**

```swift
import Foundation
import CoreGraphics

/// Segment-based camera generation pipeline.
///
/// Produces multiple discrete CameraSegments with explicit start/end transforms,
/// editable by the user in the timeline. Shares the analysis layer
/// (EventTimeline, IntentClassifier) with ContinuousCameraGenerator.
///
/// Pipeline:
/// 1. Pre-smooth mouse positions
/// 2. Build event timeline
/// 3. Classify intents
/// 4. Plan and build segments via SegmentPlanner
/// 5. Emit cursor and keystroke tracks
class SegmentCameraGenerator {

    func generate(
        from mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample],
        frameAnalysis: [VideoFrameAnalyzer.FrameAnalysis],
        screenBounds: CGSize,
        settings: ContinuousCameraSettings
    ) -> GeneratedTimeline {
        // Step 1: Pre-smooth mouse positions (same as continuous)
        let effectiveMouseData: MouseDataSource = SmoothedMouseDataSource(
            wrapping: mouseData,
            springConfig: nil
        )

        let duration = effectiveMouseData.duration

        // Step 2: Build event timeline
        let timeline = EventTimeline.build(
            from: effectiveMouseData,
            uiStateSamples: uiStateSamples
        )

        // Step 3: Classify intents
        let intentSpans = IntentClassifier.classify(
            events: timeline,
            uiStateSamples: uiStateSamples,
            settings: settings.intentClassification
        )

        // Step 4: Plan segments
        let segments = SegmentPlanner.plan(
            intentSpans: intentSpans,
            screenBounds: screenBounds,
            eventTimeline: timeline,
            frameAnalysis: frameAnalysis,
            settings: settings.shot,
            zoomIntensity: settings.zoomIntensity
        )

        let cameraTrack = CameraTrack(
            name: "Camera (Segment)",
            segments: segments
        )

        #if DEBUG
        print("[SegmentCamera] Generated \(segments.count) segments from \(intentSpans.count) intent spans")
        #endif

        // Step 5: Emit cursor and keystroke tracks
        let cursorTrack = CursorTrackEmitter.emit(
            duration: duration,
            settings: settings.cursor
        )
        let keystrokeTrack = KeystrokeTrackEmitter.emit(
            eventTimeline: timeline,
            duration: duration,
            settings: settings.keystroke
        )

        return GeneratedTimeline(
            cameraTrack: cameraTrack,
            cursorTrack: cursorTrack,
            keystrokeTrack: keystrokeTrack
        )
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

Add `SegmentCameraGenerator.swift` to `Screenize.xcodeproj/project.pbxproj` under the `SegmentCamera` group created in Task 2. Use the same UUID prefix (e.g., `D5`):

1. **PBXFileReference**:
   ```
   D5000004296A0001 /* SegmentCameraGenerator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = SegmentCameraGenerator.swift; sourceTree = "<group>"; };
   ```

2. **PBXBuildFile**:
   ```
   D5000005296A0001 /* SegmentCameraGenerator.swift in Sources */ = {isa = PBXBuildFile; fileRef = D5000004296A0001 /* SegmentCameraGenerator.swift */; };
   ```

3. **Add to SegmentCamera PBXGroup children**: `D5000004296A0001 /* SegmentCameraGenerator.swift */`

4. **Add to PBXSourcesBuildPhase files**: `D5000005296A0001`

- [ ] **Step 3: Build to verify compilation**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```
git add Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift Screenize.xcodeproj/project.pbxproj
git commit -m "feat: add SegmentCameraGenerator for segment-based pipeline"
```

---

## Chunk 2: Integration

### Task 4: Branch ViewModel on Generation Mode

**Files:**
- Modify: `Screenize/ViewModels/EditorViewModel+SmartGeneration.swift:58-73`

- [ ] **Step 1: Update runSmartZoomGeneration to branch on mode**

Replace the generation pipeline section (lines 58–73) to branch based on `generationSettings.mode`:

```swift
// 4. Run generation pipeline (off main thread to avoid UI freeze)
let springConfig = project.timeline.cursorTrackV2?.springConfig ?? .default

let generationSettings = GenerationSettingsManager.shared.effectiveSettings(for: project)
var ccSettings = ContinuousCameraSettings(from: generationSettings)
ccSettings.springConfig = springConfig
let screenBounds = project.media.pixelSize
let mode = generationSettings.mode

let generated: GeneratedTimeline = try await Task.detached(priority: .userInitiated) {
    switch mode {
    case .continuous:
        return ContinuousCameraGenerator().generate(
            from: mouseDataSource,
            uiStateSamples: uiStateSamples,
            frameAnalysis: frameAnalysis,
            screenBounds: screenBounds,
            settings: ccSettings
        )
    case .segmentBased:
        return SegmentCameraGenerator().generate(
            from: mouseDataSource,
            uiStateSamples: uiStateSamples,
            frameAnalysis: frameAnalysis,
            screenBounds: screenBounds,
            settings: ccSettings
        )
    }
}.value
```

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```
git add Screenize/ViewModels/EditorViewModel+SmartGeneration.swift
git commit -m "feat: branch smart generation on mode selection"
```

---

### Task 5: Add Mode Picker to GeneratorPanelView

**Files:**
- Modify: `Screenize/Views/GeneratorPanelView.swift`

- [ ] **Step 1: Add mode picker UI**

Add a mode picker section in the body, between the header (`SectionHeader`) and the per-type toggles (`VStack`). Bind directly to `GenerationSettingsManager.shared.settings.mode` to avoid state drift:

```swift
// Mode picker
Picker("Mode", selection: Binding(
    get: { GenerationSettingsManager.shared.settings.mode },
    set: { GenerationSettingsManager.shared.settings.mode = $0 }
)) {
    Text("Continuous").tag(GenerationMode.continuous)
    Text("Segment").tag(GenerationMode.segmentBased)
}
.pickerStyle(.segmented)
```

No `@State` property, no `.onAppear` sync, no pre-generation write-back needed — the binding writes directly to the settings manager.

- [ ] **Step 2: Build to verify compilation**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```
git add Screenize/Views/GeneratorPanelView.swift
git commit -m "feat: add generation mode picker to generator panel"
```

---

### Task 6: Final Verification

- [ ] **Step 1: Full build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run lint**

Run: `./scripts/lint.sh`
Expected: No new errors (existing warnings acceptable)

- [ ] **Step 3: Verify the complete flow manually**

1. Open the app
2. Load a project with mouse data
3. Open the generator panel
4. Switch mode to "Segment"
5. Click Generate
6. Verify multiple CameraSegments appear in the timeline
7. Verify each segment is editable (zoom/position/easing can be changed)
8. Switch back to "Continuous" and generate — verify continuous still works
