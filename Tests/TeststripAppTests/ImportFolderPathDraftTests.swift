import XCTest
@testable import TeststripApp

final class ImportFolderPathDraftTests: XCTestCase {
    func testImportPlanExplainsNonDestructiveCatalogAndPreviewWork() {
        let draft = ImportFolderPathDraft(path: "/Photos/Job")

        XCTAssertEqual(draft.planSteps, [
            ImportPlanStep(
                title: "Catalog originals in place",
                detail: "No original files are moved, rewritten, or copied from this folder."
            ),
            ImportPlanStep(
                title: "Mirror portable metadata to XMP",
                detail: "Ratings, labels, flags, keywords, captions, creator, and copyright stay file-based."
            ),
            ImportPlanStep(
                title: "Generate cached previews",
                detail: "Micro and grid previews are queued for fast browsing from slow or offline sources."
            ),
            ImportPlanStep(
                title: "Use the managed background queue",
                detail: "Preview and metadata work remains visible, pausable, and cancellable."
            )
        ])
    }

    @MainActor
    func testInvalidPathKeepsDraftErrorForSheet() throws {
        var draft = ImportFolderPathDraft(path: "/definitely/not/a/teststrip/import/folder")

        XCTAssertThrowsError(try draft.resolveFolderURL())

        XCTAssertEqual(draft.errorMessage, "Folder path does not exist")
    }

    @MainActor
    func testValidPathClearsDraftErrorAndReturnsFolder() throws {
        let directory = try makeTemporaryDirectory(named: "valid-import-path")
        var draft = ImportFolderPathDraft(path: "/definitely/not/a/teststrip/import/folder")
        XCTAssertThrowsError(try draft.resolveFolderURL())

        draft.path = directory.path
        let resolved = try draft.resolveFolderURL()

        XCTAssertEqual(resolved.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertNil(draft.errorMessage)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-import-path-draft-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
