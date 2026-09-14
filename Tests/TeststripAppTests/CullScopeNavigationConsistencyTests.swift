import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Live-review (Reviewer 1, `burst` fixture) scope-consistency defects:
//   (a) in a filtered cull scope, selection could end up stranded on a frame
//       that is not in the filter, and every navigation key then did nothing;
//   (b) the stack rail's "Stack N of M" was built from the unfiltered set, so
//       it disagreed with the run strip's scope-filtered "stack N of M".
// Both must operate on the currently visible (scope-filtered) set.
final class CullScopeNavigationConsistencyTests: XCTestCase {

    // (a) ←/→ walked the unfiltered stop sequence, so a burst that has no
    // visible frames could still be landed on, stranding the selection outside
    // the scope. In `.picks` scope the middle burst is entirely unrated.
    func testNextStackSkipsFullyOutOfScopeBurstAndLandsOnVisiblePick() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let firstPick = makeAsset(id: "x1", path: "/Photos/Job/x1.cr2", capturedAt: capturedAt, flag: .pick)
        let firstMate = makeAsset(id: "x2", path: "/Photos/Job/x2.cr2", capturedAt: capturedAt.addingTimeInterval(1), flag: nil)
        let middleLead = makeAsset(id: "m1", path: "/Photos/Job/m1.cr2", capturedAt: capturedAt.addingTimeInterval(60), flag: nil)
        let middleMate = makeAsset(id: "m2", path: "/Photos/Job/m2.cr2", capturedAt: capturedAt.addingTimeInterval(61), flag: nil)
        let secondPick = makeAsset(id: "y1", path: "/Photos/Job/y1.cr2", capturedAt: capturedAt.addingTimeInterval(120), flag: .pick)
        let secondMate = makeAsset(id: "y2", path: "/Photos/Job/y2.cr2", capturedAt: capturedAt.addingTimeInterval(121), flag: nil)

        let (model, _) = try makeModelWithCatalogAssets(
            named: "scope-nav-skips-out-of-scope-burst",
            assets: [firstPick, firstMate, middleLead, middleMate, secondPick, secondMate]
        )
        model.cycleCullScope() // .all -> .unrated
        model.cycleCullScope() // .unrated -> .picks
        XCTAssertEqual(model.cullScope, .picks)
        model.select(firstPick.id)

        try model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(
            model.selectedAssetID,
            secondPick.id,
            "←/→ must walk only the scope-filtered stops; the unrated middle burst is not in .picks scope"
        )
    }

    // (a) Applying a decision directly (no auto-advance) left the selection on
    // a frame that no longer matches the active filter. Every arrow was then a
    // dead no-op: the frame's only burst held no other visible stop to reach.
    // Navigation must snap a stranded selection back into the visible set.
    func testPreviousStackEscapesSelectionStrandedOutsideScope() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let first = makeAsset(id: "a1", path: "/Photos/Job/a1.cr2", capturedAt: capturedAt, flag: nil)
        let second = makeAsset(id: "a2", path: "/Photos/Job/a2.cr2", capturedAt: capturedAt.addingTimeInterval(1), flag: nil)

        let (model, _) = try makeModelWithCatalogAssets(
            named: "scope-nav-stranded-selection",
            assets: [first, second]
        )
        model.cycleCullScope() // .all -> .unrated
        XCTAssertEqual(model.cullScope, .unrated)
        model.select(first.id)

        // Direct command (not the shortcut) so auto-advance doesn't move the
        // selection: it stays on `a1` even though `a1` is now a pick and no
        // longer matches the `.unrated` filter.
        try model.applyCullingCommand(.pick)
        XCTAssertEqual(model.selectedAssetID, first.id, "sanity: the selection is stranded on the now-out-of-scope frame")

        try model.applyCullingShortcut(.previousStack)

        XCTAssertEqual(
            model.selectedAssetID,
            second.id,
            "a stranded selection must not dead-end navigation — it has to return to the visible set"
        )
    }

    // (b) The rail is constructed from the model's stack scope, which was
    // derived from the unfiltered partition. In `.unrated` scope burst B is
    // entirely decided, so only one multi-frame stack remains visible; the
    // rail's counter must agree with the run strip's scope-filtered one.
    func testStackRailCounterMatchesScopeFilteredRunStrip() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let undecidedLead = makeAsset(id: "a1", path: "/Photos/Job/a1.cr2", capturedAt: capturedAt, flag: nil)
        let undecidedMate = makeAsset(id: "a2", path: "/Photos/Job/a2.cr2", capturedAt: capturedAt.addingTimeInterval(1), flag: nil)
        let decidedLead = makeAsset(id: "b1", path: "/Photos/Job/b1.cr2", capturedAt: capturedAt.addingTimeInterval(60), flag: .pick)
        let decidedMate = makeAsset(id: "b2", path: "/Photos/Job/b2.cr2", capturedAt: capturedAt.addingTimeInterval(61), flag: .pick)

        let (model, _) = try makeModelWithCatalogAssets(
            named: "scope-rail-counter",
            assets: [undecidedLead, undecidedMate, decidedLead, decidedMate]
        )
        model.cycleCullScope() // .all -> .unrated
        XCTAssertEqual(model.cullScope, .unrated)
        model.select(undecidedLead.id)

        // Build the rail exactly as `LoupeView.cullingStackPresentation` does.
        let rail = CullingStackRailPresentation(
            assets: model.assets,
            selectedAssetID: model.selectedAssetID,
            evaluationSignalsByAssetID: model.selectedCullingStackEvaluationSignals(),
            explicitStackScope: model.selectedCullingStackScope,
            stackBuilder: model.stackBuilder(),
            precomputedAllStacks: model.cachedAllCullingStacksForPresentation()
        )

        // Build the run-strip counter exactly as `LoupeView.runStrip` does.
        let scopedAssets = CullScopeOrdering.filteredAssets(model.assets, scope: model.cullScope)
        let counter = CullFilmstripPresentation(
            assets: scopedAssets,
            stacks: model.allCullingStacks(for: scopedAssets),
            selectedAssetID: model.selectedAssetID
        )

        XCTAssertEqual(
            rail.titleText,
            "Stack 1 of 1",
            "the rail's stack counter must reflect the active scope, not the unfiltered set"
        )
        XCTAssertTrue(
            counter.tripleCounterText.contains("stack 1 of 1"),
            "sanity: the run strip's counter is scope-filtered (\(counter.tripleCounterText))"
        )
    }

    // MARK: - Fixtures

    private func makeAsset(
        id: String,
        path: String,
        capturedAt: Date,
        flag: PickFlag?
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(flag: flag),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                capturedAt: capturedAt,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
    }
}
