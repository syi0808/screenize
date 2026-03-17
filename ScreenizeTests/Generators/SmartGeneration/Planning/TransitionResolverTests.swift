import XCTest
import CoreGraphics
@testable import Screenize

final class TransitionResolverTests: XCTestCase {

    // MARK: - Nearly Identical Segments -> Hold

    func test_nearlyIdenticalSegments_hold() {
        let segments = [
            makeSegment(
                start: 0, end: 2,
                startCenter: NormalizedPoint(x: 0.5, y: 0.5), startZoom: 2.0,
                endCenter: NormalizedPoint(x: 0.5, y: 0.5), endZoom: 2.0
            ),
            makeSegment(
                start: 2, end: 4,
                startCenter: NormalizedPoint(x: 0.52, y: 0.51), startZoom: 2.0,
                endCenter: NormalizedPoint(x: 0.52, y: 0.51), endZoom: 2.0
            ),
        ]

        let resolved = TransitionResolver.resolve(segments)

        XCTAssertEqual(resolved[0].transitionStyle, .fullTransition)
        XCTAssertEqual(resolved[1].transitionStyle, .hold)
    }

    // MARK: - Same Zoom Different Position -> DirectPan

    func test_sameZoomDifferentPosition_directPan() {
        let segments = [
            makeSegment(
                start: 0, end: 2,
                startCenter: NormalizedPoint(x: 0.2, y: 0.5), startZoom: 2.0,
                endCenter: NormalizedPoint(x: 0.2, y: 0.5), endZoom: 2.0
            ),
            makeSegment(
                start: 2, end: 4,
                startCenter: NormalizedPoint(x: 0.6, y: 0.5), startZoom: 2.1,
                endCenter: NormalizedPoint(x: 0.6, y: 0.5), endZoom: 2.1
            ),
        ]

        let resolved = TransitionResolver.resolve(segments)

        XCTAssertEqual(resolved[0].transitionStyle, .fullTransition)
        XCTAssertEqual(resolved[1].transitionStyle, .directPan)
    }

    // MARK: - Very Different Segments -> FullTransition

    func test_veryDifferentSegments_fullTransition() {
        let segments = [
            makeSegment(
                start: 0, end: 2,
                startCenter: NormalizedPoint(x: 0.2, y: 0.2), startZoom: 1.5,
                endCenter: NormalizedPoint(x: 0.2, y: 0.2), endZoom: 1.5
            ),
            makeSegment(
                start: 2, end: 4,
                startCenter: NormalizedPoint(x: 0.8, y: 0.8), startZoom: 3.0,
                endCenter: NormalizedPoint(x: 0.8, y: 0.8), endZoom: 3.0
            ),
        ]

        let resolved = TransitionResolver.resolve(segments)

        XCTAssertEqual(resolved[0].transitionStyle, .fullTransition)
        XCTAssertEqual(resolved[1].transitionStyle, .fullTransition)
    }

    // MARK: - Idle Between Similar Active -> Hold Through Idle

    func test_idleBetweenSimilarActive_holdThroughIdle() {
        let activeCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let segments = [
            makeSegment(
                start: 0, end: 2,
                startCenter: activeCenter, startZoom: 2.0,
                endCenter: activeCenter, endZoom: 2.0
            ),
            // Idle segment (zoom ~1.0)
            makeSegment(
                start: 2, end: 3,
                startCenter: activeCenter, startZoom: 1.0,
                endCenter: activeCenter, endZoom: 1.0
            ),
            makeSegment(
                start: 3, end: 5,
                startCenter: NormalizedPoint(x: 0.52, y: 0.51), startZoom: 2.0,
                endCenter: NormalizedPoint(x: 0.52, y: 0.51), endZoom: 2.0
            ),
        ]

        let resolved = TransitionResolver.resolve(segments)

        XCTAssertEqual(resolved[0].transitionStyle, .fullTransition)
        // Idle segment should inherit hold from the active-to-active classification
        XCTAssertEqual(resolved[1].transitionStyle, .hold)
        XCTAssertEqual(resolved[2].transitionStyle, .hold)
    }

    // MARK: - First Segment Always FullTransition

    func test_firstSegment_alwaysFullTransition() {
        let segments = [
            makeSegment(
                start: 0, end: 2,
                startCenter: NormalizedPoint(x: 0.5, y: 0.5), startZoom: 2.0,
                endCenter: NormalizedPoint(x: 0.5, y: 0.5), endZoom: 2.0
            ),
        ]

        let resolved = TransitionResolver.resolve(segments)

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].transitionStyle, .fullTransition)
    }

    // MARK: - Empty Input

    func test_emptySegments_returnsEmpty() {
        let resolved = TransitionResolver.resolve([])
        XCTAssertTrue(resolved.isEmpty)
    }

    // MARK: - IntentSpan-Based Idle Detection

    func test_idleBetweenSimilarActive_withIntentSpans_holdThroughIdle() {
        let activeCenter = NormalizedPoint(x: 0.5, y: 0.5)
        let segments = [
            makeSegment(
                start: 0, end: 2,
                startCenter: activeCenter, startZoom: 2.0,
                endCenter: activeCenter, endZoom: 2.0
            ),
            // This segment has high zoom but its intent is idle
            makeSegment(
                start: 2, end: 3,
                startCenter: activeCenter, startZoom: 2.0,
                endCenter: activeCenter, endZoom: 2.0
            ),
            makeSegment(
                start: 3, end: 5,
                startCenter: NormalizedPoint(x: 0.52, y: 0.51), startZoom: 2.0,
                endCenter: NormalizedPoint(x: 0.52, y: 0.51), endZoom: 2.0
            ),
        ]

        let intentSpans = [
            IntentSpan(
                startTime: 0, endTime: 2,
                intent: .typing(context: .codeEditor), confidence: 1.0,
                focusPosition: activeCenter, focusElement: nil
            ),
            IntentSpan(
                startTime: 2, endTime: 3,
                intent: .idle, confidence: 1.0,
                focusPosition: activeCenter, focusElement: nil
            ),
            IntentSpan(
                startTime: 3, endTime: 5,
                intent: .typing(context: .codeEditor), confidence: 1.0,
                focusPosition: NormalizedPoint(x: 0.52, y: 0.51),
                focusElement: nil
            ),
        ]

        let resolved = TransitionResolver.resolve(
            segments, intentSpans: intentSpans
        )

        XCTAssertEqual(resolved[0].transitionStyle, .fullTransition)
        XCTAssertEqual(resolved[1].transitionStyle, .hold)
        XCTAssertEqual(resolved[2].transitionStyle, .hold)
    }

    // MARK: - DirectPan Through Idle

    func test_idleBetweenDirectPanActive_directPanThroughIdle() {
        let segments = [
            makeSegment(
                start: 0, end: 2,
                startCenter: NormalizedPoint(x: 0.2, y: 0.5), startZoom: 2.0,
                endCenter: NormalizedPoint(x: 0.2, y: 0.5), endZoom: 2.0
            ),
            // Idle segment
            makeSegment(
                start: 2, end: 3,
                startCenter: NormalizedPoint(x: 0.4, y: 0.5), startZoom: 1.0,
                endCenter: NormalizedPoint(x: 0.4, y: 0.5), endZoom: 1.0
            ),
            makeSegment(
                start: 3, end: 5,
                startCenter: NormalizedPoint(x: 0.6, y: 0.5), startZoom: 2.1,
                endCenter: NormalizedPoint(x: 0.6, y: 0.5), endZoom: 2.1
            ),
        ]

        let resolved = TransitionResolver.resolve(segments)

        XCTAssertEqual(resolved[0].transitionStyle, .fullTransition)
        XCTAssertEqual(resolved[1].transitionStyle, .directPan)
        XCTAssertEqual(resolved[2].transitionStyle, .directPan)
    }

    // MARK: - Helpers

    private func makeSegment(
        start: TimeInterval,
        end: TimeInterval,
        startCenter: NormalizedPoint,
        startZoom: CGFloat,
        endCenter: NormalizedPoint,
        endZoom: CGFloat
    ) -> CameraSegment {
        CameraSegment(
            startTime: start,
            endTime: end,
            kind: .manual(
                startTransform: TransformValue(zoom: startZoom, center: startCenter),
                endTransform: TransformValue(zoom: endZoom, center: endCenter)
            )
        )
    }
}
