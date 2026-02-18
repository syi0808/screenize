import Foundation
import CoreGraphics

// MARK: - Intent Classifier

/// Rule-based classifier that segments an event timeline into intent spans.
struct IntentClassifier {

    // MARK: - Configuration Constants

    /// Maximum gap between keyDown events within a typing session.
    static let typingSessionTimeout: TimeInterval = 1.5

    /// Maximum time between clicks to count as navigating.
    static let navigatingClickWindow: TimeInterval = 2.0

    /// Maximum spatial distance between clicks to count as navigating.
    static let navigatingClickDistance: CGFloat = 0.3

    /// Minimum number of clicks for a navigating span.
    static let navigatingMinClicks: Int = 2

    /// Idle threshold (no actionable events for this duration).
    static let idleThreshold: TimeInterval = 5.0

    // MARK: - Classification

    /// Classify an event timeline into intent spans.
    static func classify(
        events: EventTimeline,
        uiStateSamples: [UIStateSample]
    ) -> [IntentSpan] {
        // Stub — full implementation in next commit
        return []
    }
}
