import XCTest
import ApplicationServices
@testable import Screenize

final class StateValidatorTests: XCTestCase {

    // MARK: - isAppRunning

    /// Finder is always running on macOS
    func test_isAppRunning_finder_true() {
        XCTAssertTrue(StateValidator.isAppRunning(bundleId: "com.apple.finder"))
    }

    /// A non-existent app bundle ID → false
    func test_isAppRunning_fakeApp_false() {
        XCTAssertFalse(StateValidator.isAppRunning(bundleId: "com.fake.nonexistent.app"))
    }

    // MARK: - isElementEnabled

    /// Without a real element, the helper returns true (default assumption)
    ///
    /// We test the "attribute not accessible" code path by creating a system-wide
    /// element and querying kAXEnabledAttribute, which will fail (returns true by convention).
    func test_isElementEnabled_systemWideElement_returnsTrue() {
        // System-wide AXUIElement does not expose kAXEnabledAttribute,
        // so the guard fails and the function returns true.
        let systemWide = AXUIElementCreateSystemWide()
        let result = StateValidator.isElementEnabled(systemWide)
        XCTAssertTrue(result)
    }

    // MARK: - hasUnexpectedDialog

    /// hasUnexpectedDialog should return a Bool without crashing
    func test_hasUnexpectedDialog_doesNotCrash() {
        // We cannot control whether a dialog is present in the test environment,
        // but we verify the function executes without crashing.
        let _ = StateValidator.hasUnexpectedDialog()
    }

    // MARK: - validate (async)

    /// validate on a wait step with no element or app context → ready
    func test_validate_waitStep_noContext_ready() async {
        let validator = StateValidator()
        let waitStep = ScenarioStep(type: .wait, description: "wait", durationMs: 500)
        let result = await validator.validate(step: waitStep, resolvedElement: nil)
        XCTAssertEqual(result, .ready)
    }

    /// validate on activate_app step with Finder (always running) → ready
    func test_validate_activateApp_finderRunning_ready() async {
        let validator = StateValidator()
        let appStep = ScenarioStep(
            type: .activateApp,
            description: "activate Finder",
            durationMs: 100,
            app: "com.apple.finder"
        )
        let result = await validator.validate(step: appStep, resolvedElement: nil)
        XCTAssertEqual(result, .ready)
    }

    /// validate on activate_app step with fake bundle → appNotRunning
    func test_validate_activateApp_fakeApp_appNotRunning() async {
        let validator = StateValidator()
        let appStep = ScenarioStep(
            type: .activateApp,
            description: "activate fake app",
            durationMs: 100,
            app: "com.fake.nonexistent.app"
        )
        let result = await validator.validate(step: appStep, resolvedElement: nil)
        XCTAssertEqual(result, .appNotRunning("com.fake.nonexistent.app"))
    }
}
