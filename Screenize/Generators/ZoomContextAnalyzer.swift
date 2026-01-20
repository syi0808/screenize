import Foundation
import CoreGraphics

/// Zoom context analyzer
/// Determines a zoom strategy based on UI element types and frame analysis
struct ZoomContextAnalyzer {

    // MARK: - Types

    /// UI element context types
    enum UIContextType {
        case textInput          // Text fields, search bars, etc.
        case quickAction        // Buttons, menu items, etc.
        case navigation         // Tabs, sidebars, etc.
        case scrollable         // Scroll views, lists, etc.
        case modal              // Modals, sheets, popups
        case unknown            // Unknown context
    }

    /// Zoom strategy
    struct ZoomStrategy {
        let targetZoom: CGFloat
        let holdDuration: TimeInterval
        let followCursor: Bool
        let zoomOutOnFrameChange: Bool
        let frameChangeThreshold: CGFloat

        static let textInput = Self(
            targetZoom: 2.0,
            holdDuration: 3.0,        // Hold longer while typing
            followCursor: true,
            zoomOutOnFrameChange: false,  // Ignore frame changes while typing
            frameChangeThreshold: 0.5
        )

        static let quickAction = Self(
            targetZoom: 2.5,
            holdDuration: 0.5,        // Hold briefly
            followCursor: true,
            zoomOutOnFrameChange: true,  // Detect frame changes after a button click
            frameChangeThreshold: 0.2
        )

        static let navigation = Self(
            targetZoom: 1.8,
            holdDuration: 0.8,
            followCursor: true,
            zoomOutOnFrameChange: true,
            frameChangeThreshold: 0.25
        )

        static let scrollable = Self(
            targetZoom: 1.5,
            holdDuration: 0.3,
            followCursor: false,      // Do not follow cursor during scrolling
            zoomOutOnFrameChange: true,
            frameChangeThreshold: 0.15  // Scroll events have large changes, so use a lower threshold
        )

        static let modal = Self(
            targetZoom: 1.0,          // No zoom for modals
            holdDuration: 0.0,
            followCursor: false,
            zoomOutOnFrameChange: true,
            frameChangeThreshold: 0.3
        )

        static let `default` = Self(
            targetZoom: 2.0,
            holdDuration: 1.5,
            followCursor: true,
            zoomOutOnFrameChange: true,
            frameChangeThreshold: 0.3
        )
    }

    /// Context analysis result
    struct ContextAnalysis {
        let contextType: UIContextType
        let strategy: ZoomStrategy
        let confidence: CGFloat
        let reason: String
    }

    // MARK: - Role Mapping

    /// Accessibility roles related to text input
    private static let textInputRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXSearchField",
        "AXSecureTextField",
        "AXComboBox"
    ]

    /// Roles associated with quick actions
    private static let quickActionRoles: Set<String> = [
        "AXButton",
        "AXMenuItem",
        "AXLink",
        "AXCheckBox",
        "AXRadioButton",
        "AXSwitch",
        "AXToggle"
    ]

    /// Roles associated with navigation
    private static let navigationRoles: Set<String> = [
        "AXTab",
        "AXTabGroup",
        "AXToolbar",
        "AXOutline",
        "AXList",
        "AXBrowser"
    ]

    /// Roles associated with scrollable views
    private static let scrollableRoles: Set<String> = [
        "AXScrollArea",
        "AXScrollBar",
        "AXTable",
        "AXOutline"
    ]

    /// Roles associated with modals and popups
    private static let modalRoles: Set<String> = [
        "AXSheet",
        "AXDialog",
        "AXPopover",
        "AXMenu",
        "AXWindow"  // When a new window opens
    ]

    // MARK: - Analysis

    /// Analyze the context from UI element information
    static func analyze(elementInfo: UIElementInfo?) -> ContextAnalysis {
        guard let info = elementInfo else {
            return ContextAnalysis(
                contextType: .unknown,
                strategy: .default,
                confidence: 0.3,
                reason: "No element info"
            )
        }

        let role = info.role

        // Determine the context based on the role
        if textInputRoles.contains(role) {
            return ContextAnalysis(
                contextType: .textInput,
                strategy: .textInput,
                confidence: 0.9,
                reason: "Text input role: \(role)"
            )
        }

        if quickActionRoles.contains(role) {
            return ContextAnalysis(
                contextType: .quickAction,
                strategy: .quickAction,
                confidence: 0.9,
                reason: "Quick action role: \(role)"
            )
        }

        if modalRoles.contains(role) {
            return ContextAnalysis(
                contextType: .modal,
                strategy: .modal,
                confidence: 0.95,
                reason: "Modal role: \(role)"
            )
        }

        if navigationRoles.contains(role) {
            return ContextAnalysis(
                contextType: .navigation,
                strategy: .navigation,
                confidence: 0.8,
                reason: "Navigation role: \(role)"
            )
        }

        if scrollableRoles.contains(role) {
            return ContextAnalysis(
                contextType: .scrollable,
                strategy: .scrollable,
                confidence: 0.8,
                reason: "Scrollable role: \(role)"
            )
        }

        // Additional heuristics based on the title
        if let title = info.title?.lowercased() {
            if title.contains("search") {
                return ContextAnalysis(
                    contextType: .textInput,
                    strategy: .textInput,
                    confidence: 0.7,
                    reason: "Search-related title"
                )
            }
        }

        return ContextAnalysis(
            contextType: .unknown,
            strategy: .default,
            confidence: 0.5,
            reason: "Unknown role: \(role)"
        )
    }

    /// Determine zoom strategy alongside frame analysis results
    static func determineStrategy(
        elementInfo: UIElementInfo?,
        frameAnalysis: VideoFrameAnalyzer.FrameAnalysis?,
        previousFrameAnalysis: VideoFrameAnalyzer.FrameAnalysis?,
        settings: SmartZoomSettings
    ) -> ZoomStrategy {
        // 1. Analyze the UI context
        let contextAnalysis = analyze(elementInfo: elementInfo)
        var strategy = contextAnalysis.strategy

        // 2. Adjust strategy based on frame analysis
        if let analysis = frameAnalysis {
            // Switch to scroll strategy when scrolling is detected
            if analysis.isScrolling {
                return .scrollable
            }

            // Recommend zooming out when a large change is detected
            if analysis.changeAmount > settings.frameChangeThreshold {
                strategy = ZoomStrategy(
                    targetZoom: strategy.targetZoom,
                    holdDuration: 0.2,  // Keep the hold short
                    followCursor: false,
                    zoomOutOnFrameChange: true,
                    frameChangeThreshold: settings.frameChangeThreshold
                )
            }

            // Recommend zooming out when similarity drops (big visual change)
            if analysis.similarity < settings.similarityThreshold {
                strategy = ZoomStrategy(
                    targetZoom: 1.0,  // Zoom out
                    holdDuration: 0.0,
                    followCursor: false,
                    zoomOutOnFrameChange: true,
                    frameChangeThreshold: settings.frameChangeThreshold
                )
            }
        }

        return strategy
    }

    /// Decide whether to keep zoom during continuous activity
    static func shouldMaintainZoom(
        currentActivity: ActivityEvent,
        previousActivity: ActivityEvent,
        frameAnalysis: VideoFrameAnalyzer.FrameAnalysis?,
        settings: SmartZoomSettings
    ) -> Bool {
        // 1. Check the time interval
        let timeDiff = currentActivity.time - previousActivity.time
        if timeDiff > settings.idleTimeout {
            return false
        }

        // 2. Evaluate based on frame analysis
        if let analysis = frameAnalysis {
            // Cancel zoom for major frame changes
            if analysis.changeAmount > settings.frameChangeThreshold {
                return false
            }

            // Cancel zoom if scrolling is detected
            if settings.scrollDetectionEnabled && analysis.isScrolling {
                return false
            }

            // Cancel zoom when similarity abruptly drops
            if analysis.similarity < settings.similarityThreshold {
                return false
            }
        }

        // 3. Check if the context is consistent
        let currentContext = analyze(elementInfo: currentActivity.elementInfo)
        let previousContext = analyze(elementInfo: previousActivity.elementInfo)

        // Maintain zoom if both are text inputs
        if currentContext.contextType == .textInput && previousContext.contextType == .textInput {
            return true
        }

        // Maintain zoom for consecutive clicks within the same app (distance check)
        let distance = currentActivity.position.distance(to: previousActivity.position)
        if distance < 0.2 && timeDiff < 1.0 {
            return true
        }

        // Default: maintain zoom
        return true
    }

    /// Calculate zoom level based on element size
    static func calculateZoomLevel(
        elementInfo: UIElementInfo?,
        strategy: ZoomStrategy,
        settings: SmartZoomSettings
    ) -> CGFloat {
        // Adjust zoom based on the UI element size
        if let frame = elementInfo?.frame {
            let elementSize = min(frame.width, frame.height)

            // Smaller elements receive higher zoom (clamped between max/min)
            if elementSize < 0.03 {
                return min(settings.maxZoom, strategy.targetZoom * 1.3)
            } else if elementSize < 0.08 {
                return strategy.targetZoom
            } else if elementSize < 0.15 {
                return max(settings.minZoom, strategy.targetZoom * 0.8)
            } else {
                // Reduce zoom for larger elements
                return settings.minZoom
            }
        }

        return strategy.targetZoom
    }
}

// MARK: - ZoomStrategy Extensions

extension ZoomContextAnalyzer.ZoomStrategy {

    /// Create a strategy based on settings
    static func from(settings: SmartZoomSettings, contextType: ZoomContextAnalyzer.UIContextType) -> ZoomContextAnalyzer.ZoomStrategy {
        switch contextType {
        case .textInput:
            return ZoomContextAnalyzer.ZoomStrategy(
                targetZoom: settings.defaultZoom,
                holdDuration: settings.idleTimeout + 1.0,
                followCursor: true,
                zoomOutOnFrameChange: false,
                frameChangeThreshold: settings.frameChangeThreshold * 1.5
            )

        case .quickAction:
            return ZoomContextAnalyzer.ZoomStrategy(
                targetZoom: settings.defaultZoom * 1.2,
                holdDuration: 0.5,
                followCursor: true,
                zoomOutOnFrameChange: true,
                frameChangeThreshold: settings.frameChangeThreshold * 0.7
            )

        case .navigation:
            return ZoomContextAnalyzer.ZoomStrategy(
                targetZoom: settings.defaultZoom * 0.9,
                holdDuration: 0.8,
                followCursor: true,
                zoomOutOnFrameChange: true,
                frameChangeThreshold: settings.frameChangeThreshold
            )

        case .scrollable:
            return ZoomContextAnalyzer.ZoomStrategy(
                targetZoom: settings.minZoom,
                holdDuration: 0.3,
                followCursor: false,
                zoomOutOnFrameChange: true,
                frameChangeThreshold: settings.frameChangeThreshold * 0.5
            )

        case .modal:
            return ZoomContextAnalyzer.ZoomStrategy(
                targetZoom: settings.minZoom,
                holdDuration: 0.0,
                followCursor: false,
                zoomOutOnFrameChange: true,
                frameChangeThreshold: settings.frameChangeThreshold
            )

        case .unknown:
            return ZoomContextAnalyzer.ZoomStrategy(
                targetZoom: settings.defaultZoom,
                holdDuration: settings.idleTimeout,
                followCursor: true,
                zoomOutOnFrameChange: true,
                frameChangeThreshold: settings.frameChangeThreshold
            )
        }
    }
}
