import Foundation
import AVFoundation
import CoreImage
import CoreVideo

/// Sequential frame reader
/// Wraps AVAssetReader for efficient sequential video playback with GPU-resident buffers
final class SequentialFrameReader {

    // MARK: - Properties

    /// Video asset
    private let asset: AVAsset

    /// Video track
    private let videoTrack: AVAssetTrack

    /// Active reader
    private var reader: AVAssetReader?

    /// Active output
    private var output: AVAssetReaderTrackOutput?

    /// Video size
    let videoSize: CGSize

    /// Frame rate
    let frameRate: Double

    /// Total duration
    let duration: TimeInterval

    /// Current presentation time of the last read sample
    private(set) var currentTime: TimeInterval = 0

    /// Ring buffer for pre-read frames (absorbs decode jitter)
    private var ringBuffer: [(time: TimeInterval, pixelBuffer: CVPixelBuffer)] = []

    /// Maximum ring buffer size
    private let ringBufferSize: Int

    /// Output settings for GPU-resident pixel buffers
    private let outputSettings: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
    ]

    // MARK: - Initialization

    /// Initialize with a video URL
    /// - Parameters:
    ///   - url: Video file URL
    ///   - ringBufferSize: Number of frames to pre-read (default 8)
    init(url: URL, ringBufferSize: Int = 8) async throws {
        self.asset = AVURLAsset(url: url)
        self.ringBufferSize = ringBufferSize

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw SequentialFrameReaderError.noVideoTrack
        }
        self.videoTrack = track

        let size = try await track.load(.naturalSize)
        let nominalFR = try await track.load(.nominalFrameRate)
        let assetDuration = try await asset.load(.duration)

        self.videoSize = size
        self.frameRate = Double(nominalFR) > 0 ? Double(nominalFR) : 60.0
        self.duration = CMTimeGetSeconds(assetDuration)
    }

    // MARK: - Reader Management

    /// Start reading from a specific time
    /// - Parameter time: Start time in seconds
    func startReading(from time: TimeInterval = 0) throws {
        // Clean up existing reader
        stopReading()

        let reader = try AVAssetReader(asset: asset)

        // Set time range from the requested time to the end
        let startCMTime = CMTime(seconds: time, preferredTimescale: 600)
        let endCMTime = CMTime(seconds: duration, preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: startCMTime, end: endCMTime)

        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw SequentialFrameReaderError.cannotAddOutput
        }
        reader.add(output)

        guard reader.startReading() else {
            throw SequentialFrameReaderError.readerStartFailed(reader.error)
        }

        self.reader = reader
        self.output = output
        self.currentTime = time
        self.ringBuffer.removeAll()
    }

    /// Stop reading and release resources
    func stopReading() {
        reader?.cancelReading()
        reader = nil
        output = nil
        ringBuffer.removeAll()
    }

    // MARK: - Frame Reading

    /// Read the next frame as a CIImage (zero-copy from GPU-resident CVPixelBuffer)
    /// - Returns: Tuple of (presentation time, CIImage) or nil if no more frames
    func nextFrame() -> (time: TimeInterval, image: CIImage)? {
        guard let output = output,
              let reader = reader,
              reader.status == .reading else {
            return nil
        }

        guard let sampleBuffer = output.copyNextSampleBuffer() else {
            return nil
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let presentationTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        currentTime = presentationTime

        // CIImage wraps the CVPixelBuffer with zero copy when IOSurface-backed
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return (presentationTime, ciImage)
    }

    /// Read the next frame as a CVPixelBuffer (for direct Metal texture creation)
    /// - Returns: Tuple of (presentation time, CVPixelBuffer) or nil
    func nextPixelBuffer() -> (time: TimeInterval, pixelBuffer: CVPixelBuffer)? {
        guard let output = output,
              let reader = reader,
              reader.status == .reading else {
            return nil
        }

        guard let sampleBuffer = output.copyNextSampleBuffer() else {
            return nil
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let presentationTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        currentTime = presentationTime

        return (presentationTime, pixelBuffer)
    }

    /// Seek to a new time (tears down and recreates the reader)
    /// - Parameter time: Target time in seconds
    func seek(to time: TimeInterval) throws {
        try startReading(from: time)
    }

    /// Pre-fill the ring buffer with upcoming frames
    /// - Returns: Number of frames pre-read
    @discardableResult
    func prefillRingBuffer() -> Int {
        var count = 0
        while ringBuffer.count < ringBufferSize {
            guard let result = nextPixelBuffer() else { break }
            ringBuffer.append(result)
            count += 1
        }
        return count
    }

    /// Get the next frame from the ring buffer, refilling as needed
    /// - Returns: Tuple of (presentation time, CVPixelBuffer) or nil
    func nextBufferedFrame() -> (time: TimeInterval, pixelBuffer: CVPixelBuffer)? {
        // Refill if running low
        if ringBuffer.count < ringBufferSize / 2 {
            prefillRingBuffer()
        }

        guard !ringBuffer.isEmpty else { return nil }
        return ringBuffer.removeFirst()
    }

    // MARK: - Status

    /// Whether the reader is active and has more frames
    var isReading: Bool {
        reader?.status == .reading
    }

    /// Reader error (if failed)
    var error: Error? {
        reader?.error
    }
}

// MARK: - Errors

enum SequentialFrameReaderError: Error, LocalizedError {
    case noVideoTrack
    case cannotAddOutput
    case readerStartFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "Could not find a video track"
        case .cannotAddOutput:
            return "Cannot add reader output"
        case .readerStartFailed(let error):
            if let error = error {
                return "Failed to start reading: \(error.localizedDescription)"
            }
            return "Failed to start reading"
        }
    }
}
