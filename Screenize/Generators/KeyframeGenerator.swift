import Foundation

/// Keyframe generator protocol
/// Automatically creates editable keyframes by analyzing mouse data
protocol KeyframeGenerator {
    associatedtype Output: Track

    /// Generator name
    var name: String { get }

    /// Generator description
    var description: String { get }

    /// Generate keyframes
    /// - Parameters:
    ///   - mouseData: Mouse data
    ///   - settings: Generator settings
    /// - Returns: Track containing generated keyframes
    func generate(from mouseData: MouseDataSource, settings: GeneratorSettings) -> Output

    /// Generate keyframes with statistics
    /// - Parameters:
    ///   - mouseData: Mouse data
    ///   - settings: Generator settings
    /// - Returns: Generation result (track + statistics)
    func generateWithStatistics(from mouseData: MouseDataSource, settings: GeneratorSettings) -> GeneratorResult<Output>
}

// MARK: - Default Implementation

extension KeyframeGenerator {
    /// Default implementation for generating statistics
    /// Override this method when custom statistics are required
    func generateWithStatistics(
        from mouseData: MouseDataSource,
        settings: GeneratorSettings
    ) -> GeneratorResult<Output> {
        let startTime = Date()
        let track = generate(from: mouseData, settings: settings)
        let processingTime = Date().timeIntervalSince(startTime)

        let statistics = GeneratorStatistics(
            analyzedEvents: mouseData.positions.count + mouseData.clicks.count,
            generatedKeyframes: track.keyframeCount,
            processingTime: processingTime,
            additionalInfo: [:]
        )

        return GeneratorResult(
            track: track,
            keyframeCount: track.keyframeCount,
            statistics: statistics
        )
    }
}

// MARK: - Mouse Data Source

/// Mouse data source protocol
/// Abstracts various forms of mouse data
protocol MouseDataSource {
    /// Total duration (seconds)
    var duration: TimeInterval { get }

    /// Frame rate
    var frameRate: Double { get }

    /// Mouse position data
    var positions: [MousePositionData] { get }

    /// Click events
    var clicks: [ClickEventData] { get }

    /// Keyboard events (for typing detection)
    var keyboardEvents: [KeyboardEventData] { get }

    /// Drag events
    var dragEvents: [DragEventData] { get }
}

// MARK: - Mouse Position Data

/// Mouse position data
struct MousePositionData {
    /// Time (seconds)
    let time: TimeInterval

    /// Position (normalized 0-1, top-left origin)
    let position: NormalizedPoint

    /// App bundle ID (if available)
    let appBundleID: String?

    /// UI element info (if available)
    let elementInfo: UIElementInfo?

    // MARK: - Computed Properties (backward compatibility)

    /// X coordinate (normalized 0-1)
    var x: CGFloat { position.x }

    /// Y coordinate (normalized 0-1)
    var y: CGFloat { position.y }

    // MARK: - Initialization

    init(time: TimeInterval, position: NormalizedPoint, appBundleID: String? = nil, elementInfo: UIElementInfo? = nil) {
        self.time = time
        self.position = position
        self.appBundleID = appBundleID
        self.elementInfo = elementInfo
    }

    /// Backward compatibility initializer
    init(time: TimeInterval, x: CGFloat, y: CGFloat, appBundleID: String? = nil, elementInfo: UIElementInfo? = nil) {
        self.init(
            time: time,
            position: NormalizedPoint(x: x, y: y),
            appBundleID: appBundleID,
            elementInfo: elementInfo
        )
    }
}

// MARK: - Click Event Data

/// Click event data
struct ClickEventData {
    /// Time (seconds)
    let time: TimeInterval

    /// Position (normalized 0-1, top-left origin)
    let position: NormalizedPoint

    /// Click type
    let clickType: ClickType

    /// App bundle ID
    let appBundleID: String?

    /// UI element info
    let elementInfo: UIElementInfo?

    // MARK: - Computed Properties (backward compatibility)

    /// X coordinate (normalized 0-1)
    var x: CGFloat { position.x }

    /// Y coordinate (normalized 0-1)
    var y: CGFloat { position.y }

    enum ClickType {
        case leftDown
        case leftUp
        case rightDown
        case rightUp
        case doubleClick
    }

    // MARK: - Initialization

    init(time: TimeInterval, position: NormalizedPoint, clickType: ClickType, appBundleID: String? = nil, elementInfo: UIElementInfo? = nil) {
        self.time = time
        self.position = position
        self.clickType = clickType
        self.appBundleID = appBundleID
        self.elementInfo = elementInfo
    }

    /// Backward compatibility initializer
    init(time: TimeInterval, x: CGFloat, y: CGFloat, clickType: ClickType, appBundleID: String? = nil, elementInfo: UIElementInfo? = nil) {
        self.init(
            time: time,
            position: NormalizedPoint(x: x, y: y),
            clickType: clickType,
            appBundleID: appBundleID,
            elementInfo: elementInfo
        )
    }
}

// MARK: - Keyboard Event Data

/// Keyboard event data
struct KeyboardEventData {
    /// Time (seconds)
    let time: TimeInterval

    /// Key code
    let keyCode: UInt16

    /// Event type
    let eventType: EventType

    /// Modifier keys
    let modifiers: ModifierFlags

    /// Input character (if available)
    let character: String?

    enum EventType {
        case keyDown
        case keyUp
    }

    struct ModifierFlags: OptionSet {
        let rawValue: UInt

        static let shift = Self(rawValue: 1 << 0)
        static let control = Self(rawValue: 1 << 1)
        static let option = Self(rawValue: 1 << 2)
        static let command = Self(rawValue: 1 << 3)

        /// Check if any modifier key is pressed
        var hasModifiers: Bool { !isEmpty }

        /// 단축키 수정자 키가 눌렸는지 (command, control, option — shift 제외)
        var hasShortcutModifiers: Bool {
            contains(.command) || contains(.control) || contains(.option)
        }
    }

    init(time: TimeInterval, keyCode: UInt16, eventType: EventType, modifiers: ModifierFlags, character: String? = nil) {
        self.time = time
        self.keyCode = keyCode
        self.eventType = eventType
        self.modifiers = modifiers
        self.character = character
    }
}

// MARK: - Drag Event Data

/// Drag event data
struct DragEventData {
    /// Drag start time (seconds)
    let startTime: TimeInterval

    /// Drag end time (seconds)
    let endTime: TimeInterval

    /// Start position (normalized 0-1, top-left origin)
    let startPosition: NormalizedPoint

    /// End position (normalized 0-1, top-left origin)
    let endPosition: NormalizedPoint

    /// Drag type
    let dragType: DragType

    enum DragType {
        case selection   // Text/file selection
        case move        // Drag and drop
        case resize      // Window resize
    }

    /// Drag duration
    var duration: TimeInterval {
        endTime - startTime
    }

    /// Drag distance (normalized)
    var distance: CGFloat {
        startPosition.distance(to: endPosition)
    }
}

// Note: UIElementInfo is defined in Core/Tracking/AccessibilityInspector.swift

// MARK: - Generator Settings

/// Generator settings
struct GeneratorSettings: Codable {

    // MARK: - Smart Zoom

    var smartZoom = SmartZoomSettings()

    // MARK: - Click Zoom

    var clickZoom = ClickZoomSettings()

    // MARK: - Typing Zoom

    var typingZoom = TypingZoomSettings()

    // MARK: - Same Object Follow

    var sameObjectFollow = SameObjectFollowSettings()

    // MARK: - Mouse Data Cleaner

    var mouseDataCleaner = MouseDataCleanerSettings()

    // MARK: - Cursor Interpolation

    var cursorInterpolation = CursorInterpolationSettings()

    // MARK: - Click Cursor

    var clickCursor = ClickCursorSettings()

    // MARK: - Keystroke

    var keystroke = KeystrokeGeneratorSettings()

    static let `default` = Self()
}

// MARK: - Click Zoom Settings

/// Click zoom settings
struct ClickZoomSettings: Codable {
    /// Maximum zoom level
    var maxZoom: CGFloat = 2.0

    /// Minimum zoom level
    var minZoom: CGFloat = 1.0

    /// Zoom-in duration
    var zoomInDuration: TimeInterval = 0.3

    /// Zoom-out duration
    var zoomOutDuration: TimeInterval = 0.5

    /// Hold duration
    var holdDuration: TimeInterval = 0.2

    /// Idle timeout (zoom out when no clicks occur for this duration)
    var idleTimeout: TimeInterval = 1.5

    /// Zoom-in easing
    var zoomInEasing: EasingCurve = .springDefault

    /// Zoom-out easing
    var zoomOutEasing: EasingCurve = .springSmooth

    /// Predictive zoom enabled
    var predictiveEnabled: Bool = true

    /// Predictive zoom look-ahead time
    var lookAheadTime: TimeInterval = 0.8

    /// Predictive zoom approach start time
    var approachStartTime: TimeInterval = 0.5

    /// Predictive zoom proximity radius (normalized)
    var proximityRadius: CGFloat = 0.1

    /// Dynamic zoom enabled
    var dynamicZoomEnabled: Bool = true

    /// Dynamic zoom minimum
    var dynamicMinZoom: CGFloat = 1.5

    /// Dynamic zoom maximum
    var dynamicMaxZoom: CGFloat = 3.0

    /// Dynamic zoom fallback
    var dynamicFallbackZoom: CGFloat = 2.0
}

// MARK: - Smart Zoom Settings

/// Smart Zoom settings (session-based zoom + framing)
struct SmartZoomSettings: Codable {
    // MARK: - General settings

    /// Default zoom level
    var defaultZoom: CGFloat = 1.8

    /// Minimum zoom level
    var minZoom: CGFloat = 1.0

    /// Maximum zoom level
    var maxZoom: CGFloat = 2.5

    /// Zoom-in duration (slow spring for smoothness)
    var focusingDuration: TimeInterval = 1.0

    /// Zoom-out duration (slow return)
    var transitionDuration: TimeInterval = 1.2

    /// Idle timeout before zooming out (generous buffer)
    var idleTimeout: TimeInterval = 4.0

    /// Zoom-in easing (smooth spring without bounce)
    var zoomInEasing: EasingCurve = .spring(dampingRatio: 1.0, response: 0.8)

    /// Zoom-out easing (fast start with deceleration for a natural return)
    var zoomOutEasing: EasingCurve = .easeOut

    /// Move easing (introduces a slight inertia feel)
    var moveEasing: EasingCurve = .spring(dampingRatio: 0.92, response: 0.6)

    /// Cursor lead time (how long the cursor moves ahead of the zoom)
    var cursorLeadTime: TimeInterval = 0.05

    /// Animation settle duration (add a hold keyframe so spring animation completes within this window)
    var animationSettleDuration: TimeInterval = 0.5

    // MARK: - Session clustering settings

    /// Session merge time interval (activities within this window merge into the same session)
    var sessionMergeInterval: TimeInterval = 3.0

    /// Session merge distance (normalized, activities within this radius share the session)
    var sessionMergeDistance: CGFloat = 0.3

    /// Target area coverage (desired screen proportion guiding zoom level)
    var targetAreaCoverage: CGFloat = 0.7

    /// Work area padding (extra margin around the bounding box, normalized)
    var workAreaPadding: CGFloat = 0.08

    // MARK: - Video frame analysis settings

    /// Frame change threshold (zoom out when exceeded) — softened
    var frameChangeThreshold: CGFloat = 0.5

    /// Similarity threshold (zoom out when below this) — softened
    var similarityThreshold: CGFloat = 0.5

    /// Zoom out on scroll detection (disabled to keep zoom during scrolling)
    var scrollDetectionEnabled: Bool = false

    // MARK: - UI state-based settings

    /// Context expansion threshold (zoom out when UI element size grows beyond this multiple)
    var contextExpansionThreshold: CGFloat = 3.0

    /// Modal roles (trigger zoom out when detected)
    var modalRoles: Set<String> = ["AXSheet", "AXDialog", "AXPopover", "AXMenu"]

    // MARK: - Saliency settings

    /// Enable saliency-based center adjustment
    var saliencyEnabled: Bool = true

    /// Saliency blend factor (0 = cursor only, 1 = saliency only)
    var saliencyBlendFactor: CGFloat = 0.3

    /// Max saliency influence distance (normalized, ignore if saliency center is farther than this from the cursor)
    var saliencyMaxDistance: CGFloat = 0.3

    // MARK: - Cursor tracking settings

    /// Cursor follow dead zone (viewport stays still if within this normalized distance from center)
    var cursorFollowDeadZone: CGFloat = 0.15

    /// Cursor follow strength (0–1, lower values make the viewport more stable)
    var cursorFollowStrength: CGFloat = 0.3

    static let `default` = Self()
}

// MARK: - Typing Zoom Settings

/// Typing zoom settings
struct TypingZoomSettings: Codable {
    /// Enabled
    var enabled: Bool = true

    /// Zoom level
    var zoom: CGFloat = 1.8

    /// Typing threshold (key presses per second)
    var typingThreshold: Double = 2.0

    /// Hold duration after typing ends
    var holdAfterTyping: TimeInterval = 0.5

    /// Zoom-in duration
    var zoomInDuration: TimeInterval = 0.25

    /// Zoom-out duration
    var zoomOutDuration: TimeInterval = 0.4
}

// MARK: - Same Object Follow Settings

/// Same object follow settings
struct SameObjectFollowSettings: Codable {
    /// Enabled
    var enabled: Bool = true

    /// Follow smoothness (0–1, higher values feel smoother)
    var followSmoothness: CGFloat = 0.5

    /// Apply only within the same app
    var sameAppOnly: Bool = true

    /// Move duration
    var moveDuration: TimeInterval = 0.3

    /// Move easing
    var moveEasing: EasingCurve = .springSnappy
}

// MARK: - Cursor Interpolation Settings

/// Cursor interpolation settings
struct CursorInterpolationSettings: Codable {
    /// Smoothing factor (Catmull-Rom tension; lower values track the actual path more closely)
    var smoothingFactor: CGFloat = 0.2

    /// Velocity-based smoothing (disabled to keep the scale consistent)
    var velocityBasedSmoothing: Bool = false

    /// Minimum movement distance (ignore movements smaller than this, normalized)
    var minMovementThreshold: CGFloat = 0.002

    /// Maximum velocity (clamp movements faster than this, normalized per second)
    var maxVelocity: CGFloat = 2.0

    /// Fixed cursor scale (use constant value instead of velocity-based variation)
    var fixedCursorScale: CGFloat = 2.0
}

// MARK: - Click Cursor Settings

/// Click cursor generation settings
struct ClickCursorSettings: Codable {
    /// Enabled (disable to avoid artificial cursor paths and honor the real mouse path)
    var enabled: Bool = false

    /// Cursor scale factor
    var cursorScale: CGFloat = 2.0

    /// Arrival time before click (seconds) — how far in advance the cursor should reach the click spot
    var arrivalTime: TimeInterval = 0.15

    /// Hold time after click (seconds) — how long to stay at that spot post-click
    var holdTime: TimeInterval = 0.05

    /// Enable motion blur
    var motionBlurEnabled: Bool = false

    /// Motion blur intensity (0.0 to 2.0)
    var motionBlurIntensity: CGFloat = 0.5

    /// Motion blur velocity threshold (normalized per second)
    var motionBlurVelocityThreshold: CGFloat = 0.8

    /// Move easing (smooth spring)
    var moveEasing: EasingCurve = .spring(dampingRatio: 1.0, response: 0.5)
}

// MARK: - Keystroke Generator Settings

/// Keystroke overlay generator settings
struct KeystrokeGeneratorSettings: Codable {
    /// Enabled
    var enabled: Bool = true

    /// Show shortcuts only (modifier key + regular key combinations)
    var shortcutsOnly: Bool = true

    /// Display duration
    var displayDuration: TimeInterval = 1.5

    /// Fade-in duration
    var fadeInDuration: TimeInterval = 0.15

    /// Fade-out duration
    var fadeOutDuration: TimeInterval = 0.3

    /// Minimum interval (auto-repeat filtering)
    var minInterval: TimeInterval = 0.05
}

// MARK: - Mouse Data Cleaner Settings

/// Mouse data cleaner settings
struct MouseDataCleanerSettings: Codable {
    /// Enable jitter removal
    var enableJitterRemoval: Bool = true

    /// Enable idle compression
    var enableIdleCompression: Bool = true

    /// Enable path simplification (Douglas-Peucker)
    var enablePathSimplification: Bool = true

    /// Enable adaptive sampling
    var enableAdaptiveSampling: Bool = true

    // MARK: - Jitter Removal Settings

    /// Jitter removal window size (moving average filter)
    var jitterWindowSize: Int = 5

    // MARK: - Idle Compression Settings

    /// Idle velocity threshold (pixels/sec)
    var idleVelocityThreshold: CGFloat = 2.0

    /// Idle compression minimum duration (seconds)
    var idleMinDuration: TimeInterval = 0.5

    // MARK: - Path Simplification Settings

    /// Douglas-Peucker tolerance (normalized coordinates)
    var simplificationEpsilon: CGFloat = 0.003

    // MARK: - Adaptive Sampling Settings

    /// Adaptive sampling minimum interval (fast movement, seconds)
    var adaptiveMinInterval: TimeInterval = 1.0 / 60.0

    /// Adaptive sampling maximum interval (slow movement, seconds)
    var adaptiveMaxInterval: TimeInterval = 0.2

    /// Adaptive sampling velocity threshold (normalized per second)
    var adaptiveVelocityThreshold: CGFloat = 0.5

}

// MARK: - Generator Result

/// Generator result
struct GeneratorResult<T: Track> {
    /// Generated track
    let track: T

    /// Generated keyframe count
    let keyframeCount: Int

    /// Generation statistics
    let statistics: GeneratorStatistics
}

/// Generation statistics
struct GeneratorStatistics {
    /// Analyzed events
    let analyzedEvents: Int

    /// Generated keyframes
    let generatedKeyframes: Int

    /// Processing time
    let processingTime: TimeInterval

    /// Additional info
    let additionalInfo: [String: Any]
}
