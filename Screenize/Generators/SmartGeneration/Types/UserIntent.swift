import Foundation

/// User intent classification.
enum UserIntent: Equatable {
    case typing(context: TypingContext)
    case clicking
    case navigating
    case dragging(DragContext)
    case reading
    case scrolling
    case switching
    case idle
}

/// Typing sub-context.
enum TypingContext: Equatable {
    case codeEditor
    case textField
    case terminal
    case richTextEditor
}

/// Drag sub-context.
enum DragContext: Equatable {
    case selection
    case move
    case resize
}

/// A time span labeled with a user intent.
struct IntentSpan {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let intent: UserIntent
    let confidence: Float
    let focusPosition: NormalizedPoint
    let focusElement: UIElementInfo?
    var contextChange: UIStateSample.ContextChange?
}
