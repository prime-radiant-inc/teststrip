import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// Covers Task 5: the face matcher must union contact reference embeddings
/// into the confirmed-person centroid dict, so a catalog face near a contact
/// reference surfaces as a suggestion (latent contacts) or auto-applies
/// (name-attached contacts) — but a latent contact (no `people` row) must
/// never be auto-applied, since that would write an invisible orphan
/// `person_faces` row.
final class ContactReferenceMatchingTests: XCTestCase {
    private let provenance = AppleVisionEvaluationProvider.faceProvenance

    private func obs(_ id: AssetID, _ vec: [Double]) -> CatalogFaceObservation {
        CatalogFaceObservation(assetID: id, faceIndex: 0,
                               boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                               captureQuality: 0.9, embedding: vec, provenance: provenance)
    }

    func testLatentContactMatchSurfacesAsSuggestion() throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let (model, repo) = try makeModelWithCatalogAssets(named: "contact-latent-suggest", assets: [a])
        try repo.replaceFaceObservations(assetID: a.id, provenance: provenance, with: [obs(a.id, [1, 0, 0])])
        try repo.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan Shapiro",
                                            embedding: [1, 0, 0], boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                            photoHash: "h")

        model.refreshPeopleFaceSuggestions()

        let s = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-contact:C1" })
        XCTAssertEqual(s.kind, .matchExisting(personID: "contact:C1", personName: "Dan Shapiro"))
    }

    func testLatentContactMatchIsNotAutoApplied() throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let (model, repo) = try makeModelWithCatalogAssets(named: "contact-latent-noautoapply", assets: [a])
        try repo.replaceFaceObservations(assetID: a.id, provenance: provenance, with: [obs(a.id, [1, 0, 0])])
        try repo.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan",
                                            embedding: [1, 0, 0], boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                            photoHash: "h")

        try model.promoteFaceMatches(for: a.id)

        // No orphan person_faces row for the latent contact.
        // personFaces(assetID:) -> [Int: PersonFaceAssignment] (keyed by face index).
        XCTAssertTrue(try repo.personFaces(assetID: a.id).isEmpty)
    }

    func testNameAttachedContactMatchAutoApplies() throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let (model, repo) = try makeModelWithCatalogAssets(named: "contact-attached-autoapply", assets: [a])
        try repo.upsertPerson(id: "p1", name: "Dan Shapiro")
        try repo.replaceFaceObservations(assetID: a.id, provenance: provenance, with: [obs(a.id, [1, 0, 0])])
        try repo.upsertContactReferenceFace(contactIdentifier: "C1", personID: "p1", name: "Dan Shapiro",
                                            embedding: [1, 0, 0], boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                            photoHash: "h")

        try model.promoteFaceMatches(for: a.id)

        let assignment = try XCTUnwrap(try repo.personFaces(assetID: a.id)[0])
        XCTAssertEqual(assignment.personID, "p1")   // auto-applied…
        XCTAssertEqual(assignment.origin, "ai")     // …as a tentative proposal
    }

    // MARK: - Test support

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
            .appendingPathComponent("teststrip-contact-reference-matching-tests", isDirectory: true)
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

extension ContactReferenceMatchingTests {
    func testConfirmingLatentContactSuggestionCreatesConfirmedPerson() throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let (model, repo) = try makeModelWithCatalogAssets(named: "contact-confirm-materialize", assets: [a])
        try repo.replaceFaceObservations(assetID: a.id, provenance: provenance, with: [obs(a.id, [1, 0, 0])])
        try repo.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan Shapiro",
                                            embedding: [1, 0, 0], boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                            photoHash: "h")
        model.refreshPeopleFaceSuggestions()
        let s = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-contact:C1" })

        try model.confirmPeopleFaceSuggestion(s)

        XCTAssertEqual(model.catalogPeople.first { $0.id == "contact:C1" }?.name, "Dan Shapiro")
        XCTAssertEqual(try repo.assetIDs(personID: "contact:C1"), [a.id]) // confirmed person_assets
    }

    func testLatentContactWithNoMatchCreatesNoPerson() throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let (model, repo) = try makeModelWithCatalogAssets(named: "contact-nomatch-noperson", assets: [a])
        // Catalog face is FAR from the reference embedding → no match.
        try repo.replaceFaceObservations(assetID: a.id, provenance: provenance, with: [obs(a.id, [0, 1, 0])])
        try repo.upsertContactReferenceFace(contactIdentifier: "C1", personID: "contact:C1", name: "Dan",
                                            embedding: [1, 0, 0], boundingBox: FaceBoundingBox(x: 0, y: 0, width: 1, height: 1),
                                            photoHash: "h")
        model.refreshPeopleFaceSuggestions()
        XCTAssertNil(model.peopleFaceSuggestions.first { $0.id == "face-match-contact:C1" })
        XCTAssertTrue(model.catalogPeople.isEmpty) // no phantom person
    }
}
