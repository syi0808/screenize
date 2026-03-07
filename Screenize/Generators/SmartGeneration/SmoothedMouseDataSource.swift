import Foundation
import CoreGraphics

/// A MouseDataSource decorator that applies Catmull-Rom + Spring smoothing
/// to mouse positions, matching the render pipeline's cursor smoothing.
///
/// Only `positions` are smoothed. Clicks, keyboard events, and drag events
/// pass through unchanged since they are discrete events at precise locations.
struct SmoothedMouseDataSource: MouseDataSource {

    let duration: TimeInterval
    let frameRate: Double
    let positions: [MousePositionData]
    let clicks: [ClickEventData]
    let keyboardEvents: [KeyboardEventData]
    let dragEvents: [DragEventData]

    /// Create a smoothed mouse data source by applying render-pipeline-equivalent
    /// smoothing to the position data.
    ///
    /// - Parameters:
    ///   - source: The original mouse data source with raw positions
    ///   - springConfig: Spring cursor configuration (matches render pipeline)
    ///   - baseTension: Catmull-Rom tension parameter (default 0.2, matches render pipeline)
    init(
        wrapping source: MouseDataSource,
        springConfig: SpringCursorConfig = .default,
        baseTension: CGFloat = 0.2
    ) {
        self.duration = source.duration
        self.frameRate = source.frameRate
        self.clicks = source.clicks
        self.keyboardEvents = source.keyboardEvents
        self.dragEvents = source.dragEvents
        self.positions = Self.smoothPositions(
            source.positions,
            frameRate: source.frameRate,
            springConfig: springConfig,
            baseTension: baseTension
        )
    }

    // MARK: - Private

    private static func smoothPositions(
        _ positions: [MousePositionData],
        frameRate: Double,
        springConfig: SpringCursorConfig,
        baseTension: CGFloat
    ) -> [MousePositionData] {
        guard positions.count >= 2 else { return positions }

        // 1. Convert MousePositionData -> RenderMousePosition
        let renderPositions = positions.map { pos in
            RenderMousePosition(
                timestamp: pos.time,
                x: pos.position.x,
                y: pos.position.y
            )
        }

        // 2. Apply the same smoothing pipeline as the render path
        let effectiveFrameRate = frameRate > 0 ? frameRate : 60.0
        let smoothed = MousePositionInterpolator.interpolate(
            renderPositions,
            outputFrameRate: effectiveFrameRate,
            baseTension: baseTension,
            springConfig: springConfig
        )

        // 3. Map smoothed positions back to MousePositionData,
        //    preserving metadata from nearest original position
        return mapBackToMousePositionData(
            smoothed: smoothed,
            originals: positions
        )
    }

    /// Map smoothed RenderMousePositions back to MousePositionData,
    /// assigning metadata (appBundleID, elementInfo) from the nearest
    /// original position by timestamp.
    private static func mapBackToMousePositionData(
        smoothed: [RenderMousePosition],
        originals: [MousePositionData]
    ) -> [MousePositionData] {
        guard !originals.isEmpty else { return [] }

        let sortedOriginals = originals.sorted { $0.time < $1.time }

        return smoothed.map { renderPos in
            let nearest = findNearest(
                time: renderPos.timestamp,
                in: sortedOriginals
            )
            return MousePositionData(
                time: renderPos.timestamp,
                position: NormalizedPoint(
                    x: renderPos.position.x,
                    y: renderPos.position.y
                ),
                appBundleID: nearest.appBundleID,
                elementInfo: nearest.elementInfo
            )
        }
    }

    /// Binary search for the nearest original position by timestamp.
    private static func findNearest(
        time: TimeInterval,
        in sorted: [MousePositionData]
    ) -> MousePositionData {
        var low = 0
        var high = sorted.count - 1

        while low < high {
            let mid = (low + high) / 2
            if sorted[mid].time < time {
                low = mid + 1
            } else {
                high = mid
            }
        }

        // Check both low and low-1 to find the actual nearest
        if low > 0 {
            let before = sorted[low - 1]
            let after = sorted[low]
            return abs(before.time - time) <= abs(after.time - time)
                ? before : after
        }
        return sorted[low]
    }
}
