import Foundation
import AVFoundation
import CoreMedia

/// Writes system audio sample buffers from ScreenCaptureKit to a sidecar .m4a file.
/// Accepts CMSampleBuffer input directly (no AVCaptureSession needed).
final class SystemAudioWriter: @unchecked Sendable {

    // MARK: - Properties

    private var assetWriter: AVAssetWriter?
    private var audioWriterInput: AVAssetWriterInput?
    private var isWriting = false
    private var isPaused = false
    private var sessionStarted = false
    private let lock = NSLock()
    private var outputURL: URL?

    // MARK: - Recording Control

    /// Start writing system audio to the specified URL.
    func startWriting(to url: URL) throws {
        self.outputURL = url

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        guard writer.startWriting() else {
            throw SystemAudioWriterError.writerStartFailed(writer.error)
        }

        self.assetWriter = writer
        self.audioWriterInput = input
        self.sessionStarted = false
        self.isWriting = true
        self.isPaused = false

        print("[SystemAudioWriter] Started writing to \(url.lastPathComponent)")
    }

    /// Append a system audio sample buffer (called from capture queue).
    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        guard isWriting, !isPaused else {
            lock.unlock()
            return
        }
        lock.unlock()

        guard let input = audioWriterInput,
              input.isReadyForMoreMediaData else { return }

        if !sessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: pts)
            sessionStarted = true
        }

        input.append(sampleBuffer)
    }

    /// Stop writing and return the output URL.
    func stopWriting() async -> URL? {
        lock.lock()
        isWriting = false
        lock.unlock()

        guard let writer = assetWriter else { return nil }
        audioWriterInput?.markAsFinished()

        let url = self.outputURL
        return await withCheckedContinuation { continuation in
            writer.finishWriting {
                let result = writer.status == .completed ? url : nil
                print("[SystemAudioWriter] Stopped writing: \(result?.lastPathComponent ?? "failed")")
                continuation.resume(returning: result)
            }
        }
    }

    /// Pause writing (audio samples will be silently dropped).
    func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
    }

    /// Resume writing after a pause.
    func resume() {
        lock.lock()
        isPaused = false
        lock.unlock()
    }
}

// MARK: - Errors

enum SystemAudioWriterError: LocalizedError {
    case writerStartFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .writerStartFailed(let error):
            if let error {
                return "Failed to start system audio writer: \(error.localizedDescription)"
            }
            return "Failed to start system audio writer"
        }
    }
}
