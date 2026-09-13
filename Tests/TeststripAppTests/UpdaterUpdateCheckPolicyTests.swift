import XCTest
import TeststripApp

/// UpdateCheckPolicy gates Sparkle's automatic background update checks so
/// isolated/scenario launches do not pop a modal and wedge the AX tree. The
/// manual "Check for Updates…" entry point is independent of this decision.
final class UpdaterUpdateCheckPolicyTests: XCTestCase {
    func testAutomaticUpdateChecksEnabledByDefault() {
        let policy = UpdateCheckPolicy(environment: [:])

        XCTAssertTrue(policy.automaticUpdateChecksEnabled)
    }

    func testDisableEnvironmentKeySuppressesAutomaticUpdateChecks() {
        let policy = UpdateCheckPolicy(environment: [
            UpdateCheckPolicy.disableEnvironmentKey: "1"
        ])

        XCTAssertFalse(policy.automaticUpdateChecksEnabled)
    }

    func testDisableEnvironmentKeyAcceptsCommonTruthySpellings() {
        for raw in ["1", "true", "TRUE", "yes", "on", " on "] {
            let policy = UpdateCheckPolicy(environment: [
                UpdateCheckPolicy.disableEnvironmentKey: raw
            ])
            XCTAssertFalse(
                policy.automaticUpdateChecksEnabled,
                "expected \"\(raw)\" to disable automatic update checks"
            )
        }
    }

    func testDisableEnvironmentKeyIgnoresFalsyValues() {
        for raw in ["0", "false", "no", "off", "", "  "] {
            let policy = UpdateCheckPolicy(environment: [
                UpdateCheckPolicy.disableEnvironmentKey: raw
            ])
            XCTAssertTrue(
                policy.automaticUpdateChecksEnabled,
                "expected \"\(raw)\" to leave automatic update checks enabled"
            )
        }
    }

    func testIsolatedApplicationSupportMarkerSuppressesAutomaticUpdateChecks() {
        let policy = UpdateCheckPolicy(environment: [
            AppCatalog.applicationSupportDirectoryEnvironmentKey: "/tmp/Isolated Teststrip"
        ])

        XCTAssertFalse(policy.automaticUpdateChecksEnabled)
    }

    func testEmptyIsolatedApplicationSupportMarkerLeavesChecksEnabled() {
        let policy = UpdateCheckPolicy(environment: [
            AppCatalog.applicationSupportDirectoryEnvironmentKey: "   "
        ])

        XCTAssertTrue(policy.automaticUpdateChecksEnabled)
    }

    func testEitherGateSuppressesAutomaticUpdateChecks() {
        let policy = UpdateCheckPolicy(environment: [
            UpdateCheckPolicy.disableEnvironmentKey: "1",
            AppCatalog.applicationSupportDirectoryEnvironmentKey: "/tmp/Isolated Teststrip"
        ])

        XCTAssertFalse(policy.automaticUpdateChecksEnabled)
    }
}
