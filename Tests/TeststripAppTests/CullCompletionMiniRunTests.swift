import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class CullCompletionMiniRunTests: XCTestCase {
    // MARK: - MiniRun value type

    func testMiniRunHoldsNumberLabelAndAction() {
        let run = CullCompletionPresentation.MiniRun(
            number: 1,
            label: "Cull undecided",
            action: .cullUndecided
        )
        XCTAssertEqual(run.number, 1)
        XCTAssertEqual(run.label, "Cull undecided")
        XCTAssertEqual(run.action, .cullUndecided)
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
            CullCompletionPresentation.MiniRun(number: 1, label: "Cull undecided", action: .cullUndecided),
            CullCompletionPresentation.MiniRun(number: 3, label: "Cull never-viewed", action: .cullNeverViewed),
            CullCompletionPresentation.MiniRun(number: 5, label: "Export", action: .export),
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
            CullCompletionPresentation.MiniRun(number: 1, label: "Cull undecided", action: .cullUndecided),
            CullCompletionPresentation.MiniRun(number: 2, label: "Cull skipped", action: .cullSkipped),
            CullCompletionPresentation.MiniRun(number: 5, label: "Export", action: .export),
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
            CullCompletionPresentation.MiniRun(number: 5, label: "Export", action: .export),
            CullCompletionPresentation.MiniRun(number: 6, label: "Move rejects", action: .moveRejects),
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
            CullCompletionPresentation.MiniRun(number: 1, label: "Cull undecided", action: .cullUndecided),
            CullCompletionPresentation.MiniRun(number: 2, label: "Cull skipped", action: .cullSkipped),
            CullCompletionPresentation.MiniRun(number: 3, label: "Cull never-viewed", action: .cullNeverViewed),
            CullCompletionPresentation.MiniRun(number: 5, label: "Export", action: .export),
            CullCompletionPresentation.MiniRun(number: 6, label: "Move rejects", action: .moveRejects),
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
            CullCompletionPresentation.MiniRun(number: 5, label: "Export", action: .export),
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
            CullCompletionPresentation.MiniRun(number: 4, label: "Review ✨", action: .reviewAI),
            CullCompletionPresentation.MiniRun(number: 5, label: "Export", action: .export),
            CullCompletionPresentation.MiniRun(number: 6, label: "Move rejects", action: .moveRejects),
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
        // No "4 Review ✨" entry
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
