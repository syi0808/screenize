# Camera Anticipation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-action-type camera anticipation so the camera leads user actions instead of following them.

**Architecture:** Add 4 new anticipation settings to `IntentClassificationSettings`, then apply time shifts (both startTime and endTime) in 4 span creation sites within `IntentClassifier`. The existing `resolveOverlaps()` handles any resulting overlap. Follows the exact pattern already used for `typingAnticipation`.

**Tech Stack:** Swift, XCTest

**Spec:** `docs/superpowers/specs/2026-03-12-camera-anticipation-design.md`

---

## Task 1: Add anticipation settings and static constants

**Files:**
- Modify: `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift:9-49` (constants) and `:85-97` (settings struct)

- [ ] **Step 1: Add static constants**

In `IntentClassifier`, after the existing `typingAnticipation` constant (line 49), add:

```swift
/// Anticipation time for click scenes.
static let clickAnticipation: TimeInterval = 0.15

/// Anticipation time for drag scenes.
static let dragAnticipation: TimeInterval = 0.25

/// Anticipation time for scroll scenes.
static let scrollAnticipation: TimeInterval = 0.25

/// Anticipation time for switching scenes.
static let switchAnticipation: TimeInterval = 0.25
```

- [ ] **Step 2: Add settings properties**

In `IntentClassificationSettings`, after `typingAnticipation` (line 97), add:

```swift
var clickAnticipation: CGFloat = 0.15
var dragAnticipation: CGFloat = 0.25
var scrollAnticipation: CGFloat = 0.25
var switchAnticipation: CGFloat = 0.25
```

- [ ] **Step 3: Build to verify no compilation errors**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```
git add Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift
git commit -m "feat: add anticipation settings for click, drag, scroll, switch"
```

---

## Task 2: Write failing tests for click anticipation

**Files:**
- Modify: `ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift`

- [ ] **Step 1: Add helper that accepts custom settings**

After the existing `classify(_:)` helper (line 35), add:

```swift
private func classify(
    _ mouseData: MockMouseDataSource,
    settings: IntentClassificationSettings
) -> [IntentSpan] {
    let timeline = EventTimeline.build(from: mouseData)
    return IntentClassifier.classify(
        events: timeline, uiStateSamples: [], settings: settings
    )
}
```

- [ ] **Step 2: Write click anticipation test**

Add after the `// MARK: - Typing Anticipation` section (end of file):

```swift
// MARK: - Click Anticipation

func test_classify_clickSpan_shiftedByAnticipation() {
    let clicks = [makeClick(at: 3.0, position: NormalizedPoint(x: 0.5, y: 0.5))]
    let mouseData = MockMouseDataSource(clicks: clicks)
    let spans = classify(mouseData)

    let clickSpans = spans.filter { $0.intent == .clicking }
    XCTAssertEqual(clickSpans.count, 1)

    let anticipation: TimeInterval = 0.15
    // startTime should be shifted earlier by anticipation
    XCTAssertEqual(
        clickSpans[0].startTime, 3.0 - anticipation, accuracy: 0.01,
        "Click span should start \(anticipation)s before the click event"
    )
    // endTime should also be shifted earlier by anticipation
    let pointSpanDuration: TimeInterval = 0.5
    XCTAssertEqual(
        clickSpans[0].endTime, 3.0 + pointSpanDuration - anticipation, accuracy: 0.01,
        "Click span end should also be shifted by anticipation"
    )
}

func test_classify_clickAnticipation_clampedToZero() {
    let clicks = [makeClick(at: 0.05, position: NormalizedPoint(x: 0.5, y: 0.5))]
    let mouseData = MockMouseDataSource(clicks: clicks)
    let spans = classify(mouseData)

    let clickSpans = spans.filter { $0.intent == .clicking }
    XCTAssertEqual(clickSpans.count, 1)
    XCTAssertGreaterThanOrEqual(
        clickSpans[0].startTime, 0,
        "Click anticipation should not produce negative start time"
    )
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/IntentClassifierTests/test_classify_clickSpan_shiftedByAnticipation 2>&1 | tail -10`
Expected: FAIL — click span startTime is 3.0, not 2.85

- [ ] **Step 4: Commit failing tests**

```
git add ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift
git commit -m "test: add failing tests for click anticipation"
```

---

## Task 3: Implement click anticipation

**Files:**
- Modify: `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift:440-461` (`emitClickGroup`)

- [ ] **Step 1: Apply anticipation in `emitClickGroup()`**

Change the `IntentSpan` creation in `emitClickGroup()` (around line 450) from:

```swift
var span = IntentSpan(
    startTime: event.time,
    endTime: event.time + TimeInterval(settings.pointSpanDuration),
```

To:

```swift
var span = IntentSpan(
    startTime: max(0, event.time - TimeInterval(settings.clickAnticipation)),
    endTime: event.time + TimeInterval(settings.pointSpanDuration) - TimeInterval(settings.clickAnticipation),
```

- [ ] **Step 2: Run click anticipation tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/IntentClassifierTests/test_classify_clickSpan_shiftedByAnticipation -only-testing:ScreenizeTests/IntentClassifierTests/test_classify_clickAnticipation_clampedToZero 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 3: Run all IntentClassifier tests to check for regressions**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/IntentClassifierTests 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 4: Commit**

```
git add Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift
git commit -m "feat: apply click anticipation in IntentClassifier"
```

---

## Task 4: Write failing tests and implement drag anticipation

**Files:**
- Modify: `ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift`
- Modify: `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift:288-306` (`detectDragSpans`)

- [ ] **Step 1: Write drag anticipation test**

```swift
// MARK: - Drag Anticipation

func test_classify_dragSpan_shiftedByAnticipation() {
    let drags = [
        DragEventData(
            startTime: 3.0, endTime: 5.0,
            startPosition: NormalizedPoint(x: 0.2, y: 0.3),
            endPosition: NormalizedPoint(x: 0.8, y: 0.7),
            dragType: .selection
        ),
    ]
    let mouseData = MockMouseDataSource(dragEvents: drags)
    let spans = classify(mouseData)

    let dragSpans = spans.filter {
        if case .dragging = $0.intent { return true }
        return false
    }
    XCTAssertEqual(dragSpans.count, 1)

    let anticipation: TimeInterval = 0.25
    XCTAssertEqual(
        dragSpans[0].startTime, 3.0 - anticipation, accuracy: 0.01,
        "Drag span should start \(anticipation)s before drag begins"
    )
    XCTAssertEqual(
        dragSpans[0].endTime, 5.0 - anticipation, accuracy: 0.01,
        "Drag span end should also shift by anticipation"
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/IntentClassifierTests/test_classify_dragSpan_shiftedByAnticipation 2>&1 | tail -10`
Expected: FAIL

- [ ] **Step 3: Apply anticipation in `detectDragSpans()`**

Change the span creation (around line 298) from:

```swift
spans.append(IntentSpan(
    startTime: data.startTime,
    endTime: data.endTime,
```

To:

```swift
spans.append(IntentSpan(
    startTime: max(0, data.startTime - TimeInterval(settings.dragAnticipation)),
    endTime: data.endTime - TimeInterval(settings.dragAnticipation),
```

Note: `detectDragSpans` currently does not receive `settings`. Add the parameter:

```swift
private static func detectDragSpans(
    from timeline: EventTimeline,
    settings: IntentClassificationSettings
) -> [IntentSpan] {
```

And update the call site in `classify()` to pass `settings`.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/IntentClassifierTests/test_classify_dragSpan_shiftedByAnticipation 2>&1 | tail -10`
Expected: PASS

- [ ] **Step 5: Run all IntentClassifier tests**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/IntentClassifierTests 2>&1 | tail -20`
Expected: All pass. Fix any regressions from the existing `test_classify_dragSpan_timeMatchesDragDuration` test — it expects exact startTime=2.0, endTime=3.5, which will now be shifted. Update the test expectations to account for the 0.25s anticipation.

- [ ] **Step 6: Commit**

```
git add Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift
git commit -m "feat: apply drag anticipation in IntentClassifier"
```

---

## Task 5: Write failing tests and implement scroll anticipation

**Files:**
- Modify: `ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift`
- Modify: `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift:314-357` (`detectScrollingSpans`)

- [ ] **Step 1: Write scroll anticipation test**

```swift
// MARK: - Scroll Anticipation

func test_classify_scrollSpan_shiftedByAnticipation() {
    let scrolls = [
        ScrollEventData(time: 3.0, position: NormalizedPoint(x: 0.5, y: 0.5), deltaY: 10),
        ScrollEventData(time: 3.2, position: NormalizedPoint(x: 0.5, y: 0.5), deltaY: 10),
        ScrollEventData(time: 3.4, position: NormalizedPoint(x: 0.5, y: 0.5), deltaY: 10),
    ]
    let mouseData = MockMouseDataSource(scrollEvents: scrolls)
    let spans = classify(mouseData)

    let scrollSpans = spans.filter { $0.intent == .scrolling }
    XCTAssertEqual(scrollSpans.count, 1)

    let anticipation: TimeInterval = 0.25
    XCTAssertEqual(
        scrollSpans[0].startTime, 3.0 - anticipation, accuracy: 0.01,
        "Scroll span should start \(anticipation)s before scrolling begins"
    )
    XCTAssertEqual(
        scrollSpans[0].endTime, 3.4 - anticipation, accuracy: 0.01,
        "Scroll span end should also shift by anticipation"
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL

- [ ] **Step 3: Apply anticipation in `detectScrollingSpans()`**

There are two places where `IntentSpan` is created in this method (lines ~330 and ~346). In both, change:

```swift
startTime: start,
endTime: scrollEnd,
```

To:

```swift
startTime: max(0, start - TimeInterval(settings.scrollAnticipation)),
endTime: scrollEnd - TimeInterval(settings.scrollAnticipation),
```

- [ ] **Step 4: Run test and all IntentClassifier tests**

Expected: All pass

- [ ] **Step 5: Commit**

```
git add Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift
git commit -m "feat: apply scroll anticipation in IntentClassifier"
```

---

## Task 6: Write failing tests and implement switch anticipation

**Files:**
- Modify: `ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift`
- Modify: `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift:361-393` (`detectSwitchingSpans`)

- [ ] **Step 1: Write switch anticipation test**

```swift
// MARK: - Switch Anticipation

func test_classify_switchSpan_shiftedByAnticipation() {
    let clicks = [
        makeClick(at: 1.0, position: NormalizedPoint(x: 0.1, y: 0.1), appBundleID: "com.app.one"),
        makeClick(at: 4.0, position: NormalizedPoint(x: 0.9, y: 0.9), appBundleID: "com.app.two"),
    ]
    let mouseData = MockMouseDataSource(clicks: clicks)
    let spans = classify(mouseData)

    let switchSpans = spans.filter { $0.intent == .switching }
    XCTAssertGreaterThanOrEqual(switchSpans.count, 1)

    // The switch is detected at the second click (t=4.0).
    // Without anticipation: startTime = 4.0 - 0.5 = 3.5
    // With anticipation (0.25): startTime = 3.5 - 0.25 = 3.25
    let anticipation: TimeInterval = 0.25
    let pointSpan: TimeInterval = 0.5
    let switchSpan = switchSpans[0]
    XCTAssertEqual(
        switchSpan.startTime,
        max(0, 4.0 - pointSpan - anticipation),
        accuracy: 0.01,
        "Switch span should be shifted by anticipation"
    )
    XCTAssertEqual(
        switchSpan.endTime,
        4.0 + pointSpan - anticipation,
        accuracy: 0.01,
        "Switch span end should also shift by anticipation"
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL

- [ ] **Step 3: Apply anticipation in `detectSwitchingSpans()`**

Change the span creation (around line 382) from:

```swift
spans.append(IntentSpan(
    startTime: max(0, switchTime - TimeInterval(settings.pointSpanDuration)),
    endTime: switchTime + TimeInterval(settings.pointSpanDuration),
```

To:

```swift
spans.append(IntentSpan(
    startTime: max(0, switchTime - TimeInterval(settings.pointSpanDuration) - TimeInterval(settings.switchAnticipation)),
    endTime: switchTime + TimeInterval(settings.pointSpanDuration) - TimeInterval(settings.switchAnticipation),
```

- [ ] **Step 4: Run test and all IntentClassifier tests**

Expected: All pass. Some existing switch tests may need expectation adjustments.

- [ ] **Step 5: Commit**

```
git add Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift ScreenizeTests/Generators/SmartGeneration/Analysis/IntentClassifierTests.swift
git commit -m "feat: apply switch anticipation in IntentClassifier"
```

---

## Task 7: Final verification

- [ ] **Step 1: Run full IntentClassifier test suite**

Run: `xcodebuild test -project Screenize.xcodeproj -scheme Screenize -only-testing:ScreenizeTests/IntentClassifierTests 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 2: Run full project build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run lint**

Run: `./scripts/lint.sh`
Expected: No new violations
