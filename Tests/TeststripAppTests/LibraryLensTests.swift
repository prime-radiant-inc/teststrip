import XCTest
import SwiftUI
@testable import TeststripCore
@testable import TeststripApp

// Six lenses over one source, ⌘1–⌘6 in the same order. The Cull|Library
// workspace split is gone; Compare/A-B/cull-grid stay transient sub-modes of
// the Cull lens rather than becoming lenses of their own.
final class LibraryLensTests: XCTestCase {
    func testLensOrderTitlesAndKeyEquivalents() {
        XCTAssertEqual(LibraryLens.allCases, [.cull, .grid, .loupe, .timeline, .map, .people])
        XCTAssertEqual(LibraryLens.allCases.map(\.title), ["Cull", "Grid", "Loupe", "Timeline", "Map", "People"])
        XCTAssertEqual(
            LibraryLens.allCases.map(\.keyEquivalent),
            [KeyEquivalent("1"), KeyEquivalent("2"), KeyEquivalent("3"), KeyEquivalent("4"), KeyEquivalent("5"), KeyEquivalent("6")]
        )
    }

    func testEveryViewModeMapsToExactlyOneLens() {
        for mode in LibraryViewMode.allCases {
            _ = mode.lens // exhaustive switch compiles = every mode owned
        }
        XCTAssertEqual(LibraryViewMode.loupe.lens, .cull)
        XCTAssertEqual(LibraryViewMode.compare.lens, .cull)
        XCTAssertEqual(LibraryViewMode.abCompare.lens, .cull)
        XCTAssertEqual(LibraryViewMode.cullGrid.lens, .cull)
        XCTAssertEqual(LibraryViewMode.grid.lens, .grid)
        XCTAssertEqual(LibraryViewMode.libraryLoupe.lens, .loupe)
        XCTAssertEqual(LibraryViewMode.timeline.lens, .timeline)
        XCTAssertEqual(LibraryViewMode.map.lens, .map)
        XCTAssertEqual(LibraryViewMode.people.lens, .people)
    }

    func testEveryLensRoundTripsThroughItsDefaultViewMode() {
        for lens in LibraryLens.allCases {
            XCTAssertEqual(lens.defaultViewMode.lens, lens, "\(lens)")
        }
    }

    func testCullIsDisabledOnDiagnosticAndEmptySourcesOnly() {
        let onDiagnostic = LensRules.availability(for: .cull, sourceIsDiagnostic: true, sourceAssetCount: 12)
        XCTAssertFalse(onDiagnostic.isEnabled)
        XCTAssertEqual(onDiagnostic.disabledReason, "Nothing here is cullable")

        let onEmpty = LensRules.availability(for: .cull, sourceIsDiagnostic: false, sourceAssetCount: 0)
        XCTAssertFalse(onEmpty.isEnabled)
        XCTAssertEqual(onEmpty.disabledReason, "No photos to cull")

        let onNormal = LensRules.availability(for: .cull, sourceIsDiagnostic: false, sourceAssetCount: 3)
        XCTAssertTrue(onNormal.isEnabled)
        XCTAssertNil(onNormal.disabledReason)
    }

    func testEveryOtherLensIsEnabledEverywhere() {
        for lens in LibraryLens.allCases where lens != .cull {
            XCTAssertTrue(
                LensRules.availability(for: lens, sourceIsDiagnostic: true, sourceAssetCount: 0).isEnabled,
                "\(lens)"
            )
        }
    }

    func testAvailabilitiesCoverEveryLensInOrder() {
        let availabilities = LensRules.availabilities(sourceIsDiagnostic: true, sourceAssetCount: 0)
        XCTAssertEqual(availabilities.map(\.lens), LibraryLens.allCases)
        XCTAssertEqual(availabilities.filter { !$0.isEnabled }.map(\.lens), [.cull])
    }

    func testADisabledLensFallsBackToGrid() {
        XCTAssertEqual(LensRules.resolvedLens(.cull, sourceIsDiagnostic: true, sourceAssetCount: 5), .grid)
        XCTAssertEqual(LensRules.resolvedLens(.cull, sourceIsDiagnostic: false, sourceAssetCount: 0), .grid)
        XCTAssertEqual(LensRules.resolvedLens(.cull, sourceIsDiagnostic: false, sourceAssetCount: 5), .cull)
        XCTAssertEqual(LensRules.resolvedLens(.timeline, sourceIsDiagnostic: true, sourceAssetCount: 0), .timeline)
    }

    func testSelectingALensNeverChangesTheSource() throws {
        let picked = makeAsset(id: "lens-source-picked", path: "/Photos/picked.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "lens-never-changes-source", assets: [picked])
        let source = LibrarySource.smartCollection(.picks)
        try model.selectSource(source)

        for lens in LibraryLens.allCases {
            model.selectLens(lens)
            XCTAssertEqual(model.selectedSource, source, "\(lens) changed the source")
        }
    }

    // Binding constraint: switching lenses never changes the selected source
    // *or the selection* — only selectedView (and its sub-mode memory) is
    // selectLens's business.
    func testSelectingALensNeverChangesTheSelection() {
        let model = AppModel.demo()
        let selectedAssetID = model.selectedAssetID

        for lens in LibraryLens.allCases {
            model.selectLens(lens)
            XCTAssertEqual(model.selectedAssetID, selectedAssetID, "\(lens) changed the selection")
        }
    }

    func testSelectingACullSubModeThenReenteringCullReturnsToIt() {
        let model = AppModel.demo()
        model.selectLens(.cull)
        XCTAssertEqual(model.selectedView, .loupe)

        model.selectedView = .cullGrid
        model.selectLens(.timeline)
        XCTAssertEqual(model.selectedView, .timeline)

        model.selectLens(.cull)
        XCTAssertEqual(model.selectedView, .cullGrid)
    }

    // The ⌘1 dead-key root cause: Compare/A-B are transient comparator
    // overlays, not a "home" sub-mode — re-entering the Cull lens must escape
    // the trap, not restore it.
    func testReenteringCullNeverRestoresIntoCompareOrABCompare() {
        let model = AppModel.demo()
        model.selectedView = .loupe
        model.selectedView = .compare
        model.selectLens(.cull)
        XCTAssertEqual(model.selectedView, .loupe)

        model.selectedView = .abCompare
        model.selectLens(.cull)
        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testCullEntryCommandsAreNoOpsOnANonemptyDiagnosticSource() throws {
        let asset = makeAsset(id: "diagnostic-command", path: "/Photos/diagnostic.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "diagnostic-command",
            assets: [asset]
        )
        try repository.recordEvaluationFailure(
            assetID: asset.id,
            provider: "local-http-model",
            message: "model timed out"
        )
        model.selectedView = .loupe
        model.selectedView = .timeline
        try model.selectSource(.smartCollection(.providerFailures))
        model.setBatchSelection(asset.id, isSelected: true)

        XCTAssertEqual(model.assets.map(\.id), [asset.id], "diagnostic fixture must be nonempty")
        try assertUnavailableCullEntryCommandsAreNoOps(model)
    }

    func testCullEntryCommandsAreNoOpsOnAnEmptyOrdinarySource() throws {
        let asset = makeAsset(id: "empty-command", path: "/Photos/Somewhere/photo.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "empty-command", assets: [asset])
        model.selectedView = .loupe
        model.selectedView = .timeline
        try model.selectSource(.folder("/Photos/Nowhere"))

        XCTAssertFalse(model.selectedSource.isDiagnostic, "fixture must exercise ordinary-source emptiness")
        XCTAssertTrue(model.assets.isEmpty, "ordinary source fixture must be empty")
        try assertUnavailableCullEntryCommandsAreNoOps(model)
    }

    func testCullEntryCommandsEnterTheirModesOnANonemptyOrdinarySource() throws {
        let asset = makeAsset(id: "cullable-command", path: "/Photos/cullable.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "cullable-command", assets: [asset])
        model.selectedView = .timeline

        for command in cullEntryCommands() {
            try command.apply(model)
            XCTAssertEqual(model.selectedView, command.expectedView, command.name)
            XCTAssertEqual(model.selectedLens, .cull, command.name)
            model.selectedView = .timeline
        }
    }

    func testLoupePresentationChromeFlagByMode() {
        XCTAssertTrue(LoupePresentation(mode: .loupe).showsCullChrome)
        XCTAssertFalse(LoupePresentation(mode: .libraryLoupe).showsCullChrome)
    }

    // MARK: - Fixtures

    private func makeAsset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(flag: .pick)
        )
    }

    private func assertUnavailableCullEntryCommandsAreNoOps(_ model: AppModel) throws {
        let cullAvailability = try XCTUnwrap(model.lensAvailabilities.first { $0.lens == .cull })
        XCTAssertFalse(cullAvailability.isEnabled)
        let state = navigationState(of: model)

        for command in cullEntryCommands() {
            try command.apply(model)
            XCTAssertEqual(navigationState(of: model), state, command.name)
            model.selectedView = state.view
        }

        try model.selectSource(.allPhotos)
        model.selectLens(.cull)
        XCTAssertEqual(model.selectedView, .loupe, "rejected commands changed the remembered Cull mode")
    }

    private func navigationState(of model: AppModel) -> NavigationState {
        NavigationState(
            view: model.selectedView,
            lens: model.selectedLens,
            source: model.selectedSource,
            assetIDs: model.assets.map(\.id),
            selectedAssetID: model.selectedAssetID,
            selectedBatchAssetIDs: model.selectedBatchAssetIDs
        )
    }

    private func cullEntryCommands() -> [CullEntryCommand] {
        [
            CullEntryCommand(name: "selectLens(.cull)", expectedView: .loupe) { $0.selectLens(.cull) },
            CullEntryCommand(name: "selectCullSubMode(.loupe)", expectedView: .loupe) {
                $0.selectCullSubMode(.loupe)
            },
            CullEntryCommand(name: "selectCullSubMode(.cullGrid)", expectedView: .cullGrid) {
                $0.selectCullSubMode(.cullGrid)
            },
            CullEntryCommand(name: "selectCullSubMode(.compare)", expectedView: .compare) {
                $0.selectCullSubMode(.compare)
            },
            CullEntryCommand(name: "selectCullSubMode(.abCompare)", expectedView: .abCompare) {
                $0.selectCullSubMode(.abCompare)
            },
            CullEntryCommand(name: "applyCullingShortcut(.showCompare)", expectedView: .compare) {
                try $0.applyCullingShortcut(.showCompare)
            },
            CullEntryCommand(name: "applyCullingShortcut(.showABCompare)", expectedView: .abCompare) {
                try $0.applyCullingShortcut(.showABCompare)
            },
            CullEntryCommand(name: "applyCullingShortcut(.exitCullSubView)", expectedView: .loupe) {
                try $0.applyCullingShortcut(.exitCullSubView)
            },
            CullEntryCommand(name: "applyGridKeyCommand(.switchCullSubView(.compare))", expectedView: .compare) {
                try $0.applyGridKeyCommand(.switchCullSubView(.compare), columns: 4)
            },
            CullEntryCommand(name: "applyCullingShortcut(.showCullGrid)", expectedView: .cullGrid) {
                try $0.applyCullingShortcut(.showCullGrid)
            }
        ]
    }
}

private struct NavigationState: Equatable {
    var view: LibraryViewMode
    var lens: LibraryLens
    var source: LibrarySource
    var assetIDs: [AssetID]
    var selectedAssetID: AssetID?
    var selectedBatchAssetIDs: Set<AssetID>
}

private struct CullEntryCommand {
    var name: String
    var expectedView: LibraryViewMode
    var apply: (AppModel) throws -> Void
}
