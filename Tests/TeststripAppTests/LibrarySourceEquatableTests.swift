import XCTest
@testable import TeststripCore
@testable import TeststripApp

// A source's identity is its `kind` — the set of photos it names — not its
// `title`. Two sources with the same kind but different titles (e.g. a work
// session constructed from different code paths) must compare equal so that
// nav-history dedupe and `LibraryQueryToken.legacyRows` don't double-render or
// create spurious back-stack entries.
final class LibrarySourceEquatableTests: XCTestCase {
    func testSameKindDifferentTitlesAreEqual() {
        let sessionID = WorkSessionID(rawValue: "import-1")
        let a = LibrarySource.workSession(sessionID, titled: "Card A Cull")
        let b = LibrarySource.workSession(sessionID, titled: "Card B Cull")

        XCTAssertEqual(a, b, "sources with the same kind but different titles must be equal")
    }

    func testSameKindSameTitlesAreEqual() {
        let a = LibrarySource.allPhotos
        let b = LibrarySource.allPhotos
        XCTAssertEqual(a, b)
    }

    func testDifferentKindsAreUnequal() {
        let a = LibrarySource.allPhotos
        let b = LibrarySource.autopilotSuggestions
        XCTAssertNotEqual(a, b)
    }

    func testWorkSessionWithDifferentIDsAreUnequal() {
        let a = LibrarySource.workSession(WorkSessionID(rawValue: "s1"), titled: "Session 1")
        let b = LibrarySource.workSession(WorkSessionID(rawValue: "s2"), titled: "Session 1")
        XCTAssertNotEqual(a, b)
    }

    func testAssetSetWithDifferentIDsAreUnequal() {
        let a = LibrarySource.assetSet(AssetSetID(rawValue: "set-1"), titled: "Keepers")
        let b = LibrarySource.assetSet(AssetSetID(rawValue: "set-2"), titled: "Keepers")
        XCTAssertNotEqual(a, b)
    }

    func testImportChildWithDifferentSessionsAreUnequal() {
        let s1 = WorkSessionID(rawValue: "s1")
        let s2 = WorkSessionID(rawValue: "s2")
        let a = LibrarySource.importChild(session: s1, child: .stacks)
        let b = LibrarySource.importChild(session: s2, child: .stacks)
        XCTAssertNotEqual(a, b)
    }

    func testImportChildWithDifferentChildrenAreUnequal() {
        let session = WorkSessionID(rawValue: "s1")
        let a = LibrarySource.importChild(session: session, child: .stacks)
        let b = LibrarySource.importChild(session: session, child: .skippedFiles)
        XCTAssertNotEqual(a, b)
    }
}
