import Foundation
import AVFoundation
import Vision
import CoreImage

/// Video frame analyzer
/// Uses the Vision framework to analyze inter-frame changes, motion, and saliency
actor VideoFrameAnalyzer {

    // MARK: - Types

    private enum SamplingZone: Int, Comparable {
        case base = 0
        case boundary = 1
        case burst = 2

        static func < (lhs: SamplingZone, rhs: SamplingZone) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private struct SampleCandidate {
        let index: Int
        let time: TimeInterval
        let zone: SamplingZone
    }

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

    /// Diagnostics for adaptive frame sampling.
    struct SamplingDiagnostics {
        let duration: TimeInterval
        let sourceSampleCount: Int
        let selectedSampleCount: Int
        let baseSampleCount: Int
        let boundarySampleCount: Int
        let burstSampleCount: Int
        let anchorCount: Int
        let missedAnchorCount: Int
        let budgetApplied: Bool
        let effectiveSamplesPerSecond: Double
        let upliftVsBaseRate: Double
    }

    /// Adaptive sampling policy for frame extraction.
    struct AdaptiveSamplingPolicy {
        var enabled: Bool = true
        var anchorTimes: [TimeInterval] = []
        var baseSampleRate: Double = 1.0
        var boundarySampleRate: Double = 2.0
        var burstSampleRate: Double = 6.0
        var burstWindow: TimeInterval = 0.35
        var boundaryWindow: TimeInterval = 1.0
        var boundaryGapThreshold: TimeInterval = 1.0
        var maxAverageSampleRate: Double = 2.5
    }

    /// Analysis settings
    struct AnalysisSettings {
        var sampleRate: Double = 1.0        // Samples per second (1.0 = 1fps)
        var computeSaliency: Bool = true    // Whether to compute saliency
        var scrollThreshold: CGFloat = 50   // Threshold for scroll detection (average motion magnitude)
        var scrollDirectionCoherence: CGFloat = 0.8  // Threshold for scroll direction coherence
        var adaptiveSampling: AdaptiveSamplingPolicy?

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
        progressHandler: ((AnalysisProgress) -> Void)? = nil,
        diagnosticsHandler: ((SamplingDiagnostics) -> Void)? = nil
    ) async throws -> [FrameAnalysis] {
        self.progressHandler = progressHandler

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds

        guard duration > 0 else {
            throw AnalysisError.invalidVideo("Video duration is zero")
        }

        // Generate adaptive sample times (with budget cap + diagnostics).
        let (sampleTimes, diagnostics) = buildSampleTimes(
            duration: duration,
            settings: settings
        )
        diagnosticsHandler?(diagnostics)

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
        let toleranceSeconds = sampleTolerance(sampleTimes: sampleTimes)
        imageGenerator.requestedTimeToleranceBefore = CMTime(
            seconds: toleranceSeconds,
            preferredTimescale: 600
        )
        imageGenerator.requestedTimeToleranceAfter = CMTime(
            seconds: toleranceSeconds,
            preferredTimescale: 600
        )

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
            colorSpace: .screenizeSRGB
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

private extension VideoFrameAnalyzer {
    // MARK: - Adaptive Sampling

    func buildSampleTimes(
        duration: TimeInterval,
        settings: AnalysisSettings
    ) -> ([TimeInterval], SamplingDiagnostics) {
        let baseRate = max(0.1, settings.sampleRate)

        guard
            let policy = settings.adaptiveSampling,
            policy.enabled
        else {
            let sampleTimes = uniformSampleTimes(duration: duration, sampleRate: baseRate)
            let diagnostics = SamplingDiagnostics(
                duration: duration,
                sourceSampleCount: sampleTimes.count,
                selectedSampleCount: sampleTimes.count,
                baseSampleCount: sampleTimes.count,
                boundarySampleCount: 0,
                burstSampleCount: 0,
                anchorCount: 0,
                missedAnchorCount: 0,
                budgetApplied: false,
                effectiveSamplesPerSecond: Double(sampleTimes.count) / max(duration, 0.001),
                upliftVsBaseRate: (Double(sampleTimes.count) / max(duration, 0.001)) / baseRate
            )
            return (sampleTimes, diagnostics)
        }

        let anchors = normalizedAnchorTimes(
            policy.anchorTimes,
            duration: duration
        )
        guard !anchors.isEmpty else {
            let sampleTimes = uniformSampleTimes(duration: duration, sampleRate: baseRate)
            let diagnostics = SamplingDiagnostics(
                duration: duration,
                sourceSampleCount: sampleTimes.count,
                selectedSampleCount: sampleTimes.count,
                baseSampleCount: sampleTimes.count,
                boundarySampleCount: 0,
                burstSampleCount: 0,
                anchorCount: 0,
                missedAnchorCount: 0,
                budgetApplied: false,
                effectiveSamplesPerSecond: Double(sampleTimes.count) / max(duration, 0.001),
                upliftVsBaseRate: (Double(sampleTimes.count) / max(duration, 0.001)) / baseRate
            )
            return (sampleTimes, diagnostics)
        }

        let boundaryAnchors = makeBoundaryAnchors(
            from: anchors,
            gapThreshold: max(0.1, policy.boundaryGapThreshold)
        )
        let rates = (
            base: max(0.1, policy.baseSampleRate),
            boundary: max(max(0.1, policy.baseSampleRate), policy.boundarySampleRate),
            burst: max(max(0.1, policy.boundarySampleRate), policy.burstSampleRate)
        )

        var candidates: [SampleCandidate] = []
        var time: TimeInterval = 0
        var index = 0
        while time < duration {
            let zone = samplingZone(
                at: time,
                burstAnchors: anchors,
                boundaryAnchors: boundaryAnchors,
                burstWindow: max(0.01, policy.burstWindow),
                boundaryWindow: max(policy.burstWindow, policy.boundaryWindow)
            )
            candidates.append(SampleCandidate(index: index, time: time, zone: zone))
            index += 1

            let rate: Double
            switch zone {
            case .base:
                rate = rates.base
            case .boundary:
                rate = rates.boundary
            case .burst:
                rate = rates.burst
            }
            time += 1.0 / rate
        }

        let maxSamples = max(
            1,
            Int(ceil(duration * max(0.1, policy.maxAverageSampleRate)))
        )
        let budgetApplied = candidates.count > maxSamples
        let selectedCandidates = budgetApplied
            ? enforceBudget(candidates: candidates, maxSamples: maxSamples)
            : candidates

        let selectedTimes = selectedCandidates.map(\.time)
        let baseCount = selectedCandidates.filter { $0.zone == .base }.count
        let boundaryCount = selectedCandidates.filter { $0.zone == .boundary }.count
        let burstCount = selectedCandidates.filter { $0.zone == .burst }.count
        let missedAnchors = countMissedAnchors(
            anchors: anchors,
            sampleTimes: selectedTimes,
            maxDistance: max(0.05, 1.5 / rates.burst)
        )
        let effectiveRate = Double(selectedTimes.count) / max(duration, 0.001)
        let diagnostics = SamplingDiagnostics(
            duration: duration,
            sourceSampleCount: candidates.count,
            selectedSampleCount: selectedTimes.count,
            baseSampleCount: baseCount,
            boundarySampleCount: boundaryCount,
            burstSampleCount: burstCount,
            anchorCount: anchors.count,
            missedAnchorCount: missedAnchors,
            budgetApplied: budgetApplied,
            effectiveSamplesPerSecond: effectiveRate,
            upliftVsBaseRate: effectiveRate / baseRate
        )

        return (selectedTimes, diagnostics)
    }

    func uniformSampleTimes(
        duration: TimeInterval,
        sampleRate: Double
    ) -> [TimeInterval] {
        let interval = 1.0 / max(0.1, sampleRate)
        var result: [TimeInterval] = []
        var time: TimeInterval = 0
        while time < duration {
            result.append(time)
            time += interval
        }
        return result
    }

    func normalizedAnchorTimes(
        _ anchors: [TimeInterval],
        duration: TimeInterval
    ) -> [TimeInterval] {
        let clamped = anchors
            .map { min(max(0, $0), duration) }
            .sorted()
        guard !clamped.isEmpty else { return [] }
        var deduped: [TimeInterval] = []
        deduped.reserveCapacity(clamped.count)
        for anchor in clamped {
            if let last = deduped.last, abs(last - anchor) < 0.01 {
                continue
            }
            deduped.append(anchor)
        }
        return deduped
    }

    func makeBoundaryAnchors(
        from anchors: [TimeInterval],
        gapThreshold: TimeInterval
    ) -> [TimeInterval] {
        guard anchors.count >= 2 else { return anchors }
        var boundaries: [TimeInterval] = anchors
        for index in 1..<anchors.count {
            let previous = anchors[index - 1]
            let current = anchors[index]
            if current - previous >= gapThreshold {
                boundaries.append(previous)
                boundaries.append(current)
            }
        }
        return boundaries.sorted()
    }

    private func samplingZone(
        at time: TimeInterval,
        burstAnchors: [TimeInterval],
        boundaryAnchors: [TimeInterval],
        burstWindow: TimeInterval,
        boundaryWindow: TimeInterval
    ) -> SamplingZone {
        if nearestDistance(to: time, in: burstAnchors) <= burstWindow {
            return .burst
        }
        if nearestDistance(to: time, in: boundaryAnchors) <= boundaryWindow {
            return .boundary
        }
        return .base
    }

    func nearestDistance(
        to target: TimeInterval,
        in sortedValues: [TimeInterval]
    ) -> TimeInterval {
        guard !sortedValues.isEmpty else { return .greatestFiniteMagnitude }

        var low = 0
        var high = sortedValues.count
        while low < high {
            let mid = (low + high) / 2
            if sortedValues[mid] < target {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var best = TimeInterval.greatestFiniteMagnitude
        if low < sortedValues.count {
            best = min(best, abs(sortedValues[low] - target))
        }
        if low > 0 {
            best = min(best, abs(sortedValues[low - 1] - target))
        }
        return best
    }

    private func enforceBudget(
        candidates: [SampleCandidate],
        maxSamples: Int
    ) -> [SampleCandidate] {
        guard candidates.count > maxSamples else { return candidates }

        var selected: [SampleCandidate] = []
        var used = Set<Int>()

        func appendEvenly(_ zone: SamplingZone, budget: Int) {
            guard budget > 0 else { return }
            let scoped = candidates.filter { $0.zone == zone }
            for candidate in evenlySelected(scoped, targetCount: budget) {
                if used.insert(candidate.index).inserted {
                    selected.append(candidate)
                }
            }
        }

        var remaining = maxSamples

        let burstCandidates = candidates.filter { $0.zone == .burst }
        appendEvenly(.burst, budget: min(remaining, burstCandidates.count))
        remaining = max(0, maxSamples - selected.count)
        guard remaining > 0 else {
            return selected.sorted { $0.time < $1.time }
        }

        let boundaryCandidates = candidates.filter { $0.zone == .boundary }
        appendEvenly(.boundary, budget: min(remaining, boundaryCandidates.count))
        remaining = max(0, maxSamples - selected.count)
        guard remaining > 0 else {
            return selected.sorted { $0.time < $1.time }
        }

        let baseCandidates = candidates.filter { $0.zone == .base }
        appendEvenly(.base, budget: min(remaining, baseCandidates.count))
        remaining = max(0, maxSamples - selected.count)

        if remaining > 0 {
            let fallback = candidates.filter { !used.contains($0.index) }
            for candidate in evenlySelected(fallback, targetCount: remaining) {
                if used.insert(candidate.index).inserted {
                    selected.append(candidate)
                }
            }
        }

        return selected.sorted { $0.time < $1.time }
    }

    private func evenlySelected(
        _ candidates: [SampleCandidate],
        targetCount: Int
    ) -> [SampleCandidate] {
        guard targetCount > 0, !candidates.isEmpty else { return [] }
        guard targetCount < candidates.count else { return candidates }

        if targetCount == 1 {
            return [candidates[0]]
        }

        let step = Double(candidates.count - 1) / Double(targetCount - 1)
        var selected: [SampleCandidate] = []
        selected.reserveCapacity(targetCount)
        var used = Set<Int>()

        for i in 0..<targetCount {
            let raw = Int(round(Double(i) * step))
            let index = min(max(0, raw), candidates.count - 1)
            if used.insert(index).inserted {
                selected.append(candidates[index])
            }
        }

        if selected.count < targetCount {
            for (index, candidate) in candidates.enumerated() where !used.contains(index) {
                selected.append(candidate)
                if selected.count == targetCount {
                    break
                }
            }
        }

        return selected
    }

    func countMissedAnchors(
        anchors: [TimeInterval],
        sampleTimes: [TimeInterval],
        maxDistance: TimeInterval
    ) -> Int {
        guard !anchors.isEmpty else { return 0 }
        guard !sampleTimes.isEmpty else { return anchors.count }

        return anchors.reduce(into: 0) { misses, anchor in
            if nearestDistance(to: anchor, in: sampleTimes) > maxDistance {
                misses += 1
            }
        }
    }

    func sampleTolerance(sampleTimes: [TimeInterval]) -> TimeInterval {
        guard sampleTimes.count >= 2 else { return 0.1 }
        var minGap = TimeInterval.greatestFiniteMagnitude
        for index in 1..<sampleTimes.count {
            minGap = min(minGap, sampleTimes[index] - sampleTimes[index - 1])
        }
        guard minGap.isFinite, minGap > 0 else { return 0.1 }
        return min(0.1, max(0.01, minGap * 0.5))
    }
}
