# Spring Target Segments Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make segment-based camera generation feel as responsive as continuous mode by using spring physics and finer segment granularity.

**Architecture:** Replace the current easing-based segment interpolation with a spring simulation pass. Split segments at the event level instead of merging broad intent spans. Pre-compute `continuousTransforms` per segment so FrameEvaluator (which already supports this path) renders spring motion automatically.

**Tech Stack:** Swift, SpringDamperSimulator.springStep (existing), CameraState (existing)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift` | Modify | Emit per-click spans instead of merging into broad "navigating" spans |
| `Screenize/Generators/SegmentCamera/SegmentPlanner.swift` | Modify | Position-aware merging, spring easing, zero transition duration |
| `Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift` | Modify | Add spring simulation pass after segment planning |
| `Screenize/Generators/SegmentCamera/SegmentSpringSimulator.swift` | **Create** | Isolated spring simulation across segments, producing continuousTransforms |

No changes needed to:
- `FrameEvaluator+Transform.swift` — already handles `continuousTransforms` via binary search (line 19-20)
- `Segments.swift` — `CameraSegment` already has `continuousTransforms` field (line 67)
- `SpringDamperSimulator.swift` — we reuse its `springStep` static method directly

---

## Chunk 1: Finer Segment Splitting

### Task 1: Stop IntentClassifier from merging distant clicks into "navigating"

The root cause is upstream: `IntentClassifier.detectClickSpans` (line 400-438) groups clicks within `navigatingClickWindow: 2.0s` AND `navigatingClickDistance: 0.5` (half the screen!) into one "navigating" span. For our test recording, 4 sequential clicks at very different positions all get merged into one huge span before SegmentPlanner even sees them.

Fix: always emit individual `.clicking` spans. The segment planner's position-aware merging (Task 2) will handle grouping nearby clicks if needed.

**Files:**
- Modify: `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift:440-483`

- [ ] **Step 1: Change emitClickGroup to always emit per-click spans**

Replace the `emitClickGroup` method (lines 440-483) to always emit individual clicking spans regardless of group size:

```swift
private static func emitClickGroup(
    _ group: [UnifiedEvent],
    uiStateSamples: [UIStateSample],
    settings: IntentClassificationSettings
) -> [IntentSpan] {
    return group.map { event in
        let change = detectPostClickChange(
            clickTime: event.time, uiStateSamples: uiStateSamples,
            settings: settings
        )
        var span = IntentSpan(
            startTime: event.time,
            endTime: event.time + TimeInterval(settings.pointSpanDuration),
            intent: .clicking,
            confidence: 0.9,
            focusPosition: event.position,
            focusElement: event.metadata.elementInfo
        )
        span.contextChange = change
        return span
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift
git commit -m "feat: emit per-click intent spans instead of merging into navigating"
```

---

### Task 2: Replace aggressive scene merging in SegmentPlanner

The current `mergeScenes` (line 91-133) merges scenes shorter than 1.0s AND same-intent scenes. With per-click spans from Task 1, we need position-aware merging that only groups nearby clicks.

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift:91-147`

- [ ] **Step 1: Replace mergeScenes logic and delete intentKey**

Replace the `mergeScenes` method (lines 91-133) and delete the now-unused `intentKey` helper (lines 136-147). Only merge when BOTH conditions are true:
1. Same position area (normalized distance < 0.05)
2. Short time gap (< 0.5s)

```swift
/// Merge scenes only when they target the same position within a short time gap.
private static func mergeScenes(_ scenes: [CameraScene]) -> [CameraScene] {
    guard scenes.count > 1 else { return scenes }

    var result: [CameraScene] = [scenes[0]]

    for i in 1..<scenes.count {
        let current = scenes[i]
        let previous = result[result.count - 1]

        let shouldMerge: Bool = {
            // Only merge if positions are very close AND time gap is tiny
            let prevCenter = focusCenter(of: previous)
            let currCenter = focusCenter(of: current)
            let distance = prevCenter.distance(to: currCenter)
            let gap = current.startTime - previous.endTime

            return distance < 0.05 && gap < 0.5
        }()

        if shouldMerge {
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

/// Compute the center of a scene's focus regions.
private static func focusCenter(of scene: CameraScene) -> NormalizedPoint {
    guard !scene.focusRegions.isEmpty else {
        return NormalizedPoint(x: 0.5, y: 0.5)
    }
    let sumX = scene.focusRegions.reduce(CGFloat(0)) { $0 + $1.region.midX }
    let sumY = scene.focusRegions.reduce(CGFloat(0)) { $0 + $1.region.midY }
    let count = CGFloat(scene.focusRegions.count)
    return NormalizedPoint(x: sumX / count, y: sumY / count)
}
```

- [ ] **Step 2: Remove minimumSceneDuration constant**

Delete line 14 (`static let minimumSceneDuration: TimeInterval = 1.0`) since we no longer use a duration threshold.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentPlanner.swift
git commit -m "feat: replace duration-based scene merging with position-aware merging"
```

---

### Task 3: Set spring interpolation and zero transition duration

Currently `buildSegments` (line 152-186) sets `interpolation: easingForIntent(...)` and uses default `transitionToNext` (0.35s easeInOut). Change to spring interpolation and zero transition.

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift:152-198`

- [ ] **Step 1: Update buildSegments to use spring interpolation and zero transitions**

Replace the `buildSegments` method and `easingForIntent` method:

```swift
/// Convert shot plans to chained CameraSegments with spring interpolation.
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

        let segment = CameraSegment(
            startTime: plan.scene.startTime,
            endTime: plan.scene.endTime,
            startTransform: startTransform,
            endTransform: endTransform,
            interpolation: .spring(dampingRatio: 0.90, response: 0.35),
            mode: .manual,
            transitionToNext: SegmentTransition(duration: 0, easing: .linear),
            continuousTransforms: nil
        )

        segments.append(segment)
        previousEnd = endTransform
    }

    return segments
}
```

Delete the `easingForIntent` method (lines 189-198) — no longer needed.

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentPlanner.swift
git commit -m "feat: use spring interpolation and zero transition for segment camera"
```

---

## Chunk 2: Spring Simulation Pass

### Task 4: Create SegmentSpringSimulator

A focused simulator that runs spring physics across all segments, producing `continuousTransforms` for each. It reuses `SpringDamperSimulator.springStep` for the math.

**Files:**
- Create: `Screenize/Generators/SegmentCamera/SegmentSpringSimulator.swift`

- [ ] **Step 1: Create SegmentSpringSimulator**

```swift
import Foundation
import CoreGraphics

/// Runs spring physics simulation across camera segments, populating
/// each segment's `continuousTransforms` with pre-computed samples.
///
/// The spring target is each segment's `endTransform`. When a new segment
/// starts, the target changes but velocity carries over for seamless transitions.
struct SegmentSpringSimulator {

    struct Config {
        var positionDampingRatio: CGFloat = 0.90
        var positionResponse: CGFloat = 0.35
        var zoomDampingRatio: CGFloat = 0.90
        var zoomResponse: CGFloat = 0.55
        var tickRate: Double = 60.0
        var minZoom: CGFloat = 1.0
        var maxZoom: CGFloat = 2.8
    }

    /// Simulate spring physics across all segments and return segments with
    /// populated `continuousTransforms`.
    static func simulate(
        segments: [CameraSegment],
        config: Config = Config()
    ) -> [CameraSegment] {
        guard !segments.isEmpty else { return [] }

        let dt = 1.0 / config.tickRate
        let cgDt = CGFloat(dt)

        // Initialize state from first segment's startTransform
        let initial = segments[0].startTransform
        var state = CameraState(
            positionX: initial.center.x,
            positionY: initial.center.y,
            zoom: initial.zoom
        )

        let posOmega = 2.0 * .pi / max(0.001, config.positionResponse)
        let posDamping = config.positionDampingRatio
        let zoomOmega = 2.0 * .pi / max(0.001, config.zoomResponse)
        let zoomDamping = config.zoomDampingRatio

        var result: [CameraSegment] = []

        for segment in segments {
            let target = segment.endTransform
            let targetCenter = ShotPlanner.clampCenter(target.center, zoom: target.zoom)
            let targetZoom = target.zoom

            var samples: [TimedTransform] = []
            let tickCount = max(1, Int((segment.endTime - segment.startTime) * config.tickRate))
            samples.reserveCapacity(tickCount + 1)

            // Record initial state for this segment
            samples.append(TimedTransform(
                time: segment.startTime,
                transform: TransformValue(
                    zoom: state.zoom,
                    center: NormalizedPoint(x: state.positionX, y: state.positionY)
                )
            ))

            var t = segment.startTime + dt
            while t <= segment.endTime + dt * 0.5 {
                let (newX, newVX) = SpringDamperSimulator.springStep(
                    current: state.positionX, velocity: state.velocityX,
                    target: targetCenter.x,
                    omega: posOmega, zeta: posDamping, dt: cgDt
                )
                let (newY, newVY) = SpringDamperSimulator.springStep(
                    current: state.positionY, velocity: state.velocityY,
                    target: targetCenter.y,
                    omega: posOmega, zeta: posDamping, dt: cgDt
                )
                let (newZ, newVZ) = SpringDamperSimulator.springStep(
                    current: state.zoom, velocity: state.velocityZoom,
                    target: targetZoom,
                    omega: zoomOmega, zeta: zoomDamping, dt: cgDt
                )

                state.positionX = newX
                state.positionY = newY
                state.zoom = min(config.maxZoom, max(config.minZoom, newZ))
                state.velocityX = newVX
                state.velocityY = newVY
                state.velocityZoom = newVZ

                // Clamp center to valid bounds
                let clamped = ShotPlanner.clampCenter(
                    NormalizedPoint(x: state.positionX, y: state.positionY),
                    zoom: state.zoom
                )
                state.positionX = clamped.x
                state.positionY = clamped.y

                let sampleTime = min(t, segment.endTime)
                samples.append(TimedTransform(
                    time: sampleTime,
                    transform: TransformValue(
                        zoom: state.zoom,
                        center: NormalizedPoint(x: state.positionX, y: state.positionY)
                    )
                ))

                t += dt
            }

            var updated = segment
            updated.continuousTransforms = samples
            result.append(updated)
        }

        return result
    }
}
```

- [ ] **Step 2: Add to Xcode project**

Add `SegmentSpringSimulator.swift` to `Screenize.xcodeproj/project.pbxproj` under the `SegmentCamera` group. Requires 4 entries: PBXBuildFile, PBXFileReference, PBXGroup child (in the SegmentCamera group), PBXSourcesBuildPhase. Use a unique hex prefix not already in use (check existing prefixes with `grep -oE '[A-F0-9]{2}[0-9]{6}' project.pbxproj | sed 's/\(..\).*/\1/' | sort -u`). See MEMORY.md for used prefixes.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentSpringSimulator.swift Screenize.xcodeproj/project.pbxproj
git commit -m "feat: add SegmentSpringSimulator for spring physics across segments"
```

---

### Task 5: Wire spring simulation into SegmentCameraGenerator

Add the simulation pass after segment planning in the generator pipeline.

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift:46-59`

- [ ] **Step 1: Add spring simulation step between planning and track creation**

After line 54 (segment planning) and before line 56 (track creation), insert the simulation:

```swift
// Step 4: Plan segments
let rawSegments = SegmentPlanner.plan(
    intentSpans: intentSpans,
    screenBounds: screenBounds,
    eventTimeline: timeline,
    frameAnalysis: frameAnalysis,
    settings: settings.shot,
    zoomIntensity: settings.zoomIntensity
)

// Step 5: Run spring simulation to populate continuousTransforms
let segments = SegmentSpringSimulator.simulate(
    segments: rawSegments,
    config: SegmentSpringSimulator.Config(
        positionDampingRatio: settings.positionDampingRatio,
        positionResponse: settings.positionResponse,
        zoomDampingRatio: settings.zoomDampingRatio,
        zoomResponse: settings.zoomResponse,
        tickRate: settings.tickRate,
        minZoom: settings.minZoom,
        maxZoom: settings.maxZoom
    )
)

let cameraTrack = CameraTrack(
    name: "Camera (Segment)",
    segments: segments
)
```

Update the debug print to reflect the pipeline change:
```swift
#if DEBUG
print("[SegmentCamera] Generated \(segments.count) spring-simulated segments from \(intentSpans.count) intent spans")
#endif
```

Renumber the comment steps (cursor = Step 6, keystroke = Step 7).

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift
git commit -m "feat: wire spring simulation into segment camera pipeline"
```

---

## Verification

### Task 6: End-to-end verification

- [ ] **Step 1: Build the full project**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10
```
Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run lint**

```bash
./scripts/lint.sh 2>&1 | tail -20
```
Fix any new violations in files we modified.

- [ ] **Step 3: Commit any lint fixes**

Only if lint violations were found in our changes.
