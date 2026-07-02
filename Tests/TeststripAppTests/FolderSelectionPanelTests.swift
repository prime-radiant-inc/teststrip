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

    @MainActor
    func testCardSourcePanelChoosesDirectoriesOnly() throws {
        let panel = NSOpenPanel()

        FolderSelectionPanel.configureCardSourcePanel(panel)

        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertFalse(panel.canCreateDirectories)
        XCTAssertEqual(panel.prompt, "Choose")
        XCTAssertEqual(panel.message, "Choose the card or camera folder to copy photos from.")
    }

    @MainActor
    func testCardDestinationPanelChoosesOneCreatableDirectory() throws {
        let panel = NSOpenPanel()

        FolderSelectionPanel.configureCardDestinationPanel(panel)

        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertTrue(panel.canCreateDirectories)
        XCTAssertEqual(panel.prompt, "Choose")
        XCTAssertEqual(panel.message, "Choose where copied photos should be stored.")
    }
}
