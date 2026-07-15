import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class RankedPersonCandidatesTests: XCTestCase {
    private let provenance = AppleVisionEvaluationProvider.faceProvenance

    private func obs(_ id: AssetID, _ vec: [Double]) -> CatalogFaceObservation {
        CatalogFaceObservation(assetID: id, faceIndex: 0,
                               boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                               captureQuality: 0.9, embedding: vec, provenance: provenance)
    }

    func testRanksConfirmedPeopleBySimilarityToTargetFace() throws {
        // People + their confirmed faces are seeded BEFORE AppModel.load, which
        // populates catalogPeople via its loadCatalogPeople — so no test shim is
        // needed to refresh catalogPeople.
        let target = makeAsset(id: "t", path: "/p/t.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "rank-similarity", assets: [target]) { repo in
            try repo.replaceFaceObservations(assetID: target.id, provenance: self.provenance, with: [self.obs(target.id, [1, 0, 0])])
            try repo.upsertPerson(id: "p-near", name: "Near")
            try repo.replaceFaceObservations(assetID: AssetID(rawValue: "near"), provenance: self.provenance, with: [self.obs(AssetID(rawValue: "near"), [1, 0, 0])])
            try repo.assignFaces([FaceID(assetID: AssetID(rawValue: "near"), faceIndex: 0)], toPersonID: "p-near")
            try repo.upsertPerson(id: "p-far", name: "Far")
            try repo.replaceFaceObservations(assetID: AssetID(rawValue: "far"), provenance: self.provenance, with: [self.obs(AssetID(rawValue: "far"), [0, 1, 0])])
            try repo.assignFaces([FaceID(assetID: AssetID(rawValue: "far"), faceIndex: 0)], toPersonID: "p-far")
        }

        let ranked = model.rankedPersonCandidates(forFace: FaceID(assetID: target.id, faceIndex: 0))
        XCTAssertEqual(ranked.first?.id, "p-near")
        XCTAssertEqual(ranked.first?.similarityPercent, 100)
        XCTAssertTrue((ranked.first { $0.id == "p-far" }?.similarityPercent ?? 100) < 100)
    }

    func testNoTargetFaceOrdersByRecency() throws {
        // Drive a real assign so recency is exercised honestly (no shim).
        let a = makeAsset(id: "a", path: "/p/a.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "rank-recency", assets: [a]) { repo in
            try repo.upsertPerson(id: "p1", name: "Ann")
            try repo.upsertPerson(id: "p2", name: "Bob")
            try repo.replaceFaceObservations(assetID: a.id, provenance: self.provenance, with: [self.obs(a.id, [1, 0, 0])])
        }
        // Name a face as p2 (Bob) → p2 becomes most-recently-named.
        try model.nameFace(FaceID(assetID: a.id, faceIndex: 0), personID: "p2")

        let ranked = model.rankedPersonCandidates(forFace: nil)
        XCTAssertEqual(ranked.map(\.id), ["p2", "p1"]) // p2 recent first, then Ann alpha
    }

    // MARK: - Test support (copied from FaceGroupReviewTests.swift; kept private per file)

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset],
        configureRepository: (CatalogRepository) throws -> Void = { _ in }
    ) throws -> (AppModel, CatalogRepository) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        try configureRepository(repository)
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

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-ranked-person-candidates-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeAsset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Test",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(rating: 0)
        )
    }
}
