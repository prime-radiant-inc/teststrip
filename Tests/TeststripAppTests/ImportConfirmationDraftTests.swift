import XCTest
@testable import TeststripApp

final class ImportConfirmationDraftTests: XCTestCase {
    func testFolderDraftSummarizesInPlaceCatalogImport() {
        let sourceURL = URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true)
        let draft = ImportConfirmationDraft.folder(sourceURL)

        XCTAssertEqual(draft.title, "Import Folder")
        XCTAssertEqual(draft.sourceName, "Decades")
        XCTAssertEqual(draft.destinationName, nil)
        XCTAssertEqual(draft.primaryActionTitle, "Import 0 Photos")
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
            ),
            ImportPlanStep(
                title: "Read imported frames",
                detail: "Focus, exposure, and face reads queue over cached previews as they finish; reads stay provisional until you act.",
                stage: .followUpSetup
            )
        ])
    }

    func testDraftDefaultsToEvaluatingImportedFramesWithPlanStep() {
        let draft = ImportConfirmationDraft.folder(URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true))

        XCTAssertTrue(draft.evaluateAfterImport)
        XCTAssertEqual(draft.planSteps.last, ImportPlanStep(
            title: "Read imported frames",
            detail: "Focus, exposure, and face reads queue over cached previews as they finish; reads stay provisional until you act.",
            stage: .followUpSetup
        ))
    }

    func testDraftDefaultsToImportingNewContentOnly() {
        let folderDraft = ImportConfirmationDraft.folder(URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true))
        let cardDraft = ImportConfirmationDraft.card(
            source: URL(fileURLWithPath: "/Volumes/CARD/DCIM", isDirectory: true),
            destinationRoot: URL(fileURLWithPath: "/Volumes/Archive/Incoming", isDirectory: true)
        )

        XCTAssertTrue(folderDraft.importNewOnly)
        XCTAssertTrue(cardDraft.importNewOnly)
    }

    func testDedupCountsDescribeNewAndAlreadyPresentSplit() {
        var draft = ImportConfirmationDraft.folder(URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true))
        draft.dedupPreview = ImportDedupPreview(newContentCount: 2_310, existingContentCount: 418, reachedLimit: false)

        XCTAssertEqual(draft.dedupCountText, "2,310 new · 418 already in catalog")
    }

    // Final-verify FAIL (import-004 step 5): with "Import new photos only"
    // unchecked on an all-already-imported card, the primary still read
    // "Import 0 Photos" — promising a re-import while counting only new
    // content. The catalog keeps one row per original path
    // (idx_assets_original_path_unique) and card copies land at deterministic
    // destination paths, so dedupe-off re-imports files IN PLACE (rows
    // refresh, missing destination copies are restored) — the preflight must
    // count every scanned photo and say so.
    func testDedupeOffCountsAllScannedPhotosAndSaysReimportInPlace() throws {
        let directory = try makeTemporaryDirectory(named: "import-dedupe-off")
        for index in 0..<6 {
            try Data([UInt8(index)]).write(to: directory.appendingPathComponent("frame-\(index).jpg"))
        }
        var draft = ImportConfirmationDraft.folder(directory, supportedExtensions: ["jpg"])
        draft.dedupPreview = ImportDedupPreview(newContentCount: 0, existingContentCount: 6, reachedLimit: false)

        XCTAssertEqual(draft.primaryActionTitle, "Import 0 Photos")
        XCTAssertEqual(draft.dedupCountText, "0 new · 6 already in catalog")

        draft.importNewOnly = false

        XCTAssertEqual(draft.primaryActionTitle, "Import 6 Photos")
        XCTAssertEqual(draft.dedupCountText, "0 new · 6 already in catalog — re-imported in place")
    }

    func testDedupeOffWithNothingInCatalogKeepsPlainNewCount() throws {
        let directory = try makeTemporaryDirectory(named: "import-dedupe-off-all-new")
        for index in 0..<2 {
            try Data([UInt8(index)]).write(to: directory.appendingPathComponent("frame-\(index).jpg"))
        }
        var draft = ImportConfirmationDraft.folder(directory, supportedExtensions: ["jpg"])
        draft.dedupPreview = ImportDedupPreview(newContentCount: 2, existingContentCount: 0, reachedLimit: false)
        draft.importNewOnly = false

        XCTAssertEqual(draft.primaryActionTitle, "Import 2 Photos")
        XCTAssertEqual(draft.dedupCountText, "2 new")
    }

    func testDedupCountTextIsNilWithoutPreview() {
        let draft = ImportConfirmationDraft.folder(URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true))

        XCTAssertNil(draft.dedupCountText)
    }

    func testDedupCountTextMarksBoundedPreviewCounts() {
        var draft = ImportConfirmationDraft.folder(URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true))
        draft.dedupPreview = ImportDedupPreview(newContentCount: 300, existingContentCount: 0, reachedLimit: true)

        XCTAssertEqual(draft.dedupCountText, "300+ new")
    }

    func testDisablingEvaluateAfterImportRemovesThePlanStep() {
        var draft = ImportConfirmationDraft.folder(URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true))
        draft.evaluateAfterImport = false

        XCTAssertFalse(draft.planSteps.contains { $0.title == "Read imported frames" })
        XCTAssertEqual(draft.planSteps, ImportPlanSteps.folderInPlace)
    }

    func testDraftCarriesAutopilotAfterImportDefault() {
        var draft = ImportConfirmationDraft.folder(URL(fileURLWithPath: "/Volumes/Archive/Decades", isDirectory: true))
        draft.autopilotAfterImport = true
        XCTAssertTrue(draft.planSteps.contains { $0.title == "Autopilot cull" })
        draft.autopilotAfterImport = false
        XCTAssertFalse(draft.planSteps.contains { $0.title == "Autopilot cull" })
    }

    func testCardDraftSummarizesCopyThenCatalogImport() {
        let sourceURL = URL(fileURLWithPath: "/Volumes/CARD/DCIM", isDirectory: true)
        let destinationURL = URL(fileURLWithPath: "/Volumes/Archive/Incoming", isDirectory: true)
        let draft = ImportConfirmationDraft.card(source: sourceURL, destinationRoot: destinationURL)

        XCTAssertEqual(draft.title, "Import Card")
        XCTAssertEqual(draft.sourceName, "DCIM")
        XCTAssertEqual(draft.destinationName, "Incoming")
        XCTAssertEqual(draft.primaryActionTitle, "Import 0 Photos")
        XCTAssertEqual(draft.destinationPolicy, .capturedDate)
        XCTAssertNil(draft.secondCopyRootURL)
        XCTAssertEqual(draft.planSteps.first, ImportPlanStep(
            title: "Copy card files first",
            detail: "Originals are copied into dated folders (YYYY/YYYY-MM-DD) inside Incoming before Teststrip catalogs the copied files."
        ))
        XCTAssertFalse(draft.planSteps.contains { $0.title == "Write a second copy" })
        XCTAssertTrue(draft.planSteps.contains(ImportPlanStep(
            title: "Use the managed background queue",
            detail: "Copy, preview, and metadata work remains visible, pausable, and cancellable."
        )))
        XCTAssertEqual(
            draft.planSteps.filter { $0.stage == .followUpSetup }.map(\.title),
            [
                "Prepare imported-set culling",
                "Detect likely stacks",
                "Prepare keyword review",
                "Prepare face review",
                "Read imported frames"
            ]
        )
    }

    func testCardDraftFlatPolicyKeepsFlatCopyWording() {
        let draft = ImportConfirmationDraft.card(
            source: URL(fileURLWithPath: "/Volumes/CARD/DCIM", isDirectory: true),
            destinationRoot: URL(fileURLWithPath: "/Volumes/Archive/Incoming", isDirectory: true),
            destinationPolicy: .flat
        )

        XCTAssertEqual(draft.planSteps.first, ImportPlanStep(
            title: "Copy card files first",
            detail: "Originals are copied into Incoming before Teststrip catalogs the copied files."
        ))
    }

    func testCardDraftNamesSecondCopyPlanStepHonestly() throws {
        let source = try makeTemporaryDirectory(named: "import-card-draft-second-copy-source")
        let destination = try makeTemporaryDirectory(named: "import-card-draft-second-copy-destination")
        let secondCopy = try makeTemporaryDirectory(named: "Backup SSD")
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))

        let draft = ImportConfirmationDraft.card(
            source: source,
            destinationRoot: destination,
            secondCopyRootURL: secondCopy,
            supportedExtensions: ["jpg"]
        )

        XCTAssertEqual(draft.secondCopyName, "Backup SSD")
        XCTAssertNil(draft.secondCopyUnavailableReason)
        XCTAssertTrue(draft.canStartImport)
        XCTAssertTrue(draft.planSteps.contains(ImportPlanStep(
            title: "Write a second copy",
            detail: "Each copied original and its sidecar is also copied into Backup SSD; backup failures are reported per file and never stop the import."
        )))
    }

    func testCardDraftBlocksStartWhenSecondCopyDestinationIsMissing() throws {
        let source = try makeTemporaryDirectory(named: "import-card-draft-second-copy-missing-source")
        let destination = try makeTemporaryDirectory(named: "import-card-draft-second-copy-missing-destination")
        let missingSecondCopy = destination.deletingLastPathComponent()
            .appendingPathComponent("missing-backup", isDirectory: true)
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))

        var draft = ImportConfirmationDraft.card(
            source: source,
            destinationRoot: destination,
            secondCopyRootURL: missingSecondCopy,
            supportedExtensions: ["jpg"]
        )

        XCTAssertFalse(draft.canStartImport)
        XCTAssertEqual(draft.secondCopyUnavailableReason, "Second copy destination folder is missing")

        draft.setSecondCopyRoot(nil)

        XCTAssertTrue(draft.canStartImport)
        XCTAssertNil(draft.secondCopyUnavailableReason)
        XCTAssertNil(draft.secondCopyRootURL)
    }

    func testCardDraftBlocksStartWhenSecondCopyDestinationIsCardSource() throws {
        let source = try makeTemporaryDirectory(named: "import-card-draft-second-copy-matching-source")
        let destination = try makeTemporaryDirectory(named: "import-card-draft-second-copy-matching-destination")
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))

        let draft = ImportConfirmationDraft.card(
            source: source,
            destinationRoot: destination,
            secondCopyRootURL: source,
            supportedExtensions: ["jpg"]
        )

        XCTAssertFalse(draft.canStartImport)
        XCTAssertEqual(draft.secondCopyUnavailableReason, "Second copy destination must be different from the card source")
    }

    func testCardDraftBlocksStartWhenSecondCopyDestinationIsPrimaryDestination() throws {
        let source = try makeTemporaryDirectory(named: "import-card-draft-second-copy-matching-primary-source")
        let destination = try makeTemporaryDirectory(named: "import-card-draft-second-copy-matching-primary-destination")
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))

        let draft = ImportConfirmationDraft.card(
            source: source,
            destinationRoot: destination,
            secondCopyRootURL: destination,
            supportedExtensions: ["jpg"]
        )

        XCTAssertFalse(draft.canStartImport)
        XCTAssertEqual(draft.secondCopyUnavailableReason, "Second copy destination must be different from the primary destination")
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

    func testFolderDraftCountsRecognizedUnsupportedRawFilesByDefault() throws {
        let directory = try makeTemporaryDirectory(named: "import-source-summary-catalog-only-raw")
        try Data("catalog-only raw bytes".utf8).write(to: directory.appendingPathComponent("foveon.X3F"))

        let draft = ImportConfirmationDraft.folder(directory)

        XCTAssertEqual(draft.sourceSummary.photoCount, 1)
        XCTAssertEqual(draft.sourceSummary.countText, "1 recognized photo file")
        XCTAssertTrue(draft.canStartImport)
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

    // Per-import "Change…" destination override (confirmation sheet): the
    // sheet must be able to redirect a single import without touching the
    // saved default (AppModel.defaultCardImportDestination lives outside this
    // type entirely — setDestinationRoot only ever has a URL to work with).
    func testSetDestinationRootUpdatesNameAndRecomputesAvailability() throws {
        let source = try makeTemporaryDirectory(named: "import-card-draft-change-destination-source")
        let originalDestination = try makeTemporaryDirectory(named: "import-card-draft-change-destination-original")
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))

        var draft = ImportConfirmationDraft.card(
            source: source,
            destinationRoot: originalDestination,
            supportedExtensions: ["jpg"]
        )
        XCTAssertEqual(draft.destinationName, originalDestination.lastPathComponent)
        XCTAssertNil(draft.destinationUnavailableReason)

        draft.setDestinationRoot(URL(fileURLWithPath: "/Volumes/Other", isDirectory: true))

        XCTAssertEqual(draft.destinationRootURL, URL(fileURLWithPath: "/Volumes/Other", isDirectory: true))
        XCTAssertEqual(draft.destinationName, "Other")
        XCTAssertEqual(draft.destinationUnavailableReason, "Destination folder is missing")
    }

    func testSetDestinationRootRecomputesReasonWhenNewDestinationBecomesAvailable() throws {
        let source = try makeTemporaryDirectory(named: "import-card-draft-change-destination-recover-source")
        let missingDestination = source.deletingLastPathComponent()
            .appendingPathComponent("missing-destination", isDirectory: true)
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("frame.jpg"))

        var draft = ImportConfirmationDraft.card(
            source: source,
            destinationRoot: missingDestination,
            supportedExtensions: ["jpg"]
        )
        XCTAssertEqual(draft.destinationUnavailableReason, "Destination folder is missing")
        XCTAssertFalse(draft.canStartImport)

        let availableDestination = try makeTemporaryDirectory(named: "import-card-draft-change-destination-recover-target")
        draft.setDestinationRoot(availableDestination)

        XCTAssertEqual(draft.destinationRootURL, availableDestination)
        XCTAssertEqual(draft.destinationName, availableDestination.lastPathComponent)
        XCTAssertNil(draft.destinationUnavailableReason)
        XCTAssertTrue(draft.canStartImport)
    }

    func testSetDestinationRootIsNoOpForFolderDrafts() throws {
        let directory = try makeTemporaryDirectory(named: "import-folder-draft-change-destination")
        var draft = ImportConfirmationDraft.folder(directory)

        draft.setDestinationRoot(URL(fileURLWithPath: "/Volumes/Other", isDirectory: true))

        XCTAssertNil(draft.destinationRootURL)
        XCTAssertNil(draft.destinationName)
        XCTAssertNil(draft.destinationUnavailableReason)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-import-confirmation-\(UUID().uuidString)", isDirectory: true)
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
