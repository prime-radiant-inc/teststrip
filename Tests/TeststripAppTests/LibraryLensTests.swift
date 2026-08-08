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

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-library-lens-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }
}
