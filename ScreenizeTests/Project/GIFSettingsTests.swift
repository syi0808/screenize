import XCTest
@testable import Screenize

final class GIFSettingsTests: XCTestCase {

    // MARK: - Default Values

    func test_default_hasExpectedValues() {
        let settings = GIFSettings()

        XCTAssertEqual(settings.frameRate, 15)
        XCTAssertEqual(settings.loopCount, 0)
        XCTAssertEqual(settings.maxWidth, 640)
    }

    func test_defaultPreset_matchesInit() {
        let settings = GIFSettings.default
        let manual = GIFSettings()

        XCTAssertEqual(settings, manual)
    }

    // MARK: - Presets

    func test_compactPreset_hasExpectedValues() {
        let settings = GIFSettings.compact

        XCTAssertEqual(settings.frameRate, 10)
        XCTAssertEqual(settings.maxWidth, 480)
    }

    func test_balancedPreset_hasExpectedValues() {
        let settings = GIFSettings.balanced

        XCTAssertEqual(settings.frameRate, 15)
        XCTAssertEqual(settings.maxWidth, 640)
    }

    func test_highQualityPreset_hasExpectedValues() {
        let settings = GIFSettings.highQuality

        XCTAssertEqual(settings.frameRate, 20)
        XCTAssertEqual(settings.maxWidth, 960)
    }

    // MARK: - effectiveSize

    func test_effectiveSize_sourceSmallerThanMaxWidth_returnsSourceUnchanged() {
        let settings = GIFSettings(maxWidth: 640)
        let source = CGSize(width: 320, height: 240)

        let result = settings.effectiveSize(sourceSize: source)

        XCTAssertEqual(result.width, 320)
        XCTAssertEqual(result.height, 240)
    }

    func test_effectiveSize_sourceEqualToMaxWidth_returnsSourceUnchanged() {
        let settings = GIFSettings(maxWidth: 640)
        let source = CGSize(width: 640, height: 480)

        let result = settings.effectiveSize(sourceSize: source)

        XCTAssertEqual(result.width, 640)
        XCTAssertEqual(result.height, 480)
    }

    func test_effectiveSize_sourceLargerThanMaxWidth_scalesDown() {
        let settings = GIFSettings(maxWidth: 640)
        let source = CGSize(width: 1920, height: 1080)

        let result = settings.effectiveSize(sourceSize: source)

        XCTAssertEqual(result.width, 640)
        // 1080 * (640/1920) = 360
        XCTAssertEqual(result.height, 360)
    }

    func test_effectiveSize_ensuresEvenHeight() {
        let settings = GIFSettings(maxWidth: 640)
        // 1000 * (640/1280) = 500 → even, OK
        // Try a source that produces odd height: 1001 * (640/1280) = 500.5 → floor = 500 → even
        // Use 1280x719: 719 * (640/1280) = 359.5 → floor = 359 → odd → round to 360
        let source = CGSize(width: 1280, height: 719)

        let result = settings.effectiveSize(sourceSize: source)

        XCTAssertEqual(result.width, 640)
        XCTAssertEqual(Int(result.height) % 2, 0, "Height must be even")
    }

    func test_effectiveSize_widescreenAspectRatio_maintained() {
        let settings = GIFSettings(maxWidth: 800)
        let source = CGSize(width: 2560, height: 1440)

        let result = settings.effectiveSize(sourceSize: source)

        XCTAssertEqual(result.width, 800)
        // 1440 * (800/2560) = 450
        XCTAssertEqual(result.height, 450)
    }

    // MARK: - frameDelay

    func test_frameDelay_at15fps() {
        let settings = GIFSettings(frameRate: 15)

        XCTAssertEqual(settings.frameDelay, 1.0 / 15.0, accuracy: 0.0001)
    }

    func test_frameDelay_at10fps() {
        let settings = GIFSettings(frameRate: 10)

        XCTAssertEqual(settings.frameDelay, 0.1, accuracy: 0.0001)
    }

    func test_frameDelay_at20fps() {
        let settings = GIFSettings(frameRate: 20)

        XCTAssertEqual(settings.frameDelay, 0.05, accuracy: 0.0001)
    }

    func test_frameDelay_zeroFrameRate_clampedToOne() {
        let settings = GIFSettings(frameRate: 0)

        // max(1, 0) = 1 → delay = 1.0
        XCTAssertEqual(settings.frameDelay, 1.0, accuracy: 0.0001)
    }

    // MARK: - estimatedFileSize

    func test_estimatedFileSize_calculatesCorrectly() {
        let settings = GIFSettings(frameRate: 15, maxWidth: 640)
        let duration: TimeInterval = 10.0

        let estimated = settings.estimatedFileSize(duration: duration)

        // 150 frames * 640 * 40 = 3,840,000 bytes
        let expected: Int64 = Int64(150) * 640 * 40
        XCTAssertEqual(estimated, expected)
    }

    func test_estimatedFileSize_zeroDuration_returnsZero() {
        let settings = GIFSettings()

        let estimated = settings.estimatedFileSize(duration: 0)

        XCTAssertEqual(estimated, 0)
    }

    func test_estimatedFileSize_largerWidth_producesLargerEstimate() {
        let small = GIFSettings(maxWidth: 480)
        let large = GIFSettings(maxWidth: 960)
        let duration: TimeInterval = 5.0

        XCTAssertGreaterThan(
            large.estimatedFileSize(duration: duration),
            small.estimatedFileSize(duration: duration)
        )
    }

    // MARK: - Codable

    func test_codable_roundTrip() throws {
        let original = GIFSettings(frameRate: 20, loopCount: 3, maxWidth: 800)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GIFSettings.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func test_codable_defaultValues_roundTrip() throws {
        let original = GIFSettings()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GIFSettings.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Equatable

    func test_equatable_sameValues_areEqual() {
        let a = GIFSettings(frameRate: 15, loopCount: 0, maxWidth: 640)
        let b = GIFSettings(frameRate: 15, loopCount: 0, maxWidth: 640)

        XCTAssertEqual(a, b)
    }

    func test_equatable_differentValues_areNotEqual() {
        let a = GIFSettings(frameRate: 15, loopCount: 0, maxWidth: 640)
        let b = GIFSettings(frameRate: 20, loopCount: 1, maxWidth: 800)

        XCTAssertNotEqual(a, b)
    }
}
