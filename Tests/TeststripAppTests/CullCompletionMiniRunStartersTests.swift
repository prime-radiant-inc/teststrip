import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-D Task 6: Mini-run starter methods that start scoped culling sessions
// from the completion summary — undecided, skipped, never-viewed, and
// awaiting-review (tentative AI flags).
final class CullCompletionMiniRunStartersTests: XCTestCase {
    func testCullUndecidedFromCompletionStartsSessionScopedToUndecided() throws {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "r1", flag: .reject),
            Self.asset(id: "u1"),
            Self.asset(id: "u2"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-undecided",
            assets: assets
        )

        let session = try model.cullUndecidedFromCompletion()

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(session.title.isEmpty)
        let scopedIDs = try Self.scopedAssetIDs(from: session, model: model)
        XCTAssertEqual(scopedIDs, Set(assets[2...].map(\.id)),
                       "session should be scoped to undecided assets only (u1, u2)")
    }

    func testCullUndecidedFromCompletionThrowsWhenNoUndecided() throws {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "r1", flag: .reject),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-undecided-empty",
            assets: assets
        )

        XCTAssertThrowsError(try model.cullUndecidedFromCompletion()) { error in
            guard case TeststripError.invalidState(let message) = error else {
                XCTFail("Expected invalidState error, got \(error)")
                return
            }
            XCTAssertEqual(message, "there are no photos to cull")
        }
    }

    func testCullSkippedFromCompletionStartsSessionScopedToSkipped() throws {
        let assets = [
            Self.asset(id: "u1"),
            Self.asset(id: "u2"),
            Self.asset(id: "u3"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-skipped",
            assets: assets
        )
        try model.beginCullingSession(named: "Skipped Run")
        // Space (nextPhoto) on an undecided frame records a skip.
        try model.applyCullingShortcut(.nextPhoto)
        // The opening frame is now in the skipped set.
        XCTAssertFalse(model.cullRunTracker.skippedAssetIDs.isEmpty)
        let expectedSkippedIDs = model.cullRunTracker.skippedAssetIDs

        let session = try model.cullSkippedFromCompletion()

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(session.title.isEmpty)
        let scopedIDs = try Self.scopedAssetIDs(from: session, model: model)
        XCTAssertEqual(scopedIDs, expectedSkippedIDs,
                       "session should be scoped to skipped assets only")
    }

    func testCullSkippedFromCompletionThrowsWhenNoSkipped() throws {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-skipped-empty",
            assets: assets
        )

        XCTAssertThrowsError(try model.cullSkippedFromCompletion()) { error in
            guard case TeststripError.invalidState(let message) = error else {
                XCTFail("Expected invalidState error, got \(error)")
                return
            }
            XCTAssertEqual(message, "there are no photos to cull")
        }
    }

    func testCullNeverViewedFromCompletionStartsSessionScopedToNeverViewed() throws {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "u1"),
            Self.asset(id: "u2"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-never-viewed",
            assets: assets
        )

        let session = try model.cullNeverViewedFromCompletion()

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(session.title.isEmpty)
        let scopedIDs = try Self.scopedAssetIDs(from: session, model: model)
        XCTAssertEqual(scopedIDs, Set(assets.map(\.id)),
                       "session should be scoped to all assets (none viewed yet)")
    }

    func testCullNeverViewedFromCompletionThrowsWhenAllViewed() throws {
        let assets = [Self.asset(id: "p1", flag: .pick)]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-never-viewed-empty",
            assets: assets
        )
        try model.beginCullingSession(named: "All Viewed")
        // beginCullingSession → startCullRunTracking records the opening frame
        // as viewed, so there are no never-viewed assets left.
        model.dismissCullingSessionCompletion()

        XCTAssertThrowsError(try model.cullNeverViewedFromCompletion()) { error in
            guard case TeststripError.invalidState(let message) = error else {
                XCTFail("Expected invalidState error, got \(error)")
                return
            }
            XCTAssertEqual(message, "there are no photos to cull")
        }
    }

    func testReviewAIFromCompletionStartsSessionScopedToTentativeAI() throws {
        let assets = [
            Self.asset(id: "ai1", flag: .pick, tentative: true),
            Self.asset(id: "ai2", flag: .reject, tentative: true),
            Self.asset(id: "u1"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-review-ai",
            assets: assets
        )

        let session = try model.reviewAIFromCompletion()

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertFalse(session.title.isEmpty)
        let scopedIDs = try Self.scopedAssetIDs(from: session, model: model)
        XCTAssertEqual(scopedIDs, Set([assets[0].id, assets[1].id]),
                       "session should be scoped to tentative-AI-flagged assets only (ai1, ai2)")
    }

    func testReviewAIFromCompletionThrowsWhenNoTentativeAI() throws {
        let assets = [
            Self.asset(id: "p1", flag: .pick),
            Self.asset(id: "u1"),
        ]
        let (model, _) = try makeModelWithCatalogAssets(
            named: "mini-review-ai-empty",
            assets: assets
        )

        XCTAssertThrowsError(try model.reviewAIFromCompletion()) { error in
            guard case TeststripError.invalidState(let message) = error else {
                XCTFail("Expected invalidState error, got \(error)")
                return
            }
            XCTAssertEqual(message, "there are no photos to cull")
        }
    }

    // MARK: - Helpers

    /// Resolves the scoped asset IDs from a mini-run session by looking up
    /// its input set in the model's saved asset sets and extracting the
    /// snapshot membership.
    private static func scopedAssetIDs(from session: WorkSession, model: AppModel) throws -> Set<AssetID> {
        guard let inputSetID = session.inputSetIDs.first,
              let assetSet = model.savedAssetSets.first(where: { $0.id == inputSetID }) else {
            throw TeststripError.invalidState("session input set not found in savedAssetSets")
        }
        guard case .snapshot(let assetIDs) = assetSet.membership else {
            throw TeststripError.invalidState("expected snapshot membership for mini-run input set")
        }
        return Set(assetIDs)
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
