# Transparent Background Fallback Design

**Date:** 2026-03-11

**Goal:** Replace the current white fallback shown for transparent window backgrounds with a dark gray fallback, and apply the same policy consistently across preview and rendering fallbacks.

## Context

Screenize renders window-mode captures on top of a generated background. When the window background is effectively transparent, the current code falls back to white in multiple places:

- Preview rendering uses a white solid background when window background rendering is disabled.
- Window effect fallback paths return white `CIImage` instances when mask generation cannot produce a valid image.

These independent white defaults create an inconsistent policy and make later tuning harder.

## Scope

In scope:

- Define a single dark gray fallback color policy for transparent background rendering.
- Reuse that policy in preview background fallback and window effect fallback paths.
- Keep user-selected background styles unchanged.

Out of scope:

- Adding a new inspector setting or user-facing preference for the fallback color.
- Changing project serialization or `RenderSettings` data model.
- Refactoring unrelated background rendering behavior.

## Recommended Approach

Introduce one shared fallback color constant in the render layer and route all transparent-background fallback behavior through it.

This keeps the change small while removing duplicated policy decisions. The render pipeline still behaves the same structurally; only the fallback visual output changes from white to dark gray.

## Design

### 1. Shared Fallback Policy

Create a single render-level fallback color definition for transparent backgrounds.

Requirements:

- The fallback must be dark gray.
- The value must be reusable from both SwiftUI/`Color` and Core Image code paths.
- The symbol name should describe policy, not implementation detail, so future tuning is localized.

### 2. Preview Background Handling

Update window-mode preview rendering so that when `backgroundEnabled == false`, the generated preview background uses the shared dark gray fallback instead of white.

Behavioral rule:

- If the user explicitly chose a background style, continue using it.
- If rendering needs a transparent fallback surface, use the shared dark gray policy.

### 3. Window Effect Fallback Handling

Update rounded-mask fallback paths in `WindowEffectApplicator` so invalid sizes or mask-generation failure no longer return white images. They should return the same dark gray fallback used elsewhere.

Behavioral rule:

- Normal successful mask generation remains unchanged.
- Only fallback outputs change color.

## File Impact

Primary files:

- `Screenize/Render/WindowModeRenderer.swift`
- `Screenize/Render/WindowEffectApplicator.swift`

Possible support location:

- Shared render helper or local render-level constant file if that is cleaner than duplicating conversion code.

## Risks

- The chosen dark gray becomes the de facto product default for transparent fallback surfaces, so the constant should be named and placed intentionally.
- If fallback creation mixes `Color`, `NSColor`, and `CIColor` inconsistently, future maintenance may drift again.

## Verification

Manual verification:

- In preview, disable background rendering and confirm the area behind the captured window shows dark gray instead of white.
- Confirm user-selected solid, gradient, and image backgrounds still render unchanged.
- Confirm rounded-corner or mask fallback paths do not flash white.

Code verification:

- Build: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`
- Lint: `./scripts/lint.sh`

## Acceptance Criteria

- No transparent-background fallback path renders white anymore.
- Preview and effect fallback paths use the same dark gray policy.
- Existing background customization behavior remains unchanged.
