import Foundation
import CoreGraphics

/// Mouse data cleaner
/// Removes noise or performs interpolation to produce optimized data
final class MouseDataCleaner {

    // MARK: - Clean Pipeline

    /// Mouse position data cleanup pipeline
    /// - Parameters:
    ///   - positions: Original mouse positions
    ///   - settings: Cleanup settings
    /// - Returns: Cleaned mouse positions
    func clean(_ positions: [MousePositionData], settings: MouseDataCleanerSettings = MouseDataCleanerSettings()) -> [MousePositionData] {
        guard positions.count > 2 else { return positions }

        var result = positions
        let originalCount = positions.count

        // Step 1: Remove jitter with a moving average filter
        if settings.enableJitterRemoval {
            result = removeJitter(positions: result, windowSize: settings.jitterWindowSize)
        }

        // Step 2: Compress idle segments
        if settings.enableIdleCompression {
            result = compressIdleRegions(
                positions: result,
                velocityThreshold: settings.idleVelocityThreshold,
                minIdleDuration: settings.idleMinDuration
            )
        }

        // Step 3: Simplify the path using Douglas-Peucker
        if settings.enablePathSimplification {
            result = simplifyPath(positions: result, epsilon: settings.simplificationEpsilon)
        }

        // Step 4: Adaptive resampling
        if settings.enableAdaptiveSampling {
            result = adaptiveResample(
                positions: result,
                minInterval: settings.adaptiveMinInterval,
                maxInterval: settings.adaptiveMaxInterval,
                velocityThreshold: settings.adaptiveVelocityThreshold
            )
        }

        let cleanedCount = result.count
        let reductionRate = 1.0 - (Double(cleanedCount) / Double(originalCount))
        print("🧹 [MouseDataCleaner] Cleaning completed: \(originalCount) → \(cleanedCount) (\(String(format: "%.1f", reductionRate * 100))% reduction)")

        return result
    }

    // MARK: - Jitter Removal (Moving Average Filter)

    /// Remove jitter using a moving average filter
    /// - Parameters:
    ///   - positions: Original position data
    ///   - windowSize: Filter window size (odd values recommended)
    /// - Returns: Smoothed positions
    func removeJitter(positions: [MousePositionData], windowSize: Int = 5) -> [MousePositionData] {
        guard positions.count > windowSize else { return positions }

        var result: [MousePositionData] = []
        let halfWindow = windowSize / 2

        for i in 0..<positions.count {
            let start = max(0, i - halfWindow)
            let end = min(positions.count - 1, i + halfWindow)
            let window = positions[start...end]

            // Compute the average position within the window
            let avgX = window.map { $0.x }.reduce(0, +) / CGFloat(window.count)
            let avgY = window.map { $0.y }.reduce(0, +) / CGFloat(window.count)

            result.append(MousePositionData(
                time: positions[i].time,
                x: avgX,
                y: avgY,
                appBundleID: positions[i].appBundleID,
                elementInfo: positions[i].elementInfo
            ))
        }

        return result
    }

    // MARK: - Idle Compression

    /// Compress idle segments by keeping only their start and end points
    /// - Parameters:
    ///   - positions: Original position data
    ///   - velocityThreshold: Threshold to detect being idle
    ///   - minIdleDuration: Minimum duration to consider for compression
    /// - Returns: Position data with compressed idle regions
    func compressIdleRegions(
        positions: [MousePositionData],
        velocityThreshold: CGFloat = 2.0,
        minIdleDuration: TimeInterval = 0.5
    ) -> [MousePositionData] {
        guard positions.count > 2 else { return positions }

        var result: [MousePositionData] = []
        var idleStartIndex: Int?

        // Helper to compute velocity
        func calculateVelocity(from: MousePositionData, to: MousePositionData) -> CGFloat {
            let dt = to.time - from.time
            guard dt > 0.001 else { return 0 }
            let dx = to.x - from.x
            let dy = to.y - from.y
            let distance = sqrt(dx * dx + dy * dy)
            return distance / CGFloat(dt)
        }

        for i in 0..<positions.count {
            let velocity: CGFloat
            if i == 0 {
                velocity = i + 1 < positions.count ? calculateVelocity(from: positions[i], to: positions[i + 1]) : 0
            } else {
                velocity = calculateVelocity(from: positions[i - 1], to: positions[i])
            }

            let isIdle = velocity < velocityThreshold

            if isIdle {
                if idleStartIndex == nil {
                    idleStartIndex = i
                }
            } else {
                if let startIdx = idleStartIndex {
                    let idleDuration = positions[i].time - positions[startIdx].time

                    if idleDuration >= minIdleDuration && i - startIdx > 2 {
                        // If the idle segment is long enough, keep only start/end
                        result.append(positions[startIdx])
                        result.append(positions[i - 1])
                    } else {
                        // Short idle segments: keep all points
                        result.append(contentsOf: positions[startIdx..<i])
                    }
                    idleStartIndex = nil
                }
                result.append(positions[i])
            }
        }

        // Handle the final idle segment
        if let startIdx = idleStartIndex {
            let lastIdx = positions.count - 1
            let idleDuration = positions[lastIdx].time - positions[startIdx].time

            if idleDuration >= minIdleDuration && lastIdx - startIdx > 2 {
                result.append(positions[startIdx])
                result.append(positions[lastIdx])
            } else {
                result.append(contentsOf: positions[startIdx...lastIdx])
            }
        }

        return result
    }

    // MARK: - Path Simplification (Douglas-Peucker)

    /// Path simplification using the Douglas-Peucker algorithm
    /// Removes unnecessary midpoints while keeping the overall shape
    /// - Parameters:
    ///   - positions: Original position data
    ///   - epsilon: Tolerance (normalized coordinates)
    /// - Returns: Simplified position data
    func simplifyPath(positions: [MousePositionData], epsilon: CGFloat = 0.003) -> [MousePositionData] {
        guard positions.count > 2 else { return positions }

        return douglasPeucker(positions: positions, epsilon: epsilon)
    }

    private func douglasPeucker(positions: [MousePositionData], epsilon: CGFloat) -> [MousePositionData] {
        guard positions.count > 2 else { return positions }

        let start = CGPoint(x: positions.first!.x, y: positions.first!.y)
        let end = CGPoint(x: positions.last!.x, y: positions.last!.y)

        // Find the point farthest from the line
        var maxDistance: CGFloat = 0
        var maxIndex = 0

        for i in 1..<(positions.count - 1) {
            let point = CGPoint(x: positions[i].x, y: positions[i].y)
            let distance = perpendicularDistance(point: point, lineStart: start, lineEnd: end)

            if distance > maxDistance {
                maxDistance = distance
                maxIndex = i
            }
        }

        // Recurse when the max distance exceeds the tolerance
        if maxDistance > epsilon {
            let left = douglasPeucker(positions: Array(positions[0...maxIndex]), epsilon: epsilon)
            let right = douglasPeucker(positions: Array(positions[maxIndex...]), epsilon: epsilon)

            // Merge while removing duplicates
            return Array(left.dropLast()) + right
        } else {
            // Return only the start and end points
            return [positions.first!, positions.last!]
        }
    }

    /// Calculate the perpendicular distance from a point to a line
    private func perpendicularDistance(point: CGPoint, lineStart: CGPoint, lineEnd: CGPoint) -> CGFloat {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y

        // Handle degenerate line cases (line is a point)
        if dx == 0 && dy == 0 {
            return hypot(point.x - lineStart.x, point.y - lineStart.y)
        }

        // Compute the projection point
        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: lineStart.x + t * dx, y: lineStart.y + t * dy)

        return hypot(point.x - projection.x, point.y - projection.y)
    }

    // MARK: - Adaptive Resampling

    /// Adaptive resampling based on speed
    /// Dense sampling when moving fast, sparse when moving slowly
    /// - Parameters:
    ///   - positions: Original position data
    ///   - minInterval: Minimum sampling interval (fast motion)
    ///   - maxInterval: Maximum sampling interval (slow motion)
    ///   - velocityThreshold: Speed threshold (normalized per second)
    /// - Returns: Resampled position data
    func adaptiveResample(
        positions: [MousePositionData],
        minInterval: TimeInterval = 1.0 / 60.0,
        maxInterval: TimeInterval = 0.2,
        velocityThreshold: CGFloat = 0.5
    ) -> [MousePositionData] {
        guard positions.count > 1 else { return positions }

        var result: [MousePositionData] = [positions[0]]
        var lastAddedIndex = 0

        for i in 1..<positions.count {
            let current = positions[i]
            let lastAdded = positions[lastAddedIndex]

            let timeDelta = current.time - lastAdded.time

            // Compute the velocity
            let dx = current.x - lastAdded.x
            let dy = current.y - lastAdded.y
            let distance = sqrt(dx * dx + dy * dy)
            let velocity = timeDelta > 0 ? distance / CGFloat(timeDelta) : 0

            // Compute the target interval based on speed
            let normalizedVelocity = min(1.0, velocity / velocityThreshold)
            let targetInterval = maxInterval - (maxInterval - minInterval) * normalizedVelocity

            if timeDelta >= targetInterval {
                result.append(current)
                lastAddedIndex = i
            }
        }

        // Guarantee the final point is included
        if lastAddedIndex != positions.count - 1 {
            result.append(positions.last!)
        }

        return result
    }
}

// MARK: - MouseRecording Extension

extension MouseRecording {
    /// Create a new MouseRecording with cleaned data
    /// - Parameter settings: Cleanup settings
    /// - Returns: MouseRecording with cleaned positions
    func cleaned(with settings: MouseDataCleanerSettings = MouseDataCleanerSettings()) -> MouseRecording {
        let cleaner = MouseDataCleaner()

        // Convert MousePosition to MousePositionData
        let positionData = positions.map { pos in
            MousePositionData(
                time: pos.timestamp,
                x: pos.x,
                y: pos.y,
                appBundleID: nil,
                elementInfo: nil
            )
        }

        // Clean up the data
        let cleanedData = cleaner.clean(positionData, settings: settings)

        // Convert back to MousePosition
        let cleanedPositions = cleanedData.map { data in
            MousePosition(
                timestamp: data.time,
                x: data.x,
                y: data.y,
                velocity: 0  // Recalculate velocity elsewhere if needed
            )
        }

        return MouseRecording(
            positions: cleanedPositions,
            clicks: clicks,
            scrollEvents: scrollEvents,
            keyboardEvents: keyboardEvents,
            dragEvents: dragEvents,
            uiStateSamples: uiStateSamples,
            screenBounds: screenBounds,
            recordingDuration: recordingDuration,
            frameRate: frameRate,
            scaleFactor: scaleFactor
        )
    }
}
