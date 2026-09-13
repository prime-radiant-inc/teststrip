import Foundation
import Sparkle

/// Decides whether Sparkle's automatic background update checks should run.
///
/// Isolated/scenario launches must not start the automatic updater: Sparkle's
/// update prompt is a modal window, and modals block the accessibility tree,
/// which wedges any AX-driven scenario run. Only the automatic
/// `startingUpdater:` wiring is gated here — `Updater.checkForUpdates()` (the
/// manual Teststrip ▸ Check for Updates… item) keeps working either way.
///
/// Automatic checks are disabled when either:
/// - `TESTSTRIP_DISABLE_UPDATE_CHECKS` is a truthy value (`1`/`true`/`yes`/`on`,
///   case-insensitive), for a scenario runner that wants to opt out explicitly, or
/// - the isolated launch marker `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY` is set
///   (see `AppCatalog.applicationSupportDirectoryEnvironmentKey`), so the
///   existing isolated/scenario launch path suppresses updates with no extra
///   configuration.
public struct UpdateCheckPolicy: Equatable, Sendable {
    public static let disableEnvironmentKey = "TESTSTRIP_DISABLE_UPDATE_CHECKS"

    public let automaticUpdateChecksEnabled: Bool

    public init(environment: [String: String]) {
        automaticUpdateChecksEnabled = Self.decide(environment: environment)
    }

    public init() {
        self.init(environment: ProcessInfo.processInfo.environment)
    }

    private static func decide(environment: [String: String]) -> Bool {
        if isTruthy(environment[disableEnvironmentKey]) {
            return false
        }
        if let isolated = environment[AppCatalog.applicationSupportDirectoryEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !isolated.isEmpty {
            return false
        }
        return true
    }

    private static func isTruthy(_ raw: String?) -> Bool {
        guard let raw else { return false }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}

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
        // Automatic background checks are suppressed for isolated/scenario
        // launches (see UpdateCheckPolicy); the manual check below still works.
        controller = SPUStandardUpdaterController(
            startingUpdater: UpdateCheckPolicy().automaticUpdateChecksEnabled,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
