import Foundation
import CoreGraphics
import ApplicationServices
import AppKit

/// Orchestrates per-step execution using AXTargetResolver, EventInjector, StateValidator,
/// PathGenerator, and TimingController.
final class StepExecutor {
    let targetResolver = AXTargetResolver()
    let eventInjector = EventInjector()
    let stateValidator = StateValidator()

    enum StepResult {
        case success
        case error(String)
        case cancelled
    }

    /// Execute a single scenario step.
    func execute(
        step: ScenarioStep,
        previousPosition: CGPoint?,
        steps: [ScenarioStep],
        stepIndex: Int,
        captureArea: CGRect,
        coordinateOffset: CGPoint = .zero,
        isCancelled: @escaping () -> Bool
    ) async -> StepResult {
        guard !isCancelled() else { return .cancelled }

        switch step.type {
        case .mouseMove:
            return await executeMouseMove(
                step: step,
                from: previousPosition ?? .zero,
                steps: steps,
                stepIndex: stepIndex,
                captureArea: captureArea,
                coordinateOffset: coordinateOffset,
                isCancelled: isCancelled
            )
        case .click, .doubleClick, .rightClick:
            return await executeClick(
                step: step, captureArea: captureArea,
                coordinateOffset: coordinateOffset, isCancelled: isCancelled
            )
        case .keyboard:
            return await executeKeyboard(step: step)
        case .typeText:
            return await executeTypeText(step: step, isCancelled: isCancelled)
        case .scroll:
            return await executeScroll(
                step: step, captureArea: captureArea, coordinateOffset: coordinateOffset
            )
        case .activateApp:
            return await executeActivateApp(step: step)
        case .mouseDown:
            return await executeMouseDown(
                step: step, captureArea: captureArea, coordinateOffset: coordinateOffset
            )
        case .mouseUp:
            return await executeMouseUp(
                step: step, captureArea: captureArea, coordinateOffset: coordinateOffset
            )
        case .wait:
            await TimingController.delay(ms: step.durationMs)
            return .success
        }
    }

    func cancel() {
        eventInjector.cancelPathInjection()
    }

    // MARK: - Mouse Move

    private func executeMouseMove(
        step: ScenarioStep,
        from startPosition: CGPoint,
        steps: [ScenarioStep],
        stepIndex: Int,
        captureArea: CGRect,
        coordinateOffset: CGPoint,
        isCancelled: @escaping () -> Bool
    ) async -> StepResult {
        // Determine destination: use next step's target positionHint if available,
        // otherwise fall back to this step's own target positionHint.
        let rawDestination: CGPoint
        if let nextTarget = nextStepTarget(steps: steps, afterIndex: stepIndex) {
            rawDestination = absolutePosition(from: nextTarget.positionHint, captureArea: captureArea)
        } else if let target = step.target {
            rawDestination = absolutePosition(from: target.positionHint, captureArea: captureArea)
        } else {
            return .success
        }
        let destination = CGPoint(
            x: rawDestination.x + coordinateOffset.x,
            y: rawDestination.y + coordinateOffset.y
        )

        let points = PathGenerator.generatePath(
            from: startPosition,
            to: destination,
            path: step.path,
            durationMs: step.durationMs,
            stepId: step.id
        )

        guard !isCancelled() else { return .cancelled }
        await eventInjector.injectPath(points)
        return .success
    }

    // MARK: - Click / DoubleClick / RightClick

    private func executeClick(
        step: ScenarioStep,
        captureArea: CGRect,
        coordinateOffset: CGPoint,
        isCancelled: @escaping () -> Bool
    ) async -> StepResult {
        guard let target = step.target else {
            return .error("Click step missing target")
        }

        let resolved = await targetResolver.resolve(
            target: target, captureArea: captureArea, coordinateOffset: coordinateOffset
        )
        guard let resolved = resolved else {
            return .error("Failed to resolve target for click")
        }

        // Extract element and position
        let (element, position) = extractElementAndPosition(from: resolved)

        // Validate state
        let validation = await stateValidator.validate(step: step, resolvedElement: element)
        guard validation == .ready else {
            return .error(validationErrorMessage(validation))
        }

        guard !isCancelled() else { return .cancelled }

        // Move cursor to position first
        if let moveEvent = EventInjector.createMouseMoveEvent(to: position) {
            eventInjector.injectEvent(moveEvent)
        }

        // Small delay for cursor settle
        await TimingController.delay(ms: 20)

        switch step.type {
        case .click:
            await eventInjector.injectClick(at: position)
        case .doubleClick:
            await eventInjector.injectDoubleClick(at: position)
        case .rightClick:
            await eventInjector.injectRightClick(at: position)
        default:
            break
        }

        return .success
    }

    // MARK: - Keyboard

    private func executeKeyboard(step: ScenarioStep) async -> StepResult {
        guard let keyCombo = step.keyCombo else {
            return .error("Keyboard step missing keyCombo")
        }
        await eventInjector.injectKeyCombo(keyCombo)
        return .success
    }

    // MARK: - Type Text

    private func executeTypeText(
        step: ScenarioStep,
        isCancelled: @escaping () -> Bool
    ) async -> StepResult {
        guard let content = step.content else {
            return .error("Type text step missing content")
        }
        guard !isCancelled() else { return .cancelled }

        let speedMs = step.typingSpeedMs ?? 50
        await eventInjector.injectTypeText(content, speedMs: speedMs)
        return .success
    }

    // MARK: - Scroll

    private func executeScroll(
        step: ScenarioStep,
        captureArea: CGRect,
        coordinateOffset: CGPoint
    ) async -> StepResult {
        // Move cursor to target position if available
        if let target = step.target {
            if let resolved = await targetResolver.resolve(
                target: target, captureArea: captureArea, coordinateOffset: coordinateOffset
            ) {
                let (_, position) = extractElementAndPosition(from: resolved)
                if let moveEvent = EventInjector.createMouseMoveEvent(to: position) {
                    eventInjector.injectEvent(moveEvent)
                }
                await TimingController.delay(ms: 20)
            }
        }

        let amount = step.amount ?? 100
        let direction = step.direction ?? .down

        let deltaX: Int
        let deltaY: Int
        switch direction {
        case .up:    deltaX = 0; deltaY = -amount
        case .down:  deltaX = 0; deltaY = amount
        case .left:  deltaX = -amount; deltaY = 0
        case .right: deltaX = amount; deltaY = 0
        }

        await eventInjector.injectScroll(deltaX: deltaX, deltaY: deltaY)
        return .success
    }

    // MARK: - Activate App

    private func executeActivateApp(step: ScenarioStep) async -> StepResult {
        guard let bundleId = step.app else {
            return .error("Activate app step missing app bundle ID")
        }

        let validation = await stateValidator.validate(step: step, resolvedElement: nil)
        guard validation == .ready else {
            return .error(validationErrorMessage(validation))
        }

        // Activate with polling verification (up to 1 second)
        for _ in 0..<10 {
            await eventInjector.injectActivateApp(bundleId: bundleId)
            await TimingController.delay(ms: 100)
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId {
                break
            }
        }
        return .success
    }

    // MARK: - Mouse Down / Up

    private func executeMouseDown(
        step: ScenarioStep,
        captureArea: CGRect,
        coordinateOffset: CGPoint
    ) async -> StepResult {
        guard let target = step.target else {
            return .error("Mouse down step missing target")
        }

        let resolved = await targetResolver.resolve(
            target: target, captureArea: captureArea, coordinateOffset: coordinateOffset
        )
        guard let resolved = resolved else {
            return .error("Failed to resolve target for mouse down")
        }

        let (element, position) = extractElementAndPosition(from: resolved)

        let validation = await stateValidator.validate(step: step, resolvedElement: element)
        guard validation == .ready else {
            return .error(validationErrorMessage(validation))
        }

        if let moveEvent = EventInjector.createMouseMoveEvent(to: position) {
            eventInjector.injectEvent(moveEvent)
        }
        await TimingController.delay(ms: 20)
        await eventInjector.injectMouseDown(at: position)
        return .success
    }

    private func executeMouseUp(
        step: ScenarioStep,
        captureArea: CGRect,
        coordinateOffset: CGPoint
    ) async -> StepResult {
        guard let target = step.target else {
            return .error("Mouse up step missing target")
        }

        let resolved = await targetResolver.resolve(
            target: target, captureArea: captureArea, coordinateOffset: coordinateOffset
        )
        guard let resolved = resolved else {
            return .error("Failed to resolve target for mouse up")
        }

        let (_, position) = extractElementAndPosition(from: resolved)

        if let moveEvent = EventInjector.createMouseMoveEvent(to: position) {
            eventInjector.injectEvent(moveEvent)
        }
        await TimingController.delay(ms: 20)
        await eventInjector.injectMouseUp(at: position)
        return .success
    }

    // MARK: - Helpers

    /// Convert normalized positionHint (0-1, CG top-left) to absolute screen coordinates.
    private func absolutePosition(from hint: CGPoint, captureArea: CGRect) -> CGPoint {
        AXTargetResolver.absolutePosition(from: hint, captureArea: captureArea)
    }

    /// Extract optional AXUIElement and position from a resolved target.
    private func extractElementAndPosition(
        from resolved: AXTargetResolver.ResolvedTarget
    ) -> (AXUIElement?, CGPoint) {
        switch resolved {
        case .element(let element, let point):
            return (element, point)
        case .coordinate(let point):
            return (nil, point)
        }
    }

    /// Look ahead in steps to find the next step that has a target with a positionHint.
    private func nextStepTarget(steps: [ScenarioStep], afterIndex index: Int) -> AXTarget? {
        let nextIndex = index + 1
        guard nextIndex < steps.count else { return nil }
        return steps[nextIndex].target
    }

    /// Convert a StateValidator.ValidationResult to an error message string.
    private func validationErrorMessage(_ result: StateValidator.ValidationResult) -> String {
        switch result {
        case .ready:
            return ""
        case .appNotRunning(let bundleId):
            return "Application not running: \(bundleId)"
        case .elementNotEnabled:
            return "Target element is disabled"
        case .unexpectedDialog(let role):
            return "Unexpected dialog detected: \(role)"
        case .timeout:
            return "Validation timed out"
        }
    }
}
