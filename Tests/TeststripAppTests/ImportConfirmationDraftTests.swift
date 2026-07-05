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

    func testSourceSummaryCountsRecognizedPhotoFilesAndBytes() throws {
        let directory = try makeTemporaryDirectory(named: "import-source-summary")
        let nested = directory.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("first.jpg"))
        try Data([4, 5, 6, 7, 8]).write(to: nested.appendingPathComponent("second.CR2"))
        try Data("notes".utf8).write(to: directory.appendingPathComponent("notes.txt"))

        let summary = ImportSourceSummary.scan(
            sourceURL: directory,
            supportedExtensions: ["jpg", "cr2"],
            limit: 20
        )

        XCTAssertEqual(summary.photoCount, 2)
        XCTAssertEqual(summary.byteCount, 8)
        XCTAssertFalse(summary.reachedLimit)
        XCTAssertEqual(summary.countText, "2 recognized photo files")
        XCTAssertEqual(summary.byteCountText, "8 bytes")
        XCTAssertEqual(summary.detailText, "Ready to catalog from import-source-summary")
    }

    func testSourceSummaryStopsAtScanLimit() throws {
        let directory = try makeTemporaryDirectory(named: "import-source-summary-limit")
        for index in 0..<3 {
            try Data([UInt8(index)]).write(to: directory.appendingPathComponent("frame-\(index).jpg"))
        }

        let summary = ImportSourceSummary.scan(
            sourceURL: directory,
            supportedExtensions: ["jpg"],
            limit: 2
        )

        XCTAssertEqual(summary.photoCount, 2)
        XCTAssertEqual(summary.byteCount, 2)
        XCTAssertTrue(summary.reachedLimit)
        XCTAssertEqual(summary.countText, "2+ recognized photo files")
        XCTAssertEqual(summary.detailText, "Preview counted the first 2 recognized photo files")
    }

    func testSourceSummaryStopsAtEntryLimitBeforeExhaustingUnsupportedFiles() throws {
        let directory = try makeTemporaryDirectory(named: "import-source-summary-entry-limit")
        for index in 0..<3 {
            try Data([UInt8(index)]).write(to: directory.appendingPathComponent("notes-\(index).txt"))
        }

        let summary = ImportSourceSummary.scan(
            sourceURL: directory,
            supportedExtensions: ["jpg"],
            limit: 20,
            entryLimit: 2
        )

        XCTAssertEqual(summary.photoCount, 0)
        XCTAssertEqual(summary.scannedEntryCount, 2)
        XCTAssertFalse(summary.reachedLimit)
        XCTAssertTrue(summary.reachedEntryLimit)
        XCTAssertEqual(summary.countText, "No recognized photo files found yet")
        XCTAssertEqual(summary.detailText, "Preview scanned the first 2 files; import will keep scanning")
    }

    func testCompletedEmptySourceSummaryBlocksImportWithClearDetail() throws {
        let directory = try makeTemporaryDirectory(named: "import-source-summary-empty")
        try Data("notes".utf8).write(to: directory.appendingPathComponent("notes.txt"))

        let summary = ImportSourceSummary.scan(
            sourceURL: directory,
            supportedExtensions: ["jpg"],
            limit: 20,
            entryLimit: 20
        )

        XCTAssertEqual(summary.countText, "No recognized photo files found")
        XCTAssertEqual(summary.detailText, "Choose a folder with recognized photo files before importing")
        XCTAssertFalse(summary.canStartImport)
    }

    func testSourceSummaryBlocksMissingSourceBeforeImportStarts() throws {
        let directory = try makeTemporaryDirectory(named: "import-source-summary-missing")
        let missing = directory.appendingPathComponent("missing", isDirectory: true)

        let summary = ImportSourceSummary.scan(sourceURL: missing)

        XCTAssertEqual(summary.countText, "Source folder is missing")
        XCTAssertEqual(summary.detailText, "Source folder is missing")
        XCTAssertFalse(summary.canStartImport)
    }

    func testSourceSummaryBlocksUnreadableSourceBeforeImportStarts() throws {
        let directory = try makeTemporaryDirectory(named: "import-source-summary-unreadable")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }

        let summary = ImportSourceSummary.scan(sourceURL: directory)

        XCTAssertEqual(summary.countText, "Source folder is not readable")
        XCTAssertEqual(summary.detailText, "Source folder is not readable")
        XCTAssertFalse(summary.canStartImport)
    }

    func testFolderDraftBlocksStartWhenPreflightFindsNoSupportedPhotos() throws {
        let directory = try makeTemporaryDirectory(named: "import-draft-empty")
        try Data("notes".utf8).write(to: directory.appendingPathComponent("notes.txt"))

        let draft = ImportConfirmationDraft.folder(directory, supportedExtensions: ["jpg"])

        XCTAssertFalse(draft.canStartImport)
        XCTAssertEqual(draft.sourceSummary.detailText, "Choose a folder with recognized photo files before importing")
    }

    func testCardDraftBlocksStartWhenDestinationMatchesSource() throws {
        let source = try makeTemporaryDirectory(named: "import-card-draft-matching-destination")
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))

        let draft = ImportConfirmationDraft.card(
            source: source,
            destinationRoot: source,
            supportedExtensions: ["jpg"]
        )

        XCTAssertFalse(draft.canStartImport)
        XCTAssertEqual(draft.destinationUnavailableReason, "Destination must be different from the card source")
    }

    func testCardDraftBlocksStartWhenDestinationIsInsideSource() throws {
        let source = try makeTemporaryDirectory(named: "import-card-draft-nested-destination")
        let destination = source.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))

        let draft = ImportConfirmationDraft.card(
            source: source,
            destinationRoot: destination,
            supportedExtensions: ["jpg"]
        )

        XCTAssertFalse(draft.canStartImport)
        XCTAssertEqual(draft.destinationUnavailableReason, "Destination cannot be inside the card source")
    }

    func testCardDraftBlocksStartWhenSourceIsInsideDestination() throws {
        let destination = try makeTemporaryDirectory(named: "import-card-draft-nested-source")
        let source = destination.appendingPathComponent("DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))

        let draft = ImportConfirmationDraft.card(
            source: source,
            destinationRoot: destination,
            supportedExtensions: ["jpg"]
        )

        XCTAssertFalse(draft.canStartImport)
        XCTAssertEqual(draft.destinationUnavailableReason, "Card source cannot be inside the destination")
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-import-confirmation-\(UUID().uuidString)", isDirectory: true)
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
