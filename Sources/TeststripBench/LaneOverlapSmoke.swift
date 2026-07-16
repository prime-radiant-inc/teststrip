import Foundation
import TeststripCore

/// Regression guard for concurrent per-lane worker execution: proves the
/// preview lane and the evaluation (`.recognition`) lane can both be
/// `.running` — and actually dispatched to the worker process — in the same
/// observed instant, against a REAL `WorkerSupervisor` driving the REAL
/// `TeststripWorker` binary over a REAL catalog. This guards against a
/// regression that re-serializes the lanes (either by capping
/// `maxDispatchedCommandCount` back down or dropping the per-kind running
/// limits), which would collapse both lanes back to one-command-at-a-time.
public struct LaneOverlapSmokeResult: Equatable {
    public var catalogAssetCount: Int
    public var previewedAssetCount: Int
    public var deferredAssetCount: Int
    public var previewWorkItemCount: Int
    public var evaluationWorkItemCount: Int
    public var overlapObserved: Bool
    public var overlapSampleCount: Int
    public var sampleCount: Int
    public var pendingPreviewCountAfterDrain: Int
    public var cachedPreviewCount: Int
    public var evaluationSignalAssetCount: Int
    public var evaluationSignalCount: Int
    public var workerProcessStarted: Bool

    public init(
        catalogAssetCount: Int,
        previewedAssetCount: Int,
        deferredAssetCount: Int,
        previewWorkItemCount: Int,
        evaluationWorkItemCount: Int,
        overlapObserved: Bool,
        overlapSampleCount: Int,
        sampleCount: Int,
        pendingPreviewCountAfterDrain: Int,
        cachedPreviewCount: Int,
        evaluationSignalAssetCount: Int,
        evaluationSignalCount: Int,
        workerProcessStarted: Bool
    ) {
        self.catalogAssetCount = catalogAssetCount
        self.previewedAssetCount = previewedAssetCount
        self.deferredAssetCount = deferredAssetCount
        self.previewWorkItemCount = previewWorkItemCount
        self.evaluationWorkItemCount = evaluationWorkItemCount
        self.overlapObserved = overlapObserved
        self.overlapSampleCount = overlapSampleCount
        self.sampleCount = sampleCount
        self.pendingPreviewCountAfterDrain = pendingPreviewCountAfterDrain
        self.cachedPreviewCount = cachedPreviewCount
        self.evaluationSignalAssetCount = evaluationSignalAssetCount
        self.evaluationSignalCount = evaluationSignalCount
        self.workerProcessStarted = workerProcessStarted
    }
}

public struct LaneOverlapSmoke {
    /// The always-registered, network-free evaluation provider (see
    /// `WorkerCommandExecutor`'s default provider list) — avoids any
    /// dependency on Apple Vision / local HTTP model availability.
    public static let evaluationProviderName = "local-image-metrics"

    /// How long to wait for the whole queue (preview + evaluation lanes) to
    /// drain. Generous relative to the trivial synthetic-image work involved,
    /// bounded so a real regression (a wedged worker) fails fast instead of
    /// hanging CI.
    public static let drainTimeout: TimeInterval = 60

    public var count: Int
    public var root: URL

    public init(count: Int, root: URL) {
        self.count = max(2, count)
        self.root = root
    }

    public func run() throws -> LaneOverlapSmokeResult {
        let deferredCount = count / 2
        let previewedCount = count - deferredCount

        let primedPhotoRoot = root.appendingPathComponent("photos/primed", isDirectory: true)
        let deferredPhotoRoot = root.appendingPathComponent("photos/deferred", isDirectory: true)
        let previewRoot = root.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: primedPhotoRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deferredPhotoRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previewRoot, withIntermediateDirectories: true)

        for index in 0..<previewedCount {
            try BenchmarkImageFixtures.writeJPEG(
                to: primedPhotoRoot.appendingPathComponent("primed-\(index).jpg"),
                index: index
            )
        }
        for index in 0..<deferredCount {
            try BenchmarkImageFixtures.writeJPEG(
                to: deferredPhotoRoot.appendingPathComponent("deferred-\(index).jpg"),
                index: previewedCount + index
            )
        }

        let catalogURL = root.appendingPathComponent("catalog.sqlite")
        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: previewRoot)
        let importService = LibraryImportService(
            ingestService: IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"])),
            previewCache: previewCache
        )

        // Half the assets get their previews rendered immediately (in-process,
        // no worker involved) so they already satisfy the evaluation lane's
        // cached-preview requirement. The other half defer preview generation,
        // leaving real pending work for the preview lane.
        let previewedImport = try importService.addFolderInPlace(
            primedPhotoRoot,
            repository: repository,
            previewPolicy: .generateImmediately
        )
        _ = try importService.addFolderInPlace(
            deferredPhotoRoot,
            repository: repository,
            previewPolicy: .deferGeneration
        )

        let evaluationAssetIDs = previewedImport.importedAssets.map(\.id)
        let pendingPreviewItems = try repository.pendingPreviewGenerationItems()
        guard !evaluationAssetIDs.isEmpty, !pendingPreviewItems.isEmpty else {
            throw TeststripError.invalidState(
                "lane-overlap needs both cached-preview assets and pending-preview assets to seed both lanes"
            )
        }

        let workerExecutableURL = try Self.workerExecutableURL()
        let transport = FoundationWorkerTransport(
            executableURL: workerExecutableURL,
            arguments: ["--catalog", catalogURL.path, "--preview-cache", previewCache.root.path]
        )
        defer { transport.terminate() }

        // Matches production's AppCatalog.loadModel: a shared cap of 8 across
        // all kinds, with preview generation and recognition each capped at 1
        // concurrent item — so one preview command and one evaluation command
        // dispatch together whenever both lanes have runnable work.
        let supervisor = WorkerSupervisor(
            queue: BackgroundWorkQueue(maxRunningCount: 8, kindRunningLimits: [.previewGeneration: 1, .recognition: 1]),
            transport: transport,
            maxDispatchedCommandCount: 8
        )

        var requests: [(item: BackgroundWorkItem, command: WorkerCommand, placement: BackgroundWorkQueuePlacement)] = []
        for pendingItem in pendingPreviewItems {
            requests.append((
                item: BackgroundWorkItem(
                    id: WorkSessionID(rawValue: "preview-\(pendingItem.assetID.rawValue)-\(pendingItem.level.rawValue)"),
                    kind: .previewGeneration,
                    title: "Generate \(pendingItem.level.rawValue) preview",
                    detail: pendingItem.assetID.rawValue,
                    completedUnitCount: 0,
                    totalUnitCount: 1
                ),
                command: .generatePreview(assetID: pendingItem.assetID, level: pendingItem.level),
                placement: .back
            ))
        }
        for assetID in evaluationAssetIDs {
            requests.append((
                item: BackgroundWorkItem(
                    id: WorkSessionID(rawValue: "evaluation-\(assetID.rawValue)-\(Self.evaluationProviderName)"),
                    kind: .recognition,
                    title: "Evaluate photo",
                    detail: "Running \(Self.evaluationProviderName)",
                    completedUnitCount: 0,
                    totalUnitCount: 1
                ),
                command: .runEvaluation(assetID: assetID, provider: Self.evaluationProviderName),
                placement: .back
            ))
        }

        try supervisor.enqueue(requests)

        var overlapObserved = false
        var overlapSampleCount = 0
        var sampleCount = 0
        let deadline = Date().addingTimeInterval(Self.drainTimeout)
        while Date() < deadline {
            sampleCount += 1
            let runningItems = supervisor.queue.runningItems
            let previewRunning = runningItems.filter { $0.kind == .previewGeneration }
            let recognitionRunning = runningItems.filter { $0.kind == .recognition }
            if !previewRunning.isEmpty, !recognitionRunning.isEmpty {
                // Require both to actually be dispatched (sent to the worker
                // process), not merely scheduled client-side, so this catches
                // a supervisor-level dispatch-throttle regression too.
                let bothDispatched = previewRunning.contains { supervisor.isCommandDispatched(for: $0.id) }
                    && recognitionRunning.contains { supervisor.isCommandDispatched(for: $0.id) }
                if bothDispatched {
                    overlapObserved = true
                    overlapSampleCount += 1
                }
            }

            let stillActive = supervisor.queue.items.contains { Self.isActiveStatus($0.status) }
            if !stillActive {
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        let remainingActiveItems = supervisor.queue.items.filter { Self.isActiveStatus($0.status) }
        guard remainingActiveItems.isEmpty else {
            throw TeststripError.invalidState(
                "lane-overlap did not drain within \(Int(Self.drainTimeout))s: "
                    + "\(remainingActiveItems.count) items still active "
                    + "(\(remainingActiveItems.map { "\($0.kind.rawValue):\($0.status.rawValue)" }.joined(separator: ", ")))"
            )
        }

        let workerProcessStarted = transport.isRunning
        var evaluationSignalCount = 0
        var evaluationSignalAssetCount = 0
        for assetID in evaluationAssetIDs {
            let signals = try repository.evaluationSignals(assetID: assetID)
            evaluationSignalCount += signals.count
            if !signals.isEmpty {
                evaluationSignalAssetCount += 1
            }
        }

        return LaneOverlapSmokeResult(
            catalogAssetCount: try repository.assetCount(includeBondedSecondaries: true),
            previewedAssetCount: previewedCount,
            deferredAssetCount: deferredCount,
            previewWorkItemCount: pendingPreviewItems.count,
            evaluationWorkItemCount: evaluationAssetIDs.count,
            overlapObserved: overlapObserved,
            overlapSampleCount: overlapSampleCount,
            sampleCount: sampleCount,
            pendingPreviewCountAfterDrain: try repository.pendingPreviewGenerationItems().count,
            cachedPreviewCount: try PreviewCacheFileCounter.count(root: previewCache.root),
            evaluationSignalAssetCount: evaluationSignalAssetCount,
            evaluationSignalCount: evaluationSignalCount,
            workerProcessStarted: workerProcessStarted
        )
    }

    private static func isActiveStatus(_ status: WorkSessionStatus) -> Bool {
        [.queued, .running, .paused].contains(status)
    }

    /// The `TeststripWorker` product built alongside `TeststripBench` lands in
    /// the same SwiftPM build directory (see `script/lib/app_bundle.sh`'s
    /// `teststrip_build_bin_path`), so it can be located as a sibling of this
    /// process's own executable.
    private static func workerExecutableURL() throws -> URL {
        let benchExecutableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let candidate = benchExecutableURL
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
            .appendingPathComponent("TeststripWorker")
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else {
            throw TeststripError.invalidState(
                "TeststripWorker binary not found at \(candidate.path); run `swift build --product TeststripWorker` first"
            )
        }
        return candidate
    }
}
