import XCTest
@testable import Screenize

final class ContinuousTrackEmitterTests: XCTestCase {

    // MARK: - Empty Input

    func test_emit_emptySamples_returnsEmptyTrack() {
        let track = ContinuousTrackEmitter.emit(from: [])
        XCTAssertTrue(track.segments.isEmpty)
    }

    // MARK: - Single Sample

    func test_emit_singleSample_returnsSingleSegment() {
        let samples = [
            TimedTransform(
                time: 0,
                transform: TransformValue(
                    zoom: 1.5,
                    center: NormalizedPoint(x: 0.5, y: 0.5)
                )
            )
        ]
        let track = ContinuousTrackEmitter.emit(from: samples)
        XCTAssertEqual(track.segments.count, 1)
    }

    // MARK: - Constant Samples

    func test_emit_constantSamples_returnsSingleSegment() {
        let transform = TransformValue(
            zoom: 2.0, center: NormalizedPoint(x: 0.5, y: 0.5)
        )
        let samples = (0..<120).map { i in
            TimedTransform(time: Double(i) / 60.0, transform: transform)
        }
        let track = ContinuousTrackEmitter.emit(from: samples)
        XCTAssertEqual(track.segments.count, 1,
                       "Constant samples should produce a single segment")
    }

    // MARK: - Changing Samples

    func test_emit_changingZoom_producesMultipleSegments() {
        // Simulate zoom from 1.0 to 2.0 over 60 samples
        let samples = (0..<60).map { i -> TimedTransform in
            let t = Double(i) / 60.0
            let zoom = 1.0 + CGFloat(i) / 60.0
            return TimedTransform(
                time: t,
                transform: TransformValue(
                    zoom: zoom,
                    center: NormalizedPoint(x: 0.5, y: 0.5)
                )
            )
        }
        let track = ContinuousTrackEmitter.emit(from: samples)
        XCTAssertGreaterThan(track.segments.count, 1,
                             "Changing zoom should produce multiple segments")
    }

    // MARK: - No Overlap Guarantee

    func test_emit_noOverlap() {
        // Create varied motion path
        let samples = (0..<300).map { i -> TimedTransform in
            let t = Double(i) / 60.0
            let phase = CGFloat(t) * 0.5
            return TimedTransform(
                time: t,
                transform: TransformValue(
                    zoom: 1.5 + 0.5 * sin(phase),
                    center: NormalizedPoint(
                        x: 0.5 + 0.2 * cos(phase),
                        y: 0.5 + 0.1 * sin(phase * 2)
                    )
                )
            )
        }
        let track = ContinuousTrackEmitter.emit(from: samples)

        // Verify no overlaps: each segment's endTime <= next segment's startTime
        for i in 1..<track.segments.count {
            XCTAssertLessThanOrEqual(
                track.segments[i - 1].endTime,
                track.segments[i].startTime + 0.0001,
                "Segment \(i-1) endTime (\(track.segments[i-1].endTime)) must not overlap segment \(i) startTime (\(track.segments[i].startTime))"
            )
        }
    }

    // MARK: - Full Time Coverage

    func test_emit_coversFullTimeRange() {
        let samples = (0..<120).map { i -> TimedTransform in
            let t = Double(i) / 60.0
            return TimedTransform(
                time: t,
                transform: TransformValue(
                    zoom: 1.0 + CGFloat(i) * 0.01,
                    center: NormalizedPoint(x: 0.5, y: 0.5)
                )
            )
        }
        let track = ContinuousTrackEmitter.emit(from: samples)

        guard let first = track.segments.first, let last = track.segments.last else {
            XCTFail("Expected at least one segment")
            return
        }
        XCTAssertEqual(first.startTime, 0, accuracy: 0.001,
                       "First segment should start at beginning")
        XCTAssertGreaterThan(last.endTime, 1.5,
                             "Last segment should extend to near end of samples")
    }

    // MARK: - All Segments Use Manual Mode

    func test_emit_allSegmentsAreManualMode() {
        let samples = (0..<60).map { i -> TimedTransform in
            TimedTransform(
                time: Double(i) / 60.0,
                transform: TransformValue(
                    zoom: 1.5 + CGFloat(i) * 0.02,
                    center: NormalizedPoint(x: 0.5, y: 0.5)
                )
            )
        }
        let track = ContinuousTrackEmitter.emit(from: samples)
        for segment in track.segments {
            XCTAssertEqual(segment.mode, .manual)
        }
    }

    // MARK: - All Transitions Are Cut

    func test_emit_allTransitionsAreCut() {
        let samples = (0..<60).map { i -> TimedTransform in
            TimedTransform(
                time: Double(i) / 60.0,
                transform: TransformValue(
                    zoom: 1.0 + CGFloat(i) * 0.02,
                    center: NormalizedPoint(x: 0.5, y: 0.5)
                )
            )
        }
        let track = ContinuousTrackEmitter.emit(from: samples)
        for segment in track.segments {
            XCTAssertEqual(segment.transitionToNext, .cut)
        }
    }

    // MARK: - Continuity

    func test_emit_segmentEndMatchesNextStart() {
        let samples = (0..<180).map { i -> TimedTransform in
            let t = Double(i) / 60.0
            return TimedTransform(
                time: t,
                transform: TransformValue(
                    zoom: 1.0 + CGFloat(i) * 0.01,
                    center: NormalizedPoint(
                        x: 0.3 + CGFloat(i) * 0.002,
                        y: 0.5
                    )
                )
            )
        }
        let track = ContinuousTrackEmitter.emit(from: samples)

        // Adjacent segments should share boundary time
        for i in 1..<track.segments.count {
            let prev = track.segments[i - 1]
            let next = track.segments[i]
            XCTAssertEqual(prev.endTime, next.startTime, accuracy: 0.02,
                           "Segment boundaries should be continuous")
        }
    }
}
