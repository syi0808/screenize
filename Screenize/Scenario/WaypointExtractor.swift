import Foundation
import CoreGraphics

// MARK: - WaypointExtractor

/// Extracts waypoints from raw mouse_move events at a configurable sampling rate.
/// Returns normalized CGPoint coordinates with CG top-left origin (0–1 range).
struct WaypointExtractor {

    /// Extract waypoints from raw mouse_move events at specified Hz.
    ///
    /// - Parameters:
    ///   - rawEvents: The raw event container including capture area and all events.
    ///   - timeRange: Inclusive millisecond range to filter events within.
    ///   - hz: Desired sampling frequency in samples per second.
    ///   - captureArea: The screen area captured; used to normalize coordinates.
    /// - Returns: Array of normalized CGPoints (0–1, top-left origin), deduplicated.
    static func extract(
        from rawEvents: ScenarioRawEvents,
        timeRange: TimeRange,
        hz: Int,
        captureArea: CGRect
    ) -> [CGPoint] {
        guard hz > 0, captureArea.width > 0, captureArea.height > 0 else { return [] }

        // Step 1: Filter mouse_move events within timeRange (inclusive) that have coordinates.
        let filtered = rawEvents.events.filter { event in
            event.type == .mouseMove
                && event.timeMs >= timeRange.startMs
                && event.timeMs <= timeRange.endMs
                && event.x != nil
                && event.y != nil
        }

        guard !filtered.isEmpty else { return [] }

        // Step 2: Calculate sample interval in milliseconds.
        let intervalMs = 1000 / hz

        // Step 3: Walk through sample times, picking the closest mouse_move event.
        var waypoints: [CGPoint] = []
        var sampleTime = timeRange.startMs

        while sampleTime < timeRange.endMs {
            // Find the event closest in time to sampleTime.
            if let closest = closestEvent(in: filtered, to: sampleTime) {
                let normalized = normalize(x: closest.x!, y: closest.y!, captureArea: captureArea)

                // Step 5: Skip duplicate points (same coordinates as previous sample).
                if waypoints.last != normalized {
                    waypoints.append(normalized)
                }
            }
            sampleTime += intervalMs
        }

        return waypoints
    }

    // MARK: - Private Helpers

    /// Returns the event with the smallest absolute time distance to the target time.
    private static func closestEvent(in events: [RawEvent], to targetMs: Int) -> RawEvent? {
        events.min(by: { abs($0.timeMs - targetMs) < abs($1.timeMs - targetMs) })
    }

    /// Normalizes raw screen coordinates relative to the capture area.
    /// Uses CG top-left origin — no Y flip applied.
    private static func normalize(x: Double, y: Double, captureArea: CGRect) -> CGPoint {
        let normalizedX = (x - captureArea.origin.x) / captureArea.width
        let normalizedY = (y - captureArea.origin.y) / captureArea.height
        return CGPoint(x: normalizedX, y: normalizedY)
    }
}
