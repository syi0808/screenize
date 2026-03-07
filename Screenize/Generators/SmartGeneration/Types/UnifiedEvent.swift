import Foundation
import CoreGraphics

/// Unified event type combining all input events into a single timeline.
struct UnifiedEvent {
    let time: TimeInterval
    let kind: EventKind
    let position: NormalizedPoint
    let metadata: EventMetadata
}

/// Kind of unified event.
enum EventKind {
    case mouseMove
    case click(ClickEventData)
    case keyDown(KeyboardEventData)
    case keyUp(KeyboardEventData)
    case dragStart(DragEventData)
    case dragEnd(DragEventData)
    case scroll(direction: ScrollDirection, magnitude: CGFloat)
    case uiStateChange(UIStateSample)
}

/// Metadata attached to a unified event.
struct EventMetadata {
    let appBundleID: String?
    let elementInfo: UIElementInfo?
    let caretBounds: CGRect?

    init(
        appBundleID: String? = nil,
        elementInfo: UIElementInfo? = nil,
        caretBounds: CGRect? = nil
    ) {
        self.appBundleID = appBundleID
        self.elementInfo = elementInfo
        self.caretBounds = caretBounds
    }
}
