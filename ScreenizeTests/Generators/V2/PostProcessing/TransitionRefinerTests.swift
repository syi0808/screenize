import XCTest
@testable import Screenize

final class TransitionRefinerTests: XCTestCase {

    private let defaultSettings = TransitionRefinementSettings()

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
        center: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5)
    ) -> SimulatedSceneSegment {
        let scene = makeScene(start: start, end: end)
        let transform = TransformValue(zoom: zoom, center: center)
        let shotPlan = ShotPlan(
            scene: scene,
            shotType: .medium(zoom: zoom),
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

    // MARK: - Empty Path

    func test_refine_emptyPath_returnsEmpty() {
        let path = SimulatedPath(sceneSegments: [], transitionSegments: [])
        let result = TransitionRefiner.refine(
            path, settings: defaultSettings
        )
        XCTAssertTrue(result.sceneSegments.isEmpty)
        XCTAssertTrue(result.transitionSegments.isEmpty)
    }

    // MARK: - No Transitions

    func test_refine_noTransitions_returnsOriginal() {
        let seg = makeSegment(start: 0, end: 3)
        let path = SimulatedPath(
            sceneSegments: [seg], transitionSegments: []
        )
        let result = TransitionRefiner.refine(
            path, settings: defaultSettings
        )
        XCTAssertEqual(result.sceneSegments.count, 1)
        XCTAssertTrue(result.transitionSegments.isEmpty)
    }

    // MARK: - Disabled

    func test_refine_disabled_returnsOriginal() {
        let seg1 = makeSegment(
            start: 0, end: 3, center: NormalizedPoint(x: 0.3, y: 0.3)
        )
        let seg2 = makeSegment(
            start: 3, end: 6, center: NormalizedPoint(x: 0.7, y: 0.7)
        )
        // Transition with mismatched transforms
        let mismatchedStart = TransformValue(
            zoom: 1.5, center: NormalizedPoint(x: 0.4, y: 0.4)
        )
        let mismatchedEnd = TransformValue(
            zoom: 1.8, center: NormalizedPoint(x: 0.6, y: 0.6)
        )
        let trans = SimulatedTransitionSegment(
            fromScene: seg1.scene, toScene: seg2.scene,
            transitionPlan: TransitionPlan(
                fromScene: seg1.scene, toScene: seg2.scene,
                style: .directPan(duration: 0.5), easing: .easeInOut
            ),
            startTransform: mismatchedStart,
            endTransform: mismatchedEnd
        )
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let disabled = TransitionRefinementSettings(enabled: false)
        let result = TransitionRefiner.refine(path, settings: disabled)
        // Should not snap transforms
        XCTAssertEqual(
            result.transitionSegments[0].startTransform.zoom, 1.5,
            accuracy: 0.001
        )
    }

    // MARK: - Transform Snapping

    func test_refine_snapsStartTransformToSceneEnd() {
        let seg1 = makeSegment(
            start: 0, end: 3, zoom: 2.0,
            center: NormalizedPoint(x: 0.3, y: 0.3)
        )
        let seg2 = makeSegment(
            start: 3, end: 6, zoom: 1.5,
            center: NormalizedPoint(x: 0.7, y: 0.7)
        )
        // Transition with slightly wrong startTransform
        let wrongStart = TransformValue(
            zoom: 1.9, center: NormalizedPoint(x: 0.35, y: 0.35)
        )
        let trans = SimulatedTransitionSegment(
            fromScene: seg1.scene, toScene: seg2.scene,
            transitionPlan: TransitionPlan(
                fromScene: seg1.scene, toScene: seg2.scene,
                style: .directPan(duration: 0.5), easing: .easeInOut
            ),
            startTransform: wrongStart,
            endTransform: seg2.samples.first!.transform
        )
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = TransitionRefiner.refine(
            path, settings: defaultSettings
        )
        let refined = result.transitionSegments[0]

        // startTransform should now match seg1's last sample
        XCTAssertEqual(
            refined.startTransform.zoom,
            seg1.samples.last!.transform.zoom,
            accuracy: 0.001
        )
        XCTAssertEqual(
            refined.startTransform.center.x,
            seg1.samples.last!.transform.center.x,
            accuracy: 0.001
        )
    }

    func test_refine_snapsEndTransformToSceneStart() {
        let seg1 = makeSegment(
            start: 0, end: 3, zoom: 2.0,
            center: NormalizedPoint(x: 0.3, y: 0.3)
        )
        let seg2 = makeSegment(
            start: 3, end: 6, zoom: 1.5,
            center: NormalizedPoint(x: 0.7, y: 0.7)
        )
        // Transition with slightly wrong endTransform
        let wrongEnd = TransformValue(
            zoom: 1.6, center: NormalizedPoint(x: 0.65, y: 0.65)
        )
        let trans = SimulatedTransitionSegment(
            fromScene: seg1.scene, toScene: seg2.scene,
            transitionPlan: TransitionPlan(
                fromScene: seg1.scene, toScene: seg2.scene,
                style: .directPan(duration: 0.5), easing: .easeInOut
            ),
            startTransform: seg1.samples.last!.transform,
            endTransform: wrongEnd
        )
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = TransitionRefiner.refine(
            path, settings: defaultSettings
        )
        let refined = result.transitionSegments[0]

        // endTransform should now match seg2's first sample
        XCTAssertEqual(
            refined.endTransform.zoom,
            seg2.samples.first!.transform.zoom,
            accuracy: 0.001
        )
        XCTAssertEqual(
            refined.endTransform.center.y,
            seg2.samples.first!.transform.center.y,
            accuracy: 0.001
        )
    }

    // MARK: - Cut Transition

    func test_refine_cutTransition_alsoSnapped() {
        let seg1 = makeSegment(
            start: 0, end: 3, zoom: 2.0,
            center: NormalizedPoint(x: 0.3, y: 0.3)
        )
        let seg2 = makeSegment(
            start: 3, end: 6, zoom: 1.5,
            center: NormalizedPoint(x: 0.7, y: 0.7)
        )
        let wrongStart = TransformValue(
            zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5)
        )
        let wrongEnd = TransformValue(
            zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5)
        )
        let trans = SimulatedTransitionSegment(
            fromScene: seg1.scene, toScene: seg2.scene,
            transitionPlan: TransitionPlan(
                fromScene: seg1.scene, toScene: seg2.scene,
                style: .cut, easing: .linear
            ),
            startTransform: wrongStart,
            endTransform: wrongEnd
        )
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = TransitionRefiner.refine(
            path, settings: defaultSettings
        )
        let refined = result.transitionSegments[0]
        XCTAssertEqual(refined.startTransform.zoom, 2.0, accuracy: 0.001)
        XCTAssertEqual(refined.endTransform.zoom, 1.5, accuracy: 0.001)
    }

    // MARK: - Multiple Transitions

    func test_refine_multipleTransitions_allSnapped() {
        let seg1 = makeSegment(
            start: 0, end: 2, zoom: 2.0,
            center: NormalizedPoint(x: 0.2, y: 0.2)
        )
        let seg2 = makeSegment(
            start: 2, end: 4, zoom: 1.5,
            center: NormalizedPoint(x: 0.5, y: 0.5)
        )
        let seg3 = makeSegment(
            start: 4, end: 6, zoom: 2.5,
            center: NormalizedPoint(x: 0.8, y: 0.8)
        )
        let wrongT = TransformValue(
            zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5)
        )
        let t1 = SimulatedTransitionSegment(
            fromScene: seg1.scene, toScene: seg2.scene,
            transitionPlan: TransitionPlan(
                fromScene: seg1.scene, toScene: seg2.scene,
                style: .directPan(duration: 0.5), easing: .easeInOut
            ),
            startTransform: wrongT, endTransform: wrongT
        )
        let t2 = SimulatedTransitionSegment(
            fromScene: seg2.scene, toScene: seg3.scene,
            transitionPlan: TransitionPlan(
                fromScene: seg2.scene, toScene: seg3.scene,
                style: .directPan(duration: 0.5), easing: .easeInOut
            ),
            startTransform: wrongT, endTransform: wrongT
        )
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2, seg3],
            transitionSegments: [t1, t2]
        )
        let result = TransitionRefiner.refine(
            path, settings: defaultSettings
        )
        XCTAssertEqual(result.transitionSegments.count, 2)

        // First transition: start=seg1.end, end=seg2.start
        XCTAssertEqual(
            result.transitionSegments[0].startTransform.zoom, 2.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            result.transitionSegments[0].endTransform.zoom, 1.5,
            accuracy: 0.001
        )
        // Second transition: start=seg2.end, end=seg3.start
        XCTAssertEqual(
            result.transitionSegments[1].startTransform.zoom, 1.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            result.transitionSegments[1].endTransform.zoom, 2.5,
            accuracy: 0.001
        )
    }

    // MARK: - Scene Segments Unchanged

    func test_refine_doesNotModifySceneSegments() {
        let seg1 = makeSegment(start: 0, end: 3)
        let seg2 = makeSegment(start: 3, end: 6)
        let trans = SimulatedTransitionSegment(
            fromScene: seg1.scene, toScene: seg2.scene,
            transitionPlan: TransitionPlan(
                fromScene: seg1.scene, toScene: seg2.scene,
                style: .directPan(duration: 0.5), easing: .easeInOut
            ),
            startTransform: TransformValue(
                zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5)
            ),
            endTransform: TransformValue(
                zoom: 1.0, center: NormalizedPoint(x: 0.5, y: 0.5)
            )
        )
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = TransitionRefiner.refine(
            path, settings: defaultSettings
        )
        XCTAssertEqual(result.sceneSegments.count, 2)
        XCTAssertEqual(
            result.sceneSegments[0].samples.count,
            seg1.samples.count
        )
    }

    // MARK: - Transition Plan Preserved

    func test_refine_preservesTransitionPlanProperties() {
        let seg1 = makeSegment(start: 0, end: 3)
        let seg2 = makeSegment(start: 3, end: 6)
        let style = TransitionStyle.zoomOutAndPan(duration: 0.9)
        let trans = SimulatedTransitionSegment(
            fromScene: seg1.scene, toScene: seg2.scene,
            transitionPlan: TransitionPlan(
                fromScene: seg1.scene, toScene: seg2.scene,
                style: style,
                easing: .spring(dampingRatio: 0.85, response: 0.5)
            ),
            startTransform: TransformValue(
                zoom: 1.0, center: .center
            ),
            endTransform: TransformValue(
                zoom: 1.0, center: .center
            )
        )
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: [trans]
        )
        let result = TransitionRefiner.refine(
            path, settings: defaultSettings
        )
        let refined = result.transitionSegments[0]

        // Style and easing should be preserved
        if case let .zoomOutAndPan(dur) = refined.transitionPlan.style {
            XCTAssertEqual(dur, 0.9, accuracy: 0.001)
        } else {
            XCTFail("Expected zoomOutAndPan style")
        }
    }
}
