import SwiftUI

/// Check for Updates menu item
struct CheckForUpdatesView: View {

    @ObservedObject var sparkleController: SparkleController

    var body: some View {
        Button(L10n.string("app.menu.check_for_updates", defaultValue: "Check for Updates...")) {
            sparkleController.checkForUpdates()
        }
        .disabled(!sparkleController.canCheckForUpdates)
    }
}
