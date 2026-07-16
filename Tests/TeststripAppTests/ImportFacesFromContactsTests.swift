import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TeststripCore
@testable import TeststripApp

private struct StubContacts: ContactsProviding {
    let records: [ContactRecord]
    func contactsWithPhotos() throws -> [ContactRecord] { records }
}

final class ImportFacesFromContactsTests: XCTestCase {
    @MainActor
    func testImportSeedsReferenceAndRefreshes() async throws {
        // Build a model whose load injects the stub provider + a stub detector.
        // (Harness mirrors PeopleFaceSuggestionRejectionTests.makeModelWithCatalogAssets,
        // but calls AppModel.load with contactsProvider:/contactFaceDetector:.)
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let jpeg = tinyJPEG()
        let (model, repo) = try makeModelWithContacts(
            named: "import-contacts", assets: [a],
            provider: StubContacts(records: [ContactRecord(identifier: "C1", name: "Dan Shapiro", imageData: jpeg)]),
            detectFaces: { _ in [AppleVisionFaceObservation(
                boundingBox: FaceBoundingBox(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                captureQuality: 0.9, featurePrintVector: [1, 0, 0])] })

        try await model.importFacesFromContacts()

        XCTAssertEqual(try repo.contactReferenceNamesByPerson()["contact:C1"], "Dan Shapiro")
        XCTAssertTrue(model.statusMessage?.contains("seeded") ?? false, "expected a status message reporting the seeded count, got \(String(describing: model.statusMessage))")
    }

    // MARK: - Test support

    private func makeModelWithContacts(
        named name: String,
        assets: [Asset],
        provider: any ContactsProviding,
        detectFaces: @escaping @Sendable (CGImage) throws -> [AppleVisionFaceObservation]
    ) throws -> (model: AppModel, repository: CatalogRepository) {
        let directory = try makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("Teststrip/catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, contactsProvider: provider, contactFaceDetector: detectFaces)
        return (model, repository)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-import-faces-from-contacts-tests", isDirectory: true)
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

    // A tiny valid JPEG so decoding succeeds; face detection is stubbed via the seam.
    private func tinyJPEG() -> Data {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cg = ctx.makeImage()!
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, nil); CGImageDestinationFinalize(dest)
        return data as Data
    }
}
