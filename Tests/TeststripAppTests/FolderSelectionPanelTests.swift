import AppKit
import XCTest
@testable import TeststripApp

final class FolderSelectionPanelTests: XCTestCase {
    @MainActor
    func testImportFolderPanelChoosesDirectoriesOnly() throws {
        let panel = NSOpenPanel()

        FolderSelectionPanel.configureImportFolderPanel(panel)

        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertFalse(panel.canCreateDirectories)
        XCTAssertEqual(panel.prompt, "Import")
        XCTAssertEqual(panel.message, "Choose a folder of photos to import.")
    }
}
