import Foundation
import CoreGraphics

// MARK: - Event Stream Adapter

/// Adapts polyrecorder event streams into the MouseDataSource protocol.
/// Used when loading v4 packages (preferred path).
struct EventStreamAdapter: MouseDataSource {
    let duration: TimeInterval
    let frameRate: Double

    private let mouseMovesData: [MousePositionData]
    private let mouseClicksData: [ClickEventData]
    private let keyboardEventsData: [KeyboardEventData]
    private let dragEventsData: [DragEventData]

    var positions: [MousePositionData] { mouseMovesData }
    var clicks: [ClickEventData] { mouseClicksData }
    var keyboardEvents: [KeyboardEventData] { keyboardEventsData }
    var dragEvents: [DragEventData] { dragEventsData }

    init(
        mouseMoves: [PolyMouseMoveEvent],
        mouseClicks: [PolyMouseClickEvent],
        keystrokes: [PolyKeystrokeEvent],
        metadata: PolyRecordingMetadata,
        duration: TimeInterval,
        frameRate: Double
    ) {
        self.duration = duration
        self.frameRate = frameRate

        let displayWidth = Double(metadata.display.widthPx)
        let displayHeight = Double(metadata.display.heightPx)
        let sessionStartMs = metadata.processTimeStartMs

        // Mouse moves -> MousePositionData (normalized, bottom-left origin)
        self.mouseMovesData = mouseMoves.map { event in
            let timelineSec = Double(event.processTimeMs - sessionStartMs) / 1000.0
            let xNorm = event.x / displayWidth
            let yNorm = 1.0 - (event.y / displayHeight)
            return MousePositionData(
                time: timelineSec,
                position: NormalizedPoint(x: CGFloat(xNorm), y: CGFloat(yNorm))
            )
        }

        // Mouse clicks -> ClickEventData
        self.mouseClicksData = mouseClicks
            .compactMap { event in
                let timelineSec = Double(event.processTimeMs - sessionStartMs) / 1000.0
                let xNorm = event.x / displayWidth
                let yNorm = 1.0 - (event.y / displayHeight)

                let clickType: ClickEventData.ClickType
                switch (event.type, event.button) {
                case ("mouseDown", "left"):
                    clickType = .leftDown
                case ("mouseUp", "left"):
                    clickType = .leftUp
                case ("mouseDown", "right"):
                    clickType = .rightDown
                case ("mouseUp", "right"):
                    clickType = .rightUp
                default:
                    return nil
                }

                return ClickEventData(
                    time: timelineSec,
                    position: NormalizedPoint(x: CGFloat(xNorm), y: CGFloat(yNorm)),
                    clickType: clickType
                )
            }

        // Keystrokes -> KeyboardEventData
        self.keyboardEventsData = keystrokes.map { event in
            let timelineSec = Double(event.processTimeMs - sessionStartMs) / 1000.0
            let eventType: KeyboardEventData.EventType = (event.type == "keyDown") ? .keyDown : .keyUp
            var modifiers: KeyboardEventData.ModifierFlags = []
            if event.activeModifiers.contains("shift") { modifiers.insert(.shift) }
            if event.activeModifiers.contains("control") { modifiers.insert(.control) }
            if event.activeModifiers.contains("option") { modifiers.insert(.option) }
            if event.activeModifiers.contains("command") { modifiers.insert(.command) }
            return KeyboardEventData(
                time: timelineSec,
                keyCode: 0,
                eventType: eventType,
                modifiers: modifiers,
                character: event.character
            )
        }

        // Drag events: not available in polyrecorder streams (Phase 1)
        self.dragEventsData = []
    }
}

// MARK: - Event Stream Loader

/// Loads event stream files from a v4 package using the interop block paths.
enum EventStreamLoader {

    /// Load event streams from a v4 package and produce a MouseDataSource.
    /// Returns nil if streams are missing or unreadable (caller should fall back to v2).
    static func load(
        from packageURL: URL,
        interop: InteropBlock,
        duration: TimeInterval,
        frameRate: Double
    ) -> MouseDataSource? {
        let decoder = JSONDecoder()

        // Load recording metadata
        let metadataURL = packageURL.appendingPathComponent(interop.recordingMetadataPath)
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? decoder.decode(PolyRecordingMetadata.self, from: metadataData) else {
            return nil
        }

        // Load mouse moves
        var mouseMoves: [PolyMouseMoveEvent] = []
        if let path = interop.streams.mouseMoves {
            let url = packageURL.appendingPathComponent(path)
            if let data = try? Data(contentsOf: url) {
                mouseMoves = (try? decoder.decode([PolyMouseMoveEvent].self, from: data)) ?? []
            }
        }

        // Load mouse clicks
        var mouseClicks: [PolyMouseClickEvent] = []
        if let path = interop.streams.mouseClicks {
            let url = packageURL.appendingPathComponent(path)
            if let data = try? Data(contentsOf: url) {
                mouseClicks = (try? decoder.decode([PolyMouseClickEvent].self, from: data)) ?? []
            }
        }

        // Load keystrokes
        var keystrokes: [PolyKeystrokeEvent] = []
        if let path = interop.streams.keystrokes {
            let url = packageURL.appendingPathComponent(path)
            if let data = try? Data(contentsOf: url) {
                keystrokes = (try? decoder.decode([PolyKeystrokeEvent].self, from: data)) ?? []
            }
        }

        return EventStreamAdapter(
            mouseMoves: mouseMoves,
            mouseClicks: mouseClicks,
            keystrokes: keystrokes,
            metadata: metadata,
            duration: duration,
            frameRate: frameRate
        )
    }

    /// Load UI state samples from a v4 package.
    /// Returns empty array if the stream is missing or unreadable.
    static func loadUIStateSamples(
        from packageURL: URL,
        interop: InteropBlock,
        metadata: PolyRecordingMetadata? = nil
    ) -> [UIStateSample] {
        let decoder = JSONDecoder()

        // Load metadata if not provided
        let meta: PolyRecordingMetadata
        if let metadata {
            meta = metadata
        } else {
            let metadataURL = packageURL.appendingPathComponent(interop.recordingMetadataPath)
            guard let metadataData = try? Data(contentsOf: metadataURL),
                  let decoded = try? decoder.decode(PolyRecordingMetadata.self, from: metadataData) else {
                return []
            }
            meta = decoded
        }

        guard let path = interop.streams.uiStates else { return [] }
        let url = packageURL.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url),
              let events = try? decoder.decode([PolyUIStateEvent].self, from: data) else {
            return []
        }

        let sessionStartMs = meta.processTimeStartMs

        return events.map { event in
            let timelineSec = Double(event.processTimeMs - sessionStartMs) / 1000.0

            let elementInfo: UIElementInfo?
            if let role = event.elementRole,
               let frameX = event.elementFrameX,
               let frameY = event.elementFrameY,
               let frameW = event.elementFrameW,
               let frameH = event.elementFrameH {
                elementInfo = UIElementInfo(
                    role: role,
                    subrole: event.elementSubrole,
                    frame: CGRect(x: frameX, y: frameY, width: frameW, height: frameH),
                    title: event.elementTitle,
                    isClickable: event.elementIsClickable ?? false,
                    applicationName: event.elementAppName
                )
            } else {
                elementInfo = nil
            }

            let caretBounds: CGRect?
            if let cx = event.caretX, let cy = event.caretY,
               let cw = event.caretW, let ch = event.caretH {
                caretBounds = CGRect(x: cx, y: cy, width: cw, height: ch)
            } else {
                caretBounds = nil
            }

            return UIStateSample(
                timestamp: timelineSec,
                cursorPosition: CGPoint(x: event.cursorX, y: event.cursorY),
                elementInfo: elementInfo,
                caretBounds: caretBounds
            )
        }
    }
}
