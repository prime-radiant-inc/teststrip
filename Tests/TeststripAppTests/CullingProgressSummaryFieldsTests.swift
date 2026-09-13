import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-D Task 5: CullingProgressSummary gains loud accounting fields
// (viewedCount, skippedCount, neverViewedCount, awaitingReviewCount,
// hiddenByLensCount) for the scope line's prominent coverage readout.
final class CullingProgressSummaryFieldsTests: XCTestCase {
    func testProgressSummaryPopulatesLoudAccountingFields() throws {
        // 5 assets: 2 decided (pick + reject), 1 with tentative AI flag,
        // 2 undecided. The tracker records viewed/skipped as we navigate.
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "r1", flag: .reject),
            Self.asset(id: "ai1", flag: .pick, tentative: true),
            Self.asset(id: "u1"),
            Self.asset(id: "u2"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "progress-summary",
            assets: assets
        )
        try model.beginCullingSession(named: "Test")

        let summary = model.cullingProgressSummary

        // viewedCount: the tracker records the first selected asset on
        // startCullRunTracking, so at least 1.
        XCTAssertEqual(summary.viewedCount, 1)
        // neverViewedCount: 5 total - 1 viewed = 4
        let expectedNeverViewed = model.totalAssetCount - 1
        XCTAssertEqual(summary.neverViewedCount, expectedNeverViewed)
        // awaitingReviewCount: one asset with tentative AI flag
        XCTAssertEqual(summary.awaitingReviewCount, 1)
        // hiddenByLensCount: 0 when scope is .all (default)
        XCTAssertEqual(summary.hiddenByLensCount, 0)
        // skippedCount starts at 0 (no skips yet)
        XCTAssertEqual(summary.skippedCount, 0)
    }

    func testTentativeAIFlagNeverCountsAsDecided() throws {
        // A tentative AI pick counts as awaiting review, not as a confirmed
        // pick. The provenance invariant: confirmedProjection.flag is nil for
        // tentative flags, so they never drive "decided" math.
        let assets = [
            Self.asset(id: "ai1", flag: .pick, tentative: true),
            Self.asset(id: "u1"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "progress-tentative",
            assets: assets
        )
        try model.beginCullingSession(named: "Test")

        let summary = model.cullingProgressSummary

        // The tentative pick is not a confirmed pick
        XCTAssertEqual(summary.pickCount, 0)
        // It is awaiting review
        XCTAssertEqual(summary.awaitingReviewCount, 1)
    }

    func testHiddenByLensCountReflectsScope() throws {
        // 4 assets: 1 pick, 1 reject, 2 undecided. Scoping to .unrated hides
        // the decided assets.
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "r1", flag: .reject),
            Self.asset(id: "u1"),
            Self.asset(id: "u2"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "progress-hidden",
            assets: assets
        )
        try model.beginCullingSession(named: "Test")
        model.cycleCullScope()

        let summary = model.cullingProgressSummary

        // .unrated shows only undecided: 2 of 4 → hidden 2
        XCTAssertEqual(summary.hiddenByLensCount, 2)
    }

    func testReviewedCountIsViewedPlusSkipped() throws {
        let assets = (0..<4).map { Self.asset(id: "rev-\($0)") }
        let (model, _) = try makeModelWithCatalogAssets(
            named: "progress-reviewed",
            assets: assets
        )
        try model.beginCullingSession(named: "Test")
        // startCullRunTracking records the landing frame as viewed (1 viewed).
        // Two .nextPhoto skips on undecided frames add 2 skipped + 2 viewed.
        try model.applyCullingShortcut(.nextPhoto)
        try model.applyCullingShortcut(.nextPhoto)

        let summary = model.cullingProgressSummary

        XCTAssertEqual(
            summary.reviewedCount,
            summary.viewedCount,
            "reviewedCount must equal viewedCount (skipped frames are already viewed)"
        )
        XCTAssertEqual(summary.viewedCount, 3)
        XCTAssertEqual(summary.skippedCount, 2)
    }

    // MARK: - Scope-filtered counts (the Cull HUD's ✓/✕/left cluster)

    /// 4 assets: 1 confirmed pick, 1 confirmed reject, 1 AI-tentative pick
    /// (undecided), 1 unflagged. Scope cycle order is all → unrated → picks →
    /// rejects, so `cycleCullScope()` advances one step.
    private func makeScopedCountsModel() throws -> AppModel {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "r1", flag: .reject),
            Self.asset(id: "ai1", flag: .pick, tentative: true),
            Self.asset(id: "u1"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "progress-scoped-counts",
            assets: assets
        )
        try model.beginCullingSession(named: "Test")
        return model
    }

    func testScopedCountsMatchTheWholeSessionAtAllScope() throws {
        let model = try makeScopedCountsModel()

        let counts = model.cullingProgressSummary.scopedCounts

        XCTAssertEqual(counts.totalCount, 4)
        XCTAssertEqual(counts.pickCount, 1)
        XCTAssertEqual(counts.rejectCount, 1)
        XCTAssertEqual(counts.undecidedCount, 2)
    }

    func testScopedCountsShrinkToThePicksScope() throws {
        let model = try makeScopedCountsModel()
        model.cycleCullScope() // .all → .unrated
        model.cycleCullScope() // .unrated → .picks
        XCTAssertEqual(model.cullScope, .picks)

        let summary = model.cullingProgressSummary

        // In scope: the confirmed pick and the AI-tentative pick.
        XCTAssertEqual(summary.scopedCounts.totalCount, 2)
        XCTAssertEqual(summary.scopedCounts.pickCount, 1)
        XCTAssertEqual(summary.scopedCounts.rejectCount, 0)
        // The tentative pick is in scope but still undecided.
        XCTAssertEqual(summary.scopedCounts.undecidedCount, 1)
        // The session-wide counts the scope line reports are unchanged.
        XCTAssertEqual(summary.pickCount, 1)
        XCTAssertEqual(summary.rejectCount, 1)
        XCTAssertEqual(summary.totalCount, 4)
    }

    func testScopedCountsShrinkToTheRejectsScope() throws {
        let model = try makeScopedCountsModel()
        model.cycleCullScope()
        model.cycleCullScope()
        model.cycleCullScope() // → .rejects
        XCTAssertEqual(model.cullScope, .rejects)

        let counts = model.cullingProgressSummary.scopedCounts

        XCTAssertEqual(counts.totalCount, 1)
        XCTAssertEqual(counts.pickCount, 0)
        XCTAssertEqual(counts.rejectCount, 1)
        XCTAssertEqual(counts.undecidedCount, 0)
    }

    func testScopedCountsShrinkToTheUnratedScope() throws {
        let model = try makeScopedCountsModel()
        model.cycleCullScope() // .all → .unrated
        XCTAssertEqual(model.cullScope, .unrated)

        let counts = model.cullingProgressSummary.scopedCounts

        XCTAssertEqual(counts.totalCount, 1)
        XCTAssertEqual(counts.pickCount, 0)
        XCTAssertEqual(counts.rejectCount, 0)
        XCTAssertEqual(counts.undecidedCount, 1)
    }

    // MARK: - Fixtures

    private static func asset(id: String, flag: PickFlag? = nil, tentative: Bool = false) -> Asset {
        var metadata = AssetMetadata()
        metadata.flag = flag
        if tentative, flag != nil {
            metadata.aiUnconfirmedFields.insert(.flag)
        }
        return Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/tmp/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata
        )
    }

}
