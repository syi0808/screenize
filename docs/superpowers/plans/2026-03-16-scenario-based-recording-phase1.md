# Scenario-Based Recording Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement rehearsal recording with automatic scenario generation, timeline-integrated ScenarioTrack display, and full scenario editing capabilities.

**Architecture:** Scenario is an independent model from Timeline — `ScreenizeProject.scenario: Scenario?` (runtime-only, excluded from CodingKeys). PackageManager handles `scenario.json` and `scenario-raw.json` as separate files in the `.screenize` package. ScenarioTrack renders above timeline tracks in the editor but is not part of the `AnySegmentTrack` system. A new `ScenarioEventRecorder` runs alongside `MouseDataRecorder` during rehearsal mode, collecting raw events that `ScenarioGenerator` converts to semantic steps.

**Tech Stack:** Swift, SwiftUI, ScreenCaptureKit, Accessibility Framework, Combine

**Spec:** `docs/superpowers/specs/2026-03-16-scenario-based-recording-design.md`

**CRITICAL — Xcode project file management:** Every task that creates new `.swift` files MUST also add them to `Screenize.xcodeproj/project.pbxproj` in the same commit. Each file requires 4 entries: PBXBuildFile, PBXFileReference, PBXGroup child, PBXSourcesBuildPhase entry. New directories need a PBXGroup entry + parent group reference. Check UUID prefix conflicts before adding (see MEMORY.md for used prefixes). Without this step, `xcodebuild build` will not compile the new files.

**Scenario save timing:** Scenario changes are persisted by hooking into the existing project auto-save flow. When `EditorViewModel` detects scenario mutations, it updates `project.scenario` and triggers the same save path used for timeline edits — `PackageManager.save()` which now also writes `scenario.json` via `ScenarioFileManager`.

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `Screenize/Scenario/ScenarioModels.swift` | `Scenario`, `ScenarioStep`, `AXTarget`, `MousePath`, `ScenarioRawEvents` — all Codable data models |
| `Screenize/Scenario/ScenarioGenerator.swift` | Pure function: raw events → semantic steps conversion |
| `Screenize/Scenario/ScenarioEventRecorder.swift` | Records raw scenario events during rehearsal (parallel to MouseDataRecorder) |
| `Screenize/Scenario/WaypointExtractor.swift` | Extracts waypoints from raw mouse path at configurable Hz |
| `Screenize/Scenario/ScenarioFileManager.swift` | Read/write `scenario.json` and `scenario-raw.json` to/from `.screenize` packages |
| `Screenize/Views/Scenario/ScenarioTrackView.swift` | Timeline track rendering for scenario steps (blocks with icons/labels) |
| `Screenize/Views/Scenario/ScenarioInspectorView.swift` | Step-type-specific inspector panels |
| `Screenize/Views/Scenario/ScenarioStepBlockView.swift` | Individual step block rendering (icon + label + color) |
| `ScreenizeTests/ScenarioGeneratorTests.swift` | Unit tests for raw → semantic conversion |
| `ScreenizeTests/ScenarioModelsTests.swift` | Unit tests for Codable round-trip, model invariants |
| `ScreenizeTests/WaypointExtractorTests.swift` | Unit tests for waypoint extraction at various Hz |

### Modified Files

| File | Change |
|------|--------|
| `Screenize/Core/Coordinates.swift` | Add `cgNormalizedToNormalized()` / `normalizedToCGNormalized()` helpers |
| `Screenize/Core/Tracking/AccessibilityInspector.swift` | Add `parentPath(for:)` method for AX parent chain traversal |
| `Screenize/Core/Recording/RecordingCoordinator.swift` | Add rehearsal mode flag, integrate ScenarioEventRecorder start/stop |
| `Screenize/App/RecordingState.swift` | Store last scenario raw events, expose rehearsal mode |
| `Screenize/App/CaptureSettings.swift` | Add `@AppStorage("recordingMode")` for Direct/Rehearsal persistence |
| `Screenize/App/AppState.swift` | Thread recording mode through to RecordingCoordinator |
| `Screenize/Project/ScreenizeProject.swift` | Add `scenario: Scenario?` property (excluded from CodingKeys) |
| `Screenize/Project/PackageManager.swift` | Add scenario file load/save in package creation and loading |
| `Screenize/Project/ProjectCreator.swift` | Generate scenario from raw events during project creation |
| `Screenize/ViewModels/EditorViewModel.swift` | Manage scenario alongside timeline, scenario selection, undo/redo |
| `Screenize/Views/Recording/CaptureToolbarPanel.swift` | Add mode dropdown to selecting phase, rehearsal visual state |
| `Screenize/App/CaptureToolbarCoordinator.swift` | Pass recording mode to AppState |
| `Screenize/Views/Timeline/TimelineView.swift` | Render ScenarioTrackView above existing tracks |
| `Screenize/Views/Inspector/InspectorView.swift` | Show ScenarioInspectorView when scenario step is selected |

---

## Chunk 1: Data Models & Coordinate Helpers

### Task 1: Verify Test Infrastructure

**Files:**
- Existing: `ScreenizeTests/` directory (already exists with test files in `Generators/`, `Render/`, `Models/`, etc.)

- [ ] **Step 1: Verify test target builds**

Run: `xcodebuild -project Screenize.xcodeproj -scheme ScreenizeTests -configuration Debug build-for-testing`

Expected: Build succeeds. If not, fix any existing build issues before proceeding.

---

### Task 2: Scenario Data Models

**Files:**
- Create: `Screenize/Scenario/ScenarioModels.swift`
- Test: `ScreenizeTests/ScenarioModelsTests.swift`

- [ ] **Step 1: Write tests for Scenario model Codable round-trip**

Test that `Scenario` with various step types (click, mouse_move with auto path, mouse_move with waypoints, keyboard, type_text, scroll, activate_app, wait) can be encoded to JSON and decoded back identically. Test that `ScenarioRawEvents` encodes/decodes correctly.

- [ ] **Step 2: Run tests — expect FAIL (types don't exist)**

- [ ] **Step 3: Implement Scenario data models**

```swift
// Screenize/Scenario/ScenarioModels.swift

// MARK: - Scenario (scenario.json root)

struct Scenario: Codable, Equatable {
    var version: Int = 1
    var appContext: String?
    var steps: [ScenarioStep]

    /// Total duration in seconds (sum of all step durations)
    var totalDuration: TimeInterval {
        steps.reduce(0) { $0 + $1.durationSeconds }
    }

    /// Step at given cumulative time offset
    func step(at time: TimeInterval) -> ScenarioStep? { ... }

    /// Cumulative start time for step at index
    func startTime(forStepAt index: Int) -> TimeInterval { ... }
}

// MARK: - ScenarioStep

struct ScenarioStep: Codable, Identifiable, Equatable {
    let id: UUID
    var type: StepType
    var description: String
    var durationMs: Int

    // Type-specific fields (optional, presence depends on type)
    var target: AXTarget?           // click, double_click, right_click, scroll, mouse_down, mouse_up
    var path: MousePath?            // mouse_move
    var rawTimeRange: TimeRange?    // mouse_move (for Generate from recording)
    var app: String?                // activate_app (bundle ID)
    var keyCombo: String?           // keyboard
    var content: String?            // type_text
    var typingSpeedMs: Int?         // type_text
    var direction: ScrollDirection? // scroll
    var amount: Int?                // scroll (pixels)

    var durationSeconds: TimeInterval { Double(durationMs) / 1000.0 }

    enum StepType: String, Codable, CaseIterable {
        case mouseMove = "mouse_move"
        case activateApp = "activate_app"
        case click
        case doubleClick = "double_click"
        case rightClick = "right_click"
        case mouseDown = "mouse_down"
        case mouseUp = "mouse_up"
        case scroll
        case keyboard
        case typeText = "type_text"
        case wait
    }

    enum ScrollDirection: String, Codable {
        case up, down, left, right
    }
}

// MARK: - AXTarget

struct AXTarget: Codable, Equatable {
    var role: String
    var axTitle: String?
    var axValue: String?
    var path: [String]
    var positionHint: CGPoint   // 0-1 normalized, CG top-left origin
    var absoluteCoord: CGPoint  // CG pixels, top-left origin
}

// MARK: - MousePath

enum MousePath: Codable, Equatable {
    case auto
    case waypoints(points: [CGPoint])  // 0-1 normalized, CG top-left origin

    // Custom Codable: "auto" string or { type: "waypoints", points: [...] }
}

// MARK: - TimeRange

struct TimeRange: Codable, Equatable {
    let startMs: Int
    let endMs: Int
}

// MARK: - ScenarioRawEvents (scenario-raw.json root)

struct ScenarioRawEvents: Codable, Equatable {
    var version: Int = 1
    var startTimestamp: String  // ISO8601
    var captureArea: CGRect
    var events: [RawEvent]
}

// MARK: - RawEvent

struct RawEvent: Codable, Equatable {
    let timeMs: Int
    let type: RawEventType

    // Mouse fields
    var x: Double?
    var y: Double?
    var button: String?     // "left" or "right"

    // Scroll fields
    var deltaX: Double?
    var deltaY: Double?

    // Keyboard fields
    var keyCode: UInt16?
    var characters: String?
    var modifiers: [String]?

    // App fields
    var bundleId: String?
    var appName: String?

    // AX info (optional, async)
    var ax: RawAXInfo?

    enum RawEventType: String, Codable {
        case mouseMove = "mouse_move"
        case mouseDown = "mouse_down"
        case mouseUp = "mouse_up"
        case scroll
        case keyDown = "key_down"
        case keyUp = "key_up"
        case appActivated = "app_activated"
    }
}

// MARK: - RawAXInfo

struct RawAXInfo: Codable, Equatable {
    let role: String
    let axTitle: String?
    let axValue: String?
    let axDescription: String?
    let path: [String]
    let frame: CGRect
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Add files to Xcode project**

Add `Screenize/Scenario/ScenarioModels.swift` and `ScreenizeTests/ScenarioModelsTests.swift` to `project.pbxproj`. Create `Scenario` PBXGroup under the main Screenize group.

- [ ] **Step 6: Build and verify**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`

- [ ] **Step 7: Commit**

```
feat: Add Scenario data models (Scenario, ScenarioStep, RawEvent, AXTarget)
```

---

### Task 3: Coordinate Conversion Helpers

**Files:**
- Modify: `Screenize/Core/Coordinates.swift`
- Test: `ScreenizeTests/CoordinateHelpersTests.swift`

- [ ] **Step 1: Write tests for Y-flip conversion**

Test `cgNormalizedToNormalized` converts (0.5, 0.2) → NormalizedPoint(x: 0.5, y: 0.8). Test round-trip: `normalizedToCGNormalized(cgNormalizedToNormalized(p)) == p`.

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Add helpers to CoordinateConverter**

```swift
extension CoordinateConverter {
    /// Convert CG normalized (top-left origin) to NormalizedPoint (bottom-left origin)
    static func cgNormalizedToNormalized(_ cgPoint: CGPoint) -> NormalizedPoint {
        NormalizedPoint(x: cgPoint.x, y: 1.0 - cgPoint.y)
    }

    /// Convert NormalizedPoint (bottom-left origin) to CG normalized (top-left origin)
    static func normalizedToCGNormalized(_ point: NormalizedPoint) -> CGPoint {
        CGPoint(x: point.x, y: 1.0 - point.y)
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```
feat: Add CG normalized <-> NormalizedPoint Y-flip conversion helpers
```

---

### Task 4: AX Parent Path Traversal

**Files:**
- Modify: `Screenize/Core/Tracking/AccessibilityInspector.swift`

- [ ] **Step 1: Add `parentPath(for:)` method**

```swift
/// Traverse parent chain from element to AXWindow, collecting role strings.
/// Returns array like ["AXWindow", "AXSplitGroup", "AXOutline"].
/// Appends 0-based index for siblings with same role (e.g., "AXButton[2]").
/// Max depth: 15. Timeout: 500ms.
func parentPath(for element: AXUIElement) -> [String] {
    // Implementation: walk AXUIElementCopyAttributeValue(.parent) up to AXWindow
    // For each level, get role via kAXRoleAttribute
    // Check sibling count: get parent's children, filter same role, find index
    // Reverse the collected path so it starts from AXWindow
}
```

- [ ] **Step 2: Add `elementWithPath(at:)` method that returns both UIElementInfo and path**

```swift
struct ScenarioElementInfo {
    let element: UIElementInfo
    let path: [String]
    let axValue: String?
    let axDescription: String?
}

func scenarioElementAt(screenPoint: CGPoint) -> ScenarioElementInfo?
```

- [ ] **Step 3: Build and verify no compilation errors**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`

- [ ] **Step 4: Commit**

```
feat: Add AX parent path traversal to AccessibilityInspector
```

---

## Chunk 2: ScenarioGenerator (Core Logic)

### Task 5: ScenarioGenerator — Raw Event to Semantic Step Conversion

**Files:**
- Create: `Screenize/Scenario/ScenarioGenerator.swift`
- Test: `ScreenizeTests/ScenarioGeneratorTests.swift`

- [ ] **Step 1: Write tests for click detection**

Test: mouseDown(left) at (340, 52) → mouseUp(left) at (342, 53) within 5px → produces `click` step with correct AX target.

Test: mouseDown(left) at (340, 52) → mouseUp(left) at (340, 52) twice within 400ms → produces `double_click`.

Test: mouseDown(right) at (340, 52) → mouseUp(right) at (342, 53) → produces `right_click`.

- [ ] **Step 2: Write tests for drag detection**

Test: mouseDown → mouseMove (>5px) → mouseUp → produces `mouse_down` + `mouse_move` + `mouse_up` (implicit drag group).

- [ ] **Step 3: Write tests for scroll merging**

Test: 3 scroll events within 100ms intervals → produces single `scroll` step with summed deltas.

Test: 2 scroll events with >100ms gap → produces 2 separate `scroll` steps.

- [ ] **Step 4: Write tests for keyboard detection**

Test: cmd keyDown + c keyDown (with cmd modifier) → produces `keyboard` step with combo `"cmd+c"`.

Test: 3 character keyDowns without modifiers → produces `type_text` step.

- [ ] **Step 5: Write tests for activate_app detection**

Test: app_activated event → produces `activate_app` step with bundleId.

- [ ] **Step 6: Write test for empty events**

Test: `ScenarioRawEvents` with `events: []` → produces `Scenario` with empty steps (no crash, no error).

- [ ] **Step 7: Write tests for mouse_move auto-insertion**

Test: after conversion, all adjacent action steps have a `mouse_move` step between them with `path: .auto`.

- [ ] **Step 8: Write tests for timing**

Test: 500ms gap between events → reflected in step durationMs.

Test: mouse_move durationMs calculated from raw mouse movement time.

- [ ] **Step 9: Run all tests — expect FAIL**

- [ ] **Step 10: Implement ScenarioGenerator**

```swift
// Screenize/Scenario/ScenarioGenerator.swift

struct ScenarioGenerator {
    /// Convert raw events to semantic scenario steps.
    /// Pure function — no side effects, fully testable.
    static func generate(from rawEvents: ScenarioRawEvents) -> Scenario {
        let actionSteps = convertToActionSteps(rawEvents.events, captureArea: rawEvents.captureArea)
        let stepsWithMoves = insertMouseMoves(actionSteps, rawEvents: rawEvents.events)
        return Scenario(
            version: 1,
            appContext: detectAppContext(rawEvents.events),
            steps: stepsWithMoves
        )
    }

    // MARK: - Private

    private static func convertToActionSteps(_ events: [RawEvent], captureArea: CGRect) -> [ScenarioStep] { ... }
    private static func insertMouseMoves(_ steps: [ScenarioStep], rawEvents: [RawEvent]) -> [ScenarioStep] { ... }
    private static func detectAppContext(_ events: [RawEvent]) -> String? { ... }

    // Pattern matchers
    private static func detectClick(...) -> ScenarioStep? { ... }
    private static func detectDoubleClick(...) -> ScenarioStep? { ... }
    private static func mergeScrolls(...) -> ScenarioStep? { ... }
    private static func detectKeyboardCombo(...) -> ScenarioStep? { ... }
    private static func detectTypeText(...) -> ScenarioStep? { ... }
}
```

- [ ] **Step 11: Run all tests — expect PASS**

- [ ] **Step 12: Add files to Xcode project**

Add `Screenize/Scenario/ScenarioGenerator.swift` and `ScreenizeTests/ScenarioGeneratorTests.swift` to `project.pbxproj`.

- [ ] **Step 13: Commit**

```
feat: Implement ScenarioGenerator (raw events → semantic steps)
```

---

### Task 6: Waypoint Extractor

**Files:**
- Create: `Screenize/Scenario/WaypointExtractor.swift`
- Test: `ScreenizeTests/WaypointExtractorTests.swift`

- [ ] **Step 1: Write tests for waypoint extraction**

Test: 100 raw mouse_move events over 1 second at 5Hz → produces 5 waypoints (evenly sampled).

Test: at 1Hz → produces 1 waypoint.

Test: at 30Hz → produces 30 waypoints.

Test: empty event range → produces empty waypoints.

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement WaypointExtractor**

```swift
struct WaypointExtractor {
    /// Extract waypoints from raw mouse_move events at specified Hz.
    /// Returns normalized CG coordinates (top-left origin, 0-1 range).
    static func extract(
        from rawEvents: ScenarioRawEvents,
        timeRange: TimeRange,
        hz: Int,
        captureArea: CGRect
    ) -> [CGPoint] {
        // 1. Filter mouse_move events within timeRange
        // 2. Sample at 1/hz intervals
        // 3. Normalize to 0-1 relative to captureArea
        // 4. Return points array
    }
}
```

- [ ] **Step 4: Run tests — expect PASS**

- [ ] **Step 5: Commit**

```
feat: Implement WaypointExtractor for Generate from recording
```

---

## Chunk 3: Recording Pipeline Integration

### Task 7: ScenarioEventRecorder

**Files:**
- Create: `Screenize/Scenario/ScenarioEventRecorder.swift`

- [ ] **Step 1: Implement ScenarioEventRecorder**

```swift
/// Records raw scenario events during rehearsal mode.
/// Runs alongside MouseDataRecorder, capturing mouse/keyboard/scroll events
/// with event-based AX sampling.
final class ScenarioEventRecorder {
    private let eventMonitor = EventMonitorManager()
    private let accessibilityInspector = AccessibilityInspector()
    private let axQueue = DispatchQueue(label: "com.screenize.scenario.ax", qos: .userInitiated)

    private var events: [RawEvent] = []
    private var startTime: Date?
    private var processTimeStartMs: Int64 = 0
    private var captureArea: CGRect = .zero
    private var isPaused = false
    private var pauseOffset: Int = 0   // Accumulated pause time in ms
    private var lastAXQueryTime: TimeInterval = 0  // For 50ms debounce
    private let lock = NSLock()

    func startRecording(captureArea: CGRect, processTimeStartMs: Int64) { ... }
    func pauseRecording() { ... }
    func resumeRecording() { ... }
    func stopRecording() -> ScenarioRawEvents { ... }

    // MARK: - Private
    private func setupEventMonitors() { ... }
    private func recordEvent(_ event: RawEvent) { ... }
    private func queryAXAsync(at point: CGPoint, completion: @escaping (RawAXInfo?) -> Void) { ... }
}
```

Key implementation details:
- Register monitors via `EventMonitorManager` for mouse clicks, scroll, keyboard, app activation
- Mouse move sampling: record at ~30Hz (separate from MouseDataRecorder's 60Hz)
- AX queries on `axQueue` with 500ms timeout, 50ms debounce
- Pause support: track pause offset, subtract from timeMs calculations
- Thread-safe event array with NSLock

- [ ] **Step 2: Write tests for pause offset and debounce logic**

Create `ScreenizeTests/ScenarioEventRecorderTests.swift`:
- Test: pause offset correctly subtracted from event timeMs
- Test: 50ms debounce skips duplicate AX queries
- Test: events recorded during pause are discarded
- Extract timing/offset calculations as static pure functions for testability.

- [ ] **Step 3: Add files to Xcode project**

Add `Screenize/Scenario/ScenarioEventRecorder.swift` and `ScreenizeTests/ScenarioEventRecorderTests.swift` to `project.pbxproj`.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```
feat: Add ScenarioEventRecorder for rehearsal event capture
```

---

### Task 8: RecordingCoordinator Rehearsal Mode

**Files:**
- Modify: `Screenize/App/CaptureSettings.swift`
- Modify: `Screenize/Core/Recording/RecordingCoordinator.swift`
- Modify: `Screenize/App/RecordingState.swift`
- Modify: `Screenize/App/AppState.swift`

- [ ] **Step 1: Add RecordingMode to CaptureSettings**

```swift
// In CaptureSettings.swift
enum RecordingMode: String, Codable {
    case direct
    case rehearsal
}

@AppStorage("recordingMode") var recordingMode: RecordingMode = .direct
```

- [ ] **Step 2: Add ScenarioEventRecorder to RecordingCoordinator**

```swift
// In RecordingCoordinator.swift
private var scenarioEventRecorder: ScenarioEventRecorder?
var isRehearsalMode: Bool = false

// In startRecording(): if isRehearsalMode, create and start ScenarioEventRecorder
// In stopRecording(): if rehearsalMode, collect raw events from ScenarioEventRecorder
// In pauseRecording()/resumeRecording(): also pause/resume ScenarioEventRecorder
```

- [ ] **Step 3: Add raw events storage to RecordingState**

```swift
// In RecordingState.swift
var lastScenarioRawEvents: ScenarioRawEvents?
```

- [ ] **Step 4: Thread recording mode through AppState**

In `AppState.startRecording()`, pass `captureSettings.recordingMode` to `RecordingCoordinator.isRehearsalMode`.

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```
feat: Integrate rehearsal mode into recording pipeline
```

---

### Task 9: Scenario File I/O & Package Integration

**Files:**
- Create: `Screenize/Scenario/ScenarioFileManager.swift`
- Modify: `Screenize/Project/PackageManager.swift`
- Modify: `Screenize/Project/ScreenizeProject.swift`
- Modify: `Screenize/Project/ProjectCreator.swift`

- [ ] **Step 1: Create ScenarioFileManager**

```swift
enum ScenarioFileManager {
    static let scenarioFilename = "scenario.json"
    static let scenarioRawFilename = "scenario-raw.json"

    static func save(_ scenario: Scenario, to packageURL: URL) throws { ... }
    static func saveRaw(_ rawEvents: ScenarioRawEvents, to packageURL: URL) throws { ... }
    static func loadScenario(from packageURL: URL) -> Scenario? { ... }
    static func loadRawEvents(from packageURL: URL) -> ScenarioRawEvents? { ... }
}
```

- [ ] **Step 2: Add scenario to ScreenizeProject (CodingKeys excluded)**

```swift
// In ScreenizeProject.swift
var scenario: Scenario?     // Runtime-only, not in project.json
var scenarioRawEvents: ScenarioRawEvents?  // Runtime-only

// Add explicit CodingKeys that include ALL existing properties but exclude scenario/scenarioRawEvents.
// Current ScreenizeProject uses automatic CodingKeys synthesis, so we must enumerate all existing keys:
private enum CodingKeys: String, CodingKey {
    case id, version, name, createdAt, modifiedAt
    case media, captureMeta, timeline, renderSettings
    case frameAnalysisCache, frameAnalysisVersion
    case interop, generationSettings
    // scenario and scenarioRawEvents are intentionally EXCLUDED
}
```

**WARNING**: Omitting any existing property from CodingKeys will silently break load/save for existing `.screenize` projects. Double-check against the current `ScreenizeProject` struct before committing.

- [ ] **Step 3: Update PackageManager.load() to load scenario files**

```swift
// In PackageManager.load(from:)
// After loading project from project.json:
project.scenario = ScenarioFileManager.loadScenario(from: packageURL)
project.scenarioRawEvents = ScenarioFileManager.loadRawEvents(from: packageURL)
```

- [ ] **Step 4: Update PackageManager.save() to save scenario files**

```swift
// In PackageManager.save(_:to:)
// After saving project.json:
if let scenario = project.scenario {
    try ScenarioFileManager.save(scenario, to: packageURL)
}
```

- [ ] **Step 5: Update PackageManager.createPackageV4() for rehearsal output**

Add optional `scenarioRawEvents: ScenarioRawEvents?` parameter. When provided, run `ScenarioGenerator.generate()` and save both files.

- [ ] **Step 6: Update ProjectCreator to generate scenario from raw events**

In `createFromRecording()`, if raw events are provided, generate scenario and assign to project.

- [ ] **Step 7: Build and verify**

- [ ] **Step 8: Commit**

```
feat: Add scenario file I/O and package integration
```

---

## Chunk 4: Capture Toolbar UI

### Task 10: Mode Selection Dropdown

**Files:**
- Modify: `Screenize/Views/Recording/CaptureToolbarPanel.swift`
- Modify: `Screenize/App/CaptureToolbarCoordinator.swift`

- [ ] **Step 1: Add mode dropdown to toolbar selecting phase**

In `CaptureToolbarPanel.swift`, add a mode selector in the selecting phase:
- Dropdown next to the Record button area
- Two options: "Direct Record" (red circle icon) and "Rehearsal" (clipboard icon)
- Selected mode stored in `CaptureSettings.recordingMode` via `@AppStorage`
- When Rehearsal is selected, the main action button text changes to "Rehearse"

- [ ] **Step 2: Update recording phase visuals for rehearsal mode**

In the `.recording` phase content:
- If rehearsal mode: show "Rehearsing" text with green pulsing dot (instead of red "Recording")
- Use purple/blue accent color instead of red
- Same controls (Pause, Stop, etc.)

- [ ] **Step 3: Pass recording mode through CaptureToolbarCoordinator**

In `confirmAndRecord()`, read `CaptureSettings.recordingMode` and pass to `AppState`.

- [ ] **Step 4: Build and verify visually**

- [ ] **Step 5: Commit**

```
feat: Add rehearsal mode selection to capture toolbar
```

---

## Chunk 5: Editor — ScenarioTrack & Inspector

### Task 11: EditorViewModel Scenario Management

**Files:**
- Modify: `Screenize/ViewModels/EditorViewModel.swift`

- [ ] **Step 1: Add scenario state to EditorViewModel**

```swift
// New properties
@Published var scenario: Scenario?
@Published var selectedStepId: UUID?
@Published var scenarioRawEvents: ScenarioRawEvents?

// Scenario binding for views
var scenarioBinding: Binding<Scenario?> { ... }

// Step operations
func selectStep(_ id: UUID) { ... }        // Select + seek preview
func clearStepSelection() { ... }
func deleteStep(_ id: UUID) { ... }
func duplicateStep(_ id: UUID) { ... }
func moveStep(from: Int, to: Int) { ... }
func addStep(_ step: ScenarioStep, at index: Int) { ... }
func updateStep(_ step: ScenarioStep) { ... }
```

- [ ] **Step 2: Integrate scenario with undo/redo**

Include `scenario` in `EditorSnapshot` so that undo/redo covers scenario changes.

- [ ] **Step 3: Load scenario from project in init**

```swift
// In init or setup():
self.scenario = project.scenario
self.scenarioRawEvents = project.scenarioRawEvents
```

- [ ] **Step 4: Save scenario changes back to project**

When scenario changes, update `project.scenario` for persistence.

- [ ] **Step 5: Build and verify**

- [ ] **Step 6: Commit**

```
feat: Add scenario management to EditorViewModel
```

---

### Task 12: ScenarioTrack Timeline View

**Files:**
- Create: `Screenize/Views/Scenario/ScenarioStepBlockView.swift`
- Create: `Screenize/Views/Scenario/ScenarioTrackView.swift`
- Modify: `Screenize/Views/Timeline/TimelineView.swift`

- [ ] **Step 1: Create ScenarioStepBlockView**

Individual step block with:
- Icon based on step type (using SF Symbols or custom)
- Color based on step type (per spec: click=blue, scroll=purple, keyboard=yellow, etc.)
- Short label (step description, truncated)
- Width proportional to durationMs
- mouse_move blocks: thin, arrow-style, grey
- Drag group visual linking

```swift
struct ScenarioStepBlockView: View {
    let step: ScenarioStep
    let isSelected: Bool
    let pixelsPerSecond: CGFloat

    var body: some View { ... }

    private var stepColor: Color { ... }
    private var stepIcon: String { ... }
}
```

- [ ] **Step 2: Create ScenarioTrackView**

Track view rendered above existing timeline tracks:
- Shows all steps as blocks on the time axis
- Supports click to select step
- Supports drag to reorder
- Supports edge drag to resize (change durationMs)
- Right-click context menu: Add Step, Delete, Duplicate
- Keyboard: Delete key, Cmd+D

```swift
struct ScenarioTrackView: View {
    @Binding var scenario: Scenario
    let duration: TimeInterval
    let pixelsPerSecond: CGFloat
    let trimStart: TimeInterval
    @Binding var selectedStepId: UUID?

    var onStepSelect: ((UUID) -> Void)?
    var onStepDelete: ((UUID) -> Void)?
    var onStepDuplicate: ((UUID) -> Void)?
    var onStepAdd: ((Int) -> Void)?
    var onStepReorder: ((Int, Int) -> Void)?
    var onStepDurationChange: ((UUID, Int) -> Void)?

    var body: some View { ... }
}
```

- [ ] **Step 3: Integrate ScenarioTrackView into TimelineView**

In `TimelineView.swift`, conditionally render `ScenarioTrackView` above the existing track ForEach when `scenario != nil`. Add "Scenario" track header with appropriate icon.

Thread scenario binding from EditorViewModel through TimelineView.

- [ ] **Step 4: Build and verify**

- [ ] **Step 5: Commit**

```
feat: Add ScenarioTrack rendering to timeline
```

---

### Task 13: Scenario Inspector Views

**Files:**
- Create: `Screenize/Views/Scenario/ScenarioInspectorView.swift`
- Modify: `Screenize/Views/Inspector/InspectorView.swift`

- [ ] **Step 1: Create ScenarioInspectorView**

Step-type-specific inspector with fields per spec:

```swift
struct ScenarioInspectorView: View {
    @Binding var step: ScenarioStep
    var scenarioRawEvents: ScenarioRawEvents?
    var onGenerateWaypoints: ((UUID, Int) -> Void)?  // stepId, hz

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                // Common fields: Type picker, Description
                commonSection

                // Type-specific fields
                switch step.type {
                case .mouseMove: mouseMoveSection
                case .click, .doubleClick, .rightClick: clickSection
                case .keyboard: keyboardSection
                case .typeText: typeTextSection
                case .scroll: scrollSection
                case .activateApp: activateAppSection
                case .wait: waitSection
                case .mouseDown, .mouseUp: mouseDownUpSection
                }

                // Timing
                timingSection
            }
            .padding()
        }
    }
}
```

Each section implements the inspector layouts from the spec:
- `mouseMoveSection`: Auto/Waypoints radio, Generate from recording button + Hz picker
- `clickSection`: Target info (role read-only, title editable, path read-only, position editable)
- `keyboardSection`: Key combo field
- `typeTextSection`: Content field, typing speed field
- `scrollSection`: Direction picker, amount field, target info

- [ ] **Step 2: Integrate into InspectorView**

In `InspectorView.swift`, when a scenario step is selected (check `EditorViewModel.selectedStepId`), show `ScenarioInspectorView` instead of the regular segment inspector.

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```
feat: Add Scenario Inspector with type-specific editing panels
```

---

## Chunk 6: Editing Operations

### Task 14: Step Editing — Drag, Resize, Delete, Duplicate, Add

**Files:**
- Modify: `Screenize/Views/Scenario/ScenarioTrackView.swift`
- Modify: `Screenize/ViewModels/EditorViewModel.swift`

- [ ] **Step 1: Implement step reorder via drag**

In ScenarioTrackView, add drag gesture on step blocks. On drop, call `EditorViewModel.moveStep(from:to:)` which reorders the `scenario.steps` array and saves undo snapshot.

- [ ] **Step 2: Implement step resize via edge drag**

On drag of block right edge, calculate new durationMs from pixel delta / pixelsPerSecond. Call `EditorViewModel.updateStep()` with modified durationMs.

- [ ] **Step 3: Implement Delete key handler**

When a step is selected and Delete key is pressed, call `EditorViewModel.deleteStep()`. Save undo snapshot before deletion.

- [ ] **Step 4: Implement Cmd+D duplicate**

When a step is selected and Cmd+D is pressed, duplicate the step with a new UUID and insert after the current step.

- [ ] **Step 5: Implement context menu Add Step**

Right-click context menu on the track with "Add Step" submenu showing all step types. Insert a new step with default values at the clicked position.

- [ ] **Step 6: Build and verify**

- [ ] **Step 7: Commit**

```
feat: Implement scenario step editing operations (drag, resize, delete, duplicate, add)
```

---

### Task 15: Generate from Recording

**Files:**
- Modify: `Screenize/Views/Scenario/ScenarioInspectorView.swift`
- Modify: `Screenize/ViewModels/EditorViewModel.swift`

- [ ] **Step 1: Add generateWaypoints method to EditorViewModel**

```swift
func generateWaypoints(forStepId id: UUID, hz: Int) {
    guard let rawEvents = scenarioRawEvents,
          let stepIndex = scenario?.steps.firstIndex(where: { $0.id == id }),
          let timeRange = scenario?.steps[stepIndex].rawTimeRange else { return }

    saveUndoSnapshot()
    let points = WaypointExtractor.extract(
        from: rawEvents,
        timeRange: timeRange,
        hz: hz,
        captureArea: rawEvents.captureArea
    )
    scenario?.steps[stepIndex].path = .waypoints(points: points)
}
```

- [ ] **Step 2: Wire up inspector Generate from recording button**

In ScenarioInspectorView's mouseMoveSection, the "Generate from recording" button calls `onGenerateWaypoints?(step.id, selectedHz)`. Hz picker shows [1, 2, 5, 10, 15, 30] options, default 5.

- [ ] **Step 3: Build and verify**

- [ ] **Step 4: Commit**

```
feat: Implement Generate from recording (waypoint extraction) for mouse_move steps
```

---

## Chunk 7: End-to-End Integration & Polish

### Task 16: Post-Recording Flow — Scenario Generation Spinner

**Files:**
- Modify: `Screenize/App/AppState.swift` (or wherever post-recording flow lives)

- [ ] **Step 1: Add scenario generation step after rehearsal stop**

After `RecordingCoordinator.stopRecording()` returns in rehearsal mode:
1. Show progress indicator ("Generating scenario...")
2. Run `ScenarioGenerator.generate(from: rawEvents)` on background queue
3. Save scenario + raw events to package via ScenarioFileManager
4. Open VideoEditor with scenario loaded

- [ ] **Step 2: Build and verify end-to-end flow**

Manual test: select Rehearsal mode → record a short session → Stop → verify spinner appears → VideoEditor opens with ScenarioTrack visible.

- [ ] **Step 3: Commit**

```
feat: Add scenario generation spinner and post-rehearsal editor integration
```

---

### Task 17: Lint & Build Verification

- [ ] **Step 1: Run linter**

Run: `./scripts/lint.sh`

Fix any violations in new files (line length 140/200, etc.)

- [ ] **Step 2: Run full build**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`

- [ ] **Step 3: Run tests**

Run: `xcodebuild -project Screenize.xcodeproj -scheme ScreenizeTests -configuration Debug test`

- [ ] **Step 4: Fix any issues**

- [ ] **Step 5: Final commit**

```
chore: Fix lint violations and verify clean build
```

---

## Task Dependency Graph

```
Task 1 (Verify Tests)
  │
  ▼
Tasks 2, 3, 4 (Data Models, Coord Helpers, AX Path) — can run in parallel
  │
  ├──→ Task 5 (ScenarioGenerator) — depends on Task 2 only
  │         │
  ├──→ Task 6 (WaypointExtractor) — depends on Task 2 only (parallel with Task 5)
  │         │
  └──→ Task 7 (ScenarioEventRecorder) — depends on Tasks 2 and 4
            │
            ▼
       Task 8 (Recording Pipeline) — depends on Task 7
            │
            ▼
       Task 9 (Package Integration) — depends on Tasks 5, 7, 8
            │
            ▼
       Task 10 (Toolbar UI) — depends on Task 8
            │
            ▼
       Task 11 (EditorViewModel) — depends on Task 9
            │
      ┌─────┴─────┐
      ▼           ▼
Task 12 (Track UI)  Task 13 (Inspector) — can run in parallel
      │           │
      └─────┬─────┘
            ▼
Task 14 (Editing Ops) ──→ Task 15 (Generate from Recording, depends on Task 6)
            │
            ▼
Task 16 (E2E Flow) ──→ Task 17 (Lint/Build)
```

**Parallelizable groups:**
- Tasks 2, 3, 4 can run in parallel (no dependencies between them)
- Tasks 5, 6, 7 can run in parallel (all depend only on Task 2 and/or 4)
- Tasks 12 and 13 can run in parallel
