import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// Covers `AppModel.buildSidebarSections()` - one sidebar shared by every
/// lens. Section composition (which rows, in which section, with which
/// counts) is pinned exhaustively in `UnifiedSidebarPresentationTests`
/// against the pure builder; this file exercises the same builder through a
/// live `AppModel` so catalog-backed inputs (saved queries, folders) are
/// wired in correctly.
final class SidebarSectionsTests: XCTestCase {
    func testFreshlyLoadedSidebarKeepsEmptyCreationSections() throws {
        let (model, _) = try makeModelWithCatalogAssets(named: "sidebar-sections-empty", assets: [])

        let sections = model.sidebarSections

        XCTAssertEqual(sections.map(\.title), ["Library", "Smart Collections", "Sets"])
        let smartCollections = try XCTUnwrap(
            sections.first { $0.title == UnifiedSidebarPresentation.smartCollectionsSectionTitle }
        )
        let sets = try XCTUnwrap(
            sections.first { $0.title == UnifiedSidebarPresentation.setsSectionTitle }
        )
        XCTAssertTrue(smartCollections.rows.isEmpty)
        XCTAssertTrue(sets.rows.isEmpty)
    }

    func testSidebarSectionsAreTheUnifiedShellsSections() throws {
        let asset = makeAsset(id: "hero", path: "/Photos/hero.jpg", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(named: "sidebar-sections-unified", assets: [asset])
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()
        _ = try model.saveCurrentLibraryQuery(named: "Five Stars", starred: false)
        model.catalogFolders = [CatalogFolder(path: "photos", name: "photos", assetCount: 1)]

        let sections = model.buildSidebarSections()

        XCTAssertEqual(sections.first?.title, "Library")
        XCTAssertEqual(sections.first?.rows.first?.title, "All Photos")
        XCTAssertEqual(sections.first?.rows.first?.target, LibrarySource.allPhotos)

        // A saved dynamic search is a smart collection, not a static set.
        let smart = try XCTUnwrap(sections.first { $0.title == "Smart Collections" })
        XCTAssertTrue(smart.rowTitles.contains("Five Stars"))
        let sets = try XCTUnwrap(sections.first { $0.title == "Sets" })
        XCTAssertTrue(sets.rows.isEmpty)

        let folders = try XCTUnwrap(sections.first { $0.title == "Folders" })
        XCTAssertEqual(folders.rowTitles, ["photos"])
    }

    func testTheSidebarIsTheSameInEveryLens() {
        let model = AppModel.demo()
        let expected = model.sidebarSections.map(\.title)

        for lens in LibraryLens.allCases {
            model.selectLens(lens)
            XCTAssertEqual(model.sidebarSections.map(\.title), expected, "\(lens)")
        }
    }

    func testSavedSetContextMenuActionsStillResolveUnderTheNewSidebarShape() throws {
        let asset = makeAsset(id: "hero", path: "/Photos/hero.jpg", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(named: "sidebar-sections-context-menu", assets: [asset])
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()
        let savedSet = try model.saveCurrentLibraryQuery(named: "Five Stars", starred: true)

        let smartCollections = try XCTUnwrap(model.buildSidebarSections().first { $0.title == "Smart Collections" })
        let starredRow = try XCTUnwrap(smartCollections.rows.first { $0.target == .assetSet(savedSet.id, titled: savedSet.name) })
        let actions = model.sidebarContextActions(for: starredRow)

        XCTAssertTrue(actions.contains { $0.kind == .renameAssetSet(savedSet.id) })
        XCTAssertTrue(actions.contains { $0.kind == .duplicateAssetSet(savedSet.id) })
        XCTAssertTrue(actions.contains { $0.kind == .freezeAssetSetSnapshot(savedSet.id) })
        XCTAssertTrue(actions.contains { $0.kind == .toggleAssetSetStarred(savedSet.id) })
        XCTAssertTrue(actions.contains { $0.kind == .deleteAssetSet(savedSet.id) })
    }

    private func makeAsset(id: String, path: String, rating: Int) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Test",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(rating: rating)
        )
    }
}
