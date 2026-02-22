import Foundation
import AVFoundation
import CoreMedia

/// Records microphone audio to a sidecar .m4a file using AVCaptureSession.
/// Uses AVCaptureSession instead of ScreenCaptureKit because SCK does not
/// support microphone device selection.
final class MicrophoneRecorder: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var assetWriter: AVAssetWriter?
    private var audioWriterInput: AVAssetWriterInput?

    private let recordingQueue = DispatchQueue(
        label: "com.screenize.mic-recorder",
        qos: .userInteractive
    )

    private var isRecording = false
    private var isPaused = false
    private var sessionStarted = false
    private let lock = NSLock()

    private var outputURL: URL?

    // MARK: - Recording Control

    /// Start recording microphone audio to the specified URL.
    /// - Parameters:
    ///   - url: Output .m4a file URL
    ///   - device: Microphone device to use (nil for system default)
    func startRecording(to url: URL, device: AVCaptureDevice? = nil) throws {
        let mic = device ?? AVCaptureDevice.default(for: .audio)
        guard let mic else {
            throw MicrophoneRecorderError.noDeviceAvailable
        }

        self.outputURL = url

        // Setup AVCaptureSession
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: mic)
        guard session.canAddInput(input) else {
            throw MicrophoneRecorderError.inputConfigFailed
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: recordingQueue)
        guard session.canAddOutput(output) else {
            throw MicrophoneRecorderError.outputConfigFailed
        }
        session.addOutput(output)

        self.captureSession = session
        self.audioOutput = output

        // Setup AVAssetWriter for M4A output
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000
        ]
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings
        )
        writerInput.expectsMediaDataInRealTime = true
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw MicrophoneRecorderError.writerStartFailed(writer.error)
        }

        self.assetWriter = writer
        self.audioWriterInput = writerInput
        self.sessionStarted = false
        self.isRecording = true
        self.isPaused = false

        session.startRunning()
        print("[MicrophoneRecorder] Started recording to \(url.lastPathComponent)")
    }

    /// Stop recording and return the output URL.
    func stopRecording() async -> URL? {
        lock.lock()
        isRecording = false
        lock.unlock()

        captureSession?.stopRunning()
        captureSession = nil
        audioOutput = nil

        guard let writer = assetWriter else { return nil }
        audioWriterInput?.markAsFinished()

        let url = self.outputURL
        return await withCheckedContinuation { continuation in
            writer.finishWriting {
                let result = writer.status == .completed ? url : nil
                print("[MicrophoneRecorder] Stopped recording: \(result?.lastPathComponent ?? "failed")")
                continuation.resume(returning: result)
            }
        }
    }

    /// Pause recording (audio samples will be silently dropped).
    func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
    }

    /// Resume recording after a pause.
    func resume() {
        lock.lock()
        isPaused = false
        lock.unlock()
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension MicrophoneRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        guard isRecording, !isPaused else {
            lock.unlock()
            return
        }
        lock.unlock()

        guard let writerInput = audioWriterInput,
              writerInput.isReadyForMoreMediaData else { return }

        if !sessionStarted {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            assetWriter?.startSession(atSourceTime: pts)
            sessionStarted = true
        }

        writerInput.append(sampleBuffer)
    }
}

// MARK: - Errors

enum MicrophoneRecorderError: LocalizedError {
    case noDeviceAvailable
    case inputConfigFailed
    case outputConfigFailed
    case writerStartFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .noDeviceAvailable:
            return "No microphone device available"
        case .inputConfigFailed:
            return "Failed to configure microphone input"
        case .outputConfigFailed:
            return "Failed to configure audio output"
        case .writerStartFailed(let error):
            if let error {
                return "Failed to start audio writer: \(error.localizedDescription)"
            }
            return "Failed to start audio writer"
        }
    }
}
