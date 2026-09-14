import XCTest
import TeststripCore
@testable import TeststripApp

/// The sidebar's `List(selection:)` only becomes a real source list — an
/// `AXOutline` with a selected-rows model that Down/Up can walk — if the two
/// directions of the selection mapping are correct. Both are pure, so they are
/// pinned here; the live behaviour (arrow keys moving the highlight, and the
/// grid monitor no longer swallowing those keys) is verified with the AX
/// scenario cards.
final class SidebarKeyboardSelectionTests: XCTestCase {
    private func sections() -> [SidebarSection] {
        [
            SidebarSection(title: "Library", rows: [
                SidebarRow(id: "library-all", title: "All Photos", target: .allPhotos)
            ]),
            SidebarSection(title: "Smart Collections", rows: [
                SidebarRow(id: "smart-picks", title: "Picks", target: .smartCollection(.picks)),
                // No target: the running-import narration is rendered but is
                // not a scope to select.
                SidebarRow(id: "import-running-1", title: "Importing…")
            ]),
            SidebarSection(title: "Sets", rows: [
                SidebarRow(
                    id: "asset-set-smoke-picks",
                    title: "Smoke Picks",
                    target: LibrarySource(
                        kind: .assetSet(AssetSetID(rawValue: "smoke-picks")),
                        title: "Smoke Picks"
                    )
                )
            ])
        ]
    }

    func testRowIDResolvesTheRowThatScopesToASource() {
        XCTAssertEqual(SidebarSelection.rowID(for: .allPhotos, in: sections()), "library-all")
        XCTAssertEqual(
            SidebarSelection.rowID(for: .smartCollection(.picks), in: sections()),
            "smart-picks"
        )
    }

    // `LibrarySource.==` compares only the kind, so a work session or saved set
    // constructed on a different code path still highlights its row.
    func testRowIDIgnoresTheDisplayTitle() {
        let source = LibrarySource(
            kind: .assetSet(AssetSetID(rawValue: "smoke-picks")),
            title: "Some other title"
        )
        XCTAssertEqual(SidebarSelection.rowID(for: source, in: sections()), "asset-set-smoke-picks")
    }

    func testRowIDIsNilWhenNoRowNamesTheSource() {
        XCTAssertNil(SidebarSelection.rowID(for: LibrarySource.search(Self.query(), titled: "x"), in: sections()))
        XCTAssertNil(SidebarSelection.rowID(for: .selection, in: sections()))
    }

    func testRowLookupRoundTripsEverySelectableRow() {
        for section in sections() {
            for row in section.rows {
                XCTAssertEqual(SidebarSelection.row(forID: row.id, in: sections())?.id, row.id)
            }
        }
    }

    func testRowLookupIsNilForAStaleID() {
        XCTAssertNil(SidebarSelection.row(forID: "asset-set-deleted", in: sections()))
    }

    func testCullStackRowIDRoundTrips() {
        let setID = AssetSetID(rawValue: "cull-stack-42")
        let tag = SidebarSelection.cullStackRowID(forSetID: setID)
        XCTAssertEqual(SidebarSelection.cullStackSetID(fromRowID: tag), setID)
    }

    // The stack namespace must not swallow a real source row's id, or selecting
    // a set would be reinterpreted as selecting a stack.
    func testSourceRowIDsAreNotMistakenForCullStackTags() {
        XCTAssertNil(SidebarSelection.cullStackSetID(fromRowID: "library-all"))
        XCTAssertNil(SidebarSelection.cullStackSetID(fromRowID: "asset-set-smoke-picks"))
        XCTAssertNil(SidebarSelection.cullStackSetID(fromRowID: SidebarSelection.cullStackRowIDPrefix))
    }

    private static func query() -> SetQuery {
        SetQuery(predicates: [])
    }
}
