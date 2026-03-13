# Camera Inspector & Dead Code Cleanup Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make manual camera segments editable in the inspector by keeping them as `.manual` in the timeline, add info label for continuous segments, and remove dead code.

**Architecture:** Dead code removal first (interpolation, transitionToNext, SegmentTransition), then spring simulation cache layer so `.manual` segments persist in the timeline while spring physics are applied lazily for preview/export, then inspector UI unblocking.

**Tech Stack:** Swift, SwiftUI, CoreGraphics

---

## Task 1: Remove `interpolation` from `CameraSegmentKind.manual`

**Files:**
- Modify: `Screenize/Timeline/Segments.swift:49-103`
- Modify: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift` (lines 227-267)
- Modify: `Screenize/Generators/SegmentCamera/SegmentSpringSimulator.swift` (lines 48, 67, 78)
- Modify: `Screenize/Render/FrameEvaluator+Transform.swift:20-25, 29-34`
- Modify: `Screenize/Views/Inspector/InspectorView+CameraSection.swift:160, 171`
- Modify: `Screenize/Views/Inspector/InspectorView+SegmentBindings.swift:24`
- Modify: `Screenize/Views/GeneratorPanelView.swift:195`
- Modify: `ScreenizeTests/Generators/SegmentCamera/SegmentSpringSimulatorTests.swift:126-130`
- Modify: `ScreenizeTests/Generators/SegmentCamera/SegmentCameraGeneratorTests.swift:95-100`
- Modify: `ScreenizeTests/Generators/SegmentCamera/SegmentPlannerTests.swift` (lines 122, 146, 183)
- Modify: `ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift:232`

- [ ] **Step 1: Update `CameraSegmentKind` enum definition**

In `Screenize/Timeline/Segments.swift`, change:
```swift
case manual(
    startTransform: TransformValue,
    endTransform: TransformValue,
    interpolation: EasingCurve
)
```
to:
```swift
case manual(
    startTransform: TransformValue,
    endTransform: TransformValue
)
```

- [ ] **Step 2: Update `CameraSegmentKind` Codable**

In the same file, update `init(from:)` to use `decodeIfPresent` (backward compat). **Keep `interpolation` in `CodingKeys`** — it's needed for `decodeIfPresent` to work on old project files:

```swift
case .manual:
    let startTransform = try container.decode(TransformValue.self, forKey: .startTransform)
    let endTransform = try container.decode(TransformValue.self, forKey: .endTransform)
    // Ignore legacy interpolation field if present
    _ = try container.decodeIfPresent(EasingCurve.self, forKey: .interpolation)
    self = .manual(
        startTransform: startTransform,
        endTransform: endTransform
    )
```

Update `encode(to:)` — stop encoding `interpolation`:
```swift
case .manual(let startTransform, let endTransform):
    try container.encode(KindType.manual, forKey: .type)
    try container.encode(startTransform, forKey: .startTransform)
    try container.encode(endTransform, forKey: .endTransform)
```

- [ ] **Step 3: Update SegmentPlanner construction sites**

In `Screenize/Generators/SegmentCamera/SegmentPlanner.swift`, update all 4 `.manual(` calls to remove `interpolation:` parameter:
```swift
// Before
kind: .manual(startTransform: startTransform, endTransform: endTransform, interpolation: .easeInOut)
// After
kind: .manual(startTransform: startTransform, endTransform: endTransform)
```
Lines: 227-231, 237-241, 250-254, 263-267.

- [ ] **Step 4: Update SegmentSpringSimulator pattern matches**

In `Screenize/Generators/SegmentCamera/SegmentSpringSimulator.swift`, update 3 pattern matches:
```swift
// Line 48: .manual(let start, _, _) → .manual(let start, _)
case .manual(let start, _):
    initial = start

// Line 67: .manual(_, let end, _) → .manual(_, let end)
case .manual(_, let end):
    target = end

// Line 78: .manual(let start, let end, _) → .manual(let start, let end)
if case .manual(let start, let end) = segment.kind {
```

- [ ] **Step 5: Update FrameEvaluator+Transform**

In `Screenize/Render/FrameEvaluator+Transform.swift`:

Line 20 — update pattern match:
```swift
case .manual(let startTransform, let endTransform):
```

Lines 21-25 — remove `interpolation` parameter:
```swift
return evaluateManualTransform(
    at: time, segment: segment,
    startTransform: startTransform, endTransform: endTransform
)
```

Lines 29-34 — remove `interpolation` parameter from function signature and hardcode:
```swift
private func evaluateManualTransform(
    at time: TimeInterval,
    segment: CameraSegment,
    startTransform: TransformValue,
    endTransform: TransformValue
) -> TransformState {
    let interpolation: EasingCurve = .easeInOut
```

- [ ] **Step 6: Update Inspector pattern matches**

In `Screenize/Views/Inspector/InspectorView+CameraSection.swift`:
```swift
// Line 160: guard case .manual(let startTransform, let endTransform, _)
guard case .manual(let startTransform, let endTransform) = segment.kind else {

// Line 171: guard case .manual(var startTransform, var endTransform, let interpolation)
guard case .manual(var startTransform, var endTransform) = segment.kind else {
```

Line 179-183 — update kind reconstruction:
```swift
segment.kind = .manual(
    startTransform: startTransform,
    endTransform: endTransform
)
```

In `Screenize/Views/Inspector/InspectorView+SegmentBindings.swift` line 24:
```swift
kind: .manual(startTransform: .identity, endTransform: .identity)
```

In `Screenize/Views/GeneratorPanelView.swift` line 195:
```swift
CameraSegment(startTime: 0, endTime: 5, kind: .manual(startTransform: .identity, endTransform: .identity))
```

- [ ] **Step 7: Update test files**

In `ScreenizeTests/Generators/SegmentCamera/SegmentSpringSimulatorTests.swift` (makeSegment helper):
```swift
kind: .manual(
    startTransform: TransformValue(zoom: startZoom, center: startCenter),
    endTransform: TransformValue(zoom: endZoom, center: endCenter)
),
```

In `ScreenizeTests/Generators/SegmentCamera/SegmentCameraGeneratorTests.swift` (makeSegment helper):
```swift
kind: .manual(
    startTransform: TransformValue(zoom: 1.5, center: NormalizedPoint(x: 0.3, y: 0.4)),
    endTransform: TransformValue(zoom: 1.8, center: NormalizedPoint(x: 0.6, y: 0.7))
),
```

In `ScreenizeTests/Generators/SegmentCamera/SegmentPlannerTests.swift`, update 3 pattern matches:
```swift
// Lines 122, 146, 183: .manual(let start, let end, _) → .manual(let start, let end)
if case .manual(let start, let end) = segment.kind {
```

In `ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift` line 232:
```swift
case .manual(let start, let end):
```

- [ ] **Step 8: Build and verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```
git add -A && git commit -m "refactor: remove dead interpolation field from CameraSegmentKind.manual"
```

---

## Task 2: Remove `transitionToNext` and `SegmentTransition`

**Files:**
- Modify: `Screenize/Timeline/Segments.swift:7-13, 106-131, 135-163`
- Modify: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift` (lines 232, 242, 255, 268)
- Modify: `Screenize/ViewModels/EditorViewModel+Clipboard.swift` (lines 170, 194, 234, 254)
- Modify: `ScreenizeTests/Generators/SegmentCamera/SegmentSpringSimulatorTests.swift:131`
- Modify: `ScreenizeTests/Generators/SegmentCamera/SegmentCameraGeneratorTests.swift:100`

- [ ] **Step 1: Replace `SegmentTransition` with legacy decode-only type**

In `Screenize/Timeline/Segments.swift`, replace the public `SegmentTransition` struct with a file-private legacy type:
```swift
/// Legacy type kept only for backward-compatible decoding of old project files.
private struct LegacySegmentTransition: Codable {
    var duration: TimeInterval
    var easing: EasingCurve
}
```

- [ ] **Step 2: Remove `transitionToNext` from `CameraSegment`**

Remove the `var transitionToNext: SegmentTransition` property and init parameter. Add custom `init(from:)` **and** custom `encode(to:)` for backward compat. The custom `encode(to:)` is needed because `CodingKeys` includes `transitionToNext` (for decoding old files) but the property no longer exists:

```swift
struct CameraSegment: Identifiable, Equatable, Codable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var kind: CameraSegmentKind

    var isContinuous: Bool {
        if case .continuous = kind { return true }
        return false
    }

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        kind: CameraSegmentKind
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, kind, transitionToNext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        endTime = try container.decode(TimeInterval.self, forKey: .endTime)
        kind = try container.decode(CameraSegmentKind.self, forKey: .kind)
        _ = try container.decodeIfPresent(LegacySegmentTransition.self, forKey: .transitionToNext)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(kind, forKey: .kind)
        // transitionToNext intentionally not encoded — removed
    }
}
```

- [ ] **Step 3: Remove `transitionToNext` from `CursorSegment`**

Same approach — remove property, add custom `init(from:)` and `encode(to:)`:

```swift
struct CursorSegment: Identifiable, Equatable, Codable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var style: CursorStyle
    var visible: Bool
    var scale: CGFloat
    var clickFeedback: ClickFeedbackConfig

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        style: CursorStyle = .arrow,
        visible: Bool = true,
        scale: CGFloat = 2.5,
        clickFeedback: ClickFeedbackConfig = .default
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.style = style
        self.visible = visible
        self.scale = scale
        self.clickFeedback = clickFeedback
    }

    private enum CodingKeys: String, CodingKey {
        case id, startTime, endTime, style, visible, scale, clickFeedback, transitionToNext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startTime = try container.decode(TimeInterval.self, forKey: .startTime)
        endTime = try container.decode(TimeInterval.self, forKey: .endTime)
        style = try container.decode(CursorStyle.self, forKey: .style)
        visible = try container.decode(Bool.self, forKey: .visible)
        scale = try container.decode(CGFloat.self, forKey: .scale)
        clickFeedback = try container.decode(ClickFeedbackConfig.self, forKey: .clickFeedback)
        _ = try container.decodeIfPresent(LegacySegmentTransition.self, forKey: .transitionToNext)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(endTime, forKey: .endTime)
        try container.encode(style, forKey: .style)
        try container.encode(visible, forKey: .visible)
        try container.encode(scale, forKey: .scale)
        try container.encode(clickFeedback, forKey: .clickFeedback)
    }
}
```

- [ ] **Step 4: Update SegmentPlanner — remove `transitionToNext:` from all 4 construction sites**

In `Screenize/Generators/SegmentCamera/SegmentPlanner.swift`, remove 4 occurrences of:
```swift
transitionToNext: SegmentTransition(duration: 0, easing: .linear)
```

- [ ] **Step 5: Update EditorViewModel+Clipboard — remove `transitionToNext:` from all 4 construction sites**

In `Screenize/ViewModels/EditorViewModel+Clipboard.swift`, remove:
- Line 170: `transitionToNext: original.transitionToNext` from CameraSegment construction
- Line 194: `transitionToNext: original.transitionToNext` from CursorSegment construction
- Line 234: `transitionToNext: original.transitionToNext` from CameraSegment construction
- Line 254: `transitionToNext: original.transitionToNext` from CursorSegment construction

- [ ] **Step 6: Update test helper methods**

In `ScreenizeTests/Generators/SegmentCamera/SegmentSpringSimulatorTests.swift`, remove from makeSegment:
```swift
transitionToNext: SegmentTransition(duration: 0, easing: .linear)
```

In `ScreenizeTests/Generators/SegmentCamera/SegmentCameraGeneratorTests.swift`, remove from makeSegment:
```swift
transitionToNext: SegmentTransition(duration: 0, easing: .linear)
```

- [ ] **Step 7: Build and verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```
git add -A && git commit -m "refactor: remove dead transitionToNext and SegmentTransition"
```

---

## Task 3: Create `SpringSimulationCache`

**Files:**
- Create: `Screenize/Render/SpringSimulationCache.swift`
- Create: `ScreenizeTests/Render/SpringSimulationCacheTests.swift`

- [ ] **Step 1: Write tests for SpringSimulationCache**

Create `ScreenizeTests/Render/SpringSimulationCacheTests.swift`:
```swift
import XCTest
@testable import Screenize

final class SpringSimulationCacheTests: XCTestCase {

    func test_lookup_emptyCache_returnsNil() {
        let cache = SpringSimulationCache()
        XCTAssertNil(cache.transforms(for: UUID()))
    }

    func test_simulateAndLookup_manualSegments_returnsCachedTransforms() {
        let cache = SpringSimulationCache()
        let segment = CameraSegment(
            startTime: 0, endTime: 1,
            kind: .manual(
                startTransform: TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5)),
                endTransform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.4))
            )
        )
        cache.populate(segments: [segment])
        let result = cache.transforms(for: segment.id)
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.isEmpty)
    }

    func test_lookup_continuousSegment_returnsNil() {
        let cache = SpringSimulationCache()
        let transform = TimedTransform(
            time: 0,
            transform: TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        )
        let segment = CameraSegment(
            startTime: 0, endTime: 1,
            kind: .continuous(transforms: [transform])
        )
        cache.populate(segments: [segment])
        XCTAssertNil(cache.transforms(for: segment.id))
    }

    func test_invalidate_clearsAllCachedTransforms() {
        let cache = SpringSimulationCache()
        let segment = CameraSegment(
            startTime: 0, endTime: 1,
            kind: .manual(
                startTransform: .identity,
                endTransform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.4))
            )
        )
        cache.populate(segments: [segment])
        XCTAssertNotNil(cache.transforms(for: segment.id))
        cache.invalidate()
        XCTAssertNil(cache.transforms(for: segment.id))
    }

    func test_isValid_lifecycle() {
        let cache = SpringSimulationCache()
        XCTAssertFalse(cache.isValid, "New cache should be invalid")

        let segment = CameraSegment(
            startTime: 0, endTime: 1,
            kind: .manual(startTransform: .identity, endTransform: .identity)
        )
        cache.populate(segments: [segment])
        XCTAssertTrue(cache.isValid, "Cache should be valid after populate")

        cache.invalidate()
        XCTAssertFalse(cache.isValid, "Cache should be invalid after invalidate")
    }
}
```

- [ ] **Step 2: Implement SpringSimulationCache**

Create `Screenize/Render/SpringSimulationCache.swift`:
```swift
import Foundation
import CoreGraphics

/// Caches spring-simulated transforms for manual camera segments.
/// The entire cache is invalidated on any segment edit because
/// SegmentSpringSimulator carries velocity between segments.
final class SpringSimulationCache {

    private var cache: [UUID: [TimedTransform]] = [:]
    private(set) var isValid: Bool = false

    /// Look up cached spring transforms for a segment.
    func transforms(for segmentID: UUID) -> [TimedTransform]? {
        cache[segmentID]
    }

    /// Run spring simulation on the given segments and cache results.
    /// Only `.manual` segments produce cached entries.
    func populate(
        segments: [CameraSegment],
        config: SegmentSpringSimulator.Config = .init(),
        cursorSpeeds: [UUID: CGFloat] = [:]
    ) {
        let simulated = SegmentSpringSimulator.simulate(
            segments: segments,
            config: config,
            cursorSpeeds: cursorSpeeds
        )
        cache.removeAll()
        for (original, result) in zip(segments, simulated) {
            if case .manual = original.kind,
               case .continuous(let transforms) = result.kind {
                cache[original.id] = transforms
            }
        }
        isValid = true
    }

    /// Clear all cached data.
    func invalidate() {
        cache.removeAll()
        isValid = false
    }
}
```

- [ ] **Step 3: Add new files to Xcode project**

Add `SpringSimulationCache.swift` and `SpringSimulationCacheTests.swift` to `Screenize.xcodeproj/project.pbxproj`. Check existing UUID prefixes first and use unused ones.

- [ ] **Step 4: Build and run tests**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```
git add -A && git commit -m "feat: add SpringSimulationCache for deferred spring simulation"
```

---

## Task 4: Wire SpringSimulationCache into render pipeline

**Files:**
- Modify: `Screenize/Render/FrameEvaluator.swift:42-60`
- Modify: `Screenize/Render/FrameEvaluator+Transform.swift:9-27`
- Modify: `Screenize/Render/RenderPipelineFactory.swift:13-51, 108-155`
- Modify: `Screenize/ViewModels/EditorViewModel.swift`
- Modify: `Screenize/Render/PreviewEngine+Setup.swift:102`
- Modify: `Screenize/Render/PreviewEngine+Timeline.swift:24, 89, 117`
- Modify: `Screenize/Render/ExportEngine+VideoExport.swift:64`
- Modify: `Screenize/Render/ExportEngine+GIFExport.swift:49`

- [ ] **Step 1: Add springCache property to FrameEvaluator**

In `Screenize/Render/FrameEvaluator.swift`, add stored property and init parameter:
```swift
var springCache: SpringSimulationCache?
```

Add `springCache: SpringSimulationCache? = nil` to init parameter list and `self.springCache = springCache` in body.

- [ ] **Step 2: Update evaluateTransform to check spring cache**

In `Screenize/Render/FrameEvaluator+Transform.swift`, update the `.manual` case in `evaluateTransform(at:)`:
```swift
case .manual(let startTransform, let endTransform):
    // Check spring cache first
    if let cachedTransforms = springCache?.transforms(for: segment.id),
       !cachedTransforms.isEmpty {
        return evaluateContinuousTransform(at: time, samples: cachedTransforms)
    }
    return evaluateManualTransform(
        at: time, segment: segment,
        startTransform: startTransform, endTransform: endTransform
    )
```

- [ ] **Step 3: Add springCache parameter to RenderPipelineFactory**

In `Screenize/Render/RenderPipelineFactory.swift`, add `springCache: SpringSimulationCache? = nil` parameter to both `createEvaluator()` overloads (lines 13 and 33), and pass it through to `FrameEvaluator(... springCache: springCache)`.

Also add it to `createPreviewPipeline()` (line 108) and `createExportPipeline()` (line 133), passing it through to `createEvaluator()`.

- [ ] **Step 4: Add springCache to EditorViewModel**

In `Screenize/ViewModels/EditorViewModel.swift`, add:
```swift
let springCache = SpringSimulationCache()

func invalidateSpringCache() {
    springCache.invalidate()
}

func populateSpringCacheIfNeeded() {
    guard !springCache.isValid else { return }
    guard let cameraTrack = project.timeline.cameraTrack else { return }
    springCache.populate(segments: cameraTrack.segments)
}
```

- [ ] **Step 5: Wire springCache through PreviewEngine**

In `Screenize/Render/PreviewEngine+Setup.swift` (line 102), pass `springCache` to `createPreviewPipeline()`.

In `Screenize/Render/PreviewEngine+Timeline.swift`, pass `springCache` to all 3 `createEvaluator()` calls (lines 24, 89, 117).

This requires PreviewEngine to hold a reference to the springCache. Add `var springCache: SpringSimulationCache?` property to PreviewEngine and set it during setup.

- [ ] **Step 6: Wire springCache through ExportEngine**

In `Screenize/Render/ExportEngine+VideoExport.swift` (line 64) and `ExportEngine+GIFExport.swift` (line 49), pass `springCache` to `createExportPipeline()`.

ExportEngine needs a `springCache` property. Add `var springCache: SpringSimulationCache?` and set it from EditorViewModel when initiating export.

- [ ] **Step 7: Wire invalidation to onSegmentChange**

Find where `onSegmentChange` is called from the inspector and add `invalidateSpringCache()` + `populateSpringCacheIfNeeded()`. The inspector already calls `onSegmentChange` on edits — add spring cache invalidation and re-population there.

- [ ] **Step 8: Build and verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Commit**

```
git add -A && git commit -m "feat: wire SpringSimulationCache into render pipeline"
```

---

## Task 5: Keep segments as `.manual` in SegmentCameraGenerator

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift:66-83`
- Modify: `Screenize/ViewModels/EditorViewModel.swift` (runSmartGeneration)

- [ ] **Step 1: Stop converting to continuous in SegmentCameraGenerator**

In `Screenize/Generators/SegmentCamera/SegmentCameraGenerator.swift`, change lines 66-78. Replace the `SegmentSpringSimulator.simulate()` call with the raw segments:

```swift
// Before:
let segments = SegmentSpringSimulator.simulate(
    segments: rawSegments,
    config: SegmentSpringSimulator.Config(...),
    cursorSpeeds: speeds
)

// After:
let segments = rawSegments
```

Keep the `speeds` computation (cursor speed per segment) and the `SegmentSpringSimulator.Config` construction — they'll be needed by the cache. Store `speeds` and `config` as return values. Add them to the generator's return type or store on a property that EditorViewModel can access after generation.

**Approach:** Add `cursorSpeeds` and `springConfig` properties to `SegmentCameraGenerator` that are populated during `generate()`, so `EditorViewModel` can read them after generation and pass to `springCache.populate()`.

- [ ] **Step 2: Populate spring cache after generation**

In `EditorViewModel.swift`, after `runSmartGeneration()` completes:
```swift
// After generation stores .manual segments in timeline:
if let cameraTrack = project.timeline.cameraTrack {
    springCache.populate(
        segments: cameraTrack.segments,
        config: generator.springConfig,
        cursorSpeeds: generator.cursorSpeeds
    )
}
```

Also call `populateSpringCacheIfNeeded()` after loading a project (in `setup()`), so existing projects with `.manual` segments get their spring cache populated.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```
git add -A && git commit -m "feat: keep camera segments as .manual, defer spring simulation to cache"
```

---

## Task 6: Continuous segment info label in inspector

**Files:**
- Modify: `Screenize/Views/Inspector/InspectorView+CameraSection.swift:25-27`

- [ ] **Step 1: Add info label for continuous segments**

In `Screenize/Views/Inspector/InspectorView+CameraSection.swift`, replace:
```swift
if !binding.wrappedValue.isContinuous {
    manualCameraControls(segment: binding)
}
```
with:
```swift
if binding.wrappedValue.isContinuous {
    Label(
        "Continuous segment has no configurable options.",
        systemImage: "info.circle"
    )
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.top, 4)
} else {
    manualCameraControls(segment: binding)
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```
git add -A && git commit -m "feat: add info label for continuous camera segments in inspector"
```

---

## Task 7: Run full test suite and lint

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | grep -E "(Test Suite|Tests|PASS|FAIL)" | tail -20`
Expected: All tests pass

- [ ] **Step 2: Run lint**

Run: `./scripts/lint.sh`
Expected: No new violations

- [ ] **Step 3: Fix any failures and commit**

If any test or lint failures, fix and commit individually.
