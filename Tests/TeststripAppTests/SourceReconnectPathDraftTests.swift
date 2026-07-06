import XCTest
@testable import TeststripApp

final class SourceReconnectPathDraftTests: XCTestCase {
    @MainActor
    func testResolveRootURLsAllowsMissingOldRootAndRequiresExistingNewRoot() throws {
        let newRoot = try makeTemporaryDirectory(named: "mounted")
        var draft = SourceReconnectPathDraft(
            oldRootPath: "/Volumes/OfflineArchive",
            newRootPath: newRoot.path
        )

        let roots = try draft.resolveRootURLs()

        XCTAssertEqual(roots.oldRoot, URL(fileURLWithPath: "/Volumes/OfflineArchive", isDirectory: true).standardizedFileURL)
        XCTAssertEqual(roots.newRoot, newRoot.standardizedFileURL)
        XCTAssertNil(draft.errorMessage)
    }

    @MainActor
    func testResolveRootURLsStoresErrorWhenNewRootIsMissing() throws {
        var draft = SourceReconnectPathDraft(
            oldRootPath: "/Volumes/OfflineArchive",
            newRootPath: "/definitely/not/a/teststrip/reconnect/root"
        )

        XCTAssertThrowsError(try draft.resolveRootURLs())

        XCTAssertEqual(draft.errorMessage, "New source root does not exist")
    }

    func testChangingEitherPathClearsDraftError() {
        var draft = SourceReconnectPathDraft(
            oldRootPath: "/Volumes/OfflineArchive",
            newRootPath: "/definitely/not/a/teststrip/reconnect/root",
            errorMessage: "New source root does not exist"
        )

        draft.oldRootPath = "/Volumes/Archive"
        XCTAssertNil(draft.errorMessage)

        draft = SourceReconnectPathDraft(
            oldRootPath: "/Volumes/OfflineArchive",
            newRootPath: "/definitely/not/a/teststrip/reconnect/root",
            errorMessage: "New source root does not exist"
        )
        draft.newRootPath = "/Volumes/MountedArchive"
        XCTAssertNil(draft.errorMessage)
    }

    func testRecordErrorStoresMessageUntilAPathChanges() {
        var draft = SourceReconnectPathDraft(
            oldRootPath: "/Volumes/OfflineArchive",
            newRootPath: "/Volumes/MountedArchive"
        )

        draft.recordError("No files were reconnected from MountedArchive.")

        XCTAssertEqual(draft.errorMessage, "No files were reconnected from MountedArchive.")

        draft.newRootPath = "/Volumes/Archive"
        XCTAssertNil(draft.errorMessage)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-source-reconnect-draft-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
