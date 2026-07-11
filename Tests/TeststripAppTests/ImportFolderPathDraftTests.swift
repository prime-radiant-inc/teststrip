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
                detail: "These photos stay selected so Open and Cull can resume them immediately.",
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

    func testCardPathPlanExplainsCopyBeforeCataloging() {
        let draft = ImportCardPathDraft(sourcePath: "/Volumes/CARD/DCIM", destinationPath: "/Photos/Incoming")

        XCTAssertEqual(draft.primaryActionTitle, "Review Card Import")
        XCTAssertEqual(draft.planSteps.first, ImportPlanStep(
            title: "Copy card files first",
            detail: "Originals are copied into dated folders (YYYY/YYYY-MM-DD) inside Incoming before Teststrip catalogs the copied files."
        ))
        XCTAssertTrue(draft.planSteps.contains(ImportPlanStep(
            title: "Use the managed background queue",
            detail: "Copy, preview, and metadata work remains visible, pausable, and cancellable."
        )))
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

    func testCardPathReviewPresentationRequiresSourceAndDestination() {
        let ready = ImportCardPathReviewPresentation(
            draft: ImportCardPathDraft(sourcePath: "/Volumes/CARD/DCIM", destinationPath: "/Photos/Incoming"),
            isReviewing: false,
            isImporting: false
        )

        XCTAssertEqual(ready.primaryActionTitle, "Review Card Import")
        XCTAssertTrue(ready.isPrimaryActionEnabled)
        XCTAssertFalse(ready.showsProgress)
        XCTAssertNil(ready.statusText)

        XCTAssertFalse(ImportCardPathReviewPresentation(
            draft: ImportCardPathDraft(sourcePath: "/Volumes/CARD/DCIM", destinationPath: " "),
            isReviewing: false,
            isImporting: false
        ).isPrimaryActionEnabled)
        XCTAssertFalse(ImportCardPathReviewPresentation(
            draft: ImportCardPathDraft(sourcePath: " ", destinationPath: "/Photos/Incoming"),
            isReviewing: false,
            isImporting: false
        ).isPrimaryActionEnabled)
    }

    func testCardPathReviewPresentationShowsReviewingState() {
        let presentation = ImportCardPathReviewPresentation(
            draft: ImportCardPathDraft(sourcePath: "/Volumes/CARD/DCIM", destinationPath: "/Photos/Incoming"),
            isReviewing: true,
            isImporting: false
        )

        XCTAssertEqual(presentation.primaryActionTitle, "Reviewing...")
        XCTAssertFalse(presentation.isPrimaryActionEnabled)
        XCTAssertTrue(presentation.showsProgress)
        XCTAssertEqual(presentation.statusText, "Reviewing card import before copy...")
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
        XCTAssertEqual(confirmation.primaryActionTitle, "Import 0 Photos")
        XCTAssertNil(draft.errorMessage)
    }

    @MainActor
    func testValidCardPathsBuildCardConfirmationDraft() throws {
        let source = try makeTemporaryDirectory(named: "valid-card-source")
        let destination = try makeTemporaryDirectory(named: "valid-card-destination")
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))
        var draft = ImportCardPathDraft(sourcePath: source.path, destinationPath: destination.path)

        let confirmation = try draft.makeCardConfirmationDraft()

        XCTAssertEqual(confirmation.mode, .card)
        XCTAssertEqual(confirmation.sourceURL.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(confirmation.destinationRootURL?.standardizedFileURL, destination.standardizedFileURL)
        XCTAssertEqual(confirmation.primaryActionTitle, "Import 1 Photo")
        XCTAssertTrue(confirmation.canStartImport)
        XCTAssertNil(draft.errorMessage)
    }

    @MainActor
    func testInvalidCardDestinationKeepsDraftErrorForSheet() throws {
        let source = try makeTemporaryDirectory(named: "invalid-card-destination-source")
        var draft = ImportCardPathDraft(
            sourcePath: source.path,
            destinationPath: "/definitely/not/a/teststrip/card/destination"
        )

        XCTAssertThrowsError(try draft.makeCardConfirmationDraft())

        XCTAssertEqual(draft.errorMessage, "Folder path does not exist")
    }

    @MainActor
    func testMatchingCardSourceAndDestinationBuildsBlockedConfirmationDraft() throws {
        let source = try makeTemporaryDirectory(named: "matching-card-source-destination")
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))
        var draft = ImportCardPathDraft(sourcePath: source.path, destinationPath: source.path)

        let confirmation = try draft.makeCardConfirmationDraft()

        XCTAssertEqual(confirmation.mode, .card)
        XCTAssertEqual(confirmation.sourceURL.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(confirmation.destinationRootURL?.standardizedFileURL, source.standardizedFileURL)
        XCTAssertFalse(confirmation.canStartImport)
        XCTAssertEqual(confirmation.destinationUnavailableReason, "Destination must be different from the card source")
        XCTAssertNil(draft.errorMessage)
    }

    @MainActor
    func testCardSourceInsideDestinationBuildsBlockedConfirmationDraft() throws {
        let destination = try makeTemporaryDirectory(named: "card-source-inside-destination")
        let source = destination.appendingPathComponent("DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))
        var draft = ImportCardPathDraft(sourcePath: source.path, destinationPath: destination.path)

        let confirmation = try draft.makeCardConfirmationDraft()

        XCTAssertEqual(confirmation.mode, .card)
        XCTAssertEqual(confirmation.sourceURL.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(confirmation.destinationRootURL?.standardizedFileURL, destination.standardizedFileURL)
        XCTAssertFalse(confirmation.canStartImport)
        XCTAssertEqual(confirmation.destinationUnavailableReason, "Card source cannot be inside the destination")
        XCTAssertNil(draft.errorMessage)
    }

    @MainActor
    func testCardDestinationInsideSourceBuildsBlockedConfirmationDraft() throws {
        let source = try makeTemporaryDirectory(named: "card-destination-inside-source")
        let destination = source.appendingPathComponent("Imported", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))
        var draft = ImportCardPathDraft(sourcePath: source.path, destinationPath: destination.path)

        let confirmation = try draft.makeCardConfirmationDraft()

        XCTAssertEqual(confirmation.mode, .card)
        XCTAssertEqual(confirmation.sourceURL.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(confirmation.destinationRootURL?.standardizedFileURL, destination.standardizedFileURL)
        XCTAssertFalse(confirmation.canStartImport)
        XCTAssertEqual(confirmation.destinationUnavailableReason, "Destination cannot be inside the card source")
        XCTAssertNil(draft.errorMessage)
    }

    func testCardPathDraftDefaultsToDatedFolderOrganizationWithoutSecondCopy() {
        let draft = ImportCardPathDraft()

        XCTAssertTrue(draft.organizeIntoDatedFolders)
        XCTAssertEqual(draft.secondCopyPath, "")
    }

    func testCardPathDraftResetRestoresDatedFolderDefaultAndClearsSecondCopy() {
        var draft = ImportCardPathDraft(sourcePath: "/Volumes/CARD/DCIM", destinationPath: "/Photos/Incoming")
        draft.organizeIntoDatedFolders = false
        draft.secondCopyPath = "/Volumes/Backup"

        draft.reset()

        XCTAssertTrue(draft.organizeIntoDatedFolders)
        XCTAssertEqual(draft.secondCopyPath, "")
    }

    func testCardPathPlanNamesDatedFoldersAndSecondCopy() {
        var draft = ImportCardPathDraft(sourcePath: "/Volumes/CARD/DCIM", destinationPath: "/Photos/Incoming")
        draft.secondCopyPath = "/Volumes/Backup SSD"

        XCTAssertEqual(draft.planSteps.first, ImportPlanStep(
            title: "Copy card files first",
            detail: "Originals are copied into dated folders (YYYY/YYYY-MM-DD) inside Incoming before Teststrip catalogs the copied files."
        ))
        XCTAssertTrue(draft.planSteps.contains(ImportPlanStep(
            title: "Write a second copy",
            detail: "Each copied original and its sidecar is also copied into Backup SSD; backup failures are reported per file and never stop the import."
        )))

        draft.organizeIntoDatedFolders = false

        XCTAssertEqual(draft.planSteps.first, ImportPlanStep(
            title: "Copy card files first",
            detail: "Originals are copied into Incoming before Teststrip catalogs the copied files."
        ))
    }

    @MainActor
    func testCardPathDraftCarriesDatedPolicyAndSecondCopyIntoConfirmation() throws {
        let source = try makeTemporaryDirectory(named: "card-policy-source")
        let destination = try makeTemporaryDirectory(named: "card-policy-destination")
        let secondCopy = try makeTemporaryDirectory(named: "card-policy-backup")
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))
        var draft = ImportCardPathDraft(sourcePath: source.path, destinationPath: destination.path)
        draft.secondCopyPath = secondCopy.path

        let confirmation = try draft.makeCardConfirmationDraft()

        XCTAssertEqual(confirmation.destinationPolicy, .capturedDate)
        XCTAssertEqual(confirmation.secondCopyRootURL?.standardizedFileURL, secondCopy.standardizedFileURL)
        XCTAssertNil(draft.errorMessage)
    }

    @MainActor
    func testCardPathDraftFlatToggleBuildsFlatConfirmationWithoutSecondCopy() throws {
        let source = try makeTemporaryDirectory(named: "card-flat-source")
        let destination = try makeTemporaryDirectory(named: "card-flat-destination")
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))
        var draft = ImportCardPathDraft(sourcePath: source.path, destinationPath: destination.path)
        draft.organizeIntoDatedFolders = false

        let confirmation = try draft.makeCardConfirmationDraft()

        XCTAssertEqual(confirmation.destinationPolicy, .flat)
        XCTAssertNil(confirmation.secondCopyRootURL)
    }

    @MainActor
    func testCardPathDraftInvalidSecondCopyPathKeepsDraftError() throws {
        let source = try makeTemporaryDirectory(named: "card-second-copy-invalid-source")
        let destination = try makeTemporaryDirectory(named: "card-second-copy-invalid-destination")
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))
        var draft = ImportCardPathDraft(sourcePath: source.path, destinationPath: destination.path)
        draft.secondCopyPath = "/definitely/not/a/teststrip/second/copy"

        XCTAssertThrowsError(try draft.makeCardConfirmationDraft())

        XCTAssertEqual(draft.errorMessage, "Folder path does not exist")

        draft.secondCopyPath = ""
        let confirmation = try draft.makeCardConfirmationDraft()

        XCTAssertNil(confirmation.secondCopyRootURL)
        XCTAssertNil(draft.errorMessage)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-import-path-draft-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
