# Dual-Layer Camera Design

Improve smart generation pipeline quality to Screen Studio level by separating the camera into two layers: Macro (framing) and Micro (tracking).

## Problem

Current single-layer spring-damper camera has quality issues:
- Jerky zoom in/out (abrupt urgency changes at intent boundaries)
- No smooth following camera feel (detail waypoints create discrete jumps)
- Zoom-pan timing mismatch (position response=0.4s vs zoom response=0.5s)
- Cursor slides during camera pan (independent smoothing)

## Architecture

```
Intent Analysis (existing)
    |
    v
+-------------------------------+
|  Macro Layer (Framing)        |
|  - Which region to show       |
|  - Zoom level                 |
|  - Slow spring (response 0.8s)|
|  - Target changes per intent  |
+---------------+---------------+
                |
                v
+-------------------------------+
|  Micro Layer (Tracking)       |
|  - Cursor/caret following     |
|  - No zoom change (offset)    |
|  - Fast spring (response 0.15s)|
|  - Updates every frame (60Hz) |
+---------------+---------------+
                |
                v
    Final camera = macro + micro offset
```

## Macro Layer

### Role
Determines "what region of the screen to show" with slow, stable movement. Zoom changes feel like breathing.

### Changes from Current Pipeline
- Remove detail waypoints (move to micro layer)
- Unify zoom-pan response time to 0.8s
- Blend urgency over 0.3s transitions (not discrete jumps)
- Soft clamping at boundaries (pushback force instead of velocity reset)

### Spring Parameters
```
dampingRatio: 1.0 (critically damped, no overshoot)
positionResponse: 0.8s
zoomResponse: 0.8s (same as position for sync)
```

### Urgency Blending
```
effectiveUrgency = lerp(prevUrgency, nextUrgency, blendProgress)
blendProgress = clamp((time - transitionStart) / 0.3, 0, 1)
```

### Soft Clamping
```
overflow = center.x - maxX
if overflow > 0:
    velocity.x -= overflow * boundaryStiffness * dt
```

## Micro Layer

### Role
Tracks cursor/caret within the macro frame. Fast, responsive, no zoom changes.

### Dead Zone
Central 40% of viewport (+-20% each axis). Micro offset activates only when cursor exits dead zone. Offset proportional to excess distance.

```
relativePos = cursorPos - macro.center
viewportHalf = 0.5 / macro.zoom
deadZone = viewportHalf * 0.4

excess = abs(relativePos.x) - deadZone
if excess > 0:
    targetOffset.x = sign(relativePos.x) * excess
```

### Offset Limit
Max 30% of viewport to preserve macro framing:
```
maxOffset = viewportHalf * 0.3
targetOffset = clamp(targetOffset, -maxOffset, maxOffset)
```

### Spring Parameters
```
dampingRatio: 0.85 (slightly underdamped, natural overshoot)
response: 0.15s (5x faster than macro)
```

### Intent-Specific Behavior
| Intent | Micro Behavior |
|--------|---------------|
| Typing | Track caret position (ignore mouse) |
| Click/Navigate | Track mouse position |
| Scroll | Weak offset in scroll direction |
| Idle | Gradually return offset to 0 |
| Switching | Immediately reset offset |

### Macro Transition Handling
When macro target changes, compensate micro offset to avoid visual jump:
```
micro.offset -= (newMacroCenter - oldMacroCenter)
// Camera screen position unchanged
// Micro offset naturally decays to 0 -> smooth transition to new framing
```

## Cursor Rendering

### Camera-Space Smoothing
Smooth cursor in camera-relative coordinates (not world coordinates):
```
// Old: world-space smoothing
smoothedCursor = springStep(rawCursor)
screenPos = (smoothedCursor - camera.center) * camera.zoom

// New: camera-space smoothing
relativeCursor = rawCursor - camera.center
smoothedRelative = springStep(relativeCursor)
screenPos = smoothedRelative * camera.zoom
```

Prevents cursor "sliding" during camera pan.

### Updated Spring Parameters
```
dampingRatio: 0.90 (less overshoot)
response: 0.06s (slightly faster)
adaptiveMaxVelocity: 4.0
adaptiveMinScale: 0.4
```

### Idle Stabilization
When cursor velocity below threshold, blend target toward current position:
```
if cursorVelocity < idleThreshold:
    target = lerp(rawCursor, currentSmoothed, idleBlendFactor)
    idleBlendFactor = min(idleBlendFactor + dt * 3.0, 0.95)
else:
    idleBlendFactor = 0
```

## Implementation Phases

### Phase 1: Macro Layer Improvements (highest impact)
1. Unify zoom-pan response time (0.8s)
2. Remove detail waypoints from WaypointGenerator
3. Implement urgency blending (0.3s transition)
4. Implement soft clamping
5. Output format unchanged (TimedTransform[])

Verify: smooth breathing zoom, no jerk at intent transitions

### Phase 2: Micro Layer Addition
1. Implement MicroTracker (dead zone + offset spring)
2. Integrate in ContinuousCameraGenerator (macro + micro composition)
3. Macro transition offset compensation
4. Intent-specific micro behavior

Verify: smooth cursor following, no visual jump at macro transitions

### Phase 3: Cursor Rendering
1. Camera-space cursor smoothing
2. Spring parameter adjustment
3. Idle stabilization

Verify: no cursor sliding during pan, no jitter at rest

### Phase 4: Parameter Tuning
1. Fine-tune macro/micro spring parameters
2. Adjust dead zone size
3. Adjust offset limit ratio
4. Test with multiple real recordings

### Dependencies
```
Phase 1 -> Phase 2 -> Phase 3 -> Phase 4
```
Each phase delivers independent improvement.

## Files Affected

### Phase 1
- `Generators/ContinuousCamera/SpringDamperSimulator.swift` - soft clamping, unified response
- `Generators/ContinuousCamera/WaypointGenerator.swift` - remove detail waypoints, urgency blending
- `Generators/ContinuousCamera/ContinuousCameraTypes.swift` - parameter constants

### Phase 2
- `Generators/ContinuousCamera/MicroTracker.swift` (new) - dead zone + offset spring
- `Generators/ContinuousCamera/ContinuousCameraGenerator.swift` - orchestrate dual layers

### Phase 3
- `Render/MousePositionInterpolator.swift` - camera-space smoothing mode
- `Render/SpringCursorSimulator.swift` - parameter adjustment, idle stabilization
- `Render/FrameEvaluator+Cursor.swift` - pass camera transform to cursor evaluation
