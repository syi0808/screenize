# Smart Generation Quality Improvement v2

**Date**: 2026-03-16
**Status**: Design
**Approach**: Evolve existing pipelines (Approach A)

## Problem Statement

Current smart generation has two core quality issues:

1. **Excessive panning**: Even when adjacent segments have similar positions and zoom levels, the camera performs unnecessary transitions (zoom-out → pan → zoom-in), creating a visually chaotic experience.
2. **Inaccurate ROI**: AX-based region-of-interest determination is underutilized. The camera doesn't distinguish between "focusing on an editor" and "actively typing in it", and AX sampling frequency may miss important UI state changes.

Both issues affect the Continuous Camera and Segment Camera pipelines.

## Design Overview

Six improvements across two themes:

**Pan reduction & transition quality** (Sections 1–4):
1. Connected Pan (TransitionResolver)
2. Confidence-based movement suppression
3. Post-interaction trajectory analysis
4. Soft clamping

**ROI accuracy** (Sections 5–6):
5. AX sampling enhancement + ROI utilization
6. Two-stage zoom transition (focused → typing)

## Section 1: Connected Pan (TransitionResolver)

### Current State

`SegmentPlanner.mergeScenes()` has binary logic: merge if distance < 0.05 AND gap < 0.5s, otherwise treat as fully independent segments. Independent segments each perform their own zoom-in/zoom-out, causing repetitive camera movement between similar positions.

### Design

Add a **TransitionResolver** post-processing step after segment planning. For each pair of adjacent segments, evaluate the transition style based on positional distance and zoom ratio difference:

**Three transition styles:**

- **Hold**: Position and zoom are nearly identical. Camera stays fixed; segments are visually continuous. The viewer sees no camera movement between the two segments.
- **DirectPan**: Zoom levels are similar but positions differ. Camera maintains zoom and slides horizontally/vertically to the new position. No zoom-out → zoom-in cycle.
- **FullTransition**: Both position and zoom differ significantly. Existing behavior: zoom-out → pan → zoom-in, or cut for very large distances.

**Decision criteria:**

Based on two metrics between adjacent segments:
- **Positional distance** (normalized space): euclidean distance between segment centers
- **Zoom ratio**: `max(z1, z2) / min(z1, z2)` — how different the zoom levels are

Thresholds to be determined through testing, calibrated to Screenize's existing viewport model and dead zone parameters. The key principle: the thresholds should be generous enough that visually-similar segments don't trigger unnecessary full transitions.

**Idle segment handling:**

The current pipeline inserts idle spans between most active intent spans (via `IntentClassifier.fillGaps`). TransitionResolver must handle active-idle-active sequences:

- TransitionResolver evaluates transitions between **active segments**, looking through idle segments to find the next active segment on each side
- The idle segment's role depends on the transition style between the surrounding active segments:
  - **Hold**: idle segment is absorbed — camera stays fixed at the active segment's position, idle duration is just "quiet time" within the hold
  - **DirectPan**: idle segment becomes the transition window — pan starts at idle onset and arrives by the next active segment
  - **FullTransition**: idle segment is preserved as a zoom-out period (existing behavior)
- Short idle segments (below a tunable threshold) between similar active segments are strong candidates for Hold, preventing the zoom-out → zoom-in pattern that causes excessive panning

**Integration point:**

- Existing `mergeScenes()` remains as-is (handles truly identical scenes)
- TransitionResolver runs after merging, on the remaining segment pairs
- Each segment pair gets a `TransitionStyle` annotation
- The camera simulator (both Continuous and Segment) respects this annotation when generating the path between segments

**Applies to both pipelines:**
- Segment Camera: TransitionStyle stored on CameraSegment, used during export
- Continuous Camera: WaypointGenerator uses TransitionStyle to adjust spring response — Hold produces no waypoint change, DirectPan produces position-only waypoint (zoom unchanged)

### Files Affected

- New: `TransitionResolver.swift` (in Generators/)
- Modified: `SegmentPlanner.swift` — call TransitionResolver after segment creation
- Modified: `WaypointGenerator.swift` — respect TransitionStyle for continuous camera
- Modified: `CameraSegment` or equivalent — add TransitionStyle property

## Section 2: Confidence-Based Movement Suppression

### Current State

`IntentClassifier` assigns confidence values (0.5–0.95) to IntentSpans, but downstream consumers (WaypointGenerator, SegmentPlanner, ShotPlanner) treat all intents equally regardless of confidence. A single keystroke (confidence 0.5) triggers the same camera movement as sustained typing (confidence 0.9).

### Design

Introduce a **confidence threshold** for camera movement:

**WaypointGenerator (Continuous Camera):**
- Before generating a waypoint from an IntentSpan, check confidence against threshold
- Below threshold: skip waypoint generation entirely, camera maintains previous state
- Near threshold: generate waypoint but with reduced urgency (lazy response), so the camera reacts softly

**SegmentPlanner (Segment Camera):**
- Low-confidence scenes are absorbed into the preceding segment (extend previous segment's duration)
- If the first scene is low-confidence, it becomes an idle/hold segment

**SpringDamperSimulator (Continuous Camera — complementary):**
- For intents that pass the threshold but have moderate confidence: widen the dead zone proportionally
- Effect: camera tolerates more cursor deviation before reacting, producing a calmer response for uncertain intents

**Threshold calibration:**
Three discrete confidence bands (not a continuous gradient — simpler to reason about and tune):
- **High confidence (≥ 0.85)**: full camera response (current behavior)
- **Medium confidence (0.6–0.85)**: reduced response (wider dead zone, lower urgency)
- **Low confidence (< 0.6)**: no camera movement

If ALL scenes in a recording fall below the low confidence threshold, the recording becomes a single idle/hold segment at 1.0x zoom. This is the expected behavior for recordings with no clear user activity.

### Files Affected

- Modified: `WaypointGenerator.swift` — confidence check before waypoint creation
- Modified: `SegmentPlanner.swift` — low-confidence scene absorption
- Modified: `SpringDamperSimulator.swift` — confidence-scaled dead zone width (via DeadZoneSettings)

## Section 3: Post-Interaction Trajectory Analysis

### Current State

`IntentClassifier` classifies intent at event time. A click is always classified as `clicking` regardless of what happens afterward. This misses contextual information: a click that opens a dropdown, a click that focuses a text field, or a click followed by immediate typing all have different ideal ROIs.

### Design

Add a **refinement pass** (`refineWithPostContext()`) at the end of `IntentClassifier.classify()`. After initial classification is complete, iterate through IntentSpans and refine based on subsequent context:

**Refinement rules (using AX state changes, not cursor trajectory):**

1. **Click → UI element change**: If a click IntentSpan is followed by an AX sample showing a new focused element or new UI element appearance, update the click's `focusPosition` to the new element's center and `focusElement` to the new element's UIElementInfo. This leverages Screenize's unique AX integration — we use actual UI state changes rather than cursor movement heuristics.

2. **Click → Drag continuation**: If a click IntentSpan is immediately followed by a drag IntentSpan (gap < continuation threshold), expand the click's `focusPosition` to the centroid of the drag's bounding box and update `focusElement` if the drag target is identifiable.

3. **Click → Typing continuation**: If a click IntentSpan is immediately followed by a typing IntentSpan, replace the click's `focusPosition` and `focusElement` with the typing target element (from AX focused element). The click was a focus action — the real area of interest is the text field, not the click point.

**Key principle**: Screenize has AX data that provides ground truth about UI state. Use this instead of inferring intent from cursor movement patterns. AX tells us what actually happened (a text field became focused, a menu appeared), not what might have happened.

**Implementation:**
- Runs after initial `classify()` produces all IntentSpans
- Looks at UIStateSample changes around IntentSpan boundaries
- Only modifies `focusPosition`, `focusElement`, and potentially confidence — does not change intent type
- Non-destructive: original classification preserved, refinement layered on top

### Files Affected

- Modified: `IntentClassifier.swift` — add `refineWithPostContext()` method
- Read-only dependency: UIStateSample data (already available in classifier)

## Section 4: Soft Clamping

### Current State

`ShotPlanner.clampCenter()` uses hard `min`/`max` to constrain camera center within viewport bounds. When the camera reaches an edge, it stops abruptly. `SpringDamperSimulator` has soft velocity pushback at boundaries, but `ShotPlanner` and `SegmentPlanner` use hard clips.

### Design

Add a **soft clamp utility function** and apply it to the planning layer (ShotPlanner, SegmentPlanner). The simulator's existing velocity-based soft pushback is preserved as-is.

**Soft clamp behavior:**
- Define a "cushion zone" near each viewport boundary
- Within the cushion zone, apply a smoothstep-based easing that progressively reduces how far toward the boundary the camera can go
- Outside the cushion zone (interior): no effect, camera moves freely
- At the boundary: camera reaches it smoothly with zero velocity feel, never overshoots

**Easing approach:**
- Use the same smoothstep (hermite) function already used in `DeadZoneTarget.swift` for gradient band interpolation: `t * t * (3 - 2 * t)`. This maintains consistency with existing camera easing and avoids introducing a new curve type.
- The cushion width scales with zoom level (higher zoom = larger viewport fraction is "near edge")

**Application points:**
1. **ShotPlanner** — after computing scene center, apply soft clamp before returning
2. **SegmentPlanner** — segment target positions pass through soft clamp

**Not applied to SpringDamperSimulator** — it already has velocity-based soft pushback which serves the same purpose during physics simulation. Applying position soft clamp here could conflict with the velocity damping. The planning layer handles the "desired position" softening; the simulator handles the "in-motion" softening.

### Files Affected

- New: soft clamp utility (in Core/Coordinates.swift or a new math utility)
- Modified: `ShotPlanner.swift` — use soft clamp in center calculation
- Modified: `SegmentPlanner.swift` — use soft clamp for segment target positions

## Section 5: AX Sampling Enhancement + ROI Utilization

### Current State

AX (Accessibility) data is sampled as UIStateSamples and used by ShotPlanner as the highest-priority source for element-based zoom sizing. However:
- Sampling frequency may be too low to catch rapid UI changes (focus shifts, modal appearances)
- Only the focused element's frame is used; parent container context is ignored
- Small UI elements (buttons, icons) can produce excessively narrow zoom regions

### Design

**Adaptive sampling frequency:**
- During active interaction periods (clicking, typing, navigating): increase AX sampling rate
- During idle/reading periods: reduce AX sampling rate to save resources
- AX queries are expensive; adaptive rate balances accuracy vs. performance
- Owner: The component that manages the AX polling timer (currently in the recording coordinator layer, not in `AccessibilityInspector` which is stateless). A new `AXSamplingCoordinator` may be needed to own the adaptive timer, receiving activity signals from `EventMonitorManager` and dispatching queries via `AccessibilityInspector`
- Note: Adaptive sampling is a moderate-complexity addition. Section 6 (focused intent) and Section 3 (post-interaction refinement) can work with the existing sampling rate as long as AX data is present at all. Adaptive sampling can be deferred to a follow-up if needed.

**Parent container ROI:**
- When the focused element is below a size threshold (too small for comfortable viewing), traverse the AX hierarchy to find a meaningful parent container
- **Traversal bounds**: max 3 levels up to limit performance cost. Cache parent container for the duration of a focus session (same focused element = same parent, no re-traversal)
- **Fallback**: if parent bounds exceed 80% of screen in either dimension, discard parent and use element bounds + padding (prevents unhelpful bounds from Electron/web-view apps with deeply nested AX hierarchies)
- AX role-based heuristics:
  - `AXTextArea`, `AXTextField`, `AXTable`: use element's own bounds (these are typically large enough)
  - `AXButton`, `AXMenuItem`, `AXCheckBox`: use parent group/toolbar bounds as ROI context
  - `AXStaticText`, `AXImage`: use parent container bounds
- ShotPlanner receives both element bounds and container bounds; uses container bounds as a minimum ROI floor

**Integration with ShotPlanner:**
- Element-based sizing (current highest priority) enhanced with container awareness
- When element is small: `effectiveROI = max(elementBounds, parentContainerBounds)` (with appropriate padding)
- When element is large (text areas, editors): use element bounds directly (current behavior)

### Files Affected

- Modified: `AccessibilityInspector.swift` or sampling coordinator — adaptive frequency
- Modified: `EventMonitorManager.swift` — signal activity level for sampling rate adjustment
- Modified: `ShotPlanner.swift` — parent container ROI logic, role-based heuristics
- Potentially modified: UIStateSample — include parent container bounds if not already captured

## Section 6: Two-Stage Zoom Transition (Focused → Typing)

### Current State

`IntentClassifier` has a single `typing` intent with context (codeEditor, textField, terminal, richTextEditor). ShotPlanner applies the same zoom range whether the user just focused the editor or is actively typing. No distinction between "I clicked into the editor" and "I'm typing code."

### Design

Split the typing workflow into two intent stages:

**New intent: `focused`**
- Detected when: AX reports a new focused element that is a text input (AXTextArea, AXTextField, or known editor role), AND no keystroke events follow within a short window
- Behavior: Camera frames the **entire element** — user sees the full editor/field, gaining context of where they are
- Zoom: lower end of the typing zoom range, or a dedicated focused zoom range (wider framing)
- ROI: AX element's full bounds

**Existing intent: `typing` (refined)**
- Detected when: keystroke events begin after a focused state
- Behavior: Camera narrows to **caret vicinity** — user sees the code they're writing
- Zoom: upper end of the typing zoom range (tighter framing around caret)
- ROI: AX caret bounds, or cursor position with a comfortable context margin

**Transition flow:**

```
clicking → focused → typing
  (click)   (wide)   (close-up)
```

- `clicking → focused`: Camera moves to the editor element (may involve pan + zoom change)
- `focused → typing`: Camera tightens from full element to caret area. Position typically stays similar (same element), so TransitionResolver (Section 1) commonly classifies this as Hold or DirectPan. In cases where the caret is far from the element center, FullTransition is an acceptable fallback.

**Detection logic in IntentClassifier:**
- After a click on a text element: emit `focused` intent instead of immediately waiting for `typing`
- If keystrokes arrive: transition `focused → typing`
- If no keystrokes arrive within a timeout (suggested range: 1–3 seconds, tunable via settings): `focused` naturally ends, next intent takes over
- If keystrokes arrive WITHOUT a preceding click (e.g., continuing to type in already-focused field): emit `typing` directly, no `focused` phase

**WaypointGenerator / SegmentPlanner:**
- `focused` intent gets its own urgency level (normal — not as urgent as typing, not as lazy as reading)
- `focused → typing` transition gets smooth urgency ramp-up

### Files Affected

- Modified: `IntentClassifier.swift` — add `focused` intent type, detection logic
- Modified: `ShotPlanner.swift` — zoom range and ROI for `focused` intent
- Modified: `WaypointGenerator.swift` — urgency and lead time for `focused` intent
- Modified: `UserIntent` enum — add `focused(context:)` case

## Runtime Execution Order

Within the generation pipeline, the sections execute in this order:

1. **AX sampling** (Section 5) — happens during recording, produces richer UIStateSamples
2. **Intent classification** (Section 6) — IntentClassifier produces spans including `focused` intent
3. **Post-interaction refinement** (Section 3) — `refineWithPostContext()` adjusts focusPosition/focusElement
4. **Confidence filtering** (Section 2) — low-confidence spans are suppressed or absorbed
5. **Scene merging** — existing `mergeScenes()` merges identical scenes
6. **Transition resolution** (Section 1) — TransitionResolver classifies remaining segment transitions
7. **Soft clamping** (Section 4) — applied to final camera positions in ShotPlanner/SegmentPlanner

## Dependencies Between Sections

```
Section 5 (AX sampling) ← Section 6 (focused intent needs better AX data)
Section 5 (AX sampling) ← Section 3 (post-interaction refinement uses AX state changes)
Section 2 (confidence suppression) ← Section 1 (TransitionResolver benefits from fewer low-quality segments)
Section 4 (soft clamping) — independent, can be implemented in any order
```

**Recommended implementation order:**
1. Section 5 — AX sampling (foundation for others)
2. Section 3 — Post-interaction refinement (improves ROI accuracy)
3. Section 6 — Two-stage zoom (uses improved AX data)
4. Section 2 — Confidence suppression (reduces noise)
5. Section 1 — TransitionResolver (polishes remaining transitions)
6. Section 4 — Soft clamping (final polish)

## Success Criteria

- **Pan reduction**: Noticeably fewer unnecessary camera transitions in typical screen recording sessions (coding, browsing, app usage)
- **ROI accuracy**: Camera frames the relevant UI area, not just the cursor position. Text editors show full editor on focus, caret area on typing.
- **Smoothness**: No abrupt boundary stops; transitions between similar segments are seamless
- **No regression**: Existing working behaviors (dead zone, anticipation, urgency-based response) remain functional
