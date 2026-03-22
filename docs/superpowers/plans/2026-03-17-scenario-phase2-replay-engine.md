# Scenario-Based Recording Phase 2: Replay Engine — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Replay Engine that auto-executes scenario steps via CGEvent injection while recording, plus Re-rehearse from Step N with mid-session Rehearsal transition.

**Architecture:** `ScenarioPlayer` (@MainActor, ObservableObject) orchestrates playback via `StepExecutor`, which delegates to `AXTargetResolver` (4-level fallback), `EventInjector` (CGEvent via DispatchSourceTimer), `PathGenerator` (deterministic Bezier + Catmull-Rom), and `TimingController` (ease-in-out). `ReplayHUD` (NSPanel) shows progress/errors. `RecordingBridge` connects to the existing `RecordingCoordinator`. Re-rehearse uses `activateScenarioRecorder()` for mid-session transition.

**Tech Stack:** Swift, SwiftUI, CGEvent API, Accessibility Framework, ScreenCaptureKit, DispatchSourceTimer, Combine

**Spec:** `docs/superpowers/specs/2026-03-16-scenario-based-recording-design.md` (Phase 2 section)

**CRITICAL — Xcode project file management:** Every task that creates new `.swift` files MUST also add them to `Screenize.xcodeproj/project.pbxproj` in the same commit. Each file requires 4 entries: PBXBuildFile, PBXFileReference, PBXGroup child, PBXSourcesBuildPhase entry. Check UUID prefix conflicts before adding.

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `Screenize/Replay/PathGenerator.swift` | Cubic Bezier (deterministic seed) + Catmull-Rom spline cursor path generation |
| `Screenize/Replay/EventInjector.swift` | CGEvent creation and injection via DispatchSourceTimer (10ms interval) |
| `Screenize/Replay/AXTargetResolver.swift` | 4-level fallback chain for finding AX elements |
| `Screenize/Replay/TimingController.swift` | Ease-in-out timing, step duration control |
| `Screenize/Replay/StateValidator.swift` | Pre-step validation (app running, element visible/enabled, dialog detection) |
| `Screenize/Replay/StepExecutor.swift` | Orchestrates target resolution → validation → path/event injection per step |
| `Screenize/Replay/ScenarioPlayer.swift` | Main controller: PlaybackState machine, step loop, Recording bridge |
| `Screenize/Replay/ReplayHUDPanel.swift` | NSPanel + SwiftUI view for Replay/Rehearsal HUD states |
| `Screenize/Replay/ReplayConfiguration.swift` | Capture settings snapshot for replay recording |
| `ScreenizeTests/Replay/PathGeneratorTests.swift` | Bezier/Catmull-Rom path tests |
| `ScreenizeTests/Replay/EventInjectorTests.swift` | Event creation tests (not injection — requires permissions) |
| `ScreenizeTests/Replay/AXTargetResolverTests.swift` | Fallback chain logic tests |
| `ScreenizeTests/Replay/TimingControllerTests.swift` | Ease-in-out curve + timing tests |

### Modified Files

| File | Change |
|------|--------|
| `Screenize/Core/Recording/RecordingCoordinator.swift` | Add `activateScenarioRecorder()` for mid-session Re-rehearse |
| `Screenize/Core/Capture/ScreenCaptureManager.swift` | Add `addExcludedWindow()` for dynamic HUD exclusion |
| `Screenize/App/AppState.swift` | Add `lastCaptureConfiguration`, `ReplayConfiguration` |
| `Screenize/ViewModels/EditorViewModel.swift` | Add ScenarioPlayer integration, replay/re-rehearse methods |
| `Screenize/Views/EditorMainView.swift` | Add Bottom Bar replay buttons, ReplayHUD lifecycle |

---

## Chunk 1: Core Replay Components (Pure Logic)

### Task 1: PathGenerator

**Files:**
- Create: `Screenize/Replay/PathGenerator.swift`
- Test: `ScreenizeTests/Replay/PathGeneratorTests.swift`

- [ ] **Step 1: Write tests for Cubic Bezier generation**

Test deterministic seed: same step.id → same path every time.
Test path starts at point A, ends at point B.
Test control points have perpendicular offset 2-8%.
Test with zero-distance (A == B) → returns single point.

- [ ] **Step 2: Write tests for Catmull-Rom spline**

Test: waypoints [A, B, C] → path passes through all three.
Test: single waypoint → path passes through it.
Test: empty waypoints → straight line from start to end.

- [ ] **Step 3: Write tests for ease-in-out timing**

Test: t=0.0 → 0.0, t=0.5 → 0.5, t=1.0 → 1.0.
Test: t=0.25 → less than 0.25 (slow start).
Test: t=0.75 → greater than 0.75 (slow end).

- [ ] **Step 4: Write tests for point sampling at 10ms intervals**

Test: 300ms duration → 30 points.
Test: 10ms duration → 1 point.
Test: ease-in-out applied to path parameter.

- [ ] **Step 5: Run tests — expect FAIL**

- [ ] **Step 6: Implement PathGenerator**

```swift
import Foundation

struct PathGenerator {
    /// Generate cursor path points for a mouse_move step.
    /// Returns array of CGPoints (CG coordinates) at 10ms intervals.
    static func generatePath(
        from start: CGPoint,
        to end: CGPoint,
        path: MousePath?,
        durationMs: Int,
        stepId: UUID
    ) -> [CGPoint]

    // MARK: - Cubic Bezier (path: .auto)
    // Seed from stepId.hashValue for deterministic randomness
    // Control points: perpendicular offset 2-8%

    // MARK: - Catmull-Rom Spline (path: .waypoints)
    // alpha = 0.5 (centripetal)
    // Interpolate through all waypoints

    // MARK: - Ease-in-out timing
    // easeInOut(t) = t < 0.5 ? 2t² : 1 - (-2t+2)²/2

    // MARK: - Point sampling
    // Sample path at 10ms intervals with ease-in-out parameter mapping
}
```

- [ ] **Step 7: Run tests — expect PASS**

- [ ] **Step 8: Add files to Xcode project, build, commit**

```
feat: Implement PathGenerator (deterministic Bezier + Catmull-Rom)
```

---

### Task 2: EventInjector

**Files:**
- Create: `Screenize/Replay/EventInjector.swift`
- Test: `ScreenizeTests/Replay/EventInjectorTests.swift`

- [ ] **Step 1: Write tests for CGEvent creation (not injection)**

Test: `createMouseMoveEvent(to:)` returns valid CGEvent with correct position.
Test: `createClickEvents(at:button:clickCount:)` returns [mouseDown, mouseUp] pair.
Test: `createKeyboardEvent(keyCode:modifiers:isDown:)` sets correct flags.
Test: `createScrollEvent(deltaX:deltaY:)` creates scroll wheel event.

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement EventInjector**

```swift
import Foundation
import CoreGraphics

final class EventInjector {
    private let injectionQueue = DispatchQueue(label: "com.screenize.eventInjector", qos: .userInteractive)
    private var pathTimer: DispatchSourceTimer?

    // MARK: - Event Creation (testable)
    static func createMouseMoveEvent(to point: CGPoint) -> CGEvent?
    static func createClickEvents(at point: CGPoint, button: CGMouseButton, clickCount: Int) -> [CGEvent]
    static func createRightClickEvents(at point: CGPoint) -> [CGEvent]
    static func createKeyboardEvent(keyCode: UInt16, modifiers: CGEventFlags, isDown: Bool) -> CGEvent?
    static func createScrollEvent(deltaX: Int32, deltaY: Int32) -> CGEvent?

    // MARK: - Event Injection
    func injectEvent(_ event: CGEvent)  // CGEventPost(.cghidEventTap, event)

    // MARK: - Path Injection (mouse_move)
    /// Inject a sequence of mouse move events at 10ms intervals via DispatchSourceTimer
    func injectPath(_ points: [CGPoint], completion: @escaping () -> Void)
    func cancelPathInjection()

    // MARK: - Step Injection (action steps)
    func injectClick(at point: CGPoint) async
    func injectDoubleClick(at point: CGPoint) async
    func injectRightClick(at point: CGPoint) async
    func injectMouseDown(at point: CGPoint) async
    func injectMouseUp(at point: CGPoint) async
    func injectKeyCombo(_ combo: String) async  // Parse "cmd+c" → modifier flags + key
    func injectTypeText(_ text: String, speedMs: Int) async
    func injectScroll(deltaX: Int, deltaY: Int) async
    func injectActivateApp(bundleId: String) async
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Add files to Xcode project, build, commit**

```
feat: Implement EventInjector (CGEvent creation + DispatchSourceTimer injection)
```

---

### Task 3: AXTargetResolver

**Files:**
- Create: `Screenize/Replay/AXTargetResolver.swift`
- Test: `ScreenizeTests/Replay/AXTargetResolverTests.swift`

- [ ] **Step 1: Write tests for fallback chain logic**

Test: `resolveStrategy(for:)` returns correct strategy order for targets with varying available fields.
Test: target with all fields → tries path+title first.
Test: target with no axTitle → skips title-based strategies.
Test: target with no path → skips path-based strategy.
Test: absoluteCoord-only target → falls back to coordinate.

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement AXTargetResolver**

```swift
import Foundation
import ApplicationServices

final class AXTargetResolver {
    private let resolverQueue = DispatchQueue(label: "com.screenize.axResolver", qos: .userInitiated)
    private static let timeoutPerStrategy: TimeInterval = 0.5  // 500ms

    enum ResolvedTarget {
        case element(AXUIElement, CGPoint)  // Found AX element + its screen position
        case coordinate(CGPoint)             // Fallback: raw coordinate only
    }

    /// Resolve target using 4-level fallback chain. Runs on background queue.
    func resolve(target: AXTarget, captureArea: CGRect) async -> ResolvedTarget?

    // MARK: - Strategies (private)
    // 1. AX path + axTitle
    // 2. axTitle only (BFS through AX tree, max depth 10)
    // 3. role + positionHint (AXUIElementCopyElementAtPosition + role check)
    // 4. absoluteCoord (direct coordinate)
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Add files to Xcode project, build, commit**

```
feat: Implement AXTargetResolver (4-level fallback chain)
```

---

### Task 4: TimingController + StateValidator

**Files:**
- Create: `Screenize/Replay/TimingController.swift`
- Create: `Screenize/Replay/StateValidator.swift`
- Test: `ScreenizeTests/Replay/TimingControllerTests.swift`

- [ ] **Step 1: Write tests for TimingController**

Test: `delay(ms:)` waits approximately the specified duration.
Test: isDragGroup detection (mouse_down → mouse_move → mouse_up sequence).
Test: drag group steps have zero inter-step delay.

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement TimingController**

```swift
struct TimingController {
    /// Wait for the specified duration
    static func delay(ms: Int) async

    /// Check if the current step is part of a drag group
    static func isDragGroupMember(step: ScenarioStep, steps: [ScenarioStep], index: Int) -> Bool

    /// Get inter-step delay (0 for drag group members)
    static func interStepDelay(currentStep: ScenarioStep, steps: [ScenarioStep], index: Int) -> Int
}
```

- [ ] **Step 4: Implement StateValidator**

```swift
final class StateValidator {
    /// Validate that the target app and element are ready for interaction
    func validate(step: ScenarioStep, resolvedTarget: AXTargetResolver.ResolvedTarget?) async -> ValidationResult

    enum ValidationResult {
        case ready
        case appNotRunning(bundleId: String)
        case elementNotEnabled
        case unexpectedDialog(role: String)
        case timeout
    }

    // Checks:
    // - NSRunningApplication exists and is not terminated
    // - kAXEnabledAttribute is true
    // - Focused window role is not AXSheet/AXDialog (unexpected dialog)
    // - Timeout: 5 seconds
}
```

- [ ] **Step 5: Run tests — expect PASS**

- [ ] **Step 6: Add files to Xcode project, build, commit**

```
feat: Implement TimingController and StateValidator
```

---

## Chunk 2: StepExecutor + ScenarioPlayer

### Task 5: StepExecutor

**Files:**
- Create: `Screenize/Replay/StepExecutor.swift`

- [ ] **Step 1: Implement StepExecutor**

```swift
final class StepExecutor {
    let targetResolver = AXTargetResolver()
    let eventInjector = EventInjector()
    let stateValidator = StateValidator()

    enum StepResult {
        case success
        case error(String)
        case cancelled
    }

    /// Execute a single scenario step
    func execute(
        step: ScenarioStep,
        previousPosition: CGPoint?,
        steps: [ScenarioStep],
        stepIndex: Int,
        captureArea: CGRect,
        isCancelled: @escaping () -> Bool
    ) async -> StepResult {
        // 1. Resolve target (if applicable)
        // 2. Validate state
        // 3. Execute:
        //    - mouse_move: PathGenerator → EventInjector.injectPath
        //    - click/double_click/right_click: move to target → inject click
        //    - keyboard: inject key combo
        //    - type_text: inject characters with speed delay
        //    - scroll: inject scroll event
        //    - activate_app: activate via NSWorkspace
        //    - mouse_down/mouse_up: inject mouse button
        //    - wait: just delay
        // 4. Inter-step delay (unless drag group)
    }

    func cancel() { eventInjector.cancelPathInjection() }
}
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Add to Xcode project, commit**

```
feat: Implement StepExecutor (orchestrates per-step execution)
```

---

### Task 6: ReplayConfiguration + RecordingCoordinator Extensions

**Files:**
- Create: `Screenize/Replay/ReplayConfiguration.swift`
- Modify: `Screenize/Core/Recording/RecordingCoordinator.swift`
- Modify: `Screenize/App/AppState.swift`

- [ ] **Step 1: Create ReplayConfiguration**

```swift
struct ReplayConfiguration {
    let captureTarget: CaptureTarget
    let backgroundStyle: BackgroundStyle
    let frameRate: Int
    let isSystemAudioEnabled: Bool
    let isMicrophoneEnabled: Bool
    let microphoneDevice: AVCaptureDevice?
}
```

- [ ] **Step 2: Add activateScenarioRecorder() to RecordingCoordinator**

```swift
/// Activate ScenarioEventRecorder mid-session (for Re-rehearse transition).
func activateScenarioRecorder() {
    guard scenarioEventRecorder == nil else { return }
    scenarioEventRecorder = ScenarioEventRecorder()
    scenarioEventRecorder?.startRecording(captureArea: captureBounds)
    isRehearsalMode = true
}
```

- [ ] **Step 3: Add lastCaptureConfiguration to AppState**

Store the capture configuration after each recording so Replay can reuse it:
```swift
var lastCaptureConfiguration: ReplayConfiguration?
```
Set this in `startRecording()` before launching the coordinator.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Add new file to Xcode project, commit**

```
feat: Add ReplayConfiguration and mid-session ScenarioEventRecorder activation
```

---

### Task 7: ScenarioPlayer (Main Controller)

**Files:**
- Create: `Screenize/Replay/ScenarioPlayer.swift`

- [ ] **Step 1: Implement ScenarioPlayer**

```swift
@MainActor
final class ScenarioPlayer: ObservableObject {
    @Published var state: PlaybackState = .idle
    @Published var currentStepIndex: Int = 0
    @Published var currentStepDescription: String = ""

    private var scenario: Scenario?
    private var mode: PlaybackMode = .replayAll
    private let stepExecutor = StepExecutor()
    private var isCancelled = false

    // Playback
    func start(scenario: Scenario, mode: PlaybackMode, config: ReplayConfiguration) async
    func stop() async
    func skip()          // Skip current step on error
    func doManually()    // Enter manual mode on error
    func continueAfterManual()  // Resume after manual step
    func startRehearsal()       // Re-rehearse: user pressed Start

    // State machine
    private func executeStepLoop() async
    private func handleError(stepIndex: Int, message: String) async
    private func transitionToRehearsal() async  // Start countdown → rehearsal

    // Recording bridge
    private func startRecording(config: ReplayConfiguration) async throws
    private func stopRecording() async -> URL?
    private func activateScenarioRecorder()  // Mid-session for Re-rehearse

    // Scenario merge (Re-rehearse)
    private func mergeScenarios(
        original: Scenario,
        newRawEvents: ScenarioRawEvents,
        splitAtIndex: Int,
        replayDurationMs: Int
    ) -> Scenario
}
```

Key state transitions:
```
idle → [start()] → playing
playing → [step error] → error
playing → [ESC/stop()] → completed
playing → [replayUntilStep reached] → waitingForUser
error → [skip()] → playing (next step)
error → [doManually()] → paused(.doManually)
error → [stop()] → completed
paused(.doManually) → [continueAfterManual()] → playing
waitingForUser → [startRehearsal()] → countdown(3) → countdown(2) → countdown(1) → rehearsing
rehearsing → [stop()] → completed
```

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Add to Xcode project, commit**

```
feat: Implement ScenarioPlayer (playback state machine + recording bridge)
```

---

## Chunk 3: Replay HUD + UI Integration

### Task 8: ReplayHUD Panel

**Files:**
- Create: `Screenize/Replay/ReplayHUDPanel.swift`

- [ ] **Step 1: Implement ReplayHUDPanel (NSPanel + SwiftUI)**

Follow the CaptureToolbarPanel pattern:

```swift
// NSPanel subclass
final class ReplayHUDPanel: NSPanel {
    init(player: ScenarioPlayer) // Create panel with SwiftUI content
    func show()
    func dismiss()
}

// SwiftUI content
struct ReplayHUDView: View {
    @ObservedObject var player: ScenarioPlayer

    var body: some View {
        // Switch on player.state:
        // .playing → "▶ Replaying  Step N/M  description  [■ Stop]"
        // .error → "⚠ Step N failed: message  [Skip] [Do Manually] [Stop]"
        // .paused(.doManually) → "✋ Manual mode — Step N  [Continue] [Stop]"
        // .waitingForUser → "📋 Your turn — Step N description  [▶ Start] [■ Stop]"
        // .countdown(n) → "n..." (large text)
        // .rehearsing → "📋 Rehearsing  ◉ duration  [■ Stop]"
    }
}
```

NSPanel configuration:
- `styleMask: [.borderless, .nonactivatingPanel]`
- `level: .floating`
- `isOpaque: false`, `backgroundColor: .clear`
- Positioned: top center of screen, offset 60pt from top
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]`

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Add to Xcode project, commit**

```
feat: Implement ReplayHUD panel with state-dependent content
```

---

### Task 9: ScreenCaptureManager Dynamic Window Exclusion

**Files:**
- Modify: `Screenize/Core/Capture/ScreenCaptureManager.swift`

- [ ] **Step 1: Add addExcludedWindow method**

```swift
/// Dynamically exclude a window from capture (macOS 14+).
/// For display capture mode: updates SCContentFilter via SCStream.updateContentFilter.
/// For window capture mode: no-op (only target window is captured).
@available(macOS 14.0, *)
func addExcludedWindow(_ window: NSWindow) async throws {
    // Get window ID from NSWindow
    // Rebuild SCContentFilter with the additional excluded window
    // Call stream.updateContentFilter()
}
```

Note: The current code already excludes the Screenize app via `excludingApplications`. Since ReplayHUD is owned by Screenize process, it's already excluded in display capture mode. This method is a safety net for edge cases.

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```
feat: Add dynamic window exclusion to ScreenCaptureManager
```

---

### Task 10: EditorViewModel + EditorMainView Integration

**Files:**
- Modify: `Screenize/ViewModels/EditorViewModel.swift`
- Modify: `Screenize/Views/EditorMainView.swift`

- [ ] **Step 1: Add ScenarioPlayer to EditorViewModel**

```swift
@Published var scenarioPlayer: ScenarioPlayer?
@Published var isReplaying: Bool = false

func startReplay() async {
    guard let scenario, let config = appState?.lastCaptureConfiguration else { return }
    let player = ScenarioPlayer()
    self.scenarioPlayer = player
    self.isReplaying = true
    await player.start(scenario: scenario, mode: .replayAll, config: config)
    // After completion: load new project if video was created
    self.isReplaying = false
}

func startReRehearse() async {
    guard let scenario, let config = appState?.lastCaptureConfiguration,
          let selectedId = selectedStepId,
          let stepIndex = scenario.steps.firstIndex(where: { $0.id == selectedId }) else { return }
    let player = ScenarioPlayer()
    self.scenarioPlayer = player
    self.isReplaying = true
    await player.start(scenario: scenario, mode: .replayUntilStep(stepIndex), config: config)
    self.isReplaying = false
}
```

- [ ] **Step 2: Add Bottom Bar buttons to EditorMainView**

Add two buttons to the editor toolbar:
- **[▶ Replay & Record]**: enabled when `scenario != nil`, calls `viewModel.startReplay()`
- **[🔄 Re-rehearse from here]**: enabled when `selectedStepId != nil`, calls `viewModel.startReRehearse()`

Both show confirmation dialog before starting.

- [ ] **Step 3: Add ReplayHUD lifecycle to EditorMainView**

When `viewModel.isReplaying` becomes true, create and show `ReplayHUDPanel`. When false, dismiss it.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```
feat: Integrate ScenarioPlayer into editor with Replay & Re-rehearse buttons
```

---

## Chunk 4: End-to-End Flow + Polish

### Task 11: Post-Replay Project Creation

**Files:**
- Modify: `Screenize/Replay/ScenarioPlayer.swift`
- Modify: `Screenize/ViewModels/EditorViewModel.swift`

- [ ] **Step 1: Wire post-replay flow**

After ScenarioPlayer completes (state = .completed):
1. Get video URL from RecordingCoordinator
2. Create new .screenize package with scenario files
3. If Re-rehearse: merge scenarios (original steps[0..<N] + new generated steps, with timing offset)
4. Open new project in editor

- [ ] **Step 2: Implement scenario merging with timing offset**

```swift
func mergeScenarios(
    original: Scenario,
    newRawEvents: ScenarioRawEvents,
    splitAtIndex: Int,
    replayDurationMs: Int
) -> Scenario {
    let keptSteps = Array(original.steps[0..<splitAtIndex])
    var newScenario = ScenarioGenerator.generate(from: newRawEvents)
    // Offset new steps' rawTimeRange by replayDurationMs
    for i in 0..<newScenario.steps.count {
        if var range = newScenario.steps[i].rawTimeRange {
            newScenario.steps[i].rawTimeRange = TimeRange(
                startMs: range.startMs + replayDurationMs,
                endMs: range.endMs + replayDurationMs
            )
        }
    }
    return Scenario(
        version: original.version,
        appContext: original.appContext,
        steps: keptSteps + newScenario.steps
    )
}
```

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```
feat: Add post-replay project creation and scenario merging
```

---

### Task 12: Confirmation Dialogs

**Files:**
- Modify: `Screenize/Views/EditorMainView.swift`

- [ ] **Step 1: Add confirmation dialogs**

Before Replay & Record:
```
"시나리오를 자동 실행하며 새 영상을 녹화합니다.
 실행 중 ESC를 누르면 즉시 중단됩니다."
[Cancel]  [Start]
```

Before Re-rehearse:
```
"Step N부터 다시 리허설합니다.
 Step 1~(N-1)은 자동 재생되며, Step N부터 직접 조작합니다."
[Cancel]  [Start]
```

Use SwiftUI `.alert()` modifier.

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```
feat: Add confirmation dialogs for Replay and Re-rehearse
```

---

### Task 13: Lint & Build Verification

- [ ] **Step 1: Run linter**

Run: `./scripts/lint.sh`

- [ ] **Step 2: Run full build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`

- [ ] **Step 3: Run tests**

Run: `xcodebuild -project Screenize.xcodeproj -scheme ScreenizeTests -configuration Debug test`

Verify all new Replay tests pass.

- [ ] **Step 4: Fix any issues, final commit**

```
chore: Fix lint violations and verify clean build
```

---

## Task Dependency Graph

```
Tasks 1, 2, 3, 4 (PathGenerator, EventInjector, AXTargetResolver, TimingController+StateValidator)
  — can run in parallel, no dependencies
       │
       ▼
Task 5 (StepExecutor) — depends on Tasks 1-4
       │
       ▼
Task 6 (ReplayConfiguration + RecordingCoordinator) — no deps on above, can parallel with 5
       │
       ▼
Task 7 (ScenarioPlayer) — depends on Tasks 5, 6
       │
       ▼
Tasks 8, 9 (ReplayHUD, ScreenCaptureManager) — can parallel, depend on Task 7
       │
       ▼
Task 10 (Editor Integration) — depends on Tasks 7, 8
       │
       ▼
Task 11 (Post-Replay Flow) — depends on Task 10
       │
       ▼
Task 12 (Confirmation Dialogs) — depends on Task 10
       │
       ▼
Task 13 (Lint & Build) — last
```

**Parallelizable groups:**
- Tasks 1, 2, 3, 4 (all independent pure logic)
- Tasks 5, 6 (can overlap)
- Tasks 8, 9 (can overlap)
- Tasks 11, 12 (can overlap)
