import XCTest
@testable import TeststripCore
@testable import TeststripApp

// App-layer plumbing for the sidecar rescan (Jesse's ruling 2026-07-11):
// the launch/menu check finds out-of-band sidecar edits, refreshes the
// model's sync counts, and reports through statusMessage.
final class SidecarRescanAppTests: XCTestCase {
    @MainActor
    func testCheckSidecarsForChangesFlagsOutOfBandEditAndRefreshesCounts() async throws {
        let directory = try makeTemporaryDirectory(named: "app-rescan-edit")
        let (model, repository, sidecarURL, assetID) = try makeModelWithSyncedSidecar(directory: directory)

        // Out-of-band edit after the clean sync.
        let editedData = try XMPPacket(metadata: AssetMetadata(rating: 5)).xmlData()
        try editedData.write(to: sidecarURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: sidecarURL.path
        )

        let summary = try await model.checkSidecarsForChanges()

        XCTAssertEqual(summary.pendingCount, 1)
        XCTAssertEqual(summary.conflictCount, 0)
        XCTAssertNotNil(try repository.pendingMetadataSyncItem(assetID: assetID))
        XCTAssertEqual(model.pendingMetadataSyncCount, 1)
        XCTAssertEqual(
            model.statusMessage,
            "Checked 1 sidecar — 1 changed on disk, queued to re-sync"
        )
    }

    @MainActor
    func testCheckSidecarsForChangesIsQuietWhenNothingChangedUnlessAsked() async throws {
        let directory = try makeTemporaryDirectory(named: "app-rescan-clean")
        let (model, repository, sidecarURL, assetID) = try makeModelWithSyncedSidecar(directory: directory)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: sidecarURL.path
        )

        let quietSummary = try await model.checkSidecarsForChanges()
        XCTAssertEqual(quietSummary, SidecarRescanSummary(scannedCount: 1))
        XCTAssertNil(model.statusMessage)

        let announcedSummary = try await model.checkSidecarsForChanges(announceWhenUnchanged: true)
        XCTAssertEqual(announcedSummary, SidecarRescanSummary(scannedCount: 1))
        XCTAssertEqual(model.statusMessage, "Checked 1 sidecar — no changes")
        XCTAssertNil(try repository.pendingMetadataSyncItem(assetID: assetID))
    }

    // persona-6 Priya: with the Pick chip still active from an earlier task,
    // Metadata ▸ Check Sidecars for Changes silently skipped every unpicked
    // asset — a real out-of-band edit went permanently unnoticed. The menu
    // command is a catalog-integrity check: it must walk the whole catalog
    // regardless of the active library filter.
    @MainActor
    func testMenuCheckIgnoresActiveLibraryFilterAndFindsEdit() async throws {
        let directory = try makeTemporaryDirectory(named: "app-rescan-filtered")
        let (model, repository, sidecarURL, assetID) = try makeModelWithSyncedSidecar(directory: directory)
        // Active filter that excludes the (unflagged) edited asset.
        model.flagFilter = .pick

        let editedData = try XMPPacket(metadata: AssetMetadata(rating: 2, caption: "edited by exiftool-sim")).xmlData()
        try editedData.write(to: sidecarURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: sidecarURL.path
        )

        await model.checkSidecarsForChangesInCurrentScope()

        XCTAssertNotNil(try repository.pendingMetadataSyncItem(assetID: assetID))
        XCTAssertEqual(model.statusMessage, "Checked 1 sidecar — 1 changed on disk, queued to re-sync")
    }

    // The command used to finish in total silence; silence is
    // indistinguishable from broken. The menu path always reports.
    @MainActor
    func testMenuCheckReportsCompletionWhenNothingChanged() async throws {
        let directory = try makeTemporaryDirectory(named: "app-rescan-report")
        let (model, _, sidecarURL, _) = try makeModelWithSyncedSidecar(directory: directory)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: sidecarURL.path
        )

        await model.checkSidecarsForChangesInCurrentScope()

        XCTAssertEqual(model.statusMessage, "Checked 1 sidecar — no changes")
    }

    // MARK: - Fixtures

    @MainActor
    private func makeModelWithSyncedSidecar(
        directory: URL
    ) throws -> (AppModel, CatalogRepository, URL, AssetID) {
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("Teststrip/catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assetID = AssetID(rawValue: "rescan-asset")
        let originalURL = directory.appendingPathComponent("photo.jpg")
        try Data("jpeg-bytes".utf8).write(to: originalURL)
        let metadata = AssetMetadata(rating: 3)
        try repository.upsert([Asset(
            id: assetID,
            originalURL: originalURL,
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: metadata
        )])
        let sidecarURL = originalURL.appendingPathExtension("xmp")
        let sidecarData = try XMPPacket(metadata: metadata).xmlData()
        try sidecarData.write(to: sidecarURL)
        try repository.markMetadataSynced(
            assetID: assetID,
            sidecarURL: sidecarURL,
            catalogGeneration: try repository.catalogGeneration(assetID: assetID),
            fingerprint: XMPSidecarStore.fingerprint(for: sidecarData)
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3600)],
            ofItemAtPath: sidecarURL.path
        )
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
        let model = try AppModel.load(catalog: catalog)
        return (model, repository, sidecarURL, assetID)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
