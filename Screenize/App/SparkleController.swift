import Foundation
import Sparkle

/// Sparkle updater controller wrapper
/// ObservableObject for using Sparkle within SwiftUI
@MainActor
final class SparkleController: ObservableObject {

    // MARK: - Properties

    /// SPUStandardUpdaterController must persist for the app lifecycle
    private let updaterController: SPUStandardUpdaterController

    /// Indicates whether update checks are available (used for menu enabling)
    @Published var canCheckForUpdates: Bool = false

    /// SPUUpdater accessor (used by the settings view)
    var updater: SPUUpdater {
        updaterController.updater
    }

    // MARK: - Initialization

    init() {
        // startingUpdater: false - disable auto-start until appcast.xml and EdDSA keys are configured
        // Switch to true once distribution is ready
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Bind to the updater's availability state
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    // MARK: - Public Methods

    /// Manually check for updates (triggered from the menu)
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
