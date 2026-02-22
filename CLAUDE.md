# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Language

All comments, code, commit messages, and documentation must be written in English. Do not use any other language.

## MANDATORY WORKFLOW

**Commit per unit:** Always commit after completing each individual feature or bug fix. Never bundle multiple changes into a single commit.

**Every task must follow this pattern:**

```
1. START  →  work-context-finder (check previous work)
2. WORK   →  implement the task
3. FINISH →  /log-work (document automatically)
```

### Before Starting Any Task

Run `work-context-finder` agent first (skip if continuing within same session):
```
Use Task tool with subagent_type="work-context-finder"
```

### After Completing Any Task

Execute `/log-work` skill automatically (do NOT ask for permission):
```
Use Skill tool with skill="work-logger"
```

## Build Commands

**Xcode (recommended):**

- Open `Screenize.xcodeproj`
- Cmd+B to build, Cmd+R to run

**Command Line:**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build
```

**Linting:**

```bash
./scripts/lint.sh          # Run SwiftLint
./scripts/lint.sh --fix    # Auto-fix violations
```

Configuration in `.swiftlint.yml`. Key limits: line length 140/200, file length 600/1000, function length 80/150. `force_cast` is warning-only (required by AXValue API); `force_try` is error.

**Permission Reset (when screen capture or microphone permissions break):**

```bash
tccutil reset ScreenCapture com.screenize.Screenize
tccutil reset Microphone com.screenize.Screenize
```

**No automated tests exist yet.** Build verification is the primary check.

## Architecture

Screenize is a macOS screen recording application that captures screen/window content with mouse tracking, then post-processes recordings with auto-zoom effects, custom cursor rendering, and background styling.

**Three-phase processing model:**

1. **Recording phase**: ScreenCaptureManager captures raw video via ScreenCaptureKit; MouseDataRecorder logs cursor positions, clicks, keyboard events, scrolls, and drags to `<video>.mouse.json`; VideoWriter encodes raw frames to video file
2. **Editor phase**: User loads recording into timeline-based editor, auto-generators create keyframes from mouse data, user can edit keyframes manually
3. **Export phase**: ExportEngine reads raw video + timeline keyframes; FrameEvaluator computes per-frame state; Renderer applies transforms/effects via CoreImage

**Core modules (`Core/`):**

- `Capture/` - ScreenCaptureKit wrapper (ScreenCaptureManager, CaptureConfiguration, PermissionsManager)
- `Recording/` - Video encoding (VideoWriter) and session orchestration (RecordingCoordinator, RecordingSession); CFRRecordingManager for macOS 15+ SCRecordingOutput
- `Tracking/` - Mouse/click tracking (MouseTracker, ClickDetector, AccessibilityInspector)
- `EventMonitoring/` - Centralized event monitors (EventMonitorManager) for keyboard, drag, and scroll handlers in `Recording/EventHandlers/`

**Timeline system (`Timeline/`):**

- `Timeline` - Contains multiple tracks, each with time-sorted keyframes; supports trim range
- `Track` protocol - Base for TransformTrack (zoom/pan), RippleTrack (click effects), CursorTrack (cursor style), KeystrokeTrack (keystroke overlays)
- `Keyframe` - Individual keyframe types (TransformKeyframe, RippleKeyframe, CursorStyleKeyframe, KeystrokeKeyframe) with time, values, and easing curves
- `AnyTrack` - Type-erased wrapper for Codable serialization of heterogeneous track types

**Keyframe generators (`Generators/`):**

- `KeyframeGenerator` protocol - Analyzes MouseDataSource to auto-generate keyframes
- `SmartZoomGenerator` - Session-based intelligent zoom: ActivityCollector → SessionClusterer → ZoomLevelCalculator → SessionCenterResolver
- `RippleGenerator` - Creates click ripple effects
- `CursorInterpolationGenerator` - Smooths cursor movement
- `ClickCursorGenerator` - Creates cursor style keyframes on clicks
- `KeystrokeGenerator` - Creates keystroke overlay keyframes from keyboard events

**Render pipeline (`Render/`):**

- `ExportEngine` - Orchestrates final video export with progress tracking
- `FrameEvaluator` - Evaluates timeline state at any given time
- `Renderer` - Applies transforms and composites effects using CoreImage
- `PreviewEngine` - Real-time preview with frame caching (PreviewCache)
- `KeyframeInterpolator` / `MousePositionInterpolator` - Easing-aware interpolation between keyframes

**Project system (`Project/`):**

- `ScreenizeProject` - Main project model (v2, `.screenize` package containing `project.json`)
- `MediaAsset` - Stores relative paths (`videoPath`/`mouseDataPath`) in JSON; absolute URLs resolved at load time via `resolveURLs(from:)`
- `PackageManager` - Singleton managing `.screenize` package CRUD (create, save, load, path resolution)
- `ProjectManager` - Orchestrates project lifecycle, recent projects, delegates to PackageManager
- `ProjectCreator` - Factory creating projects from recordings or imported videos (accepts `PackageInfo`)
- `RenderSettings` - Export codec, quality, resolution settings

**`.screenize` package structure:**

```
MyProject.screenize/           # macOS package (appears as single file in Finder)
├── project.json               # ScreenizeProject v2 (JSON)
└── recording/
    ├── recording.mp4          # Video (keeps original extension)
    └── recording.mouse.json   # Mouse tracking data
```

UTType `com.screenize.project` conforming to `com.apple.package` is registered in `Info.plist`.

**State management:**

- `AppState.swift` - Global application state (@MainActor singleton)
- `EditorViewModel` - Timeline editing state
- @AppStorage for user preferences
- Combine publishers for reactive UI updates

**Data flow:**

- Mouse data stored as `<videoName>.mouse.json` alongside video files (contains positions, clicks, scrolls, keyboard events, drag events, UI state samples)
- Project packages (`.screenize/`) contain `project.json` with timeline edits + render settings, plus a `recording/` subdirectory for media files
- ScreenCaptureDelegate for frame callbacks from ScreenCaptureKit

## Coordinate System

Three coordinate spaces are used; all internal logic uses NormalizedPoint. Types are defined in `Core/Coordinates.swift`:

- **ScreenPoint** - macOS screen coordinates (bottom-left origin, pixel units)
- **CapturePixelPoint** - Pixel coordinates relative to capture area (stored in mouse JSON)
- **NormalizedPoint** - 0–1 range, bottom-left origin (internal standard for timeline, keyframes, rendering)

`CoordinateConverter` handles all conversions. When writing rendering or tracking code, always work in NormalizedPoint and convert at boundaries.

## Key Technologies

- **ScreenCaptureKit** - Screen/window capture
- **AVFoundation** - Video encoding/decoding (AVAssetReader/Writer)
- **CoreImage** - GPU-accelerated image processing
- **Vision Framework** - Frame analysis for smart zoom (optical flow, saliency)
- **Accessibility Framework** - UI element detection for zoom targeting
- **SwiftUI** - Entire UI
- **Swift Concurrency** - async/await with @MainActor for thread safety
- **Sparkle** - Auto-update framework (only external dependency)

Target: macOS 13.0+.

## Conventions

- `@MainActor` on all major state classes; `nonisolated(unsafe)` for properties accessed from ScreenCaptureKit capture queues
- Manager/Coordinator suffixes for orchestration classes
- Sendable types and dispatch queues for thread safety
- Keyframes always sorted by time within tracks (enforced in Track initializers)
- Normalized coordinates (0–1, bottom-left origin) for all internal position data
- Commit messages use imperative mood ("Add feature" not "Added feature")
