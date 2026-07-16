import Foundation
import TeststripCore

public struct ImportPreviewDrainBenchmarkResult: Equatable {
    public var importedAssetCount: Int
    public var catalogAssetCount: Int
    public var pendingPreviewCountBeforeDrain: Int
    public var generatedPreviewCount: Int
    public var previewFailureCount: Int
    public var pendingPreviewCountAfterDrain: Int
    public var cachedPreviewCount: Int

    public init(
        importedAssetCount: Int,
        catalogAssetCount: Int,
        pendingPreviewCountBeforeDrain: Int,
        generatedPreviewCount: Int,
        previewFailureCount: Int,
        pendingPreviewCountAfterDrain: Int,
        cachedPreviewCount: Int
    ) {
        self.importedAssetCount = importedAssetCount
        self.catalogAssetCount = catalogAssetCount
        self.pendingPreviewCountBeforeDrain = pendingPreviewCountBeforeDrain
        self.generatedPreviewCount = generatedPreviewCount
        self.previewFailureCount = previewFailureCount
        self.pendingPreviewCountAfterDrain = pendingPreviewCountAfterDrain
        self.cachedPreviewCount = cachedPreviewCount
    }
}

public struct ImportPreviewDrainBenchmark {
    public var count: Int
    public var root: URL

    public init(count: Int, root: URL) {
        self.count = count
        self.root = root
    }

    public func run(recordingInto recorder: inout BenchmarkSummaryRecorder) throws -> ImportPreviewDrainBenchmarkResult {
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

        let importResult = try recorder.measure("import_deferred") {
            try service.addFolderInPlace(
                photoRoot,
                repository: repository,
                previewPolicy: .deferGeneration
            )
        }
        let pendingPreviewCountBeforeDrain = try repository.pendingPreviewGenerationItems().count
        let drainResult = try recorder.measure("preview_drain") {
            try service.resumePendingPreviews(repository: repository)
        }

        return ImportPreviewDrainBenchmarkResult(
            importedAssetCount: importResult.importedAssets.count,
            catalogAssetCount: try repository.assetCount(includeBondedSecondaries: true),
            pendingPreviewCountBeforeDrain: pendingPreviewCountBeforeDrain,
            generatedPreviewCount: drainResult.generatedCount,
            previewFailureCount: drainResult.previewFailures.count,
            pendingPreviewCountAfterDrain: try repository.pendingPreviewGenerationItems().count,
            cachedPreviewCount: try PreviewCacheFileCounter.count(root: previewCache.root)
        )
    }

    public func run() throws -> ImportPreviewDrainBenchmarkResult {
        var recorder = BenchmarkSummaryRecorder(benchmark: "import_preview_drain", count: count)
        return try run(recordingInto: &recorder)
    }

    private func writeSourceFiles(to photoRoot: URL) throws {
        for index in 0..<count {
            try BenchmarkImageFixtures.writeJPEG(
                to: photoRoot.appendingPathComponent("image-\(index).jpg"),
                index: index
            )
        }
    }
}
