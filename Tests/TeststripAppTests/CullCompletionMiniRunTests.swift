import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class CullCompletionMiniRunTests: XCTestCase {
    // MARK: - MiniRun value type

    func testMiniRunHoldsNumberTitleActionAndAssetIDs() {
        let run = CullCompletionPresentation.MiniRun(
            number: 1,
            title: "Cull undecided",
            action: .cullUndecided,
            assetIDs: [AssetID(rawValue: "a1")]
        )
        XCTAssertEqual(run.number, 1)
        XCTAssertEqual(run.title, "Cull undecided")
        XCTAssertEqual(run.action, .cullUndecided)
        XCTAssertEqual(run.assetIDs, [AssetID(rawValue: "a1")])
    }

    // MARK: - summary() populates miniRuns with stable numbering

    func testMiniRunsIncludeCullUndecidedWhenUndecidedPositive() {
        let assets = [
            Self.asset(id: "a0", flag: .pick),
            Self.asset(id: "a1"),
        ]
        let summary = CullCompletionPresentation.summary(
            assets: assets,
            viewedAssetIDs: [],
            skippedAssetIDs: []
        )
        XCTAssertEqual(summary.miniRuns, [
            .init(number: 1, title: "Cull undecided", action: .cullUndecided, assetIDs: [assets[1].id]),
            .init(number: 3, title: "Cull never-viewed", action: .cullNeverViewed, assetIDs: [assets[0].id, assets[1].id]),
            .init(number: 5, title: "Export", action: .export, assetIDs: [assets[0].id]),
        ])
    }

    func testMiniRunsIncludeCullSkippedWhenSkippedPositive() {
        let assets = [
            Self.asset(id: "a0", flag: .pick),
            Self.asset(id: "a1"),
        ]
        let summary = CullCompletionPresentation.summary(
            assets: assets,
            viewedAssetIDs: [assets[0].id, assets[1].id],
            skippedAssetIDs: [assets[1].id]
        )
        // undecided=1, skipped=1 (a1 is skipped and undecided), neverViewed=0
        XCTAssertEqual(summary.miniRuns, [
            .init(number: 1, title: "Cull undecided", action: .cullUndecided, assetIDs: [assets[1].id]),
            .init(number: 2, title: "Cull skipped", action: .cullSkipped, assetIDs: [assets[1].id]),
            .init(number: 5, title: "Export", action: .export, assetIDs: [assets[0].id]),
        ])
    }

    func testMiniRunsIncludeMoveRejectsWhenRejectsPositive() {
        let assets = [
            Self.asset(id: "a0", flag: .pick),
            Self.asset(id: "a1", flag: .reject),
        ]
        let summary = CullCompletionPresentation.summary(
            assets: assets,
            viewedAssetIDs: [assets[0].id, assets[1].id],
            skippedAssetIDs: []
        )
        // picks=1, rejects=1, undecided=0, skipped=0, neverViewed=0
        XCTAssertEqual(summary.miniRuns, [
            .init(number: 5, title: "Export", action: .export, assetIDs: [assets[0].id]),
            .init(number: 6, title: "Move rejects", action: .moveRejects, assetIDs: [assets[1].id]),
        ])
    }

    func testMiniRunsIncludeAllEligibleRunsWithStableNumbers() {
        let assets = [
            Self.asset(id: "a0", flag: .pick),
            Self.asset(id: "a1", flag: .reject),
            Self.asset(id: "a2"),
            Self.asset(id: "a3"),
        ]
        let summary = CullCompletionPresentation.summary(
            assets: assets,
            viewedAssetIDs: [assets[0].id, assets[1].id, assets[2].id],
            skippedAssetIDs: [assets[1].id, assets[2].id]
        )
        // picks=1, rejects=1, undecided=2, skipped=1 (a2), neverViewed=1 (a3)
        XCTAssertEqual(summary.miniRuns, [
            .init(number: 1, title: "Cull undecided", action: .cullUndecided, assetIDs: [assets[2].id, assets[3].id]),
            .init(number: 2, title: "Cull skipped", action: .cullSkipped, assetIDs: [assets[2].id]),
            .init(number: 3, title: "Cull never-viewed", action: .cullNeverViewed, assetIDs: [assets[3].id]),
            .init(number: 5, title: "Export", action: .export, assetIDs: [assets[0].id]),
            .init(number: 6, title: "Move rejects", action: .moveRejects, assetIDs: [assets[1].id]),
        ])
    }

    func testMiniRunsOmitZeroCountEntriesButKeepStableNumbers() {
        let assets = [
            Self.asset(id: "a0", flag: .pick),
            Self.asset(id: "a1", flag: .pick),
        ]
        let summary = CullCompletionPresentation.summary(
            assets: assets,
            viewedAssetIDs: [assets[0].id, assets[1].id],
            skippedAssetIDs: []
        )
        // All decided, all viewed, no skips, no rejects
        XCTAssertEqual(summary.miniRuns, [
            .init(number: 5, title: "Export", action: .export, assetIDs: [assets[0].id, assets[1].id]),
        ])
    }

    // MARK: - Awaiting review (passed as parameter)

    func testMiniRunsIncludeReviewAIWhenAwaitingReviewPositive() {
        let assets = [
            Self.asset(id: "a0", flag: .pick),
            Self.asset(id: "a1", flag: .reject),
        ]
        let summary = CullCompletionPresentation.summary(
            assets: assets,
            viewedAssetIDs: [assets[0].id, assets[1].id],
            skippedAssetIDs: [],
            awaitingReviewCount: 96
        )
        XCTAssertEqual(summary.miniRuns, [
            .init(number: 4, title: "Review ✨", action: .reviewAI, assetIDs: []),
            .init(number: 5, title: "Export", action: .export, assetIDs: [assets[0].id]),
            .init(number: 6, title: "Move rejects", action: .moveRejects, assetIDs: [assets[1].id]),
        ])
    }

    func testMiniRunsOmitReviewAIWhenAwaitingReviewZero() {
        let assets = [
            Self.asset(id: "a0", flag: .pick),
            Self.asset(id: "a1", flag: .reject),
        ]
        let summary = CullCompletionPresentation.summary(
            assets: assets,
            viewedAssetIDs: [assets[0].id, assets[1].id],
            skippedAssetIDs: [],
            awaitingReviewCount: 0
        )
        XCTAssertFalse(summary.miniRuns.contains { $0.number == 4 })
    }

    // MARK: - Defaults

    func testAwaitingReviewCountDefaultsToZero() {
        let assets = [Self.asset(id: "a0", flag: .pick)]
        let summary = CullCompletionPresentation.summary(
            assets: assets,
            viewedAssetIDs: [assets[0].id],
            skippedAssetIDs: []
        )
        XCTAssertEqual(summary.awaitingReviewCount, 0)
    }

    // MARK: - Action enum includes mini-run starters

    func testActionEnumIncludesMiniRunStarters() {
        XCTAssertEqual(CullCompletionPresentation.Action.cullUndecided, .cullUndecided)
        XCTAssertEqual(CullCompletionPresentation.Action.cullSkipped, .cullSkipped)
        XCTAssertEqual(CullCompletionPresentation.Action.cullNeverViewed, .cullNeverViewed)
        XCTAssertEqual(CullCompletionPresentation.Action.reviewAI, .reviewAI)
    }

    // MARK: - Helpers

    private static func asset(id: String, flag: PickFlag? = nil) -> Asset {
        var metadata = AssetMetadata()
        metadata.flag = flag
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
