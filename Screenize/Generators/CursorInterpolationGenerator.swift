import Foundation
import CoreGraphics

/// Cursor interpolation generator
/// Smooths cursor movement using a Catmull-Rom spline
final class CursorInterpolationGenerator: KeyframeGenerator {

    typealias Output = CursorTrack

    // MARK: - Properties

    let name = "Cursor Interpolation"
    let description = "Smooth cursor movement using Catmull-Rom spline interpolation"

    private let cleaner = MouseDataCleaner()

    // MARK: - Generate

    func generate(from mouseData: MouseDataSource, settings: GeneratorSettings) -> CursorTrack {
        let cursorSettings = settings.cursorInterpolation
        let cleanerSettings = settings.mouseDataCleaner
        var positions = mouseData.positions

        guard positions.count >= 2 else {
            return createDefaultTrack()
        }

        // 0. Clean mouse data (remove unnecessary movement)
        positions = cleaner.clean(positions, settings: cleanerSettings)

        guard positions.count >= 2 else {
            return createDefaultTrack()
        }

        // 1. Filter noise
        let filteredPositions = filterPositions(positions, settings: cursorSettings)

        guard filteredPositions.count >= 2 else {
            return createTrackFromPositions(filteredPositions, settings: cursorSettings)
        }

        // 2. Calculate velocities
        let velocities = calculateVelocities(filteredPositions)

        // 3. Detect key points (direction changes, stops, acceleration/deceleration)
        let keyPoints = detectKeyPoints(
            positions: filteredPositions,
            velocities: velocities,
            settings: cursorSettings
        )

        // 4. Generate keyframes from the key points
        let keyframes = createKeyframesFromKeyPoints(
            keyPoints: keyPoints,
            allPositions: filteredPositions,
            velocities: velocities,
            settings: cursorSettings
        )

        return CursorTrack(
            id: UUID(),
            name: "Cursor (Smoothed)",
            isEnabled: true,
            styleKeyframes: keyframes
        )
    }

    /// Generate keyframes from key points (fixed scale, simplified key points)
    private func createKeyframesFromKeyPoints(
        keyPoints: [KeyPoint],
        allPositions: [MousePositionData],
        velocities: [VelocityData],
        settings: CursorInterpolationSettings
    ) -> [CursorStyleKeyframe] {
        guard !allPositions.isEmpty else { return [] }

        var keyframes: [CursorStyleKeyframe] = []
        let fixedScale = settings.fixedCursorScale

        // Always include the first point
        let firstPos = allPositions[0]
        keyframes.append(CursorStyleKeyframe(
            time: firstPos.time,
            position: NormalizedPoint(x: firstPos.x, y: firstPos.y),
            style: .arrow,
            visible: true,
            scale: fixedScale,
            easing: .easeInOut
        ))

        // Convert key points into keyframes (with fixed scale)
        for keyPoint in keyPoints {
            keyframes.append(CursorStyleKeyframe(
                time: keyPoint.time,
                position: NormalizedPoint(x: keyPoint.x, y: keyPoint.y),
                style: .arrow,
                visible: true,
                scale: fixedScale,
                easing: .easeInOut
            ))
        }

        // Always include the final position
        if let lastPos = allPositions.last, lastPos.time > (keyframes.last?.time ?? 0) {
            keyframes.append(CursorStyleKeyframe(
                time: lastPos.time,
                position: NormalizedPoint(x: lastPos.x, y: lastPos.y),
                style: .arrow,
                visible: true,
                scale: fixedScale,
                easing: .easeInOut
            ))
        }

        // Sort by time and remove duplicates
        keyframes.sort { $0.time < $1.time }
        keyframes = removeDuplicateKeyframes(keyframes)

        return keyframes
    }

    /// Remove duplicate keyframes that occur too close together
    private func removeDuplicateKeyframes(_ keyframes: [CursorStyleKeyframe]) -> [CursorStyleKeyframe] {
        guard keyframes.count > 1 else { return keyframes }

        var result: [CursorStyleKeyframe] = [keyframes[0]]

        for i in 1..<keyframes.count {
            let prev = result.last!
            let curr = keyframes[i]

            // Keep keyframes separated by at least 0.05 seconds
            if curr.time - prev.time >= 0.05 {
                result.append(curr)
            }
        }

        return result
    }

    /// Calculate distance between two positions
    private func positionDistance(from: NormalizedPoint?, to: NormalizedPoint?) -> CGFloat {
        guard let from = from, let to = to else { return 0 }
        let dx = to.x - from.x
        let dy = to.y - from.y
        return sqrt(dx * dx + dy * dy)
    }

    /// Create a simple track when fewer than 4 points exist
    private func createTrackFromPositions(
        _ positions: [MousePositionData],
        settings: CursorInterpolationSettings
    ) -> CursorTrack {
        var keyframes: [CursorStyleKeyframe] = []

        for position in positions {
            keyframes.append(CursorStyleKeyframe(
                time: position.time,
                position: NormalizedPoint(x: position.x, y: position.y),
                style: .arrow,
                visible: true,
                scale: settings.fixedCursorScale,
                easing: .easeInOut
            ))
        }

        return CursorTrack(
            id: UUID(),
            name: "Cursor (Smoothed)",
            isEnabled: true,
            styleKeyframes: keyframes
        )
    }

    // MARK: - Position Filtering

    private func filterPositions(
        _ positions: [MousePositionData],
        settings: CursorInterpolationSettings
    ) -> [MousePositionData] {
        guard positions.count > 1 else { return positions }

        var filtered: [MousePositionData] = [positions[0]]
        var lastPosition = positions[0]

        for position in positions.dropFirst() {
            let dx = position.x - lastPosition.x
            let dy = position.y - lastPosition.y
            let distance = sqrt(dx * dx + dy * dy)

            // Include only when the movement exceeds the minimum distance
            if distance >= settings.minMovementThreshold {
                filtered.append(position)
                lastPosition = position
            }
        }

        return filtered
    }

    // MARK: - Velocity Calculation

    private struct VelocityData {
        let time: TimeInterval
        let velocity: CGFloat  // normalized units per second
        let direction: CGFloat  // radians
    }

    private func calculateVelocities(_ positions: [MousePositionData]) -> [VelocityData] {
        guard positions.count >= 2 else { return [] }

        var velocities: [VelocityData] = []

        for i in 1..<positions.count {
            let prev = positions[i - 1]
            let curr = positions[i]

            let dt = curr.time - prev.time
            guard dt > 0.001 else { continue }  // Guard against division by zero

            let dx = curr.x - prev.x
            let dy = curr.y - prev.y
            let distance = sqrt(dx * dx + dy * dy)
            let velocity = distance / CGFloat(dt)
            let direction = atan2(dy, dx)

            velocities.append(VelocityData(
                time: curr.time,
                velocity: velocity,
                direction: direction
            ))
        }

        return velocities
    }

    // MARK: - Key Point Detection

    private struct KeyPoint {
        let time: TimeInterval
        let x: CGFloat
        let y: CGFloat
        let velocity: CGFloat
        let type: KeyPointType

        enum KeyPointType {
            case directionChange
            case stop
            case acceleration
            case deceleration
        }
    }

    private func detectKeyPoints(
        positions: [MousePositionData],
        velocities: [VelocityData],
        settings: CursorInterpolationSettings
    ) -> [KeyPoint] {
        var keyPoints: [KeyPoint] = []

        guard velocities.count >= 2 else { return keyPoints }

        for i in 1..<velocities.count {
            let prev = velocities[i - 1]
            let curr = velocities[i]

            // Locate the matching position data
            guard let position = positions.first(where: { abs($0.time - curr.time) < 0.02 }) else {
                continue
            }

            // 1. Detect stops (very low velocity to capture meaningful pauses)
            if curr.velocity < 0.005 && prev.velocity > 0.02 {
                keyPoints.append(KeyPoint(
                    time: curr.time,
                    x: position.x,
                    y: position.y,
                    velocity: curr.velocity,
                    type: .stop
                ))
                continue
            }

            // 2. Detect only large direction changes (>= 90 degrees, easing from previous 45-degree threshold)
            let directionChange = abs(curr.direction - prev.direction)
            let normalizedChange = min(directionChange, 2 * .pi - directionChange)
            if normalizedChange > .pi / 2 && curr.velocity > 0.01 {
                keyPoints.append(KeyPoint(
                    time: curr.time,
                    x: position.x,
                    y: position.y,
                    velocity: curr.velocity,
                    type: .directionChange
                ))
                continue
            }

            // Skip acceleration/deceleration detection to avoid unnecessary key points and keep velocity smooth
        }

        // Filter out key points that are too close together (minimum 0.3s, relaxed from 0.1s)
        return filterCloseKeyPoints(keyPoints, minInterval: 0.3)
    }

    private func filterCloseKeyPoints(_ keyPoints: [KeyPoint], minInterval: TimeInterval) -> [KeyPoint] {
        var filtered: [KeyPoint] = []

        for keyPoint in keyPoints {
            if let last = filtered.last {
                if keyPoint.time - last.time >= minInterval {
                    filtered.append(keyPoint)
                }
            } else {
                filtered.append(keyPoint)
            }
        }

        return filtered
    }

    // MARK: - Cursor Scale

    /// Return the fixed cursor scale (removes velocity-based variation)
    private func getCursorScale(settings: CursorInterpolationSettings) -> CGFloat {
        return settings.fixedCursorScale
    }

    // MARK: - Keyframe Optimization

    private func optimizeKeyframes(_ keyframes: [CursorStyleKeyframe]) -> [CursorStyleKeyframe] {
        guard keyframes.count > 2 else { return keyframes }

        var optimized: [CursorStyleKeyframe] = [keyframes[0]]

        for i in 1..<keyframes.count - 1 {
            let prev = keyframes[i - 1]
            let curr = keyframes[i]
            let next = keyframes[i + 1]

            // Skip if the scale is similar
            let scaleDiffPrev = abs(curr.scale - prev.scale)
            let scaleDiffNext = abs(curr.scale - next.scale)

            if scaleDiffPrev > 0.1 || scaleDiffNext > 0.1 {
                optimized.append(curr)
            }
        }

        optimized.append(keyframes.last!)
        optimized.sort { $0.time < $1.time }

        return optimized
    }

    // MARK: - Helpers

    private func createDefaultTrack() -> CursorTrack {
        CursorTrack(
            id: UUID(),
            name: "Cursor (Smoothed)",
            isEnabled: true,
            styleKeyframes: [
                CursorStyleKeyframe(
                    time: 0,
                    style: .arrow,
                    visible: true,
                    scale: 2.0,
                    easing: .easeInOut
                )
            ]
        )
    }
}

// MARK: - Catmull-Rom Spline Utilities

extension CursorInterpolationGenerator {

    /// Catmull-Rom spline interpolation
    /// - Parameters:
    ///   - p0, p1, p2, p3: Control points
    ///   - t: Interpolation parameter (0-1)
    ///   - tension: Tension factor (0.2 produces a natural curve close to the real path)
    /// - Returns: Interpolated point
    static func catmullRom(
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        t: CGFloat,
        tension: CGFloat = 0.2
    ) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t

        let m1x = tension * (p2.x - p0.x)
        let m1y = tension * (p2.y - p0.y)
        let m2x = tension * (p3.x - p1.x)
        let m2y = tension * (p3.y - p1.y)

        let a = 2 * t3 - 3 * t2 + 1
        let b = t3 - 2 * t2 + t
        let c = -2 * t3 + 3 * t2
        let d = t3 - t2

        let x = a * p1.x + b * m1x + c * p2.x + d * m2x
        let y = a * p1.y + b * m1y + c * p2.y + d * m2y

        return CGPoint(x: x, y: y)
    }

    /// Interpolate an array of positions using a Catmull-Rom spline
    static func interpolatePositions(
        _ positions: [MousePositionData],
        outputFrameRate: Double,
        tension: CGFloat = 0.2
    ) -> [MousePositionData] {
        guard positions.count >= 4 else { return positions }

        var interpolated: [MousePositionData] = []
        let frameDuration = 1.0 / outputFrameRate

        for i in 0..<positions.count - 3 {
            let p0 = CGPoint(x: positions[i].x, y: positions[i].y)
            let p1 = CGPoint(x: positions[i + 1].x, y: positions[i + 1].y)
            let p2 = CGPoint(x: positions[i + 2].x, y: positions[i + 2].y)
            let p3 = CGPoint(x: positions[i + 3].x, y: positions[i + 3].y)

            let startTime = positions[i + 1].time
            let endTime = positions[i + 2].time
            let duration = endTime - startTime

            guard duration > 0 else { continue }

            var t: TimeInterval = 0
            while t <= duration {
                let progress = CGFloat(t / duration)
                let point = catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: progress, tension: tension)

                interpolated.append(MousePositionData(
                    time: startTime + t,
                    x: point.x,
                    y: point.y,
                    appBundleID: positions[i + 1].appBundleID,
                    elementInfo: nil
                ))

                t += frameDuration
            }
        }

        return interpolated
    }
}

// MARK: - Cursor Interpolation Generator with Statistics

extension CursorInterpolationGenerator {

    func generateWithStatistics(
        from mouseData: MouseDataSource,
        settings: GeneratorSettings
    ) -> GeneratorResult<CursorTrack> {
        let startTime = Date()

        let track = generate(from: mouseData, settings: settings)

        let processingTime = Date().timeIntervalSince(startTime)

        let keyframeCount = track.styleKeyframes?.count ?? 0

        let statistics = GeneratorStatistics(
            analyzedEvents: mouseData.positions.count,
            generatedKeyframes: keyframeCount,
            processingTime: processingTime,
            additionalInfo: [
                "inputPositions": mouseData.positions.count,
                "smoothingFactor": settings.cursorInterpolation.smoothingFactor
            ]
        )

        return GeneratorResult(
            track: track,
            keyframeCount: keyframeCount,
            statistics: statistics
        )
    }
}
