import XCTest
import TeststripCore
@testable import TeststripApp

// The burst stack builder's capture-time window used to be a hardcoded 2s
// constant (`AppModel.candidateStackMaximumCaptureGap`). It's now a
// persisted preference (`burstIntervalSeconds`, Settings' "Burst interval")
// threaded through every live stack-building path via `AppModel.stackBuilder()`.
final class BurstIntervalPreferenceTests: XCTestCase {
    func testBurstIntervalDefaultsToAssetStackBuilderDefault() {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])

        XCTAssertEqual(model.burstIntervalSeconds, AssetStackBuilder.defaultMaximumCaptureGap)
    }

    func testAllCullingStacksHonorsConfiguredBurstInterval() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(id: "first", path: "/Photos/Job/first.cr2", capturedAt: capturedAt)
        let second = makeAsset(id: "second", path: "/Photos/Job/second.cr2", capturedAt: capturedAt.addingTimeInterval(5))
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])

        model.burstIntervalSeconds = 2
        XCTAssertEqual(
            model.allCullingStacks(for: [first, second]).map(\.assetIDs),
            [[first.id], [second.id]]
        )

        model.burstIntervalSeconds = 10
        let stacked = model.allCullingStacks(for: [first, second])
        XCTAssertEqual(stacked.map(\.assetIDs), [[first.id, second.id]])
        XCTAssertEqual(stacked.first?.rationale, "Same folder, captured within 10s")
    }

    // The rail reads its "captured within Ns" rationale straight off
    // `selectedCullingStackScope`, the same scope `CullingStackRailPresentation`
    // is built from — so this is the rail's actual live text, not a proxy.
    func testSelectedCullingStackScopeRationaleReflectsConfiguredBurstInterval() {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(id: "first", path: "/Photos/Job/first.cr2", capturedAt: capturedAt)
        let second = makeAsset(id: "second", path: "/Photos/Job/second.cr2", capturedAt: capturedAt.addingTimeInterval(5))
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])
        model.burstIntervalSeconds = 10
        model.select(second.id)

        XCTAssertEqual(model.selectedCullingStackScope?.rationaleText, "Same folder, captured within 10s")
    }

    private func makeAsset(id: String, path: String, capturedAt: Date) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: capturedAt),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                capturedAt: capturedAt,
                provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
            )
        )
    }
}
