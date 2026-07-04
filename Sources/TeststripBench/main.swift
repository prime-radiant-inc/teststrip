import Foundation
import TeststripCore

let command = BenchmarkCommand.parse(CommandLine.arguments)
let fileManager = FileManager.default
let root = BenchmarkWorkspace.temporaryRoot()
try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
defer {
    try? fileManager.removeItem(at: root)
}

switch command {
case .catalogScale(let count):
    try runCatalogScaleBenchmark(count: count, root: root)
case .importDeferred(let count):
    try runDeferredImportBenchmark(count: count, root: root)
case .localHTTPSmoke(let endpoint, let model, let imagePath, let timeout):
    try runLocalHTTPModelSmoke(endpoint: endpoint, model: model, imagePath: imagePath, timeout: timeout)
case .metadataWrite(let count):
    try runMetadataWriteBenchmark(count: count, root: root)
case .previewRender(let count):
    try runPreviewRenderBenchmark(count: count, root: root)
case .samplePreviewRender(let photoDirectory):
    try runSamplePreviewRenderBenchmark(photoDirectory: photoDirectory, root: root)
case .seedAppCatalog(let applicationSupportDirectory, let count):
    try runSeedAppCatalog(applicationSupportDirectory: applicationSupportDirectory, count: count)
case .seedSampleCatalog(let applicationSupportDirectory, let photoDirectory):
    try runSeedSampleCatalog(applicationSupportDirectory: applicationSupportDirectory, photoDirectory: photoDirectory)
}

private func runCatalogScaleBenchmark(count: Int, root: URL) throws {
    let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
    try database.migrate()
    let repository = CatalogRepository(database: database)
    var recorder = BenchmarkSummaryRecorder(benchmark: "catalog_scale", count: count)

    print("TeststripBench catalog scale")
    print("count: \(count)")

    try measure("seed assets", recorder: &recorder, key: "seed_assets") {
        let batchSize = 1_000
        for batchStart in stride(from: 0, to: count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, count)
            let assets = (batchStart..<batchEnd).map { index in
                Asset(
                    id: AssetID(rawValue: "bench-\(index)"),
                    originalURL: URL(fileURLWithPath: "/Volumes/NAS/Photos/frame-\(index).dng"),
                    volumeIdentifier: "NAS",
                    fingerprint: FileFingerprint(
                        size: Int64(index + 1),
                        modificationDate: Date(timeIntervalSince1970: TimeInterval(index))
                    ),
                    availability: index.isMultiple(of: 2) ? .online : .offline,
                    metadata: AssetMetadata(rating: index % 6)
                )
            }
            try repository.upsert(assets)
        }
    }

    let assetCount = try measure("count assets", recorder: &recorder, key: "count_assets") {
        try repository.assetCount()
    }
    recorder.recordMetric("asset_count", assetCount)
    print("asset count: \(assetCount)")

    let firstPage = try measure("load first page", recorder: &recorder, key: "load_first_page") {
        try repository.allAssets(limit: 500)
    }
    recorder.recordMetric("first_page_rows", firstPage.count)
    print("first page rows: \(firstPage.count)")

    let middleOffset = max(count / 2, 0)
    let middlePage = try measure("load middle page", recorder: &recorder, key: "load_middle_page") {
        try repository.allAssets(limit: 500, offset: middleOffset)
    }
    recorder.recordMetric("middle_page_offset", middleOffset)
    recorder.recordMetric("middle_page_rows", middlePage.count)
    print("middle page offset: \(middleOffset)")
    print("middle page rows: \(middlePage.count)")

    let filterQuery = SetQuery(predicates: [.ratingAtLeast(4)])
    let filteredCount = try measure("count filtered 4+ star assets", recorder: &recorder, key: "count_filtered_rating_4_plus") {
        try repository.assetCount(matching: filterQuery)
    }
    recorder.recordMetric("filtered_rating_4_plus_count", filteredCount)
    print("filtered count: \(filteredCount)")

    let filteredPage = try measure("load filtered page", recorder: &recorder, key: "load_filtered_page") {
        try repository.allAssets(matching: filterQuery, limit: 500)
    }
    recorder.recordMetric("filtered_page_rows", filteredPage.count)
    print("filtered page rows: \(filteredPage.count)")
    try printMachineReadableSummary(recorder.summary)
}

private func runDeferredImportBenchmark(count: Int, root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "deferred_import", count: count)

    print("TeststripBench deferred import")
    print("count: \(count)")
    let result = try measure("import deferred", recorder: &recorder, key: "import_deferred") {
        try ImportDeferredBenchmark(count: count, root: root).run()
    }
    recorder.recordMetric("imported_assets", result.importedAssetCount)
    recorder.recordMetric("catalog_assets", result.catalogAssetCount)
    recorder.recordMetric("pending_previews", result.pendingPreviewCount)
    recorder.recordMetric("progress_events", result.progressEventCount)
    print("imported assets: \(result.importedAssetCount)")
    print("catalog assets: \(result.catalogAssetCount)")
    print("pending previews: \(result.pendingPreviewCount)")
    print("progress events: \(result.progressEventCount)")
    try printMachineReadableSummary(recorder.summary)
}

private func runLocalHTTPModelSmoke(endpoint: URL, model: String, imagePath: String?, timeout: TimeInterval) throws {
    guard let imagePath, !imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw TeststripError.invalidState("local-http-smoke requires an image path")
    }
    let imageURL = URL(fileURLWithPath: imagePath)
    print("TeststripBench local HTTP model smoke")
    print("endpoint: \(endpoint.absoluteString)")
    print("model: \(model)")
    print("image: \(imageURL.path)")
    var recorder = BenchmarkSummaryRecorder(benchmark: "local_http_model_smoke", count: 1)
    let result = try measure("local HTTP model smoke", recorder: &recorder, key: "local_http_model_smoke") {
        try LocalHTTPModelSmoke(
            endpoint: endpoint,
            model: model,
            imageURL: imageURL,
            timeout: timeout
        ).run()
    }
    recorder.recordMetric("signals", result.signalCount)
    print("signals: \(result.signalCount)")
    print("signal kinds: \(result.signalKinds.map(\.rawValue).joined(separator: ", "))")
    try printMachineReadableSummary(recorder.summary)
}

private func runMetadataWriteBenchmark(count: Int, root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "metadata_write", count: count)

    print("TeststripBench metadata write")
    print("count: \(count)")
    let result = try measure("metadata write", recorder: &recorder, key: "metadata_write") {
        try MetadataWriteBenchmark(count: count, root: root).run()
    }
    recorder.recordMetric("updated_assets", result.updatedAssetCount)
    recorder.recordMetric("catalog_assets", result.catalogAssetCount)
    recorder.recordMetric("sidecars", result.sidecarCount)
    recorder.recordMetric("synced_fingerprints", result.syncedFingerprintCount)
    recorder.recordMetric("pending_sync_items", result.pendingSyncCount)
    recorder.recordMetric("unchanged_originals", result.unchangedOriginalCount)
    print("updated assets: \(result.updatedAssetCount)")
    print("catalog assets: \(result.catalogAssetCount)")
    print("sidecars: \(result.sidecarCount)")
    print("synced fingerprints: \(result.syncedFingerprintCount)")
    print("pending sync items: \(result.pendingSyncCount)")
    print("unchanged originals: \(result.unchangedOriginalCount)")
    try printMachineReadableSummary(recorder.summary)
}

private func runPreviewRenderBenchmark(count: Int, root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "preview_render", count: count)

    print("TeststripBench preview render")
    print("count: \(count)")
    let result = try measure("preview render", recorder: &recorder, key: "preview_render") {
        try PreviewRenderBenchmark(count: count, root: root).run()
    }
    recorder.recordMetric("source_images", result.sourceImageCount)
    recorder.recordMetric("rendered_previews", result.renderedPreviewCount)
    recorder.recordMetric("cached_previews", result.cachedPreviewCount)
    print("source images: \(result.sourceImageCount)")
    print("rendered previews: \(result.renderedPreviewCount)")
    print("cached previews: \(result.cachedPreviewCount)")
    try printMachineReadableSummary(recorder.summary)
}

private func runSamplePreviewRenderBenchmark(photoDirectory: URL, root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "sample_preview_render", count: 0)

    print("TeststripBench sample preview render")
    print("photo directory: \(photoDirectory.path)")
    let result = try measure("sample preview render", recorder: &recorder, key: "sample_preview_render") {
        try SamplePreviewRenderBenchmark(root: root, photoDirectory: photoDirectory).run()
    }
    recorder.recordMetric("source_images", result.sourceImageCount)
    recorder.recordMetric("catalog_assets", result.catalogAssetCount)
    recorder.recordMetric("cached_previews", result.cachedPreviewCount)
    print("source images: \(result.sourceImageCount)")
    print("catalog assets: \(result.catalogAssetCount)")
    print("cached previews: \(result.cachedPreviewCount)")
    try printMachineReadableSummary(recorder.summary)
}

private func runSeedAppCatalog(applicationSupportDirectory: URL, count: Int) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "seed_app_catalog", count: count)

    print("TeststripBench seed app catalog")
    print("application support: \(applicationSupportDirectory.path)")
    print("count: \(count)")
    let result = try measure("seed app catalog", recorder: &recorder, key: "seed_app_catalog") {
        try SmokeCatalogSeeder(
            applicationSupportDirectory: applicationSupportDirectory,
            count: count
        ).run()
    }
    recorder.recordMetric("source_images", result.sourceImageCount)
    recorder.recordMetric("catalog_assets", result.assetCount)
    recorder.recordMetric("cached_previews", result.cachedPreviewCount)
    print("catalog: \(result.catalogURL.path)")
    print("preview cache: \(result.previewCacheRoot.path)")
    print("source images: \(result.sourceImageCount)")
    print("catalog assets: \(result.assetCount)")
    print("cached previews: \(result.cachedPreviewCount)")
    try printMachineReadableSummary(recorder.summary)
}

private func runSeedSampleCatalog(applicationSupportDirectory: URL, photoDirectory: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "seed_sample_catalog", count: 0)

    print("TeststripBench seed sample catalog")
    print("application support: \(applicationSupportDirectory.path)")
    print("photo directory: \(photoDirectory.path)")
    let result = try measure("seed sample catalog", recorder: &recorder, key: "seed_sample_catalog") {
        try SampleCatalogSeeder(
            applicationSupportDirectory: applicationSupportDirectory,
            photoDirectory: photoDirectory
        ).run()
    }
    recorder.recordMetric("source_images", result.sourceImageCount)
    recorder.recordMetric("catalog_assets", result.assetCount)
    recorder.recordMetric("cached_previews", result.cachedPreviewCount)
    print("catalog: \(result.catalogURL.path)")
    print("preview cache: \(result.previewCacheRoot.path)")
    print("source images: \(result.sourceImageCount)")
    print("catalog assets: \(result.assetCount)")
    print("cached previews: \(result.cachedPreviewCount)")
    try printMachineReadableSummary(recorder.summary)
}

@discardableResult
private func measure<T>(
    _ label: String,
    recorder: inout BenchmarkSummaryRecorder,
    key: String,
    work: () throws -> T
) rethrows -> T {
    let start = Date()
    let value = try work()
    let elapsed = Date().timeIntervalSince(start)
    print("\(label): \(String(format: "%.3f", elapsed))s")
    recorder.recordMeasurement(key, elapsed)
    return value
}

private func printMachineReadableSummary(_ summary: BenchmarkSummary) throws {
    print(try summary.machineReadableLine())
}
