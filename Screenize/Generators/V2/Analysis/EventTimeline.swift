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

    /// Downsample interval for mouse move events (seconds).
    private static let mouseMoveDownsampleInterval: TimeInterval = 0.1

    /// Build a unified event timeline from a mouse data source.
    /// Mouse move events are downsampled to ~10 Hz for efficiency.
    static func build(
        from mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample] = []
    ) -> EventTimeline {
        var unified: [UnifiedEvent] = []

        // Mouse positions — downsampled to ~10 Hz
        var lastPositionTime: TimeInterval = -.greatestFiniteMagnitude
        for pos in mouseData.positions {
            if pos.time - lastPositionTime >= mouseMoveDownsampleInterval {
                unified.append(UnifiedEvent(
                    time: pos.time,
                    kind: .mouseMove,
                    position: pos.position,
                    metadata: EventMetadata(
                        appBundleID: pos.appBundleID,
                        elementInfo: pos.elementInfo
                    )
                ))
                lastPositionTime = pos.time
            }
        }

        // Clicks — all types included
        for click in mouseData.clicks {
            unified.append(UnifiedEvent(
                time: click.time,
                kind: .click(click),
                position: click.position,
                metadata: EventMetadata(
                    appBundleID: click.appBundleID,
                    elementInfo: click.elementInfo
                )
            ))
        }

        // Keyboard events
        for kbd in mouseData.keyboardEvents {
            let kind: EventKind = kbd.eventType == .keyDown
                ? .keyDown(kbd)
                : .keyUp(kbd)
            // Position from nearest mouse position before this time
            let position = nearestPosition(before: kbd.time, in: mouseData.positions)
                ?? NormalizedPoint(x: 0.5, y: 0.5)
            unified.append(UnifiedEvent(
                time: kbd.time,
                kind: kind,
                position: position,
                metadata: EventMetadata()
            ))
        }

        // Drag events — emit both start and end
        for drag in mouseData.dragEvents {
            unified.append(UnifiedEvent(
                time: drag.startTime,
                kind: .dragStart(drag),
                position: drag.startPosition,
                metadata: EventMetadata()
            ))
            unified.append(UnifiedEvent(
                time: drag.endTime,
                kind: .dragEnd(drag),
                position: drag.endPosition,
                metadata: EventMetadata()
            ))
        }

        // UI state samples
        for sample in uiStateSamples {
            let position = nearestPosition(before: sample.timestamp, in: mouseData.positions)
                ?? NormalizedPoint(x: 0.5, y: 0.5)
            unified.append(UnifiedEvent(
                time: sample.timestamp,
                kind: .uiStateChange(sample),
                position: position,
                metadata: EventMetadata(
                    elementInfo: sample.elementInfo,
                    caretBounds: sample.caretBounds
                )
            ))
        }

        unified.sort { $0.time < $1.time }

        return EventTimeline(events: unified, duration: mouseData.duration)
    }

    // MARK: - Querying

    /// Return all events within the given closed time range (inclusive).
    /// Uses binary search for start index, then linear scan.
    func events(in range: ClosedRange<TimeInterval>) -> [UnifiedEvent] {
        // Binary search for first event with time >= range.lowerBound
        var low = 0
        var high = events.count
        while low < high {
            let mid = (low + high) / 2
            if events[mid].time < range.lowerBound {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var result: [UnifiedEvent] = []
        for i in low..<events.count {
            if events[i].time > range.upperBound { break }
            result.append(events[i])
        }
        return result
    }

    /// Return the last mouse position at or before the given time.
    func lastMousePosition(before time: TimeInterval) -> NormalizedPoint? {
        var result: NormalizedPoint?
        for event in events {
            if event.time > time { break }
            if case .mouseMove = event.kind {
                result = event.position
            }
        }
        return result
    }

    // MARK: - Private Helpers

    /// Find the nearest mouse position at or before a given time.
    private static func nearestPosition(
        before time: TimeInterval,
        in positions: [MousePositionData]
    ) -> NormalizedPoint? {
        positions.last(where: { $0.time <= time })?.position
    }
}
