# Advanced Generation Settings Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expose all 80+ smart generation constants as user-configurable parameters via a dedicated settings window with app-level defaults, per-project overrides, and user presets.

**Architecture:** A `GenerationSettings` Codable struct wraps 5 nested setting groups. `GenerationSettingsManager` (singleton) persists app-level defaults to Application Support JSON. `ScreenizeProject` gains an optional override field. Existing generator settings structs gain `init(from:)` factories. A standalone NSWindow hosts the settings UI with collapsible sections.

**Tech Stack:** SwiftUI, Codable, JSONEncoder/Decoder, NSWindow, DisclosureGroup

**Design doc:** `docs/plans/2026-03-10-advanced-generation-settings-design.md`

---

### Task 1: GenerationSettings Data Model

**Files:**
- Create: `Screenize/Generators/GenerationSettings.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj` (add file reference)

**Step 1: Create GenerationSettings.swift**

This is the central data model. 5 nested Codable structs, each with defaults matching current hardcoded values. All types must conform to `Codable` and `Equatable`.

```swift
import Foundation
import CoreGraphics

// MARK: - Generation Settings

/// User-configurable settings for the smart generation pipeline.
/// Persisted at app level and optionally overridden per project.
struct GenerationSettings: Codable, Equatable {

    var cameraMotion = CameraMotionSettings()
    var zoom = ZoomSettings()
    var intentClassification = IntentClassificationSettings()
    var timing = TimingSettings()
    var cursorKeystroke = CursorKeystrokeSettings()

    static let `default` = GenerationSettings()
}

// MARK: - Camera Motion Settings

struct CameraMotionSettings: Codable, Equatable {
    // Spring physics (from ContinuousCameraSettings)
    var positionDampingRatio: CGFloat = 0.90
    var positionResponse: CGFloat = 0.35
    var zoomDampingRatio: CGFloat = 0.90
    var zoomResponse: CGFloat = 0.55
    var boundaryStiffness: CGFloat = 12.0
    var zoomSettleThreshold: CGFloat = 0.02

    // Urgency multipliers (from ContinuousCameraSettings.urgencyMultipliers)
    var urgencyImmediateMultiplier: CGFloat = 0.05
    var urgencyHighMultiplier: CGFloat = 0.5
    var urgencyNormalMultiplier: CGFloat = 1.0
    var urgencyLazyMultiplier: CGFloat = 2.0
    var urgencyBlendDuration: CGFloat = 0.5

    // Dead zone (from DeadZoneSettings)
    var safeZoneFraction: CGFloat = 0.75
    var safeZoneFractionTyping: CGFloat = 0.60
    var gradientBandWidth: CGFloat = 0.25
    var correctionFraction: CGFloat = 0.45
    var hysteresisMargin: CGFloat = 0.15
    var correctionFractionTyping: CGFloat = 0.80
    var deadZoneMinResponse: CGFloat = 0.20
    var deadZoneMaxResponse: CGFloat = 0.50

    // Micro tracker (from MicroTrackerSettings)
    var idleVelocityThreshold: CGFloat = 0.02
    var microTrackerDampingRatio: CGFloat = 1.0
    var microTrackerResponse: CGFloat = 3.0
}

// MARK: - Zoom Settings

struct ZoomSettings: Codable, Equatable {
    // Per-activity zoom ranges (from ShotSettings)
    var typingCodeZoomMin: CGFloat = 2.0
    var typingCodeZoomMax: CGFloat = 2.5
    var typingTextFieldZoomMin: CGFloat = 2.2
    var typingTextFieldZoomMax: CGFloat = 2.8
    var typingTerminalZoomMin: CGFloat = 1.6
    var typingTerminalZoomMax: CGFloat = 2.0
    var typingRichTextZoomMin: CGFloat = 1.8
    var typingRichTextZoomMax: CGFloat = 2.2
    var clickingZoomMin: CGFloat = 1.5
    var clickingZoomMax: CGFloat = 2.5
    var navigatingZoomMin: CGFloat = 1.5
    var navigatingZoomMax: CGFloat = 1.8
    var draggingZoomMin: CGFloat = 1.3
    var draggingZoomMax: CGFloat = 1.6
    var scrollingZoomMin: CGFloat = 1.3
    var scrollingZoomMax: CGFloat = 1.5
    var readingZoomMin: CGFloat = 1.0
    var readingZoomMax: CGFloat = 1.3

    // Fixed zoom levels
    var switchingZoom: CGFloat = 1.0
    var idleZoom: CGFloat = 1.0

    // Global limits and modifiers
    var targetAreaCoverage: CGFloat = 0.7
    var workAreaPadding: CGFloat = 0.08
    var minZoom: CGFloat = 1.0
    var maxZoom: CGFloat = 2.8
    var idleZoomDecay: CGFloat = 0.5
    var zoomIntensity: CGFloat = 1.0
}

// MARK: - Intent Classification Settings

struct IntentClassificationSettings: Codable, Equatable {
    var typingSessionTimeout: CGFloat = 1.5
    var navigatingClickWindow: CGFloat = 2.0
    var navigatingClickDistance: CGFloat = 0.5
    var navigatingMinClicks: Int = 2
    var idleThreshold: CGFloat = 5.0
    var continuationGapThreshold: CGFloat = 1.5
    var continuationMaxDistance: CGFloat = 0.20
    var scrollMergeGap: CGFloat = 1.0
    var pointSpanDuration: CGFloat = 0.5
    var contextChangeWindow: CGFloat = 0.8
    var typingAnticipation: CGFloat = 0.4
}

// MARK: - Timing Settings

struct TimingSettings: Codable, Equatable {
    // Lead times per urgency (from WaypointGenerator.entryLeadTime)
    var leadTimeImmediate: CGFloat = 0.24
    var leadTimeHigh: CGFloat = 0.16
    var leadTimeNormal: CGFloat = 0.08
    var leadTimeLazy: CGFloat = 0.0

    // Simulation (from ContinuousCameraSettings)
    var tickRate: CGFloat = 60.0
    var typingDetailMinInterval: CGFloat = 0.2
    var typingDetailMinDistance: CGFloat = 0.025

    // Dead zone response thresholds (from DeadZoneSettings)
    var responseFastThreshold: CGFloat = 0.5
    var responseSlowThreshold: CGFloat = 2.0
}

// MARK: - Cursor & Keystroke Settings

struct CursorKeystrokeSettings: Codable, Equatable {
    var cursorScale: CGFloat = 2.0
    var keystrokeEnabled: Bool = true
    var shortcutsOnly: Bool = true
    var displayDuration: CGFloat = 1.5
    var fadeInDuration: CGFloat = 0.15
    var fadeOutDuration: CGFloat = 0.3
    var minInterval: CGFloat = 0.05
}
```

**Step 2: Add to Xcode project**

Add `GenerationSettings.swift` to `Screenize.xcodeproj/project.pbxproj` under the `Generators` group. Use a unique UUID prefix not already in use (check existing prefixes first).

**Step 3: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: add GenerationSettings data model with 5 nested setting groups
```

---

### Task 2: GenerationSettingsManager (Persistence Singleton)

**Files:**
- Create: `Screenize/Project/GenerationSettingsManager.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj`

**Step 1: Create GenerationSettingsManager.swift**

Follow the exact `PresetManager` pattern from `Screenize/Project/PresetManager.swift`.

```swift
import Foundation

/// Manages app-level generation settings and user presets.
@MainActor
final class GenerationSettingsManager: ObservableObject {

    // MARK: - Singleton

    static let shared = GenerationSettingsManager()

    // MARK: - Published Properties

    /// Current app-level generation settings
    @Published var settings = GenerationSettings.default

    /// User-created presets
    @Published private(set) var presets: [GenerationSettingsPreset] = []

    // MARK: - Initialization

    private init() {
        loadSettings()
        loadPresets()
    }

    // MARK: - Settings

    func saveSettings() {
        do {
            let directory = settingsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: settingsFileURL, options: .atomic)
        } catch {
            Log.project.error("Failed to save generation settings: \(error)")
        }
    }

    func resetSettings() {
        settings = .default
        saveSettings()
    }

    // MARK: - Presets

    func savePreset(name: String) {
        let preset = GenerationSettingsPreset(name: name, settings: settings)
        presets.append(preset)
        savePresets()
    }

    func loadPreset(_ preset: GenerationSettingsPreset) {
        settings = preset.settings
        saveSettings()
    }

    func deletePreset(_ id: UUID) {
        presets.removeAll { $0.id == id }
        savePresets()
    }

    func renamePreset(_ id: UUID, to newName: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = newName
        savePresets()
    }

    // MARK: - Resolution

    /// Resolve effective settings: project override > app defaults
    func effectiveSettings(for project: ScreenizeProject?) -> GenerationSettings {
        project?.generationSettings ?? settings
    }

    // MARK: - Persistence

    private var settingsFileURL: URL {
        Self.appSupportURL.appendingPathComponent("generation_settings.json")
    }

    private var presetsFileURL: URL {
        Self.appSupportURL.appendingPathComponent("generation_presets.json")
    }

    private static var appSupportURL: URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Screenize")
        }
        return appSupport.appendingPathComponent("Screenize")
    }

    private func loadSettings() {
        guard FileManager.default.fileExists(atPath: settingsFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: settingsFileURL)
            settings = try JSONDecoder().decode(GenerationSettings.self, from: data)
        } catch {
            Log.project.error("Failed to load generation settings: \(error)")
        }
    }

    private func loadPresets() {
        guard FileManager.default.fileExists(atPath: presetsFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: presetsFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            presets = try decoder.decode([GenerationSettingsPreset].self, from: data)
        } catch {
            Log.project.error("Failed to load generation presets: \(error)")
        }
    }

    private func savePresets() {
        do {
            let directory = presetsFileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(presets)
            try data.write(to: presetsFileURL, options: .atomic)
        } catch {
            Log.project.error("Failed to save generation presets: \(error)")
        }
    }
}

// MARK: - Preset

struct GenerationSettingsPreset: Codable, Identifiable {
    let id: UUID
    var name: String
    let settings: GenerationSettings
    let createdAt: Date

    init(id: UUID = UUID(), name: String, settings: GenerationSettings, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.settings = settings
        self.createdAt = createdAt
    }
}
```

**Step 2: Add to Xcode project**

Add to `Project` group in pbxproj.

**Step 3: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: add GenerationSettingsManager with persistence and preset support
```

---

### Task 3: Per-Project Override on ScreenizeProject

**Files:**
- Modify: `Screenize/Project/ScreenizeProject.swift`

**Step 1: Add optional generationSettings field**

Add after the `interop` field (line 28):

```swift
// Generation settings override (nil = use app defaults)
var generationSettings: GenerationSettings?
```

Add to `init()` parameter list:

```swift
generationSettings: GenerationSettings? = nil
```

And in the init body:

```swift
self.generationSettings = generationSettings
```

Since `ScreenizeProject` uses auto-synthesized Codable and `GenerationSettings` is already Codable, the field will automatically be decoded when present and default to `nil` when absent in older project files (because it's optional).

**Step 2: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat: add optional generationSettings override to ScreenizeProject
```

---

### Task 4: Factory Init Methods on Existing Settings Structs

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`
- Modify: `Screenize/Generators/SmartGeneration/Planning/ShotPlanner.swift`
- Modify: `Screenize/Generators/SmartGeneration/Emission/CursorTrackEmitter.swift`
- Modify: `Screenize/Generators/KeyframeGenerator.swift`

These factory methods allow existing generator types to be initialized from the unified `GenerationSettings`.

**Step 1: Add init(from:) to ContinuousCameraSettings**

Add at the end of `ContinuousCameraTypes.swift`, after the `ContinuousCameraSettings` struct:

```swift
extension ContinuousCameraSettings {
    /// Initialize from unified GenerationSettings
    init(from gs: GenerationSettings) {
        self.init()
        // Camera motion
        positionDampingRatio = gs.cameraMotion.positionDampingRatio
        positionResponse = gs.cameraMotion.positionResponse
        zoomDampingRatio = gs.cameraMotion.zoomDampingRatio
        zoomResponse = gs.cameraMotion.zoomResponse
        boundaryStiffness = gs.cameraMotion.boundaryStiffness
        zoomSettleThreshold = gs.cameraMotion.zoomSettleThreshold
        urgencyBlendDuration = TimeInterval(gs.cameraMotion.urgencyBlendDuration)
        urgencyMultipliers = [
            .immediate: gs.cameraMotion.urgencyImmediateMultiplier,
            .high: gs.cameraMotion.urgencyHighMultiplier,
            .normal: gs.cameraMotion.urgencyNormalMultiplier,
            .lazy: gs.cameraMotion.urgencyLazyMultiplier
        ]
        // Timing
        tickRate = Double(gs.timing.tickRate)
        typingDetailMinInterval = TimeInterval(gs.timing.typingDetailMinInterval)
        typingDetailMinDistance = gs.timing.typingDetailMinDistance
        // Zoom
        minZoom = gs.zoom.minZoom
        maxZoom = gs.zoom.maxZoom
        zoomIntensity = gs.zoom.zoomIntensity
        // Nested structs
        shot = ShotSettings(from: gs)
        micro = MicroTrackerSettings(from: gs)
        deadZone = DeadZoneSettings(from: gs)
        cursor = CursorEmissionSettings(from: gs)
        keystroke = KeystrokeEmissionSettings(from: gs)
    }
}

extension MicroTrackerSettings {
    init(from gs: GenerationSettings) {
        self.init()
        idleVelocityThreshold = gs.cameraMotion.idleVelocityThreshold
        dampingRatio = gs.cameraMotion.microTrackerDampingRatio
        response = gs.cameraMotion.microTrackerResponse
    }
}

extension DeadZoneSettings {
    init(from gs: GenerationSettings) {
        self.init()
        safeZoneFraction = gs.cameraMotion.safeZoneFraction
        safeZoneFractionTyping = gs.cameraMotion.safeZoneFractionTyping
        gradientBandWidth = gs.cameraMotion.gradientBandWidth
        correctionFraction = gs.cameraMotion.correctionFraction
        hysteresisMargin = gs.cameraMotion.hysteresisMargin
        correctionFractionTyping = gs.cameraMotion.correctionFractionTyping
        minResponse = gs.cameraMotion.deadZoneMinResponse
        maxResponse = gs.cameraMotion.deadZoneMaxResponse
        responseFastThreshold = TimeInterval(gs.timing.responseFastThreshold)
        responseSlowThreshold = TimeInterval(gs.timing.responseSlowThreshold)
    }
}
```

**Step 2: Add init(from:) to ShotSettings**

Add at end of `ShotPlanner.swift`:

```swift
extension ShotSettings {
    init(from gs: GenerationSettings) {
        self.init()
        typingCodeZoomRange = gs.zoom.typingCodeZoomMin...gs.zoom.typingCodeZoomMax
        typingTextFieldZoomRange = gs.zoom.typingTextFieldZoomMin...gs.zoom.typingTextFieldZoomMax
        typingTerminalZoomRange = gs.zoom.typingTerminalZoomMin...gs.zoom.typingTerminalZoomMax
        typingRichTextZoomRange = gs.zoom.typingRichTextZoomMin...gs.zoom.typingRichTextZoomMax
        clickingZoomRange = gs.zoom.clickingZoomMin...gs.zoom.clickingZoomMax
        navigatingZoomRange = gs.zoom.navigatingZoomMin...gs.zoom.navigatingZoomMax
        draggingZoomRange = gs.zoom.draggingZoomMin...gs.zoom.draggingZoomMax
        scrollingZoomRange = gs.zoom.scrollingZoomMin...gs.zoom.scrollingZoomMax
        readingZoomRange = gs.zoom.readingZoomMin...gs.zoom.readingZoomMax
        switchingZoom = gs.zoom.switchingZoom
        idleZoom = gs.zoom.idleZoom
        targetAreaCoverage = gs.zoom.targetAreaCoverage
        workAreaPadding = gs.zoom.workAreaPadding
        minZoom = gs.zoom.minZoom
        maxZoom = gs.zoom.maxZoom
        idleZoomDecay = gs.zoom.idleZoomDecay
    }
}
```

**Step 3: Add init(from:) to CursorEmissionSettings**

Add at end of `CursorTrackEmitter.swift`:

```swift
extension CursorEmissionSettings {
    init(from gs: GenerationSettings) {
        self.init()
        cursorScale = gs.cursorKeystroke.cursorScale
    }
}
```

**Step 4: Add init(from:) to KeystrokeEmissionSettings**

Add at end of `KeyframeGenerator.swift` (or near the `KeystrokeEmissionSettings` definition):

```swift
extension KeystrokeEmissionSettings {
    init(from gs: GenerationSettings) {
        self.init()
        enabled = gs.cursorKeystroke.keystrokeEnabled
        shortcutsOnly = gs.cursorKeystroke.shortcutsOnly
        displayDuration = TimeInterval(gs.cursorKeystroke.displayDuration)
        fadeInDuration = TimeInterval(gs.cursorKeystroke.fadeInDuration)
        fadeOutDuration = TimeInterval(gs.cursorKeystroke.fadeOutDuration)
        minInterval = TimeInterval(gs.cursorKeystroke.minInterval)
    }
}
```

**Step 5: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```
feat: add init(from: GenerationSettings) factories to all generator settings structs
```

---

### Task 5: Refactor IntentClassifier to Accept Settings

**Files:**
- Modify: `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift`
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraGenerator.swift`

Currently `IntentClassifier` uses static constants. We need to make it accept `IntentClassificationSettings` while keeping the static constants as fallback defaults.

**Step 1: Add settings parameter to IntentClassifier.classify**

In `IntentClassifier.swift`, change the `classify` method signature to accept settings:

```swift
static func classify(
    events timeline: EventTimeline,
    uiStateSamples: [UIStateSample],
    settings: IntentClassificationSettings = IntentClassificationSettings()
) -> [IntentSpan] {
```

Then replace all references to `Self.typingSessionTimeout` etc. within the `classify` method and any private helper methods with `settings.typingSessionTimeout` etc.

The static constants remain as documentation but the method now uses the passed-in settings. Since the parameter has a default value, all existing call sites continue to compile without changes.

However, we need to thread settings from `ContinuousCameraGenerator`. The tricky part: the static helpers that use these constants need access to the settings. The cleanest approach is to make the helpers accept the settings parameter too.

Specifically, replace each `Self.<constant>` reference with the corresponding `settings.<property>`. The constants are used in the `classify` method body and any private static helpers it calls. Pass `settings` through to those helpers.

**Step 2: Update ContinuousCameraGenerator to pass intent settings**

In `ContinuousCameraGenerator.swift`, the `classify` call (line 47-50) becomes:

```swift
let intentSettings = IntentClassificationSettings.from(settings)
let intentSpans = IntentClassifier.classify(
    events: timeline,
    uiStateSamples: uiStateSamples,
    settings: intentSettings
)
```

But wait — `ContinuousCameraGenerator` receives `ContinuousCameraSettings`, not `GenerationSettings`. We need to thread intent classification settings through. Two options:

**Option A:** Add `intentClassification: IntentClassificationSettings` to `ContinuousCameraSettings`
**Option B:** Pass `GenerationSettings` directly to `ContinuousCameraGenerator`

**Option A is better** (minimal API change). Add to `ContinuousCameraSettings`:

```swift
var intentClassification = IntentClassificationSettings()
```

And in the `init(from gs: GenerationSettings)` extension (Task 4), add:

```swift
intentClassification = gs.intentClassification
```

Then in `ContinuousCameraGenerator.generate()`:

```swift
let intentSpans = IntentClassifier.classify(
    events: timeline,
    uiStateSamples: uiStateSamples,
    settings: settings.intentClassification
)
```

**Step 3: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
refactor: make IntentClassifier accept configurable settings
```

---

### Task 6: Refactor WaypointGenerator Lead Times

**Files:**
- Modify: `Screenize/Generators/ContinuousCamera/WaypointGenerator.swift`
- Modify: `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift`

**Step 1: Add lead time settings to ContinuousCameraSettings**

In `ContinuousCameraTypes.swift`, add to `ContinuousCameraSettings`:

```swift
var leadTimeImmediate: TimeInterval = 0.24
var leadTimeHigh: TimeInterval = 0.16
var leadTimeNormal: TimeInterval = 0.08
var leadTimeLazy: TimeInterval = 0.0
```

Update the `init(from gs: GenerationSettings)` extension:

```swift
leadTimeImmediate = TimeInterval(gs.timing.leadTimeImmediate)
leadTimeHigh = TimeInterval(gs.timing.leadTimeHigh)
leadTimeNormal = TimeInterval(gs.timing.leadTimeNormal)
leadTimeLazy = TimeInterval(gs.timing.leadTimeLazy)
```

**Step 2: Refactor WaypointGenerator.entryLeadTime**

Change the private static method to use settings. The `generate` method already receives `ContinuousCameraSettings`. Change `entryLeadTime` to accept settings:

```swift
private static func entryLeadTime(
    for urgency: WaypointUrgency,
    settings: ContinuousCameraSettings
) -> TimeInterval {
    switch urgency {
    case .immediate: return settings.leadTimeImmediate
    case .high: return settings.leadTimeHigh
    case .normal: return settings.leadTimeNormal
    case .lazy: return settings.leadTimeLazy
    }
}
```

Update all call sites of `entryLeadTime` within `WaypointGenerator` to pass `settings`.

**Step 3: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
refactor: make WaypointGenerator lead times configurable via settings
```

---

### Task 7: Wire GenerationSettings into EditorViewModel

**Files:**
- Modify: `Screenize/ViewModels/EditorViewModel+SmartGeneration.swift`

**Step 1: Update runSmartZoomGeneration to use resolved settings**

Replace the settings construction at line 62:

```swift
// Before:
var ccSettings = ContinuousCameraSettings()
ccSettings.springConfig = springConfig

// After:
let generationSettings = GenerationSettingsManager.shared.effectiveSettings(for: project)
var ccSettings = ContinuousCameraSettings(from: generationSettings)
ccSettings.springConfig = springConfig
```

This resolves project-level overrides vs app defaults, then builds the internal settings structs from the unified config.

**Step 2: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat: wire GenerationSettings into smart generation pipeline
```

---

### Task 8: Settings Window UI — Shell and Section Layout

**Files:**
- Create: `Screenize/Views/Settings/GenerationSettingsView.swift`
- Create: `Screenize/Views/Settings/GenerationSettingsWindowController.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj`

**Step 1: Create GenerationSettingsWindowController.swift**

A lightweight window controller that creates/shows a single NSWindow:

```swift
import SwiftUI
import AppKit

/// Manages the singleton Advanced Generation Settings window.
@MainActor
final class GenerationSettingsWindowController {

    static let shared = GenerationSettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = GenerationSettingsView()
            .environmentObject(GenerationSettingsManager.shared)

        let hostingController = NSHostingController(rootView: settingsView)
        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Advanced Generation Settings"
        newWindow.styleMask = [.titled, .closable, .resizable]
        newWindow.setContentSize(NSSize(width: 520, height: 700))
        newWindow.minSize = NSSize(width: 420, height: 400)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
}
```

**Step 2: Create GenerationSettingsView.swift**

The main settings view with top bar (scope toggle, presets, regenerate) and 5 collapsible sections.

```swift
import SwiftUI

struct GenerationSettingsView: View {
    @EnvironmentObject private var manager: GenerationSettingsManager
    @State private var scope: SettingsScope = .appDefaults
    @State private var showSavePresetSheet = false
    @State private var presetName = ""

    enum SettingsScope: String, CaseIterable {
        case appDefaults = "App Defaults"
        case thisProject = "This Project"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar
            Divider()
            // Scrollable sections
            ScrollView {
                VStack(spacing: 12) {
                    cameraMotionSection
                    zoomSection
                    intentClassificationSection
                    timingSection
                    cursorKeystrokeSection
                }
                .padding()
            }
        }
        .frame(minWidth: 420, minHeight: 400)
        .sheet(isPresented: $showSavePresetSheet) {
            savePresetSheet
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Scope picker
            Picker("", selection: $scope) {
                ForEach(SettingsScope.allCases, id: \.self) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Spacer()

            // Presets menu
            Menu {
                Button("Save as Preset...") {
                    presetName = ""
                    showSavePresetSheet = true
                }
                if !manager.presets.isEmpty {
                    Divider()
                    ForEach(manager.presets) { preset in
                        Button(preset.name) {
                            manager.loadPreset(preset)
                        }
                    }
                    Divider()
                    Menu("Delete Preset") {
                        ForEach(manager.presets) { preset in
                            Button(preset.name, role: .destructive) {
                                manager.deletePreset(preset.id)
                            }
                        }
                    }
                }
            } label: {
                Label("Presets", systemImage: "archivebox")
            }

            // Regenerate button
            Button {
                NotificationCenter.default.post(name: .regenerateTimeline, object: nil)
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Sections

    private var cameraMotionSection: some View {
        SettingsSection(title: "Camera Motion") {
            SettingSlider(label: "Position Damping", value: $manager.settings.cameraMotion.positionDampingRatio, range: 0.1...1.0, defaultValue: 0.90)
            SettingSlider(label: "Position Response", value: $manager.settings.cameraMotion.positionResponse, range: 0.05...2.0, defaultValue: 0.35, unit: "s")
            SettingSlider(label: "Zoom Damping", value: $manager.settings.cameraMotion.zoomDampingRatio, range: 0.1...1.0, defaultValue: 0.90)
            SettingSlider(label: "Zoom Response", value: $manager.settings.cameraMotion.zoomResponse, range: 0.05...2.0, defaultValue: 0.55, unit: "s")
            SettingSlider(label: "Boundary Stiffness", value: $manager.settings.cameraMotion.boundaryStiffness, range: 1.0...30.0, defaultValue: 12.0)
            SettingSlider(label: "Zoom Settle Threshold", value: $manager.settings.cameraMotion.zoomSettleThreshold, range: 0.001...0.1, defaultValue: 0.02)

            Divider()
            Text("Urgency Multipliers").font(.caption).foregroundColor(.secondary)
            SettingSlider(label: "Immediate", value: $manager.settings.cameraMotion.urgencyImmediateMultiplier, range: 0.01...1.0, defaultValue: 0.05)
            SettingSlider(label: "High", value: $manager.settings.cameraMotion.urgencyHighMultiplier, range: 0.1...2.0, defaultValue: 0.5)
            SettingSlider(label: "Normal", value: $manager.settings.cameraMotion.urgencyNormalMultiplier, range: 0.5...3.0, defaultValue: 1.0)
            SettingSlider(label: "Lazy", value: $manager.settings.cameraMotion.urgencyLazyMultiplier, range: 1.0...5.0, defaultValue: 2.0)
            SettingSlider(label: "Blend Duration", value: $manager.settings.cameraMotion.urgencyBlendDuration, range: 0.1...2.0, defaultValue: 0.5, unit: "s")

            Divider()
            Text("Dead Zone").font(.caption).foregroundColor(.secondary)
            SettingSlider(label: "Safe Zone Fraction", value: $manager.settings.cameraMotion.safeZoneFraction, range: 0.3...1.0, defaultValue: 0.75)
            SettingSlider(label: "Safe Zone (Typing)", value: $manager.settings.cameraMotion.safeZoneFractionTyping, range: 0.3...1.0, defaultValue: 0.60)
            SettingSlider(label: "Gradient Band Width", value: $manager.settings.cameraMotion.gradientBandWidth, range: 0.05...0.5, defaultValue: 0.25)
            SettingSlider(label: "Correction Fraction", value: $manager.settings.cameraMotion.correctionFraction, range: 0.1...1.0, defaultValue: 0.45)
            SettingSlider(label: "Hysteresis Margin", value: $manager.settings.cameraMotion.hysteresisMargin, range: 0.01...0.5, defaultValue: 0.15)
            SettingSlider(label: "Correction (Typing)", value: $manager.settings.cameraMotion.correctionFractionTyping, range: 0.1...1.0, defaultValue: 0.80)
            SettingSlider(label: "Min Response", value: $manager.settings.cameraMotion.deadZoneMinResponse, range: 0.05...1.0, defaultValue: 0.20, unit: "s")
            SettingSlider(label: "Max Response", value: $manager.settings.cameraMotion.deadZoneMaxResponse, range: 0.1...2.0, defaultValue: 0.50, unit: "s")

            Divider()
            Text("Micro Tracker").font(.caption).foregroundColor(.secondary)
            SettingSlider(label: "Idle Velocity Threshold", value: $manager.settings.cameraMotion.idleVelocityThreshold, range: 0.001...0.1, defaultValue: 0.02)
            SettingSlider(label: "Damping Ratio", value: $manager.settings.cameraMotion.microTrackerDampingRatio, range: 0.1...2.0, defaultValue: 1.0)
            SettingSlider(label: "Response", value: $manager.settings.cameraMotion.microTrackerResponse, range: 0.5...10.0, defaultValue: 3.0, unit: "s")
        }
    }

    private var zoomSection: some View {
        SettingsSection(title: "Zoom Levels") {
            Text("Per-Activity Zoom Ranges").font(.caption).foregroundColor(.secondary)
            RangeSettingSlider(label: "Typing (Code)", min: $manager.settings.zoom.typingCodeZoomMin, max: $manager.settings.zoom.typingCodeZoomMax, range: 1.0...4.0, defaultMin: 2.0, defaultMax: 2.5)
            RangeSettingSlider(label: "Typing (Text Field)", min: $manager.settings.zoom.typingTextFieldZoomMin, max: $manager.settings.zoom.typingTextFieldZoomMax, range: 1.0...4.0, defaultMin: 2.2, defaultMax: 2.8)
            RangeSettingSlider(label: "Typing (Terminal)", min: $manager.settings.zoom.typingTerminalZoomMin, max: $manager.settings.zoom.typingTerminalZoomMax, range: 1.0...4.0, defaultMin: 1.6, defaultMax: 2.0)
            RangeSettingSlider(label: "Typing (Rich Text)", min: $manager.settings.zoom.typingRichTextZoomMin, max: $manager.settings.zoom.typingRichTextZoomMax, range: 1.0...4.0, defaultMin: 1.8, defaultMax: 2.2)
            RangeSettingSlider(label: "Clicking", min: $manager.settings.zoom.clickingZoomMin, max: $manager.settings.zoom.clickingZoomMax, range: 1.0...4.0, defaultMin: 1.5, defaultMax: 2.5)
            RangeSettingSlider(label: "Navigating", min: $manager.settings.zoom.navigatingZoomMin, max: $manager.settings.zoom.navigatingZoomMax, range: 1.0...4.0, defaultMin: 1.5, defaultMax: 1.8)
            RangeSettingSlider(label: "Dragging", min: $manager.settings.zoom.draggingZoomMin, max: $manager.settings.zoom.draggingZoomMax, range: 1.0...4.0, defaultMin: 1.3, defaultMax: 1.6)
            RangeSettingSlider(label: "Scrolling", min: $manager.settings.zoom.scrollingZoomMin, max: $manager.settings.zoom.scrollingZoomMax, range: 1.0...4.0, defaultMin: 1.3, defaultMax: 1.5)
            RangeSettingSlider(label: "Reading", min: $manager.settings.zoom.readingZoomMin, max: $manager.settings.zoom.readingZoomMax, range: 1.0...4.0, defaultMin: 1.0, defaultMax: 1.3)

            Divider()
            Text("Fixed Zoom Levels").font(.caption).foregroundColor(.secondary)
            SettingSlider(label: "Switching", value: $manager.settings.zoom.switchingZoom, range: 0.5...3.0, defaultValue: 1.0)
            SettingSlider(label: "Idle", value: $manager.settings.zoom.idleZoom, range: 0.5...3.0, defaultValue: 1.0)

            Divider()
            Text("Global Limits").font(.caption).foregroundColor(.secondary)
            SettingSlider(label: "Target Area Coverage", value: $manager.settings.zoom.targetAreaCoverage, range: 0.3...1.0, defaultValue: 0.7)
            SettingSlider(label: "Work Area Padding", value: $manager.settings.zoom.workAreaPadding, range: 0.0...0.3, defaultValue: 0.08)
            SettingSlider(label: "Min Zoom", value: $manager.settings.zoom.minZoom, range: 0.5...2.0, defaultValue: 1.0)
            SettingSlider(label: "Max Zoom", value: $manager.settings.zoom.maxZoom, range: 1.5...5.0, defaultValue: 2.8)
            SettingSlider(label: "Idle Zoom Decay", value: $manager.settings.zoom.idleZoomDecay, range: 0.0...1.0, defaultValue: 0.5)
            SettingSlider(label: "Zoom Intensity", value: $manager.settings.zoom.zoomIntensity, range: 0.0...3.0, defaultValue: 1.0)
        }
    }

    private var intentClassificationSection: some View {
        SettingsSection(title: "Intent Classification") {
            SettingSlider(label: "Typing Session Timeout", value: $manager.settings.intentClassification.typingSessionTimeout, range: 0.5...5.0, defaultValue: 1.5, unit: "s")
            SettingSlider(label: "Navigating Click Window", value: $manager.settings.intentClassification.navigatingClickWindow, range: 0.5...5.0, defaultValue: 2.0, unit: "s")
            SettingSlider(label: "Navigating Click Distance", value: $manager.settings.intentClassification.navigatingClickDistance, range: 0.1...1.0, defaultValue: 0.5)
            SettingStepper(label: "Navigating Min Clicks", value: $manager.settings.intentClassification.navigatingMinClicks, range: 1...10, defaultValue: 2)
            SettingSlider(label: "Idle Threshold", value: $manager.settings.intentClassification.idleThreshold, range: 1.0...15.0, defaultValue: 5.0, unit: "s")
            SettingSlider(label: "Continuation Gap", value: $manager.settings.intentClassification.continuationGapThreshold, range: 0.5...5.0, defaultValue: 1.5, unit: "s")
            SettingSlider(label: "Continuation Max Distance", value: $manager.settings.intentClassification.continuationMaxDistance, range: 0.05...0.5, defaultValue: 0.20)
            SettingSlider(label: "Scroll Merge Gap", value: $manager.settings.intentClassification.scrollMergeGap, range: 0.2...3.0, defaultValue: 1.0, unit: "s")
            SettingSlider(label: "Point Span Duration", value: $manager.settings.intentClassification.pointSpanDuration, range: 0.1...2.0, defaultValue: 0.5, unit: "s")
            SettingSlider(label: "Context Change Window", value: $manager.settings.intentClassification.contextChangeWindow, range: 0.2...3.0, defaultValue: 0.8, unit: "s")
            SettingSlider(label: "Typing Anticipation", value: $manager.settings.intentClassification.typingAnticipation, range: 0.0...1.5, defaultValue: 0.4, unit: "s")
        }
    }

    private var timingSection: some View {
        SettingsSection(title: "Timing") {
            Text("Lead Times").font(.caption).foregroundColor(.secondary)
            SettingSlider(label: "Immediate", value: $manager.settings.timing.leadTimeImmediate, range: 0.0...1.0, defaultValue: 0.24, unit: "s")
            SettingSlider(label: "High", value: $manager.settings.timing.leadTimeHigh, range: 0.0...1.0, defaultValue: 0.16, unit: "s")
            SettingSlider(label: "Normal", value: $manager.settings.timing.leadTimeNormal, range: 0.0...1.0, defaultValue: 0.08, unit: "s")
            SettingSlider(label: "Lazy", value: $manager.settings.timing.leadTimeLazy, range: 0.0...1.0, defaultValue: 0.0, unit: "s")

            Divider()
            Text("Simulation").font(.caption).foregroundColor(.secondary)
            SettingSlider(label: "Tick Rate", value: $manager.settings.timing.tickRate, range: 24.0...120.0, defaultValue: 60.0, unit: "Hz")
            SettingSlider(label: "Typing Detail Min Interval", value: $manager.settings.timing.typingDetailMinInterval, range: 0.05...1.0, defaultValue: 0.2, unit: "s")
            SettingSlider(label: "Typing Detail Min Distance", value: $manager.settings.timing.typingDetailMinDistance, range: 0.005...0.1, defaultValue: 0.025)

            Divider()
            Text("Response Thresholds").font(.caption).foregroundColor(.secondary)
            SettingSlider(label: "Fast Threshold", value: $manager.settings.timing.responseFastThreshold, range: 0.1...2.0, defaultValue: 0.5, unit: "s")
            SettingSlider(label: "Slow Threshold", value: $manager.settings.timing.responseSlowThreshold, range: 1.0...5.0, defaultValue: 2.0, unit: "s")
        }
    }

    private var cursorKeystrokeSection: some View {
        SettingsSection(title: "Cursor & Keystroke") {
            SettingSlider(label: "Cursor Scale", value: $manager.settings.cursorKeystroke.cursorScale, range: 0.5...5.0, defaultValue: 2.0, unit: "x")

            Divider()
            Text("Keystroke Overlay").font(.caption).foregroundColor(.secondary)
            Toggle("Enabled", isOn: $manager.settings.cursorKeystroke.keystrokeEnabled)
            Toggle("Shortcuts Only", isOn: $manager.settings.cursorKeystroke.shortcutsOnly)
            SettingSlider(label: "Display Duration", value: $manager.settings.cursorKeystroke.displayDuration, range: 0.5...5.0, defaultValue: 1.5, unit: "s")
            SettingSlider(label: "Fade In", value: $manager.settings.cursorKeystroke.fadeInDuration, range: 0.0...1.0, defaultValue: 0.15, unit: "s")
            SettingSlider(label: "Fade Out", value: $manager.settings.cursorKeystroke.fadeOutDuration, range: 0.0...1.0, defaultValue: 0.3, unit: "s")
            SettingSlider(label: "Min Interval", value: $manager.settings.cursorKeystroke.minInterval, range: 0.01...0.5, defaultValue: 0.05, unit: "s")
        }
    }

    // MARK: - Save Preset Sheet

    private var savePresetSheet: some View {
        VStack(spacing: 16) {
            Text("Save Preset").font(.headline)
            TextField("Preset Name", text: $presetName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { showSavePresetSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard !presetName.isEmpty else { return }
                    manager.savePreset(name: presetName)
                    showSavePresetSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(presetName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

// MARK: - Notification

extension Notification.Name {
    static let regenerateTimeline = Notification.Name("regenerateTimeline")
}
```

**Step 3: Add to Xcode project**

Create the `Screenize/Views/Settings/` directory. Add both files to pbxproj under a new `Settings` group inside `Views`.

**Step 4: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```
feat: add Advanced Generation Settings window with 5 collapsible sections
```

---

### Task 9: Reusable Setting Control Components

**Files:**
- Create: `Screenize/Views/Settings/SettingControls.swift`
- Modify: `Screenize.xcodeproj/project.pbxproj`

**Step 1: Create SettingControls.swift**

Shared components: `SettingsSection`, `SettingSlider` (with reset), `RangeSettingSlider`, `SettingStepper`.

```swift
import SwiftUI

// MARK: - Collapsible Section

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(title, isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Slider with Reset

struct SettingSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let defaultValue: CGFloat
    var unit: String = ""
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 160, alignment: .leading)
                .font(.system(size: 11))

            Slider(value: $value, in: range)
                .frame(minWidth: 100)

            Text(formattedValue)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 60, alignment: .trailing)

            Button {
                value = defaultValue
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .opacity(isHovering && value != defaultValue ? 1.0 : 0.0)
        }
        .onHover { isHovering = $0 }
    }

    private var formattedValue: String {
        if unit.isEmpty {
            return String(format: "%.3f", value)
        }
        return String(format: "%.2f", value) + unit
    }
}

// MARK: - Range Slider (Dual Value)

struct RangeSettingSlider: View {
    let label: String
    @Binding var min: CGFloat
    @Binding var max: CGFloat
    let range: ClosedRange<CGFloat>
    let defaultMin: CGFloat
    let defaultMax: CGFloat
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(label)
                    .frame(width: 160, alignment: .leading)
                    .font(.system(size: 11))

                Text(String(format: "%.1f – %.1f", min, max))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    min = defaultMin
                    max = defaultMax
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .opacity(isHovering && (min != defaultMin || max != defaultMax) ? 1.0 : 0.0)
            }
            HStack(spacing: 8) {
                Text("Min")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                Slider(value: $min, in: range.lowerBound...max)
                    .frame(minWidth: 80)
                Text("Max")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 28)
                Slider(value: $max, in: min...range.upperBound)
                    .frame(minWidth: 80)
            }
        }
        .onHover { isHovering = $0 }
    }
}

// MARK: - Stepper with Reset

struct SettingStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let defaultValue: Int
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 160, alignment: .leading)
                .font(.system(size: 11))

            Stepper(value: $value, in: range) {
                Text("\(value)")
                    .font(.system(size: 11, design: .monospaced))
            }

            Spacer()

            Button {
                value = defaultValue
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .opacity(isHovering && value != defaultValue ? 1.0 : 0.0)
        }
        .onHover { isHovering = $0 }
    }
}
```

**Step 2: Add to Xcode project**

Add to the `Settings` group in pbxproj.

**Step 3: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: add reusable setting control components (slider, range slider, stepper with reset)
```

---

### Task 10: Menu Bar Item and Toolbar Access

**Files:**
- Modify: `Screenize/ScreenizeApp.swift`
- Modify: `Screenize/Views/EditorMainView.swift`
- Modify: `Screenize/ViewModels/EditorViewModel+SmartGeneration.swift` (regenerate notification)
- Modify: `Screenize.xcodeproj/project.pbxproj` (if new files were created)

**Step 1: Add menu bar item**

In `ScreenizeApp.swift`, add a new `CommandGroup` after the existing ones inside `.commands { }`:

```swift
// After the CommandGroup(replacing: .newItem) block
CommandGroup(after: .appSettings) {
    Button("Advanced Generation Settings...") {
        GenerationSettingsWindowController.shared.showWindow()
    }
    .keyboardShortcut(",", modifiers: [.command, .option])
}
```

This places it in the app menu near Preferences (Cmd+Option+, shortcut).

**Step 2: Add toolbar button in editor**

In `EditorMainView.swift`, add a gear button near the Smart Generation button (around line 192-298 in the toolbar). Add it right after the Smart Generation button:

```swift
Button {
    GenerationSettingsWindowController.shared.showWindow()
} label: {
    Image(systemName: "gearshape.2")
}
.help("Advanced Generation Settings")
```

**Step 3: Handle regenerate notification**

In `EditorViewModel+SmartGeneration.swift` or in the view that owns the EditorViewModel, observe the `.regenerateTimeline` notification and trigger `runSmartGeneration()`.

The simplest place is in the EditorMainView (or wherever the EditorViewModel is owned). Add an `.onReceive` modifier:

```swift
.onReceive(NotificationCenter.default.publisher(for: .regenerateTimeline)) { _ in
    Task {
        await viewModel.runSmartGeneration()
    }
}
```

**Step 4: Auto-save settings on change**

In `GenerationSettingsView`, add an `onChange` to auto-save when settings change:

```swift
.onChange(of: manager.settings) { _ in
    manager.saveSettings()
}
```

**Step 5: Handle scope toggle (This Project)**

When scope is "This Project", the view should read/write to the project's `generationSettings` override instead of the manager's app-level settings. This requires the view to receive an optional binding to the project's settings.

Add to `GenerationSettingsView`:

```swift
// Add property
@EnvironmentObject private var appState: AppState

// In scope toggle onChange, switch the binding source:
// When "This Project" is selected and a project is open,
// copy app settings to project if project has no override yet,
// then edit the project copy.
```

This is the most complex UI wiring. The approach:
- "App Defaults" scope: reads/writes `manager.settings`
- "This Project" scope: reads/writes a project-level override (communicated via NotificationCenter or a shared binding)

For simplicity in v1, the scope toggle can post a notification with the current settings to apply to the project, and the EditorViewModel handles the storage. Keep this minimal.

**Step 6: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 7: Commit**

```
feat: add menu bar item and toolbar button for Advanced Generation Settings
```

---

### Task 11: Project Scope Wiring

**Files:**
- Modify: `Screenize/Views/Settings/GenerationSettingsView.swift`
- Modify: `Screenize/ViewModels/EditorViewModel+SmartGeneration.swift`

**Step 1: Wire project-scope editing**

When the user selects "This Project" scope:
1. If the current project has no `generationSettings`, initialize it from app defaults
2. The settings view edits the project's `generationSettings` directly
3. On save, the project is marked as having unsaved changes

This requires the settings view to know about the current project. Pass the project binding via environment or notification.

The cleanest approach: `GenerationSettingsWindowController.showWindow()` accepts an optional `Binding<ScreenizeProject>`. When provided, the scope toggle is enabled and "This Project" edits the project's settings. When nil, "This Project" is disabled/hidden.

Update `GenerationSettingsView` to accept an optional project binding:

```swift
@Binding var project: ScreenizeProject?

var editingSettings: Binding<GenerationSettings> {
    switch scope {
    case .appDefaults:
        return $manager.settings
    case .thisProject:
        return Binding(
            get: { project?.generationSettings ?? manager.settings },
            set: { newValue in
                project?.generationSettings = newValue
            }
        )
    }
}
```

Then replace all `$manager.settings` references in the sections with `editingSettings`.

**Step 2: Disable "This Project" when no project open**

```swift
Picker("", selection: $scope) {
    Text("App Defaults").tag(SettingsScope.appDefaults)
    Text("This Project").tag(SettingsScope.thisProject)
}
.disabled(project == nil && scope == .thisProject)
```

**Step 3: Build verification**

Run: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: wire project-scope settings editing in Advanced Generation Settings
```

---

### Task 12: Final Integration and Polish

**Files:**
- All previously modified files (verification pass)

**Step 1: End-to-end verification**

1. Build the project: `xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build`
2. Verify the menu item appears in the app menu
3. Verify the settings window opens with all 5 sections
4. Verify sliders move and reset buttons work
5. Verify presets can be saved and loaded
6. Verify "Regenerate" triggers generation
7. Verify project-scope toggle works when a project is open

**Step 2: Lint check**

Run: `./scripts/lint.sh`
Fix any new violations (line length is the most common — keep lines under 140 chars).

**Step 3: Commit any fixes**

```
fix: address lint violations in generation settings
```

---

## File Inventory

### New Files (6)
| File | Purpose |
|------|---------|
| `Screenize/Generators/GenerationSettings.swift` | Data model (5 nested Codable structs) |
| `Screenize/Project/GenerationSettingsManager.swift` | Persistence singleton + presets |
| `Screenize/Views/Settings/GenerationSettingsView.swift` | Main settings window UI |
| `Screenize/Views/Settings/GenerationSettingsWindowController.swift` | NSWindow management |
| `Screenize/Views/Settings/SettingControls.swift` | Reusable UI components |

### Modified Files (8)
| File | Change |
|------|--------|
| `Screenize/Project/ScreenizeProject.swift` | Add optional `generationSettings` field |
| `Screenize/Generators/ContinuousCamera/ContinuousCameraTypes.swift` | Add `init(from:)` factories, lead time props, intent settings |
| `Screenize/Generators/SmartGeneration/Planning/ShotPlanner.swift` | Add `init(from:)` factory |
| `Screenize/Generators/SmartGeneration/Emission/CursorTrackEmitter.swift` | Add `init(from:)` factory |
| `Screenize/Generators/KeyframeGenerator.swift` | Add `init(from:)` factory |
| `Screenize/Generators/SmartGeneration/Analysis/IntentClassifier.swift` | Accept settings parameter |
| `Screenize/Generators/ContinuousCamera/WaypointGenerator.swift` | Use configurable lead times |
| `Screenize/ViewModels/EditorViewModel+SmartGeneration.swift` | Resolve and apply GenerationSettings |
| `Screenize/ScreenizeApp.swift` | Add menu bar item |
| `Screenize/Views/EditorMainView.swift` | Add toolbar button + regenerate handler |
| `Screenize.xcodeproj/project.pbxproj` | Add all new file references |

### Dependency Order
```
Task 1 (data model) → Task 2 (manager) → Task 3 (project field)
    ↓
Task 4 (factory inits) → Task 5 (IntentClassifier) → Task 6 (WaypointGenerator)
    ↓
Task 7 (EditorViewModel wiring)
    ↓
Task 9 (setting controls) → Task 8 (settings window) → Task 10 (menu/toolbar)
    ↓
Task 11 (project scope) → Task 12 (polish)
```

Tasks 1-3 and Tasks 8-9 can run in parallel. Tasks 4-6 depend on Task 1. Task 7 depends on Tasks 2-6. Tasks 10-12 are sequential.
