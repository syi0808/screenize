import XCTest
import UniformTypeIdentifiers
@testable import Screenize

final class RenderSettingsGIFTests: XCTestCase {

    // MARK: - ExportFormat Defaults

    func test_exportFormat_defaultIsVideo() {
        let settings = RenderSettings()

        XCTAssertEqual(settings.exportFormat, .video)
    }

    func test_gifSettings_defaultIsDefault() {
        let settings = RenderSettings()

        XCTAssertEqual(settings.gifSettings, .default)
    }

    // MARK: - ExportFormat Properties

    func test_exportFormat_video_displayName() {
        XCTAssertEqual(ExportFormat.video.displayName, "Video")
    }

    func test_exportFormat_gif_displayName() {
        XCTAssertEqual(ExportFormat.gif.displayName, "GIF")
    }

    func test_exportFormat_allCases() {
        XCTAssertEqual(ExportFormat.allCases.count, 2)
        XCTAssertTrue(ExportFormat.allCases.contains(.video))
        XCTAssertTrue(ExportFormat.allCases.contains(.gif))
    }

    // MARK: - RenderSettings Computed Properties

    func test_fileExtension_video_delegatesToCodec() {
        var settings = RenderSettings()
        settings.exportFormat = .video
        settings.codec = .hevc

        XCTAssertEqual(settings.fileExtension, "mp4")

        settings.codec = .proRes422
        XCTAssertEqual(settings.fileExtension, "mov")
    }

    func test_fileExtension_gif_returnsGif() {
        var settings = RenderSettings()
        settings.exportFormat = .gif

        XCTAssertEqual(settings.fileExtension, "gif")
    }

    func test_exportUTType_video_delegatesToCodec() {
        var settings = RenderSettings()
        settings.exportFormat = .video
        settings.codec = .hevc

        XCTAssertEqual(settings.exportUTType, .mpeg4Movie)

        settings.codec = .proRes4444
        XCTAssertEqual(settings.exportUTType, .quickTimeMovie)
    }

    func test_exportUTType_gif_returnsGif() {
        var settings = RenderSettings()
        settings.exportFormat = .gif

        XCTAssertEqual(settings.exportUTType, .gif)
    }

    // MARK: - Codable Backward Compatibility

    func test_codable_withoutExportFormat_defaultsToVideo() throws {
        // Simulate older project JSON without exportFormat field
        let json = """
        {
            "codec": "hevc",
            "quality": "high"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RenderSettings.self, from: data)

        XCTAssertEqual(decoded.exportFormat, .video)
    }

    func test_codable_withoutGifSettings_defaultsToDefault() throws {
        let json = """
        {
            "codec": "hevc",
            "quality": "high"
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RenderSettings.self, from: data)

        XCTAssertEqual(decoded.gifSettings, .default)
    }

    func test_codable_roundTrip_withGIF() throws {
        var original = RenderSettings()
        original.exportFormat = .gif
        original.gifSettings = GIFSettings(frameRate: 20, loopCount: 3, maxWidth: 800)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RenderSettings.self, from: data)

        XCTAssertEqual(decoded.exportFormat, .gif)
        XCTAssertEqual(decoded.gifSettings.frameRate, 20)
        XCTAssertEqual(decoded.gifSettings.loopCount, 3)
        XCTAssertEqual(decoded.gifSettings.maxWidth, 800)
    }

    func test_codable_roundTrip_withVideo() throws {
        var original = RenderSettings()
        original.exportFormat = .video
        original.codec = .h264

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RenderSettings.self, from: data)

        XCTAssertEqual(decoded.exportFormat, .video)
        XCTAssertEqual(decoded.codec, .h264)
    }

    // MARK: - ExportFormat Codable

    func test_exportFormat_codable_roundTrip() throws {
        for format in ExportFormat.allCases {
            let data = try JSONEncoder().encode(format)
            let decoded = try JSONDecoder().decode(ExportFormat.self, from: data)
            XCTAssertEqual(decoded, format)
        }
    }
}
