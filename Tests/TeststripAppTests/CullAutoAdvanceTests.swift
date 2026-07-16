import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Task 2 (culling-flow shell, SP-A): the `A` auto-advance toggle and the
// next-undecided advance target for P/X (and rating/color-label) decisions.
// Fixture pattern copied from CullStackNavigationTests.swift.
final class CullAutoAdvanceTests: XCTestCase {
    func testToggleAutoAdvanceKeyDecodesFromBareA() {
        XCTAssertEqual(CullingShortcut(key: .character("a")), .toggleAutoAdvance)
    }

    // P on frame 1 of a 3-frame stack, with frame 2 already user-picked,
    // skips the decided frame 2 and lands on frame 3 — the next *undecided*
    // stack member, not simply the next frame in order.
    func testPickAdvancesToNextUndecidedFrameInStackSkippingDecided() throws {
        let (model, repository) = try makeStackOfThree(
            named: "advance-skips-decided",
            frame2Metadata: AssetMetadata(flag: .pick),
            selected: "frame-1"
        )

        try model.applyCullingShortcut(.pick)

        XCTAssertEqual(try repository.asset(id: AssetID(rawValue: "frame-1")).metadata.flag, .pick)
        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "frame-3"))
    }

    // Deciding the last undecided frame in a stack carries the selection out
    // of the stack entirely, landing on the next stack's AI-recommended frame
    // (the same landing machinery ←/→ use) — not just the next asset in array
    // order, which would land on second-stack-lead instead.
    func testDecidingLastUndecidedFrameAdvancesToNextStacksLandingFrame() throws {
        let capturedAt = Date(timeIntervalSince1970: 500)
        let frame1 = makeAsset(
            id: "landing-frame-1",
            path: "/Photos/Job/landing-frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt),
            metadata: AssetMetadata(flag: .pick)
        )
        let frame2 = makeAsset(
            id: "landing-frame-2",
            path: "/Photos/Job/landing-frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)),
            metadata: AssetMetadata(flag: .reject)
        )
        let frame3 = makeAsset(
            id: "landing-frame-3",
            path: "/Photos/Job/landing-frame-3.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let secondStackLead = makeAsset(
            id: "second-stack-lead",
            path: "/Photos/Job/second-stack-lead.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(30))
        )
        let secondStackBest = makeAsset(
            id: "second-stack-best",
            path: "/Photos/Job/second-stack-best.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(31))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "advance-past-stack",
            assets: [frame1, frame2, frame3, secondStackLead, secondStackBest]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: secondStackLead.id, kind: .focus, value: .score(0.4), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: secondStackBest.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
        ])
        model.select(frame3.id)

        try model.applyCullingShortcut(.pick)

        XCTAssertEqual(try repository.asset(id: frame3.id).metadata.flag, .pick)
        XCTAssertEqual(model.selectedAssetID, secondStackBest.id)
    }

    // With auto-advance off, P still decides the frame but leaves the
    // selection exactly where it was.
    func testPickLeavesSelectionUnchangedWhenAutoAdvanceIsDisabled() throws {
        let (model, repository) = try makeStackOfThree(
            named: "advance-disabled",
            frame2Metadata: AssetMetadata(),
            selected: "frame-1"
        )
        model.toggleCullAutoAdvance()
        XCTAssertFalse(model.cullAutoAdvanceEnabled)

        try model.applyCullingShortcut(.pick)

        XCTAssertEqual(try repository.asset(id: AssetID(rawValue: "frame-1")).metadata.flag, .pick)
        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "frame-1"))
    }

    // Invariant: a sibling carrying only a tentative (AI-unconfirmed) flag
    // still counts as *undecided* for the advance search — the search must
    // key off `confirmedProjection.flag`, not the raw (possibly tentative)
    // `metadata.flag`. If this regressed to the raw field, frame 2 would look
    // "decided" and the advance would skip past it to frame 3.
    func testTentativeFlagStillCountsAsUndecidedForAdvanceSearch() throws {
        let (model, repository) = try makeStackOfThree(
            named: "advance-tentative-invariant",
            frame2Metadata: AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag]),
            selected: "frame-1"
        )

        try model.applyCullingShortcut(.pick)

        XCTAssertEqual(try repository.asset(id: AssetID(rawValue: "frame-1")).metadata.flag, .pick)
        XCTAssertEqual(model.selectedAssetID, AssetID(rawValue: "frame-2"))
    }

    // MARK: - Fixtures (mirrors CullStackNavigationTests' private helpers; kept local per file)

    private func makeStackOfThree(
        named name: String,
        frame2Metadata: AssetMetadata,
        selected id: String
    ) throws -> (AppModel, CatalogRepository) {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let frame1 = makeAsset(
            id: "frame-1",
            path: "/Photos/Job/frame-1.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let frame2 = makeAsset(
            id: "frame-2",
            path: "/Photos/Job/frame-2.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1)),
            metadata: frame2Metadata
        )
        let frame3 = makeAsset(
            id: "frame-3",
            path: "/Photos/Job/frame-3.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let (model, repository) = try makeModelWithCatalogAssets(named: name, assets: [frame1, frame2, frame3])
        model.select(AssetID(rawValue: id))
        return (model, repository)
    }

    private func makeAsset(
        id: String,
        path: String,
        technicalMetadata: AssetTechnicalMetadata? = nil,
        metadata: AssetMetadata = AssetMetadata()
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata,
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
