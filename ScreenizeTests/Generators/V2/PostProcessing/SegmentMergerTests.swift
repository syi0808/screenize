import XCTest
@testable import Screenize

final class SegmentMergerTests: XCTestCase {

    private let defaultSettings = MergeSettings()

    // MARK: - Helpers

    private func makeScene(
        start: TimeInterval,
        end: TimeInterval,
        intent: UserIntent = .clicking
    ) -> CameraScene {
        CameraScene(
            startTime: start, endTime: end, primaryIntent: intent
        )
    }

    private func makeSegment(
        start: TimeInterval,
        end: TimeInterval,
        zoom: CGFloat = 2.0,
        center: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5),
        intent: UserIntent = .clicking
    ) -> SimulatedSceneSegment {
        let scene = makeScene(start: start, end: end, intent: intent)
        let transform = TransformValue(zoom: zoom, center: center)
        let shotPlan = ShotPlan(
            scene: scene,
            shotType: zoom > 2.0 ? .closeUp(zoom: zoom)
                : zoom > 1.0 ? .medium(zoom: zoom) : .wide,
            idealZoom: zoom,
            idealCenter: center
        )
        return SimulatedSceneSegment(
            scene: scene, shotPlan: shotPlan,
            samples: [
                TimedTransform(time: start, transform: transform),
                TimedTransform(time: end, transform: transform)
            ]
        )
    }

    private func makeTransition(
        from: SimulatedSceneSegment,
        to: SimulatedSceneSegment,
        style: TransitionStyle = .directPan(duration: 0.5)
    ) -> SimulatedTransitionSegment {
        SimulatedTransitionSegment(
            fromScene: from.scene, toScene: to.scene,
            transitionPlan: TransitionPlan(
                fromScene: from.scene, toScene: to.scene,
                style: style, easing: .easeInOut
            ),
            startTransform: from.samples.last!.transform,
            endTransform: to.samples.first!.transform
        )
    }

    // MARK: - Empty Path

    func test_merge_emptyPath_returnsEmpty() {
        let path = SimulatedPath(sceneSegments: [], transitionSegments: [])
        let result = SegmentMerger.merge(path, settings: defaultSettings)
        XCTAssertTrue(result.sceneSegments.isEmpty)
    }

    // MARK: - Single Scene

    func test_merge_singleScene_returnsUnchanged() {
        let seg = makeSegment(start: 0, end: 3)
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = SegmentMerger.merge(path, settings: defaultSettings)
        XCTAssertEqual(result.sceneSegments.count, 1)
        XCTAssertEqual(
            result.sceneSegments[0].scene.startTime, 0, accuracy: 0.001
        )
    }

    // MARK: - All Long Enough

    func test_merge_allScenesLongEnough_returnsUnchanged() {
        let seg1 = makeSegment(
            start: 0, end: 2, zoom: 2.0,
            center: NormalizedPoint(x: 0.2, y: 0.2)
        )
        let seg2 = makeSegment(
            start: 2, end: 5, zoom: 1.5,
            center: NormalizedPoint(x: 0.8, y: 0.8)
        )
        let trans = makeTransition(from: seg1, to: seg2)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = SegmentMerger.merge(path, settings: defaultSettings)
        XCTAssertEqual(result.sceneSegments.count, 2)
        XCTAssertEqual(result.transitionSegments.count, 1)
    }

    // MARK: - Short Segment Absorption

    func test_merge_shortSegmentAbsorbedByPrevious() {
        // seg2 is 0.2s (<0.3s min) → absorbed into seg1
        let seg1 = makeSegment(start: 0, end: 3, zoom: 2.0)
        let seg2 = makeSegment(start: 3, end: 3.2, zoom: 2.0)
        let seg3 = makeSegment(
            start: 3.2, end: 6, zoom: 1.5,
            center: NormalizedPoint(x: 0.8, y: 0.8)
        )
        let t1 = makeTransition(from: seg1, to: seg2)
        let t2 = makeTransition(from: seg2, to: seg3)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2, seg3],
            transitionSegments: [t1, t2]
        )
        let result = SegmentMerger.merge(path, settings: defaultSettings)

        // Should have 2 scenes (short one absorbed)
        XCTAssertEqual(result.sceneSegments.count, 2)
        // Should have 1 transition (the one between merged scenes removed)
        XCTAssertEqual(result.transitionSegments.count, 1)
    }

    func test_merge_shortFirstSegmentAbsorbedByNext() {
        // seg1 is 0.1s (<0.3s min), no previous → absorbed into seg2
        let seg1 = makeSegment(start: 0, end: 0.1, zoom: 2.0)
        let seg2 = makeSegment(start: 0.1, end: 3, zoom: 2.0)
        let trans = makeTransition(from: seg1, to: seg2)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = SegmentMerger.merge(path, settings: defaultSettings)
        XCTAssertEqual(result.sceneSegments.count, 1)
        XCTAssertTrue(result.transitionSegments.isEmpty)
    }

    // MARK: - Similar Adjacent Scenes

    func test_merge_similarAdjacentScenes_merged() {
        // Two scenes with nearly identical transforms
        let seg1 = makeSegment(
            start: 0, end: 2, zoom: 2.0,
            center: NormalizedPoint(x: 0.5, y: 0.5)
        )
        let seg2 = makeSegment(
            start: 2, end: 5, zoom: 2.05,
            center: NormalizedPoint(x: 0.52, y: 0.51)
        )
        let trans = makeTransition(from: seg1, to: seg2)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = SegmentMerger.merge(path, settings: defaultSettings)
        XCTAssertEqual(result.sceneSegments.count, 1)
        XCTAssertTrue(result.transitionSegments.isEmpty)
        // Merged scene covers full range
        XCTAssertEqual(
            result.sceneSegments[0].scene.startTime, 0, accuracy: 0.001
        )
        XCTAssertEqual(
            result.sceneSegments[0].scene.endTime, 5, accuracy: 0.001
        )
    }

    func test_merge_differentScenes_notMerged() {
        // Two scenes with significantly different transforms
        let seg1 = makeSegment(
            start: 0, end: 2, zoom: 2.0,
            center: NormalizedPoint(x: 0.2, y: 0.2)
        )
        let seg2 = makeSegment(
            start: 2, end: 5, zoom: 1.5,
            center: NormalizedPoint(x: 0.8, y: 0.8)
        )
        let trans = makeTransition(from: seg1, to: seg2)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = SegmentMerger.merge(path, settings: defaultSettings)
        XCTAssertEqual(result.sceneSegments.count, 2)
    }

    // MARK: - Chain of Short Segments

    func test_merge_chainOfShortSegments_allAbsorbed() {
        let seg1 = makeSegment(start: 0, end: 0.1, zoom: 2.0)
        let seg2 = makeSegment(start: 0.1, end: 0.2, zoom: 2.0)
        let seg3 = makeSegment(start: 0.2, end: 3, zoom: 2.0)
        let t1 = makeTransition(from: seg1, to: seg2)
        let t2 = makeTransition(from: seg2, to: seg3)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2, seg3],
            transitionSegments: [t1, t2]
        )
        let result = SegmentMerger.merge(path, settings: defaultSettings)
        // All short segments absorbed — should have 1 scene
        XCTAssertEqual(result.sceneSegments.count, 1)
        XCTAssertTrue(result.transitionSegments.isEmpty)
    }

    // MARK: - Transition Removal

    func test_merge_removesTransitionBetweenMergedScenes() {
        let seg1 = makeSegment(
            start: 0, end: 2, zoom: 2.0,
            center: NormalizedPoint(x: 0.5, y: 0.5)
        )
        let seg2 = makeSegment(
            start: 2, end: 4, zoom: 2.01,
            center: NormalizedPoint(x: 0.51, y: 0.51)
        )
        let seg3 = makeSegment(
            start: 4, end: 7, zoom: 1.0,
            center: NormalizedPoint(x: 0.5, y: 0.5)
        )
        let t1 = makeTransition(from: seg1, to: seg2)
        let t2 = makeTransition(from: seg2, to: seg3)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2, seg3],
            transitionSegments: [t1, t2]
        )
        let result = SegmentMerger.merge(path, settings: defaultSettings)
        // seg1 and seg2 merge → t1 removed, t2 updated
        XCTAssertEqual(result.sceneSegments.count, 2)
        XCTAssertEqual(result.transitionSegments.count, 1)
    }

    // MARK: - Preserved Samples

    func test_merge_absorbedSceneTimeRange_extended() {
        let seg1 = makeSegment(start: 0, end: 3, zoom: 2.0)
        let seg2 = makeSegment(start: 3, end: 3.1, zoom: 2.0)
        let trans = makeTransition(from: seg1, to: seg2)
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = SegmentMerger.merge(path, settings: defaultSettings)
        XCTAssertEqual(result.sceneSegments.count, 1)
        let merged = result.sceneSegments[0]
        // Merged scene should span the full range
        XCTAssertEqual(merged.scene.startTime, 0, accuracy: 0.001)
        XCTAssertEqual(merged.scene.endTime, 3.1, accuracy: 0.001)
    }
}
