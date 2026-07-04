import XCTest
@testable import TeststripApp

final class ImportConfirmationDraftTests: XCTestCase {
    func testFolderDraftSummarizesInPlaceCatalogImport() {
        let sourceURL = URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true)
        let draft = ImportConfirmationDraft.folder(sourceURL)

        XCTAssertEqual(draft.title, "Import Folder")
        XCTAssertEqual(draft.sourceName, "Decades")
        XCTAssertEqual(draft.destinationName, nil)
        XCTAssertEqual(draft.primaryActionTitle, "Start Import")
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

    func testCardDraftSummarizesCopyThenCatalogImport() {
        let sourceURL = URL(fileURLWithPath: "/Volumes/CARD/DCIM", isDirectory: true)
        let destinationURL = URL(fileURLWithPath: "/Volumes/Archive/Incoming", isDirectory: true)
        let draft = ImportConfirmationDraft.card(source: sourceURL, destinationRoot: destinationURL)

        XCTAssertEqual(draft.title, "Import Card")
        XCTAssertEqual(draft.sourceName, "DCIM")
        XCTAssertEqual(draft.destinationName, "Incoming")
        XCTAssertEqual(draft.primaryActionTitle, "Start Card Import")
        XCTAssertEqual(draft.planSteps.first, ImportPlanStep(
            title: "Copy card files first",
            detail: "Originals are copied into Incoming before Teststrip catalogs the copied files."
        ))
        XCTAssertTrue(draft.planSteps.contains(ImportPlanStep(
            title: "Use the managed background queue",
            detail: "Copy, preview, and metadata work remains visible, pausable, and cancellable."
        )))
    }
}
