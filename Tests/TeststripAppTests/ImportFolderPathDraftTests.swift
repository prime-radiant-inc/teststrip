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
            ),
            ImportPlanStep(
                title: "Prepare imported-set culling",
                detail: "The imported output set is kept as a working scope so Open and Cull can resume it immediately.",
                stage: .followUpSetup
            ),
            ImportPlanStep(
                title: "Detect likely stacks",
                detail: "Time-adjacent frames unlock stack culling when a burst or sequence is found after import.",
                stage: .followUpSetup
            ),
            ImportPlanStep(
                title: "Prepare keyword review",
                detail: "Local object labels stay provisional until you accept them into keywords/XMP.",
                stage: .followUpSetup
            ),
            ImportPlanStep(
                title: "Prepare face review",
                detail: "Detected faces route to Faces Found review; naming waits for future clustering.",
                stage: .followUpSetup
            )
        ])
    }

    func testImportPlanKeepsAgenticFollowUpsHonestAndScoped() {
        let draft = ImportFolderPathDraft(path: "/Photos/Job")
        let followUps = draft.planSteps.filter { $0.stage == .followUpSetup }

        XCTAssertEqual(followUps.map(\.title), [
            "Prepare imported-set culling",
            "Detect likely stacks",
            "Prepare keyword review",
            "Prepare face review"
        ])
        XCTAssertFalse(draft.planSteps.contains { step in
            let copy = "\(step.title) \(step.detail)".lowercased()
            return copy.contains("geo") || copy.contains("map")
        })
    }

    func testPathSheetPrimaryActionShowsReviewStep() {
        XCTAssertEqual(ImportFolderPathDraft().primaryActionTitle, "Review Import")
    }

    func testPathReviewPresentationEnablesReviewForEnteredPath() {
        let presentation = ImportFolderPathReviewPresentation(
            draft: ImportFolderPathDraft(path: "/Photos/Job"),
            isReviewing: false,
            isImporting: false
        )

        XCTAssertEqual(presentation.primaryActionTitle, "Review Import")
        XCTAssertTrue(presentation.isPrimaryActionEnabled)
        XCTAssertFalse(presentation.showsProgress)
        XCTAssertNil(presentation.statusText)
    }

    func testPathReviewPresentationShowsReviewingState() {
        let presentation = ImportFolderPathReviewPresentation(
            draft: ImportFolderPathDraft(path: "/Photos/Job"),
            isReviewing: true,
            isImporting: false
        )

        XCTAssertEqual(presentation.primaryActionTitle, "Reviewing...")
        XCTAssertFalse(presentation.isPrimaryActionEnabled)
        XCTAssertTrue(presentation.showsProgress)
        XCTAssertEqual(presentation.statusText, "Reviewing folder before import...")
    }

    func testPathReviewPresentationDisablesEmptyImportingOrReviewingStates() {
        XCTAssertFalse(ImportFolderPathReviewPresentation(
            draft: ImportFolderPathDraft(path: "  "),
            isReviewing: false,
            isImporting: false
        ).isPrimaryActionEnabled)
        XCTAssertFalse(ImportFolderPathReviewPresentation(
            draft: ImportFolderPathDraft(path: "/Photos/Job"),
            isReviewing: false,
            isImporting: true
        ).isPrimaryActionEnabled)
        XCTAssertFalse(ImportFolderPathReviewPresentation(
            draft: ImportFolderPathDraft(path: "/Photos/Job"),
            isReviewing: true,
            isImporting: true
        ).isPrimaryActionEnabled)
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

    @MainActor
    func testValidPathBuildsFolderConfirmationDraft() throws {
        let directory = try makeTemporaryDirectory(named: "valid-import-confirmation-path")
        var draft = ImportFolderPathDraft(path: "/definitely/not/a/teststrip/import/folder")
        XCTAssertThrowsError(try draft.resolveFolderURL())

        draft.path = directory.path
        let confirmation = try draft.makeFolderConfirmationDraft()

        XCTAssertEqual(confirmation.mode, .folder)
        XCTAssertEqual(confirmation.sourceURL.standardizedFileURL, directory.standardizedFileURL)
        XCTAssertEqual(confirmation.primaryActionTitle, "Start Import")
        XCTAssertNil(draft.errorMessage)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-import-path-draft-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
