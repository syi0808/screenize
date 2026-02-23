import Foundation
import AVFoundation
import Vision
import CoreImage

/// Video frame analyzer
/// Uses the Vision framework to analyze inter-frame changes, motion, and saliency
actor VideoFrameAnalyzer {

    // MARK: - Types

    /// Frame analysis result
    struct FrameAnalysis: Codable, Equatable {
        let time: TimeInterval
        let changeAmount: CGFloat           // Frame change amount (0.0–1.0)
        let motionVector: CGVector          // Average motion vector
        let isScrolling: Bool               // Whether scrolling is detected
        let similarity: CGFloat             // Similarity to the previous frame (0.0–1.0)
        let saliencyCenter: CGPoint?        // Center of visual saliency (normalized)

        static func == (lhs: FrameAnalysis, rhs: FrameAnalysis) -> Bool {
            lhs.time == rhs.time
        }
    }

    /// Analysis progress state
    struct AnalysisProgress {
        let current: Int
        let total: Int
        var percentage: Double { Double(current) / Double(max(1, total)) }
    }

    /// Analysis settings
    struct AnalysisSettings {
        var sampleRate: Double = 1.0        // Samples per second (1.0 = 1fps)
        var computeSaliency: Bool = true    // Whether to compute saliency
        var scrollThreshold: CGFloat = 50   // Threshold for scroll detection (average motion magnitude)
        var scrollDirectionCoherence: CGFloat = 0.8  // Threshold for scroll direction coherence

        static let `default` = AnalysisSettings()
    }

    // MARK: - Properties

    private let ciContext: CIContext
    private var progressHandler: ((AnalysisProgress) -> Void)?

    // MARK: - Initialization

    init() {
        // Use a Metal-backed CIContext for GPU acceleration
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice)
        } else {
            self.ciContext = CIContext()
        }
    }

    // MARK: - Public API

    /// Analyze the entire video
    /// - Parameters:
    ///   - videoURL: URL of the video file to analyze
    ///   - settings: Analysis settings
    ///   - progressHandler: Progress callback
    /// - Returns: Frame analysis results over time
    func analyze(
        videoURL: URL,
        settings: AnalysisSettings = .default,
        progressHandler: ((AnalysisProgress) -> Void)? = nil
    ) async throws -> [FrameAnalysis] {
        self.progressHandler = progressHandler

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds

        guard duration > 0 else {
            throw AnalysisError.invalidVideo("Video duration is zero")
        }

        // Generate the list of sample times
        let sampleInterval = 1.0 / settings.sampleRate
        var sampleTimes: [TimeInterval] = []
        var time: TimeInterval = 0

        while time < duration {
            sampleTimes.append(time)
            time += sampleInterval
        }

        guard !sampleTimes.isEmpty else {
            return []
        }

        // Extract and analyze frames
        return try await analyzeFrames(
            asset: asset,
            sampleTimes: sampleTimes,
            settings: settings
        )
    }

    // MARK: - Frame Extraction & Analysis

    private func analyzeFrames(
        asset: AVAsset,
        sampleTimes: [TimeInterval],
        settings: AnalysisSettings
    ) async throws -> [FrameAnalysis] {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)

        var results: [FrameAnalysis] = []
        results.reserveCapacity(sampleTimes.count)

        var previousFrame: CGImage?
        var previousFeaturePrint: VNFeaturePrintObservation?

        let total = sampleTimes.count

        for (index, sampleTime) in sampleTimes.enumerated() {
            let cmTime = CMTime(seconds: sampleTime, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await imageGenerator.image(at: cmTime)

                let analysis = try await analyzeFrame(
                    currentFrame: cgImage,
                    previousFrame: previousFrame,
                    previousFeaturePrint: &previousFeaturePrint,
                    time: sampleTime,
                    settings: settings
                )

                results.append(analysis)
                previousFrame = cgImage

                // Report progress
                progressHandler?(AnalysisProgress(current: index + 1, total: total))

            } catch {
                // Fill with defaults if frame extraction fails
                results.append(FrameAnalysis(
                    time: sampleTime,
                    changeAmount: 0,
                    motionVector: .zero,
                    isScrolling: false,
                    similarity: 1.0,
                    saliencyCenter: nil
                ))
            }
        }

        return results
    }

    private func analyzeFrame(
        currentFrame: CGImage,
        previousFrame: CGImage?,
        previousFeaturePrint: inout VNFeaturePrintObservation?,
        time: TimeInterval,
        settings: AnalysisSettings
    ) async throws -> FrameAnalysis {

        // 1. Compute the feature print (for similarity comparison)
        let featurePrint = try await computeFeaturePrint(cgImage: currentFrame)
        let similarity: CGFloat
        if let prevPrint = previousFeaturePrint {
            var distance: Float = 0
            try featurePrint.computeDistance(&distance, to: prevPrint)
            // distance ranges from 0 (identical) to 1+ (very different)
            // Convert to similarity (1 = identical, 0 = completely different)
            similarity = CGFloat(max(0, 1.0 - distance))
        } else {
            similarity = 1.0
        }
        previousFeaturePrint = featurePrint

        // 2. Compute frame difference
        let changeAmount: CGFloat
        if let prevFrame = previousFrame {
            changeAmount = try await computeFrameDifference(
                current: currentFrame,
                previous: prevFrame
            )
        } else {
            changeAmount = 0
        }

        // 3. Analyze optical flow (scroll/motion detection)
        let motionResult: (vector: CGVector, isScrolling: Bool)
        if let prevFrame = previousFrame {
            motionResult = try await computeOpticalFlow(
                current: currentFrame,
                previous: prevFrame,
                settings: settings
            )
        } else {
            motionResult = (.zero, false)
        }

        // 4. Optionally analyze saliency
        let saliencyCenter: CGPoint?
        if settings.computeSaliency {
            saliencyCenter = try await computeSaliencyCenter(cgImage: currentFrame)
        } else {
            saliencyCenter = nil
        }

        return FrameAnalysis(
            time: time,
            changeAmount: changeAmount,
            motionVector: motionResult.vector,
            isScrolling: motionResult.isScrolling,
            similarity: similarity,
            saliencyCenter: saliencyCenter
        )
    }

    // MARK: - Vision Analysis

    /// Compute the feature print (image descriptor)
    private func computeFeaturePrint(cgImage: CGImage) async throws -> VNFeaturePrintObservation {
        let request = VNGenerateImageFeaturePrintRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first else {
            throw AnalysisError.featurePrintFailed
        }

        return observation
    }

    /// Compute inter-frame difference using Core Image
    private func computeFrameDifference(
        current: CGImage,
        previous: CGImage
    ) async throws -> CGFloat {
        let currentCI = CIImage(cgImage: current)
        let previousCI = CIImage(cgImage: previous)

        // Use the CIColorAbsoluteDifference filter
        guard let differenceFilter = CIFilter(name: "CIColorAbsoluteDifference") else {
            throw AnalysisError.filterNotAvailable("CIColorAbsoluteDifference")
        }

        differenceFilter.setValue(currentCI, forKey: kCIInputImageKey)
        differenceFilter.setValue(previousCI, forKey: "inputImage2")

        guard let diffImage = differenceFilter.outputImage else {
            throw AnalysisError.filterFailed
        }

        // Compute the average brightness (mean of the difference)
        guard let areaAverage = CIFilter(name: "CIAreaAverage") else {
            throw AnalysisError.filterNotAvailable("CIAreaAverage")
        }

        areaAverage.setValue(diffImage, forKey: kCIInputImageKey)
        areaAverage.setValue(CIVector(cgRect: diffImage.extent), forKey: kCIInputExtentKey)

        guard let outputImage = areaAverage.outputImage else {
            throw AnalysisError.filterFailed
        }

        // Read the average value from a 1x1 pixel
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )

        // Convert the RGB average into a change amount (0–1)
        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0
        let changeAmount = (r + g + b) / 3.0

        return changeAmount
    }

    /// Optical flow analysis (motion vector)
    private func computeOpticalFlow(
        current: CGImage,
        previous: CGImage,
        settings: AnalysisSettings
    ) async throws -> (vector: CGVector, isScrolling: Bool) {
        let request = VNGenerateOpticalFlowRequest(targetedCGImage: previous, options: [:])

        let handler = VNImageRequestHandler(cgImage: current, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first as? VNPixelBufferObservation else {
            return (.zero, false)
        }

        // Compute the average motion vector from the optical flow buffer
        let flowBuffer = observation.pixelBuffer
        let (avgVector, coherence) = computeAverageMotion(from: flowBuffer)

        // Determine scrolling: large, coherent motion signals scrolling
        let magnitude = sqrt(avgVector.dx * avgVector.dx + avgVector.dy * avgVector.dy)
        let isScrolling = magnitude > settings.scrollThreshold && coherence > settings.scrollDirectionCoherence

        return (avgVector, isScrolling)
    }

    /// Compute the average motion vector from the optical flow buffer
    private func computeAverageMotion(from pixelBuffer: CVPixelBuffer) -> (vector: CGVector, coherence: CGFloat) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return (.zero, 0)
        }

        let floatPointer = baseAddress.assumingMemoryBound(to: Float.self)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float>.size

        var sumDx: Double = 0
        var sumDy: Double = 0
        var count: Int = 0

        // Sample a subset of pixels instead of every pixel
        let sampleStep = max(1, min(width, height) / 50)

        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let offset = y * floatsPerRow + x * 2  // 2 channels (dx, dy)
                let dx = Double(floatPointer[offset])
                let dy = Double(floatPointer[offset + 1])

                // Check for NaN
                if !dx.isNaN && !dy.isNaN {
                    sumDx += dx
                    sumDy += dy
                    count += 1
                }
            }
        }

        guard count > 0 else {
            return (.zero, 0)
        }

        let avgDx = CGFloat(sumDx / Double(count))
        let avgDy = CGFloat(sumDy / Double(count))

        // Compute direction coherence (simple heuristic)
        // Coherence is 1 when all vectors align, 0 when directions vary
        var coherentCount = 0
        let avgMagnitude = sqrt(avgDx * avgDx + avgDy * avgDy)

        if avgMagnitude > 1 {
            for y in stride(from: 0, to: height, by: sampleStep) {
                for x in stride(from: 0, to: width, by: sampleStep) {
                    let offset = y * floatsPerRow + x * 2
                    let dx = CGFloat(floatPointer[offset])
                    let dy = CGFloat(floatPointer[offset + 1])

                    // Check if the vector aligns with the average direction
                    let dotProduct = dx * avgDx + dy * avgDy
                    if dotProduct > 0 {
                        coherentCount += 1
                    }
                }
            }
        }

        let coherence = CGFloat(coherentCount) / CGFloat(max(1, count))

        return (CGVector(dx: avgDx, dy: avgDy), coherence)
    }

    /// Saliency analysis (visual attention)
    private func computeSaliencyCenter(cgImage: CGImage) async throws -> CGPoint? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first as? VNSaliencyImageObservation,
              let salientObjects = observation.salientObjects,
              let mostSalient = salientObjects.max(by: { $0.confidence < $1.confidence }) else {
            return nil
        }

        // Vision uses bottom-left origin and normalized coordinates (0–1)
        // Compute the center point
        let boundingBox = mostSalient.boundingBox
        let centerX = boundingBox.midX
        let centerY = 1.0 - boundingBox.midY  // Flip Y-axis for top-left origin

        return CGPoint(x: centerX, y: centerY)
    }

    // MARK: - Error Types

    enum AnalysisError: Error, LocalizedError {
        case invalidVideo(String)
        case featurePrintFailed
        case filterNotAvailable(String)
        case filterFailed
        case opticalFlowFailed

        var errorDescription: String? {
            switch self {
            case .invalidVideo(let message):
                return "Invalid video: \(message)"
            case .featurePrintFailed:
                return "Feature print calculation failed"
            case .filterNotAvailable(let name):
                return "Core Image filter not available: \(name)"
            case .filterFailed:
                return "Core Image filter execution failed"
            case .opticalFlowFailed:
                return "Optical flow calculation failed"
            }
        }
    }
}
