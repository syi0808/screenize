# Camera Segment Kind Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace implicit continuous/manual camera segment branching with an explicit `CameraSegmentKind` enum, making the two segment behaviors type-safe and visually distinct.

**Architecture:** Add a `CameraSegmentKind` enum with `.continuous(transforms:)` and `.manual(startTransform:endTransform:interpolation:)` cases. Replace the flat fields on `CameraSegment` with a single `kind` property. Update all consumers (evaluator, generators, views, tests) to use the new structure.

**Tech Stack:** Swift, SwiftUI, CoreGraphics

**Spec:** `docs/superpowers/specs/2026-03-12-camera-segment-kind-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Screenize/Timeline/Segments.swift` | Modify | Add `CameraSegmentKind` enum, rewrite `CameraSegment` struct |
| `Screenize/Render/FrameEvaluator+Transform.swift` | Modify | Switch-based dispatch on `segment.kind` |
| `Screenize/Generators/SegmentCamera/SegmentPlanner.swift` | Modify | Emit `.manual` kind segments |
| `Screenize/Generators/SegmentCamera/SegmentSpringSimulator.swift` | Modify | Read manual targets, write `.continuous` kind |
| `Screenize/Generators/ContinuousCamera/ContinuousCameraGenerator.swift` | Modify | Emit `.continuous` kind segment |
| `Screenize/Render/MouseDataConverter.swift` | Modify | Extract continuous transforms via `kind` enum |
| `Screenize/ViewModels/EditorViewModel+Clipboard.swift` | Modify | Use `kind` for duplicate/paste |
| `Screenize/ViewModels/EditorViewModel+SegmentOperations.swift` | Modify | Use `.manual` kind for new segments |
| `Screenize/Views/Inspector/InspectorView+CameraSection.swift` | Modify | Branch on `isContinuous` for inspector UI |
| `Screenize/Views/Inspector/InspectorView+SegmentBindings.swift` | Modify | Update fallback segment construction |
| `Screenize/Project/ProjectCreator.swift` | Modify | Use `.manual` kind for default timeline |
| `Screenize/Views/GeneratorPanelView.swift` | Modify | Update preview segment construction |
| `ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift` | Modify | Access zoom/transforms via `kind` |

---

## Chunk 1: Type System + Core Evaluation

### Task 1: Add CameraSegmentKind enum and rewrite CameraSegment

**Files:**
- Modify: `Screenize/Timeline/Segments.swift:49-94`

- [ ] **Step 1: Add `CameraSegmentKind` enum above `CameraSegment`**

Replace lines 49-52 (`CameraSegmentMode`) and rewrite lines 54-94 (`CameraSegment`):

```swift
// MARK: - Camera Segment

enum CameraSegmentKind: Codable, Equatable {
    case continuous(transforms: [TimedTransform])
    case manual(
        startTransform: TransformValue,
        endTransform: TransformValue,
        interpolation: EasingCurve
    )

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type
        case transforms
        case startTransform
        case endTransform
        case interpolation
    }

    private enum KindType: String, Codable {
        case continuous
        case manual
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(KindType.self, forKey: .type)
        switch type {
        case .continuous:
            let transforms = try container.decode([TimedTransform].self, forKey: .transforms)
            self = .continuous(transforms: transforms)
        case .manual:
            let startTransform = try container.decode(TransformValue.self, forKey: .startTransform)
            let endTransform = try container.decode(TransformValue.self, forKey: .endTransform)
            let interpolation = try container.decode(EasingCurve.self, forKey: .interpolation)
            self = .manual(
                startTransform: startTransform,
                endTransform: endTransform,
                interpolation: interpolation
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .continuous(let transforms):
            try container.encode(KindType.continuous, forKey: .type)
            try container.encode(transforms, forKey: .transforms)
        case .manual(let startTransform, let endTransform, let interpolation):
            try container.encode(KindType.manual, forKey: .type)
            try container.encode(startTransform, forKey: .startTransform)
            try container.encode(endTransform, forKey: .endTransform)
            try container.encode(interpolation, forKey: .interpolation)
        }
    }
}

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

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        kind: CameraSegmentKind,
        transitionToNext: SegmentTransition = .default
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.kind = kind
        self.transitionToNext = transitionToNext
    }
}
```

Also delete the `CameraSegmentMode` enum (lines 49-52) and the `CursorFollowConfig` struct stays (lines 16-30, used internally by generators).

- [ ] **Step 2: Build to see all compilation errors**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | grep "error:" | head -30`

Expected: ~15-20 errors across files that construct or access removed fields. This confirms the scope of changes needed.

- [ ] **Step 3: Commit type system change**

```
git add Screenize/Timeline/Segments.swift
git commit -m "refactor: replace CameraSegment flat fields with CameraSegmentKind enum"
```

---

### Task 2: Update FrameEvaluator to use CameraSegmentKind

**Files:**
- Modify: `Screenize/Render/FrameEvaluator+Transform.swift:9-63`

- [ ] **Step 1: Rewrite `evaluateTransform(at:)` with switch dispatch**

Replace the current method body (lines 9-63) with:

```swift
func evaluateTransform(at time: TimeInterval) -> TransformState {
    guard let track = timeline.cameraTrack, track.isEnabled else {
        return .identity
    }

    guard let segment = track.activeSegment(at: time) else {
        return .identity
    }

    switch segment.kind {
    case .continuous(let samples):
        guard !samples.isEmpty else { return .identity }
        return evaluateContinuousTransform(at: time, samples: samples)
    case .manual(let startTransform, let endTransform, let interpolation):
        return evaluateManualTransform(
            at: time,
            segment: segment,
            startTransform: startTransform,
            endTransform: endTransform,
            interpolation: interpolation
        )
    }
}
```

- [ ] **Step 2: Extract manual evaluation into `evaluateManualTransform` method**

Add a new method after `evaluateTransform`:

```swift
private func evaluateManualTransform(
    at time: TimeInterval,
    segment: CameraSegment,
    startTransform: TransformValue,
    endTransform: TransformValue,
    interpolation: EasingCurve
) -> TransformState {
    let duration = max(0.001, segment.endTime - segment.startTime)
    let rawProgress = CGFloat((time - segment.startTime) / duration)
    let progress = interpolation.apply(rawProgress, duration: CGFloat(duration))
    let derivative = interpolation.derivative(rawProgress, duration: CGFloat(duration))
    let interpolatedValue: TransformValue

    if isWindowMode {
        interpolatedValue = startTransform.interpolatedForWindowMode(
            to: endTransform, amount: progress
        )
    } else {
        interpolatedValue = startTransform.interpolated(
            to: endTransform, amount: progress
        )
    }

    let finalCenter = interpolatedValue.center
    let clampedCenter = isWindowMode
        ? finalCenter
        : clampCenterForZoom(center: finalCenter, zoom: interpolatedValue.zoom)

    return TransformState(
        zoom: interpolatedValue.zoom,
        center: clampedCenter,
        zoomVelocity: abs(
            derivative * (endTransform.zoom - startTransform.zoom)
                / CGFloat(duration)
        ),
        panVelocity: abs(derivative) * hypot(
            endTransform.center.x - startTransform.center.x,
            endTransform.center.y - startTransform.center.y
        ) / CGFloat(duration),
        panDirection: atan2(
            endTransform.center.y - startTransform.center.y,
            endTransform.center.x - startTransform.center.x
        )
    )
}
```

- [ ] **Step 3: Commit**

```
git add Screenize/Render/FrameEvaluator+Transform.swift
git commit -m "refactor: use switch on CameraSegmentKind in FrameEvaluator"
```

---

## Chunk 2: Generator Pipeline Updates

### Task 3: Update SegmentPlanner to emit `.manual` kind

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift:157-166`

- [ ] **Step 1: Update `buildSegments()` to construct `.manual` kind**

Replace the CameraSegment constructor at lines 157-166:

```swift
let segment = CameraSegment(
    startTime: plan.scene.startTime,
    endTime: plan.scene.endTime,
    kind: .manual(
        startTransform: startTransform,
        endTransform: endTransform,
        interpolation: .easeInOut
    ),
    transitionToNext: SegmentTransition(duration: 0, easing: .linear)
)
```

- [ ] **Step 2: Commit**

```
git add Screenize/Generators/SegmentCamera/SegmentPlanner.swift
git commit -m "refactor: update SegmentPlanner to emit .manual kind segments"
```

---

### Task 4: Update SegmentSpringSimulator to read/write via kind

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentSpringSimulator.swift:33,46,117-118`

- [ ] **Step 1: Update `simulate()` to extract transforms from `.manual` kind**

At line 33, change initialization to extract from kind:

```swift
// Replace:
let initial = segments[0].startTransform

// With:
let initial: TransformValue
switch segments[0].kind {
case .manual(let start, _, _):
    initial = start
case .continuous(let transforms):
    initial = transforms.first?.transform ?? TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))
}
```

At line 46, change target extraction:

```swift
// Replace:
let target = segment.endTransform

// With:
let target: TransformValue
switch segment.kind {
case .manual(_, let end, _):
    target = end
case .continuous(let transforms):
    target = transforms.last?.transform ?? TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))
}
```

At lines 117-118, change output to `.continuous` kind:

```swift
// Replace:
var updated = segment
updated.continuousTransforms = samples
result.append(updated)

// With:
var updated = segment
updated.kind = .continuous(transforms: samples)
result.append(updated)
```

- [ ] **Step 2: Commit**

```
git add Screenize/Generators/SegmentCamera/SegmentSpringSimulator.swift
git commit -m "refactor: update SegmentSpringSimulator to use CameraSegmentKind"
```

---

### Task 5: Update ContinuousCameraGenerator to emit `.continuous` kind

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraGenerator.swift:138-144`

- [ ] **Step 1: Update `createDisplayTrack` segment construction**

Replace lines 138-144:

```swift
let segment = CameraSegment(
    startTime: first.time,
    endTime: max(first.time + 0.001, last.time > 0 ? last.time : duration),
    kind: .continuous(transforms: samples)
)
```

- [ ] **Step 2: Commit**

```
git add Screenize/Generators/ContinuousCamera/ContinuousCameraGenerator.swift
git commit -m "refactor: update ContinuousCameraGenerator to emit .continuous kind"
```

### Task 6: Update MouseDataConverter

**Files:**
- Modify: `Screenize/Render/MouseDataConverter.swift:100-102`

- [ ] **Step 1: Extract continuous transforms via `kind` enum**

Replace lines 100-102:

```swift
// Replace:
// Uses first continuous segment's transforms (generator produces exactly one)
cameraTransforms: project.timeline.cameraTrack?.segments
    .first(where: { $0.isContinuous })?.continuousTransforms

// With:
// Uses first continuous segment's transforms (generator produces exactly one)
cameraTransforms: project.timeline.cameraTrack?.segments
    .first(where: { $0.isContinuous }).flatMap {
        if case .continuous(let transforms) = $0.kind { return transforms }
        return nil
    }
```

- [ ] **Step 2: Commit**

```
git add Screenize/Render/MouseDataConverter.swift
git commit -m "refactor: update MouseDataConverter to extract transforms via CameraSegmentKind"
```

---

## Chunk 3: ViewModel & View Updates

### Task 7: Update EditorViewModel+Clipboard

**Files:**
- Modify: `Screenize/ViewModels/EditorViewModel+Clipboard.swift:166-174,234-242`

- [ ] **Step 1: Update `duplicateCameraSegment` to copy `kind`**

Replace lines 166-174:

```swift
let duplicate = CameraSegment(
    startTime: newStart,
    endTime: newEnd,
    kind: original.kind,
    transitionToNext: original.transitionToNext
)
```

- [ ] **Step 2: Update `insertCameraSegment` to copy `kind`**

Replace lines 234-242:

```swift
let pasted = CameraSegment(
    startTime: startTime,
    endTime: endTime,
    kind: original.kind,
    transitionToNext: original.transitionToNext
)
```

- [ ] **Step 3: Commit**

```
git add Screenize/ViewModels/EditorViewModel+Clipboard.swift
git commit -m "refactor: update clipboard operations to use CameraSegmentKind"
```

---

### Task 8: Update EditorViewModel+SegmentOperations

**Files:**
- Modify: `Screenize/ViewModels/EditorViewModel+SegmentOperations.swift:46-51`

- [ ] **Step 1: Update `addTransformSegment` to use `.manual` kind**

Replace lines 46-51:

```swift
let newSegment = CameraSegment(
    startTime: time,
    endTime: max(time + 0.05, endTime),
    kind: .manual(
        startTransform: .identity,
        endTransform: .identity,
        interpolation: .easeInOut
    )
)
```

- [ ] **Step 2: Commit**

```
git add Screenize/ViewModels/EditorViewModel+SegmentOperations.swift
git commit -m "refactor: update addTransformSegment to use .manual kind"
```

---

### Task 9: Update InspectorView+CameraSection

**Files:**
- Modify: `Screenize/Views/Inspector/InspectorView+CameraSection.swift:8-59`

- [ ] **Step 1: Branch inspector UI on `isContinuous`**

Replace the `cameraSection` body (lines 8-59):

```swift
@ViewBuilder
func cameraSection(segmentID: UUID) -> some View {
    if let binding = cameraSegmentBinding(for: segmentID) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera")
                .font(.subheadline.weight(.medium))

            timeRangeFields(
                start: Binding(
                    get: { binding.wrappedValue.startTime },
                    set: { binding.wrappedValue.startTime = $0 }
                ),
                end: Binding(
                    get: { binding.wrappedValue.endTime },
                    set: { binding.wrappedValue.endTime = $0 }
                )
            )

            if !binding.wrappedValue.isContinuous {
                manualCameraControls(segment: binding)
            }
        }
    } else {
        Text("Camera segment not found")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

@ViewBuilder
private func manualCameraControls(segment: Binding<CameraSegment>) -> some View {
    if case .manual(let startTransform, let endTransform, _) = segment.wrappedValue.kind {
        // Start Zoom
        zoomControl(
            label: "Start Zoom",
            segment: segment,
            isStart: true
        )

        // End Zoom
        zoomControl(
            label: "End Zoom",
            segment: segment,
            isStart: false
        )

        Divider()

        // Start Position
        positionControl(
            label: "Start Position",
            segment: segment,
            isStart: true
        )

        // End Position
        positionControl(
            label: "End Position",
            segment: segment,
            isStart: false
        )
    }
}
```

- [ ] **Step 2: Update `zoomControl` and `positionControl` to work with `kind`**

The existing `zoomControl` and `positionControl` use `WritableKeyPath<CameraSegment, TransformValue>` which no longer works since transforms are inside the enum. Rewrite them to take an `isStart: Bool` parameter and extract/update transforms via the `kind`:

```swift
func zoomControl(
    label: String,
    segment: Binding<CameraSegment>,
    isStart: Bool
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        let currentZoom = extractTransform(from: segment.wrappedValue, isStart: isStart).zoom

        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text("\(Int(currentZoom * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        HStack(spacing: 8) {
            Slider(value: Binding(
                get: { Double(extractTransform(from: segment.wrappedValue, isStart: isStart).zoom) },
                set: { newZoom in
                    updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                        TransformValue(zoom: CGFloat(newZoom), center: transform.center)
                    }
                }
            ), in: 1...5, step: 0.1)
            TextField("", value: Binding(
                get: { Double(extractTransform(from: segment.wrappedValue, isStart: isStart).zoom) },
                set: { newZoom in
                    updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                        TransformValue(zoom: max(1, min(5, CGFloat(newZoom))), center: transform.center)
                    }
                }
            ), format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
        }
    }
}

func positionControl(
    label: String,
    segment: Binding<CameraSegment>,
    isStart: Bool
) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)

        CenterPointPicker(
            centerX: Binding(
                get: { extractTransform(from: segment.wrappedValue, isStart: isStart).center.x },
                set: { newX in
                    updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                        TransformValue(
                            zoom: transform.zoom,
                            center: NormalizedPoint(x: newX, y: transform.center.y)
                        )
                    }
                }
            ),
            centerY: Binding(
                get: { extractTransform(from: segment.wrappedValue, isStart: isStart).center.y },
                set: { newY in
                    updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                        TransformValue(
                            zoom: transform.zoom,
                            center: NormalizedPoint(x: transform.center.x, y: newY)
                        )
                    }
                }
            ),
            onChange: onSegmentChange
        )
        .frame(height: 100)

        HStack(spacing: 8) {
            Text("X")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 12)
            TextField("", value: Binding(
                get: { Double(extractTransform(from: segment.wrappedValue, isStart: isStart).center.x) },
                set: { newX in
                    updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                        TransformValue(
                            zoom: transform.zoom,
                            center: NormalizedPoint(x: max(0, min(1, CGFloat(newX))), y: transform.center.y)
                        )
                    }
                    onSegmentChange?()
                }
            ), format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
            Text("Y")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 12)
            TextField("", value: Binding(
                get: { Double(extractTransform(from: segment.wrappedValue, isStart: isStart).center.y) },
                set: { newY in
                    updateTransform(in: &segment.wrappedValue, isStart: isStart) { transform in
                        TransformValue(
                            zoom: transform.zoom,
                            center: NormalizedPoint(x: transform.center.x, y: max(0, min(1, CGFloat(newY))))
                        )
                    }
                    onSegmentChange?()
                }
            ), format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Transform Helpers

private func extractTransform(from segment: CameraSegment, isStart: Bool) -> TransformValue {
    guard case .manual(let startTransform, let endTransform, _) = segment.kind else {
        return .identity
    }
    return isStart ? startTransform : endTransform
}

private func updateTransform(
    in segment: inout CameraSegment,
    isStart: Bool,
    update: (TransformValue) -> TransformValue
) {
    guard case .manual(var startTransform, var endTransform, let interpolation) = segment.kind else {
        return
    }
    if isStart {
        startTransform = update(startTransform)
    } else {
        endTransform = update(endTransform)
    }
    segment.kind = .manual(
        startTransform: startTransform,
        endTransform: endTransform,
        interpolation: interpolation
    )
}
```

- [ ] **Step 3: Commit**

```
git add Screenize/Views/Inspector/InspectorView+CameraSection.swift
git commit -m "refactor: update inspector camera section for CameraSegmentKind"
```

---

### Task 10: Update InspectorView+SegmentBindings

**Files:**
- Modify: `Screenize/Views/Inspector/InspectorView+SegmentBindings.swift:21`

- [ ] **Step 1: Update fallback segment construction**

Replace line 21:

```swift
// Replace:
return CameraSegment(startTime: 0, endTime: 1, startTransform: .identity, endTransform: .identity)

// With:
return CameraSegment(
    startTime: 0,
    endTime: 1,
    kind: .manual(startTransform: .identity, endTransform: .identity, interpolation: .easeInOut)
)
```

- [ ] **Step 2: Commit**

```
git add Screenize/Views/Inspector/InspectorView+SegmentBindings.swift
git commit -m "refactor: update segment binding fallback for CameraSegmentKind"
```

---

### Task 11: Update ProjectCreator

**Files:**
- Modify: `Screenize/Project/ProjectCreator.swift:192-198`

- [ ] **Step 1: Update default timeline segment construction**

Replace lines 192-198:

```swift
CameraSegment(
    startTime: 0,
    endTime: max(0.1, duration),
    kind: .manual(
        startTransform: .identity,
        endTransform: .identity,
        interpolation: .easeInOut
    )
),
```

- [ ] **Step 2: Commit**

```
git add Screenize/Project/ProjectCreator.swift
git commit -m "refactor: update ProjectCreator default segment for CameraSegmentKind"
```

---

### Task 12: Update GeneratorPanelView

**Files:**
- Modify: `Screenize/Views/GeneratorPanelView.swift:195`

- [ ] **Step 1: Update preview segment construction**

Replace line 195:

```swift
// Replace:
CameraSegment(startTime: 0, endTime: 5, startTransform: .identity, endTransform: .identity),

// With:
CameraSegment(startTime: 0, endTime: 5, kind: .manual(startTransform: .identity, endTransform: .identity, interpolation: .easeInOut)),
```

- [ ] **Step 2: Commit**

```
git add Screenize/Views/GeneratorPanelView.swift
git commit -m "refactor: update GeneratorPanelView preview segment for CameraSegmentKind"
```

---

## Chunk 4: Tests

### Task 13: Update ContinuousCameraGeneratorTests

**Files:**
- Modify: `ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift`

- [ ] **Step 1: Update tests that access `startTransform`/`endTransform` directly**

These tests need to extract zoom values from the `kind` enum instead of direct field access.

Add a test helper at the bottom of the test class (before the existing helpers):

```swift
// MARK: - Kind Helpers

private func extractZooms(from segment: CameraSegment) -> (start: CGFloat, end: CGFloat) {
    switch segment.kind {
    case .manual(let start, let end, _):
        return (start.zoom, end.zoom)
    case .continuous(let transforms):
        return (transforms.first?.transform.zoom ?? 1.0, transforms.last?.transform.zoom ?? 1.0)
    }
}

private func extractContinuousTransforms(from segment: CameraSegment) -> [TimedTransform]? {
    if case .continuous(let transforms) = segment.kind {
        return transforms
    }
    return nil
}
```

Update `test_generate_zoomWithinBounds` (lines 89-94):

```swift
for segment in result.cameraTrack.segments {
    let zooms = extractZooms(from: segment)
    XCTAssertGreaterThanOrEqual(zooms.start, 0.99)
    XCTAssertLessThanOrEqual(zooms.start, 2.81)
    XCTAssertGreaterThanOrEqual(zooms.end, 0.99)
    XCTAssertLessThanOrEqual(zooms.end, 2.81)
}
```

Update `test_generate_zoomIntensity_scalesZoom` (lines 123-126):

```swift
let defaultMaxZoom = defaultResult.cameraTrack.segments
    .flatMap { seg in let z = extractZooms(from: seg); return [z.start, z.end] }.max() ?? 1.0
let highMaxZoom = highResult.cameraTrack.segments
    .flatMap { seg in let z = extractZooms(from: seg); return [z.start, z.end] }.max() ?? 1.0
```

Update `test_generate_withClicks_producesZoomedSegments` (lines 143-144):

```swift
let hasZoomedSegment = result.cameraTrack.segments.contains {
    let zooms = extractZooms(from: $0)
    return zooms.start > 1.01 || zooms.end > 1.01
}
```

Update `test_generate_quietStart_startsWithEstablishingShot` (line 160):

```swift
guard let firstSeg = result.cameraTrack.segments.first,
      let first = extractContinuousTransforms(from: firstSeg)?.first else {
    XCTFail("Expected continuous transforms for quiet-start recording")
    return
}
```

Update `test_generate_immediateClick_releasesStartupBiasEarly` (line 182):

```swift
guard let firstSeg = result.cameraTrack.segments.first,
      let samples = extractContinuousTransforms(from: firstSeg),
      let first = samples.first,
      let postRelease = samples.first(where: { $0.time >= 0.35 }) else {
    XCTFail("Expected generated continuous transforms")
    return
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ContinuousCameraGeneratorTests 2>&1 | tail -20`

Expected: All tests pass.

- [ ] **Step 3: Commit**

```
git add ScreenizeTests/Generators/ContinuousCamera/ContinuousCameraGeneratorTests.swift
git commit -m "refactor: update ContinuousCameraGeneratorTests for CameraSegmentKind"
```

---

**Note:** Timeline segment view visual distinction (different background color/pattern for continuous vs manual) is deferred — it requires UI design decisions for specific colors/patterns. The `isContinuous` property is available for future implementation.

---

## Chunk 5: Build Verification

### Task 14: Full build and lint verification

- [ ] **Step 1: Run full build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: Run lint**

Run: `./scripts/lint.sh`

Expected: No new violations.

- [ ] **Step 3: Run all tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | tail -10`

Expected: All tests pass.
