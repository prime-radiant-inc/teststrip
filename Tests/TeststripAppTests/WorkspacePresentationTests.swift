import XCTest
import SwiftUI
@testable import TeststripApp

final class WorkspacePresentationTests: XCTestCase {
    func testWorkspaceTitleAndKeyEquivalent() {
        // People is no longer a top-level workspace: only Cull (⌘1) and
        // Library (⌘2) remain.
        XCTAssertEqual(Workspace.allCases, [.cull, .library])

        XCTAssertEqual(Workspace.cull.title, "Cull")
        XCTAssertEqual(Workspace.library.title, "Library")

        XCTAssertEqual(Workspace.cull.keyEquivalent, KeyEquivalent("1"))
        XCTAssertEqual(Workspace.library.keyEquivalent, KeyEquivalent("2"))
    }

    func testEveryViewModeMapsToExactlyOneWorkspace() {
        for mode in LibraryViewMode.allCases {
            _ = mode.workspace // exhaustive switch compiles = every mode owned
        }
        XCTAssertEqual(LibraryViewMode.loupe.workspace, .cull)
        XCTAssertEqual(LibraryViewMode.compare.workspace, .cull)
        XCTAssertEqual(LibraryViewMode.abCompare.workspace, .cull)
        XCTAssertEqual(LibraryViewMode.grid.workspace, .library)
        XCTAssertEqual(LibraryViewMode.timeline.workspace, .library)
        XCTAssertEqual(LibraryViewMode.map.workspace, .library)
        XCTAssertEqual(LibraryViewMode.libraryLoupe.workspace, .library)
        // People is a Library sub-view now, not its own workspace.
        XCTAssertEqual(LibraryViewMode.people.workspace, .library)
    }

    func testLoupePresentationChromeFlagByMode() {
        XCTAssertTrue(LoupePresentation(mode: .loupe).showsCullChrome)
        XCTAssertFalse(LoupePresentation(mode: .libraryLoupe).showsCullChrome)
    }

    func testSelectWorkspaceRestoresLastSubView() {
        let model = AppModel.demo()
        model.selectedView = .timeline
        model.selectWorkspace(.cull)
        XCTAssertEqual(model.selectedView, .loupe)
        model.selectedView = .cullGrid
        model.selectWorkspace(.library)
        XCTAssertEqual(model.selectedView, .timeline) // remembered
        model.selectWorkspace(.cull)
        XCTAssertEqual(model.selectedView, .cullGrid) // remembered
    }

    // Persona-3 item 1's ⌘1 root cause: .compare/.abCompare are transient
    // comparator overlays, not "home" sub-views — they must not become the
    // sticky restore target, or re-selecting the already-active workspace
    // (⌘1) silently re-enters the trap instead of escaping it.
    func testSelectWorkspaceDoesNotRestoreIntoCompareOrABCompare() {
        let model = AppModel.demo()
        model.selectedView = .loupe
        model.selectedView = .compare
        model.selectWorkspace(.cull)
        XCTAssertEqual(model.selectedView, .loupe)

        model.selectedView = .abCompare
        model.selectWorkspace(.cull)
        XCTAssertEqual(model.selectedView, .loupe)
    }
}
