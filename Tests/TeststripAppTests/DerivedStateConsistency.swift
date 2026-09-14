import XCTest
@testable import TeststripCore
@testable import TeststripApp

// A reusable pattern for the derived-state bug CLASS the four-persona live
// review found: the catalog is right, but the app's DERIVED UI state ("what's
// left / where am I") drifts from it. Five instances of one shape shipped
// across three surfaces (cull scope navigation + rail counter, the People-lens
// person disappearing, premature "Nothing left to review", and plain-text
// search coverage). Each helper below asserts a model-derived value against a
// FRESH catalog query, and is meant to be applied immediately after a mutating
// action — the moment the drift would appear.
//
// Where a derived value genuinely cannot be answered by a catalog query, the
// helper asserts it against the documented invariant instead, and says which.

/// The catalog query the model resolves from its live search text — the plain
/// text + structured-token portion of `AppModel.currentLibraryQuery()`.
/// `LibrarySearchIntent.parse` is the same parser the model itself uses, so a
/// test that keeps every other filter empty (no dynamic set, no detached
/// filters, no keyword/folder/rating fields) gets an exact reconstruction.
func catalogQuery(matchingSearchText searchText: String) -> SetQuery {
    var predicates: [SetQuery.Predicate] = []
    let intent = LibrarySearchIntent.parse(searchText)
    if let residual = intent.residualText {
        predicates.append(.text(residual))
    }
    predicates.append(contentsOf: intent.predicates)
    return SetQuery(predicates: predicates)
}

/// Maps the app's `CullScope` onto the catalog's `CatalogCullScope` for a
/// scoped count query (`AppModel.catalogCullScope` is private).
func catalogCullScope(for scope: CullScope) -> CatalogCullScope {
    switch scope {
    case .all: return .all
    case .unrated: return .unrated
    case .picks: return .picks
    case .rejects: return .rejects
    }
}

extension XCTestCase {

    /// The Cull HUD's ✓/✕/undecided cluster must equal a fresh scoped catalog
    /// count for the model's query, and the HUD presentation must render
    /// exactly the summary it was handed. A scoped pass over a fully loaded
    /// catalog is where the original defect lived: the cluster showed
    /// whole-session numbers even in a filtered scope.
    func assertCullHUDMatchesCatalog(
        _ model: AppModel,
        repository: CatalogRepository,
        query: SetQuery = SetQuery(predicates: []),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let scope = catalogCullScope(for: model.cullScope)
        let expectedTotal = try repository.assetCount(matching: query, cullScope: scope)
        let expectedPick = try repository.assetCount(matching: query, cullScope: scope, confirmedFlag: .pick)
        let expectedReject = try repository.assetCount(matching: query, cullScope: scope, confirmedFlag: .reject)
        let expectedUndecided = expectedTotal - expectedPick - expectedReject

        let summary = model.cullingProgressSummary
        XCTAssertEqual(
            summary.scopedCounts.totalCount, expectedTotal,
            "scoped total drifted from the catalog for \(model.cullScope)",
            file: file, line: line
        )
        XCTAssertEqual(
            summary.scopedCounts.pickCount, expectedPick,
            "scoped pick count drifted from the catalog for \(model.cullScope)",
            file: file, line: line
        )
        XCTAssertEqual(
            summary.scopedCounts.rejectCount, expectedReject,
            "scoped reject count drifted from the catalog for \(model.cullScope)",
            file: file, line: line
        )
        XCTAssertEqual(
            summary.scopedCounts.undecidedCount, expectedUndecided,
            "scoped undecided count drifted from the catalog for \(model.cullScope)",
            file: file, line: line
        )

        // The HUD's own cluster is a pure projection of the summary — if the
        // two ever disagree, the surface shows numbers the model never held.
        let hud = CullHUDPresentation(
            filename: "",
            rating: 0,
            colorLabel: nil,
            summary: summary,
            scope: model.cullScope
        )
        XCTAssertEqual(hud.pickCount, expectedPick, "HUD pick count drifted", file: file, line: line)
        XCTAssertEqual(hud.rejectCount, expectedReject, "HUD reject count drifted", file: file, line: line)
        XCTAssertEqual(hud.undecidedCount, expectedUndecided, "HUD undecided count drifted", file: file, line: line)
    }

    /// The Cull lens' scope line must report the catalog's session-wide
    /// confirmed pick/reject totals. Its "left" count is asserted against the
    /// documented invariant `total - hiddenByLens - reviewed` (already clamped
    /// at 0): that number folds in session-only skip/view state, so no plain
    /// catalog query can answer it. The stack segment comes from
    /// `AppModel.cullingStackListEntries()`, which the scope line itself uses;
    /// it is empty outside a persisted stack session.
    func assertCullScopeLineMatchesCatalog(
        _ model: AppModel,
        repository: CatalogRepository,
        query: SetQuery = SetQuery(predicates: []),
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(
            model.selectedLens, .cull,
            "the scope line only carries cull progress in the Cull lens",
            file: file, line: line
        )
        let expectedPick = try repository.assetCount(matching: query, confirmedFlag: .pick)
        let expectedReject = try repository.assetCount(matching: query, confirmedFlag: .reject)

        let scopeLine = model.scopeLine
        XCTAssertTrue(
            scopeLine.statusText.contains("✓ \(expectedPick) ·"),
            "scope line must report the catalog's confirmed session picks (\(expectedPick)); got \(scopeLine.statusText)",
            file: file, line: line
        )
        XCTAssertTrue(
            scopeLine.statusText.contains("✕ \(expectedReject) ·"),
            "scope line must report the catalog's confirmed session rejects (\(expectedReject)); got \(scopeLine.statusText)",
            file: file, line: line
        )

        // Documented invariant — not a catalog query (session skip/view state).
        let summary = model.cullingProgressSummary
        let expectedLeft = max(summary.totalCount - summary.hiddenByLensCount - summary.reviewedCount, 0)
        XCTAssertTrue(
            scopeLine.statusText.hasSuffix("\(expectedLeft) left"),
            "scope line's left count must equal total - hidden - reviewed (\(expectedLeft)); got \(scopeLine.statusText)",
            file: file, line: line
        )

        let stackEntries = model.cullingStackListEntries()
        XCTAssertEqual(
            scopeLine.statusText.contains("stack"),
            !stackEntries.isEmpty,
            "the scope line's stack segment must track cullingStackListEntries(); got \(scopeLine.statusText)",
            file: file, line: line
        )
        if !stackEntries.isEmpty {
            XCTAssertTrue(
                scopeLine.statusText.contains("\(stackEntries.count) stack"),
                "scope line's stack count must equal cullingStackListEntries().count (\(stackEntries.count)); got \(scopeLine.statusText)",
                file: file, line: line
            )
        }
    }

    /// The culling stack rail's "Stack N of M" must equal a partition rebuilt
    /// from the VISIBLE (scope-filtered) assets — the same set the run strip
    /// counts — never the unfiltered partition. Rebuilds the rail exactly as
    /// `LoupeView.cullingStackPresentation` does.
    func assertCullingStackRailMatchesScopedPartition(
        _ model: AppModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scopedAssets = CullScopeOrdering.filteredAssets(model.assets, scope: model.cullScope)
        let multiFrameStacks = model.allCullingStacks(for: scopedAssets).filter { $0.assetIDs.count > 1 }

        let rail = CullingStackRailPresentation(
            assets: model.assets,
            selectedAssetID: model.selectedAssetID,
            evaluationSignalsByAssetID: model.selectedCullingStackEvaluationSignals(),
            explicitStackScope: model.selectedCullingStackScope,
            stackBuilder: model.stackBuilder(),
            precomputedAllStacks: model.cachedAllCullingStacksForPresentation()
        )

        guard let selectedAssetID = model.selectedAssetID else {
            XCTAssertEqual(rail.titleText, "", "no selection means no rail", file: file, line: line)
            return
        }
        if let index = multiFrameStacks.firstIndex(where: { $0.assetIDs.contains(selectedAssetID) }) {
            XCTAssertEqual(
                rail.titleText, "Stack \(index + 1) of \(multiFrameStacks.count)",
                "rail's stack counter must reflect the scope-filtered partition for \(model.cullScope); got \(rail.titleText)",
                file: file, line: line
            )
        } else {
            XCTAssertEqual(
                rail.titleText, "Standalone",
                "a frame with no in-scope burst-mates must read as Standalone; got \(rail.titleText)",
                file: file, line: line
            )
        }
    }

    /// The People lens must list exactly the confirmed people a fresh
    /// `person_assets` read returns for the lens' scope — a person the catalog
    /// still holds (or an assigned one it now holds) can never vanish from the
    /// lens, and the presentation's rows must match the list.
    func assertPeopleLensMatchesCatalog(
        _ model: AppModel,
        repository: CatalogRepository,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let scope = try model.peopleScopeAssetIDs()
        let expected = try repository.people(assetIDs: scope)
        XCTAssertEqual(
            model.peopleInCurrentSource.map(\.id), expected.map(\.id),
            "People-lens ids drifted from the catalog's scoped person_assets read",
            file: file, line: line
        )
        XCTAssertEqual(
            model.peopleInCurrentSource, expected,
            "People-lens rows drifted from the catalog's scoped person_assets read",
            file: file, line: line
        )
        let presentation = PeoplePresentation(model: model)
        XCTAssertEqual(
            presentation.namedPeople.map(\.id), expected.map(\.id),
            "People-lens presentation rows drifted from the catalog",
            file: file, line: line
        )
    }

    /// The Library result header's match count must equal a fresh repository
    /// count for the model's live search query, and the presentation must
    /// render that same count. `librarySearchText` must be the only active
    /// filter for the reconstructed query to be exact.
    func assertLibraryResultHeaderMatchesCatalog(
        _ model: AppModel,
        repository: CatalogRepository,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let query = catalogQuery(matchingSearchText: model.librarySearchText)
        let expected = try repository.assetCount(matching: query)
        XCTAssertEqual(
            model.totalAssetCount, expected,
            "the loaded search result count drifted from the catalog for \(model.librarySearchText)",
            file: file, line: line
        )
        let header = LibraryResultHeaderPresentation(
            totalAssetCount: model.totalAssetCount,
            librarySearchText: model.librarySearchText,
            canSaveDynamicSet: model.canSaveCurrentLibraryQuery,
            canSaveSnapshotSet: model.canSaveCurrentAssetScopeSnapshot,
            canSaveManualSet: model.canSaveSelectedAssetAsManualSet
        )
        XCTAssertEqual(
            header.matchCount, expected,
            "the result header's match count drifted from the catalog for \(model.librarySearchText)",
            file: file, line: line
        )
    }
}
