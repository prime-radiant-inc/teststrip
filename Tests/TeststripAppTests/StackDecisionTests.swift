import Observation
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Task 16: Return promotes the current frame (Pick) and rejects the rest of
// its stack in one gesture, then advances past the stack. Covers the single
// undo-group requirement and the confirm-before-write boundary (siblings
// only — nothing outside the stack is touched).
final class StackDecisionTests: XCTestCase {
    func testPromoteFlagsFrameAndSiblingsInOneUndoGroupAndAdvances() throws {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let frame1 = makeAsset(
            id: "frame-1",
            path: "/Photos/Job/frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "frame-2",
            path: "/Photos/Job/frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let frame3 = makeAsset(
            id: "frame-3",
            path: "/Photos/Job/frame-3.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let frame4 = makeAsset(
            id: "frame-4",
            path: "/Photos/Job/frame-4.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(2.6))
        )
        let outsideStack = makeAsset(
            id: "outside-stack",
            path: "/Photos/Other/outside-stack.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(30))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-stack",
            assets: [frame1, frame2, frame3, frame4, outsideStack]
        )
        model.select(frame2.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame3.id).metadata.flag, .reject)
        XCTAssertEqual(try repository.asset(id: frame4.id).metadata.flag, .reject)
        // Confirm-before-write: promoting never touches assets outside the stack.
        XCTAssertNil(try repository.asset(id: outsideStack.id).metadata.flag)
        // Advances to the next stack's first undecided frame.
        XCTAssertEqual(model.selectedAssetID, outsideStack.id)

        // A single ⌘Z reverts all four flags it set.
        try model.undoMetadataChange()
        XCTAssertNil(try repository.asset(id: frame1.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame2.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame3.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: frame4.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: outsideStack.id).metadata.flag)
    }

    func testReturnShortcutPromotesAndRejectsSiblings() throws {
        let capturedAt = Date(timeIntervalSince1970: 200)
        let frame1 = makeAsset(
            id: "return-frame-1",
            path: "/Photos/Job/return-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "return-frame-2",
            path: "/Photos/Job/return-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "return-shortcut-promotes",
            assets: [frame1, frame2]
        )
        model.select(frame1.id)

        XCTAssertEqual(CullingShortcut(key: .returnKey), .promoteAndRejectSiblings)
        try model.applyCullingShortcut(.promoteAndRejectSiblings)

        XCTAssertEqual(try repository.asset(id: frame1.id).metadata.flag, .pick)
        XCTAssertEqual(try repository.asset(id: frame2.id).metadata.flag, .reject)
    }

    // Maya's session (persona-1): pressing Return silently overrode her
    // explicit pick of a sibling with no toast, so she couldn't tell what
    // happened without reading the database. Promote must set the same
    // decision-feedback the P/X shortcuts set, naming the full effect.
    func testPromoteSetsDecisionFeedbackNamingSiblingCount() throws {
        let capturedAt = Date(timeIntervalSince1970: 300)
        let frame1 = makeAsset(
            id: "toast-frame-1",
            path: "/Photos/Job/toast-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "toast-frame-2",
            path: "/Photos/Job/toast-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let frame3 = makeAsset(
            id: "toast-frame-3",
            path: "/Photos/Job/toast-frame-3.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "promote-stack-toast",
            assets: [frame1, frame2, frame3]
        )
        model.select(frame1.id)

        XCTAssertNil(model.lastCullingMetadataDecision)
        try model.promoteCurrentFrameAndRejectSiblings()

        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.assetID, frame1.id)
        XCTAssertEqual(feedback.filename, "toast-frame-1.cr2")
        XCTAssertEqual(feedback.decisionText, "Picked · 2 siblings rejected")
    }

    func testPromoteSingleSiblingUsesSingularWording() throws {
        let capturedAt = Date(timeIntervalSince1970: 400)
        let frame1 = makeAsset(
            id: "singular-frame-1",
            path: "/Photos/Job/singular-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "singular-frame-2",
            path: "/Photos/Job/singular-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let (model, _) = try makeModelWithCatalogAssets(
            named: "promote-stack-toast-singular",
            assets: [frame1, frame2]
        )
        model.select(frame1.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.decisionText, "Picked · 1 sibling rejected")
    }

    // Persona-3 item 4: Return on a frame with no siblings at all used to be
    // a genuine silent no-op (the guard returned before anything fired) —
    // three presses read as the app hanging. Now it shows decision feedback
    // and writes nothing.
    func testPromoteOnSingleFrameShowsNoticeAndWritesNoMetadata() throws {
        let capturedAt = Date(timeIntervalSince1970: 500)
        let lonely = makeAsset(
            id: "lonely-frame",
            path: "/Photos/Job/lonely-frame.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let farAway = makeAsset(
            id: "far-away-frame",
            path: "/Photos/Job/far-away-frame.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(600))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "promote-single-frame",
            assets: [lonely, farAway]
        )
        model.select(lonely.id)

        try model.promoteCurrentFrameAndRejectSiblings()

        let feedback = try XCTUnwrap(model.lastCullingMetadataDecision)
        XCTAssertEqual(feedback.assetID, lonely.id)
        XCTAssertEqual(feedback.decisionText, "No stack to promote — P picks this frame")
        XCTAssertTrue(feedback.isInformational)
        XCTAssertNil(try repository.asset(id: lonely.id).metadata.flag)
        XCTAssertNil(try repository.asset(id: farAway.id).metadata.flag)
        // Stays put — nothing to advance past.
        XCTAssertEqual(model.selectedAssetID, lonely.id)
    }

    // MARK: - Fixtures (mirrors AppModelTests' private helpers; kept local per file)

    private func makeAsset(
        id: String,
        path: String,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: technicalMetadata
        )
    }

    private static func technicalMetadata(capturedAt: Date) -> AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            capturedAt: capturedAt,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog)
        return (model, repository)
    }
}
