import Foundation
import CoreGraphics

/// Classifies transitions between adjacent camera segments as hold, directPan,
/// or fullTransition based on positional distance and zoom ratio.
enum TransitionResolver {

    struct Settings {
        /// Max distance between segment centers to qualify as hold.
        var holdDistanceThreshold: CGFloat = 0.08
        /// Max zoom ratio between segments to qualify as hold.
        var holdZoomRatioThreshold: CGFloat = 1.1
        /// Max zoom ratio between segments to qualify as directPan.
        var directPanZoomRatioThreshold: CGFloat = 1.25
    }

    /// Resolve transition styles for an array of camera segments.
    ///
    /// - Parameters:
    ///   - segments: The camera segments to classify.
    ///   - intentSpans: Optional intent spans for determining idle status.
    ///   - settings: Thresholds for classification.
    /// - Returns: Segments with transitionStyle set appropriately.
    static func resolve(
        _ segments: [CameraSegment],
        intentSpans: [IntentSpan] = [],
        settings: Settings = .init()
    ) -> [CameraSegment] {
        guard !segments.isEmpty else { return [] }

        var result = segments

        // First segment always gets fullTransition.
        result[0].transitionStyle = .fullTransition

        for i in 1..<result.count {
            // Find the previous active (non-idle) segment.
            guard let prevActiveIdx = findPreviousActive(
                before: i, in: result, intentSpans: intentSpans
            ) else {
                result[i].transitionStyle = .fullTransition
                continue
            }

            let prevTransform = endTransform(of: result[prevActiveIdx])
            let currTransform = startTransform(of: result[i])
            let style = classify(
                from: prevTransform, to: currTransform, settings: settings
            )

            // Apply the classified style to the current segment.
            result[i].transitionStyle = style

            // Propagate style to intermediate idle segments between
            // the previous active and the current segment.
            if style == .hold || style == .directPan {
                for j in (prevActiveIdx + 1)..<i {
                    if isIdle(result[j], intentSpans: intentSpans) {
                        result[j].transitionStyle = style
                    }
                }
            }
        }

        return result
    }

    // MARK: - Classification

    private static func classify(
        from prev: TransformValue,
        to curr: TransformValue,
        settings: Settings
    ) -> TransitionStyle {
        let dx = prev.center.x - curr.center.x
        let dy = prev.center.y - curr.center.y
        let distance = sqrt(dx * dx + dy * dy)
        let zoomRatio = zoomRatio(prev.zoom, curr.zoom)

        if distance < settings.holdDistanceThreshold
            && zoomRatio < settings.holdZoomRatioThreshold {
            return .hold
        }

        if zoomRatio < settings.directPanZoomRatioThreshold {
            return .directPan
        }

        return .fullTransition
    }

    /// Compute the ratio between two zoom levels, always >= 1.0.
    private static func zoomRatio(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let minZ = min(a, b)
        let maxZ = max(a, b)
        guard minZ > 0 else { return maxZ > 0 ? maxZ : 1.0 }
        return maxZ / minZ
    }

    // MARK: - Idle Detection

    /// Determine if a segment is idle, using intentSpans if available,
    /// otherwise falling back to a zoom heuristic.
    private static func isIdle(
        _ segment: CameraSegment,
        intentSpans: [IntentSpan]
    ) -> Bool {
        if !intentSpans.isEmpty {
            let midTime = (segment.startTime + segment.endTime) / 2
            if let span = intentSpans.first(where: {
                $0.startTime <= midTime && $0.endTime >= midTime
            }) {
                if case .idle = span.intent { return true }
                return false
            }
        }

        // Fallback: heuristic based on zoom level.
        let transform = endTransform(of: segment)
        return transform.zoom <= 1.05
    }

    /// Find the index of the previous active (non-idle) segment.
    private static func findPreviousActive(
        before index: Int,
        in segments: [CameraSegment],
        intentSpans: [IntentSpan]
    ) -> Int? {
        for i in stride(from: index - 1, through: 0, by: -1) {
            if !isIdle(segments[i], intentSpans: intentSpans) {
                return i
            }
        }
        return nil
    }

    // MARK: - Transform Extraction

    /// Extract the end transform from a segment.
    private static func endTransform(of segment: CameraSegment) -> TransformValue {
        switch segment.kind {
        case .manual(_, let endTransform):
            return endTransform
        case .continuous(let transforms):
            if let last = transforms.last {
                return last.transform
            }
            return TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        }
    }

    /// Extract the start transform from a segment.
    private static func startTransform(of segment: CameraSegment) -> TransformValue {
        switch segment.kind {
        case .manual(let startTransform, _):
            return startTransform
        case .continuous(let transforms):
            if let first = transforms.first {
                return first.transform
            }
            return TransformValue(zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5))
        }
    }
}
