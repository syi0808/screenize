import Foundation
import AVFoundation
import CoreImage

/// Video frame extractor
/// Extracts frames at specific times from an AVAsset
final class VideoFrameExtractor {

    // MARK: - Properties

    /// Video asset
    private let asset: AVAsset

    /// Video track
    private var videoTrack: AVAssetTrack?

    /// Image generator
    private var imageGenerator: AVAssetImageGenerator?

    /// Frame rate
    let frameRate: Double

    /// Video size
    let videoSize: CGSize

    /// Total duration
    let duration: TimeInterval

    // MARK: - Initialization

    init(url: URL) async throws {
        self.asset = AVAsset(url: url)

        // Load video track information
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoFrameExtractorError.noVideoTrack
        }
        self.videoTrack = videoTrack

        let size = try await videoTrack.load(.naturalSize)
        let nominalFR = try await videoTrack.load(.nominalFrameRate)
        let assetDuration = try await asset.load(.duration)

        self.videoSize = size
        self.frameRate = Double(nominalFR) > 0 ? Double(nominalFR) : 60.0
        self.duration = CMTimeGetSeconds(assetDuration)

        // DEBUG: Log video metadata
        let transform = try await videoTrack.load(.preferredTransform)
        print("🔍 [DEBUG] VideoFrameExtractor: videoSize=\(size), frameRate=\(self.frameRate), transform=\(transform)")

        // Configure the image generator
        setupImageGenerator()
    }

    private func setupImageGenerator() {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 600)

        self.imageGenerator = generator
    }

    // MARK: - Frame Extraction

    /// Extract a frame at the specified time
    /// - Parameter time: Time to extract (seconds)
    /// - Returns: CIImage
    func extractFrame(at time: TimeInterval) async throws -> CIImage {
        guard let generator = imageGenerator else {
            throw VideoFrameExtractorError.generatorNotReady
        }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)

        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: cmTime)]) { _, cgImage, _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard result == .succeeded, let cgImage = cgImage else {
                    continuation.resume(throwing: VideoFrameExtractorError.frameExtractionFailed)
                    return
                }

                let ciImage = CIImage(cgImage: cgImage)
                continuation.resume(returning: ciImage)
            }
        }
    }

    /// Extract a frame by frame number
    /// - Parameter frame: Frame number
    /// - Returns: CIImage
    func extractFrame(frame: Int) async throws -> CIImage {
        let time = Double(frame) / frameRate
        return try await extractFrame(at: time)
    }

    /// Extract frames for multiple times
    /// - Parameter times: Times to extract (seconds)
    /// - Returns: Array of (time, CIImage) tuples
    func extractFrames(at times: [TimeInterval]) async throws -> [(TimeInterval, CIImage)] {
        guard let generator = imageGenerator else {
            throw VideoFrameExtractorError.generatorNotReady
        }

        let cmTimes = times.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }

        var results: [(TimeInterval, CIImage)] = []
        results.reserveCapacity(times.count)

        return try await withCheckedThrowingContinuation { continuation in
            var extractedResults: [(TimeInterval, CIImage)] = []
            var lastError: Error?
            let totalCount = times.count
            var completedCount = 0
            let lock = NSLock()

            generator.generateCGImagesAsynchronously(forTimes: cmTimes) { requestedTime, cgImage, _, result, error in
                lock.lock()
                defer {
                    lock.unlock()
                    completedCount += 1

                    if completedCount == totalCount {
                        if let error = lastError {
                            continuation.resume(throwing: error)
                        } else {
                            // Sort in chronological order
                            extractedResults.sort { $0.0 < $1.0 }
                            continuation.resume(returning: extractedResults)
                        }
                    }
                }

                if let error = error {
                    lastError = error
                    return
                }

                if result == .succeeded, let cgImage = cgImage {
                    let time = CMTimeGetSeconds(requestedTime)
                    let ciImage = CIImage(cgImage: cgImage)
                    extractedResults.append((time, ciImage))
                }
            }
        }
    }

    // MARK: - Configuration

    /// Set the extraction resolution
    func setMaximumSize(_ size: CGSize) {
        imageGenerator?.maximumSize = size
    }

    /// Configure time tolerance
    func setTimeTolerance(before: CMTime, after: CMTime) {
        imageGenerator?.requestedTimeToleranceBefore = before
        imageGenerator?.requestedTimeToleranceAfter = after
    }

    /// Extract at exact times (slower but precise)
    func setExactTimeExtraction(_ exact: Bool) {
        if exact {
            imageGenerator?.requestedTimeToleranceBefore = .zero
            imageGenerator?.requestedTimeToleranceAfter = .zero
        } else {
            imageGenerator?.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 600)
            imageGenerator?.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 600)
        }
    }

    // MARK: - Cleanup

    func cancelAllPendingRequests() {
        imageGenerator?.cancelAllCGImageGeneration()
    }
}

// MARK: - Errors

enum VideoFrameExtractorError: Error, LocalizedError {
    case noVideoTrack
    case generatorNotReady
    case frameExtractionFailed

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "Could not find a video track"
        case .generatorNotReady:
            return "Image generator is not ready"
        case .frameExtractionFailed:
            return "Failed to extract frame"
        }
    }
}
