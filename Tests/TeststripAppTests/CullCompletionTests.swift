import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class CullCompletionTests: XCTestCase {
    // MARK: - Presentation appears only at zero scoped-undecided, non-empty session

    func testPresentationIsNilWhenScopedUndecidedRemains() {
        let presentation = CullCompletionPresentation.presentation(
            pickCount: 2,
            rejectCount: 1,
            totalCount: 5,
            scopedUndecidedCount: 2
        )
        XCTAssertNil(presentation)
    }

    func testPresentationIsNilWhenSessionIsEmpty() {
        let presentation = CullCompletionPresentation.presentation(
            pickCount: 0,
            rejectCount: 0,
            totalCount: 0,
            scopedUndecidedCount: 0
        )
        XCTAssertNil(presentation)
    }

    func testPresentationAppearsWhenScopedUndecidedIsZeroAndSessionNonEmpty() {
        let presentation = CullCompletionPresentation.presentation(
            pickCount: 3,
            rejectCount: 2,
            totalCount: 5,
            scopedUndecidedCount: 0
        )
        XCTAssertEqual(presentation?.picks, 3)
        XCTAssertEqual(presentation?.rejects, 2)
    }

    // MARK: - Actions

    func testActionsAreExportMoveRejectsReviewPicksInOrder() {
        let presentation = CullCompletionPresentation.presentation(
            pickCount: 1,
            rejectCount: 1,
            totalCount: 2,
            scopedUndecidedCount: 0
        )
        XCTAssertEqual(presentation?.actions, [.export, .moveRejects, .reviewPicks])
    }

    // MARK: - Scoped undecided count on AppModel

    func testScopedUndecidedCountReflectsCurrentScopeOnly() {
        let model = makeModel(withFlags: [nil, .pick, .reject, nil])
        // Default cullScope is .all.
        XCTAssertEqual(model.cullScope, .all)
        XCTAssertEqual(model.scopedUndecidedCount, 2)

        cycleCullScope(model, to: .picks)
        XCTAssertEqual(model.scopedUndecidedCount, 0)

        cycleCullScope(model, to: .unrated)
        XCTAssertEqual(model.scopedUndecidedCount, 2)
    }

    // MARK: - ReviewPicks sets scope

    func testReviewPicksActionSetsCullScopeToPicks() {
        let model = makeModel(withFlags: [nil, .pick])
        XCTAssertNotEqual(model.cullScope, .picks)

        model.applyCullCompletionReviewPicks()

        XCTAssertEqual(model.cullScope, .picks)
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
