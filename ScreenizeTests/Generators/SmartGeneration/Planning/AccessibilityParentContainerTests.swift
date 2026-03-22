import XCTest
@testable import Screenize

final class AccessibilityParentContainerTests: XCTestCase {

    private let screenBounds = CGSize(width: 1920, height: 1080)

    // MARK: - shouldTraverseForParent

    func test_shouldTraverse_selfSufficientRoles_returnsFalse() {
        let selfSufficientRoles = ["AXTextArea", "AXTextField", "AXTable", "AXScrollArea", "AXWebArea"]
        for role in selfSufficientRoles {
            let element = UIElementInfo(
                role: role, subrole: nil,
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                title: nil, isClickable: false, applicationName: nil
            )
            XCTAssertFalse(
                AccessibilityInspector.shouldTraverseForParent(element: element, screenBounds: screenBounds),
                "\(role) should be self-sufficient and not require parent traversal"
            )
        }
    }

    func test_shouldTraverse_smallElement_returnsTrue() {
        // 5% of screen area = 1920*1080*0.05 = 103,680 px
        // Element 100x50 = 5,000 px << 5% threshold
        let element = UIElementInfo(
            role: "AXGroup", subrole: nil,
            frame: CGRect(x: 500, y: 300, width: 100, height: 50),
            title: nil, isClickable: false, applicationName: nil
        )
        XCTAssertTrue(
            AccessibilityInspector.shouldTraverseForParent(element: element, screenBounds: screenBounds)
        )
    }

    func test_shouldTraverse_largeElement_returnsFalse() {
        // Element that covers > 5% of screen
        // 1920*1080*0.05 = 103,680. Element 400x300 = 120,000 > threshold
        let element = UIElementInfo(
            role: "AXGroup", subrole: nil,
            frame: CGRect(x: 500, y: 300, width: 400, height: 300),
            title: nil, isClickable: false, applicationName: nil
        )
        XCTAssertFalse(
            AccessibilityInspector.shouldTraverseForParent(element: element, screenBounds: screenBounds)
        )
    }

    func test_shouldTraverse_parentPreferredRoles_returnsTrue() {
        let preferredRoles = [
            "AXButton", "AXMenuItem", "AXCheckBox", "AXRadioButton",
            "AXStaticText", "AXImage", "AXPopUpButton"
        ]
        for role in preferredRoles {
            // Even with a larger frame, parent-preferred roles should return true
            let element = UIElementInfo(
                role: role, subrole: nil,
                frame: CGRect(x: 0, y: 0, width: 500, height: 300),
                title: nil, isClickable: true, applicationName: nil
            )
            XCTAssertTrue(
                AccessibilityInspector.shouldTraverseForParent(element: element, screenBounds: screenBounds),
                "\(role) should prefer parent context"
            )
        }
    }

    func test_shouldTraverse_unknownRole_largeElement_returnsFalse() {
        let element = UIElementInfo(
            role: "AXUnknown", subrole: nil,
            frame: CGRect(x: 0, y: 0, width: 500, height: 400),
            title: nil, isClickable: false, applicationName: nil
        )
        XCTAssertFalse(
            AccessibilityInspector.shouldTraverseForParent(element: element, screenBounds: screenBounds)
        )
    }

    func test_shouldTraverse_zeroScreenArea_returnsFalse() {
        let element = UIElementInfo(
            role: "AXButton", subrole: nil,
            frame: CGRect(x: 0, y: 0, width: 50, height: 30),
            title: nil, isClickable: true, applicationName: nil
        )
        // Parent-preferred role still returns true even with zero screen
        XCTAssertTrue(
            AccessibilityInspector.shouldTraverseForParent(
                element: element, screenBounds: CGSize(width: 0, height: 0)
            )
        )
    }

    // MARK: - isParentBoundsTooLarge

    func test_isParentBoundsTooLarge_smallBounds_returnsFalse() {
        let bounds = CGRect(x: 100, y: 50, width: 600, height: 60)
        XCTAssertFalse(
            AccessibilityInspector.isParentBoundsTooLarge(bounds, screenBounds: screenBounds)
        )
    }

    func test_isParentBoundsTooLarge_wideParent_returnsTrue() {
        // Width > 80% of screen (1920 * 0.8 = 1536)
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 60)
        XCTAssertTrue(
            AccessibilityInspector.isParentBoundsTooLarge(bounds, screenBounds: screenBounds)
        )
    }

    func test_isParentBoundsTooLarge_tallParent_returnsTrue() {
        // Height > 80% of screen (1080 * 0.8 = 864)
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 900)
        XCTAssertTrue(
            AccessibilityInspector.isParentBoundsTooLarge(bounds, screenBounds: screenBounds)
        )
    }

    func test_isParentBoundsTooLarge_exactThreshold_returnsFalse() {
        // Exactly 80% should NOT be too large (> not >=)
        let bounds = CGRect(
            x: 0, y: 0,
            width: screenBounds.width * 0.8,
            height: screenBounds.height * 0.8
        )
        XCTAssertFalse(
            AccessibilityInspector.isParentBoundsTooLarge(bounds, screenBounds: screenBounds)
        )
    }

    func test_isParentBoundsTooLarge_zeroScreenBounds_returnsTrue() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        XCTAssertTrue(
            AccessibilityInspector.isParentBoundsTooLarge(
                bounds, screenBounds: CGSize(width: 0, height: 0)
            )
        )
    }

    // MARK: - withParentBounds

    func test_withParentBounds_copiesAllFields() {
        let original = UIElementInfo(
            role: "AXButton", subrole: "AXCloseButton",
            frame: CGRect(x: 10, y: 20, width: 30, height: 40),
            title: "Close", isClickable: true, applicationName: "Finder"
        )
        let parentBounds = CGRect(x: 0, y: 0, width: 200, height: 60)
        let updated = original.withParentBounds(parentBounds)

        XCTAssertEqual(updated.role, original.role)
        XCTAssertEqual(updated.subrole, original.subrole)
        XCTAssertEqual(updated.frame, original.frame)
        XCTAssertEqual(updated.title, original.title)
        XCTAssertEqual(updated.isClickable, original.isClickable)
        XCTAssertEqual(updated.applicationName, original.applicationName)
        XCTAssertEqual(updated.parentContainerBounds, parentBounds)
    }

    func test_withParentBounds_nil_clearsExisting() {
        let original = UIElementInfo(
            role: "AXButton", subrole: nil,
            frame: CGRect(x: 10, y: 20, width: 30, height: 40),
            title: nil, isClickable: true, applicationName: nil,
            parentContainerBounds: CGRect(x: 0, y: 0, width: 200, height: 60)
        )
        let cleared = original.withParentBounds(nil)
        XCTAssertNil(cleared.parentContainerBounds)
    }
}
