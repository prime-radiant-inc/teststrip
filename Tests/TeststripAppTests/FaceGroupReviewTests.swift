import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// Covers the model side of the face-group review surface: resolving each
/// face's bounding box for the large zoomed tiles, and the "remove this face"
/// gesture, which reuses the foundation's sticky reject / dismiss and never
/// writes a person assignment (confirm-before-write).
final class FaceGroupReviewTests: XCTestCase {
    func testReviewResolvesEachFaceBoundingBoxInStableOrder() throws {
        let (model, _, _, incoming, secondIncoming) = try makeFaceSuggestionModel(named: "review-tiles")
        model.refreshPeopleFaceSuggestions()
        let suggestion = try XCTUnwrap(
            model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" }
        )

        let review = model.faceGroupReview(for: suggestion)

        XCTAssertEqual(review.title, "Is this Maya?")
        // Both incoming faces (each in its own asset) resolve to a tile, in
        // asset-id then face-index order.
        XCTAssertEqual(review.tiles.map(\.faceID), [
            FaceID(assetID: incoming.id, faceIndex: 0),
            FaceID(assetID: secondIncoming.id, faceIndex: 0)
        ])
        XCTAssertEqual(review.tiles[0].boundingBox, FaceBoundingBox(x: 0.10, y: 0.10, width: 0.2, height: 0.2))
        XCTAssertEqual(review.tiles[1].boundingBox, FaceBoundingBox(x: 0.50, y: 0.50, width: 0.2, height: 0.2))
        XCTAssertEqual(review.remainingPhotoCount, 2)
    }

    func testRemovingAMatchedFaceRejectsItStickyAndShrinksTheGroup() throws {
        let (model, repository, _, incoming, secondIncoming) = try makeFaceSuggestionModel(named: "review-remove-match")
        model.refreshPeopleFaceSuggestions()
        let suggestion = try XCTUnwrap(
            model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" }
        )
        let removedFace = FaceID(assetID: incoming.id, faceIndex: 0)

        try model.removeFaceFromReviewGroup(suggestion, faceID: removedFace)

        // Sticky rejection recorded so recognition stops re-proposing Maya here.
        XCTAssertTrue(try repository.rejectedFacePeople().contains(
            RejectedFacePerson(assetID: incoming.id, faceIndex: 0, personID: "person-maya")
        ))
        // Confirm-before-write: no person assignment was written for the
        // removed face, and Maya gains no confirmed photo beyond her seed
        // (the `known` face) — the removed incoming photo is not added.
        XCTAssertTrue(try repository.personFaces(assetID: incoming.id).isEmpty)
        XCTAssertEqual(try repository.people().first { $0.id == "person-maya" }?.assetCount, 1)
        // The group shrinks to the face that was left.
        let shrunk = try XCTUnwrap(
            model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" }
        )
        XCTAssertEqual(shrunk.faceIDs, [FaceID(assetID: secondIncoming.id, faceIndex: 0)])
        XCTAssertFalse(shrunk.faceIDs.contains(removedFace))
    }

    func testRemovingAClusteredFaceDismissesItFromReview() throws {
        let (model, repository, _, incoming, _) = try makeFaceSuggestionModel(named: "review-remove-cluster")
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        let removedFace = FaceID(assetID: incoming.id, faceIndex: 0)
        // A new-cluster group's faces have no matched person; removing one
        // dismisses it rather than recording a person rejection.
        let clusterSuggestion = PeopleFaceSuggestion(
            id: "face-cluster-\(incoming.id.rawValue)-0",
            kind: .newPerson,
            faceIDs: [removedFace],
            representativeFace: removedFace,
            representativeBoundingBox: FaceBoundingBox(x: 0.10, y: 0.10, width: 0.2, height: 0.2),
            assetIDs: [incoming.id]
        )

        try model.removeFaceFromReviewGroup(clusterSuggestion, faceID: removedFace)

        // Dismissed, not rejected: it drops out of the unassigned review pool
        // and records no person rejection.
        let stillUnassigned = try repository.unassignedFaceObservations(provenance: provenance, limit: 100)
        XCTAssertFalse(stillUnassigned.contains { $0.faceID == removedFace })
        XCTAssertTrue(try repository.rejectedFacePeople().isEmpty)
        XCTAssertTrue(try repository.personFaces(assetID: incoming.id).isEmpty)
    }

    // MARK: - Test support (mirrors PeopleFaceSuggestionRejectionTests)

    private func makeFaceSuggestionModel(
        named name: String
    ) throws -> (model: AppModel, repository: CatalogRepository, known: Asset, incoming: Asset, secondIncoming: Asset) {
        let known = makeAsset(id: "known", path: "/Volumes/NAS/Wedding/known.jpg")
        let incoming = makeAsset(id: "incoming", path: "/Volumes/NAS/Wedding/incoming.jpg")
        let secondIncoming = makeAsset(id: "incoming2", path: "/Volumes/NAS/Wedding/incoming2.jpg")
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        func observation(_ asset: Asset, box: FaceBoundingBox, _ embedding: [Double]) -> CatalogFaceObservation {
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 0,
                boundingBox: box,
                captureQuality: 0.9,
                embedding: embedding,
                provenance: provenance
            )
        }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: name,
            assets: [known, incoming, secondIncoming],
            configureRepository: { repository in
                try repository.replaceFaceObservations(assetID: known.id, provenance: provenance, with: [
                    observation(known, box: FaceBoundingBox(x: 0.30, y: 0.30, width: 0.2, height: 0.2), [1, 0, 0])
                ])
                try repository.replaceFaceObservations(assetID: incoming.id, provenance: provenance, with: [
                    observation(incoming, box: FaceBoundingBox(x: 0.10, y: 0.10, width: 0.2, height: 0.2), [0.99, 0.1, 0])
                ])
                try repository.replaceFaceObservations(assetID: secondIncoming.id, provenance: provenance, with: [
                    observation(secondIncoming, box: FaceBoundingBox(x: 0.50, y: 0.50, width: 0.2, height: 0.2), [0.99, -0.1, 0])
                ])
                try repository.upsertPerson(id: "person-maya", name: "Maya")
                try repository.assignFaces([FaceID(assetID: known.id, faceIndex: 0)], toPersonID: "person-maya")
            }
        )
        return (model, repository, known, incoming, secondIncoming)
    }

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
            .appendingPathComponent("teststrip-face-group-review-tests", isDirectory: true)
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
