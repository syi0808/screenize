import Foundation
import CoreGraphics

/// Caches spring-simulated transforms for manual camera segments.
/// The entire cache is invalidated on any segment edit because
/// SegmentSpringSimulator carries velocity between segments.
final class SpringSimulationCache {

    private var cache: [UUID: [TimedTransform]] = [:]
    private(set) var isValid: Bool = false

    /// Look up cached spring transforms for a segment.
    func transforms(for segmentID: UUID) -> [TimedTransform]? {
        cache[segmentID]
    }

    /// Run spring simulation on the given segments and cache results.
    /// Only `.manual` segments produce cached entries.
    func populate(
        segments: [CameraSegment],
        config: SegmentSpringSimulator.Config = .init(),
        cursorSpeeds: [UUID: CGFloat] = [:]
    ) {
        let simulated = SegmentSpringSimulator.simulate(
            segments: segments,
            config: config,
            cursorSpeeds: cursorSpeeds
        )
        cache.removeAll()
        for (original, result) in zip(segments, simulated) {
            if case .manual = original.kind,
               case .continuous(let transforms) = result.kind {
                cache[original.id] = transforms
            }
        }
        isValid = true
    }

    /// Clear all cached data.
    func invalidate() {
        cache.removeAll()
        isValid = false
    }
}
