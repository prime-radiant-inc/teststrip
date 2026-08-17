import XCTest
@testable import TeststripCore
@testable import TeststripApp

// After import completion, the model must reload assets/totalAssetCount
// through the *current library scope* (currentLibraryQuery), not the
// unscoped catalogContents(query: nil) the background task used. Otherwise
// a folder or smart-collection scope is silently blown away to "all photos"
// the moment an import finishes.
//
// To isolate the scoping fix from presentCompletedImportResultIfNeeded (which
// deliberately switches to the import output set when a scope is active), the
// stubbed import reports importedAssets: [] so the presentation switch is
// suppressed.  The background task still upserts an out-of-scope asset, so the
// unscoped output.assets would include it if the old code path were in use.
final class ImportCompletionScopingTests: XCTestCase {

    @MainActor
    func testImportCompletionRespectsTheCurrentLibraryScope() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-import-scoping-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let paths = AppCatalog.defaultPaths(
            applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)
        )
        let catalog = try AppCatalog.open(paths: paths)

        // Asset inside the selected folder scope.
        let insideAsset = Asset(
            id: AssetID(rawValue: "inside-scope"),
            originalURL: URL(fileURLWithPath: "/Photos/A/inside.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        // Asset outside the selected folder scope.
        let outsideAsset = Asset(
            id: AssetID(rawValue: "outside-scope"),
            originalURL: URL(fileURLWithPath: "/Photos/B/outside.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 20, modificationDate: Date(timeIntervalSince1970: 20)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert([insideAsset, outsideAsset])

        // Asset the background task upserts during import — outside the scope.
        let upsertedAsset = Asset(
            id: AssetID(rawValue: "upserted-outside"),
            originalURL: URL(fileURLWithPath: "/Photos/C/new.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 30, modificationDate: Date(timeIntervalSince1970: 30)),
            availability: .online,
            metadata: AssetMetadata()
        )

        let model = try AppModel.load(
            catalog: catalog,
            importTaskFactory: { factoryPaths, _, _, _ in
                Task.detached {
                    let backgroundCatalog = try AppCatalog.open(paths: factoryPaths)
                    try backgroundCatalog.repository.upsert(upsertedAsset)
                    // importedAssets is empty so presentCompletedImportResultIfNeeded
                    // does not switch to an import output set.  The unscoped
                    // output.assets still includes all three assets.
                    return AppImportOutput(
                        result: LibraryImportResult(
                            importedAssets: [],
                            previewFailures: [],
                            skippedSourceFiles: [],
                            newAssetCount: 0,
                            existingAssetCount: 1
                        ),
                        assets: try backgroundCatalog.repository.allAssets(limit: 500),
                        totalAssetCount: try backgroundCatalog.repository.assetCount()
                    )
                }
            }
        )

        // Select a folder scope that includes only /Photos/A.
        try model.selectSource(.folder("/Photos/A"))
        XCTAssertEqual(
            model.assets.map(\.id),
            [insideAsset.id],
            "fixture check: the scope should contain only the inside-scope asset"
        )
        XCTAssertEqual(model.totalAssetCount, 1, "fixture check: totalAssetCount should be scoped")

        // Begin the import. The stubbed factory upserts an asset in /Photos/C
        // (outside the scope) and returns ALL assets unscoped.
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        model.beginImportFolder(photoFolder)

        // Wait for the import to complete.
        for _ in 0..<200 {
            if model.recentWork.first?.status == .completed { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(model.recentWork.first?.status, .completed, "import must complete")

        // After completion, the scope must be preserved: only the inside-scope
        // asset should be in model.assets, and totalAssetCount must be scoped.
        // The unscoped output.assets includes all 3 assets; a correct scoped
        // reload includes only the 1 asset in /Photos/A.
        XCTAssertEqual(
            model.assets.map(\.id),
            [insideAsset.id],
            "import completion must reload through the current scope, not the unscoped background output"
        )
        XCTAssertEqual(
            model.totalAssetCount, 1,
            "totalAssetCount must reflect the scoped count after import completion"
        )
    }
}
