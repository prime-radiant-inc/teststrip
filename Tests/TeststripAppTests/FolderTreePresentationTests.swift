import XCTest
import TeststripCore
@testable import TeststripApp

final class FolderTreePresentationTests: XCTestCase {
    func testEmptyFolderListProducesNoNodes() {
        XCTAssertEqual(FolderTreePresentation.build(from: []), [])
    }

    func testCollapsesSharedSingleChildAncestorChainIntoOneRootRow() {
        // "/Volumes/NAS/" has exactly one child ("Wedding" branches, but the
        // Volumes -> NAS chain above it has no photos of its own and no
        // sibling directories) so it should read as a single top-level row
        // named after its deepest merged segment ("NAS"), not two meaningless
        // expand clicks through "Volumes" then "NAS".
        let folders = [
            CatalogFolder(path: "/Volumes/NAS/Travel/", name: "Travel", assetCount: 1),
            CatalogFolder(path: "/Volumes/NAS/Wedding/Ceremony/", name: "Ceremony", assetCount: 1),
            CatalogFolder(path: "/Volumes/NAS/Wedding/Portraits/", name: "Portraits", assetCount: 1)
        ]

        let tree = FolderTreePresentation.build(from: folders)

        XCTAssertEqual(tree.map(\.title), ["NAS"])
        let root = tree[0]
        XCTAssertEqual(root.fullPath, "/Volumes/NAS/")
        XCTAssertEqual(root.assetCount, 3)
        XCTAssertTrue(root.hasChildren)

        XCTAssertEqual(root.children.map(\.title), ["Travel", "Wedding"])
        let travel = root.children[0]
        XCTAssertEqual(travel.fullPath, "/Volumes/NAS/Travel/")
        XCTAssertEqual(travel.assetCount, 1)
        XCTAssertFalse(travel.hasChildren)

        let wedding = root.children[1]
        XCTAssertEqual(wedding.fullPath, "/Volumes/NAS/Wedding/")
        XCTAssertEqual(wedding.assetCount, 2)
        XCTAssertEqual(wedding.children.map(\.title), ["Ceremony", "Portraits"])
        XCTAssertEqual(wedding.children.map(\.fullPath), [
            "/Volumes/NAS/Wedding/Ceremony/",
            "/Volumes/NAS/Wedding/Portraits/"
        ])
        XCTAssertEqual(wedding.children.map(\.assetCount), [1, 1])
    }

    func testCollapsesEntireSingleChildChainDownToASoleLeafFolder() {
        // A catalog with photos filed under one long unbranched path (the
        // common case right after a fresh import into an empty catalog)
        // should show as exactly one row, not one row per path segment.
        let folders = [
            CatalogFolder(path: "/Volumes/NAS/Photos/2024/2024-05-01/", name: "2024-05-01", assetCount: 42)
        ]

        let tree = FolderTreePresentation.build(from: folders)

        XCTAssertEqual(tree.count, 1)
        XCTAssertEqual(tree[0].title, "2024-05-01")
        XCTAssertEqual(tree[0].fullPath, "/Volumes/NAS/Photos/2024/2024-05-01/")
        XCTAssertEqual(tree[0].assetCount, 42)
        XCTAssertEqual(tree[0].children, [])
    }

    func testDoesNotMergePastAFolderThatDirectlyHoldsPhotosEvenWithASingleSubfolder() {
        // "Wedding" itself holds photos directly (not just its "Ceremony"
        // subfolder), so it must remain its own selectable row even though
        // it has only one child - merging it away would make those direct
        // photos inaccessible as their own scope.
        let folders = [
            CatalogFolder(path: "/Root/Wedding/", name: "Wedding", assetCount: 3),
            CatalogFolder(path: "/Root/Wedding/Ceremony/", name: "Ceremony", assetCount: 2)
        ]

        let tree = FolderTreePresentation.build(from: folders)

        // "Root" has no photos of its own and a single child, so it merges
        // forward into "Wedding" (which does hold its own photos and stops
        // the merge there).
        XCTAssertEqual(tree.map(\.title), ["Wedding"])
        let wedding = tree[0]
        XCTAssertEqual(wedding.fullPath, "/Root/Wedding/")
        XCTAssertEqual(wedding.assetCount, 5)
        XCTAssertEqual(wedding.children.map(\.title), ["Ceremony"])
        XCTAssertEqual(wedding.children[0].assetCount, 2)
    }

    func testAggregatesCountsAcrossMultipleNestedBranches() {
        let folders = [
            CatalogFolder(path: "/Lib/2024/2024-01-01/", name: "2024-01-01", assetCount: 10),
            CatalogFolder(path: "/Lib/2024/2024-06-01/", name: "2024-06-01", assetCount: 5),
            CatalogFolder(path: "/Lib/2023/2023-06-01/", name: "2023-06-01", assetCount: 7),
            CatalogFolder(path: "/Lib/2023/2023-12-25/", name: "2023-12-25", assetCount: 20)
        ]

        let tree = FolderTreePresentation.build(from: folders)

        XCTAssertEqual(tree.map(\.title), ["Lib"])
        let lib = tree[0]
        XCTAssertEqual(lib.assetCount, 42)
        XCTAssertEqual(lib.children.map(\.title), ["2023", "2024"])
        let year2023 = lib.children[0]
        let year2024 = lib.children[1]
        XCTAssertEqual(year2023.assetCount, 27)
        XCTAssertEqual(year2024.assetCount, 15)
        XCTAssertEqual(year2023.children.map(\.title), ["2023-06-01", "2023-12-25"])
        XCTAssertEqual(year2023.children.map(\.assetCount), [7, 20])
        XCTAssertEqual(year2024.children.map(\.title), ["2024-01-01", "2024-06-01"])
        XCTAssertEqual(year2024.children.map(\.assetCount), [10, 5])
    }

    func testSortsSiblingsInLocalizedStandardOrderNotLexicographic() {
        let folders = [
            CatalogFolder(path: "/Lib/Shoot 10/", name: "Shoot 10", assetCount: 1),
            CatalogFolder(path: "/Lib/Shoot 2/", name: "Shoot 2", assetCount: 1),
            CatalogFolder(path: "/Lib/Shoot 1/", name: "Shoot 1", assetCount: 1)
        ]

        let tree = FolderTreePresentation.build(from: folders)

        XCTAssertEqual(tree[0].children.map(\.title), ["Shoot 1", "Shoot 2", "Shoot 10"])
    }

    func testCapsSiblingRowsPerLevelSoAWideDirectoryCannotFloodTheSidebar() {
        let folders = (0..<(FolderTreePresentation.maxRowsPerLevel + 20)).map { index in
            CatalogFolder(
                path: "/Lib/Shoot-\(String(format: "%03d", index))/",
                name: "Shoot-\(index)",
                assetCount: 1
            )
        }

        let tree = FolderTreePresentation.build(from: folders)

        XCTAssertEqual(tree[0].children.count, FolderTreePresentation.maxRowsPerLevel)
    }

    func testDuplicateLeafEntriesForTheSamePathCombineTheirCounts() {
        // folders() is expected to return one row per distinct path, but the
        // builder should stay correct (rather than silently drop data) if
        // that ever changes.
        let folders = [
            CatalogFolder(path: "/Lib/Shoot/", name: "Shoot", assetCount: 2),
            CatalogFolder(path: "/Lib/Shoot/", name: "Shoot", assetCount: 3)
        ]

        let tree = FolderTreePresentation.build(from: folders)

        XCTAssertEqual(tree[0].assetCount, 5)
    }
}
