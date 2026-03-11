import XCTest
@testable import Screenize

final class GenerationSettingsViewTests: XCTestCase {

    func test_resetAllState_appDefaults_resetsOnlyAppSettings() {
        var appSettings = makeCustomizedSettings()
        let originalProjectSettings = makeCustomizedSettings()
        var projectSettings: GenerationSettings? = originalProjectSettings

        let notification: GenerationSettingsResetNotification = GenerationSettingsView.resetAllState(
            scope: GenerationSettingsView.SettingsScope.appDefaults,
            appSettings: &appSettings,
            projectSettings: &projectSettings
        )

        XCTAssertEqual(appSettings, .default)
        XCTAssertEqual(projectSettings, originalProjectSettings)
        XCTAssertEqual(notification, .none)
    }

    func test_resetAllState_thisProject_resetsOnlyProjectSettings() {
        let originalAppSettings = makeCustomizedSettings()
        var appSettings = originalAppSettings
        var projectSettings: GenerationSettings? = makeCustomizedSettings()

        let notification: GenerationSettingsResetNotification = GenerationSettingsView.resetAllState(
            scope: GenerationSettingsView.SettingsScope.thisProject,
            appSettings: &appSettings,
            projectSettings: &projectSettings
        )

        XCTAssertEqual(appSettings, originalAppSettings)
        XCTAssertEqual(projectSettings, .default)
        XCTAssertEqual(notification, .projectSettingsChanged(GenerationSettings.default))
    }

    // MARK: - Helpers

    private func makeCustomizedSettings() -> GenerationSettings {
        var settings = GenerationSettings.default
        settings.cameraMotion.positionResponse = 1.2
        settings.zoom.maxZoom = 2.4
        settings.intentClassification.navigatingMinClicks = 4
        settings.timing.tickRate = 30
        settings.cursorKeystroke.keystrokeEnabled = false
        return settings
    }
}
