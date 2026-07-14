import SwiftUI
import XCTest
@testable import TeststripCore
@testable import TeststripApp

/// Covers Task 2: face-suggestion computation must skip any (face, person)
/// pair the user has explicitly rejected ("not them") — recognition must
/// stop re-suggesting that person for that exact face, without losing
/// suggestions for faces that were never rejected.
final class PeopleFaceSuggestionRejectionTests: XCTestCase {
    func testRejectedFaceIsExcludedButSuggestedWithoutRejection() throws {
        // WITHOUT any rejection recorded: the match suggestion for
        // person-maya includes the incoming face.
        let (modelWithoutRejection, _, _, incoming, _) = try makeFaceSuggestionModel(named: "reject-without")
        modelWithoutRejection.refreshPeopleFaceSuggestions()
        let matchWithoutRejection = try XCTUnwrap(
            modelWithoutRejection.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" }
        )
        XCTAssertTrue(matchWithoutRejection.faceIDs.contains(FaceID(assetID: incoming.id, faceIndex: 0)))

        // WITH a rejection recorded for exactly that (face, person) pair:
        // the suggestion must not propose person-maya for that face. It's
        // the only face in the match, so the whole suggestion disappears.
        let (modelWithRejection, _, _, rejectedIncoming, _) = try makeFaceSuggestionModel(
            named: "reject-with",
            configureRepository: { repository in
                try repository.recordRejectedFacePerson(assetID: AssetID(rawValue: "incoming"), faceIndex: 0, personID: "person-maya")
            }
        )
        modelWithRejection.refreshPeopleFaceSuggestions()

        XCTAssertNil(modelWithRejection.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        XCTAssertFalse(modelWithRejection.peopleFaceSuggestions.contains { suggestion in
            guard case .matchExisting(let personID, _) = suggestion.kind else { return false }
            return personID == "person-maya" && suggestion.faceIDs.contains(FaceID(assetID: rejectedIncoming.id, faceIndex: 0))
        })
    }

    func testRejectionOnlyDropsTheRejectedFaceLeavingOtherFacesInTheSameMatch() throws {
        // Two unassigned faces both match person-maya; reject only one of
        // them. The match suggestion must survive (the other face still
        // proposes person-maya) but must no longer include the rejected face.
        let (model, _, _, incoming, maybeSecondIncoming) = try makeFaceSuggestionModel(
            named: "reject-partial",
            includeSecondIncoming: true,
            configureRepository: { repository in
                try repository.recordRejectedFacePerson(assetID: AssetID(rawValue: "incoming"), faceIndex: 0, personID: "person-maya")
            }
        )
        let secondIncoming = try XCTUnwrap(maybeSecondIncoming)
        model.refreshPeopleFaceSuggestions()

        let match = try XCTUnwrap(model.peopleFaceSuggestions.first { $0.id == "face-match-person-maya" })
        XCTAssertFalse(match.faceIDs.contains(FaceID(assetID: incoming.id, faceIndex: 0)))
        XCTAssertTrue(match.faceIDs.contains(FaceID(assetID: secondIncoming.id, faceIndex: 0)))
    }

    // MARK: - Test support

    private func makeFaceSuggestionModel(
        named name: String,
        includeSecondIncoming: Bool = false,
        configureRepository: @escaping (CatalogRepository) throws -> Void = { _ in }
    ) throws -> (model: AppModel, repository: CatalogRepository, known: Asset, incoming: Asset, secondIncoming: Asset?) {
        let known = makeAsset(id: "known", path: "/Volumes/NAS/Wedding/known.jpg")
        let incoming = makeAsset(id: "incoming", path: "/Volumes/NAS/Wedding/incoming.jpg")
        let secondIncoming = includeSecondIncoming ? makeAsset(id: "incoming2", path: "/Volumes/NAS/Wedding/incoming2.jpg") : nil
        let provenance = AppleVisionEvaluationProvider.faceProvenance
        func observation(_ asset: Asset, _ embedding: [Double]) -> CatalogFaceObservation {
            CatalogFaceObservation(
                assetID: asset.id,
                faceIndex: 0,
                boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                captureQuality: 0.9,
                embedding: embedding,
                provenance: provenance
            )
        }
        var assets = [known, incoming]
        if let secondIncoming {
            assets.append(secondIncoming)
        }
        let (model, repository) = try makeModelWithCatalogAssets(
            named: name,
            assets: assets,
            configureRepository: { repository in
                try repository.replaceFaceObservations(assetID: known.id, provenance: provenance, with: [observation(known, [1, 0, 0])])
                try repository.replaceFaceObservations(assetID: incoming.id, provenance: provenance, with: [observation(incoming, [0.99, 0.1, 0])])
                if let secondIncoming {
                    try repository.replaceFaceObservations(assetID: secondIncoming.id, provenance: provenance, with: [observation(secondIncoming, [0.99, -0.1, 0])])
                }
                try repository.upsertPerson(id: "person-maya", name: "Maya")
                try repository.assignFaces([FaceID(assetID: known.id, faceIndex: 0)], toPersonID: "person-maya")
                try configureRepository(repository)
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
            .appendingPathComponent("teststrip-people-face-rejection-tests", isDirectory: true)
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
