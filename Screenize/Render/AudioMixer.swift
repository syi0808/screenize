import Foundation
import AVFoundation
import Accelerate

/// Mixes system audio (from source video) and microphone audio (from sidecar)
/// into a single audio track for export.
final class AudioMixer {

    // MARK: - Audio Output Settings

    /// Standard output format for mixed audio
    static let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128_000
    ]

    /// Shared export queue for audio writing operations
    private let exportQueue = DispatchQueue(label: "com.screenize.audio-export", qos: .userInitiated)

    /// PCM decompression settings for reading source audio
    private static let decompressionSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
        AVSampleRateKey: 48000,
        AVNumberOfChannelsKey: 2
    ]

    // MARK: - Single Source Passthrough

    /// Write audio from a single source (passthrough, no mixing needed).
    func writePassthrough(
        audioURL: URL,
        writerInput: AVAssetWriterInput,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        volume: Float = 1.0
    ) async throws {
        let asset = AVAsset(url: audioURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else { return }

        let timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600)
        )

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: Self.decompressionSettings)
        output.alwaysCopiesSampleData = false
        reader.timeRange = timeRange
        reader.add(output)

        guard reader.startReading() else {
            throw AudioMixerError.readerStartFailed(reader.error)
        }



        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false

            writerInput.requestMediaDataWhenReady(on: exportQueue) {
                while writerInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = output.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        if !didResume {
                            didResume = true
                            continuation.resume()
                        }
                        return
                    }

                    if volume != 1.0 {
                        Self.applyVolume(to: sampleBuffer, volume: volume)
                    }

                    writerInput.append(sampleBuffer)
                }
            }
        }

        reader.cancelReading()
    }

    // MARK: - Dual Source Mixing

    /// Mix system audio and microphone audio into the writer input.
    func mixAndWrite(
        systemAudioURL: URL,
        micAudioURL: URL,
        writerInput: AVAssetWriterInput,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        systemVolume: Float = 1.0,
        micVolume: Float = 1.0
    ) async throws {
        let timeRange = CMTimeRange(
            start: CMTime(seconds: trimStart, preferredTimescale: 600),
            end: CMTime(seconds: trimEnd, preferredTimescale: 600)
        )

        // Setup system audio reader
        let systemAsset = AVAsset(url: systemAudioURL)
        let systemTracks = try await systemAsset.loadTracks(withMediaType: .audio)
        guard let systemTrack = systemTracks.first else {
            // No system audio — fall back to mic-only passthrough
            try await writePassthrough(
                audioURL: micAudioURL,
                writerInput: writerInput,
                trimStart: trimStart,
                trimEnd: trimEnd,
                volume: micVolume
            )
            return
        }

        let systemReader = try AVAssetReader(asset: systemAsset)
        let systemOutput = AVAssetReaderTrackOutput(track: systemTrack, outputSettings: Self.decompressionSettings)
        systemOutput.alwaysCopiesSampleData = false
        systemReader.timeRange = timeRange
        systemReader.add(systemOutput)

        // Setup mic audio reader
        let micAsset = AVAsset(url: micAudioURL)
        let micTracks = try await micAsset.loadTracks(withMediaType: .audio)
        guard let micTrack = micTracks.first else {
            // No mic audio — fall back to system-only passthrough
            systemReader.cancelReading()
            try await writePassthrough(
                audioURL: systemAudioURL,
                writerInput: writerInput,
                trimStart: trimStart,
                trimEnd: trimEnd,
                volume: systemVolume
            )
            return
        }

        let micReader = try AVAssetReader(asset: micAsset)
        let micOutput = AVAssetReaderTrackOutput(track: micTrack, outputSettings: Self.decompressionSettings)
        micOutput.alwaysCopiesSampleData = false
        micReader.timeRange = timeRange
        micReader.add(micOutput)

        guard systemReader.startReading() else {
            throw AudioMixerError.readerStartFailed(systemReader.error)
        }
        guard micReader.startReading() else {
            systemReader.cancelReading()
            throw AudioMixerError.readerStartFailed(micReader.error)
        }



        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var didResume = false

            writerInput.requestMediaDataWhenReady(on: exportQueue) {
                while writerInput.isReadyForMoreMediaData {
                    let systemSample = systemOutput.copyNextSampleBuffer()
                    let micSample = micOutput.copyNextSampleBuffer()

                    // Both sources exhausted
                    if systemSample == nil && micSample == nil {
                        writerInput.markAsFinished()
                        if !didResume {
                            didResume = true
                            continuation.resume()
                        }
                        return
                    }

                    // Only system audio remaining
                    if let sysBuf = systemSample, micSample == nil {
                        if systemVolume != 1.0 {
                            Self.applyVolume(to: sysBuf, volume: systemVolume)
                        }
                        writerInput.append(sysBuf)
                        continue
                    }

                    // Only mic audio remaining
                    if systemSample == nil, let micBuf = micSample {
                        if micVolume != 1.0 {
                            Self.applyVolume(to: micBuf, volume: micVolume)
                        }
                        writerInput.append(micBuf)
                        continue
                    }

                    // Mix both sources
                    if let sysBuf = systemSample, let micBuf = micSample {
                        if let mixed = Self.mixSampleBuffers(
                            sysBuf, volume1: systemVolume,
                            micBuf, volume2: micVolume
                        ) {
                            writerInput.append(mixed)
                        } else {
                            // Fallback: write system audio if mixing fails
                            if systemVolume != 1.0 {
                                Self.applyVolume(to: sysBuf, volume: systemVolume)
                            }
                            writerInput.append(sysBuf)
                        }
                    }
                }
            }
        }

        systemReader.cancelReading()
        micReader.cancelReading()
    }

    // MARK: - PCM Mixing

    /// Mix two PCM sample buffers with volume scaling using vDSP.
    private static func mixSampleBuffers(
        _ buffer1: CMSampleBuffer, volume1: Float,
        _ buffer2: CMSampleBuffer, volume2: Float
    ) -> CMSampleBuffer? {
        guard let dataBuffer1 = CMSampleBufferGetDataBuffer(buffer1),
              let dataBuffer2 = CMSampleBufferGetDataBuffer(buffer2) else {
            return nil
        }

        let length1 = CMBlockBufferGetDataLength(dataBuffer1)
        let length2 = CMBlockBufferGetDataLength(dataBuffer2)
        let sampleCount1 = length1 / MemoryLayout<Float>.size
        let sampleCount2 = length2 / MemoryLayout<Float>.size
        let outputCount = min(sampleCount1, sampleCount2)
        guard outputCount > 0 else { return nil }

        // Get pointers to PCM data
        var dataPointer1: UnsafeMutablePointer<Int8>?
        var lengthAtOffset1 = 0
        CMBlockBufferGetDataPointer(dataBuffer1, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset1,
                                    totalLengthOut: nil, dataPointerOut: &dataPointer1)

        var dataPointer2: UnsafeMutablePointer<Int8>?
        var lengthAtOffset2 = 0
        CMBlockBufferGetDataPointer(dataBuffer2, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset2,
                                    totalLengthOut: nil, dataPointerOut: &dataPointer2)

        guard let ptr1 = dataPointer1, let ptr2 = dataPointer2 else { return nil }

        let floatPtr1 = UnsafeMutableRawPointer(ptr1).bindMemory(to: Float.self, capacity: outputCount)
        let floatPtr2 = UnsafeMutableRawPointer(ptr2).bindMemory(to: Float.self, capacity: outputCount)

        // Allocate output buffer
        let outputBuffer = UnsafeMutablePointer<Float>.allocate(capacity: outputCount)
        defer { outputBuffer.deallocate() }

        // Scale buffer1 by volume1
        var vol1 = volume1
        vDSP_vsmul(floatPtr1, 1, &vol1, outputBuffer, 1, vDSP_Length(outputCount))

        // Scale buffer2 by volume2 and add
        var vol2 = volume2
        var scaledBuf2 = [Float](repeating: 0, count: outputCount)
        vDSP_vsmul(floatPtr2, 1, &vol2, &scaledBuf2, 1, vDSP_Length(outputCount))
        vDSP_vadd(outputBuffer, 1, scaledBuf2, 1, outputBuffer, 1, vDSP_Length(outputCount))

        // Clip to [-1.0, 1.0]
        var lo: Float = -1.0
        var hi: Float = 1.0
        vDSP_vclip(outputBuffer, 1, &lo, &hi, outputBuffer, 1, vDSP_Length(outputCount))

        // Create output CMSampleBuffer
        let outputByteLength = outputCount * MemoryLayout<Float>.size
        var outputBlockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: outputByteLength,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: outputByteLength,
            flags: 0,
            blockBufferOut: &outputBlockBuffer
        )

        guard let outBlock = outputBlockBuffer else { return nil }

        CMBlockBufferReplaceDataBytes(
            with: outputBuffer,
            blockBuffer: outBlock,
            offsetIntoDestination: 0,
            dataLength: outputByteLength
        )

        var formatDescription: CMFormatDescription?
        CMSampleBufferGetFormatDescription(buffer1).map { formatDescription = $0 }

        guard let format = formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(buffer1),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(buffer1),
            decodeTimeStamp: .invalid
        )

        let numSamples = CMSampleBufferGetNumSamples(buffer1)
        var outputSampleBuffer: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: outBlock,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: format,
            sampleCount: numSamples,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &outputSampleBuffer
        )

        return outputSampleBuffer
    }

    /// Apply volume scaling to a PCM sample buffer in-place.
    private static func applyVolume(to sampleBuffer: CMSampleBuffer, volume: Float) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let length = CMBlockBufferGetDataLength(dataBuffer)
        let sampleCount = length / MemoryLayout<Float>.size
        guard sampleCount > 0 else { return }

        var dataPointer: UnsafeMutablePointer<Int8>?
        var lengthAtOffset = 0
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset,
                                    totalLengthOut: nil, dataPointerOut: &dataPointer)

        guard let ptr = dataPointer else { return }
        let floatPtr = UnsafeMutableRawPointer(ptr).bindMemory(to: Float.self, capacity: sampleCount)

        var vol = volume
        vDSP_vsmul(floatPtr, 1, &vol, floatPtr, 1, vDSP_Length(sampleCount))

        // Clip to [-1.0, 1.0]
        var lo: Float = -1.0
        var hi: Float = 1.0
        vDSP_vclip(floatPtr, 1, &lo, &hi, floatPtr, 1, vDSP_Length(sampleCount))
    }
}

// MARK: - Errors

enum AudioMixerError: LocalizedError {
    case readerStartFailed(Error?)
    case noAudioTrack

    var errorDescription: String? {
        switch self {
        case .readerStartFailed(let error):
            if let error {
                return "Failed to start audio reader: \(error.localizedDescription)"
            }
            return "Failed to start audio reader"
        case .noAudioTrack:
            return "No audio track found in source"
        }
    }
}
