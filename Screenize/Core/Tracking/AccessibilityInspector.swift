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
    let parentContainerBounds: CGRect?  // Parent group/toolbar bounds for small elements

    // Custom init providing default nil for parentContainerBounds (backward compatible)
    init(
        role: String,
        subrole: String?,
        frame: CGRect,
        title: String?,
        isClickable: Bool,
        applicationName: String?,
        parentContainerBounds: CGRect? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.title = title
        self.isClickable = isClickable
        self.applicationName = applicationName
        self.parentContainerBounds = parentContainerBounds
    }

    // Backward-compatible Codable: decode existing JSON missing parentContainerBounds
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        subrole = try container.decodeIfPresent(String.self, forKey: .subrole)
        frame = try container.decode(CGRect.self, forKey: .frame)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        isClickable = try container.decode(Bool.self, forKey: .isClickable)
        applicationName = try container.decodeIfPresent(String.self, forKey: .applicationName)
        parentContainerBounds = try container.decodeIfPresent(CGRect.self, forKey: .parentContainerBounds)
    }

    private enum CodingKeys: String, CodingKey {
        case role, subrole, frame, title, isClickable, applicationName, parentContainerBounds
    }

    /// Return a copy with parentContainerBounds set
    func withParentBounds(_ bounds: CGRect?) -> UIElementInfo {
        UIElementInfo(
            role: role, subrole: subrole, frame: frame,
            title: title, isClickable: isClickable,
            applicationName: applicationName,
            parentContainerBounds: bounds
        )
    }

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

        guard var info = extractElementInfo(from: element) else {
            return nil
        }

        // Resolve parent container bounds for small or parent-preferred elements
        let screenSize = NSScreen.main?.frame.size ?? .zero
        if screenSize.width > 0,
           Self.shouldTraverseForParent(element: info, screenBounds: screenSize) {
            let parentBounds = Self.findParentContainer(
                for: element, screenBounds: screenSize
            )
            info = info.withParentBounds(parentBounds)
        }

        return info
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

        if let positionValue = positionRef,
           CFGetTypeID(positionValue) == AXValueGetTypeID() {
            // swiftlint:disable:next force_cast
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        }
        if let sizeValue = sizeRef,
           CFGetTypeID(sizeValue) == AXValueGetTypeID() {
            // swiftlint:disable:next force_cast
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
               let parent = parentRef,
               CFGetTypeID(parent) == AXUIElementGetTypeID() {
                // swiftlint:disable:next force_cast
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

// MARK: - Parent Container Traversal

extension AccessibilityInspector {

    /// Roles that are self-sufficient containers — no need to look for a parent
    private static let selfSufficientRoles: Set<String> = [
        "AXTextArea", "AXTextField", "AXTable", "AXScrollArea", "AXWebArea"
    ]

    /// Roles that typically live inside a toolbar/group and benefit from parent context
    private static let parentPreferredRoles: Set<String> = [
        "AXButton", "AXMenuItem", "AXCheckBox", "AXRadioButton",
        "AXStaticText", "AXImage", "AXPopUpButton"
    ]

    /// Determine whether we should traverse the AX hierarchy to find a parent container.
    /// - Parameters:
    ///   - element: The focused UI element info
    ///   - screenBounds: The screen size in pixels
    /// - Returns: true if parent traversal is recommended
    static func shouldTraverseForParent(
        element: UIElementInfo, screenBounds: CGSize
    ) -> Bool {
        // Self-sufficient roles never need parent context
        if selfSufficientRoles.contains(element.role) { return false }

        // Small elements (< 5% of screen area) always benefit from parent context
        let screenArea = screenBounds.width * screenBounds.height
        if screenArea > 0 && element.area / screenArea < 0.05 { return true }

        // Parent-preferred roles benefit from parent context regardless of size
        if parentPreferredRoles.contains(element.role) { return true }

        return false
    }

    /// Check if the given bounds are too large to be a useful parent container.
    /// Returns true if width > 80% of screen OR height > 80% of screen.
    static func isParentBoundsTooLarge(
        _ bounds: CGRect, screenBounds: CGSize
    ) -> Bool {
        guard screenBounds.width > 0, screenBounds.height > 0 else { return true }
        return bounds.width > screenBounds.width * 0.8
            || bounds.height > screenBounds.height * 0.8
    }

    /// Walk up the AX hierarchy to find a suitable parent container.
    /// - Parameters:
    ///   - axElement: The starting AXUIElement
    ///   - screenBounds: The screen size in pixels
    ///   - maxDepth: Maximum levels to traverse (default 3)
    /// - Returns: Parent container bounds in screen coordinates, or nil
    static func findParentContainer(
        for axElement: AXUIElement,
        screenBounds: CGSize,
        maxDepth: Int = 3
    ) -> CGRect? {
        var current = axElement

        for _ in 0..<maxDepth {
            // Walk up to parent
            var parentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current, kAXParentAttribute as CFString, &parentRef
            ) == .success,
                  let parent = parentRef,
                  CFGetTypeID(parent) == AXUIElementGetTypeID() else {
                break
            }
            // swiftlint:disable:next force_cast
            let parentElement = parent as! AXUIElement

            // Get parent position + size
            var posRef: CFTypeRef?
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(
                parentElement, kAXPositionAttribute as CFString, &posRef
            )
            AXUIElementCopyAttributeValue(
                parentElement, kAXSizeAttribute as CFString, &sizeRef
            )

            var position = CGPoint.zero
            var size = CGSize.zero
            if let posVal = posRef, CFGetTypeID(posVal) == AXValueGetTypeID() {
                // swiftlint:disable:next force_cast
                AXValueGetValue(posVal as! AXValue, .cgPoint, &position)
            }
            if let sizeVal = sizeRef, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
                // swiftlint:disable:next force_cast
                AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
            }

            let bounds = CGRect(origin: position, size: size)

            // Skip zero-size parents
            guard bounds.width > 0, bounds.height > 0 else {
                current = parentElement
                continue
            }

            // If bounds are reasonable (not too large), return them
            if !isParentBoundsTooLarge(bounds, screenBounds: screenBounds) {
                return bounds
            }

            current = parentElement
        }

        return nil
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
              let rangeValue = selectedRangeRef,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        // Extract the CFRange from the AXValue
        var range = CFRange(location: 0, length: 0)
        // swiftlint:disable:next force_cast
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
              let boundsValue = boundsRef,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        // Extract CGRect from the AXValue
        var bounds = CGRect.zero
        // swiftlint:disable:next force_cast
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

        guard let focusedApp = focusedAppRef,
              CFGetTypeID(focusedApp) == AXUIElementGetTypeID() else { return nil }

        // swiftlint:disable:next force_cast
        let focusedAppElement = focusedApp as! AXUIElement

        // Get the focused UI element
        var focusedElementRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            focusedAppElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard let focusedElement = focusedElementRef,
              CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else { return nil }

        // swiftlint:disable:next force_cast
        let focusedUIElement = focusedElement as! AXUIElement

        // Check the role
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(
            focusedUIElement,
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

        return getCaretBounds(from: focusedUIElement)
    }
}

// MARK: - Scenario Element Info

/// Extended element info for scenario recording, including AX path and extra properties
struct ScenarioElementInfo {
    let element: UIElementInfo
    let path: [String]          // e.g., ["AXWindow", "AXSplitGroup", "AXOutline"]
    let axValue: String?
    let axDescription: String?
}

// MARK: - Scenario Inspection

extension AccessibilityInspector {

    /// Traverse the parent chain from an element up to AXWindow, collecting role strings.
    /// Returns an array like ["AXWindow", "AXSplitGroup", "AXOutline"] (root to leaf).
    /// Appends a 0-based index for siblings with the same role (e.g., "AXButton[2]").
    /// Max depth: 15.
    func parentPath(for element: AXUIElement) -> [String] {
        var roles: [String] = []  // Collected bottom-up (leaf to root), reversed at the end
        var currentElement = element
        let maxDepth = 15

        for _ in 0..<maxDepth {
            // Get the role of the current element
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(currentElement, kAXRoleAttribute as CFString, &roleRef)
            let role = (roleRef as? String) ?? "Unknown"

            // Compute sibling disambiguation index (if parent has multiple children with same role)
            var disambiguatedRole = role
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef,
               CFGetTypeID(parent) == AXUIElementGetTypeID() {
                // swiftlint:disable:next force_cast
                let parentElement = parent as! AXUIElement

                // Fetch siblings (parent's children)
                var childrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(parentElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
                   let childrenArray = childrenRef as? [AXUIElement] {
                    // Filter to siblings sharing the same role
                    let sameRoleSiblings = childrenArray.filter { sibling in
                        var siblingRoleRef: CFTypeRef?
                        AXUIElementCopyAttributeValue(sibling, kAXRoleAttribute as CFString, &siblingRoleRef)
                        return (siblingRoleRef as? String) == role
                    }

                    // Only append index when there are multiple siblings with the same role
                    if sameRoleSiblings.count > 1 {
                        // Find this element's position among same-role siblings
                        let index = sameRoleSiblings.firstIndex { sibling in
                            CFEqual(sibling, currentElement)
                        } ?? 0
                        disambiguatedRole = "\(role)[\(index)]"
                    }
                }
            }

            roles.append(disambiguatedRole)

            // Stop at AXWindow — it is the root of a window hierarchy
            if role == "AXWindow" {
                break
            }

            // Walk up to parent
            var nextParentRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(currentElement, kAXParentAttribute as CFString, &nextParentRef) == .success,
                  let nextParent = nextParentRef,
                  CFGetTypeID(nextParent) == AXUIElementGetTypeID() else {
                break
            }
            // swiftlint:disable:next force_cast
            currentElement = nextParent as! AXUIElement
        }

        // Roles were collected leaf-to-root; reverse to get root-to-leaf order
        return roles.reversed()
    }

    /// Get element info with a full AX path and extra properties for scenario recording.
    /// - Parameter screenPoint: Screen coordinate (top-left origin, CG coordinate space)
    /// - Returns: ScenarioElementInfo (nil when unavailable or permission denied)
    func scenarioElementAt(screenPoint: CGPoint) -> ScenarioElementInfo? {
        guard Self.hasPermission else {
            return nil
        }

        let systemElement = AXUIElementCreateSystemWide()
        var axElement: AXUIElement?

        let result = AXUIElementCopyElementAtPosition(
            systemElement,
            Float(screenPoint.x),
            Float(screenPoint.y),
            &axElement
        )

        guard result == .success, let axElement = axElement else {
            return nil
        }

        guard let elementInfo = extractElementInfo(from: axElement) else {
            return nil
        }

        // AXValue — plain string value of the element (e.g., checkbox state, text content)
        var axValueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &axValueRef)
        let axValue = axValueRef as? String

        // AXDescription — accessible description of the element
        var axDescriptionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXDescriptionAttribute as CFString, &axDescriptionRef)
        let axDescription = axDescriptionRef as? String

        let path = parentPath(for: axElement)

        return ScenarioElementInfo(
            element: elementInfo,
            path: path,
            axValue: axValue,
            axDescription: axDescription
        )
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
