# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

**Xcode (recommended):**

- Open `Screenize.xcodeproj`
- Cmd+B to build, Cmd+R to run

**Command Line:**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build
```

**Permission Reset (when screen capture or microphone permissions break):**

```bash
./scripts/reset-permissions.sh
```

Manual permission reset:

```bash
tccutil reset ScreenCapture com.screenize.Screenize
tccutil reset Microphone com.screenize.Screenize
```

## Architecture

Screenize is a macOS screen recording application that captures screen/window content with mouse tracking, then post-processes recordings with auto-zoom effects, custom cursor rendering, and background styling.

**Two-pass processing model:**

1. **Recording phase**: ScreenCaptureManager captures raw video via ScreenCaptureKit; MouseDataRecorder logs cursor positions and clicks to `<video>.mouse.json`; VideoWriter encodes raw frames to video file
2. **Editor phase**: User loads recording into timeline-based editor, auto-generators create keyframes from mouse data, user can edit keyframes manually
3. **Export phase**: ExportEngine reads raw video + timeline keyframes; FrameEvaluator computes per-frame state; Renderer applies transforms/effects

**Core modules (`Core/`):**

- `Capture/` - ScreenCaptureKit wrapper (ScreenCaptureManager, CaptureConfiguration, PermissionsManager)
- `Recording/` - Video encoding (VideoWriter) and session orchestration (RecordingCoordinator, RecordingSession)
- `Tracking/` - Mouse/click tracking (MouseDataRecorder, MouseTracker, ClickDetector, AccessibilityInspector)

**Timeline system (`Timeline/`):**

- `Timeline` - Contains multiple tracks, each with time-sorted keyframes
- `Track` protocol - Base for TransformTrack (zoom/pan), RippleTrack (click effects), CursorTrack (cursor style)
- `Keyframe` - Individual keyframe types (TransformKeyframe, RippleKeyframe) with time, values, and easing curves
- `AnyTrack` - Type-erased wrapper for Codable serialization

**Keyframe generators (`Generators/`):**

- `KeyframeGenerator` protocol - Analyzes MouseDataSource to auto-generate keyframes
- `SmartZoomGenerator` - Intelligent zoom using video analysis and UI state (Vision Framework based)
- `ZoomContextAnalyzer` - UI element context analysis for zoom strategies
- `RippleGenerator` - Creates click ripple effects
- `CursorInterpolationGenerator` - Smooths cursor movement
- `ClickCursorGenerator` - Creates cursor style keyframes on clicks

**Video analysis (`Analysis/`):**

- `VideoFrameAnalyzer` - Vision Framework based frame analysis (optical flow, saliency, feature print)

**Render pipeline (`Render/`):**

- `ExportEngine` - Orchestrates final video export
- `FrameEvaluator` - Evaluates timeline state at any given time
- `Renderer` - Applies transforms and composites effects using CoreImage
- `PreviewEngine` - Real-time preview with caching

**Project system (`Project/`):**

- `ScreenizeProject` - Main project model (`.fsproj` JSON files)
- `MediaAsset` - Reference to video + mouse data files
- `RenderSettings` - Export codec, quality, resolution settings

**State management:**

- `AppState.swift` - Global application state (@MainActor singleton)
- `EditorViewModel` - Timeline editing state
- @AppStorage for user preferences

**Data flow:**

- Mouse data stored as `<videoName>.mouse.json` alongside video files
- Project files (`.fsproj`) store timeline edits + render settings as JSON
- ScreenCaptureDelegate for frame callbacks from ScreenCaptureKit
- Combine publishers for reactive UI updates

## Key Technologies

- **ScreenCaptureKit** - Screen/window capture
- **AVFoundation** - Video encoding/decoding (AVAssetReader/Writer)
- **CoreImage** - GPU-accelerated image processing
- **SwiftUI** - Entire UI
- **Swift Concurrency** - async/await with @MainActor for thread safety

Target: macOS 13.0+, no external dependencies.

## Conventions

- @MainActor on all major state classes
- Manager/Coordinator suffixes for orchestration classes
- Korean comments throughout the codebase
- Sendable types and dispatch queues for thread safety
- Keyframes always sorted by time within tracks
- Normalized coordinates (0~1) for mouse positions to handle different screen sizes
