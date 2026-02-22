import XCTest
@testable import Screenize

final class CursorTrackEmitterTests: XCTestCase {

    // MARK: - Zero Duration

    func test_emit_zeroDuration_returnsEmptyTrack() {
        let settings = CursorEmissionSettings()
        let track = CursorTrackEmitter.emit(duration: 0, settings: settings)
        XCTAssertTrue(track.segments.isEmpty)
    }

    // MARK: - Normal Duration

    func test_emit_normalDuration_returnsSingleSegment() {
        let settings = CursorEmissionSettings()
        let track = CursorTrackEmitter.emit(duration: 10.0, settings: settings)
        XCTAssertEqual(track.segments.count, 1)
    }

    func test_emit_normalDuration_segmentSpansFullDuration() {
        let settings = CursorEmissionSettings()
        let track = CursorTrackEmitter.emit(duration: 10.0, settings: settings)
        let segment = track.segments[0]
        XCTAssertEqual(segment.startTime, 0, accuracy: 0.001)
        XCTAssertEqual(segment.endTime, 10.0, accuracy: 0.001)
    }

    func test_emit_normalDuration_segmentHasArrowStyle() {
        let settings = CursorEmissionSettings()
        let track = CursorTrackEmitter.emit(duration: 10.0, settings: settings)
        XCTAssertEqual(track.segments[0].style, .arrow)
    }

    func test_emit_normalDuration_segmentIsVisible() {
        let settings = CursorEmissionSettings()
        let track = CursorTrackEmitter.emit(duration: 10.0, settings: settings)
        XCTAssertTrue(track.segments[0].visible)
    }

    // MARK: - Custom Scale

    func test_emit_customScale_usesSettingsScale() {
        var settings = CursorEmissionSettings()
        settings.cursorScale = 3.5
        let track = CursorTrackEmitter.emit(duration: 5.0, settings: settings)
        XCTAssertEqual(track.segments[0].scale, 3.5, accuracy: 0.01)
    }

    // MARK: - Track Name

    func test_emit_trackNameIsCorrect() {
        let settings = CursorEmissionSettings()
        let track = CursorTrackEmitter.emit(duration: 5.0, settings: settings)
        XCTAssertEqual(track.name, "Cursor (Smart V2)")
    }

    // MARK: - Track Enabled

    func test_emit_trackIsEnabled() {
        let settings = CursorEmissionSettings()
        let track = CursorTrackEmitter.emit(duration: 5.0, settings: settings)
        XCTAssertTrue(track.isEnabled)
    }
}
