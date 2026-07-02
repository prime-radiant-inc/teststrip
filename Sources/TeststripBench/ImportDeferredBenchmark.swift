import Foundation
import TeststripCore

public struct ImportDeferredBenchmarkResult: Equatable {
    public var importedAssetCount: Int
    public var catalogAssetCount: Int
    public var pendingPreviewCount: Int
    public var progressEventCount: Int

    public init(
        importedAssetCount: Int,
        catalogAssetCount: Int,
        pendingPreviewCount: Int,
        progressEventCount: Int
    ) {
        self.importedAssetCount = importedAssetCount
        self.catalogAssetCount = catalogAssetCount
        self.pendingPreviewCount = pendingPreviewCount
        self.progressEventCount = progressEventCount
    }
}

public struct ImportDeferredBenchmark {
    public var count: Int
    public var root: URL

    public init(count: Int, root: URL) {
        self.count = count
        self.root = root
    }

    public func run() throws -> ImportDeferredBenchmarkResult {
        let photoRoot = root.appendingPathComponent("photos", isDirectory: true)
        let previewRoot = root.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: photoRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previewRoot, withIntermediateDirectories: true)
        try writeSourceFiles(to: photoRoot)

        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: previewRoot)
        let service = LibraryImportService(
            ingestService: IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"])),
            previewCache: previewCache
        )
        let progressRecorder = BenchmarkProgressRecorder()

        let result = try service.addFolderInPlace(
            photoRoot,
            repository: repository,
            previewPolicy: .deferGeneration
        ) { _ in
            progressRecorder.recordEvent()
        }

        return ImportDeferredBenchmarkResult(
            importedAssetCount: result.importedAssets.count,
            catalogAssetCount: try repository.assetCount(),
            pendingPreviewCount: try repository.pendingPreviewGenerationItems().count,
            progressEventCount: progressRecorder.eventCount()
        )
    }

    private func writeSourceFiles(to photoRoot: URL) throws {
        for index in 0..<count {
            let url = photoRoot.appendingPathComponent("image-\(index).jpg")
            try Data("jpg-\(index)".utf8).write(to: url)
        }
    }
}

private final class BenchmarkProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func recordEvent() {
        lock.withLock {
            count += 1
        }
    }

    func eventCount() -> Int {
        lock.withLock {
            count
        }
    }
}
