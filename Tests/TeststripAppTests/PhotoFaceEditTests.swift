import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// Covers Task 4: per-photo, per-face edit gestures on `AppModel`
/// (`nameFace`, `removeFacePerson`, `rejectFaceSuggestion`) wrap the repo
/// and write ONLY on the explicit gesture. The confirm-before-write
/// assertion reads `person_faces` directly — not `assetIDs(personID:)`,
/// which reads the different `person_assets` table and would make the
/// test vacuous (the trap Task 1 already hit).
final class PhotoFaceEditTests: XCTestCase {
    func testNameFaceWritesPersonFaceOnlyOnGesture() throws {
        let (model, _, db) = try makeModelWithOneFace(named: "name-face")
        let faceID = FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0)

        XCTAssertTrue(try personFaceRows(db, assetID: "a").isEmpty)

        try model.nameFace(faceID, newPersonName: "Jesse")

        XCTAssertEqual(try personFaceRows(db, assetID: "a").count, 1)
    }

    func testRejectRecordsNegativeThenNameClearsItAndRemoveClearsPerson() throws {
        let (model, repository, db) = try makeModelWithOneFace(named: "reject-name-remove")
        let faceID = FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0)
        try repository.upsertPerson(id: "p1", name: "Pat")

        try model.rejectFaceSuggestion(faceID, personID: "p1")
        XCTAssertTrue(try repository.rejectedFacePeople().contains {
            $0.assetID.rawValue == "a" && $0.faceIndex == 0 && $0.personID == "p1"
        })

        try model.nameFace(faceID, personID: "p1")
        XCTAssertFalse(try repository.rejectedFacePeople().contains {
            $0.assetID.rawValue == "a" && $0.faceIndex == 0 && $0.personID == "p1"
        })
        XCTAssertEqual(try personFaceRows(db, assetID: "a").count, 1)

        try model.removeFacePerson(faceID)
        XCTAssertTrue(try personFaceRows(db, assetID: "a").isEmpty)
    }

    // MARK: - Test support

    private func personFaceRows(_ db: CatalogDatabase, assetID: String) throws -> [[String: String]] {
        try db.rows(
            "SELECT face_index, person_id FROM person_faces WHERE asset_id = ?",
            bindings: [assetID]
        )
    }

    private func makeModelWithOneFace(named name: String) throws -> (AppModel, CatalogRepository, CatalogDatabase) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "a", path: "/Volumes/NAS/Wedding/a.jpg")
        try repository.upsert([asset])
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        try repository.replaceFaceObservations(
            assetID: asset.id,
            provenance: provenance,
            with: [
                CatalogFaceObservation(
                    assetID: asset.id,
                    faceIndex: 0,
                    boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                    captureQuality: 0.9,
                    embedding: [1, 0, 0],
                    provenance: provenance
                )
            ]
        )
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
        return (model, repository, database)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-photo-face-edit-tests", isDirectory: true)
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
