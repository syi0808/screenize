import Foundation
import ApplicationServices
import CoreGraphics

/// Resolves AXTarget references to live AXUIElements using a 4-level fallback chain.
///
/// Fallback order:
/// 1. AX path + axTitle — walks the element tree along the recorded role path, verifies title at leaf
/// 2. axTitle only — BFS from the focused app's root element, up to depth 10 with a 500ms timeout
/// 3. role + positionHint — looks up element at the converted absolute coordinate and checks its role
/// 4. absoluteCoord — raw screen coordinate used as-is for event injection
final class AXTargetResolver {

    // MARK: - Public Types

    enum ResolvedTarget {
        /// Found a live AXUIElement plus its computed screen center point.
        case element(AXUIElement, CGPoint)
        /// Fallback: only a raw screen coordinate is available.
        case coordinate(CGPoint)
    }

    enum ResolutionStrategy: CaseIterable {
        case pathAndTitle
        case titleOnly
        case roleAndPosition
        case coordinate
    }

    // MARK: - Private Properties

    private let resolverQueue = DispatchQueue(label: "com.screenize.axResolver", qos: .userInitiated)
    private static let timeoutPerStrategy: TimeInterval = 0.5

    // MARK: - Public Interface

    /// Resolves the target using the 4-level fallback chain. Executes on a background queue.
    /// Has a hard 1-second timeout — if AX calls hang, falls back to coordinate.
    func resolve(target: AXTarget, captureArea: CGRect) async -> ResolvedTarget? {
        // AXUIElement calls are synchronous Mach IPC that can hang indefinitely if the target
        // app is unresponsive. Use a separate timeout queue to guarantee we always return.
        await withCheckedContinuation { continuation in
            var didResume = false
            let lock = NSLock()

            // Run AX resolution on the resolver queue (may block)
            resolverQueue.async {
                let result = self.resolveSync(target: target, captureArea: captureArea)
                lock.lock()
                guard !didResume else { lock.unlock(); return }
                didResume = true
                lock.unlock()
                continuation.resume(returning: result)
            }

            // Timeout on a DIFFERENT queue (global) so it fires even if resolverQueue is blocked
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                lock.lock()
                guard !didResume else { lock.unlock(); return }
                didResume = true
                lock.unlock()
                // AX call is stuck — fall back to raw coordinate
                continuation.resume(returning: .coordinate(target.absoluteCoord))
            }
        }
    }

    // MARK: - Static Helpers (testable)

    /// Returns the ordered list of resolution strategies applicable for the given target.
    static func availableStrategies(for target: AXTarget) -> [ResolutionStrategy] {
        var strategies: [ResolutionStrategy] = []

        // Strategy 1 requires both a non-empty path and a non-nil title.
        if !target.path.isEmpty, target.axTitle != nil {
            strategies.append(.pathAndTitle)
        }

        // Strategy 2 requires a non-nil title (path is optional).
        if target.axTitle != nil {
            strategies.append(.titleOnly)
        }

        // Strategy 3 requires a non-zero positionHint.
        if target.positionHint != .zero {
            strategies.append(.roleAndPosition)
        }

        // Strategy 4 is always available.
        strategies.append(.coordinate)

        return strategies
    }

    /// Converts a normalized positionHint (0–1, CG top-left) to an absolute screen point.
    static func absolutePosition(from positionHint: CGPoint, captureArea: CGRect) -> CGPoint {
        CGPoint(
            x: positionHint.x * captureArea.width + captureArea.origin.x,
            y: positionHint.y * captureArea.height + captureArea.origin.y
        )
    }

    /// Parses a path component that may carry an optional index suffix, e.g. "AXButton[2]".
    /// Returns a tuple of (role, index) where index is nil when no valid bracket suffix is present.
    static func parsePathComponent(_ component: String) -> (role: String, index: Int?) {
        guard let openBracket = component.lastIndex(of: "["),
              let closeBracket = component.lastIndex(of: "]"),
              closeBracket > openBracket,
              closeBracket == component.index(before: component.endIndex) else {
            return (component, nil)
        }

        let role = String(component[component.startIndex ..< openBracket])
        let indexStart = component.index(after: openBracket)
        let indexString = String(component[indexStart ..< closeBracket])
        let index = Int(indexString)
        return (role, index)
    }

    // MARK: - Fallback Chain (private)

    private func resolveSync(target: AXTarget, captureArea: CGRect) -> ResolvedTarget? {
        let strategies = AXTargetResolver.availableStrategies(for: target)

        for strategy in strategies {
            switch strategy {
            case .pathAndTitle:
                if let result = resolveByPathAndTitle(target) { return result }
            case .titleOnly:
                if let result = resolveByTitleOnly(target) { return result }
            case .roleAndPosition:
                if let result = resolveByRoleAndPosition(target, captureArea: captureArea) { return result }
            case .coordinate:
                return .coordinate(target.absoluteCoord)
            }
        }

        // Should not be reached because .coordinate is always appended, but provide safety fallback.
        return .coordinate(target.absoluteCoord)
    }

    // MARK: - Strategy 1: AX path + axTitle

    /// Walks the AX element tree along `target.path`, then verifies the leaf title.
    private func resolveByPathAndTitle(_ target: AXTarget) -> ResolvedTarget? {
        guard let axTitle = target.axTitle, !target.path.isEmpty else { return nil }

        guard let appElement = focusedAppElement() else { return nil }

        var current: AXUIElement = appElement

        for component in target.path {
            let (role, desiredIndex) = AXTargetResolver.parsePathComponent(component)
            guard let children = axChildren(of: current) else { return nil }

            let matching = children.filter { axRole(of: $0) == role }
            guard !matching.isEmpty else { return nil }

            let index = desiredIndex ?? 0
            guard index < matching.count else { return nil }

            current = matching[index]
        }

        // Verify the leaf element's title matches.
        guard axAttributeString(of: current, attribute: kAXTitleAttribute as String) == axTitle else {
            return nil
        }

        guard let center = elementCenter(current) else { return nil }
        return .element(current, center)
    }

    // MARK: - Strategy 2: axTitle BFS

    /// BFS from the focused app root, searching for the first element matching `target.axTitle`.
    private func resolveByTitleOnly(_ target: AXTarget) -> ResolvedTarget? {
        guard let axTitle = target.axTitle else { return nil }
        guard let appElement = focusedAppElement() else { return nil }

        let deadline = Date().addingTimeInterval(AXTargetResolver.timeoutPerStrategy)
        var queue: [(element: AXUIElement, depth: Int)] = [(appElement, 0)]

        while !queue.isEmpty {
            guard Date() < deadline else { return nil }

            let (element, depth) = queue.removeFirst()

            if axAttributeString(of: element, attribute: kAXTitleAttribute as String) == axTitle {
                guard let center = elementCenter(element) else { continue }
                return .element(element, center)
            }

            if depth < 10, let children = axChildren(of: element) {
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }

        return nil
    }

    // MARK: - Strategy 3: role + positionHint

    /// Queries the element at the converted absolute coordinate and checks the role matches.
    private func resolveByRoleAndPosition(_ target: AXTarget, captureArea: CGRect) -> ResolvedTarget? {
        let absPoint = AXTargetResolver.absolutePosition(from: target.positionHint, captureArea: captureArea)

        var elementRef: AXUIElement?
        let systemWide = AXUIElementCreateSystemWide()
        var rawElement: AXUIElement?

        let result = withUnsafeMutablePointer(to: &rawElement) { ptr -> AXError in
            // AXUIElementCopyElementAtPosition is not directly callable as a generic function;
            // use the C API binding through the pointer cast pattern.
            ptr.withMemoryRebound(to: Optional<CFTypeRef>.self, capacity: 1) { cfPtr in
                AXUIElementCopyElementAtPosition(systemWide, Float(absPoint.x), Float(absPoint.y), cfPtr as! UnsafeMutablePointer<AXUIElement?>)
            }
        }

        guard result == .success, let element = rawElement else { return nil }
        elementRef = element

        guard let found = elementRef,
              axRole(of: found) == target.role,
              let center = elementCenter(found) else { return nil }

        return .element(found, center)
    }

    // MARK: - AX Attribute Helpers

    private func focusedAppElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard result == .success, let app = focusedApp else { return nil }
        // swiftlint:disable:next force_cast
        return (app as! AXUIElement)
    }

    private func axChildren(of element: AXUIElement) -> [AXUIElement]? {
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard result == .success, let children = childrenRef as? [AXUIElement] else { return nil }
        return children
    }

    private func axRole(of element: AXUIElement) -> String? {
        axAttributeString(of: element, attribute: kAXRoleAttribute as String)
    }

    private func axAttributeString(of element: AXUIElement, attribute: String) -> String? {
        var valueRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef)
        guard result == .success, let value = valueRef as? String else { return nil }
        return value
    }

    private func elementCenter(_ element: AXUIElement) -> CGPoint? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        let posResult = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        let sizeResult = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        guard posResult == .success, sizeResult == .success,
              let posValue = positionRef, let sizeValue = sizeRef else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
    }
}
