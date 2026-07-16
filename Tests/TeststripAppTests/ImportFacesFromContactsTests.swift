import CoreGraphics
import Dispatch
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TeststripCore
@testable import TeststripApp

private struct StubContacts: ContactsProviding {
    let records: [ContactRecord]
    func contactsWithPhotos() throws -> [ContactRecord] { records }
}

/// Thread-safe call counter for detectors invoked off the MainActor (inside
/// `importFacesFromContacts`'s `Task.detached` seeding work).
private final class ThreadSafeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    var value: Int {
        lock.withLock { count }
    }
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

    /// Reentry guard: `importFacesFromContacts()` must be a silent no-op when
    /// called while an import is already in flight (belt-and-suspenders behind
    /// the menu's `.disabled(isImportingContacts)`), so a second call can never
    /// race a concurrent detached seed against `contact_reference_faces`.
    ///
    /// Asserts, with a real in-flight import (not a simulated flag): while the
    /// first call is blocked mid-detection, a reentrant call returns promptly
    /// without ever reaching the detector a second time; once the first call
    /// is unblocked it completes normally, seeds exactly once, and leaves
    /// `isImportingContacts` false.
    @MainActor
    func testReentrantImportWhileFirstImportInFlightIsANoOp() async throws {
        let a = makeAsset(id: "a1", path: "/p/a1.jpg")
        let jpeg = tinyJPEG()
        let detectorCallCount = ThreadSafeCounter()
        let releaseGate = DispatchSemaphore(value: 0)
        let (model, repo) = try makeModelWithContacts(
            named: "import-contacts-reentrant", assets: [a],
            provider: StubContacts(records: [ContactRecord(identifier: "C1", name: "Dan Shapiro", imageData: jpeg)]),
            detectFaces: { _ in
                detectorCallCount.increment()
                releaseGate.wait()
                return [AppleVisionFaceObservation(
                    boundingBox: FaceBoundingBox(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                    captureQuality: 0.9, featurePrintVector: [1, 0, 0])]
            })

        let firstImport = Task { try await model.importFacesFromContacts() }

        // Let the first call run onto the MainActor, set the flag, hand off to
        // its detached seeding work, and block inside the detector.
        for _ in 0..<200 where detectorCallCount.value == 0 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(detectorCallCount.value, 1, "expected the first import's detector to have started")
        XCTAssertTrue(model.isImportingContacts)

        // Reentrant call while the first is still blocked mid-detection. Race
        // it against a bounded timeout rather than awaiting it directly, so a
        // regressed guard fails the assertion below instead of hanging the test.
        let secondCallReturned = ThreadSafeCounter()
        let secondImport = Task { try await model.importFacesFromContacts(); secondCallReturned.increment() }
        for _ in 0..<40 where secondCallReturned.value == 0 {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(secondCallReturned.value, 1, "reentrant call should return immediately via the guard, without waiting on the in-flight import")
        XCTAssertEqual(detectorCallCount.value, 1, "reentrant call must not invoke the detector a second time")

        // Signal twice unconditionally (not once) so a regressed guard — which
        // would let the reentrant call reach the detector too, blocking a
        // second waiter on this gate — can't hang the test: at most two calls
        // (first + reentrant) ever reach the detector here, so two signals
        // always clear the gate regardless of whether the guard held.
        releaseGate.signal()
        releaseGate.signal()
        try await firstImport.value
        try await secondImport.value

        XCTAssertFalse(model.isImportingContacts)
        XCTAssertEqual(try repo.contactReferenceNamesByPerson()["contact:C1"], "Dan Shapiro")
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
