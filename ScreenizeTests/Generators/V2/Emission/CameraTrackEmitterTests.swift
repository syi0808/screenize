import XCTest
@testable import Screenize

final class CameraTrackEmitterTests: XCTestCase {

    // MARK: - Empty

    func test_emit_emptyPath_returnsEmptyTrack() {
        let path = SimulatedPath(sceneSegments: [], transitionSegments: [])
        let track = CameraTrackEmitter.emit(path, duration: 10.0)
        XCTAssertTrue(track.segments.isEmpty)
    }

    // MARK: - Single Scene (Static Hold)

    func test_emit_singleStaticHold_oneSegment() {
        let transform = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.4, y: 0.6))
        let scene = CameraScene(startTime: 0, endTime: 5, primaryIntent: .clicking)
        let shotPlan = ShotPlan(scene: scene, shotType: .medium(zoom: 2.0), idealZoom: 2.0, idealCenter: NormalizedPoint(x: 0.4, y: 0.6))
        let segment = SimulatedSceneSegment(
            scene: scene, shotPlan: shotPlan,
            samples: [
                TimedTransform(time: 0, transform: transform),
                TimedTransform(time: 5, transform: transform)
            ]
        )
        let path = SimulatedPath(sceneSegments: [segment], transitionSegments: [])
        let track = CameraTrackEmitter.emit(path, duration: 5.0)
        XCTAssertEqual(track.segments.count, 1)
        XCTAssertEqual(track.segments[0].startTime, 0, accuracy: 0.01)
        XCTAssertEqual(track.segments[0].endTime, 5, accuracy: 0.01)
        XCTAssertEqual(track.segments[0].startTransform.zoom, 2.0, accuracy: 0.01)
        XCTAssertEqual(track.segments[0].endTransform.zoom, 2.0, accuracy: 0.01)
    }

    // MARK: - With Direct Pan Transition

    func test_emit_directPanTransition_producesSegments() {
        let t1 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))
        let t2 = TransformValue(zoom: 1.5, center: NormalizedPoint(x: 0.7, y: 0.7))
        let scene1 = CameraScene(startTime: 0, endTime: 3, primaryIntent: .clicking)
        let scene2 = CameraScene(startTime: 3, endTime: 6, primaryIntent: .clicking)
        let shot1 = ShotPlan(scene: scene1, shotType: .medium(zoom: 2.0), idealZoom: 2.0, idealCenter: t1.center)
        let shot2 = ShotPlan(scene: scene2, shotType: .medium(zoom: 1.5), idealZoom: 1.5, idealCenter: t2.center)

        let sceneSegs = [
            SimulatedSceneSegment(scene: scene1, shotPlan: shot1, samples: [
                TimedTransform(time: 0, transform: t1),
                TimedTransform(time: 3, transform: t1)
            ]),
            SimulatedSceneSegment(scene: scene2, shotPlan: shot2, samples: [
                TimedTransform(time: 3, transform: t2),
                TimedTransform(time: 6, transform: t2)
            ])
        ]
        let transition = TransitionPlan(
            fromScene: scene1, toScene: scene2,
            style: .directPan(duration: 0.5),
            easing: .spring(dampingRatio: 0.85, response: 0.5)
        )
        let transSeg = SimulatedTransitionSegment(
            fromScene: scene1, toScene: scene2,
            transitionPlan: transition,
            startTransform: t1, endTransform: t2
        )
        let path = SimulatedPath(sceneSegments: sceneSegs, transitionSegments: [transSeg])
        let track = CameraTrackEmitter.emit(path, duration: 6.0)

        // Should have scene1 + transition + scene2 = 3 segments
        XCTAssertEqual(track.segments.count, 3)
    }

    // MARK: - With ZoomOutAndIn Transition

    func test_emit_zoomOutAndInTransition_producesTwoTransitionSegments() {
        let t1 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.2, y: 0.2))
        let t2 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.8, y: 0.8))
        let scene1 = CameraScene(startTime: 0, endTime: 3, primaryIntent: .clicking)
        let scene2 = CameraScene(startTime: 3, endTime: 6, primaryIntent: .clicking)
        let shot1 = ShotPlan(scene: scene1, shotType: .medium(zoom: 2.0), idealZoom: 2.0, idealCenter: t1.center)
        let shot2 = ShotPlan(scene: scene2, shotType: .medium(zoom: 2.0), idealZoom: 2.0, idealCenter: t2.center)

        let sceneSegs = [
            SimulatedSceneSegment(scene: scene1, shotPlan: shot1, samples: [
                TimedTransform(time: 0, transform: t1),
                TimedTransform(time: 3, transform: t1)
            ]),
            SimulatedSceneSegment(scene: scene2, shotPlan: shot2, samples: [
                TimedTransform(time: 3, transform: t2),
                TimedTransform(time: 6, transform: t2)
            ])
        ]
        let transition = TransitionPlan(
            fromScene: scene1, toScene: scene2,
            style: .zoomOutAndIn(outDuration: 0.5, inDuration: 0.5),
            easing: .easeOut
        )
        let transSeg = SimulatedTransitionSegment(
            fromScene: scene1, toScene: scene2,
            transitionPlan: transition,
            startTransform: t1, endTransform: t2
        )
        let path = SimulatedPath(sceneSegments: sceneSegs, transitionSegments: [transSeg])
        let track = CameraTrackEmitter.emit(path, duration: 6.0)

        // Should have scene1 + zoomOut + zoomIn + scene2 = 4 segments
        XCTAssertEqual(track.segments.count, 4)
    }

    // MARK: - Segments Time-Sorted

    func test_emit_segmentsAreTimeSorted() {
        let t1 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))
        let t2 = TransformValue(zoom: 1.5, center: NormalizedPoint(x: 0.7, y: 0.7))
        let scene1 = CameraScene(startTime: 0, endTime: 3, primaryIntent: .clicking)
        let scene2 = CameraScene(startTime: 3, endTime: 6, primaryIntent: .clicking)
        let shot1 = ShotPlan(scene: scene1, shotType: .medium(zoom: 2.0), idealZoom: 2.0, idealCenter: t1.center)
        let shot2 = ShotPlan(scene: scene2, shotType: .medium(zoom: 1.5), idealZoom: 1.5, idealCenter: t2.center)

        let sceneSegs = [
            SimulatedSceneSegment(scene: scene1, shotPlan: shot1, samples: [
                TimedTransform(time: 0, transform: t1), TimedTransform(time: 3, transform: t1)
            ]),
            SimulatedSceneSegment(scene: scene2, shotPlan: shot2, samples: [
                TimedTransform(time: 3, transform: t2), TimedTransform(time: 6, transform: t2)
            ])
        ]
        let transition = TransitionPlan(fromScene: scene1, toScene: scene2, style: .directPan(duration: 0.5), easing: .easeInOut)
        let transSeg = SimulatedTransitionSegment(fromScene: scene1, toScene: scene2, transitionPlan: transition, startTransform: t1, endTransform: t2)
        let path = SimulatedPath(sceneSegments: sceneSegs, transitionSegments: [transSeg])
        let track = CameraTrackEmitter.emit(path, duration: 6.0)

        for i in 0..<(track.segments.count - 1) {
            XCTAssertLessThanOrEqual(track.segments[i].startTime, track.segments[i + 1].startTime)
        }
    }

    // MARK: - Cut Transition

    func test_emit_cutTransition_producesSegments() {
        let t1 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))
        let t2 = TransformValue(zoom: 1.5, center: NormalizedPoint(x: 0.7, y: 0.7))
        let scene1 = CameraScene(startTime: 0, endTime: 3, primaryIntent: .clicking)
        let scene2 = CameraScene(startTime: 3, endTime: 6, primaryIntent: .switching)
        let shot1 = ShotPlan(scene: scene1, shotType: .medium(zoom: 2.0), idealZoom: 2.0, idealCenter: t1.center)
        let shot2 = ShotPlan(scene: scene2, shotType: .medium(zoom: 1.5), idealZoom: 1.5, idealCenter: t2.center)

        let sceneSegs = [
            SimulatedSceneSegment(scene: scene1, shotPlan: shot1, samples: [
                TimedTransform(time: 0, transform: t1), TimedTransform(time: 3, transform: t1)
            ]),
            SimulatedSceneSegment(scene: scene2, shotPlan: shot2, samples: [
                TimedTransform(time: 3, transform: t2), TimedTransform(time: 6, transform: t2)
            ])
        ]
        let transition = TransitionPlan(fromScene: scene1, toScene: scene2, style: .cut, easing: .linear)
        let transSeg = SimulatedTransitionSegment(fromScene: scene1, toScene: scene2, transitionPlan: transition, startTransform: t1, endTransform: t2)
        let path = SimulatedPath(sceneSegments: sceneSegs, transitionSegments: [transSeg])
        let track = CameraTrackEmitter.emit(path, duration: 6.0)

        // Cut should produce scene1 + cut + scene2 = 3 segments
        XCTAssertEqual(track.segments.count, 3)
    }
}
