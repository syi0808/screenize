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

    // MARK: - Time Carving for Contiguous Scenes

    func test_emit_contiguousScenes_directPan_hasActualDuration() {
        let (track, _) = makeContiguousTwoSceneTrack(
            transitionStyle: .directPan(duration: 0.5)
        )
        // Find the transition segment (between the two scene segments)
        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sorted.count, 3)
        let transition = sorted[1]
        let transDuration = transition.endTime - transition.startTime
        XCTAssertGreaterThan(transDuration, 0.1,
                             "DirectPan transition should have actual duration, not 0.001s")
    }

    func test_emit_contiguousScenes_zoomOutAndIn_hasActualDuration() {
        let (track, _) = makeContiguousTwoSceneTrack(
            transitionStyle: .zoomOutAndIn(outDuration: 0.5, inDuration: 0.5)
        )
        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        // scene1 + zoomOut + zoomIn + scene2 = 4
        XCTAssertEqual(sorted.count, 4)
        let zoomOut = sorted[1]
        let zoomIn = sorted[2]
        XCTAssertGreaterThan(zoomOut.endTime - zoomOut.startTime, 0.1,
                             "Zoom-out phase should have actual duration")
        XCTAssertGreaterThan(zoomIn.endTime - zoomIn.startTime, 0.1,
                             "Zoom-in phase should have actual duration")
    }

    func test_emit_contiguousScenes_scenesTrimmedForTransitions() {
        let boundary: TimeInterval = 3.0
        let (track, _) = makeContiguousTwoSceneTrack(
            transitionStyle: .directPan(duration: 0.5)
        )
        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sorted.count, 3)
        // Scene A should end before boundary
        XCTAssertLessThan(sorted[0].endTime, boundary,
                          "Scene A should be trimmed to end before boundary")
        // Scene B should start after boundary
        XCTAssertGreaterThan(sorted[2].startTime, boundary,
                             "Scene B should be trimmed to start after boundary")
    }

    func test_emit_shortScene_capsTransitionTrim() {
        // Short scene (0.5s) with 0.8s transition → max trim = 0.5 * 0.3 = 0.15s per side
        let t1 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))
        let t2 = TransformValue(zoom: 1.5, center: NormalizedPoint(x: 0.7, y: 0.7))
        let t3 = TransformValue(zoom: 1.8, center: NormalizedPoint(x: 0.5, y: 0.5))
        let scene1 = CameraScene(startTime: 0, endTime: 3, primaryIntent: .clicking)
        let scene2 = CameraScene(startTime: 3, endTime: 3.5, primaryIntent: .clicking)
        let scene3 = CameraScene(startTime: 3.5, endTime: 6, primaryIntent: .clicking)

        let sceneSegs = [
            makeStaticSceneSeg(scene: scene1, transform: t1),
            makeStaticSceneSeg(scene: scene2, transform: t2),
            makeStaticSceneSeg(scene: scene3, transform: t3)
        ]
        let trans1 = makeTransitionSeg(
            from: scene1, to: scene2, style: .directPan(duration: 0.8),
            startT: t1, endT: t2
        )
        let trans2 = makeTransitionSeg(
            from: scene2, to: scene3, style: .directPan(duration: 0.8),
            startT: t2, endT: t3
        )
        let path = SimulatedPath(sceneSegments: sceneSegs, transitionSegments: [trans1, trans2])
        let track = CameraTrackEmitter.emit(path, duration: 6.0)

        // Find the scene2 segment (the short 0.5s scene)
        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        // scene1 + trans1 + scene2 + trans2 + scene3 = 5 segments
        XCTAssertEqual(sorted.count, 5)
        let scene2Seg = sorted[2]
        let scene2Duration = scene2Seg.endTime - scene2Seg.startTime
        // Short scene should retain at least 40% of its duration (0.2s)
        XCTAssertGreaterThan(scene2Duration, 0.15,
                             "Short scene should not be consumed entirely by transitions")
    }

    func test_emit_noOverlapBetweenSegments() {
        // Three scenes with transitions between each
        let t1 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))
        let t2 = TransformValue(zoom: 1.5, center: NormalizedPoint(x: 0.5, y: 0.5))
        let t3 = TransformValue(zoom: 1.8, center: NormalizedPoint(x: 0.7, y: 0.7))
        let scene1 = CameraScene(startTime: 0, endTime: 3, primaryIntent: .clicking)
        let scene2 = CameraScene(startTime: 3, endTime: 6, primaryIntent: .navigating)
        let scene3 = CameraScene(startTime: 6, endTime: 10, primaryIntent: .clicking)

        let sceneSegs = [
            makeStaticSceneSeg(scene: scene1, transform: t1),
            makeStaticSceneSeg(scene: scene2, transform: t2),
            makeStaticSceneSeg(scene: scene3, transform: t3)
        ]
        let trans1 = makeTransitionSeg(
            from: scene1, to: scene2, style: .directPan(duration: 0.5),
            startT: t1, endT: t2
        )
        let trans2 = makeTransitionSeg(
            from: scene2, to: scene3, style: .directPan(duration: 0.5),
            startT: t2, endT: t3
        )
        let path = SimulatedPath(sceneSegments: sceneSegs, transitionSegments: [trans1, trans2])
        let track = CameraTrackEmitter.emit(path, duration: 10.0)

        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        for i in 0..<(sorted.count - 1) {
            XCTAssertLessThanOrEqual(
                sorted[i].endTime, sorted[i + 1].startTime + 0.001,
                "Segment \(i) end (\(sorted[i].endTime)) should not overlap "
                + "segment \(i+1) start (\(sorted[i + 1].startTime))"
            )
        }
    }

    func test_emit_cutTransition_minimalCarving() {
        let (track, _) = makeContiguousTwoSceneTrack(transitionStyle: .cut)
        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sorted.count, 3)
        let cutSeg = sorted[1]
        let cutDuration = cutSeg.endTime - cutSeg.startTime
        // Cut should be very short (< 0.05s)
        XCTAssertLessThan(cutDuration, 0.05,
                          "Cut transition should be very brief")
    }

    func test_emit_transitionTransformsPreserved() {
        let t1 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.4))
        let t2 = TransformValue(zoom: 1.5, center: NormalizedPoint(x: 0.7, y: 0.6))
        let (track, _) = makeContiguousTwoSceneTrack(
            t1: t1, t2: t2,
            transitionStyle: .directPan(duration: 0.5)
        )
        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        let transition = sorted[1]
        // Transition should bridge from t1 to t2
        XCTAssertEqual(transition.startTransform.zoom, t1.zoom, accuracy: 0.01)
        XCTAssertEqual(transition.endTransform.zoom, t2.zoom, accuracy: 0.01)
        XCTAssertEqual(transition.startTransform.center.x, t1.center.x, accuracy: 0.05)
        XCTAssertEqual(transition.endTransform.center.x, t2.center.x, accuracy: 0.05)
    }

    func test_emit_segmentsCoverFullTimeline() {
        let (track, _) = makeContiguousTwoSceneTrack(
            transitionStyle: .directPan(duration: 0.5)
        )
        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        // First segment should start at 0
        XCTAssertEqual(sorted.first!.startTime, 0, accuracy: 0.01)
        // Last segment should end at 6
        XCTAssertEqual(sorted.last!.endTime, 6, accuracy: 0.01)
        // No gaps: each segment's end should meet next segment's start
        for i in 0..<(sorted.count - 1) {
            XCTAssertEqual(sorted[i].endTime, sorted[i + 1].startTime, accuracy: 0.01,
                           "Gap between segment \(i) and \(i+1)")
        }
    }

    func test_emit_middleScene_trimmedBothSides() {
        let t1 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))
        let t2 = TransformValue(zoom: 1.5, center: NormalizedPoint(x: 0.5, y: 0.5))
        let t3 = TransformValue(zoom: 1.8, center: NormalizedPoint(x: 0.7, y: 0.7))
        let scene1 = CameraScene(startTime: 0, endTime: 3, primaryIntent: .clicking)
        let scene2 = CameraScene(startTime: 3, endTime: 6, primaryIntent: .navigating)
        let scene3 = CameraScene(startTime: 6, endTime: 10, primaryIntent: .clicking)

        let sceneSegs = [
            makeStaticSceneSeg(scene: scene1, transform: t1),
            makeStaticSceneSeg(scene: scene2, transform: t2),
            makeStaticSceneSeg(scene: scene3, transform: t3)
        ]
        let trans1 = makeTransitionSeg(
            from: scene1, to: scene2, style: .directPan(duration: 0.6),
            startT: t1, endT: t2
        )
        let trans2 = makeTransitionSeg(
            from: scene2, to: scene3, style: .directPan(duration: 0.6),
            startT: t2, endT: t3
        )
        let path = SimulatedPath(sceneSegments: sceneSegs, transitionSegments: [trans1, trans2])
        let track = CameraTrackEmitter.emit(path, duration: 10.0)

        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        // scene1 + trans1 + scene2 + trans2 + scene3 = 5
        XCTAssertEqual(sorted.count, 5)
        // Middle scene (index 2) should be trimmed from both sides
        let middleSeg = sorted[2]
        XCTAssertGreaterThan(middleSeg.startTime, 3.0,
                             "Middle scene should start after first boundary")
        XCTAssertLessThan(middleSeg.endTime, 6.0,
                          "Middle scene should end before second boundary")
    }

    func test_emit_singleScene_noTrimming() {
        let transform = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.4, y: 0.6))
        let scene = CameraScene(startTime: 0, endTime: 5, primaryIntent: .clicking)
        let shotPlan = ShotPlan(
            scene: scene, shotType: .medium(zoom: 2.0),
            idealZoom: 2.0, idealCenter: transform.center
        )
        let seg = SimulatedSceneSegment(
            scene: scene, shotPlan: shotPlan,
            samples: [
                TimedTransform(time: 0, transform: transform),
                TimedTransform(time: 5, transform: transform)
            ]
        )
        let path = SimulatedPath(sceneSegments: [seg], transitionSegments: [])
        let track = CameraTrackEmitter.emit(path, duration: 5.0)
        XCTAssertEqual(track.segments.count, 1)
        XCTAssertEqual(track.segments[0].startTime, 0, accuracy: 0.01)
        XCTAssertEqual(track.segments[0].endTime, 5, accuracy: 0.01)
    }

    // MARK: - Easing Propagation: zoomOutAndIn Uses Plan Easings

    func test_emit_zoomOutAndIn_usesTransitionPlanEasings() {
        let t1 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))
        let t2 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.7, y: 0.7))
        let scene1 = CameraScene(startTime: 0, endTime: 3, primaryIntent: .clicking)
        let scene2 = CameraScene(startTime: 3, endTime: 6, primaryIntent: .clicking)
        let sceneSegs = [
            makeStaticSceneSeg(scene: scene1, transform: t1),
            makeStaticSceneSeg(scene: scene2, transform: t2)
        ]
        let customOutEasing: EasingCurve = .easeIn
        let customInEasing: EasingCurve = .spring(dampingRatio: 0.7, response: 0.4)
        let plan = TransitionPlan(
            fromScene: scene1, toScene: scene2,
            style: .zoomOutAndIn(outDuration: 0.5, inDuration: 0.5),
            easing: .easeOut,
            zoomOutEasing: customOutEasing,
            zoomInEasing: customInEasing
        )
        let transSeg = SimulatedTransitionSegment(
            fromScene: scene1, toScene: scene2,
            transitionPlan: plan,
            startTransform: t1, endTransform: t2
        )
        let path = SimulatedPath(sceneSegments: sceneSegs, transitionSegments: [transSeg])
        let track = CameraTrackEmitter.emit(path, duration: 6.0)

        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        // scene1 + zoomOut + zoomIn + scene2 = 4
        XCTAssertEqual(sorted.count, 4)

        let zoomOutSeg = sorted[1]
        let zoomInSeg = sorted[2]
        // Zoom-out phase should use the plan's zoomOutEasing
        XCTAssertEqual(zoomOutSeg.interpolation, customOutEasing,
                       "Zoom-out should use plan.zoomOutEasing, not hardcoded .easeOut")
        // Zoom-in phase should use the plan's zoomInEasing
        XCTAssertEqual(zoomInSeg.interpolation, customInEasing,
                       "Zoom-in should use plan.zoomInEasing, not hardcoded spring")
    }

    func test_emit_zoomOutAndIn_defaultEasings_matchTransitionPlanDefaults() {
        // When using default TransitionPlan easings, segments should carry those defaults
        let t1 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.2, y: 0.2))
        let t2 = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.8, y: 0.8))
        let scene1 = CameraScene(startTime: 0, endTime: 3, primaryIntent: .clicking)
        let scene2 = CameraScene(startTime: 3, endTime: 6, primaryIntent: .clicking)
        let sceneSegs = [
            makeStaticSceneSeg(scene: scene1, transform: t1),
            makeStaticSceneSeg(scene: scene2, transform: t2)
        ]
        // Use default zoomOutEasing/zoomInEasing (from TransitionPlan defaults)
        let plan = TransitionPlan(
            fromScene: scene1, toScene: scene2,
            style: .zoomOutAndIn(outDuration: 0.5, inDuration: 0.5),
            easing: .easeOut
        )
        let transSeg = SimulatedTransitionSegment(
            fromScene: scene1, toScene: scene2,
            transitionPlan: plan,
            startTransform: t1, endTransform: t2
        )
        let path = SimulatedPath(sceneSegments: sceneSegs, transitionSegments: [transSeg])
        let track = CameraTrackEmitter.emit(path, duration: 6.0)

        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sorted.count, 4)
        // Default zoomOutEasing = .easeOut
        XCTAssertEqual(sorted[1].interpolation, .easeOut)
        // Default zoomInEasing = .spring(dampingRatio: 1.0, response: 0.6)
        XCTAssertEqual(sorted[2].interpolation, .spring(dampingRatio: 1.0, response: 0.6))
    }

    // MARK: - Easing Propagation: Multi-Sample Scene Pattern

    func test_emit_multiSampleScene_usesEaseOutLinearEaseInPattern() {
        // Scene with 4 samples → 3 sub-segments → easeOut, linear, easeIn
        let scene = CameraScene(startTime: 0, endTime: 6, primaryIntent: .typing(context: .codeEditor))
        let shotPlan = ShotPlan(
            scene: scene, shotType: .medium(zoom: 2.0),
            idealZoom: 2.0, idealCenter: NormalizedPoint(x: 0.3, y: 0.3)
        )
        let seg = SimulatedSceneSegment(
            scene: scene, shotPlan: shotPlan,
            samples: [
                TimedTransform(time: 0, transform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))),
                TimedTransform(time: 2, transform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.4, y: 0.4))),
                TimedTransform(time: 4, transform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5))),
                TimedTransform(time: 6, transform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.6, y: 0.6)))
            ]
        )
        let path = SimulatedPath(sceneSegments: [seg], transitionSegments: [])
        let track = CameraTrackEmitter.emit(path, duration: 6.0)

        XCTAssertEqual(track.segments.count, 3,
                       "4 samples → 3 sub-segments")
        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sorted[0].interpolation, .easeOut,
                       "First sub-segment should use easeOut")
        XCTAssertEqual(sorted[1].interpolation, .linear,
                       "Middle sub-segment should use linear")
        XCTAssertEqual(sorted[2].interpolation, .easeIn,
                       "Last sub-segment should use easeIn")
    }

    func test_emit_twoSampleMovingScene_usesEaseInOut() {
        // Scene with 2 different-transform samples → 1 sub-segment → easeInOut
        let scene = CameraScene(startTime: 0, endTime: 4, primaryIntent: .typing(context: .codeEditor))
        let shotPlan = ShotPlan(
            scene: scene, shotType: .medium(zoom: 2.0),
            idealZoom: 2.0, idealCenter: NormalizedPoint(x: 0.3, y: 0.3)
        )
        let seg = SimulatedSceneSegment(
            scene: scene, shotPlan: shotPlan,
            samples: [
                TimedTransform(time: 0, transform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3))),
                TimedTransform(time: 2, transform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5))),
                TimedTransform(time: 4, transform: TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.7, y: 0.7)))
            ]
        )
        let path = SimulatedPath(sceneSegments: [seg], transitionSegments: [])
        let track = CameraTrackEmitter.emit(path, duration: 4.0)

        // 3 samples → 2 sub-segments → easeOut, easeIn
        XCTAssertEqual(track.segments.count, 2)
        let sorted = track.segments.sorted { $0.startTime < $1.startTime }
        XCTAssertEqual(sorted[0].interpolation, .easeOut,
                       "First of 2 sub-segments should use easeOut")
        XCTAssertEqual(sorted[1].interpolation, .easeIn,
                       "Last of 2 sub-segments should use easeIn")
    }

    func test_emit_singleSampleScene_usesLinear() {
        let transform = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.4, y: 0.6))
        let scene = CameraScene(startTime: 0, endTime: 5, primaryIntent: .clicking)
        let shotPlan = ShotPlan(
            scene: scene, shotType: .medium(zoom: 2.0),
            idealZoom: 2.0, idealCenter: transform.center
        )
        let seg = SimulatedSceneSegment(
            scene: scene, shotPlan: shotPlan,
            samples: [TimedTransform(time: 0, transform: transform)]
        )
        let path = SimulatedPath(sceneSegments: [seg], transitionSegments: [])
        let track = CameraTrackEmitter.emit(path, duration: 5.0)
        XCTAssertEqual(track.segments.count, 1)
        XCTAssertEqual(track.segments[0].interpolation, .linear)
    }

    // MARK: - Helpers

    private func makeContiguousTwoSceneTrack(
        t1: TransformValue = TransformValue(zoom: 2.0, center: NormalizedPoint(x: 0.3, y: 0.3)),
        t2: TransformValue = TransformValue(zoom: 1.5, center: NormalizedPoint(x: 0.7, y: 0.7)),
        transitionStyle: TransitionStyle
    ) -> (CameraTrack, [CameraSegment]) {
        let scene1 = CameraScene(startTime: 0, endTime: 3, primaryIntent: .clicking)
        let scene2 = CameraScene(startTime: 3, endTime: 6, primaryIntent: .clicking)
        let sceneSegs = [
            makeStaticSceneSeg(scene: scene1, transform: t1),
            makeStaticSceneSeg(scene: scene2, transform: t2)
        ]
        let transSeg = makeTransitionSeg(
            from: scene1, to: scene2, style: transitionStyle,
            startT: t1, endT: t2
        )
        let path = SimulatedPath(sceneSegments: sceneSegs, transitionSegments: [transSeg])
        let track = CameraTrackEmitter.emit(path, duration: 6.0)
        return (track, track.segments)
    }

    private func makeStaticSceneSeg(
        scene: CameraScene, transform: TransformValue
    ) -> SimulatedSceneSegment {
        let shotPlan = ShotPlan(
            scene: scene, shotType: .medium(zoom: transform.zoom),
            idealZoom: transform.zoom, idealCenter: transform.center
        )
        return SimulatedSceneSegment(
            scene: scene, shotPlan: shotPlan,
            samples: [
                TimedTransform(time: scene.startTime, transform: transform),
                TimedTransform(time: scene.endTime, transform: transform)
            ]
        )
    }

    private func makeTransitionSeg(
        from: CameraScene, to: CameraScene,
        style: TransitionStyle,
        startT: TransformValue, endT: TransformValue
    ) -> SimulatedTransitionSegment {
        let easing: EasingCurve
        switch style {
        case .cut: easing = .linear
        case .directPan: easing = .spring(dampingRatio: 0.85, response: 0.5)
        case .zoomOutAndIn: easing = .easeOut
        }
        let plan = TransitionPlan(
            fromScene: from, toScene: to, style: style, easing: easing
        )
        return SimulatedTransitionSegment(
            fromScene: from, toScene: to,
            transitionPlan: plan,
            startTransform: startT, endTransform: endT
        )
    }
}
