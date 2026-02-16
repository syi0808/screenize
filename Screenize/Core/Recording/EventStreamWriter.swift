import Foundation
import CoreGraphics

// MARK: - Event Stream Writer

/// Writes polyrecorder-compatible event stream files from a MouseRecording.
/// Called during the recording pipeline to produce the v4 canonical format.
struct EventStreamWriter {

    /// Write all event stream files into the recording directory.
    static func write(
        recording: MouseRecording,
        to recordingDir: URL,
        captureMeta: CaptureMeta,
        recordingStartDate: Date,
        processTimeStartMs: Int64,
        appVersion: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let processTimeEndMs = processTimeStartMs + Int64(recording.recordingDuration * 1000)
        let unixStartMs = Int64(recordingStartDate.timeIntervalSince1970 * 1000)
        let height = recording.screenBounds.height
        let sf = Double(captureMeta.scaleFactor)

        try writeMetadata(
            encoder: encoder, to: recordingDir, captureMeta: captureMeta,
            recordingStartDate: recordingStartDate, appVersion: appVersion,
            processTimeStartMs: processTimeStartMs, processTimeEndMs: processTimeEndMs,
            unixStartMs: unixStartMs
        )
        try writeMouseMoves(
            encoder: encoder, to: recordingDir, positions: recording.positions,
            height: height, scaleFactor: sf,
            processTimeStartMs: processTimeStartMs, unixStartMs: unixStartMs
        )
        try writeMouseClicks(
            encoder: encoder, to: recordingDir, clicks: recording.clicks,
            height: height, scaleFactor: sf,
            processTimeStartMs: processTimeStartMs, unixStartMs: unixStartMs
        )
        try writeKeystrokes(
            encoder: encoder, to: recordingDir, events: recording.keyboardEvents,
            processTimeStartMs: processTimeStartMs, unixStartMs: unixStartMs
        )
        try writeUIStates(
            encoder: encoder, to: recordingDir, samples: recording.uiStateSamples,
            processTimeStartMs: processTimeStartMs, unixStartMs: unixStartMs
        )
    }

    // MARK: - Private

    private static func writeMetadata(
        encoder: JSONEncoder, to dir: URL, captureMeta: CaptureMeta,
        recordingStartDate: Date, appVersion: String,
        processTimeStartMs: Int64, processTimeEndMs: Int64, unixStartMs: Int64
    ) throws {
        let widthPx = Int(captureMeta.boundsPt.width * captureMeta.scaleFactor)
        let heightPx = Int(captureMeta.boundsPt.height * captureMeta.scaleFactor)
        let metadata = PolyRecordingMetadata(
            formatVersion: 2,
            recorderName: "screenize",
            recorderVersion: appVersion,
            createdAt: ISO8601DateFormatter().string(from: recordingStartDate),
            processTimeStartMs: processTimeStartMs,
            processTimeEndMs: processTimeEndMs,
            unixTimeStartMs: unixStartMs,
            display: PolyRecordingMetadata.DisplayInfo(
                widthPx: widthPx, heightPx: heightPx,
                scaleFactor: Double(captureMeta.scaleFactor)
            )
        )
        try encoder.encode(metadata).write(
            to: dir.appendingPathComponent("metadata.json"), options: .atomic
        )
    }

    private static func writeMouseMoves(
        encoder: JSONEncoder, to dir: URL, positions: [MousePosition],
        height: CGFloat, scaleFactor: Double,
        processTimeStartMs: Int64, unixStartMs: Int64
    ) throws {
        let moves: [PolyMouseMoveEvent] = positions.map { pos in
            let offsetMs = Int64(pos.timestamp * 1000)
            return PolyMouseMoveEvent(
                type: "mouseMoved",
                processTimeMs: processTimeStartMs + offsetMs,
                unixTimeMs: unixStartMs + offsetMs,
                x: Double(pos.x) * scaleFactor,
                y: Double(height - pos.y) * scaleFactor,
                cursorId: nil, activeModifiers: [], button: nil
            )
        }
        try encoder.encode(moves).write(
            to: dir.appendingPathComponent("mousemoves-0.json"), options: .atomic
        )
    }

    private static func writeMouseClicks(
        encoder: JSONEncoder, to dir: URL, clicks: [MouseClickEvent],
        height: CGFloat, scaleFactor: Double,
        processTimeStartMs: Int64, unixStartMs: Int64
    ) throws {
        var result: [PolyMouseClickEvent] = []
        for click in clicks {
            let button = (click.type == .left) ? "left" : "right"
            let downMs = Int64(click.timestamp * 1000)
            result.append(PolyMouseClickEvent(
                type: "mouseDown",
                processTimeMs: processTimeStartMs + downMs, unixTimeMs: unixStartMs + downMs,
                x: Double(click.x) * scaleFactor,
                y: Double(height - click.y) * scaleFactor,
                button: button, cursorId: nil, activeModifiers: []
            ))
            let upMs = Int64(click.endTimestamp * 1000)
            result.append(PolyMouseClickEvent(
                type: "mouseUp",
                processTimeMs: processTimeStartMs + upMs, unixTimeMs: unixStartMs + upMs,
                x: Double(click.x) * scaleFactor,
                y: Double(height - click.y) * scaleFactor,
                button: button, cursorId: nil, activeModifiers: []
            ))
        }
        try encoder.encode(result).write(
            to: dir.appendingPathComponent("mouseclicks-0.json"), options: .atomic
        )
    }

    private static func writeKeystrokes(
        encoder: JSONEncoder, to dir: URL, events: [KeyboardEvent],
        processTimeStartMs: Int64, unixStartMs: Int64
    ) throws {
        let keystrokes: [PolyKeystrokeEvent] = events.map { event in
            let offsetMs = Int64(event.timestamp * 1000)
            return PolyKeystrokeEvent(
                type: event.type == .keyDown ? "keyDown" : "keyUp",
                processTimeMs: processTimeStartMs + offsetMs,
                unixTimeMs: unixStartMs + offsetMs,
                character: event.character, isARepeat: false,
                activeModifiers: ActiveModifiersConverter.toStrings(from: event.modifiers)
            )
        }
        try encoder.encode(keystrokes).write(
            to: dir.appendingPathComponent("keystrokes-0.json"), options: .atomic
        )
    }

    private static func writeUIStates(
        encoder: JSONEncoder, to dir: URL, samples: [UIStateSample],
        processTimeStartMs: Int64, unixStartMs: Int64
    ) throws {
        let events: [PolyUIStateEvent] = samples.map { sample in
            let offsetMs = Int64(sample.timestamp * 1000)
            return PolyUIStateEvent(
                processTimeMs: processTimeStartMs + offsetMs,
                unixTimeMs: unixStartMs + offsetMs,
                cursorX: Double(sample.cursorPosition.x),
                cursorY: Double(sample.cursorPosition.y),
                elementRole: sample.elementInfo?.role,
                elementSubrole: sample.elementInfo?.subrole,
                elementTitle: sample.elementInfo?.title,
                elementAppName: sample.elementInfo?.applicationName,
                elementFrameX: sample.elementInfo.map { Double($0.frame.origin.x) },
                elementFrameY: sample.elementInfo.map { Double($0.frame.origin.y) },
                elementFrameW: sample.elementInfo.map { Double($0.frame.width) },
                elementFrameH: sample.elementInfo.map { Double($0.frame.height) },
                elementIsClickable: sample.elementInfo?.isClickable,
                caretX: sample.caretBounds.map { Double($0.origin.x) },
                caretY: sample.caretBounds.map { Double($0.origin.y) },
                caretW: sample.caretBounds.map { Double($0.width) },
                caretH: sample.caretBounds.map { Double($0.height) }
            )
        }
        try encoder.encode(events).write(
            to: dir.appendingPathComponent("uistates-0.json"), options: .atomic
        )
    }
}
