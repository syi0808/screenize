import SwiftUI

/// Check for Updates menu item
struct CheckForUpdatesView: View {

    @ObservedObject var sparkleController: SparkleController

    var body: some View {
        Button("Check for Updates...") {
            sparkleController.checkForUpdates()
        }
        .disabled(!sparkleController.canCheckForUpdates)
    }
}
