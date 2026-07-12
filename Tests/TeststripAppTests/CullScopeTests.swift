import XCTest
import TeststripCore
@testable import TeststripApp

final class CullScopeTests: XCTestCase {
    func testCycleOrderIsUnratedPicksRejectsAllThenWrapsToUnrated() {
        XCTAssertEqual(CullScope.unrated.next(), .picks)
        XCTAssertEqual(CullScope.picks.next(), .rejects)
        XCTAssertEqual(CullScope.rejects.next(), .all)
        XCTAssertEqual(CullScope.all.next(), .unrated)
    }

    func testUnratedScopeMatchesOnlyAssetsWithNoFlag() {
        XCTAssertTrue(CullScope.unrated.matches(nil))
        XCTAssertFalse(CullScope.unrated.matches(.pick))
        XCTAssertFalse(CullScope.unrated.matches(.reject))
    }

    func testPicksScopeMatchesOnlyPickedAssets() {
        XCTAssertTrue(CullScope.picks.matches(.pick))
        XCTAssertFalse(CullScope.picks.matches(.reject))
        XCTAssertFalse(CullScope.picks.matches(nil))
    }

    func testRejectsScopeMatchesOnlyRejectedAssets() {
        XCTAssertTrue(CullScope.rejects.matches(.reject))
        XCTAssertFalse(CullScope.rejects.matches(.pick))
        XCTAssertFalse(CullScope.rejects.matches(nil))
    }

    func testAllScopeMatchesEveryFlag() {
        XCTAssertTrue(CullScope.all.matches(nil))
        XCTAssertTrue(CullScope.all.matches(.pick))
        XCTAssertTrue(CullScope.all.matches(.reject))
    }

    func testScopeDisplayNamesAreUserFacing() {
        XCTAssertEqual(CullScope.unrated.displayName, "Unrated only")
        XCTAssertEqual(CullScope.picks.displayName, "Picks only")
        XCTAssertEqual(CullScope.rejects.displayName, "Rejects only")
        XCTAssertEqual(CullScope.all.displayName, "All frames")
    }

    func testCycleCullScopeAnnouncesNewScopeThroughDecisionToast() throws {
        // Pressing S silently renumbered the filmstrip (persona-8); the
        // scope change must announce itself through the same toast the
        // rating keys use.
        let model = AppModel(
            sidebarSections: [],
            selectedView: .loupe,
            assets: [Self.asset(id: "a", flag: nil), Self.asset(id: "b", flag: .pick)]
        )

        model.cycleCullScope()

        XCTAssertEqual(model.cullScope, .unrated)
        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertTrue(feedback.isInformational, "scope change writes no metadata; toast must not imply an undoable edit")
        XCTAssertEqual(feedback.decisionText, "Scope: Unrated only")
        XCTAssertEqual(CullDecisionToastPresentation(feedback: feedback).text, "Scope: Unrated only")

        model.cycleCullScope()
        XCTAssertEqual(model.lastCullingMetadataDecision?.decisionText, "Scope: Picks only")
    }

    func testFirstEntryToCullShowsKeyboardShortcutHintOncePerSession() throws {
        // Persona-8: the ? keymap overlay is great but nothing advertises it.
        // The first entry to the Cull workspace shows a one-time hint through
        // the decision toast; later entries stay quiet.
        let model = AppModel(
            sidebarSections: [],
            selectedView: .grid,
            assets: [Self.asset(id: "a", flag: nil)]
        )
        XCTAssertNil(model.lastCullingMetadataDecision)

        model.selectedView = .loupe

        let hint = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertTrue(hint.isInformational)
        XCTAssertEqual(hint.decisionText, "Press ? for keyboard shortcuts")

        model.selectedView = .grid
        XCTAssertNil(
            model.lastCullingMetadataDecision,
            "leaving Cull must clear the toast — the loupe re-renders whatever is left here on re-entry"
        )
        model.selectedView = .loupe
        XCTAssertNil(model.lastCullingMetadataDecision, "hint is once per session")
    }

    func testLeavingCullWorkspaceClearsStaleDecisionToast() throws {
        // Final-verify FAIL (cull-009): the once-per-session hint reappeared on
        // every re-entry to Cull. The gate was on emission, but the loupe's
        // toast task re-fires on view reappearance with whatever feedback is
        // still in lastCullingMetadataDecision — so ANY stale decision toast
        // (hint, scope, pick) re-renders on workspace re-entry unless the
        // model clears it on the way out.
        let model = AppModel(
            sidebarSections: [],
            selectedView: .loupe,
            assets: [Self.asset(id: "a", flag: nil)]
        )
        model.cycleCullScope()
        XCTAssertNotNil(model.lastCullingMetadataDecision)

        model.selectedView = .grid
        XCTAssertNil(model.lastCullingMetadataDecision, "workspace exit expires the decision toast")
    }

    func testFilteredAssetIDsOnlyContainsMatchingFrames() {
        let assets = [
            Self.asset(id: "a", flag: nil),
            Self.asset(id: "b", flag: .pick),
            Self.asset(id: "c", flag: .reject),
            Self.asset(id: "d", flag: nil)
        ]

        XCTAssertEqual(
            CullScopeOrdering.filteredAssetIDs(assets, scope: .unrated).map(\.rawValue),
            ["a", "d"]
        )
        XCTAssertEqual(
            CullScopeOrdering.filteredAssetIDs(assets, scope: .picks).map(\.rawValue),
            ["b"]
        )
        XCTAssertEqual(
            CullScopeOrdering.filteredAssetIDs(assets, scope: .rejects).map(\.rawValue),
            ["c"]
        )
        XCTAssertEqual(
            CullScopeOrdering.filteredAssetIDs(assets, scope: .all).map(\.rawValue),
            ["a", "b", "c", "d"]
        )
    }

    func testSelectionAfterScopeChangeKeepsCurrentFrameWhenItMatches() {
        let assets = [
            Self.asset(id: "a", flag: nil),
            Self.asset(id: "b", flag: .pick),
            Self.asset(id: "c", flag: .reject)
        ]

        let selection = CullScopeOrdering.selectionAfterScopeChange(
            assets: assets,
            scope: .picks,
            currentSelection: AssetID(rawValue: "b")
        )

        XCTAssertEqual(selection, AssetID(rawValue: "b"))
    }

    func testSelectionAfterScopeChangeAdvancesForwardToNearestMatch() {
        let assets = [
            Self.asset(id: "a", flag: nil),
            Self.asset(id: "b", flag: nil),
            Self.asset(id: "c", flag: .pick),
            Self.asset(id: "d", flag: nil)
        ]

        let selection = CullScopeOrdering.selectionAfterScopeChange(
            assets: assets,
            scope: .picks,
            currentSelection: AssetID(rawValue: "b")
        )

        XCTAssertEqual(selection, AssetID(rawValue: "c"))
    }

    func testSelectionAfterScopeChangeFallsBackToNearestPreviousMatch() {
        let assets = [
            Self.asset(id: "a", flag: .reject),
            Self.asset(id: "b", flag: nil),
            Self.asset(id: "c", flag: nil),
            Self.asset(id: "d", flag: nil)
        ]

        let selection = CullScopeOrdering.selectionAfterScopeChange(
            assets: assets,
            scope: .rejects,
            currentSelection: AssetID(rawValue: "c")
        )

        XCTAssertEqual(selection, AssetID(rawValue: "a"))
    }

    func testSelectionAfterScopeChangeReturnsNilWhenNoFrameMatches() {
        let assets = [
            Self.asset(id: "a", flag: nil),
            Self.asset(id: "b", flag: nil)
        ]

        let selection = CullScopeOrdering.selectionAfterScopeChange(
            assets: assets,
            scope: .rejects,
            currentSelection: AssetID(rawValue: "a")
        )

        XCTAssertNil(selection)
    }

    func testSelectionAfterScopeChangeWithNoCurrentSelectionPicksFirstMatch() {
        let assets = [
            Self.asset(id: "a", flag: nil),
            Self.asset(id: "b", flag: .pick),
            Self.asset(id: "c", flag: .pick)
        ]

        let selection = CullScopeOrdering.selectionAfterScopeChange(
            assets: assets,
            scope: .picks,
            currentSelection: nil
        )

        XCTAssertEqual(selection, AssetID(rawValue: "b"))
    }

    private static func asset(id: String, flag: PickFlag?) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(flag: flag)
        )
    }
}
