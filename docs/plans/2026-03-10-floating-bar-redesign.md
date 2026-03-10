# Recording Floating Bar Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify recording floating bars into a single `CaptureToolbarPanel` with consistent macOS-native visual style (`.ultraThinMaterial`, rounded corners, subtle border/shadow) and new recording controls (restart, delete).

**Architecture:** Remove `RecordingFloatingPanel` entirely. Route all recording paths through `CaptureToolbarCoordinator` / `CaptureToolbarPanel`. Update visual style tokens and apply new design to both selection and recording phases. Add drag-to-reposition and bottom-center default positioning.

**Tech Stack:** SwiftUI, AppKit (NSPanel), existing DesignSystem tokens

---

### Task 1: Update Design Tokens

**Files:**
- Modify: `Screenize/DesignSystem/CornerRadius.swift`
- Modify: `Screenize/DesignSystem/DesignOpacity.swift`

**Step 1: Add new CornerRadius token**

`CornerRadius.swift` — change `xxl` from 12pt to 16pt (floating bar new radius) and add `xxxl` for larger containers that previously used 12pt:

```swift
/// 10pt — Floating panels, recording control bar
static let xl: CGFloat = 10

/// 16pt — Floating toolbar, capture bar
static let xxl: CGFloat = 16

/// 12pt — Drop zones, permission list, large containers
static let xxxl: CGFloat = 12
```

Wait — this reorders semantics. Simpler approach: just update `xxl` to 16 and audit existing usages of `xxl` (12pt) to see if anything breaks.

Actually, cleanest approach: add a dedicated token.

```swift
/// 12pt — Drop zones, permission list, large containers
static let xxl: CGFloat = 12

/// 16pt — Floating toolbar
static let toolbar: CGFloat = 16
```

**Step 2: Add new DesignOpacity token**

`DesignOpacity.swift` — add `whisper` at the top of the enum:

```swift
/// 0.08 — Barely visible borders, ultra-subtle shadows
static let whisper: Double = 0.08
```

**Step 3: Verify build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: add toolbar corner radius and whisper opacity design tokens
```

---

### Task 2: Update Visual Style of CaptureToolbarPanel

**Files:**
- Modify: `Screenize/Views/Recording/CaptureToolbarPanel.swift`

**Step 1: Update `toolbarBackground` in `CaptureToolbarView`**

Replace the current `toolbarBackground` (lines 215-225):

```swift
private var toolbarBackground: some View {
    RoundedRectangle(cornerRadius: CornerRadius.toolbar, style: .continuous)
        .fill(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.toolbar, style: .continuous)
                .strokeBorder(Color.white.opacity(DesignOpacity.whisper), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(DesignOpacity.whisper), radius: 8, y: 3)
}
```

Changes:
- `.ultraThickMaterial` → `.ultraThinMaterial`
- corner radius `14` → `CornerRadius.toolbar` (16pt)
- border opacity `0.15` → `DesignOpacity.whisper` (0.08)
- dual shadow → single shadow with `DesignOpacity.whisper`

**Step 2: Update selection phase spacing to use design tokens**

Replace hardcoded padding in `selectingContent` (lines 158-159):

```swift
.padding(.horizontal, Spacing.md)  // was 12
.padding(.vertical, Spacing.sm)    // was 8
```

These happen to be the same values but now use tokens instead of magic numbers.

**Step 3: Update recording phase spacing to use design tokens**

Replace hardcoded padding in `recordingContent` (lines 207-208):

```swift
.padding(.horizontal, Spacing.md)  // was 14
.padding(.vertical, Spacing.sm)    // was 8
```

Note: 14 → 12 (Spacing.md). This tightens horizontal padding slightly for consistency with selection phase.

**Step 4: Verify build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```
feat: apply new visual style to CaptureToolbarPanel
```

---

### Task 3: Change Default Position to Bottom Center

**Files:**
- Modify: `Screenize/Views/Recording/CaptureToolbarPanel.swift`

**Step 1: Update `positionOnScreen()` method**

Replace lines 52-64 in `CaptureToolbarPanel`:

```swift
private func positionOnScreen() {
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    guard let screen else { return }

    let screenFrame = screen.visibleFrame
    let panelSize = self.frame.size
    let origin = NSPoint(
        x: screenFrame.midX - panelSize.width / 2,
        y: screenFrame.minY + 60
    )
    self.setFrameOrigin(origin)
}
```

Change: `screenFrame.minY + 80` → `screenFrame.minY + 60` (bottom center, 60pt from bottom of visible frame). `minY` in macOS coordinates is the bottom, so this already places it at the bottom. Just change the offset from 80 to 60.

**Step 2: Verify build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat: position capture toolbar at bottom center of screen
```

---

### Task 4: Add Drag-to-Reposition Support

**Files:**
- Modify: `Screenize/Views/Recording/CaptureToolbarPanel.swift`

**Step 1: Verify existing drag support**

Check `configurePanel()` — it already has `self.isMovableByWindowBackground = true` (line 41). This means the NSPanel is already draggable by clicking and dragging its background.

However, the SwiftUI content fills the panel, so we need to verify that mouse events pass through for dragging. Since `.isMovableByWindowBackground = true` is set on the NSPanel, and the panel is borderless, AppKit handles window dragging automatically when the user drags on non-interactive areas.

**Step 2: Add screen bounds constraint**

Override `setFrameOrigin` or add a drag-end handler to constrain panel within screen bounds. Add to `CaptureToolbarPanel` class:

```swift
override func setFrameOrigin(_ point: NSPoint) {
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(
        NSPoint(x: point.x + frame.width / 2, y: point.y + frame.height / 2)
    ) }) ?? NSScreen.main else {
        super.setFrameOrigin(point)
        return
    }

    let screenFrame = screen.visibleFrame
    let constrained = NSPoint(
        x: min(max(point.x, screenFrame.minX), screenFrame.maxX - frame.width),
        y: min(max(point.y, screenFrame.minY), screenFrame.maxY - frame.height)
    )
    super.setFrameOrigin(constrained)
}
```

**Step 3: Verify build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: constrain floating toolbar drag to screen bounds
```

---

### Task 5: Add Restart and Delete Buttons to Recording Phase

**Files:**
- Modify: `Screenize/Views/Recording/CaptureToolbarPanel.swift`
- Modify: `Screenize/App/CaptureToolbarCoordinator.swift`
- Modify: `Screenize/App/AppState.swift`

**Step 1: Add restart and delete methods to CaptureToolbarCoordinator**

Add to `CaptureToolbarCoordinator` after `stopRecording()`:

```swift
/// Restart: stop current recording, discard, and start a new one
func restartRecording() {
    Task {
        guard let appState else { return }
        // Stop current recording and discard
        _ = await appState.recording.stopRecording()
        // Reset state
        isPaused = false
        recordingDuration = 0
        // Start new recording
        await appState.startRecording()
    }
}

/// Delete: stop current recording and discard without saving
func deleteRecording() {
    Task {
        guard let appState else { return }
        // Stop recording and discard the result
        _ = await appState.recording.stopRecording()
        // Clean up and dismiss
        toolbarPanel?.dismiss()
        toolbarPanel = nil
        appState.captureToolbarDidDismiss()
    }
}
```

**Step 2: Add restart and delete buttons to `recordingContent`**

Replace `recordingContent` in `CaptureToolbarView`:

```swift
private var recordingContent: some View {
    HStack(spacing: Spacing.sm) {
        RecordingDot()

        Text(formattedDuration)
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundColor(.white)

        if coordinator.isPaused {
            Text("PAUSED")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.yellow)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Color.yellow.opacity(0.15))
                )
        }

        Spacer(minLength: Spacing.sm)

        // Restart
        ToolbarIconButton(
            icon: "arrow.counterclockwise",
            tooltip: "Restart Recording",
            action: coordinator.restartRecording
        )

        // Pause/Resume
        ToolbarIconButton(
            icon: coordinator.isPaused ? "play.fill" : "pause.fill",
            tooltip: coordinator.isPaused ? "Resume" : "Pause",
            action: coordinator.togglePause
        )

        // Delete
        ToolbarIconButton(
            icon: "trash",
            tooltip: "Delete Recording",
            action: coordinator.deleteRecording
        )

        // Stop — distinctive red square
        Button {
            coordinator.stopRecording()
        } label: {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Stop Recording")
    }
    .padding(.horizontal, Spacing.md)
    .padding(.vertical, Spacing.sm)
    .frame(minWidth: 260)
    .background(toolbarBackground)
}
```

Changes: added restart + delete buttons, `minWidth` 220→260 to fit new buttons, spacing uses `Spacing.sm`.

**Step 3: Verify build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: add restart and delete buttons to recording toolbar
```

---

### Task 6: Remove RecordingFloatingPanel and Unify Paths

**Files:**
- Delete: `Screenize/Views/Recording/RecordingFloatingPanel.swift`
- Modify: `Screenize/App/RecordingState.swift`
- Modify: `Screenize/App/AppState.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj`

**Step 1: Remove floating panel code from RecordingState**

In `RecordingState.swift`, remove:
- Line 34: `private var recordingFloatingPanel: RecordingFloatingPanel?`
- Lines 111-122: The entire `// MARK: - Recording Floating Panel` section (`showRecordingFloatingPanel` and `hideRecordingFloatingPanel` methods)

**Step 2: Update AppState.startRecording()**

In `AppState.swift`, remove the fallback panel logic in `startRecording()` (lines 222-225):

```swift
// REMOVE these lines:
// Only show standalone panel when capture toolbar is not managing the UI
if !showCaptureToolbar {
    recording.showRecordingFloatingPanel(appState: self)
}
```

Replace `startRecording()` so that when `!showCaptureToolbar`, it automatically routes through the capture toolbar flow:

```swift
func startRecording() async {
    guard #available(macOS 15.0, *) else {
        errorMessage = "Recording requires macOS 15.0 or later"
        return
    }

    do {
        try await recording.startRecording(appState: self)
    } catch {
        errorMessage = "Failed to start recording: \(error.localizedDescription)"
    }
}
```

**Step 3: Update AppState.stopRecording()**

Remove the fallback panel hiding in `stopRecording()` (lines 234-237):

```swift
// REMOVE these lines:
if !showCaptureToolbar {
    recording.hideRecordingFloatingPanel()
}
```

Resulting `stopRecording()`:

```swift
func stopRecording() async {
    guard #available(macOS 15.0, *) else { return }

    if let videoURL = await recording.stopRecording() {
        showEditor = true
        _ = videoURL
    } else {
        errorMessage = "Failed to stop recording"
    }

    showMainWindow()
}
```

**Step 4: Update toggleRecording()**

The `else` branch (line 263) already calls `showCaptureToolbarFlow()`, which is correct — all recording now goes through the capture toolbar.

**Step 5: Delete RecordingFloatingPanel.swift**

```bash
rm Screenize/Views/Recording/RecordingFloatingPanel.swift
```

**Step 6: Remove from Xcode project file**

In `Screenize.xcodeproj/project.pbxproj`, remove these 4 lines:
- `F00000F4296A0001 /* RecordingFloatingPanel.swift in Sources */` (PBXBuildFile, line ~171)
- `F10000F4296A0001 /* RecordingFloatingPanel.swift */` (PBXFileReference, line ~373)
- `F10000F4296A0001 /* RecordingFloatingPanel.swift */,` (PBXGroup children, line ~936)
- `F00000F4296A0001 /* RecordingFloatingPanel.swift in Sources */,` (PBXSourcesBuildPhase, line ~1181)

**Step 7: Verify build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 8: Commit**

```
refactor: remove RecordingFloatingPanel, unify to CaptureToolbarPanel
```

---

### Task 7: Lint Check and Final Verification

**Files:** All modified files

**Step 1: Run linter**

Run: `./scripts/lint.sh`
Expected: No new violations in modified files

**Step 2: Fix any lint violations**

Address any new warnings (line length, etc.) in the files we touched.

**Step 3: Final build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit (if lint fixes needed)**

```
fix: address lint violations from floating bar redesign
```

---

## Summary of All Changes

| File | Action | Description |
|------|--------|-------------|
| `CornerRadius.swift` | Modify | Add `toolbar: 16` token |
| `DesignOpacity.swift` | Modify | Add `whisper: 0.08` token |
| `CaptureToolbarPanel.swift` | Modify | New visual style, bottom position, screen bounds constraint, restart/delete buttons |
| `CaptureToolbarCoordinator.swift` | Modify | Add `restartRecording()`, `deleteRecording()` |
| `AppState.swift` | Modify | Remove fallback panel logic |
| `RecordingState.swift` | Modify | Remove floating panel methods and property |
| `RecordingFloatingPanel.swift` | Delete | No longer needed |
| `project.pbxproj` | Modify | Remove RecordingFloatingPanel references |
