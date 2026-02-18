import Foundation
import CoreGraphics

// MARK: - Event Timeline

/// Merged, time-sorted stream of all recording events.
struct EventTimeline {

    /// All events sorted by time.
    let events: [UnifiedEvent]

    /// Recording duration in seconds.
    let duration: TimeInterval

    // MARK: - Building

    /// Build a unified event timeline from a mouse data source.
    /// Mouse move events are downsampled to ~10 Hz for efficiency.
    static func build(
        from mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample] = []
    ) -> EventTimeline {
        // Stub — full implementation in next commit
        return EventTimeline(events: [], duration: mouseData.duration)
    }

    // MARK: - Querying

    /// Return all events within the given closed time range (inclusive).
    func events(in range: ClosedRange<TimeInterval>) -> [UnifiedEvent] {
        // Stub
        return []
    }

    /// Return the last mouse position at or before the given time.
    func lastMousePosition(before time: TimeInterval) -> NormalizedPoint? {
        // Stub
        return nil
    }
}
