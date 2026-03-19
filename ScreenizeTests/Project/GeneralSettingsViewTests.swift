import XCTest
@testable import Screenize

final class GeneralSettingsViewTests: XCTestCase {

    func test_languagePickerOptions_putSystemDefaultFirst() {
        let options = GeneralSettingsView.languagePickerOptions(
            supportedLanguages: [.systemDefault, .english, .korean]
        )

        XCTAssertEqual(options.map(\.language), [.systemDefault, .english, .korean])
        XCTAssertEqual(
            options.map(\.title),
            [L10n.string("common.system_default", defaultValue: "System Default"), "English", "한국어"]
        )
    }
}
