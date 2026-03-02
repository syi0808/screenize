import Foundation
import CoreGraphics

// MARK: - Event Timeline

/// Merged, time-sorted stream of all recording events.
struct EventTimeline {

    private enum SamplingZone: Int, Comparable {
        case base = 0
        case boundary = 1
        case burst = 2

        static func < (lhs: SamplingZone, rhs: SamplingZone) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private struct MouseMoveCandidate {
        let index: Int
        let position: MousePositionData
        let zone: SamplingZone
    }

    /// Adaptive sampling policy for mouse-move events.
    struct SamplingPolicy {
        var baseMouseMoveInterval: TimeInterval = 0.10
        var boundaryMouseMoveInterval: TimeInterval = 1.0 / 20.0
        var burstMouseMoveInterval: TimeInterval = 1.0 / 45.0
        var burstWindow: TimeInterval = 0.35
        var boundaryWindow: TimeInterval = 1.0
        var boundaryGapThreshold: TimeInterval = 1.0
        var maxAverageMouseMoveRate: Double = 20.0

        static let `default` = Self()
    }

    /// Sampling diagnostics for observability and quality tracking.
    struct SamplingDiagnostics {
        let duration: TimeInterval
        let sourceMouseMoveCount: Int
        let selectedMouseMoveCount: Int
        let baseSampleCount: Int
        let boundarySampleCount: Int
        let burstSampleCount: Int
        let anchorCount: Int
        let missedAnchorCount: Int
        let budgetApplied: Bool
        let sourceSamplesPerSecond: Double
        let effectiveSamplesPerSecond: Double
    }

    /// All events sorted by time.
    let events: [UnifiedEvent]

    /// Recording duration in seconds.
    let duration: TimeInterval

    // MARK: - Building

    /// Build a unified event timeline from a mouse data source.
    /// Mouse move events are sampled adaptively around high-entropy windows.
    static func build(
        from mouseData: MouseDataSource,
        uiStateSamples: [UIStateSample] = [],
        samplingPolicy: SamplingPolicy = .default,
        diagnosticsHandler: ((SamplingDiagnostics) -> Void)? = nil
    ) -> Self {
        var unified: [UnifiedEvent] = []
        let samplingResult = sampledMousePositions(
            from: mouseData,
            policy: samplingPolicy
        )
        diagnosticsHandler?(samplingResult.diagnostics)

        // Mouse positions
        for pos in samplingResult.positions {
            unified.append(UnifiedEvent(
                time: pos.time,
                kind: .mouseMove,
                position: pos.position,
                metadata: EventMetadata(
                    appBundleID: pos.appBundleID,
                    elementInfo: pos.elementInfo
                )
            ))
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
                    appBundleID: normalizedAppIdentifier(
                        sample.elementInfo?.applicationName
                    ),
                    elementInfo: sample.elementInfo,
                    caretBounds: sample.caretBounds
                )
            ))
        }

        unified.sort { $0.time < $1.time }

        return Self(events: unified, duration: mouseData.duration)
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

    private static func normalizedAppIdentifier(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

}

private extension EventTimeline {
    static func sampledMousePositions(
        from mouseData: MouseDataSource,
        policy: SamplingPolicy
    ) -> (positions: [MousePositionData], diagnostics: SamplingDiagnostics) {
        let sourcePositions = mouseData.positions
        guard !sourcePositions.isEmpty else {
            let diagnostics = SamplingDiagnostics(
                duration: mouseData.duration,
                sourceMouseMoveCount: 0,
                selectedMouseMoveCount: 0,
                baseSampleCount: 0,
                boundarySampleCount: 0,
                burstSampleCount: 0,
                anchorCount: 0,
                missedAnchorCount: 0,
                budgetApplied: false,
                sourceSamplesPerSecond: 0,
                effectiveSamplesPerSecond: 0
            )
            return ([], diagnostics)
        }

        let actionAnchors = actionAnchors(from: mouseData)
        let boundaryAnchors = makeBoundaryAnchors(
            from: actionAnchors,
            gapThreshold: max(0.1, policy.boundaryGapThreshold)
        )

        let baseInterval = max(0.01, policy.baseMouseMoveInterval)
        let boundaryInterval = max(0.01, min(policy.boundaryMouseMoveInterval, baseInterval))
        let burstInterval = max(0.005, min(policy.burstMouseMoveInterval, boundaryInterval))

        var selectedCandidates: [MouseMoveCandidate] = []
        selectedCandidates.reserveCapacity(sourcePositions.count)

        var lastAcceptedTime: TimeInterval = -.greatestFiniteMagnitude
        for (index, position) in sourcePositions.enumerated() {
            let zone = samplingZone(
                at: position.time,
                actionAnchors: actionAnchors,
                boundaryAnchors: boundaryAnchors,
                burstWindow: max(0.01, policy.burstWindow),
                boundaryWindow: max(policy.burstWindow, policy.boundaryWindow)
            )
            let requiredInterval: TimeInterval
            switch zone {
            case .base:
                requiredInterval = baseInterval
            case .boundary:
                requiredInterval = boundaryInterval
            case .burst:
                requiredInterval = burstInterval
            }

            if position.time - lastAcceptedTime >= requiredInterval {
                selectedCandidates.append(
                    MouseMoveCandidate(index: index, position: position, zone: zone)
                )
                lastAcceptedTime = position.time
            }
        }

        let maxSamples = max(
            1,
            Int(ceil(mouseData.duration * max(1.0, policy.maxAverageMouseMoveRate)))
        )
        let budgetApplied = selectedCandidates.count > maxSamples
        let budgetedCandidates = budgetApplied
            ? enforceBudget(candidates: selectedCandidates, maxSamples: maxSamples)
            : selectedCandidates

        let selectedPositions = budgetedCandidates.map(\.position)
        let selectedTimes = selectedPositions.map(\.time)
        let baseCount = budgetedCandidates.filter { $0.zone == .base }.count
        let boundaryCount = budgetedCandidates.filter { $0.zone == .boundary }.count
        let burstCount = budgetedCandidates.filter { $0.zone == .burst }.count
        let missedAnchors = countMissedAnchors(
            anchors: actionAnchors,
            sampleTimes: selectedTimes,
            maxDistance: max(0.04, policy.burstMouseMoveInterval * 1.5)
        )
        let safeDuration = max(mouseData.duration, 0.001)
        let diagnostics = SamplingDiagnostics(
            duration: mouseData.duration,
            sourceMouseMoveCount: sourcePositions.count,
            selectedMouseMoveCount: selectedPositions.count,
            baseSampleCount: baseCount,
            boundarySampleCount: boundaryCount,
            burstSampleCount: burstCount,
            anchorCount: actionAnchors.count,
            missedAnchorCount: missedAnchors,
            budgetApplied: budgetApplied,
            sourceSamplesPerSecond: Double(sourcePositions.count) / safeDuration,
            effectiveSamplesPerSecond: Double(selectedPositions.count) / safeDuration
        )

        return (selectedPositions, diagnostics)
    }

    static func actionAnchors(from mouseData: MouseDataSource) -> [TimeInterval] {
        let clickAnchors = mouseData.clicks.map(\.time)
        let keyAnchors = mouseData.keyboardEvents.map(\.time)
        let dragAnchors = mouseData.dragEvents.flatMap { [$0.startTime, $0.endTime] }
        let all = (clickAnchors + keyAnchors + dragAnchors)
            .map { min(max(0, $0), mouseData.duration) }
            .sorted()

        guard !all.isEmpty else { return [] }
        var deduped: [TimeInterval] = []
        deduped.reserveCapacity(all.count)
        for value in all {
            if let last = deduped.last, abs(last - value) < 0.01 {
                continue
            }
            deduped.append(value)
        }
        return deduped
    }

    static func makeBoundaryAnchors(
        from anchors: [TimeInterval],
        gapThreshold: TimeInterval
    ) -> [TimeInterval] {
        guard anchors.count >= 2 else { return anchors }
        var boundaries: [TimeInterval] = anchors
        for index in 1..<anchors.count {
            let previous = anchors[index - 1]
            let current = anchors[index]
            if current - previous >= gapThreshold {
                boundaries.append(previous)
                boundaries.append(current)
            }
        }
        return boundaries.sorted()
    }

    private static func samplingZone(
        at time: TimeInterval,
        actionAnchors: [TimeInterval],
        boundaryAnchors: [TimeInterval],
        burstWindow: TimeInterval,
        boundaryWindow: TimeInterval
    ) -> SamplingZone {
        if nearestDistance(to: time, in: actionAnchors) <= burstWindow {
            return .burst
        }
        if nearestDistance(to: time, in: boundaryAnchors) <= boundaryWindow {
            return .boundary
        }
        return .base
    }

    static func nearestDistance(
        to target: TimeInterval,
        in sortedValues: [TimeInterval]
    ) -> TimeInterval {
        guard !sortedValues.isEmpty else { return .greatestFiniteMagnitude }

        var low = 0
        var high = sortedValues.count
        while low < high {
            let mid = (low + high) / 2
            if sortedValues[mid] < target {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var best = TimeInterval.greatestFiniteMagnitude
        if low < sortedValues.count {
            best = min(best, abs(sortedValues[low] - target))
        }
        if low > 0 {
            best = min(best, abs(sortedValues[low - 1] - target))
        }
        return best
    }

    static func countMissedAnchors(
        anchors: [TimeInterval],
        sampleTimes: [TimeInterval],
        maxDistance: TimeInterval
    ) -> Int {
        guard !anchors.isEmpty else { return 0 }
        guard !sampleTimes.isEmpty else { return anchors.count }

        return anchors.reduce(into: 0) { misses, anchor in
            if nearestDistance(to: anchor, in: sampleTimes) > maxDistance {
                misses += 1
            }
        }
    }

    private static func enforceBudget(
        candidates: [MouseMoveCandidate],
        maxSamples: Int
    ) -> [MouseMoveCandidate] {
        guard candidates.count > maxSamples else { return candidates }

        var selected: [MouseMoveCandidate] = []
        var used = Set<Int>()

        func appendEvenly(_ zone: SamplingZone, budget: Int) {
            guard budget > 0 else { return }
            let scoped = candidates.filter { $0.zone == zone }
            for candidate in evenlySelected(scoped, targetCount: budget) {
                if used.insert(candidate.index).inserted {
                    selected.append(candidate)
                }
            }
        }

        var remaining = maxSamples

        let burst = candidates.filter { $0.zone == .burst }
        appendEvenly(.burst, budget: min(remaining, burst.count))
        remaining = max(0, maxSamples - selected.count)
        guard remaining > 0 else {
            return selected.sorted { $0.position.time < $1.position.time }
        }

        let boundary = candidates.filter { $0.zone == .boundary }
        appendEvenly(.boundary, budget: min(remaining, boundary.count))
        remaining = max(0, maxSamples - selected.count)
        guard remaining > 0 else {
            return selected.sorted { $0.position.time < $1.position.time }
        }

        let base = candidates.filter { $0.zone == .base }
        appendEvenly(.base, budget: min(remaining, base.count))
        remaining = max(0, maxSamples - selected.count)

        if remaining > 0 {
            let fallback = candidates.filter { !used.contains($0.index) }
            for candidate in evenlySelected(fallback, targetCount: remaining) {
                if used.insert(candidate.index).inserted {
                    selected.append(candidate)
                }
            }
        }

        return selected.sorted { $0.position.time < $1.position.time }
    }

    private static func evenlySelected(
        _ candidates: [MouseMoveCandidate],
        targetCount: Int
    ) -> [MouseMoveCandidate] {
        guard targetCount > 0, !candidates.isEmpty else { return [] }
        guard targetCount < candidates.count else { return candidates }

        if targetCount == 1 {
            return [candidates[0]]
        }

        let step = Double(candidates.count - 1) / Double(targetCount - 1)
        var selected: [MouseMoveCandidate] = []
        selected.reserveCapacity(targetCount)
        var used = Set<Int>()

        for i in 0..<targetCount {
            let raw = Int(round(Double(i) * step))
            let index = min(max(0, raw), candidates.count - 1)
            if used.insert(index).inserted {
                selected.append(candidates[index])
            }
        }

        if selected.count < targetCount {
            for (index, candidate) in candidates.enumerated() where !used.contains(index) {
                selected.append(candidate)
                if selected.count == targetCount {
                    break
                }
            }
        }

        return selected
    }
}
