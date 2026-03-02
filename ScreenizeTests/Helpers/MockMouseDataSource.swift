import Foundation
@testable import Screenize

/// Mock MouseDataSource for unit testing.
struct MockMouseDataSource: MouseDataSource {
    var duration: TimeInterval
    var frameRate: Double
    var positions: [MousePositionData]
    var clicks: [ClickEventData]
    var keyboardEvents: [KeyboardEventData]
    var dragEvents: [DragEventData]

    init(
        duration: TimeInterval = 10.0,
        frameRate: Double = 60.0,
        positions: [MousePositionData] = [],
        clicks: [ClickEventData] = [],
        keyboardEvents: [KeyboardEventData] = [],
        dragEvents: [DragEventData] = []
    ) {
        self.duration = duration
        self.frameRate = frameRate
        self.positions = positions
        self.clicks = clicks
        self.keyboardEvents = keyboardEvents
        self.dragEvents = dragEvents
    }
}
