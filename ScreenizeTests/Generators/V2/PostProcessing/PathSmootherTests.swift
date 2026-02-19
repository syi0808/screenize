import XCTest
@testable import Screenize

final class PathSmootherTests: XCTestCase {

    private let disabledSettings = SmoothingSettings(enabled: false)
    private let enabledSettings = SmoothingSettings(
        enabled: true, windowSize: 5, maxDeviation: 0.02
    )

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

    private func makeShotPlan(
        scene: CameraScene,
        zoom: CGFloat = 2.0,
        center: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5)
    ) -> ShotPlan {
        ShotPlan(
            scene: scene,
            shotType: .medium(zoom: zoom),
            idealZoom: zoom,
            idealCenter: center
        )
    }

    private func makeStaticSegment(
        start: TimeInterval,
        end: TimeInterval,
        zoom: CGFloat = 2.0,
        center: NormalizedPoint = NormalizedPoint(x: 0.5, y: 0.5)
    ) -> SimulatedSceneSegment {
        let scene = makeScene(start: start, end: end)
        let transform = TransformValue(zoom: zoom, center: center)
        return SimulatedSceneSegment(
            scene: scene,
            shotPlan: makeShotPlan(scene: scene, zoom: zoom, center: center),
            samples: [
                TimedTransform(time: start, transform: transform),
                TimedTransform(time: end, transform: transform)
            ]
        )
    }

    // MARK: - Empty Path

    func test_smooth_emptyPath_returnsEmpty() {
        let path = SimulatedPath(sceneSegments: [], transitionSegments: [])
        let result = PathSmoother.smooth(path, settings: enabledSettings)
        XCTAssertTrue(result.sceneSegments.isEmpty)
        XCTAssertTrue(result.transitionSegments.isEmpty)
    }

    // MARK: - Disabled

    func test_smooth_disabled_returnsOriginalPath() {
        let segment = makeStaticSegment(start: 0, end: 5)
        let path = SimulatedPath(
            sceneSegments: [segment], transitionSegments: []
        )
        let result = PathSmoother.smooth(path, settings: disabledSettings)
        XCTAssertEqual(result.sceneSegments.count, 1)
        XCTAssertEqual(result.sceneSegments[0].samples.count, 2)
        XCTAssertEqual(
            result.sceneSegments[0].samples[0].transform,
            segment.samples[0].transform
        )
    }

    // MARK: - Static Hold (No Jitter)

    func test_smooth_staticHoldSamples_returnsUnchanged() {
        let segment = makeStaticSegment(start: 0, end: 3)
        let path = SimulatedPath(
            sceneSegments: [segment], transitionSegments: []
        )
        let result = PathSmoother.smooth(path, settings: enabledSettings)
        XCTAssertEqual(result.sceneSegments[0].samples.count, 2)
        XCTAssertEqual(
            result.sceneSegments[0].samples[0].transform.zoom, 2.0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            result.sceneSegments[0].samples[1].transform.zoom, 2.0,
            accuracy: 0.001
        )
    }

    // MARK: - Jitter Removal

    func test_smooth_enabled_removesSmallJitter() {
        let scene = makeScene(start: 0, end: 2)
        let baseCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let samples = [
            TimedTransform(
                time: 0,
                transform: TransformValue(zoom: 2.0, center: baseCenter)
            ),
            TimedTransform(
                time: 0.5,
                transform: TransformValue(
                    zoom: 2.0,
                    center: NormalizedPoint(x: 0.505, y: 0.503)
                )
            ),
            TimedTransform(
                time: 1.0,
                transform: TransformValue(
                    zoom: 2.0,
                    center: NormalizedPoint(x: 0.498, y: 0.497)
                )
            ),
            TimedTransform(
                time: 1.5,
                transform: TransformValue(
                    zoom: 2.0,
                    center: NormalizedPoint(x: 0.502, y: 0.501)
                )
            ),
            TimedTransform(
                time: 2.0,
                transform: TransformValue(zoom: 2.0, center: baseCenter)
            )
        ]
        let segment = SimulatedSceneSegment(
            scene: scene,
            shotPlan: makeShotPlan(scene: scene),
            samples: samples
        )
        let path = SimulatedPath(
            sceneSegments: [segment], transitionSegments: []
        )
        let result = PathSmoother.smooth(path, settings: enabledSettings)
        let smoothed = result.sceneSegments[0].samples

        // First and last samples are anchors — unchanged
        XCTAssertEqual(smoothed[0].transform, samples[0].transform)
        XCTAssertEqual(
            smoothed[4].transform, samples[4].transform
        )

        // Middle samples should be smoothed closer to average
        for i in 1..<4 {
            let dx = abs(smoothed[i].transform.center.x - 0.5)
            let dy = abs(smoothed[i].transform.center.y - 0.5)
            XCTAssertLessThan(dx, 0.005, "Sample \(i) center.x should be smoothed")
            XCTAssertLessThan(dy, 0.005, "Sample \(i) center.y should be smoothed")
        }
    }

    func test_smooth_enabled_preservesLargeMovement() {
        let scene = makeScene(start: 0, end: 3)
        let samples = [
            TimedTransform(
                time: 0,
                transform: TransformValue(
                    zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3)
                )
            ),
            TimedTransform(
                time: 1.0,
                transform: TransformValue(
                    zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5)
                )
            ),
            TimedTransform(
                time: 2.0,
                transform: TransformValue(
                    zoom: 2.0, center: NormalizedPoint(x: 0.7, y: 0.7)
                )
            ),
            TimedTransform(
                time: 3.0,
                transform: TransformValue(
                    zoom: 2.0, center: NormalizedPoint(x: 0.9, y: 0.9)
                )
            )
        ]
        let segment = SimulatedSceneSegment(
            scene: scene,
            shotPlan: makeShotPlan(scene: scene),
            samples: samples
        )
        let path = SimulatedPath(
            sceneSegments: [segment], transitionSegments: []
        )
        let result = PathSmoother.smooth(path, settings: enabledSettings)
        let smoothed = result.sceneSegments[0].samples

        // Large movement should be preserved (not smoothed to average)
        for i in 1..<3 {
            XCTAssertEqual(
                smoothed[i].transform.center.x,
                samples[i].transform.center.x,
                accuracy: 0.001,
                "Large movement at sample \(i) should not be smoothed"
            )
        }
    }

    // MARK: - Single Scene Segment

    func test_smooth_singleSceneWithOneSample_returnsUnchanged() {
        let scene = makeScene(start: 0, end: 1)
        let transform = TransformValue(
            zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5)
        )
        let segment = SimulatedSceneSegment(
            scene: scene,
            shotPlan: makeShotPlan(scene: scene),
            samples: [TimedTransform(time: 0, transform: transform)]
        )
        let path = SimulatedPath(
            sceneSegments: [segment], transitionSegments: []
        )
        let result = PathSmoother.smooth(path, settings: enabledSettings)
        XCTAssertEqual(result.sceneSegments[0].samples.count, 1)
        XCTAssertEqual(
            result.sceneSegments[0].samples[0].transform, transform
        )
    }

    // MARK: - Transitions Preserved

    func test_smooth_transitionsPreserved() {
        let seg1 = makeStaticSegment(start: 0, end: 3)
        let seg2 = makeStaticSegment(start: 3, end: 6)
        let transition = SimulatedTransitionSegment(
            fromScene: seg1.scene, toScene: seg2.scene,
            transitionPlan: TransitionPlan(
                fromScene: seg1.scene, toScene: seg2.scene,
                style: .directPan(duration: 0.5),
                easing: .easeInOut
            ),
            startTransform: seg1.samples.last!.transform,
            endTransform: seg2.samples.first!.transform
        )
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2],
            transitionSegments: [transition]
        )
        let result = PathSmoother.smooth(path, settings: enabledSettings)
        XCTAssertEqual(result.transitionSegments.count, 1)
        XCTAssertEqual(
            result.transitionSegments[0].startTransform,
            transition.startTransform
        )
        XCTAssertEqual(
            result.transitionSegments[0].endTransform,
            transition.endTransform
        )
    }

    // MARK: - Multiple Scenes

    func test_smooth_multipleScenes_eachSmoothedIndependently() {
        let seg1 = makeStaticSegment(
            start: 0, end: 3, center: NormalizedPoint(x: 0.3, y: 0.3)
        )
        let seg2 = makeStaticSegment(
            start: 3, end: 6, center: NormalizedPoint(x: 0.7, y: 0.7)
        )
        let path = SimulatedPath(
            sceneSegments: [seg1, seg2], transitionSegments: []
        )
        let result = PathSmoother.smooth(path, settings: enabledSettings)
        XCTAssertEqual(result.sceneSegments.count, 2)
        // Scene timestamps preserved
        XCTAssertEqual(
            result.sceneSegments[0].scene.startTime, 0, accuracy: 0.001
        )
        XCTAssertEqual(
            result.sceneSegments[1].scene.startTime, 3, accuracy: 0.001
        )
    }

    // MARK: - Zoom Jitter

    func test_smooth_enabled_smoothsZoomJitter() {
        let scene = makeScene(start: 0, end: 2)
        let center = NormalizedPoint(x: 0.5, y: 0.5)
        let samples = [
            TimedTransform(
                time: 0,
                transform: TransformValue(zoom: 2.0, center: center)
            ),
            TimedTransform(
                time: 0.5,
                transform: TransformValue(zoom: 2.005, center: center)
            ),
            TimedTransform(
                time: 1.0,
                transform: TransformValue(zoom: 1.998, center: center)
            ),
            TimedTransform(
                time: 1.5,
                transform: TransformValue(zoom: 2.003, center: center)
            ),
            TimedTransform(
                time: 2.0,
                transform: TransformValue(zoom: 2.0, center: center)
            )
        ]
        let segment = SimulatedSceneSegment(
            scene: scene,
            shotPlan: makeShotPlan(scene: scene),
            samples: samples
        )
        let path = SimulatedPath(
            sceneSegments: [segment], transitionSegments: []
        )
        let result = PathSmoother.smooth(path, settings: enabledSettings)
        let smoothed = result.sceneSegments[0].samples

        // Middle zoom values should be closer to 2.0
        for i in 1..<4 {
            XCTAssertEqual(
                smoothed[i].transform.zoom, 2.0, accuracy: 0.003,
                "Sample \(i) zoom should be smoothed"
            )
        }
    }
}
