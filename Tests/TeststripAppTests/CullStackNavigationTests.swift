import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Task 4 (cull-stack-rail): ↑/↓ move within the stack containing the
// selection, stopping at the ends — no wrap, no crossing into a neighboring
// stack. Complements the existing ←/→ stack-to-stack navigation.
final class CullStackNavigationTests: XCTestCase {
    func testNextCandidateMovesWithinStackAndStopsAtEnd() throws {
        let (model, _) = try makeStackOfThree(selected: "a")

        try model.selectNextCandidateInStack()
        XCTAssertEqual(model.selectedAssetID?.rawValue, "b")

        try model.selectNextCandidateInStack()
        XCTAssertEqual(model.selectedAssetID?.rawValue, "c")

        try model.selectNextCandidateInStack() // at end — stays put
        XCTAssertEqual(model.selectedAssetID?.rawValue, "c")
    }

    func testPreviousCandidateMovesWithinStackAndStopsAtEnd() throws {
        let (model, _) = try makeStackOfThree(selected: "c")

        try model.selectPreviousCandidateInStack()
        XCTAssertEqual(model.selectedAssetID?.rawValue, "b")

        try model.selectPreviousCandidateInStack()
        XCTAssertEqual(model.selectedAssetID?.rawValue, "a")

        try model.selectPreviousCandidateInStack() // at start — stays put
        XCTAssertEqual(model.selectedAssetID?.rawValue, "a")
    }

    // A frame with no stack-mates (no multi-frame stack contains it) has no
    // "current stack" to navigate within — J/K (and ↑/↓) fall back to
    // stop-to-stop advance through the deck instead of going dead.
    func testNextCandidateFallsBackToStopToStopAdvanceWhenSelectedAssetHasNoStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 400)
        let lonely = makeAsset(
            id: "lonely",
            path: "/Photos/Job/lonely.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let farAway = makeAsset(
            id: "far-away",
            path: "/Photos/Job/far-away.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(30))
        )
        let (model, _) = try makeModelWithCatalogAssets(named: "no-stack-nav-next", assets: [lonely, farAway])
        model.select(lonely.id)

        try model.applyCullingShortcut(.nextCandidateInStack)

        XCTAssertEqual(model.selectedAssetID, farAway.id)
    }

    func testPreviousCandidateFallsBackToStopToStopAdvanceWhenSelectedAssetHasNoStack() throws {
        let capturedAt = Date(timeIntervalSince1970: 400)
        let lonely = makeAsset(
            id: "lonely",
            path: "/Photos/Job/lonely.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let farAway = makeAsset(
            id: "far-away",
            path: "/Photos/Job/far-away.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(30))
        )
        let (model, _) = try makeModelWithCatalogAssets(named: "no-stack-nav-previous", assets: [lonely, farAway])
        model.select(farAway.id)

        try model.applyCullingShortcut(.previousCandidateInStack)

        XCTAssertEqual(model.selectedAssetID, lonely.id)
    }

    // Secondary requirement: ←/→ stack-to-stack navigation lands on the new
    // stack's AI-recommended frame (highest quality score), not always frame 1.
    func testNextStackForCullingLandsOnRecommendedFrame() throws {
        let capturedAt = Date(timeIntervalSince1970: 500)
        let firstStackLead = makeAsset(
            id: "first-stack-lead",
            path: "/Photos/Job/first-stack-lead.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let firstStackAlt = makeAsset(
            id: "first-stack-alt",
            path: "/Photos/Job/first-stack-alt.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
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
            named: "next-stack-recommended",
            assets: [firstStackLead, firstStackAlt, secondStackLead, secondStackBest]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: secondStackLead.id, kind: .focus, value: .score(0.4), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: secondStackBest.id, kind: .focus, value: .score(0.95), confidence: 0.9, provenance: provenance)
        ])
        model.select(firstStackLead.id)

        try model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(model.selectedAssetID, secondStackBest.id)
    }

    // When the destination stack's leaders are too close to call, there's no
    // single defensible AI winner to land on — landing falls back to the
    // first tied leader (capture order), not frame 1 and not an arbitrary
    // pick from the raw-score ranking.
    func testNextStackForCullingLandsOnFirstTiedLeaderWhenTooCloseToCall() throws {
        let capturedAt = Date(timeIntervalSince1970: 500)
        let firstStackLead = makeAsset(
            id: "first-stack-lead",
            path: "/Photos/Job/first-stack-lead.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let firstStackAlt = makeAsset(
            id: "first-stack-alt",
            path: "/Photos/Job/first-stack-alt.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let secondStackLead = makeAsset(
            id: "second-stack-lead",
            path: "/Photos/Job/second-stack-lead.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(30))
        )
        let secondStackAlt = makeAsset(
            id: "second-stack-alt",
            path: "/Photos/Job/second-stack-alt.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(31))
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "next-stack-tied",
            assets: [firstStackLead, firstStackAlt, secondStackLead, secondStackAlt]
        )
        let provenance = ProviderProvenance(provider: "local-image-metrics", model: "focus", version: "2", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: secondStackLead.id, kind: .focus, value: .score(0.80), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: secondStackAlt.id, kind: .focus, value: .score(0.79), confidence: 0.9, provenance: provenance)
        ])
        model.select(firstStackLead.id)

        try model.applyCullingShortcut(.nextStack)

        XCTAssertEqual(model.selectedAssetID, secondStackLead.id)
    }

    // MARK: - Fixtures (mirrors StackDecisionTests' private helpers; kept local per file)

    private func makeStackOfThree(selected id: String) throws -> (AppModel, CatalogRepository) {
        let capturedAt = Date(timeIntervalSince1970: 100)
        let a = makeAsset(
            id: "a",
            path: "/Photos/Job/a.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt)
        )
        let b = makeAsset(
            id: "b",
            path: "/Photos/Job/b.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1))
        )
        let c = makeAsset(
            id: "c",
            path: "/Photos/Job/c.cr2",
            technicalMetadata: Self.technicalMetadata(capturedAt: capturedAt.addingTimeInterval(1.8))
        )
        let (model, repository) = try makeModelWithCatalogAssets(named: "stack-of-three-\(id)", assets: [a, b, c])
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
