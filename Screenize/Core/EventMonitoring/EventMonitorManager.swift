import Foundation
import AppKit

// MARK: - Event Monitor Manager

/// Utility for managing NSEvent monitors
/// Encapsulates the global/local monitor pair pattern to reduce duplication
final class EventMonitorManager {

    // MARK: - Monitor Pair

    /// Global + Local monitor pair
    /// Most use cases require monitoring both external (global) and internal (local) events
    final class MonitorPair {
        private var globalMonitor: Any?
        private var localMonitor: Any?

        init(
            events: NSEvent.EventTypeMask,
            globalHandler: @escaping (NSEvent) -> Void,
            localHandler: ((NSEvent) -> NSEvent?)? = nil
        ) {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: globalHandler)

            // If localHandler is missing, reuse the global handler and pass the event through
            let actualLocalHandler: (NSEvent) -> NSEvent? = localHandler ?? { event in
                globalHandler(event)
                return event
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: actualLocalHandler)
        }

        func stop() {
            if let monitor = globalMonitor {
                NSEvent.removeMonitor(monitor)
                globalMonitor = nil
            }
            if let monitor = localMonitor {
                NSEvent.removeMonitor(monitor)
                localMonitor = nil
            }
        }

        deinit {
            stop()
        }
    }

    // MARK: - Properties

    private var monitorPairs: [String: MonitorPair] = [:]
    private let lock = NSLock()

    // MARK: - Public Methods

    /// Add a monitor pair
    /// - Parameters:
    ///   - identifier: Monitor identifier (for later removal)
    ///   - events: Event types to monitor
    ///   - handler: Event handler
    func addMonitor(
        identifier: String,
        events: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        // Stop any existing monitor first
        monitorPairs[identifier]?.stop()

        monitorPairs[identifier] = MonitorPair(
            events: events,
            globalHandler: handler
        )
    }

    /// Add a monitor pair with a custom local handler
    /// - Parameters:
    ///   - identifier: Monitor identifier
    ///   - events: Event types to monitor
    ///   - globalHandler: Global event handler
    ///   - localHandler: Local event handler (can modify events)
    func addMonitor(
        identifier: String,
        events: NSEvent.EventTypeMask,
        globalHandler: @escaping (NSEvent) -> Void,
        localHandler: @escaping (NSEvent) -> NSEvent?
    ) {
        lock.lock()
        defer { lock.unlock() }

        monitorPairs[identifier]?.stop()

        monitorPairs[identifier] = MonitorPair(
            events: events,
            globalHandler: globalHandler,
            localHandler: localHandler
        )
    }

    /// Remove a specific monitor
    func removeMonitor(identifier: String) {
        lock.lock()
        defer { lock.unlock() }

        monitorPairs[identifier]?.stop()
        monitorPairs.removeValue(forKey: identifier)
    }

    /// Remove all monitors
    func removeAllMonitors() {
        lock.lock()
        defer { lock.unlock() }

        for pair in monitorPairs.values {
            pair.stop()
        }
        monitorPairs.removeAll()
    }

    deinit {
        removeAllMonitors()
    }
}

// MARK: - Convenience Extensions

extension EventMonitorManager {

    /// Add mouse movement monitor
    func addMouseMovementMonitor(
        identifier: String = "mouseMovement",
        handler: @escaping (NSEvent) -> Void
    ) {
        addMonitor(
            identifier: identifier,
            events: [.mouseMoved, .leftMouseDragged, .rightMouseDragged],
            handler: handler
        )
    }

    /// Add mouse click monitor
    func addMouseClickMonitor(
        identifier: String = "mouseClick",
        handler: @escaping (NSEvent) -> Void
    ) {
        addMonitor(
            identifier: identifier,
            events: [.leftMouseDown, .rightMouseDown],
            handler: handler
        )
    }

    /// Add scroll monitor
    func addScrollMonitor(
        identifier: String = "scroll",
        handler: @escaping (NSEvent) -> Void
    ) {
        addMonitor(
            identifier: identifier,
            events: .scrollWheel,
            handler: handler
        )
    }
}
