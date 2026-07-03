import XCTest
@testable import TeststripApp

final class ImportFolderPathDraftTests: XCTestCase {
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
