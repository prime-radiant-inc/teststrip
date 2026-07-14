import TeststripCore
import XCTest
@testable import TeststripApp

/// Covers `photoFacesPresentation(for:)`'s AppModel-level assembly: it
/// gathers one photo's face observations and its `person_faces` links (via
/// `personFaces`, name-resolved against `catalogPeople`), split into
/// confirmed (`origin='user'`) vs. suggested (`origin='ai'`) by that same
/// read, into one `PhotoFacesPresentation`. Task 11 moved `suggested` off
/// the in-memory `peopleFaceSuggestions` array onto this persisted read —
/// these tests never call `refreshPeopleFaceSuggestions()`, so a passing
/// `.suggested` row here proves the persisted origin drives it. The
/// row-state precedence itself (confirmed wins over suggested) is
/// `PhotoFacesPresentationTests`' job — this file is about the AppModel
/// plumbing that feeds it.
final class PhotoFacesPresentationAssemblyTests: XCTestCase {
    func testConfirmedFaceResolvesNameFromCatalogPeople() throws {
        let (catalog, repository, _) = try makeCatalog(named: "confirmed-assembly")
        try seedFaceObservations(repository, assetID: "a", embeddings: [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
        try repository.upsertPerson(id: "p1", name: "Jesse")
        try repository.assignFaces([FaceID(assetID: AssetID(rawValue: "a"), faceIndex: 0)], toPersonID: "p1")

        let model = try AppModel.load(catalog: catalog)
        let presentation = model.photoFacesPresentation(for: AssetID(rawValue: "a"))

        XCTAssertEqual(presentation.rows.map(\.state), [
            .confirmed(personID: "p1", name: "Jesse"),
            .unnamed,
            .unnamed
        ])
    }

    func testSuggestedFaceResolvesFromPersistedAIOriginRow() throws {
        // A face's persisted origin='ai' person_faces row (as `insertAIFace`/
        // `promoteFaceMatches` create) is what drives `.suggested` now — the
        // in-memory `peopleFaceSuggestions` array is never refreshed here,
        // proving it's not the source.
        let (catalog, repository, _) = try makeCatalog(named: "suggested-assembly")
        try seedFaceObservations(repository, assetID: "a", embeddings: [[1, 0, 0], [0, 1, 0]])
        try repository.upsertPerson(id: "p1", name: "Casey")
        try repository.insertAIFace(assetID: AssetID(rawValue: "a"), faceIndex: 0, personID: "p1")

        let model = try AppModel.load(catalog: catalog)
        let presentation = model.photoFacesPresentation(for: AssetID(rawValue: "a"))

        XCTAssertEqual(presentation.rows.map(\.state), [
            .suggested(personID: "p1", name: "Casey"),
            .unnamed
        ])
        XCTAssertTrue(model.peopleFaceSuggestions.isEmpty)
    }

    func testUnknownAssetYieldsNoRows() throws {
        let (catalog, _, _) = try makeCatalog(named: "empty-assembly")
        let model = try AppModel.load(catalog: catalog)
        let presentation = model.photoFacesPresentation(for: AssetID(rawValue: "missing"))
        XCTAssertTrue(presentation.rows.isEmpty)
    }

    // MARK: - Test support

    private func makeCatalog(named name: String) throws -> (AppCatalog, CatalogRepository, CatalogDatabase) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
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
        return (catalog, repository, database)
    }

    private func seedFaceObservations(
        _ repository: CatalogRepository,
        assetID: String,
        embeddings: [[Double]]
    ) throws {
        let asset = makeAsset(id: assetID, path: "/Volumes/NAS/Wedding/\(assetID).jpg")
        try repository.upsert([asset])
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        let observations = embeddings.enumerated().map { index, embedding in
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: index,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.9,
                embedding: embedding,
                provenance: provenance
            )
        }
        try repository.replaceFaceObservations(assetID: asset.id, provenance: provenance, with: observations)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-photo-faces-assembly-tests", isDirectory: true)
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
