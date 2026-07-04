import TeststripCore
import XCTest

final class WorkerEntrypointTests: XCTestCase {
    func testImportFolderCommandCatalogsThroughWorkerProcess() throws {
        let root = try makeTemporaryDirectory(named: "worker-entrypoint-import")
        let photoRoot = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoRoot, withIntermediateDirectories: true)
        let source = photoRoot.appendingPathComponent("source.jpg")
        try Data("jpg".utf8).write(to: source)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let previewCacheRoot = root.appendingPathComponent("previews", isDirectory: true)
        let workerURL = try builtWorkerExecutableURL()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = workerURL
        process.arguments = [
            "--catalog",
            catalogURL.path,
            "--preview-cache",
            previewCacheRoot.path
        ]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data(try WorkerProtocolEncoder.encode(.importFolder(root: photoRoot)).utf8))
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(stderr, "")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = try repository.allAssets(limit: 10)
        let asset = try XCTUnwrap(assets.first)
        XCTAssertEqual(try WorkerProtocolEncoder.decodeEvent(stdout), .completedImport(
            itemID: nil,
            message: "imported 1 photo from photos",
            importedAssetIDs: [asset.id],
            newAssetCount: 1,
            existingAssetCount: 0
        ))
        XCTAssertEqual(assets.map(\.originalURL), [source])
        XCTAssertEqual(try repository.pendingPreviewGenerationItems(), [
            PreviewGenerationItem(assetID: asset.id, level: .micro),
            PreviewGenerationItem(assetID: asset.id, level: .grid)
        ])
    }

    func testImportFolderCommandWithItemIDReportsProgressThroughWorkerProcess() throws {
        let root = try makeTemporaryDirectory(named: "worker-entrypoint-import-progress")
        let photoRoot = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoRoot, withIntermediateDirectories: true)
        let source = photoRoot.appendingPathComponent("source.jpg")
        try Data("jpg".utf8).write(to: source)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let previewCacheRoot = root.appendingPathComponent("previews", isDirectory: true)
        let workerURL = try builtWorkerExecutableURL()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = workerURL
        process.arguments = [
            "--catalog",
            catalogURL.path,
            "--preview-cache",
            previewCacheRoot.path
        ]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let itemID = WorkSessionID(rawValue: "import-work")

        try process.run()
        inputPipe.fileHandleForWriting.write(Data(try WorkerProtocolEncoder.encode(.importFolder(root: photoRoot), itemID: itemID).utf8))
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(stderr, "")
        let events = try stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try WorkerProtocolEncoder.decodeEvent(String($0)) }
        XCTAssertTrue(events.contains { event in
            if case .progress(let progressItemID, _, _, _, let catalogedAssetIDs) = event {
                return progressItemID == itemID && catalogedAssetIDs.count == 1
            }
            return false
        })
        let completion = try XCTUnwrap(events.last)
        if case .completedImport(let completionItemID, let message, let importedAssetIDs, let newAssetCount, let existingAssetCount) = completion {
            XCTAssertEqual(completionItemID, itemID)
            XCTAssertEqual(message, "imported 1 photo from photos")
            XCTAssertEqual(importedAssetIDs.count, 1)
            XCTAssertEqual(newAssetCount, 1)
            XCTAssertEqual(existingAssetCount, 0)
        } else {
            XCTFail("expected import completion event")
        }
    }

    func testRefreshAvailabilityCommandUpdatesCatalogThroughWorkerProcess() throws {
        let root = try makeTemporaryDirectory(named: "worker-entrypoint-source-scan")
        let source = root.appendingPathComponent("source.jpg")
        try Data("original".utf8).write(to: source)
        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let previewCacheRoot = root.appendingPathComponent("previews", isDirectory: true)
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: source,
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try FileManager.default.removeItem(at: source)
        let workerURL = try builtWorkerExecutableURL()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let itemID = WorkSessionID(rawValue: "source-scan")
        process.executableURL = workerURL
        process.arguments = [
            "--catalog",
            catalogURL.path,
            "--preview-cache",
            previewCacheRoot.path
        ]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data(try WorkerProtocolEncoder.encode(.refreshAvailability(assetID: asset.id), itemID: itemID).utf8))
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(stderr, "")
        XCTAssertEqual(try WorkerProtocolEncoder.decodeEvent(stdout), .completed(
            itemID: itemID,
            message: "source missing for source.jpg"
        ))
        XCTAssertEqual(try repository.asset(id: asset.id).availability, .missing)
    }

    func testMalformedCommandWritesUnstructuredErrorToStderr() throws {
        let workerURL = try builtWorkerExecutableURL()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = workerURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data("not-json\n".utf8))
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(stdout, "")
        XCTAssertTrue(stderr.hasPrefix("error "))
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-worker-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func builtWorkerExecutableURL() throws -> URL {
        let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            packageRoot.appendingPathComponent(".build/debug/TeststripWorker"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/TeststripWorker")
        ]

        guard let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw XCTSkip("TeststripWorker executable is not built")
        }
        return url
    }
}
