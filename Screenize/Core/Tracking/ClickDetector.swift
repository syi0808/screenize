import Foundation
import AppKit
import Combine

@MainActor
final class ClickDetector {
    @Published private(set) var lastClick: ClickEvent?
    @Published private(set) var activeClicks: [ClickEvent] = []

    private let eventMonitor = EventMonitorManager()
    private var isTracking = false

    private let clickDuration: TimeInterval = 0.3 // How long to show click effect

    struct ClickEvent: Identifiable {
        let id = UUID()
        let position: CGPoint
        let screenPosition: CGPoint
        let type: ClickType  // References Models/ClickType.swift
        let timestamp: Date

        var age: TimeInterval {
            Date().timeIntervalSince(timestamp)
        }
    }

    init() {}

    func startTracking() {
        guard !isTracking else { return }

        // Monitor mouse clicks (global + local)
        eventMonitor.addMouseClickMonitor { [weak self] event in
            self?.handleClickEvent(event)
        }

        isTracking = true

        // Start cleanup timer
        startCleanupTimer()
    }

    func stopTracking() {
        guard isTracking else { return }

        eventMonitor.removeAllMonitors()
        isTracking = false
    }

    private func handleClickEvent(_ event: NSEvent) {
        let position = NSEvent.mouseLocation

        // Convert to screen coordinates (top-left origin)
        let screenPosition = CoordinateConverter.appKitToTopLeftOrigin(
            position,
            screenHeight: CoordinateConverter.mainScreenHeight
        )

        let clickType: ClickType
        switch event.type {
        case .leftMouseDown:
            clickType = .left
        case .rightMouseDown:
            clickType = .right
        default:
            return
        }

        let click = ClickEvent(
            position: position,
            screenPosition: screenPosition,
            type: clickType,
            timestamp: Date()
        )

        lastClick = click
        activeClicks.append(click)
    }

    private var cleanupTimer: Timer?

    private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupExpiredClicks()
            }
        }
    }

    private func cleanupExpiredClicks() {
        activeClicks.removeAll { click in
            click.age > clickDuration
        }
    }

    func normalizedClickPosition(_ click: ClickEvent, in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: (click.screenPosition.x - bounds.origin.x) / bounds.width,
            y: (click.screenPosition.y - bounds.origin.y) / bounds.height
        )
    }

    deinit {
        eventMonitor.removeAllMonitors()
        cleanupTimer?.invalidate()
    }
}
