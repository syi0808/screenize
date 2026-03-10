# Transparent Background Fallback Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every white transparent-background fallback in window rendering with one shared dark gray fallback policy.

**Architecture:** Introduce a small render-scoped fallback helper that owns the dark gray policy in one place, then route both preview background selection and window-effect fallback image creation through that helper. Keep the change isolated to render code so project data, inspector state, and user-selected background styles remain unchanged.

**Tech Stack:** Swift, SwiftUI `Color`, AppKit `NSColor`, CoreImage `CIColor`/`CIImage`, XCTest, Xcode

---

## File Structure

- Create: `Screenize/Render/TransparentBackgroundFallback.swift`
  Responsibility: Define the shared dark gray fallback once and expose conversions needed by renderer code (`Color`, `CIColor`, and cropped `CIImage`).
- Modify: `Screenize/Render/WindowModeRenderer.swift`
  Responsibility: Replace the preview-only white fallback branch with the shared dark gray fallback style.
- Modify: `Screenize/Render/WindowEffectApplicator.swift`
  Responsibility: Replace white rounded-mask fallback images with the shared dark gray fallback image helper.
- Create: `ScreenizeTests/Render/TransparentBackgroundFallbackTests.swift`
  Responsibility: Lock the fallback color policy and image-generation behavior with focused unit tests.
- Modify: `docs/superpowers/plans/2026-03-11-transparent-background-fallback-plan.md`
  Responsibility: Check off completed steps during execution.

## Spec Reference

- `docs/superpowers/specs/2026-03-11-transparent-background-fallback-design.md`

## Chunk 1: Shared Fallback Policy

### Task 1: Add a reusable render fallback helper

**Files:**
- Create: `Screenize/Render/TransparentBackgroundFallback.swift`
- Test: `ScreenizeTests/Render/TransparentBackgroundFallbackTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
import CoreImage
@testable import Screenize

final class TransparentBackgroundFallbackTests: XCTestCase {
    func test_swiftUIColor_isDarkGray() {
        let nsColor = NSColor(TransparentBackgroundFallback.swiftUIColor)
        let ciColor = CIColor(color: nsColor)

        XCTAssertNotNil(ciColor)
        XCTAssertEqual(ciColor?.red, 0.16, accuracy: 0.02)
        XCTAssertEqual(ciColor?.green, 0.16, accuracy: 0.02)
        XCTAssertEqual(ciColor?.blue, 0.16, accuracy: 0.02)
        XCTAssertEqual(ciColor?.alpha, 1.0, accuracy: 0.001)
    }

    func test_image_cropsToRequestedSize() {
        let image = TransparentBackgroundFallback.image(size: CGSize(width: 320, height: 180))
        XCTAssertEqual(image.extent, CGRect(x: 0, y: 0, width: 320, height: 180))
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run:

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/TransparentBackgroundFallbackTests test
```

Expected: FAIL because `TransparentBackgroundFallback` does not exist yet.

- [ ] **Step 3: Implement the minimal helper**

```swift
import SwiftUI
import AppKit
import CoreImage

enum TransparentBackgroundFallback {
    static let swiftUIColor = Color(nsColor: NSColor(calibratedWhite: 0.16, alpha: 1.0))

    static var ciColor: CIColor {
        CIColor(color: NSColor(swiftUIColor))!
    }

    static func image(size: CGSize) -> CIImage {
        CIImage(color: ciColor).cropped(to: CGRect(origin: .zero, size: size))
    }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run:

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/TransparentBackgroundFallbackTests test
```

Expected: PASS for both new tests.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Render/TransparentBackgroundFallback.swift ScreenizeTests/Render/TransparentBackgroundFallbackTests.swift docs/superpowers/plans/2026-03-11-transparent-background-fallback-plan.md
git commit -m "feat: add shared transparent background fallback"
```

## Chunk 2: Wire Renderers to the Shared Policy

### Task 2: Replace preview white fallback in `WindowModeRenderer`

**Files:**
- Modify: `Screenize/Render/WindowModeRenderer.swift`
- Test: `ScreenizeTests/Render/TransparentBackgroundFallbackTests.swift`

- [ ] **Step 1: Add a failing test for preview fallback style selection**

```swift
func test_previewFallbackStyle_usesSharedDarkGrayWhenBackgroundDisabled() {
    let style = WindowModeRenderer.previewBackgroundStyle(
        backgroundEnabled: false,
        configuredStyle: .gradient(.defaultGradient),
        isPreview: true
    )

    XCTAssertEqual(style, .solid(TransparentBackgroundFallback.swiftUIColor))
}
```

Implementation note:

- Add an `internal static func previewBackgroundStyle(backgroundEnabled:configuredStyle:isPreview:) -> BackgroundStyle` so the selection policy is testable without pixel-inspecting rendered frames.

- [ ] **Step 2: Run the targeted tests to confirm failure**

Run:

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/TransparentBackgroundFallbackTests test
```

Expected: FAIL because the new selector helper does not exist and preview fallback still points at white.

- [ ] **Step 3: Implement the selector and replace the inline branch**

```swift
static func previewBackgroundStyle(
    backgroundEnabled: Bool,
    configuredStyle: BackgroundStyle,
    isPreview: Bool
) -> BackgroundStyle {
    guard !backgroundEnabled else { return configuredStyle }
    return .solid(isPreview ? TransparentBackgroundFallback.swiftUIColor : .clear)
}
```

Then replace:

```swift
let backgroundStyle: BackgroundStyle = settings.backgroundEnabled
    ? settings.backgroundStyle
    : .solid(isPreview ? .white : .clear)
```

with:

```swift
let backgroundStyle = Self.previewBackgroundStyle(
    backgroundEnabled: settings.backgroundEnabled,
    configuredStyle: settings.backgroundStyle,
    isPreview: isPreview
)
```

- [ ] **Step 4: Re-run the targeted tests**

Run:

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/TransparentBackgroundFallbackTests test
```

Expected: PASS for the preview selector test and the helper tests.

### Task 3: Replace window-effect white fallbacks

**Files:**
- Modify: `Screenize/Render/WindowEffectApplicator.swift`
- Test: `ScreenizeTests/Render/TransparentBackgroundFallbackTests.swift`

- [ ] **Step 1: Add failing tests for effect fallback image creation**

```swift
func test_maskFallbackImage_zeroSize_returnsSharedFallbackImage() {
    let image = WindowEffectApplicator.maskFallbackImage(size: .zero)
    XCTAssertEqual(image.extent, .zero)
}

func test_maskFallbackImage_nonZeroSize_matchesSharedFallbackExtent() {
    let size = CGSize(width: 200, height: 120)
    let image = WindowEffectApplicator.maskFallbackImage(size: size)
    XCTAssertEqual(image.extent, CGRect(origin: .zero, size: size))
}
```

Implementation note:

- Extract an `internal static func maskFallbackImage(size: CGSize) -> CIImage` from the current white fallback branches so tests can verify the fallback path directly.

- [ ] **Step 2: Run the targeted tests to confirm failure**

Run:

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/TransparentBackgroundFallbackTests test
```

Expected: FAIL because `maskFallbackImage` does not exist yet.

- [ ] **Step 3: Implement the helper and route all white fallback branches through it**

```swift
static func maskFallbackImage(size: CGSize) -> CIImage {
    TransparentBackgroundFallback.image(size: size)
}
```

Then replace these branches:

- `return CIImage.white`
- `return CIImage.white.cropped(to: CGRect(origin: .zero, size: size))`

with:

```swift
return Self.maskFallbackImage(size: size)
```

Also remove the private `CIImage.white` helper if it is no longer used.

- [ ] **Step 4: Re-run the targeted tests**

Run:

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/TransparentBackgroundFallbackTests test
```

Expected: PASS for all fallback policy tests.

- [ ] **Step 5: Commit**

```bash
git add Screenize/Render/TransparentBackgroundFallback.swift Screenize/Render/WindowModeRenderer.swift Screenize/Render/WindowEffectApplicator.swift ScreenizeTests/Render/TransparentBackgroundFallbackTests.swift docs/superpowers/plans/2026-03-11-transparent-background-fallback-plan.md
git commit -m "fix: unify transparent background fallback color"
```

## Chunk 3: Verification

### Task 4: Run repository verification and smoke checks

**Files:**
- Modify: `docs/superpowers/plans/2026-03-11-transparent-background-fallback-plan.md`

- [ ] **Step 1: Run the focused fallback tests**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/TransparentBackgroundFallbackTests test
```

Expected: PASS.

- [ ] **Step 2: Run the full unit test suite**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' test
```

Expected: PASS for `ScreenizeTests`.

- [ ] **Step 3: Run the debug build**

```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Run lint**

```bash
./scripts/lint.sh
```

Expected: no lint violations.

- [ ] **Step 5: Manual smoke-check in the app**

Checklist:

- Open a window-mode recording in preview with background disabled and confirm dark gray appears behind the window.
- Toggle through solid, gradient, and image backgrounds and confirm their rendering is unchanged.
- Scrub frames with rounded corners and confirm there is no white flash on fallback edges.

- [ ] **Step 6: Commit final verification bookkeeping if the plan file changed**

```bash
git add docs/superpowers/plans/2026-03-11-transparent-background-fallback-plan.md
git commit -m "docs: mark transparent fallback plan complete"
```
