import Foundation
import AppKit
import ApplicationServices

/// Validates pre-conditions for scenario step execution.
final class StateValidator {

    enum ValidationResult: Equatable {
        case ready
        case appNotRunning(String)      // bundleId
        case elementNotEnabled
        case unexpectedDialog(String)   // dialog role
        case timeout
    }

    /// Validate pre-conditions for step execution.
    ///
    /// Checks (in order):
    /// 1. If step has app context (`activate_app`), verify app is running.
    /// 2. If resolved element exists, verify `kAXEnabledAttribute`.
    /// 3. Check for unexpected dialogs (focused window role is AXSheet/AXDialog).
    /// Applies a 5-second timeout to the entire validation.
    func validate(step: ScenarioStep, resolvedElement: AXUIElement?) async -> ValidationResult {
        let result = await withTaskGroup(of: ValidationResult?.self) { group in
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return .timeout
            }
            group.addTask {
                return await self.performValidation(step: step, resolvedElement: resolvedElement)
            }

            // Return the first non-nil result
            for await value in group {
                if let result = value {
                    group.cancelAll()
                    return result
                }
            }
            return .timeout
        }
        return result
    }

    // MARK: - Private

    private func performValidation(step: ScenarioStep, resolvedElement: AXUIElement?) async -> ValidationResult {
        // 1. Check app is running for activate_app steps
        if step.type == .activateApp, let bundleId = step.app {
            if !StateValidator.isAppRunning(bundleId: bundleId) {
                return .appNotRunning(bundleId)
            }
        }

        // 2. Check element is enabled if we have a resolved element
        if let element = resolvedElement {
            if !StateValidator.isElementEnabled(element) {
                return .elementNotEnabled
            }
        }

        // 3. Check for unexpected dialogs
        if let dialogRole = StateValidator.unexpectedDialogRole() {
            return .unexpectedDialog(dialogRole)
        }

        return .ready
    }

    // MARK: - Static Helpers

    /// Check if an app with given bundleId is running and not terminated.
    static func isAppRunning(bundleId: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first(where: { !$0.isTerminated }) != nil
    }

    /// Returns the role string if a focused window is an unexpected dialog (AXSheet or AXDialog), or nil.
    static func unexpectedDialogRole() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp) == .success,
              let appElement = focusedApp else {
            return nil
        }

        var focusedWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            // swiftlint:disable:next force_cast
            appElement as! AXUIElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        ) == .success, let window = focusedWindow else {
            return nil
        }

        var roleRef: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return nil
        }

        let unexpectedRoles: Set<String> = ["AXSheet", "AXDialog"]
        return unexpectedRoles.contains(role) ? role : nil
    }

    /// Check if a focused window is an unexpected dialog (AXSheet or AXDialog).
    static func hasUnexpectedDialog() -> Bool {
        unexpectedDialogRole() != nil
    }

    /// Check if AX element is enabled.
    static func isElementEnabled(_ element: AXUIElement) -> Bool {
        var enabledRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabledRef) == .success else {
            return true // Assume enabled if attribute is not accessible
        }
        return (enabledRef as? Bool) ?? true
    }
}
