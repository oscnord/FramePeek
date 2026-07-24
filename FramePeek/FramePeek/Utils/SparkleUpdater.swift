#if SPARKLE_UPDATES
import SwiftUI
import Sparkle

/// Auto-update support for the GitHub distribution channel.
/// The App Store target compiles without SPARKLE_UPDATES (and without the
/// Sparkle framework); its updates come through the App Store.
@MainActor
final class SparkleUpdater {
    static let shared = SparkleUpdater()

    private let controller: SPUStandardUpdaterController

    private init() {
        // The unit test host launches the full app; Sparkle's first-run
        // permission prompt would hang a headless test run
        let isRunningTests = NSClassFromString("XCTestCase") != nil

        controller = SPUStandardUpdaterController(
            startingUpdater: !isRunningTests,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                SparkleUpdater.shared.checkForUpdates()
            }
        }
    }
}
#else
import SwiftUI

/// App Store channel: updates are delivered by the App Store, no menu item
struct CheckForUpdatesCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) { }
    }
}
#endif
