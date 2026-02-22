import XCTest
@testable import Screenize

final class SegmentOptimizerTests: XCTestCase {

    private let defaultSettings = OptimizationSettings()

    // MARK: - Helpers

    private func makeSegment(
        start: TimeInterval,
        end: TimeInterval,
        startZoom: CGFloat = 2.0,
        endZoom: CGFloat = 2.0,
        startCenter: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5),
        endCenter: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5),
        easing: EasingCurve = .linear
    ) -> CameraSegment {
        CameraSegment(
            startTime: start, endTime: end,
            startTransform: TransformValue(zoom: startZoom, center: startCenter),
            endTransform: TransformValue(zoom: endZoom, center: endCenter),
            interpolation: easing
        )
    }

    private func makeTrack(
        segments: [CameraSegment]
    ) -> CameraTrack {
        CameraTrack(name: "Test", segments: segments)
    }

    // MARK: - Empty Track

    func test_optimize_emptyTrack_returnsEmpty() {
        let track = makeTrack(segments: [])
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertTrue(result.segments.isEmpty)
    }

    // MARK: - Single Segment

    func test_optimize_singleSegment_returnsUnchanged() {
        let seg = makeSegment(start: 0, end: 3)
        let track = makeTrack(segments: [seg])
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].startTime, 0, accuracy: 0.001)
        XCTAssertEqual(result.segments[0].endTime, 3, accuracy: 0.001)
    }

    // MARK: - Adjacent Similar Segments Merged

    func test_optimize_adjacentSimilarSegments_merged() {
        let seg1 = makeSegment(start: 0, end: 2)
        let seg2 = makeSegment(start: 2, end: 5)
        let track = makeTrack(segments: [seg1, seg2])
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].startTime, 0, accuracy: 0.001)
        XCTAssertEqual(result.segments[0].endTime, 5, accuracy: 0.001)
    }

    // MARK: - Different Segments Not Merged

    func test_optimize_differentSegments_notMerged() {
        let seg1 = makeSegment(
            start: 0, end: 2, startZoom: 2.0, endZoom: 2.0,
            startCenter: NormalizedPoint(x: 0.3, y: 0.3),
            endCenter: NormalizedPoint(x: 0.3, y: 0.3)
        )
        let seg2 = makeSegment(
            start: 2, end: 5, startZoom: 1.5, endZoom: 1.5,
            startCenter: NormalizedPoint(x: 0.8, y: 0.8),
            endCenter: NormalizedPoint(x: 0.8, y: 0.8)
        )
        let track = makeTrack(segments: [seg1, seg2])
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertEqual(result.segments.count, 2)
    }

    // MARK: - Merged Segment Properties

    func test_optimize_mergedSegment_usesFirstStartTransform() {
        let startT = TransformValue(
            zoom: 2.0, center: NormalizedPoint(x: 0.4, y: 0.4)
        )
        let seg1 = CameraSegment(
            startTime: 0, endTime: 2,
            startTransform: startT,
            endTransform: TransformValue(
                zoom: 2.01, center: NormalizedPoint(x: 0.405, y: 0.405)
            )
        )
        let seg2 = CameraSegment(
            startTime: 2, endTime: 5,
            startTransform: TransformValue(
                zoom: 2.01, center: NormalizedPoint(x: 0.405, y: 0.405)
            ),
            endTransform: TransformValue(
                zoom: 2.02, center: NormalizedPoint(x: 0.41, y: 0.41)
            )
        )
        let track = makeTrack(segments: [seg1, seg2])
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(
            result.segments[0].startTransform.zoom,
            startT.zoom, accuracy: 0.001
        )
        XCTAssertEqual(
            result.segments[0].startTransform.center.x,
            startT.center.x, accuracy: 0.001
        )
    }

    func test_optimize_mergedSegment_usesLastEndTransform() {
        let endT = TransformValue(
            zoom: 2.01, center: NormalizedPoint(x: 0.505, y: 0.505)
        )
        let seg1 = makeSegment(start: 0, end: 2)
        let seg2 = CameraSegment(
            startTime: 2, endTime: 5,
            startTransform: TransformValue(
                zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5)
            ),
            endTransform: endT
        )
        let track = makeTrack(segments: [seg1, seg2])
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(
            result.segments[0].endTransform.zoom,
            endT.zoom, accuracy: 0.001
        )
    }

    // MARK: - Chain Merge

    func test_optimize_chainOfSimilarSegments_allMerged() {
        let seg1 = makeSegment(start: 0, end: 1)
        let seg2 = makeSegment(start: 1, end: 2)
        let seg3 = makeSegment(start: 2, end: 3)
        let track = makeTrack(segments: [seg1, seg2, seg3])
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].startTime, 0, accuracy: 0.001)
        XCTAssertEqual(result.segments[0].endTime, 3, accuracy: 0.001)
    }

    // MARK: - Non-Adjacent Segments

    func test_optimize_nonAdjacentSegments_notMerged() {
        // Gap between segments
        let seg1 = makeSegment(start: 0, end: 2)
        let seg2 = makeSegment(start: 3, end: 5)
        let track = makeTrack(segments: [seg1, seg2])
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertEqual(result.segments.count, 2)
    }

    // MARK: - Disabled

    func test_optimize_disabled_returnsOriginal() {
        let disabledSettings = OptimizationSettings(mergeConsecutiveHolds: false)
        let seg1 = makeSegment(start: 0, end: 2)
        let seg2 = makeSegment(start: 2, end: 5)
        let track = makeTrack(segments: [seg1, seg2])
        let result = SegmentOptimizer.optimize(
            track, settings: disabledSettings
        )
        XCTAssertEqual(result.segments.count, 2)
    }

    // MARK: - Zoom Threshold

    func test_optimize_zoomDiffAtThreshold_notMerged() {
        // Zoom difference exactly at the threshold boundary
        let threshold = defaultSettings.negligibleZoomDiff
        let seg1 = makeSegment(start: 0, end: 2, startZoom: 2.0, endZoom: 2.0)
        let seg2 = makeSegment(
            start: 2, end: 5,
            startZoom: 2.0 + threshold + 0.01,
            endZoom: 2.0 + threshold + 0.01
        )
        let track = makeTrack(segments: [seg1, seg2])
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertEqual(result.segments.count, 2)
    }

    // MARK: - Track Properties Preserved

    func test_optimize_preservesTrackProperties() {
        let seg = makeSegment(start: 0, end: 3)
        let track = CameraTrack(
            name: "Custom Name", isEnabled: false, segments: [seg]
        )
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertEqual(result.name, "Custom Name")
        XCTAssertFalse(result.isEnabled)
    }

    // MARK: - Interpolation Preserved

    func test_optimize_mergedSegment_preservesFirstInterpolation() {
        let seg1 = makeSegment(
            start: 0, end: 2, easing: .easeOut
        )
        let seg2 = makeSegment(
            start: 2, end: 5, easing: .easeIn
        )
        let track = makeTrack(segments: [seg1, seg2])
        let result = SegmentOptimizer.optimize(track, settings: defaultSettings)
        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments[0].interpolation, .easeOut)
    }
}
