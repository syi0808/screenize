# Camera Anticipation for All Action Types

## Problem

Smart generation produces camera movements that start simultaneously with or slightly after user actions. This makes the camera feel like it's "following" the action rather than "leading" it. Only typing has anticipation (0.4s); all other actions (click, drag, scroll, switch) have zero lead time.

## Solution

Apply a per-action-type time offset to shift entire camera segments earlier, using the same pattern already established for typing anticipation in `IntentClassifier`.

## Anticipation Values

| Action Type | Lead Time | Rationale |
|-------------|-----------|-----------|
| Typing | 0.4s | Existing value, unchanged |
| Click | 0.15s | Instantaneous action, subtle lead |
| Drag | 0.25s | Continuous motion, needs framing time |
| Scroll | 0.25s | Screen transition, needs preparation |
| Switch | 0.25s | Large position change, needs preparation |

## Implementation

### Where: `IntentClassifier.swift`

All changes are in `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift`.

### Step 1: Add settings to `IntentClassificationSettings`

Add new anticipation properties alongside existing `typingAnticipation`:

```swift
var clickAnticipation: CGFloat = 0.15
var dragAnticipation: CGFloat = 0.25
var scrollAnticipation: CGFloat = 0.25
var switchAnticipation: CGFloat = 0.25
```

### Step 2: Apply anticipation in each span factory

**Clicking** — in `emitClickGroup()` (~line 450):
```swift
startTime: max(0, event.time - TimeInterval(settings.clickAnticipation)),
endTime: event.time + TimeInterval(settings.pointSpanDuration) - TimeInterval(settings.clickAnticipation),
```

**Dragging** — in `detectDragSpans()` (~line 298):
```swift
startTime: max(0, data.startTime - TimeInterval(settings.dragAnticipation)),
endTime: data.endTime - TimeInterval(settings.dragAnticipation),
```

**Scrolling** — in `detectScrollingSpans()` (~line 330, 346):
```swift
startTime: max(0, start - TimeInterval(settings.scrollAnticipation)),
endTime: scrollEnd - TimeInterval(settings.scrollAnticipation),
```

**Switching** — in `detectSwitchingSpans()` (~line 382):
```swift
startTime: max(0, switchTime - TimeInterval(settings.pointSpanDuration) - TimeInterval(settings.switchAnticipation)),
endTime: switchTime + TimeInterval(settings.pointSpanDuration) - TimeInterval(settings.switchAnticipation),
```

### Approach: Shift Entire Segment

Both `startTime` and `endTime` shift by the same anticipation amount. The camera arrives at the target position earlier, giving viewers time to see the action unfold.

`max(0, ...)` clamp prevents negative timestamps at the beginning of recordings.

### Overlap Handling

The existing `resolveOverlaps()` method already handles spans that overlap after time shifts. No changes needed there.

## Scope

- Only `IntentClassifier.swift` changes
- 4 new settings in `IntentClassificationSettings`
- 4 span creation sites updated
- No changes to rendering, spring simulation, or export pipeline
