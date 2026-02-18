import Foundation
import AppKit
import ApplicationServices

/// UI element info structure
struct UIElementInfo: Codable {
    let role: String              // e.g., "AXButton", "AXTextField", "AXLink"
    let subrole: String?          // e.g., "AXCloseButton", "AXSearchField"
    let frame: CGRect             // Element position/size on screen
    let title: String?            // Button text, etc.
    let isClickable: Bool         // Deduce clickability based on role
    let applicationName: String?  // Owning application name

    /// Area in pixels
    var area: CGFloat {
        frame.width * frame.height
    }

    /// List of roles considered clickable
    static let clickableRoles: Set<String> = [
        "AXButton",
        "AXLink",
        "AXCheckBox",
        "AXRadioButton",
        "AXMenuItem",
        "AXPopUpButton",
        "AXSlider",
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXDisclosureTriangle",
        "AXIncrementor",
        "AXCell",
        "AXColorWell",
        "AXSwitch",
        "AXSegmentedControl"
    ]

    /// List of roles that represent text input elements
    static let textInputRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField",
        "AXSecureTextField", "AXComboBox"
    ]
}

/// Accessibility permission status
enum AccessibilityPermissionStatus {
    case granted
    case denied
    case unknown
}

/// Accessibility Inspector - UI element information queries
final class AccessibilityInspector {

    // MARK: - Permission Check

    /// Check the accessibility permission status
    static var permissionStatus: AccessibilityPermissionStatus {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        return trusted ? .granted : .denied
    }

    /// Request accessibility permission (shows the system prompt)
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Determine if permission is granted
    static var hasPermission: Bool {
        permissionStatus == .granted
    }

    // MARK: - Element Inspection

    /// Inspect the UI element at a given screen point
    /// - Parameter screenPoint: Screen coordinate (top-left origin, CG coordinate space)
    /// - Returns: UI element info (nil when unavailable or permission denied)
    func elementAt(screenPoint: CGPoint) -> UIElementInfo? {
        guard Self.hasPermission else {
            return nil
        }

        // Create the system-wide AXUIElement
        let systemElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?

        // Get the element at the requested position (top-left origin, CG coordinate space)
        let result = AXUIElementCopyElementAtPosition(
            systemElement,
            Float(screenPoint.x),
            Float(screenPoint.y),
            &element
        )

        guard result == .success, let element = element else {
            return nil
        }

        return extractElementInfo(from: element)
    }

    /// Extract information from an AXUIElement
    private func extractElementInfo(from element: AXUIElement) -> UIElementInfo? {
        // Role
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? "Unknown"

        // Subrole
        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String

        // Frame (Position + Size)
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        var position = CGPoint.zero
        var size = CGSize.zero

        if let positionValue = positionRef {
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        }
        if let sizeValue = sizeRef {
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        }

        // Accessibility API returns coordinates with a top-left origin (CG coordinates)
        let frame = CGRect(origin: position, size: size)

        // Title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String

        // Application Name
        // Search parents to find the owning application
        var currentElement = element
        var applicationName: String?

        for _ in 0..<20 {  // Search up to 20 levels
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef {
                currentElement = (parent as! AXUIElement)

                var currentRole: CFTypeRef?
                AXUIElementCopyAttributeValue(currentElement, kAXRoleAttribute as CFString, &currentRole)

                if (currentRole as? String) == "AXApplication" {
                    var nameRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(currentElement, kAXTitleAttribute as CFString, &nameRef)
                    applicationName = nameRef as? String
                    break
                }
            } else {
                break
            }
        }

        // Determine whether the element is clickable
        let isClickable = UIElementInfo.clickableRoles.contains(role)

        return UIElementInfo(
            role: role,
            subrole: subrole,
            frame: frame,
            title: title,
            isClickable: isClickable,
            applicationName: applicationName
        )
    }
}

// MARK: - Caret Position

extension AccessibilityInspector {

    /// Get the caret (input cursor) bounds for a text element
    /// - Parameter textElement: AXUIElement representing a text input
    /// - Returns: Screen bounds of the caret (nil when unavailable)
    func getCaretBounds(from textElement: AXUIElement) -> CGRect? {
        // Retrieve the selected range (caret is the range start)
        var selectedRangeRef: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            textElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeRef
        )

        guard rangeResult == .success,
              let rangeValue = selectedRangeRef else {
            return nil
        }

        // Extract the CFRange from the AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            return nil
        }

        // Caret location (length 0 for caret, otherwise selection)
        // Cursor position is the start of the selection
        let caretLocation = range.location

        // Obtain screen coordinates for the caret
        // Use the AXBoundsForRange parameterized attribute
        // Convert CFRange to AXValue
        var mutableCaretRange = CFRange(location: caretLocation, length: 1)
        guard let rangeAXValue = AXValueCreate(.cfRange, &mutableCaretRange) else {
            return nil
        }

        var boundsRef: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            textElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeAXValue,
            &boundsRef
        )

        guard boundsResult == .success,
              let boundsValue = boundsRef else {
            return nil
        }

        // Extract CGRect from the AXValue
        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) else {
            return nil
        }

        return bounds
    }

    /// Get caret bounds for a text element at a screen point
    /// - Parameter screenPoint: Screen coordinate
    /// - Returns: Caret bounds (nil if not a text element or caret unavailable)
    func caretBoundsAt(screenPoint: CGPoint) -> CGRect? {
        guard Self.hasPermission else { return nil }

        let systemElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?

        let result = AXUIElementCopyElementAtPosition(
            systemElement,
            Float(screenPoint.x),
            Float(screenPoint.y),
            &element
        )

        guard result == .success, let element = element else {
            return nil
        }

        // Check the role to ensure it's a text input
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""

        let textInputRoles: Set<String> = [
            "AXTextField", "AXTextArea", "AXSearchField",
            "AXSecureTextField", "AXComboBox"
        ]

        guard textInputRoles.contains(role) else {
            return nil
        }

        return getCaretBounds(from: element)
    }

    /// Get caret bounds for the currently focused element
    /// - Returns: Caret bounds (nil when no focused text element)
    func focusedElementCaretBounds() -> CGRect? {
        guard Self.hasPermission else { return nil }

        let systemElement = AXUIElementCreateSystemWide()

        // Get the currently focused app
        var focusedAppRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedApplicationAttribute as CFString,
            &focusedAppRef
        )

        guard let focusedApp = focusedAppRef else { return nil }

        // Get the focused UI element
        var focusedElementRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            focusedApp as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard let focusedElement = focusedElementRef else { return nil }

        // Check the role
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            focusedElement as! AXUIElement,
            kAXRoleAttribute as CFString,
            &roleRef
        )
        let role = (roleRef as? String) ?? ""

        let textInputRoles: Set<String> = [
            "AXTextField", "AXTextArea", "AXSearchField",
            "AXSecureTextField", "AXComboBox"
        ]

        guard textInputRoles.contains(role) else {
            return nil
        }

        return getCaretBounds(from: focusedElement as! AXUIElement)
    }
}

// MARK: - Dynamic Zoom Calculation

extension UIElementInfo {
    /// Compute a dynamic zoom level based on element size
    /// - Parameters:
    ///   - screenArea: Total screen area
    ///   - minZoom: Minimum zoom level
    ///   - maxZoom: Maximum zoom level
    /// - Returns: Recommended zoom level
    func recommendedZoomLevel(
        screenArea: CGFloat,
        minZoom: CGFloat = 1.5,
        maxZoom: CGFloat = 3.0
    ) -> CGFloat {
        guard screenArea > 0 else { return minZoom }

        // Normalize by dividing the element area by the screen area
        let normalizedArea = area / screenArea

        // Define thresholds
        let smallThreshold: CGFloat = 0.005   // 0.5% - small element
        let largeThreshold: CGFloat = 0.05    // 5% - large element

        if normalizedArea <= smallThreshold {
            return maxZoom  // Small elements: maximum zoom
        } else if normalizedArea >= largeThreshold {
            return minZoom  // Large elements: minimum zoom
        } else {
            // Linear interpolation (smaller areas yield higher zoom)
            let t = (normalizedArea - smallThreshold) / (largeThreshold - smallThreshold)
            return maxZoom - (maxZoom - minZoom) * CGFloat(t)
        }
    }
}
