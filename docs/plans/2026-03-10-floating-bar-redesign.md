# Recording Floating Bar Redesign

## Goal

Unify and redesign the recording floating bar for consistent UI/UX, following macOS native aesthetics inspired by Screen Studio.

## Structural Changes

### Unify to Single Panel

- Remove `RecordingFloatingPanel` entirely (dead weight — duplicate of CaptureToolbarPanel's recording phase)
- Route all recording paths through `CaptureToolbarPanel`
- Non-toolbar recording path shows `CaptureToolbarPanel` directly in recording phase, skipping selection

### Files to Remove

- `Screenize/Views/Recording/RecordingFloatingPanel.swift`
- References in `RecordingState.swift` (`showRecordingFloatingPanel`, `hideRecordingFloatingPanel`)

### Files to Modify

- `AppState.swift` — remove fallback panel logic, always use `CaptureToolbarCoordinator`
- `CaptureToolbarPanel.swift` — new visual style, drag support, bottom positioning
- `CaptureToolbarCoordinator.swift` — support direct-to-recording phase entry

## Visual Style

### Common Style (both phases)

| Property | Before | After |
|----------|--------|-------|
| Background | `.ultraThickMaterial` | `.ultraThinMaterial` |
| Corner radius | 14pt | 16-18pt |
| Border | white 0.15 opacity, 0.5pt | white 0.08-0.1 opacity, 0.5pt |
| Shadow | Dual layer (0.2 + 0.15) | Single layer, 0.08-0.1 opacity |
| Position | Top center, 80pt from top | **Bottom center** + draggable |
| Color scheme | Dark | Dark |

### Design Token Updates

- Add `CornerRadius.xxl` or adjust existing value for 16-18pt
- Add `DesignOpacity.whisper` (~0.08) for subtle borders/shadows

## Selection Phase

- **Controls unchanged:** Mode buttons (Entire Screen / Window), System Audio toggle, Mic menu, Frame Rate menu, Close button
- Apply new visual style
- Clean up spacing/layout to align with design tokens

## Recording Phase

### Controls

| Element | Description |
|---------|-------------|
| Recording dot | 8x8pt red circle, pulse animation |
| Timer | Monospaced elapsed time |
| Paused badge | "PAUSED" yellow badge (when paused) |
| Restart button | **NEW** — restart recording from scratch |
| Pause/Resume button | Toggle pause state |
| Delete button | **NEW** — discard current recording |
| Stop button | Finish and save recording |

### Button Layout

```
[🔴 00:00:00]  [↩ Restart] [⏸ Pause] [🗑 Delete] [⏹ Stop]
```

## Drag Behavior

- NSPanel supports mouse drag to reposition
- Default position: bottom center of screen
- Remember position within session (not persisted across app launches)
- Constrain to screen bounds

## Out of Scope

- Countdown panel redesign (separate effort)
- Keyboard shortcut changes
- Menu bar icon changes
