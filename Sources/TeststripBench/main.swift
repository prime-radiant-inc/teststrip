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
case .cardImportSmoke(let count):
    try runCardImportSmoke(count: count, root: root)
case .importDeferred(let count):
    try runDeferredImportBenchmark(count: count, root: root)
case .importPreviewDrain(let count):
    try runImportPreviewDrainBenchmark(count: count, root: root)
case .localHTTPSmoke(let endpoint, let model, let imagePath, let timeout):
    try runLocalHTTPModelSmoke(endpoint: endpoint, model: model, imagePath: imagePath, timeout: timeout)
case .metadataWrite(let count):
    try runMetadataWriteBenchmark(count: count, root: root)
case .offlineReconnectSmoke:
    try runOfflineReconnectSmoke(root: root)
case .sourceAvailability(let count):
    try runSourceAvailabilityBenchmark(count: count, root: root)
case .previewRender(let count):
    try runPreviewRenderBenchmark(count: count, root: root)
case .workerRecoverySmoke(let count):
    try runWorkerRecoverySmoke(count: count, root: root)
case .realCorpusSmoke(let photoDirectory):
    try runRealCorpusSmoke(photoDirectory: photoDirectory, root: root)
case .samplePreviewRender(let photoDirectory):
    try runSamplePreviewRenderBenchmark(photoDirectory: photoDirectory, root: root)
case .seedAppCatalog(let applicationSupportDirectory, let count):
    try runSeedAppCatalog(applicationSupportDirectory: applicationSupportDirectory, count: count)
case .seedSampleCatalog(let applicationSupportDirectory, let photoDirectory):
    try runSeedSampleCatalog(applicationSupportDirectory: applicationSupportDirectory, photoDirectory: photoDirectory)
}

private func runCatalogScaleBenchmark(count: Int, root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "catalog_scale", count: count)

    print("TeststripBench catalog scale")
    print("count: \(count)")

    let result = try CatalogScaleBenchmark(count: count, root: root).run(recordingInto: &recorder)
    print("asset count: \(result.assetCount)")
    print("first page rows: \(result.firstPageRows)")
    print("middle page offset: \(result.middlePageOffset)")
    print("middle page rows: \(result.middlePageRows)")
    print("filtered rating 4+ count: \(result.filteredRating4PlusCount)")
    print("filtered page rows: \(result.filteredPageRows)")
    print("picked count: \(result.pickedCount)")
    print("green label count: \(result.greenLabelCount)")
    print("keyword batch-10 count: \(result.keywordBatch10Count)")
    print("offline count: \(result.offlineCount)")
    print("folder frame count: \(result.folderFrameCount)")
    print("SmokeCam 2 count: \(result.cameraSmokeCam2Count)")
    print("50mm lens count: \(result.lens50mmCount)")
    print("ISO 500+ count: \(result.isoAtLeast500Count)")
    print("recent capture count: \(result.recentCaptureCount)")
    try printMachineReadableSummary(recorder.summary)
}

private func runCardImportSmoke(count: Int, root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "card_import_smoke", count: count)

    print("TeststripBench card import smoke")
    print("count: \(count)")
    let result = try measure("card import smoke", recorder: &recorder, key: "card_import_smoke") {
        try CardImportSmoke(count: count, root: root).run()
    }
    recorder.recordMetric("imported_assets", result.importedAssetCount)
    recorder.recordMetric("catalog_assets", result.catalogAssetCount)
    recorder.recordMetric("destination_originals", result.destinationOriginalCount)
    recorder.recordMetric("cached_previews", result.cachedPreviewCount)
    recorder.recordMetric("source_originals_unchanged", result.sourceOriginalUnchangedCount)
    recorder.recordMetric("source_roots", result.sourceRootCount)
    recorder.recordMetric("destination_catalog_assets", result.destinationCatalogAssetCount)
    print("imported assets: \(result.importedAssetCount)")
    print("catalog assets: \(result.catalogAssetCount)")
    print("destination originals: \(result.destinationOriginalCount)")
    print("cached previews: \(result.cachedPreviewCount)")
    print("source originals unchanged: \(result.sourceOriginalUnchangedCount)")
    print("source roots: \(result.sourceRootCount)")
    print("destination catalog assets: \(result.destinationCatalogAssetCount)")
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

private func runImportPreviewDrainBenchmark(count: Int, root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "import_preview_drain", count: count)

    print("TeststripBench import preview drain")
    print("count: \(count)")
    let result = try ImportPreviewDrainBenchmark(count: count, root: root).run(recordingInto: &recorder)
    recorder.recordMetric("imported_assets", result.importedAssetCount)
    recorder.recordMetric("catalog_assets", result.catalogAssetCount)
    recorder.recordMetric("pending_previews_before_drain", result.pendingPreviewCountBeforeDrain)
    recorder.recordMetric("generated_previews", result.generatedPreviewCount)
    recorder.recordMetric("preview_failures", result.previewFailureCount)
    recorder.recordMetric("pending_previews_after_drain", result.pendingPreviewCountAfterDrain)
    recorder.recordMetric("cached_previews", result.cachedPreviewCount)
    print("imported assets: \(result.importedAssetCount)")
    print("catalog assets: \(result.catalogAssetCount)")
    print("pending previews before drain: \(result.pendingPreviewCountBeforeDrain)")
    print("generated previews: \(result.generatedPreviewCount)")
    print("preview failures: \(result.previewFailureCount)")
    print("pending previews after drain: \(result.pendingPreviewCountAfterDrain)")
    print("cached previews: \(result.cachedPreviewCount)")
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
    recorder.recordMetric("vector_signals", result.vectorSignalCount)
    recorder.recordMetric("visual_similarity_vector", result.hasVisualSimilarityVector ? 1 : 0)
    print("signals: \(result.signalCount)")
    print("vector signals: \(result.vectorSignalCount)")
    print("visual similarity vector: \(result.hasVisualSimilarityVector ? "yes" : "no")")
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
    recorder.recordMetric("matching_sidecar_metadata", result.matchingSidecarMetadataCount)
    recorder.recordMetric("synced_fingerprints", result.syncedFingerprintCount)
    recorder.recordMetric("pending_sync_items", result.pendingSyncCount)
    recorder.recordMetric("unchanged_originals", result.unchangedOriginalCount)
    print("updated assets: \(result.updatedAssetCount)")
    print("catalog assets: \(result.catalogAssetCount)")
    print("sidecars: \(result.sidecarCount)")
    print("matching sidecar metadata: \(result.matchingSidecarMetadataCount)")
    print("synced fingerprints: \(result.syncedFingerprintCount)")
    print("pending sync items: \(result.pendingSyncCount)")
    print("unchanged originals: \(result.unchangedOriginalCount)")
    try printMachineReadableSummary(recorder.summary)
}

private func runOfflineReconnectSmoke(root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "offline_reconnect_smoke", count: 1)

    print("TeststripBench offline reconnect smoke")
    let result = try measure("offline reconnect smoke", recorder: &recorder, key: "offline_reconnect_smoke") {
        try OfflineReconnectSmoke(root: root).run()
    }
    recorder.recordMetric("catalog_assets", result.catalogAssetCount)
    recorder.recordMetric("cached_preview_readable_before_reconnect", result.cachedPreviewReadableBeforeReconnect ? 1 : 0)
    recorder.recordMetric("cached_preview_readable_after_reconnect", result.cachedPreviewReadableAfterReconnect ? 1 : 0)
    recorder.recordMetric("reconnected_assets", result.reconnectedAssetCount)
    recorder.recordMetric("online_assets_after_reconnect", result.onlineAssetCountAfterReconnect)
    recorder.recordMetric("sidecar_path_updated", result.sidecarPathUpdatedCount)
    recorder.recordMetric("unchanged_originals", result.unchangedOriginalCount)
    recorder.recordMetric("unchanged_sidecars", result.unchangedSidecarCount)
    print("catalog assets: \(result.catalogAssetCount)")
    print("cached preview readable before reconnect: \(result.cachedPreviewReadableBeforeReconnect ? "yes" : "no")")
    print("cached preview readable after reconnect: \(result.cachedPreviewReadableAfterReconnect ? "yes" : "no")")
    print("reconnected assets: \(result.reconnectedAssetCount)")
    print("online assets after reconnect: \(result.onlineAssetCountAfterReconnect)")
    print("sidecar path updated: \(result.sidecarPathUpdatedCount)")
    print("unchanged originals: \(result.unchangedOriginalCount)")
    print("unchanged sidecars: \(result.unchangedSidecarCount)")
    try printMachineReadableSummary(recorder.summary)
}

private func runSourceAvailabilityBenchmark(count: Int, root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "source_availability", count: count)

    print("TeststripBench source availability")
    print("count: \(count)")
    let result = try SourceAvailabilityBenchmark(count: count, root: root).run(recordingInto: &recorder)
    print("catalog assets: \(result.catalogAssetCount)")
    print("refreshed assets: \(result.refreshedAssetCount)")
    print("online assets: \(result.onlineCount)")
    print("missing assets: \(result.missingCount)")
    print("stale assets: \(result.staleCount)")
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

private func runWorkerRecoverySmoke(count: Int, root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "worker_recovery_smoke", count: count)

    print("TeststripBench worker recovery smoke")
    print("count: \(count)")
    let result = try measure("worker recovery smoke", recorder: &recorder, key: "worker_recovery_smoke") {
        try WorkerRecoverySmoke(count: count, root: root).run()
    }
    recorder.recordMetric("catalog_assets", result.assetCount)
    recorder.recordMetric("recovered_preview_work", result.recoveredPreviewWorkCount)
    recorder.recordMetric("running_work", result.runningWorkCount)
    recorder.recordMetric("queued_work", result.queuedWorkCount)
    recorder.recordMetric("dispatched_commands", result.dispatchedCommandCount)
    recorder.recordMetric("pending_previews", result.pendingPreviewCount)
    recorder.recordMetric("worker_process_started", result.workerProcessStarted ? 1 : 0)
    print("catalog assets: \(result.assetCount)")
    print("recovered preview work: \(result.recoveredPreviewWorkCount)")
    print("running work: \(result.runningWorkCount)")
    print("queued work: \(result.queuedWorkCount)")
    print("dispatched commands: \(result.dispatchedCommandCount)")
    print("pending previews: \(result.pendingPreviewCount)")
    print("worker process started: \(result.workerProcessStarted ? "yes" : "no")")
    try printMachineReadableSummary(recorder.summary)
}

private func runRealCorpusSmoke(photoDirectory: URL, root: URL) throws {
    var recorder = BenchmarkSummaryRecorder(benchmark: "real_corpus_smoke", count: 0)

    print("TeststripBench real corpus smoke")
    print("photo directory: \(photoDirectory.path)")
    let result = try measure("real corpus smoke", recorder: &recorder, key: "real_corpus_smoke") {
        try RealCorpusSmoke(root: root, photoDirectory: photoDirectory).run()
    }
    recorder.recordMetric("candidate_photos", result.candidatePhotoCount)
    recorder.recordMetric("selected_photos", result.selectedPhotoCount)
    recorder.recordMetric("imported_assets", result.importedAssetCount)
    recorder.recordMetric("catalog_assets", result.catalogAssetCount)
    recorder.recordMetric("working_stills", result.workingStillCount)
    recorder.recordMetric("best_effort_raws", result.bestEffortRawCount)
    recorder.recordMetric("unsupported_files", result.unsupportedCount)
    recorder.recordMetric("preview_eligible_assets", result.previewEligibleCount)
    recorder.recordMetric("pending_previews", result.pendingPreviewCount)
    recorder.recordMetric("full_image_decode_assets", result.fullImageDecodeCount)
    recorder.recordMetric("adjacent_sidecars", result.adjacentSidecarCount)
    recorder.recordMetric("imported_sidecar_sync_items", result.importedSidecarSyncCount)
    recorder.recordMetric("adjacent_sidecars_not_imported", result.adjacentSidecarNotImportedCount)
    recorder.recordMetric("unchanged_originals", result.unchangedOriginalCount)
    recorder.recordMetric("unchanged_sidecars", result.unchangedSidecarCount)
    for (fileExtension, count) in result.selectedExtensions.sorted(by: { $0.key < $1.key }) {
        recorder.recordMetric("selected_\(fileExtension)_files", count)
    }
    print("candidate photos: \(result.candidatePhotoCount)")
    print("selected photos: \(result.selectedPhotoCount)")
    print("imported assets: \(result.importedAssetCount)")
    print("catalog assets: \(result.catalogAssetCount)")
    print("working stills: \(result.workingStillCount)")
    print("best-effort RAWs: \(result.bestEffortRawCount)")
    print("unsupported files: \(result.unsupportedCount)")
    print("preview-eligible assets: \(result.previewEligibleCount)")
    print("pending previews: \(result.pendingPreviewCount)")
    print("full-image decode assets: \(result.fullImageDecodeCount)")
    print("adjacent sidecars: \(result.adjacentSidecarCount)")
    print("imported sidecar sync items: \(result.importedSidecarSyncCount)")
    print("adjacent sidecars not imported: \(result.adjacentSidecarNotImportedCount)")
    print("unchanged originals: \(result.unchangedOriginalCount)")
    print("unchanged sidecars: \(result.unchangedSidecarCount)")
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
