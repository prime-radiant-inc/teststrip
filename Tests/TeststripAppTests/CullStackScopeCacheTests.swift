import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Issue #5: `selectedCullingStackScope` recomputes the full stack partition
// (one `evaluationSignals` SQL query per asset) on every access with no
// cache. These tests verify the cache is used across reads without
// invalidation, and invalidated on flag/rating/scope/asset/selection changes.
final class CullStackScopeCacheTests: XCTestCase {

    // MARK: - Cache hit (no recomputation without invalidation)

    func testRepeatedAccessDoesNotRecompute() throws {
        let (model, _) = try makeStackOfThree(selected: "a")

        let first = model.selectedCullingStackScope
        let countAfterFirst = model._cullingStackScopeRecomputeCount
        XCTAssertNotNil(first)

        let second = model.selectedCullingStackScope
        let countAfterSecond = model._cullingStackScopeRecomputeCount

        XCTAssertEqual(countAfterFirst, countAfterSecond,
                       "second access should hit the cache, not recompute")
        XCTAssertEqual(first, second)
    }

    // MARK: - Flag invalidation

    func testCacheInvalidatedAfterFlagWrite() throws {
        let (model, _) = try makeStackOfThree(selected: "a")

        _ = model.selectedCullingStackScope
        let countBefore = model._cullingStackScopeRecomputeCount

        try model.setFlagForSelectedAsset(.pick)

        _ = model.selectedCullingStackScope
        let countAfter = model._cullingStackScopeRecomputeCount

        XCTAssertEqual(countAfter, countBefore + 1,
                       "flag write should invalidate the cache and force recomputation")
    }

    func testCacheInvalidatedAfterClearingFlag() throws {
        let (model, _) = try makeStackOfThree(selected: "a")

        try model.setFlagForSelectedAsset(.pick)
        _ = model.selectedCullingStackScope
        let countBefore = model._cullingStackScopeRecomputeCount

        try model.setFlagForSelectedAsset(nil)

        _ = model.selectedCullingStackScope
        let countAfter = model._cullingStackScopeRecomputeCount

        XCTAssertEqual(countAfter, countBefore + 1,
                       "clearing a flag should invalidate the cache")
    }

    // MARK: - Rating invalidation

    func testCacheInvalidatedAfterRatingWrite() throws {
        let (model, _) = try makeStackOfThree(selected: "a")

        _ = model.selectedCullingStackScope
        let countBefore = model._cullingStackScopeRecomputeCount

        try model.setRatingForSelectedAsset(3)

        _ = model.selectedCullingStackScope
        let countAfter = model._cullingStackScopeRecomputeCount

        XCTAssertEqual(countAfter, countBefore + 1,
                       "rating write should invalidate the cache and force recomputation")
    }

    // MARK: - Scope invalidation

    func testCacheInvalidatedAfterScopeChange() throws {
        let (model, _) = try makeStackOfThree(selected: "a")

        _ = model.selectedCullingStackScope
        let countBefore = model._cullingStackScopeRecomputeCount

        model.cycleCullScope()

        _ = model.selectedCullingStackScope
        let countAfter = model._cullingStackScopeRecomputeCount

        // cycleCullScope invalidates directly AND changes selectedAssetID
        // (which invalidates again via didSet). Both set the cache to nil,
        // so exactly one recomputation occurs.
        XCTAssertEqual(countAfter, countBefore + 1,
                       "scope change should invalidate the cache")
    }

    // MARK: - Selection invalidation

    func testCacheInvalidatedAfterSelectionChange() throws {
        let (model, _) = try makeStackOfThree(selected: "a")

        _ = model.selectedCullingStackScope
        let countBefore = model._cullingStackScopeRecomputeCount

        model.select(AssetID(rawValue: "b"))

        _ = model.selectedCullingStackScope
        let countAfter = model._cullingStackScopeRecomputeCount

        XCTAssertEqual(countAfter, countBefore + 1,
                       "selection change should invalidate the cache")
    }

    // MARK: - Reload invalidation

    func testCacheInvalidatedAfterReload() throws {
        let (model, _) = try makeStackOfThree(selected: "a")

        _ = model.selectedCullingStackScope
        let countBefore = model._cullingStackScopeRecomputeCount

        try model.reload()

        _ = model.selectedCullingStackScope
        let countAfter = model._cullingStackScopeRecomputeCount

        // reload() invalidates directly AND calls replaceAssets (which
        // invalidates again) AND may change selectedAssetID (didSet).
        // All set the cache to nil, so exactly one recomputation occurs.
        XCTAssertEqual(countAfter, countBefore + 1,
                       "reload should invalidate the cache")
    }

    // MARK: - Culling command invalidation

    func testCacheInvalidatedAfterCullingCommandPick() throws {
        let (model, _) = try makeStackOfThree(selected: "a")

        _ = model.selectedCullingStackScope
        let countBefore = model._cullingStackScopeRecomputeCount

        try model.applyCullingCommand(.pick)

        _ = model.selectedCullingStackScope
        let countAfter = model._cullingStackScopeRecomputeCount

        XCTAssertEqual(countAfter, countBefore + 1,
                       "culling pick command should invalidate the cache")
    }

    // MARK: - Correctness after invalidation

    func testScopeReflectsCurrentStateAfterFlagMutation() throws {
        let (model, _) = try makeStackOfThree(selected: "a")

        let before = model.selectedCullingStackScope
        XCTAssertEqual(before?.assetIDs, [AssetID(rawValue: "a"), AssetID(rawValue: "b"), AssetID(rawValue: "c")])

        try model.setFlagForSelectedAsset(.pick)

        let after = model.selectedCullingStackScope
        // The partition (stack grouping) is based on capture time and visual
        // similarity, not flag state, so the stack membership is the same.
        // The key assertion is that the scope was recomputed (not stale).
        XCTAssertEqual(after?.assetIDs, [AssetID(rawValue: "a"), AssetID(rawValue: "b"), AssetID(rawValue: "c")])
        XCTAssertNotEqual(model._cullingStackScopeRecomputeCount, 0)
    }

    // MARK: - Fixtures

    private func makeStackOfThree(selected id: String) throws -> (AppModel, CatalogRepository) {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let a = makeAsset(
            id: "a",
            path: "/Photos/Job/a.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let b = makeAsset(
            id: "b",
            path: "/Photos/Job/b.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let c = makeAsset(
            id: "c",
            path: "/Photos/Job/c.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let (model, repository) = try makeModelWithCatalogAssets(named: "stack-cache-\(id)", assets: [a, b, c])
        model.select(AssetID(rawValue: id))
        // Reset the recompute counter after setup so tests start from a clean baseline.
        model._cullingStackScopeRecomputeCount = 0
        _ = model.selectedCullingStackScope
        model._cullingStackScopeRecomputeCount = 0
        return (model, repository)
    }

    private func makeAsset(
        id: String,
        path: String,
        technicalMetadata: AssetTechnicalMetadata? = nil,
        metadata: AssetMetadata = AssetMetadata()
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata,
            technicalMetadata: technicalMetadata
        )
    }

    private static func technicalMetadata(capturedAt: Date) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
    }
}
