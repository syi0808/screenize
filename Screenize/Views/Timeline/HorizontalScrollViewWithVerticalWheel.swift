import SwiftUI
import AppKit

/// Scroll view that converts vertical mouse wheel input into horizontal scrolling
/// Makes long horizontal content (like timelines) easier to scroll with the mouse wheel
struct HorizontalScrollViewWithVerticalWheel<Content: View>: NSViewRepresentable {

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = VerticalToHorizontalScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.autohidesScrollers = true

        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = hostingView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        if let hostingView = scrollView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
        }
    }
}

/// NSScrollView subclass that converts vertical scroll wheel events into horizontal scrolling
private class VerticalToHorizontalScrollView: NSScrollView {

    override func scrollWheel(with event: NSEvent) {
        // Convert to horizontal scrolling when the vertical delta is larger
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            // Create a new event to reuse deltaY as deltaX
            let newEvent = event.cgEvent?.copy()
            if let cgEvent = newEvent {
                // Use scrollingDeltaY and apply it as scrollingDeltaX
                // Set the scroll values directly on the CGEvent
                let deltaY = event.scrollingDeltaY

                // Compute the current scroll position
                var newOrigin = contentView.bounds.origin
                newOrigin.x -= deltaY  // Apply the Y delta to X (invert sign for a natural direction)

                // Clamp within valid bounds
                let maxX = max(0, (documentView?.frame.width ?? 0) - contentView.bounds.width)
                newOrigin.x = max(0, min(maxX, newOrigin.x))

                // Apply the scroll
                contentView.scroll(to: newOrigin)
                reflectScrolledClipView(contentView)
                return
            }
        }

        // Fall back to the default behavior when horizontal scrolling dominates or conversion fails
        super.scrollWheel(with: event)
    }
}
