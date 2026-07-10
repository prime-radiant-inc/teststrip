import Foundation
import Sparkle

/// Owns the Sparkle updater for the app's lifetime. `startingUpdater: true`
/// wires up automatic background checks (governed by SUFeedURL /
/// SUPublicEDKey in Info.plist); `checkForUpdates()` is the manual entry
/// point from the Teststrip menu's "Check for Updates…" item.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
