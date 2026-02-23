import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// GIF encoder using ImageIO's CGImageDestination
final class GIFEncoder {

    // MARK: - Errors

    enum GIFEncoderError: Error, LocalizedError {
        case cannotCreateDestination
        case cannotFinalizeGIF
        case notStarted

        var errorDescription: String? {
            switch self {
            case .cannotCreateDestination:
                return "Failed to create GIF file destination"
            case .cannotFinalizeGIF:
                return "Failed to finalize GIF file"
            case .notStarted:
                return "GIF encoder has not been started"
            }
        }
    }

    // MARK: - Properties

    private let outputURL: URL
    private let settings: GIFSettings
    private var destination: CGImageDestination?
    private var frameCount: Int = 0

    /// Total frames written
    var framesWritten: Int { frameCount }

    // MARK: - Initialization

    init(outputURL: URL, settings: GIFSettings) {
        self.outputURL = outputURL
        self.settings = settings
    }

    // MARK: - Writing

    /// Begin writing. Creates the CGImageDestination with GIF file properties.
    func beginWriting(estimatedFrameCount: Int) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            estimatedFrameCount,
            nil
        ) else {
            throw GIFEncoderError.cannotCreateDestination
        }

        let gifProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: settings.loopCount
            ]
        ]
        CGImageDestinationSetProperties(dest, gifProperties as CFDictionary)

        self.destination = dest
        self.frameCount = 0
    }

    /// Add a single frame with the configured delay time
    func addFrame(_ image: CGImage) {
        guard let destination = destination else { return }

        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: settings.frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime as String: settings.frameDelay
            ]
        ]

        CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        frameCount += 1
    }

    /// Finalize the GIF and write to disk
    func finalize() throws {
        guard let destination = destination else {
            throw GIFEncoderError.notStarted
        }

        guard CGImageDestinationFinalize(destination) else {
            throw GIFEncoderError.cannotFinalizeGIF
        }

        self.destination = nil
    }
}
