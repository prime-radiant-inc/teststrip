import AppKit
import XCTest
@testable import TeststripApp

final class FolderSelectionPanelTests: XCTestCase {
    @MainActor
    func testImportFolderPanelChoosesDirectoriesOnly() throws {
        let panel = NSOpenPanel()
        let startingDirectory = try makeTemporaryDirectory(named: "import-start")

        FolderSelectionPanel.configureImportFolderPanel(panel, startingDirectory: startingDirectory)

        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertFalse(panel.canCreateDirectories)
        XCTAssertEqual(panel.prompt, "Import Folder")
        XCTAssertEqual(panel.message, "Select a folder of photos. If you open it first, Import Folder uses the current folder.")
        XCTAssertEqual(panel.directoryURL?.standardizedFileURL, startingDirectory.standardizedFileURL)
    }

    @MainActor
    func testCardSourcePanelChoosesDirectoriesOnly() throws {
        let panel = NSOpenPanel()
        let startingDirectory = try makeTemporaryDirectory(named: "card-source-start")

        FolderSelectionPanel.configureCardSourcePanel(panel, startingDirectory: startingDirectory)

        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertFalse(panel.canCreateDirectories)
        XCTAssertEqual(panel.prompt, "Choose Source")
        XCTAssertEqual(panel.message, "Select the card or camera folder. If you open it first, Choose Source uses the current folder.")
        XCTAssertEqual(panel.directoryURL?.standardizedFileURL, startingDirectory.standardizedFileURL)
    }

    @MainActor
    func testCardDestinationPanelChoosesOneCreatableDirectory() throws {
        let panel = NSOpenPanel()
        let startingDirectory = try makeTemporaryDirectory(named: "card-destination-start")

        FolderSelectionPanel.configureCardDestinationPanel(panel, startingDirectory: startingDirectory)

        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertTrue(panel.canCreateDirectories)
        XCTAssertEqual(panel.prompt, "Choose Destination")
        XCTAssertEqual(panel.message, "Select where copied photos should be stored. If you open it first, Choose Destination uses the current folder.")
        XCTAssertEqual(panel.directoryURL?.standardizedFileURL, startingDirectory.standardizedFileURL)
    }

    @MainActor
    func testRememberedImportFolderStartsNextChooserAtParentDirectory() throws {
        let defaults = try makeDefaults()
        let parent = try makeTemporaryDirectory(named: "remember-import-parent")
        let selectedFolder = parent.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: selectedFolder, withIntermediateDirectories: true)

        FolderSelectionPanel.rememberImportFolder(selectedFolder, defaults: defaults)

        XCTAssertEqual(FolderSelectionPanel.startingImportDirectory(defaults: defaults)?.standardizedFileURL, parent.standardizedFileURL)
    }

    @MainActor
    func testRememberedCardFoldersStartNextChoosersAtParentDirectories() throws {
        let defaults = try makeDefaults()
        let sourceParent = try makeTemporaryDirectory(named: "remember-card-source-parent")
        let source = sourceParent.appendingPathComponent("card", isDirectory: true)
        let destinationParent = try makeTemporaryDirectory(named: "remember-card-destination-parent")
        let destination = destinationParent.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        FolderSelectionPanel.rememberCardSourceFolder(source, defaults: defaults)
        FolderSelectionPanel.rememberCardDestinationFolder(destination, defaults: defaults)

        XCTAssertEqual(FolderSelectionPanel.startingCardSourceDirectory(defaults: defaults)?.standardizedFileURL, sourceParent.standardizedFileURL)
        XCTAssertEqual(FolderSelectionPanel.startingCardDestinationDirectory(defaults: defaults)?.standardizedFileURL, destinationParent.standardizedFileURL)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-folder-panel-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "teststrip.folder-panel.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "FolderSelectionPanelTests", code: 1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
