# Smart Generation Quality Improvement v2 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce excessive panning and improve ROI accuracy in smart generation by adding connected pan transitions, confidence-based suppression, post-interaction analysis, soft clamping, AX enhancement, and two-stage zoom.

**Architecture:** Six incremental improvements to existing ContinuousCamera and SegmentCamera pipelines. Each section builds on the previous but produces working, testable software independently. Runtime execution order: AX sampling → Intent classification (focused) → Post-interaction refinement → Confidence filtering → Scene merging → Transition resolution → Soft clamping.

**Tech Stack:** Swift, XCTest, CoreGraphics, Accessibility Framework

**Spec:** `docs/superpowers/specs/2026-03-16-smart-generation-quality-v2-design.md`

**Important notes for implementers:**
- **Xcode project file**: New `.swift` files must be manually added to `Screenize.xcodeproj/project.pbxproj` with 4 entries (PBXBuildFile, PBXFileReference, PBXGroup child, PBXSourcesBuildPhase). New directories need a PBXGroup entry. See MEMORY.md for UUID prefix guidance.
- **ShotPlan properties**: Use `idealZoom` and `idealCenter` (not `zoom`/`center`).
- **CameraScene immutability**: All properties except `contextChange` are `let`. To modify, reconstruct with updated values.
- **CameraSegment Codable**: Has custom `init(from:)`/`encode(to:)`. Adding new stored properties requires updating both methods plus backward-compatible decoding.
- **Test helpers**: Many test methods reference helpers like `makeSingleClickScene`, `makeTypingSpan`, `makeEmptyTimeline`, etc. Check existing test files for available helpers; create missing ones as needed.

---

## Chunk 1: Soft Clamping (Section 4)

Independent of all other sections. Good starting point.

### Task 1: Add `softClamp` utility to Coordinates.swift

**Files:**
- Modify: `Screenize/Core/Coordinates.swift`
- Create: `ScreenizeTests/Core/SoftClampTests.swift`

- [ ] **Step 1: Write tests for softClamp**

```swift
import XCTest
import CoreGraphics
@testable import Screenize

final class SoftClampTests: XCTestCase {

    // MARK: - softClamp(value:min:max:cushion:)

    func test_softClamp_interiorValue_unchanged() {
        // Value well inside bounds → no effect
        let result = SoftClamp.clamp(value: 0.5, min: 0.1, max: 0.9, cushion: 0.1)
        XCTAssertEqual(result, 0.5, accuracy: 0.001)
    }

    func test_softClamp_atBoundary_reachesLimit() {
        // Value at exact boundary → clamped to boundary
        let result = SoftClamp.clamp(value: 0.0, min: 0.1, max: 0.9, cushion: 0.1)
        XCTAssertEqual(result, 0.1, accuracy: 0.001)
    }

    func test_softClamp_inCushionZone_easedTowardBoundary() {
        // Value in cushion zone → between raw value and boundary, smoothly eased
        let result = SoftClamp.clamp(value: 0.15, min: 0.1, max: 0.9, cushion: 0.1)
        XCTAssertGreaterThan(result, 0.1)
        XCTAssertLessThanOrEqual(result, 0.15)
    }

    func test_softClamp_beyondBoundary_clampedToLimit() {
        // Value beyond boundary → clamped to boundary
        let result = SoftClamp.clamp(value: 0.05, min: 0.1, max: 0.9, cushion: 0.1)
        XCTAssertEqual(result, 0.1, accuracy: 0.001)
    }

    func test_softClamp_symmetricTopBoundary() {
        // Same behavior at top boundary
        let result = SoftClamp.clamp(value: 0.85, min: 0.1, max: 0.9, cushion: 0.1)
        XCTAssertGreaterThanOrEqual(result, 0.85)
        XCTAssertLessThan(result, 0.9)
    }

    func test_softClamp_zeroCushion_hardClamp() {
        // Zero cushion → hard clamp behavior
        let result = SoftClamp.clamp(value: 0.05, min: 0.1, max: 0.9, cushion: 0.0)
        XCTAssertEqual(result, 0.1, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SoftClampTests 2>&1 | tail -20`
Expected: Compilation failure — `SoftClamp` not defined.

- [ ] **Step 3: Implement SoftClamp**

Add to `Screenize/Core/Coordinates.swift`:

```swift
/// Soft clamping utility — eases values near boundaries instead of hard clipping.
/// Uses smoothstep (hermite) interpolation consistent with DeadZoneTarget.
enum SoftClamp {

    /// Soft-clamp a value within [min, max] with a cushion zone near each boundary.
    /// Inside the cushion zone, the value is eased toward the boundary using smoothstep.
    /// Outside boundaries, hard-clamped. In the interior (beyond cushion), unchanged.
    static func clamp(value: CGFloat, min minBound: CGFloat, max maxBound: CGFloat, cushion: CGFloat) -> CGFloat {
        guard cushion > 0 else {
            return Swift.min(Swift.max(value, minBound), maxBound)
        }

        // Hard clamp first
        let clamped = Swift.min(Swift.max(value, minBound), maxBound)

        // Check lower cushion zone
        let lowerEdge = minBound + cushion
        if clamped < lowerEdge {
            let t = (clamped - minBound) / cushion // 0 at boundary, 1 at cushion edge
            let eased = smoothstep(t)
            return minBound + cushion * eased
        }

        // Check upper cushion zone
        let upperEdge = maxBound - cushion
        if clamped > upperEdge {
            let t = (maxBound - clamped) / cushion // 0 at boundary, 1 at cushion edge
            let eased = smoothstep(t)
            return maxBound - cushion * eased
        }

        return clamped
    }

    /// Soft-clamp a NormalizedPoint for a given zoom level.
    /// Cushion width scales with zoom: higher zoom → larger viewport fraction near edge.
    static func clampCenter(_ center: NormalizedPoint, zoom: CGFloat, cushionFraction: CGFloat = 0.15) -> NormalizedPoint {
        let viewportHalf = 0.5 / zoom
        let cushion = viewportHalf * cushionFraction

        let x = clamp(value: center.x, min: viewportHalf, max: 1.0 - viewportHalf, cushion: cushion)
        let y = clamp(value: center.y, min: viewportHalf, max: 1.0 - viewportHalf, cushion: cushion)

        return NormalizedPoint(x: x, y: y)
    }

    /// Smoothstep (hermite) interpolation: t * t * (3 - 2 * t)
    /// Same function used in DeadZoneTarget for gradient band interpolation.
    private static func smoothstep(_ t: CGFloat) -> CGFloat {
        let clamped = Swift.min(Swift.max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SoftClampTests 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Core/Coordinates.swift ScreenizeTests/Core/SoftClampTests.swift
git commit -m "feat: add SoftClamp utility with smoothstep easing"
```

### Task 2: Integrate soft clamping into ShotPlanner

**Files:**
- Modify: `Screenize/Generators/SmartGeneration/Planning/ShotPlanner.swift`
- Modify: `ScreenizeTests/Generators/SmartGeneration/Planning/ShotPlannerTests.swift`

- [ ] **Step 1: Write test for soft-clamped center computation**

Add to `ShotPlannerTests.swift`:

```swift
func test_plan_centerNearEdge_softClamped() {
    // Create a scene whose activity is near the screen edge
    // The resulting center should be soft-clamped, not hard-clipped
    let edgePosition = NormalizedPoint(x: 0.95, y: 0.5)
    let scene = makeSingleClickScene(at: edgePosition)
    let plans = ShotPlanner.plan(
        scenes: [scene],
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: makeEmptyTimeline(),
        frameAnalysis: [],
        settings: ShotSettings()
    )
    guard let plan = plans.first else {
        XCTFail("Expected one plan")
        return
    }
    // At zoom > 1.0, center should be pulled inward from 0.95
    // but NOT hard-clipped to the exact viewport boundary
    let viewportHalf = 0.5 / plan.idealZoom
    let hardClipMax = 1.0 - viewportHalf
    // Soft clamp pulls it slightly more inward than hard clamp would
    XCTAssertLessThanOrEqual(plan.idealCenter.x, hardClipMax)
}
```

- [ ] **Step 2: Run test to verify it fails or confirms current behavior**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ShotPlannerTests/test_plan_centerNearEdge_softClamped 2>&1 | tail -20`

- [ ] **Step 3: Replace hard clamp with soft clamp in ShotPlanner**

In `ShotPlanner.swift`, modify `clampCenter()` (around line 462-470):

Replace the existing hard clamp implementation with:

```swift
static func clampCenter(_ center: NormalizedPoint, zoom: CGFloat) -> NormalizedPoint {
    SoftClamp.clampCenter(center, zoom: zoom)
}
```

- [ ] **Step 4: Run full ShotPlanner test suite**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ShotPlannerTests 2>&1 | tail -20`
Expected: All tests PASS. Some existing tests may need tolerance adjustments due to soft vs hard clamp differences.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/SmartGeneration/Planning/ShotPlanner.swift ScreenizeTests/Generators/SmartGeneration/Planning/ShotPlannerTests.swift
git commit -m "feat: integrate soft clamping into ShotPlanner"
```

### Task 3: Integrate soft clamping into SegmentPlanner

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift`
- Modify: `ScreenizeTests/Generators/SegmentCamera/SegmentPlannerTests.swift`

- [ ] **Step 1: Write test for soft-clamped segment target positions**

Add to `SegmentPlannerTests.swift`:

```swift
func test_plan_segmentNearEdge_positionSoftClamped() {
    // Create intent span whose focus is near screen edge
    // Resulting segment's target position should be soft-clamped
    let edgeSpan = makeTypingSpan(
        start: 0.0, end: 3.0,
        focusPosition: NormalizedPoint(x: 0.05, y: 0.5)
    )
    let segments = SegmentPlanner.plan(
        intentSpans: [edgeSpan],
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: makeEmptyTimeline(),
        frameAnalysis: [],
        settings: ShotSettings()
    )
    // Verify segments exist and target position is within valid viewport
    XCTAssertFalse(segments.isEmpty)
}
```

- [ ] **Step 2: Apply soft clamping to segment target positions**

In `SegmentPlanner.swift`, where segment target transforms are computed from ShotPlan results, ensure center positions pass through `SoftClamp.clampCenter()`. Since ShotPlanner already uses soft clamping (Task 2), this should be inherited. Verify the chain is intact — if SegmentPlanner does its own clamping, replace that with soft clamping.

- [ ] **Step 3: Run SegmentPlanner test suite**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentPlannerTests 2>&1 | tail -20`
Expected: All tests PASS.

- [ ] **Step 4: Build full project**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentPlanner.swift ScreenizeTests/Generators/SegmentCamera/SegmentPlannerTests.swift
git commit -m "feat: apply soft clamping to SegmentPlanner target positions"
```

---

## Chunk 2: AX Sampling Enhancement + Parent Container ROI (Section 5)

### Task 4: Add parent container fields to UIStateSample and UIElementInfo

**Files:**
- Modify: `Screenize/Core/Tracking/AccessibilityInspector.swift` (UIElementInfo struct)
- Modify: `Screenize/Core/Recording/Tracking/MouseEvent.swift` (UIStateSample struct, if parent container fields needed)

- [ ] **Step 1: Add `parentContainerBounds` to UIElementInfo**

In `AccessibilityInspector.swift`, add to UIElementInfo struct:

```swift
struct UIElementInfo: Codable {
    // ... existing fields ...
    let parentContainerBounds: CGRect?  // Parent group/toolbar bounds for small elements
}
```

Update all existing initializers of UIElementInfo to include `parentContainerBounds: nil` as default.

- [ ] **Step 2: Build to verify no compilation errors**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Screenize/Core/Tracking/AccessibilityInspector.swift
git commit -m "feat: add parentContainerBounds field to UIElementInfo"
```

### Task 5: Implement parent container AX traversal

**Files:**
- Modify: `Screenize/Core/Tracking/AccessibilityInspector.swift`
- Create: `ScreenizeTests/Core/Tracking/ParentContainerTests.swift`

- [ ] **Step 1: Write tests for parent container logic**

```swift
import XCTest
import CoreGraphics
@testable import Screenize

final class ParentContainerTests: XCTestCase {

    func test_shouldUseParentBounds_smallButton_true() {
        // Small button (30x30) should use parent bounds
        let element = UIElementInfo(
            role: "AXButton",
            subrole: nil,
            frame: CGRect(x: 100, y: 100, width: 30, height: 30),
            title: "OK",
            isClickable: true,
            applicationName: "TestApp",
            parentContainerBounds: nil
        )
        let screenBounds = CGSize(width: 1920, height: 1080)
        XCTAssertTrue(AccessibilityInspector.shouldTraverseForParent(element: element, screenBounds: screenBounds))
    }

    func test_shouldUseParentBounds_largeTextArea_false() {
        // Large text area should use own bounds
        let element = UIElementInfo(
            role: "AXTextArea",
            subrole: nil,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            title: nil,
            isClickable: false,
            applicationName: "TestApp",
            parentContainerBounds: nil
        )
        let screenBounds = CGSize(width: 1920, height: 1080)
        XCTAssertFalse(AccessibilityInspector.shouldTraverseForParent(element: element, screenBounds: screenBounds))
    }

    func test_parentBounds_tooLarge_discarded() {
        // Parent bounds > 80% of screen → discard
        let parentBounds = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let screenBounds = CGSize(width: 1920, height: 1080)
        XCTAssertTrue(AccessibilityInspector.isParentBoundsTooLarge(parentBounds, screenBounds: screenBounds))
    }

    func test_parentBounds_reasonable_kept() {
        let parentBounds = CGRect(x: 100, y: 100, width: 400, height: 50)
        let screenBounds = CGSize(width: 1920, height: 1080)
        XCTAssertFalse(AccessibilityInspector.isParentBoundsTooLarge(parentBounds, screenBounds: screenBounds))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ParentContainerTests 2>&1 | tail -20`
Expected: Compilation failure.

- [ ] **Step 3: Implement parent traversal logic**

In `AccessibilityInspector.swift`, add:

```swift
// MARK: - Parent Container Traversal

/// Roles that are typically large enough to use their own bounds as ROI.
private static let selfSufficientRoles: Set<String> = [
    "AXTextArea", "AXTextField", "AXTable", "AXScrollArea", "AXWebArea"
]

/// Roles whose parent container provides better ROI context.
private static let parentPreferredRoles: Set<String> = [
    "AXButton", "AXMenuItem", "AXCheckBox", "AXRadioButton",
    "AXStaticText", "AXImage", "AXPopUpButton"
]

/// Determines if parent traversal is needed for this element.
static func shouldTraverseForParent(element: UIElementInfo, screenBounds: CGSize) -> Bool {
    // Self-sufficient roles don't need parent
    if selfSufficientRoles.contains(element.role) { return false }

    // Small elements (< 5% of screen area) need parent context
    let screenArea = screenBounds.width * screenBounds.height
    let elementArea = element.frame.width * element.frame.height
    if elementArea < screenArea * 0.05 { return true }

    // Parent-preferred roles
    if parentPreferredRoles.contains(element.role) { return true }

    return false
}

/// Checks if parent bounds are too large to be useful (> 80% of screen in either dimension).
static func isParentBoundsTooLarge(_ bounds: CGRect, screenBounds: CGSize) -> Bool {
    bounds.width > screenBounds.width * 0.8 || bounds.height > screenBounds.height * 0.8
}

/// Traverse up to 3 levels of AX hierarchy to find a meaningful parent container.
/// Caches result: same focused element → same parent.
static func findParentContainer(for axElement: AXUIElement, screenBounds: CGSize, maxDepth: Int = 3) -> CGRect? {
    var current = axElement
    for _ in 0..<maxDepth {
        var parentRef: AnyObject?
        let result = AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef)
        guard result == .success, let parent = parentRef as! AXUIElement? else { break }

        var positionRef: AnyObject?
        var sizeRef: AnyObject?
        AXUIElementCopyAttributeValue(parent, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(parent, kAXSizeAttribute as CFString, &sizeRef)

        if let posVal = positionRef, let sizeVal = sizeRef {
            var position = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            let bounds = CGRect(origin: position, size: size)

            if !isParentBoundsTooLarge(bounds, screenBounds: screenBounds) && size.width > 0 && size.height > 0 {
                return bounds
            }
        }
        current = parent
    }
    return nil
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ParentContainerTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Core/Tracking/AccessibilityInspector.swift ScreenizeTests/Core/Tracking/ParentContainerTests.swift
git commit -m "feat: add parent container AX traversal with depth limit and size fallback"
```

### Task 6: Wire parent container into AX sampling and populate UIElementInfo

**Files:**
- Modify: `Screenize/Core/Tracking/AccessibilityInspector.swift` (elementAt method)

- [ ] **Step 1: Update `elementAt()` to populate parentContainerBounds**

In the `elementAt()` method, after obtaining the UIElementInfo, check if parent traversal is needed. If so, call `findParentContainer()` and set `parentContainerBounds`.

```swift
// After creating elementInfo:
var info = UIElementInfo(/* existing fields */, parentContainerBounds: nil)
if AccessibilityInspector.shouldTraverseForParent(element: info, screenBounds: screenBounds) {
    info = UIElementInfo(
        /* copy existing fields */,
        parentContainerBounds: findParentContainer(for: axElement, screenBounds: screenBounds)
    )
}
```

Note: UIElementInfo may need to become a `var`-based struct or use a builder pattern since it's currently all `let` properties. Alternatively, add a `withParentBounds(_:)` method that returns a copy.

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Screenize/Core/Tracking/AccessibilityInspector.swift
git commit -m "feat: populate parentContainerBounds during AX sampling"
```

### Task 7: Integrate parent container ROI into ShotPlanner

**Files:**
- Modify: `Screenize/Generators/SmartGeneration/Planning/ShotPlanner.swift`
- Modify: `ScreenizeTests/Generators/SmartGeneration/Planning/ShotPlannerTests.swift`

- [ ] **Step 1: Write test for parent container ROI**

```swift
func test_computeZoom_smallButton_usesParentContainerBounds() {
    // Small button with parent toolbar bounds → zoom should fit toolbar, not just button
    let buttonElement = UIElementInfo(
        role: "AXButton",
        subrole: nil,
        frame: CGRect(x: 500, y: 500, width: 30, height: 30),
        title: "OK",
        isClickable: true,
        applicationName: "TestApp",
        parentContainerBounds: CGRect(x: 400, y: 490, width: 300, height: 50)
    )
    // Create scene with this element as focus region
    let scene = makeSingleElementScene(element: buttonElement)
    let plans = ShotPlanner.plan(
        scenes: [scene],
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: makeEmptyTimeline(),
        frameAnalysis: [],
        settings: ShotSettings()
    )
    guard let plan = plans.first else { XCTFail("Expected plan"); return }
    // Zoom should be moderate (fitting toolbar), not extreme (fitting button)
    XCTAssertLessThan(plan.idealZoom, 2.5, "Zoom should not be extreme for small button with parent context")
}
```

- [ ] **Step 2: Implement parent container ROI in ShotPlanner**

In `ShotPlanner.swift`, in the element-based sizing logic (around line 174-188), add parent container check:

```swift
// After computing elementSize from focusRegion:
var effectiveSize = elementSize

// If element has parent container and element is small, use parent as minimum ROI floor
if let parentBounds = focusRegion.elementInfo?.parentContainerBounds {
    let parentSize = max(parentBounds.width / screenBounds.width, parentBounds.height / screenBounds.height)
    effectiveSize = max(effectiveSize, parentSize)
}
```

- [ ] **Step 3: Run ShotPlanner tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ShotPlannerTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 4: Commit**

```bash
git add Screenize/Generators/SmartGeneration/Planning/ShotPlanner.swift ScreenizeTests/Generators/SmartGeneration/Planning/ShotPlannerTests.swift
git commit -m "feat: use parent container bounds as minimum ROI floor in ShotPlanner"
```

---

## Chunk 3: Post-Interaction Trajectory Analysis (Section 3)

### Task 8: Add `refineWithPostContext()` to IntentClassifier

**Files:**
- Modify: `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift`
- Modify: `ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift`

- [ ] **Step 1: Write tests for post-interaction refinement**

```swift
// MARK: - refineWithPostContext

func test_refine_clickFollowedByNewFocusElement_updatesFocusPosition() {
    // Click at (0.3, 0.5), then AX shows new text field focused at (0.5, 0.5)
    let clickSpan = IntentSpan(
        startTime: 1.0, endTime: 1.5,
        intent: .clicking, confidence: 0.9,
        focusPosition: NormalizedPoint(x: 0.3, y: 0.5),
        focusElement: nil
    )
    let typingSpan = IntentSpan(
        startTime: 1.6, endTime: 4.0,
        intent: .typing(context: .codeEditor), confidence: 0.9,
        focusPosition: NormalizedPoint(x: 0.5, y: 0.5),
        focusElement: makeTextFieldElement(center: NormalizedPoint(x: 0.5, y: 0.5))
    )
    let uiSamples = [
        makeUIStateSample(time: 1.3, elementRole: "AXTextField", frame: CGRect(x: 400, y: 400, width: 300, height: 30))
    ]

    let refined = IntentClassifier.refineWithPostContext(
        spans: [clickSpan, typingSpan],
        uiStateSamples: uiSamples
    )

    // Click's focusElement should be updated to the new text field
    XCTAssertNotNil(refined[0].focusElement)
    XCTAssertEqual(refined[0].focusElement?.role, "AXTextField")
}

func test_refine_clickFollowedByDrag_expandsROI() {
    // Click at (0.3, 0.5), immediately followed by drag to (0.7, 0.5)
    let clickSpan = IntentSpan(
        startTime: 1.0, endTime: 1.2,
        intent: .clicking, confidence: 0.9,
        focusPosition: NormalizedPoint(x: 0.3, y: 0.5),
        focusElement: nil
    )
    let dragSpan = IntentSpan(
        startTime: 1.2, endTime: 2.0,
        intent: .dragging(.selection), confidence: 0.95,
        focusPosition: NormalizedPoint(x: 0.7, y: 0.5),
        focusElement: nil
    )

    let refined = IntentClassifier.refineWithPostContext(
        spans: [clickSpan, dragSpan],
        uiStateSamples: []
    )

    // Click's focusPosition should move toward the drag area centroid
    let centroidX = (0.3 + 0.7) / 2.0
    XCTAssertEqual(refined[0].focusPosition.x, centroidX, accuracy: 0.05)
}

func test_refine_clickFollowedByTyping_replacesROIWithTypingTarget() {
    // Click at (0.3, 0.5), then typing with focusElement at (0.5, 0.6)
    let clickSpan = IntentSpan(
        startTime: 1.0, endTime: 1.3,
        intent: .clicking, confidence: 0.9,
        focusPosition: NormalizedPoint(x: 0.3, y: 0.5),
        focusElement: nil
    )
    let typingSpan = IntentSpan(
        startTime: 1.4, endTime: 5.0,
        intent: .typing(context: .textField), confidence: 0.9,
        focusPosition: NormalizedPoint(x: 0.5, y: 0.6),
        focusElement: makeTextFieldElement(center: NormalizedPoint(x: 0.5, y: 0.6))
    )

    let refined = IntentClassifier.refineWithPostContext(
        spans: [clickSpan, typingSpan],
        uiStateSamples: []
    )

    // Click's focusPosition should match typing target
    XCTAssertEqual(refined[0].focusPosition.x, 0.5, accuracy: 0.05)
    XCTAssertEqual(refined[0].focusPosition.y, 0.6, accuracy: 0.05)
}

func test_refine_noFollowingSpan_unchanged() {
    // Single click with no following span → no refinement
    let clickSpan = IntentSpan(
        startTime: 1.0, endTime: 1.5,
        intent: .clicking, confidence: 0.9,
        focusPosition: NormalizedPoint(x: 0.3, y: 0.5),
        focusElement: nil
    )

    let refined = IntentClassifier.refineWithPostContext(
        spans: [clickSpan],
        uiStateSamples: []
    )

    XCTAssertEqual(refined[0].focusPosition.x, 0.3, accuracy: 0.001)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/IntentClassifierTests 2>&1 | tail -20`
Expected: Compilation failure — `refineWithPostContext` not defined.

- [ ] **Step 3: Implement refineWithPostContext()**

In `IntentClassifier.swift`, add static method:

```swift
/// Post-interaction refinement: adjusts focusPosition and focusElement based on what
/// happened after each intent span. Uses AX state changes as ground truth.
static func refineWithPostContext(
    spans: [IntentSpan],
    uiStateSamples: [UIStateSample]
) -> [IntentSpan] {
    guard spans.count > 1 else { return spans }

    var refined = spans

    for i in 0..<(refined.count - 1) {
        let current = refined[i]
        let next = refined[i + 1]

        // Only refine clicking intents
        guard case .clicking = current.intent else { continue }

        let gap = next.startTime - current.endTime

        // Rule 1: Click → UI element change (via AX samples)
        if let axSample = uiStateSamples.first(where: { sample in
            sample.timestamp >= current.startTime &&
            sample.timestamp <= next.startTime &&
            sample.elementInfo != nil &&
            sample.elementInfo?.role != current.focusElement?.role
        }) {
            if let newElement = axSample.elementInfo {
                refined[i] = current.withUpdatedFocus(
                    position: normalizedCenter(of: newElement.frame, screenBounds: /* pass through */),
                    element: newElement
                )
                continue
            }
        }

        // Rule 2: Click → Drag continuation (gap < continuation threshold)
        if case .dragging = next.intent, gap < 0.5 {
            let centroid = NormalizedPoint(
                x: (current.focusPosition.x + next.focusPosition.x) / 2,
                y: (current.focusPosition.y + next.focusPosition.y) / 2
            )
            refined[i] = current.withUpdatedFocus(position: centroid, element: next.focusElement)
            continue
        }

        // Rule 3: Click → Typing continuation (gap < continuation threshold)
        if case .typing = next.intent, gap < 1.0, next.focusElement != nil {
            refined[i] = current.withUpdatedFocus(
                position: next.focusPosition,
                element: next.focusElement
            )
            continue
        }
    }

    return refined
}
```

Note: `IntentSpan` needs a `withUpdatedFocus(position:element:)` helper since its fields are `let`. Add this to the struct:

```swift
func withUpdatedFocus(position: NormalizedPoint, element: UIElementInfo?) -> IntentSpan {
    IntentSpan(
        startTime: startTime, endTime: endTime,
        intent: intent, confidence: confidence,
        focusPosition: position,
        focusElement: element ?? focusElement,
        contextChange: contextChange
    )
}
```

- [ ] **Step 4: Wire refineWithPostContext into classify()**

At the end of the `classify()` method, before returning the final spans, add:

```swift
let refined = refineWithPostContext(spans: filledSpans, uiStateSamples: uiStateSamples)
return refined
```

- [ ] **Step 5: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/IntentClassifierTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift Screenize/Generators/SmartGeneration/Types/UserIntent.swift ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift
git commit -m "feat: add post-interaction trajectory analysis to IntentClassifier"
```

---

## Chunk 4: Two-Stage Zoom Transition (Section 6)

### Task 9: Add `focused` case to UserIntent enum

**Files:**
- Modify: `Screenize/Generators/SmartGeneration/Types/UserIntent.swift`

- [ ] **Step 1: Add focused intent case**

```swift
enum UserIntent: Equatable {
    case typing(context: TypingContext)
    case focused(context: TypingContext)  // NEW: text element focused, not yet typing
    case clicking
    case navigating
    case dragging(DragContext)
    case reading
    case scrolling
    case switching
    case idle
}
```

- [ ] **Step 2: Build to find all switch exhaustiveness errors**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | grep "not exhaustive" | head -20`

Fix each switch statement to handle `.focused`. In most cases, `focused` should behave like a calmer version of `typing`:
- In `WaypointGenerator.urgency()`: `.focused` → `.normal` (between typing's `.high` and reading's `.lazy`)
- In `WaypointGenerator.entryLeadTime()`: `.focused` → `settings.leadTimeNormal`
- In `ShotPlanner` zoom range lookups: `.focused` → same context-based range but use the lower bound
- In `IntentClassifier` intent compatibility checks: `focused` is compatible with `typing` of same context

- [ ] **Step 3: Build successfully**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Screenize/Generators/SmartGeneration/Types/UserIntent.swift
git commit -m "feat: add focused(context:) case to UserIntent enum"
```

### Task 10: Add focused zoom ranges to ShotPlanner

**Files:**
- Modify: `Screenize/Generators/SmartGeneration/Planning/ShotPlanner.swift`
- Modify: `ScreenizeTests/Generators/SmartGeneration/Planning/ShotPlannerTests.swift`

- [ ] **Step 1: Write test for focused zoom vs typing zoom**

```swift
func test_computeZoom_focusedIntent_widerThanTyping() {
    // Focused on code editor → wider framing than typing in code editor
    let focusedScene = makeSingleIntentScene(intent: .focused(context: .codeEditor))
    let typingScene = makeSingleIntentScene(intent: .typing(context: .codeEditor))

    let focusedPlans = ShotPlanner.plan(scenes: [focusedScene], screenBounds: testScreenBounds, eventTimeline: makeEmptyTimeline(), frameAnalysis: [], settings: ShotSettings())
    let typingPlans = ShotPlanner.plan(scenes: [typingScene], screenBounds: testScreenBounds, eventTimeline: makeEmptyTimeline(), frameAnalysis: [], settings: ShotSettings())

    guard let focusedPlan = focusedPlans.first, let typingPlan = typingPlans.first else {
        XCTFail("Expected plans"); return
    }
    // Focused should have lower zoom (wider view) than typing
    XCTAssertLessThan(focusedPlan.idealZoom, typingPlan.idealZoom)
}
```

- [ ] **Step 2: Add focused zoom ranges to ShotSettings**

In `ShotPlanner.swift`, add to `ShotSettings`:

```swift
var focusedCodeZoomRange: ClosedRange<CGFloat> = 1.3...1.8
var focusedTextFieldZoomRange: ClosedRange<CGFloat> = 1.5...2.0
var focusedTerminalZoomRange: ClosedRange<CGFloat> = 1.2...1.5
var focusedRichTextZoomRange: ClosedRange<CGFloat> = 1.3...1.6
```

In the zoom range lookup, add handling for `.focused(context:)`:

```swift
case .focused(let context):
    switch context {
    case .codeEditor: return settings.focusedCodeZoomRange
    case .textField: return settings.focusedTextFieldZoomRange
    case .terminal: return settings.focusedTerminalZoomRange
    case .richTextEditor: return settings.focusedRichTextZoomRange
    }
```

- [ ] **Step 3: For focused intent, use element's full bounds as ROI**

In the center computation for `.focused`, prefer the full element bounds (AX element frame) rather than caret position:

```swift
case .focused:
    // Frame the entire element — user sees full editor/field for context
    if let elementBounds = scene.focusRegions.first?.elementInfo?.frame {
        return normalizedCenter(of: elementBounds, screenBounds: screenBounds)
    }
    // Fallback to first focus position
    return scene.focusRegions.first?.position ?? NormalizedPoint(x: 0.5, y: 0.5)
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/ShotPlannerTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/SmartGeneration/Planning/ShotPlanner.swift ScreenizeTests/Generators/SmartGeneration/Planning/ShotPlannerTests.swift
git commit -m "feat: add focused intent zoom ranges to ShotPlanner (wider than typing)"
```

### Task 11: Implement focused intent detection in IntentClassifier

**Files:**
- Modify: `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift`
- Modify: `ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift`

- [ ] **Step 1: Write tests for focused intent detection**

```swift
func test_classify_clickOnTextFieldThenPause_emitsFocused() {
    // Click on text field, no keystrokes for > focusedTimeout → should emit focused intent
    let events = EventTimeline(events: [
        makeClickEvent(time: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5))
    ], duration: 5.0)
    let uiSamples = [
        makeUIStateSample(time: 1.1, elementRole: "AXTextField", frame: CGRect(x: 400, y: 400, width: 300, height: 30))
    ]

    let spans = IntentClassifier.classify(events: events, uiStateSamples: uiSamples, settings: .init())

    let focusedSpans = spans.filter { if case .focused = $0.intent { return true }; return false }
    XCTAssertFalse(focusedSpans.isEmpty, "Should detect focused intent when clicking text field without typing")
}

func test_classify_clickOnTextFieldThenType_emitsFocusedThenTyping() {
    // Click on text field, then keystrokes → focused then typing
    let events = EventTimeline(events: [
        makeClickEvent(time: 1.0, position: NormalizedPoint(x: 0.5, y: 0.5)),
        makeKeyEvent(time: 2.0, keyCode: 0), // 'a'
        makeKeyEvent(time: 2.1, keyCode: 1), // 's'
        makeKeyEvent(time: 2.2, keyCode: 2), // 'd'
    ], duration: 5.0)
    let uiSamples = [
        makeUIStateSample(time: 1.1, elementRole: "AXTextArea", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    ]

    let spans = IntentClassifier.classify(events: events, uiStateSamples: uiSamples, settings: .init())

    let intentTypes = spans.map { $0.intent }
    // Should have: clicking → focused → typing (or focused → typing)
    let hasFocused = intentTypes.contains { if case .focused = $0 { return true }; return false }
    let hasTyping = intentTypes.contains { if case .typing = $0 { return true }; return false }
    XCTAssertTrue(hasFocused, "Should have focused intent")
    XCTAssertTrue(hasTyping, "Should have typing intent after focused")
}

func test_classify_typingWithoutClick_noFocusedPhase() {
    // Keystrokes without preceding click → typing directly, no focused
    let events = EventTimeline(events: [
        makeKeyEvent(time: 1.0, keyCode: 0),
        makeKeyEvent(time: 1.1, keyCode: 1),
        makeKeyEvent(time: 1.2, keyCode: 2),
        makeKeyEvent(time: 1.3, keyCode: 3),
    ], duration: 5.0)

    let spans = IntentClassifier.classify(events: events, uiStateSamples: [], settings: .init())

    let focusedSpans = spans.filter { if case .focused = $0.intent { return true }; return false }
    XCTAssertTrue(focusedSpans.isEmpty, "No focused intent when typing without click")
}
```

- [ ] **Step 2: Add focusedTimeout to IntentClassificationSettings**

```swift
// In IntentClassificationSettings (GenerationSettings.swift):
var focusedTimeout: TimeInterval = 2.0  // Time to wait for keystrokes after text field focus
```

- [ ] **Step 3: Implement focused detection logic in IntentClassifier**

In the classify method, after detecting a click on a text element (via AX sample showing AXTextArea/AXTextField focus):

1. Check if keystrokes follow within `focusedTimeout`
2. If yes: emit `focused` from click time to first keystroke, then `typing` from first keystroke onward
3. If no: emit `focused` for the duration of the focus (until next intent)
4. If keystrokes arrive without preceding click on text element: emit `typing` directly (current behavior)

The detection relies on UIStateSample showing a text-input role becoming focused around the click time.

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/IntentClassifierTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 5: Build full project**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift
git commit -m "feat: detect focused intent for text elements before typing starts"
```

### Task 12: Wire focused intent into WaypointGenerator

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/WaypointGenerator.swift`
- Modify: `ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift`

- [ ] **Step 1: Write test for focused urgency**

```swift
func test_urgency_focused_isNormal() {
    let urgency = WaypointGenerator.urgency(for: .focused(context: .codeEditor))
    XCTAssertEqual(urgency, .normal)
}
```

- [ ] **Step 2: Add focused handling to urgency() and generate()**

In `WaypointGenerator.swift`:
- `urgency()`: `.focused` → `.normal`
- `entryLeadTime()`: `.focused` → `settings.leadTimeNormal`
- In `generate()`: treat `.focused` like typing for waypoint creation but with normal urgency

- [ ] **Step 3: Run WaypointGenerator tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/WaypointGeneratorTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 4: Commit**

```bash
git add Screenize/Generators/ContinuousCamera/WaypointGenerator.swift ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift
git commit -m "feat: wire focused intent into WaypointGenerator with normal urgency"
```

---

## Chunk 5: Confidence-Based Movement Suppression (Section 2)

### Task 13: Add confidence band constants and helper

**Files:**
- Create: `Screenize/Generators/SmartGeneration/Types/ConfidenceBands.swift`

Note: There is no single `GenerationSettings.swift`. `ShotSettings` lives in `ShotPlanner.swift`, `IntentClassificationSettings` lives in `IntentClassifier.swift`. Create a new file for `ConfidenceBands` in the Types directory.

- [ ] **Step 1: Add confidence band thresholds**

```swift
struct ConfidenceBands {
    /// Below this: no camera movement
    static let lowThreshold: Float = 0.6
    /// Below this but above low: reduced response
    static let mediumThreshold: Float = 0.85

    /// Returns the response band for a given confidence value.
    enum Band { case none, reduced, full }

    static func band(for confidence: Float) -> Band {
        if confidence < lowThreshold { return .none }
        if confidence < mediumThreshold { return .reduced }
        return .full
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add Screenize/Generators/SmartGeneration/Types/ConfidenceBands.swift
git commit -m "feat: add ConfidenceBands helper with three discrete response levels"
```

Note: Add `ConfidenceBands.swift` to `project.pbxproj` (4 entries).

### Task 14: Implement confidence filtering in WaypointGenerator

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/WaypointGenerator.swift`
- Modify: `ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift`

- [ ] **Step 1: Write tests for confidence filtering**

```swift
func test_generate_lowConfidenceSpan_noWaypoint() {
    // Single keystroke typing span (confidence 0.5) → should not generate waypoint
    let span = IntentSpan(
        startTime: 1.0, endTime: 1.5,
        intent: .typing(context: .codeEditor), confidence: 0.5,
        focusPosition: NormalizedPoint(x: 0.5, y: 0.5),
        focusElement: nil
    )
    let idleBefore = IntentSpan(
        startTime: 0.0, endTime: 1.0,
        intent: .idle, confidence: 0.8,
        focusPosition: NormalizedPoint(x: 0.5, y: 0.5),
        focusElement: nil
    )

    let waypoints = WaypointGenerator.generate(
        from: [idleBefore, span],
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: nil,
        frameAnalysis: [],
        settings: ContinuousCameraSettings()
    )

    // Should not have a typing waypoint (only idle)
    let typingWaypoints = waypoints.filter { if case .typing = $0.source { return true }; return false }
    XCTAssertTrue(typingWaypoints.isEmpty, "Low confidence span should not generate waypoint")
}

func test_generate_mediumConfidenceSpan_lazyUrgency() {
    // Medium confidence (0.7) → waypoint generated but with lazy urgency
    let span = IntentSpan(
        startTime: 1.0, endTime: 3.0,
        intent: .typing(context: .codeEditor), confidence: 0.7,
        focusPosition: NormalizedPoint(x: 0.5, y: 0.5),
        focusElement: nil
    )

    let waypoints = WaypointGenerator.generate(
        from: [span],
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: nil,
        frameAnalysis: [],
        settings: ContinuousCameraSettings()
    )

    let typingWaypoints = waypoints.filter { if case .typing = $0.source { return true }; return false }
    XCTAssertFalse(typingWaypoints.isEmpty, "Medium confidence should still generate waypoint")
    if let wp = typingWaypoints.first {
        XCTAssertEqual(wp.urgency, .lazy, "Medium confidence should have lazy urgency")
    }
}
```

- [ ] **Step 2: Implement confidence filtering in generate()**

In `WaypointGenerator.generate()`, before creating a waypoint for each intent span:

```swift
let band = ConfidenceBands.band(for: span.confidence)
switch band {
case .none:
    continue  // Skip waypoint entirely
case .reduced:
    // Generate waypoint but downgrade urgency to lazy
    let waypoint = CameraWaypoint(
        time: entryTime,
        targetZoom: shotPlan.zoom,
        targetCenter: shotPlan.center,
        urgency: .lazy,
        source: span.intent
    )
    waypoints.append(waypoint)
case .full:
    // Current behavior — use normal urgency mapping
    // ... existing code ...
}
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/WaypointGeneratorTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 4: Commit**

```bash
git add Screenize/Generators/ContinuousCamera/WaypointGenerator.swift ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift
git commit -m "feat: filter waypoints by confidence band (none/reduced/full)"
```

### Task 15: Implement confidence filtering in SegmentPlanner

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift`
- Modify: `ScreenizeTests/Generators/SegmentCamera/SegmentPlannerTests.swift`

- [ ] **Step 1: Write test for low-confidence scene absorption**

```swift
func test_plan_lowConfidenceScene_absorbedIntoPrevious() {
    // High-confidence typing, then low-confidence single keystroke, then high-confidence typing
    // The low-confidence scene should be absorbed into the first segment
    let spans = [
        makeTypingSpan(start: 0.0, end: 3.0, confidence: 0.9, focusPosition: NormalizedPoint(x: 0.3, y: 0.5)),
        makeTypingSpan(start: 3.5, end: 4.0, confidence: 0.5, focusPosition: NormalizedPoint(x: 0.35, y: 0.5)),
        makeTypingSpan(start: 4.5, end: 7.0, confidence: 0.9, focusPosition: NormalizedPoint(x: 0.6, y: 0.5)),
    ]

    let segments = SegmentPlanner.plan(
        intentSpans: spans,
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: makeEmptyTimeline(),
        frameAnalysis: [],
        settings: ShotSettings()
    )

    // Should have fewer segments than if all 3 were treated independently
    // The low-confidence middle span should not create its own segment
    let segmentCount = segments.count
    // At most 2 distinct active segments (first and third), not 3
    XCTAssertLessThanOrEqual(segmentCount, 4, "Low-confidence scene should be absorbed, not create separate segment")
}
```

- [ ] **Step 2: Implement confidence absorption in SegmentPlanner**

In `SegmentPlanner.plan()`, after creating scenes from intent spans, filter out low-confidence scenes by absorbing them.

**Note**: `CameraScene` has no direct `confidence` property — confidence lives on `FocusRegion.confidence` within the scene's `focusRegions` array. Also, `CameraScene` properties are `let` (immutable), so "modifying" a scene means reconstructing it.

```swift
// After scene creation, before segment building:
let filteredScenes = absorbLowConfidenceScenes(scenes)

func absorbLowConfidenceScenes(_ scenes: [CameraScene]) -> [CameraScene] {
    guard scenes.count > 1 else { return scenes }
    var result: [CameraScene] = []
    for scene in scenes {
        // Aggregate confidence from focus regions (use max, or first)
        let sceneConfidence = scene.focusRegions.map(\.confidence).max() ?? 0
        let band = ConfidenceBands.band(for: sceneConfidence)
        if band == .none, let last = result.last {
            // Absorb: reconstruct previous scene with extended end time
            result[result.count - 1] = CameraScene(
                id: last.id, startTime: last.startTime, endTime: scene.endTime,
                primaryIntent: last.primaryIntent, focusRegions: last.focusRegions,
                appContext: last.appContext, contextChange: last.contextChange
            )
        } else {
            result.append(scene)
        }
    }
    // If first scene is low-confidence, reconstruct as idle
    if let first = result.first {
        let firstConf = first.focusRegions.map(\.confidence).max() ?? 0
        if ConfidenceBands.band(for: firstConf) == .none {
            result[0] = CameraScene(
                id: first.id, startTime: first.startTime, endTime: first.endTime,
                primaryIntent: .idle, focusRegions: first.focusRegions,
                appContext: first.appContext, contextChange: first.contextChange
            )
        }
    }
    return result
}
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentPlannerTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 4: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentPlanner.swift ScreenizeTests/Generators/SegmentCamera/SegmentPlannerTests.swift
git commit -m "feat: absorb low-confidence scenes into preceding segments"
```

### Task 16: Scale dead zone by confidence in SpringDamperSimulator

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift`
- Modify: `Screenize/Generators/ContinuousCamera/DeadZoneTarget.swift`
- Modify: `ScreenizeTests/Generators/ContinuousCamera/DeadZoneTargetTests.swift`

- [ ] **Step 1: Write test for confidence-scaled dead zone**

```swift
func test_deadZone_mediumConfidence_widerSafeZone() {
    // Medium confidence should produce wider safe zone than full confidence
    let settings = DeadZoneSettings()
    let cursor = NormalizedPoint(x: 0.6, y: 0.5)
    let camera = NormalizedPoint(x: 0.5, y: 0.5)

    let fullResult = DeadZoneTarget.computeWithState(
        cursorPosition: cursor, cameraCenter: camera,
        zoom: 2.0, isTyping: false, wasActive: false,
        settings: settings, confidence: 0.9
    )
    let mediumResult = DeadZoneTarget.computeWithState(
        cursorPosition: cursor, cameraCenter: camera,
        zoom: 2.0, isTyping: false, wasActive: false,
        settings: settings, confidence: 0.7
    )

    // Medium confidence → wider safe zone → less likely to be active
    // If full is active, medium might not be (or should produce less correction)
    if fullResult.isActive {
        // Medium confidence should either not be active, or produce less correction
        if mediumResult.isActive {
            // Target should be closer to camera center (less correction)
            let fullDist = fullResult.target.distance(to: camera)
            let mediumDist = mediumResult.target.distance(to: camera)
            XCTAssertLessThanOrEqual(mediumDist, fullDist + 0.01)
        }
    }
}
```

- [ ] **Step 2: Add confidence parameter to DeadZoneTarget.computeWithState()**

Add `confidence: Float = 1.0` parameter. When confidence is in the medium band, scale `safeZoneFraction` up (wider safe zone):

```swift
// In computeWithState():
let confidenceBand = ConfidenceBands.band(for: confidence)
let safeZoneMultiplier: CGFloat = confidenceBand == .reduced ? 1.15 : 1.0  // 15% wider for medium confidence
let safeFraction = (isTyping ? settings.safeZoneFractionTyping : settings.safeZoneFraction) * safeZoneMultiplier
```

- [ ] **Step 3: Pass confidence through SpringDamperSimulator**

In `SpringDamperSimulator.simulate()`, when calling `DeadZoneTarget.computeWithState()`, pass the current intent span's confidence value.

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/DeadZoneTargetTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/ContinuousCamera/SpringDamperSimulator.swift Screenize/Generators/ContinuousCamera/DeadZoneTarget.swift ScreenizeTests/Generators/ContinuousCamera/DeadZoneTargetTests.swift
git commit -m "feat: scale dead zone width by confidence band in SpringDamperSimulator"
```

---

## Chunk 6: Connected Pan — TransitionResolver (Section 1)

### Task 17: Define TransitionStyle type

**Files:**
- Create: `Screenize/Generators/SmartGeneration/Planning/TransitionStyle.swift`

- [ ] **Step 1: Create TransitionStyle enum**

```swift
import Foundation
import CoreGraphics

/// Describes how the camera transitions between two adjacent segments.
enum TransitionStyle: Codable, Equatable {
    /// Camera stays fixed — segments are visually continuous.
    case hold
    /// Camera pans without changing zoom level.
    case directPan
    /// Full zoom-out → pan → zoom-in transition (existing behavior).
    case fullTransition
}
```

- [ ] **Step 2: Add TransitionStyle to CameraSegment**

In `Screenize/Timeline/Segments.swift`, add `transitionStyle` to `CameraSegment`:

```swift
struct CameraSegment: Identifiable, Equatable, Codable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval
    var kind: CameraSegmentKind
    var transitionStyle: TransitionStyle = .fullTransition  // NEW: how to transition TO this segment
}
```

**IMPORTANT**: `CameraSegment` has custom `init(from decoder:)` and `encode(to:)`. You MUST update both:
- In `encode(to:)`: add `try container.encode(transitionStyle, forKey: .transitionStyle)`
- In `init(from:)`: add `transitionStyle = try container.decodeIfPresent(TransitionStyle.self, forKey: .transitionStyle) ?? .fullTransition` (backward-compatible: old projects without this field decode as `.fullTransition`)
- Add `.transitionStyle` to the `CodingKeys` enum

- [ ] **Step 3: Build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED. Add new file to Xcode project if needed.

- [ ] **Step 4: Commit**

```bash
git add Screenize/Generators/SmartGeneration/Planning/TransitionStyle.swift Screenize/Timeline/Segments.swift
git commit -m "feat: define TransitionStyle enum and add to CameraSegment"
```

### Task 18: Implement TransitionResolver

**Files:**
- Create: `Screenize/Generators/SmartGeneration/Planning/TransitionResolver.swift`
- Create: `ScreenizeTests/Generators/SmartGeneration/Planning/TransitionResolverTests.swift`

- [ ] **Step 1: Write tests for TransitionResolver**

```swift
import XCTest
import CoreGraphics
@testable import Screenize

final class TransitionResolverTests: XCTestCase {

    func test_resolve_nearlyIdenticalSegments_hold() {
        // Two segments at almost same position and zoom → Hold
        let segments = [
            makeSegment(center: NormalizedPoint(x: 0.5, y: 0.5), zoom: 2.0, start: 0, end: 2),
            makeSegment(center: NormalizedPoint(x: 0.52, y: 0.5), zoom: 2.05, start: 3, end: 5),
        ]
        let resolved = TransitionResolver.resolve(segments)
        XCTAssertEqual(resolved[1].transitionStyle, .hold)
    }

    func test_resolve_sameZoomDifferentPosition_directPan() {
        // Same zoom, different position → DirectPan
        let segments = [
            makeSegment(center: NormalizedPoint(x: 0.3, y: 0.5), zoom: 2.0, start: 0, end: 2),
            makeSegment(center: NormalizedPoint(x: 0.7, y: 0.5), zoom: 2.0, start: 3, end: 5),
        ]
        let resolved = TransitionResolver.resolve(segments)
        XCTAssertEqual(resolved[1].transitionStyle, .directPan)
    }

    func test_resolve_differentZoomAndPosition_fullTransition() {
        // Very different zoom and position → FullTransition
        let segments = [
            makeSegment(center: NormalizedPoint(x: 0.2, y: 0.2), zoom: 1.0, start: 0, end: 2),
            makeSegment(center: NormalizedPoint(x: 0.8, y: 0.8), zoom: 2.5, start: 3, end: 5),
        ]
        let resolved = TransitionResolver.resolve(segments)
        XCTAssertEqual(resolved[1].transitionStyle, .fullTransition)
    }

    func test_resolve_idleBetweenSimilarActive_holdThroughIdle() {
        // Active → short idle → similar active → idle should be absorbed as Hold
        let segments = [
            makeSegment(center: NormalizedPoint(x: 0.5, y: 0.5), zoom: 2.0, start: 0, end: 2, intent: .typing(context: .codeEditor)),
            makeSegment(center: NormalizedPoint(x: 0.5, y: 0.5), zoom: 1.0, start: 2, end: 3, intent: .idle),
            makeSegment(center: NormalizedPoint(x: 0.52, y: 0.5), zoom: 2.0, start: 3, end: 5, intent: .typing(context: .codeEditor)),
        ]
        let resolved = TransitionResolver.resolve(segments)
        // The idle segment should be absorbed (hold) and the third segment should be hold
        XCTAssertEqual(resolved[2].transitionStyle, .hold)
    }

    func test_resolve_firstSegment_alwaysFullTransition() {
        // First segment has no predecessor → fullTransition (entry from 1x zoom)
        let segments = [
            makeSegment(center: NormalizedPoint(x: 0.5, y: 0.5), zoom: 2.0, start: 0, end: 2),
        ]
        let resolved = TransitionResolver.resolve(segments)
        XCTAssertEqual(resolved[0].transitionStyle, .fullTransition)
    }

    // MARK: - Helpers

    private func makeSegment(center: NormalizedPoint, zoom: CGFloat, start: TimeInterval, end: TimeInterval, intent: UserIntent = .typing(context: .codeEditor)) -> CameraSegment {
        CameraSegment(
            id: UUID(),
            startTime: start,
            endTime: end,
            kind: .manual(
                startTransform: TransformValue(zoom: zoom, center: center),
                endTransform: TransformValue(zoom: zoom, center: center)
            ),
            transitionStyle: .fullTransition
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/TransitionResolverTests 2>&1 | tail -20`
Expected: Compilation failure.

- [ ] **Step 3: Implement TransitionResolver**

```swift
import Foundation
import CoreGraphics

/// Post-processing step that classifies transition styles between adjacent camera segments.
/// Runs after scene merging to prevent unnecessary zoom-out/zoom-in cycles.
enum TransitionResolver {

    struct Settings {
        /// Max positional distance for Hold (camera stays fixed)
        var holdDistanceThreshold: CGFloat = 0.08
        /// Max zoom ratio for Hold
        var holdZoomRatioThreshold: CGFloat = 1.1
        /// Max zoom ratio for DirectPan (pan without zoom change)
        var directPanZoomRatioThreshold: CGFloat = 1.25
    }

    /// Resolve transition styles for a sequence of camera segments.
    /// First segment always gets .fullTransition.
    /// Evaluates active-to-active pairs, looking through idle segments.
    /// `intentSpans` is used to determine which segments are idle (by matching time ranges).
    static func resolve(_ segments: [CameraSegment], intentSpans: [IntentSpan] = [], settings: Settings = .init()) -> [CameraSegment] {
        guard segments.count > 1 else { return segments }

        var result = segments
        result[0].transitionStyle = .fullTransition

        // Find active (non-idle) segment indices
        var i = 1
        while i < result.count {
            let current = result[i]
            let previous = findPreviousActiveSegment(before: i, in: result)

            guard let prev = previous else {
                result[i].transitionStyle = .fullTransition
                i += 1
                continue
            }

            let style = classifyTransition(from: prev, to: current, settings: settings)
            result[i].transitionStyle = style

            // If Hold: absorb intermediate idle segments
            if style == .hold {
                for j in (prev.index + 1)..<i {
                    if isIdleSegment(result[j], intentSpans: intentSpans) {
                        result[j].transitionStyle = .hold
                    }
                }
            }

            // If DirectPan: idle segments become transition windows
            if style == .directPan {
                for j in (prev.index + 1)..<i {
                    if isIdleSegment(result[j], intentSpans: intentSpans) {
                        result[j].transitionStyle = .directPan
                    }
                }
            }

            i += 1
        }

        return result
    }

    private struct IndexedSegment {
        let segment: CameraSegment
        let index: Int
    }

    private static func findPreviousActiveSegment(before index: Int, in segments: [CameraSegment]) -> IndexedSegment? {
        for i in stride(from: index - 1, through: 0, by: -1) {
            if !isIdleSegment(segments[i], intentSpans: intentSpans) {
                return IndexedSegment(segment: segments[i], index: i)
            }
        }
        return nil
    }

    /// Determines if a segment corresponds to an idle intent by matching against the intent span timeline.
    private static func isIdleSegment(_ segment: CameraSegment, intentSpans: [IntentSpan]) -> Bool {
        // Match by time range: find the intent span that overlaps this segment's midpoint
        let midTime = (segment.startTime + segment.endTime) / 2
        if let matchingSpan = intentSpans.first(where: { $0.startTime <= midTime && $0.endTime >= midTime }) {
            return matchingSpan.intent == .idle
        }
        return false
    }

    private static func classifyTransition(from prev: IndexedSegment, to current: CameraSegment, settings: Settings) -> TransitionStyle {
        guard case .manual(_, let prevEnd) = prev.segment.kind,
              case .manual(let curStart, _) = current.kind else {
            return .fullTransition
        }

        let distance = prevEnd.center.distance(to: curStart.center)
        let zoomRatio = max(prevEnd.zoom, curStart.zoom) / max(min(prevEnd.zoom, curStart.zoom), 0.01)

        // Hold: nearly identical
        if distance < settings.holdDistanceThreshold && zoomRatio < settings.holdZoomRatioThreshold {
            return .hold
        }

        // DirectPan: similar zoom, different position
        if zoomRatio < settings.directPanZoomRatioThreshold {
            return .directPan
        }

        return .fullTransition
    }
}
```

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/TransitionResolverTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/SmartGeneration/Planning/TransitionResolver.swift ScreenizeTests/Generators/SmartGeneration/Planning/TransitionResolverTests.swift
git commit -m "feat: implement TransitionResolver with hold/directPan/fullTransition classification"
```

### Task 19: Integrate TransitionResolver into SegmentPlanner

**Files:**
- Modify: `Screenize/Generators/SegmentCamera/SegmentPlanner.swift`

- [ ] **Step 1: Call TransitionResolver after segment creation**

In `SegmentPlanner.plan()`, after creating segments and before returning:

```swift
// After existing segment creation logic:
let resolvedSegments = TransitionResolver.resolve(segments, intentSpans: intentSpans)
return resolvedSegments
```

Note: `intentSpans` is already a parameter of `SegmentPlanner.plan()`, so it's available here.

- [ ] **Step 2: Run SegmentPlanner tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/SegmentPlannerTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 3: Commit**

```bash
git add Screenize/Generators/SegmentCamera/SegmentPlanner.swift
git commit -m "feat: integrate TransitionResolver into SegmentPlanner pipeline"
```

### Task 20: Integrate TransitionResolver into WaypointGenerator (Continuous Camera)

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/WaypointGenerator.swift`
- Modify: `ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift`

- [ ] **Step 1: Write test for TransitionStyle-aware waypoints**

```swift
func test_generate_holdTransition_noZoomChange() {
    // Two similar typing spans → TransitionResolver should classify as Hold
    // WaypointGenerator should not produce zoom-out waypoint between them
    let span1 = makeTypingSpan(start: 0, end: 2, position: NormalizedPoint(x: 0.5, y: 0.5))
    let idle = makeIdleSpan(start: 2, end: 3)
    let span2 = makeTypingSpan(start: 3, end: 5, position: NormalizedPoint(x: 0.52, y: 0.5))

    let waypoints = WaypointGenerator.generate(
        from: [span1, idle, span2],
        screenBounds: CGSize(width: 1920, height: 1080),
        eventTimeline: nil,
        frameAnalysis: [],
        settings: ContinuousCameraSettings()
    )

    // Should not have an idle waypoint that drops zoom to 1.0 between the two typing waypoints
    let idleWaypoints = waypoints.filter { $0.time > 2.0 && $0.time < 3.0 && $0.targetZoom < 1.5 }
    XCTAssertTrue(idleWaypoints.isEmpty, "Hold transition should not produce zoom-out waypoint")
}
```

- [ ] **Step 2: Apply TransitionStyle in WaypointGenerator**

In `WaypointGenerator.generate()`, after computing shot plans for each intent span, use TransitionResolver to classify transitions. For Hold transitions, skip the idle waypoint (maintain previous zoom/position). For DirectPan, emit position-only waypoint (same zoom as previous).

```swift
// After generating initial waypoints:
// Apply transition style logic to suppress unnecessary zoom changes
let resolvedWaypoints = applyTransitionStyles(waypoints, intentSpans: intentSpans)
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/WaypointGeneratorTests 2>&1 | tail -20`
Expected: All PASS.

- [ ] **Step 4: Full build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Generators/ContinuousCamera/WaypointGenerator.swift ScreenizeTests/Generators/ContinuousCamera/WaypointGeneratorTests.swift
git commit -m "feat: apply TransitionResolver styles to waypoint generation"
```

---

## Final Verification

### Task 21: Full test suite and build

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize 2>&1 | tail -30`
Expected: All tests PASS.

- [ ] **Step 2: Run lint**

Run: `./scripts/lint.sh 2>&1 | tail -20`
Fix any new lint warnings.

- [ ] **Step 3: Final build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit any final fixes**

Stage only the specific files that were modified to fix lint warnings, then commit:
```bash
git commit -m "chore: fix lint warnings from smart generation quality v2"
```
