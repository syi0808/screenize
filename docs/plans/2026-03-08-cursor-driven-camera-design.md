# Cursor-Driven Camera Design

**Date:** 2026-03-08
**Status:** Approved
**Supersedes:** 2026-03-07-dual-layer-camera-design.md (intent-driven approach)

## Problem

Current smart generation is intent-driven: IntentClassifier → WaypointGenerator → SpringDamperSimulator. The camera targets waypoint positions derived from intents, with cursor as a secondary 60% blend. This causes:

1. **Jerkiness** — Intent boundary transitions cause target jumps, even with urgency blending
2. **No cursor-following feel** — Camera reacts to events (clicks, typing) rather than continuously tracking cursor movement
3. **Micro offset capping** — MicroTracker limited to 30% viewport offset; cursor outruns camera easily

## Solution

Invert the architecture: **cursor is the primary camera target, intent only controls zoom level.**

## Architecture

```
Cursor Position (60Hz sampled)
    ↓
Layer 1: Active Tracking Spring (fast, ~0.15s response)
    → Always follows cursor position
    → Primary camera center driver
    ↓
Layer 2: Idle Re-centering Spring (slow, ~2.5s response)
    → Activates when cursor velocity drops below threshold
    → Gently drifts camera center toward cursor
    → Ensures good framing when action resumes
    ↓
Final Camera Center
    ↓
Soft Boundary Clamp (existing)
    ↓
[TimedTransform] at 60Hz

Intent Classification (parallel path)
    → Determines zoom level only (typing=1.5-2x, clicking=1.3x, idle=1.0x)
    → Separate zoom spring (~0.7s, critically damped)
```

## Dual-Layer Responsibilities

### Layer 1: Active Tracking
- **Input:** Smoothed cursor position
- **Output:** Camera center offset
- **Response:** 0.15s (fast, responsive)
- **Damping:** 0.85 (slight underdamp for natural feel)
- **Always active:** Tracks cursor regardless of activity state

### Layer 2: Idle Re-centering
- **Input:** Current camera center vs cursor position
- **Output:** Slow correction offset
- **Response:** 2.5s (slow drift)
- **Damping:** 1.0 (critically damped, no overshoot)
- **Activation:** When cursor velocity drops below threshold
- **Purpose:** Ensures cursor is well-framed when next action begins

### Zoom (Intent-Driven)
- **Input:** IntentClassifier output (activity type)
- **Output:** Target zoom level
- **Response:** 0.7s (medium, smooth zoom transitions)
- **Damping:** 1.0 (critically damped)
- **Trigger:** Intent type changes

## Spring Parameters (Starting Point)

| Parameter | Layer 1 (Active) | Layer 2 (Idle) | Zoom |
|-----------|------------------|----------------|------|
| Response | 0.15s | 2.5s | 0.7s |
| Damping | 0.85 | 1.0 | 1.0 |
| Activation | Always | velocity < threshold | Intent change |

## What Gets Removed

- `WaypointGenerator` positioning logic (keep zoom-per-intent mapping only)
- Cursor blend weight concept in SpringDamperSimulator
- Macro layer's intent-based center targeting
- MicroTracker dead zone / max offset capping
- Urgency system for position (keep for zoom transition speed only)

## What Gets Kept/Repurposed

- `IntentClassifier` — zoom level decisions
- `SpringDamperSimulator` — repurposed as cursor-following engine
- `MicroTracker` — repurposed as idle re-centering layer
- Soft boundary clamping — viewport edge handling
- `SmoothedMouseDataSource` — cursor pre-smoothing
- `EventTimeline` — still needed for IntentClassifier input
- `FrameEvaluator` — unchanged (reads TimedTransform array)

## Data Flow

```
MouseData
  ├→ SmoothedMouseDataSource (Catmull-Rom resampling)
  │     ↓
  │   Smoothed cursor positions at frame rate
  │     ↓
  │   Layer 1: Active tracking spring
  │     ↓
  │   Layer 2: Idle re-centering spring
  │     ↓
  │   Soft boundary clamp
  │     ↓
  │   Camera center (60Hz)
  │
  ├→ EventTimeline → IntentClassifier
  │     ↓
  │   Intent spans with zoom levels
  │     ↓
  │   Zoom spring (separate)
  │     ↓
  │   Camera zoom (60Hz)
  │
  └→ Combined: [TimedTransform] array
        ↓
      FrameEvaluator (binary search + lerp, unchanged)
```

## Behavioral Comparison

| Scenario | Current (Intent-Driven) | New (Cursor-Driven) |
|----------|------------------------|---------------------|
| Cursor moves | Blend + capped micro offset | Direct spring follow (no cap) |
| Intent changes | Camera jumps to new waypoint | Only zoom changes |
| Cursor stops | Offset decays to zero | Camera holds, then slowly re-centers |
| Rapid movement | Hits micro offset cap | Spring stretches, catches up naturally |
| Typing session | Camera targets intent focus pos | Camera stays where cursor is, zooms in |
