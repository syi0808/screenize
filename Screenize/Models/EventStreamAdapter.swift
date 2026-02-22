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

        // Infer drag events from mouseDown+mouseMoved+mouseUp sequences.
        // Polyrecorder-v2 doesn't store explicit drag events, so we detect them
        // by checking mouse displacement between mouseDown and mouseUp.
        let (inferredDrags, dragClickIndices) = Self.synthesizeDragEvents(
            clicks: mouseClicks,
            moves: mouseMoves,
            displayWidth: displayWidth,
            displayHeight: displayHeight,
            sessionStartMs: sessionStartMs
        )
        self.dragEventsData = inferredDrags

        // Mouse clicks -> ClickEventData (excluding events reclassified as drags)
        self.mouseClicksData = mouseClicks
            .enumerated()
            .compactMap { index, event in
                if dragClickIndices.contains(index) { return nil }

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
                keyCode: event.keyCode ?? 0,
                eventType: eventType,
                modifiers: modifiers,
                character: event.character
            )
        }
    }

    // MARK: - Drag Inference

    /// Minimum normalized distance to classify a mouseDown/mouseUp pair as a drag.
    /// ~30px on a 1512px display (0.02 * 1512 ≈ 30).
    private static let dragDistanceThreshold: CGFloat = 0.02

    /// Synthesize drag events from mouseDown+mouseMoved+mouseUp sequences.
    /// Returns inferred drags and the indices of click events to remove.
    private static func synthesizeDragEvents(
        clicks: [PolyMouseClickEvent],
        moves: [PolyMouseMoveEvent],
        displayWidth: Double,
        displayHeight: Double,
        sessionStartMs: Int64
    ) -> ([DragEventData], Set<Int>) {
        var drags: [DragEventData] = []
        var indicesToRemove: Set<Int> = []

        // Pair each left mouseDown with the next left mouseUp
        for (downIdx, downEvent) in clicks.enumerated() {
            guard downEvent.type == "mouseDown" && downEvent.button == "left" else {
                continue
            }

            // Find matching mouseUp (next left mouseUp after this mouseDown)
            guard let upIdx = clicks.indices.first(where: { idx in
                idx > downIdx
                    && clicks[idx].type == "mouseUp"
                    && clicks[idx].button == "left"
            }) else { continue }

            let upEvent = clicks[upIdx]

            // Gather mouse moves between down and up times
            let downTime = downEvent.processTimeMs
            let upTime = upEvent.processTimeMs
            let movesInRange = moves.filter {
                $0.processTimeMs >= downTime && $0.processTimeMs <= upTime
            }

            guard movesInRange.count >= 2 else { continue }

            // Compute max displacement from the mouseDown position
            let downXNorm = downEvent.x / displayWidth
            let downYNorm = 1.0 - (downEvent.y / displayHeight)
            let downPos = NormalizedPoint(
                x: CGFloat(downXNorm), y: CGFloat(downYNorm)
            )

            var maxDisplacement: CGFloat = 0
            var farthestPos = downPos
            for move in movesInRange {
                let mx = CGFloat(move.x / displayWidth)
                let my = CGFloat(1.0 - (move.y / displayHeight))
                let pos = NormalizedPoint(x: mx, y: my)
                let dist = downPos.distance(to: pos)
                if dist > maxDisplacement {
                    maxDisplacement = dist
                    farthestPos = pos
                }
            }

            guard maxDisplacement >= dragDistanceThreshold else { continue }

            // Use last mouse move position as the drag end position
            let lastMove = movesInRange.last!
            let endX = CGFloat(lastMove.x / displayWidth)
            let endY = CGFloat(1.0 - (lastMove.y / displayHeight))
            let endPos = NormalizedPoint(x: endX, y: endY)

            let startTime = Double(downTime - sessionStartMs) / 1000.0
            let endTime = Double(upTime - sessionStartMs) / 1000.0

            drags.append(DragEventData(
                startTime: startTime,
                endTime: endTime,
                startPosition: downPos,
                endPosition: endPos,
                dragType: .selection
            ))
            indicesToRemove.insert(downIdx)
            indicesToRemove.insert(upIdx)
        }

        return (drags, indicesToRemove)
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
        let displayWidth = Double(meta.display.widthPx)
        let displayHeight = Double(meta.display.heightPx)
        let scaleFactor = meta.display.scaleFactor

        return events.map { event in
            let timelineSec = Double(event.processTimeMs - sessionStartMs) / 1000.0

            // Normalize cursor position: logical points → normalized (bottom-left origin)
            let cursorXNorm = event.cursorX * scaleFactor / displayWidth
            let cursorYNorm = 1.0 - (event.cursorY * scaleFactor / displayHeight)

            // Element frame: may be in global screen coordinates (can exceed display bounds).
            // Attempt to build frame, but discard if out of display range.
            let elementInfo: UIElementInfo?
            if let role = event.elementRole,
               let frameX = event.elementFrameX,
               let frameY = event.elementFrameY,
               let frameW = event.elementFrameW,
               let frameH = event.elementFrameH {
                // Estimate display-local position using cursor as reference:
                // cursorX/Y is display-local logical; elementFrame is global logical.
                // Offset = elementFrameOrigin - (cursorLogical - cursorRelativeToElement)
                // Since we can't reliably compute this, store raw and let downstream validate.
                let rawFrame = CGRect(x: frameX, y: frameY, width: frameW, height: frameH)
                elementInfo = UIElementInfo(
                    role: role,
                    subrole: event.elementSubrole,
                    frame: rawFrame,
                    title: event.elementTitle,
                    isClickable: event.elementIsClickable ?? false,
                    applicationName: event.elementAppName
                )
            } else {
                elementInfo = nil
            }

            // Caret bounds: also in global screen coordinates — store raw, validate downstream
            let caretBounds: CGRect?
            if let cx = event.caretX, let cy = event.caretY,
               let cw = event.caretW, let ch = event.caretH {
                caretBounds = CGRect(x: cx, y: cy, width: cw, height: ch)
            } else {
                caretBounds = nil
            }

            return UIStateSample(
                timestamp: timelineSec,
                cursorPosition: CGPoint(x: cursorXNorm, y: cursorYNorm),
                elementInfo: elementInfo,
                caretBounds: caretBounds
            )
        }
    }
}
