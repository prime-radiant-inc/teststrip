import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class CullCompletionTests: XCTestCase {
    // MARK: - Presentation appears only at zero undecided, non-empty session

    func testPresentationIsNilWhenUndecidedRemains() {
        let presentation = CullCompletionPresentation.presentation(
            pickCount: 2,
            rejectCount: 1,
            totalCount: 5,
            undecidedCount: 2,
            scope: .all
        )
        XCTAssertNil(presentation)
    }

    func testPresentationIsNilWhenSessionIsEmpty() {
        let presentation = CullCompletionPresentation.presentation(
            pickCount: 0,
            rejectCount: 0,
            totalCount: 0,
            undecidedCount: 0,
            scope: .all
        )
        XCTAssertNil(presentation)
    }

    func testPresentationAppearsWhenUndecidedIsZeroAndSessionNonEmpty() {
        for scope in [CullScope.unrated, .all] {
            let presentation = CullCompletionPresentation.presentation(
                pickCount: 3,
                rejectCount: 2,
                totalCount: 5,
                undecidedCount: 0,
                scope: scope
            )
            XCTAssertEqual(presentation?.picks, 3, "scope \(scope)")
            XCTAssertEqual(presentation?.rejects, 2, "scope \(scope)")
        }
    }

    // MARK: - Review scopes never show completion

    func testPresentationIsSuppressedInReviewScopesEvenWhenComplete() {
        // .picks/.rejects are review scopes: even a genuinely-complete
        // session must show the frames under review, not the handoff.
        for scope in [CullScope.picks, .rejects] {
            let presentation = CullCompletionPresentation.presentation(
                pickCount: 3,
                rejectCount: 2,
                totalCount: 5,
                undecidedCount: 0,
                scope: scope
            )
            XCTAssertNil(presentation, "scope \(scope)")
        }
    }

    func testSwitchingToPicksScopeWithUndecidedWorkDoesNotShowCompletionAndPicksAreBrowsable() {
        // Regression: undecided must be counted session-wide, not within the
        // scope filter — .picks excludes unflagged frames by definition, so a
        // scope-filtered count is trivially zero and falsely reports done.
        let model = makeModel(withFlags: [nil, .pick, .pick, nil])
        cycleCullScope(model, to: .picks)

        XCTAssertEqual(model.cullUndecidedCount, 2)
        let presentation = CullCompletionPresentation.presentation(
            pickCount: 2,
            rejectCount: 0,
            totalCount: 4,
            undecidedCount: model.cullUndecidedCount,
            scope: model.cullScope
        )
        XCTAssertNil(presentation)
        // The picks are browsable: scope navigation has picks to land on.
        XCTAssertEqual(
            CullScopeOrdering.filteredAssetIDs(model.assets, scope: model.cullScope),
            [AssetID(rawValue: "asset-1"), AssetID(rawValue: "asset-2")]
        )
    }

    // MARK: - Actions

    func testActionsAreExportMoveRejectsMoveRejectsToTrashReviewPicksInOrder() {
        let presentation = CullCompletionPresentation.presentation(
            pickCount: 1,
            rejectCount: 1,
            totalCount: 2,
            undecidedCount: 0,
            scope: .all
        )
        XCTAssertEqual(presentation?.actions, [.export, .moveRejects, .moveRejectsToTrash, .reviewPicks])
    }

    // MARK: - Undecided count on AppModel

    func testCullUndecidedCountIsSessionWideRegardlessOfScope() {
        let model = makeModel(withFlags: [nil, .pick, .reject, nil])
        XCTAssertEqual(model.cullScope, .all)
        XCTAssertEqual(model.cullUndecidedCount, 2)

        cycleCullScope(model, to: .picks)
        XCTAssertEqual(model.cullUndecidedCount, 2)

        cycleCullScope(model, to: .unrated)
        XCTAssertEqual(model.cullUndecidedCount, 2)
    }

    // MARK: - ReviewPicks sets scope

    func testReviewPicksActionSetsCullScopeToPicks() {
        let model = makeModel(withFlags: [nil, .pick])
        XCTAssertNotEqual(model.cullScope, .picks)

        model.applyCullCompletionReviewPicks()

        XCTAssertEqual(model.cullScope, .picks)
    }

    func testReviewPicksFromCompleteSessionShowsPicksNotCompletion() {
        // From a genuinely-complete session, ReviewPicks must land the user
        // on the picks stage, not re-render the completion state.
        let model = makeModel(withFlags: [.pick, .reject, .pick])
        XCTAssertEqual(model.cullUndecidedCount, 0)

        model.applyCullCompletionReviewPicks()

        XCTAssertEqual(model.cullScope, .picks)
        let presentation = CullCompletionPresentation.presentation(
            pickCount: 2,
            rejectCount: 1,
            totalCount: 3,
            undecidedCount: model.cullUndecidedCount,
            scope: model.cullScope
        )
        XCTAssertNil(presentation)
        // A pick is selected, so the stage shows a pick.
        let pickIDs = CullScopeOrdering.filteredAssetIDs(model.assets, scope: .picks)
        XCTAssertFalse(pickIDs.isEmpty)
        if let selected = model.selectedAssetID {
            XCTAssertTrue(pickIDs.contains(selected))
        }
    }

    // MARK: - Helpers

    private func cycleCullScope(_ model: AppModel, to target: CullScope) {
        while model.cullScope != target {
            model.cycleCullScope()
        }
    }

    private func makeModel(withFlags flags: [PickFlag?]) -> AppModel {
        let assets = flags.enumerated().map { index, flag -> Asset in
            var metadata = AssetMetadata()
            metadata.flag = flag
            return Asset(
                id: AssetID(rawValue: "asset-\(index)"),
                originalURL: URL(fileURLWithPath: "/tmp/asset-\(index).jpg"),
                volumeIdentifier: "Photos",
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index))),
                availability: .online,
                metadata: metadata
            )
        }
        return AppModel(sidebarSections: [], selectedView: .loupe, assets: assets)
    }
}
