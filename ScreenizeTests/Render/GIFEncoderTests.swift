import XCTest
import CoreGraphics
import ImageIO
@testable import Screenize

final class GIFEncoderTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gif")
    }

    override func tearDown() {
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTestImage(
        width: Int = 100,
        height: Int = 100,
        color: (r: UInt8, g: UInt8, b: UInt8) = (255, 0, 0)
    ) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(
            CGColor(
                red: CGFloat(color.r) / 255.0,
                green: CGFloat(color.g) / 255.0,
                blue: CGFloat(color.b) / 255.0,
                alpha: 1.0
            )
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    // MARK: - Basic Writing

    func test_beginWriting_andFinalize_producesFile() throws {
        let encoder = GIFEncoder(
            outputURL: tempURL,
            settings: .default
        )

        try encoder.beginWriting(estimatedFrameCount: 1)
        encoder.addFrame(makeTestImage())
        try encoder.finalize()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }

    func test_output_startsWithGIFMagicBytes() throws {
        let encoder = GIFEncoder(
            outputURL: tempURL,
            settings: .default
        )

        try encoder.beginWriting(estimatedFrameCount: 2)
        encoder.addFrame(makeTestImage())
        encoder.addFrame(makeTestImage(color: (0, 255, 0)))
        try encoder.finalize()

        let data = try Data(contentsOf: tempURL)
        // GIF files start with "GIF" (either GIF87a or GIF89a)
        let magic = String(data: data.prefix(3), encoding: .ascii)
        XCTAssertEqual(magic, "GIF")
    }

    // MARK: - Frame Count

    func test_framesWritten_startsAtZero() {
        let encoder = GIFEncoder(
            outputURL: tempURL,
            settings: .default
        )

        XCTAssertEqual(encoder.framesWritten, 0)
    }

    func test_addFrame_incrementsFrameCount() throws {
        let encoder = GIFEncoder(
            outputURL: tempURL,
            settings: .default
        )

        try encoder.beginWriting(estimatedFrameCount: 5)

        encoder.addFrame(makeTestImage())
        XCTAssertEqual(encoder.framesWritten, 1)

        encoder.addFrame(makeTestImage())
        XCTAssertEqual(encoder.framesWritten, 2)

        encoder.addFrame(makeTestImage())
        XCTAssertEqual(encoder.framesWritten, 3)

        try encoder.finalize()
    }

    func test_multipleFrames_allWritten() throws {
        let encoder = GIFEncoder(
            outputURL: tempURL,
            settings: .default
        )

        let frameCount = 10
        try encoder.beginWriting(estimatedFrameCount: frameCount)

        for _ in 0..<frameCount {
            encoder.addFrame(makeTestImage())
        }

        try encoder.finalize()

        XCTAssertEqual(encoder.framesWritten, frameCount)

        // Verify via CGImageSource that all frames exist
        guard let source = CGImageSourceCreateWithURL(tempURL as CFURL, nil) else {
            XCTFail("Cannot read GIF file")
            return
        }
        XCTAssertEqual(CGImageSourceGetCount(source), frameCount)
    }

    // MARK: - Loop Count

    func test_loopCount_infiniteLoop() throws {
        let settings = GIFSettings(frameRate: 15, loopCount: 0, maxWidth: 640)
        let encoder = GIFEncoder(outputURL: tempURL, settings: settings)

        try encoder.beginWriting(estimatedFrameCount: 2)
        encoder.addFrame(makeTestImage())
        encoder.addFrame(makeTestImage())
        try encoder.finalize()

        guard let source = CGImageSourceCreateWithURL(tempURL as CFURL, nil) else {
            XCTFail("Cannot read GIF file")
            return
        }
        let props = CGImageSourceCopyProperties(source, nil) as? [String: Any]
        let gifDict = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        let loopCount = gifDict?[kCGImagePropertyGIFLoopCount as String] as? Int
        XCTAssertEqual(loopCount, 0)
    }

    func test_loopCount_specificCount() throws {
        let settings = GIFSettings(frameRate: 15, loopCount: 3, maxWidth: 640)
        let encoder = GIFEncoder(outputURL: tempURL, settings: settings)

        try encoder.beginWriting(estimatedFrameCount: 2)
        encoder.addFrame(makeTestImage())
        encoder.addFrame(makeTestImage())
        try encoder.finalize()

        guard let source = CGImageSourceCreateWithURL(tempURL as CFURL, nil) else {
            XCTFail("Cannot read GIF file")
            return
        }
        let props = CGImageSourceCopyProperties(source, nil) as? [String: Any]
        let gifDict = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        let loopCount = gifDict?[kCGImagePropertyGIFLoopCount as String] as? Int
        XCTAssertEqual(loopCount, 3)
    }

    // MARK: - Frame Delay

    func test_frameDelay_matchesSettings() throws {
        let settings = GIFSettings(frameRate: 10, loopCount: 0, maxWidth: 640)
        let encoder = GIFEncoder(outputURL: tempURL, settings: settings)

        try encoder.beginWriting(estimatedFrameCount: 1)
        encoder.addFrame(makeTestImage())
        try encoder.finalize()

        guard let source = CGImageSourceCreateWithURL(tempURL as CFURL, nil) else {
            XCTFail("Cannot read GIF file")
            return
        }
        let frameProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let gifDict = frameProps?[kCGImagePropertyGIFDictionary as String] as? [String: Any]

        // Check unclamped delay time
        if let unclampedDelay = gifDict?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double {
            XCTAssertEqual(unclampedDelay, 0.1, accuracy: 0.01)
        } else if let delay = gifDict?[kCGImagePropertyGIFDelayTime as String] as? Double {
            XCTAssertEqual(delay, 0.1, accuracy: 0.01)
        } else {
            XCTFail("No delay time found in frame properties")
        }
    }

    // MARK: - Error Handling

    func test_finalize_withoutBeginWriting_throws() {
        let encoder = GIFEncoder(
            outputURL: tempURL,
            settings: .default
        )

        XCTAssertThrowsError(try encoder.finalize()) { error in
            XCTAssertTrue(error is GIFEncoder.GIFEncoderError)
        }
    }

    // MARK: - Different Frame Sizes

    func test_differentFrameSizes_allWritten() throws {
        let encoder = GIFEncoder(
            outputURL: tempURL,
            settings: .default
        )

        try encoder.beginWriting(estimatedFrameCount: 3)
        encoder.addFrame(makeTestImage(width: 200, height: 150))
        encoder.addFrame(makeTestImage(width: 200, height: 150, color: (0, 255, 0)))
        encoder.addFrame(makeTestImage(width: 200, height: 150, color: (0, 0, 255)))
        try encoder.finalize()

        XCTAssertEqual(encoder.framesWritten, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
    }
}
