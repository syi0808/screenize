# Advanced Generation Settings — Design

**Date:** 2026-03-10
**Status:** Approved

## Overview

A dedicated settings window exposing all 80+ smart generation constants as user-configurable parameters. App-level defaults with per-project overrides. Targets power users who want full control over camera behavior generation.

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage scope | App-level defaults + per-project overrides | Maximum flexibility |
| UI layout | Flat collapsible sections | Matches existing patterns, scannable |
| Access point | Separate window (menu bar + gear button) | Keeps editor clean |
| Reset granularity | Per-setting reset | Sufficient control without clutter |
| Preset system | Save/Load user presets (no built-in) | Community-driven discovery |
| Apply behavior | Manual "Regenerate" button | Avoids expensive intermediate states |

## Data Architecture

### GenerationSettings (Codable struct)

Top-level struct containing 5 nested setting groups. Each nested struct has default values matching current hardcoded constants. `static let default` on the top-level struct.

#### 1. CameraMotionSettings (~15 params)

From `ContinuousCameraSettings`, `DeadZoneSettings`, `MicroTrackerSettings`:

| Parameter | Type | Default | Source |
|-----------|------|---------|--------|
| positionDampingRatio | CGFloat | 0.90 | ContinuousCameraSettings |
| positionResponse | CGFloat | 0.35 | ContinuousCameraSettings |
| zoomDampingRatio | CGFloat | 0.90 | ContinuousCameraSettings |
| zoomResponse | CGFloat | 0.55 | ContinuousCameraSettings |
| urgencyBlendDuration | CGFloat | 0.5 | ContinuousCameraSettings |
| urgencyImmediateMultiplier | CGFloat | 0.05 | ContinuousCameraSettings |
| urgencyHighMultiplier | CGFloat | 0.5 | ContinuousCameraSettings |
| urgencyNormalMultiplier | CGFloat | 1.0 | ContinuousCameraSettings |
| urgencyLazyMultiplier | CGFloat | 2.0 | ContinuousCameraSettings |
| boundaryStiffness | CGFloat | 12.0 | ContinuousCameraSettings |
| zoomSettleThreshold | CGFloat | 0.02 | ContinuousCameraSettings |
| safeZoneFraction | CGFloat | 0.75 | DeadZoneSettings |
| safeZoneFractionTyping | CGFloat | 0.60 | DeadZoneSettings |
| gradientBandWidth | CGFloat | 0.25 | DeadZoneSettings |
| correctionFraction | CGFloat | 0.45 | DeadZoneSettings |
| hysteresisMargin | CGFloat | 0.15 | DeadZoneSettings |
| correctionFractionTyping | CGFloat | 0.80 | DeadZoneSettings |
| deadZoneMinResponse | CGFloat | 0.20 | DeadZoneSettings |
| deadZoneMaxResponse | CGFloat | 0.50 | DeadZoneSettings |
| idleVelocityThreshold | CGFloat | 0.02 | MicroTrackerSettings |
| microTrackerDampingRatio | CGFloat | 1.0 | MicroTrackerSettings |
| microTrackerResponse | CGFloat | 3.0 | MicroTrackerSettings |

#### 2. ZoomSettings (~18 params)

From `ShotSettings`, `ContinuousCameraSettings`:

| Parameter | Type | Default | Source |
|-----------|------|---------|--------|
| typingCodeZoomRange | ClosedRange<CGFloat> | 2.0...2.5 | ShotSettings |
| typingTextFieldZoomRange | ClosedRange<CGFloat> | 2.2...2.8 | ShotSettings |
| typingTerminalZoomRange | ClosedRange<CGFloat> | 1.6...2.0 | ShotSettings |
| typingRichTextZoomRange | ClosedRange<CGFloat> | 1.8...2.2 | ShotSettings |
| clickingZoomRange | ClosedRange<CGFloat> | 1.5...2.5 | ShotSettings |
| navigatingZoomRange | ClosedRange<CGFloat> | 1.5...1.8 | ShotSettings |
| draggingZoomRange | ClosedRange<CGFloat> | 1.3...1.6 | ShotSettings |
| scrollingZoomRange | ClosedRange<CGFloat> | 1.3...1.5 | ShotSettings |
| readingZoomRange | ClosedRange<CGFloat> | 1.0...1.3 | ShotSettings |
| switchingZoom | CGFloat | 1.0 | ShotSettings |
| idleZoom | CGFloat | 1.0 | ShotSettings |
| targetAreaCoverage | CGFloat | 0.7 | ShotSettings |
| workAreaPadding | CGFloat | 0.08 | ShotSettings |
| minZoom | CGFloat | 1.0 | ShotSettings |
| maxZoom | CGFloat | 2.8 | ShotSettings |
| idleZoomDecay | CGFloat | 0.5 | ShotSettings |
| zoomIntensity | CGFloat | 1.0 | ContinuousCameraSettings |

#### 3. IntentClassificationSettings (~11 params)

From `IntentClassifier`:

| Parameter | Type | Default | Source |
|-----------|------|---------|--------|
| typingSessionTimeout | CGFloat | 1.5 | IntentClassifier |
| navigatingClickWindow | CGFloat | 2.0 | IntentClassifier |
| navigatingClickDistance | CGFloat | 0.5 | IntentClassifier |
| navigatingMinClicks | Int | 2 | IntentClassifier |
| idleThreshold | CGFloat | 5.0 | IntentClassifier |
| continuationGapThreshold | CGFloat | 1.5 | IntentClassifier |
| continuationMaxDistance | CGFloat | 0.20 | IntentClassifier |
| scrollMergeGap | CGFloat | 1.0 | IntentClassifier |
| pointSpanDuration | CGFloat | 0.5 | IntentClassifier |
| contextChangeWindow | CGFloat | 0.8 | IntentClassifier |
| typingAnticipation | CGFloat | 0.4 | IntentClassifier |

#### 4. TimingSettings (~12 params)

From `ContinuousCameraSettings`, `WaypointGenerator`, `DeadZoneSettings`:

| Parameter | Type | Default | Source |
|-----------|------|---------|--------|
| leadTimeImmediate | CGFloat | 0.24 | WaypointGenerator |
| leadTimeHigh | CGFloat | 0.16 | WaypointGenerator |
| leadTimeNormal | CGFloat | 0.08 | WaypointGenerator |
| leadTimeLazy | CGFloat | 0.0 | WaypointGenerator |
| tickRate | CGFloat | 60.0 | ContinuousCameraSettings |
| typingDetailMinInterval | CGFloat | 0.2 | ContinuousCameraSettings |
| typingDetailMinDistance | CGFloat | 0.025 | ContinuousCameraSettings |
| responseFastThreshold | CGFloat | 0.5 | DeadZoneSettings |
| responseSlowThreshold | CGFloat | 2.0 | DeadZoneSettings |
| urgencyBlendDuration | CGFloat | 0.5 | ContinuousCameraSettings |

#### 5. CursorKeystrokeSettings (~8 params)

From `ClickCursorSettings`, `KeystrokeGeneratorSettings`:

| Parameter | Type | Default | Source |
|-----------|------|---------|--------|
| cursorScale | CGFloat | 2.0 | ClickCursorSettings |
| keystrokeEnabled | Bool | true | KeystrokeGeneratorSettings |
| shortcutsOnly | Bool | true | KeystrokeGeneratorSettings |
| displayDuration | CGFloat | 1.5 | KeystrokeGeneratorSettings |
| fadeInDuration | CGFloat | 0.15 | KeystrokeGeneratorSettings |
| fadeOutDuration | CGFloat | 0.3 | KeystrokeGeneratorSettings |
| minInterval | CGFloat | 0.05 | KeystrokeGeneratorSettings |

### Storage

**App-level defaults:**
- Path: `~/Library/Application Support/Screenize/generation_settings.json`
- Managed by `GenerationSettingsManager` singleton (@MainActor)
- Same pattern as existing `PresetManager`

**Per-project overrides:**
- Optional `generationSettings: GenerationSettings?` field on `ScreenizeProject`
- Serialized in `project.json`
- When `nil`, falls back to app-level defaults

**User presets:**
- Path: `~/Library/Application Support/Screenize/generation_presets.json`
- Array of `GenerationSettingsPreset` (name + `GenerationSettings`)

**Resolution:** `project.generationSettings ?? GenerationSettingsManager.shared.settings`

## UI

### Access

- Menu bar: `Screenize > Advanced Generation Settings...`
- Editor toolbar: gear icon button

### Window Layout

Standard macOS settings window. Single scrollable panel.

**Top bar:**
- Scope toggle: "App Defaults" / "This Project" (when project is open)
- Preset dropdown: Save as preset, load preset, delete preset
- "Regenerate" button (enabled when project is open)

**Body:** 5 collapsible `DisclosureGroup` sections:

1. **Camera Motion** — spring physics, dead zones, urgency multipliers
2. **Zoom Levels** — per-activity zoom ranges, global limits
3. **Intent Classification** — time thresholds, distance thresholds, counts
4. **Timing** — lead times, durations, intervals
5. **Cursor & Keystroke** — scale, display duration, fade timing

### Parameter Controls

| Type | Control |
|------|---------|
| CGFloat | Slider + numeric text field |
| ClosedRange<CGFloat> | Dual-thumb range slider |
| Bool | Toggle |
| Int | Stepper + text field |

Each parameter has:
- Label with descriptive name
- Current value display
- Reset button (visible on hover, restores default)
- Slider min/max bounds with default value indicator

## Integration with Generators

Existing settings structs gain `init(from:)` factory methods:

```swift
extension ContinuousCameraSettings {
    init(from settings: GenerationSettings) {
        self.init(
            positionDampingRatio: settings.cameraMotion.positionDampingRatio,
            positionResponse: settings.cameraMotion.positionResponse,
            // ...
        )
    }
}

extension ShotSettings {
    init(from settings: GenerationSettings) { ... }
}

extension DeadZoneSettings {
    init(from settings: GenerationSettings) { ... }
}
```

Generators continue using their internal types. The only change is initialization source.

## Out of Scope

- No real-time preview (manual regenerate only)
- No built-in presets (user-created only)
- No undo/redo within settings window
- No import/export UI (JSON files are shareable manually)
- No changes to the legacy V1 generator settings (ClickZoomSettings, SmartZoomSettings, TypingZoomSettings)
