import Foundation
import TeststripCore

public struct SourceAvailabilityBenchmarkResult: Equatable {
    public var catalogAssetCount: Int
    public var refreshedAssetCount: Int
    public var onlineCount: Int
    public var missingCount: Int
    public var staleCount: Int
}

public struct SourceAvailabilityBenchmark {
    public var count: Int
    public var root: URL

    public init(count: Int, root: URL) {
        self.count = max(0, count)
        self.root = root
    }

    public func run() throws -> SourceAvailabilityBenchmarkResult {
        var recorder = BenchmarkSummaryRecorder(benchmark: "source_availability", count: count)
        return try run(recordingInto: &recorder)
    }

    public func run(recordingInto recorder: inout BenchmarkSummaryRecorder) throws -> SourceAvailabilityBenchmarkResult {
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        try recorder.measure("seed_assets") {
            try seedAssets(repository: repository)
        }

        let refreshedAssetCount = try recorder.measure("refresh_source_availability") {
            try refreshSourceAvailability(repository: repository)
        }
        recorder.recordMetric("refreshed_assets", refreshedAssetCount)

        let catalogAssetCount = try recorder.measure("count_assets") {
            try repository.assetCount(includeBondedSecondaries: true)
        }
        recorder.recordMetric("catalog_assets", catalogAssetCount)

        let onlineCount = try countAvailability(
            .online,
            metric: "online_assets",
            measurement: "count_online",
            repository: repository,
            recorder: &recorder
        )
        let missingCount = try countAvailability(
            .missing,
            metric: "missing_assets",
            measurement: "count_missing",
            repository: repository,
            recorder: &recorder
        )
        let staleCount = try countAvailability(
            .stale,
            metric: "stale_assets",
            measurement: "count_stale",
            repository: repository,
            recorder: &recorder
        )

        return SourceAvailabilityBenchmarkResult(
            catalogAssetCount: catalogAssetCount,
            refreshedAssetCount: refreshedAssetCount,
            onlineCount: onlineCount,
            missingCount: missingCount,
            staleCount: staleCount
        )
    }

    private func seedAssets(repository: CatalogRepository) throws {
        let sourceRoot = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        var assets: [Asset] = []
        assets.reserveCapacity(count)
        for index in 0..<count {
            let originalURL = sourceRoot.appendingPathComponent("frame-\(index).jpg")
            try Self.writeOriginal(index: index, to: originalURL, byteCount: 16)
            let fingerprint = try Self.fileFingerprint(for: originalURL)
            assets.append(Self.asset(index: index, originalURL: originalURL, fingerprint: fingerprint))

            switch index % 3 {
            case 1:
                try FileManager.default.removeItem(at: originalURL)
            case 2:
                try Self.writeOriginal(index: index + count + 1, to: originalURL, byteCount: 32)
            default:
                break
            }
        }
        try repository.upsert(assets)
    }

    private func refreshSourceAvailability(repository: CatalogRepository) throws -> Int {
        let assets = try repository.allAssets(limit: max(count, 1))
        let probe = SourceAvailabilityProbe()
        for asset in assets {
            try repository.updateAvailability(assetID: asset.id, availability: probe.availability(for: asset))
        }
        return assets.count
    }

    private func countAvailability(
        _ availability: SourceAvailability,
        metric: String,
        measurement: String,
        repository: CatalogRepository,
        recorder: inout BenchmarkSummaryRecorder
    ) throws -> Int {
        let value = try recorder.measure(measurement) {
            try repository.assetCount(matching: SetQuery(predicates: [.availability(availability)]))
        }
        recorder.recordMetric(metric, value)
        return value
    }

    private static func asset(index: Int, originalURL: URL, fingerprint: FileFingerprint) -> Asset {
        Asset(
            id: AssetID(rawValue: "source-availability-\(index)"),
            originalURL: originalURL,
            volumeIdentifier: "benchmark",
            fingerprint: fingerprint,
            availability: .online,
            metadata: AssetMetadata(
                rating: index % 6,
                keywords: ["source-availability", "batch-\(index / 10)"],
                caption: "Source availability benchmark frame \(index + 1)"
            )
        )
    }

    private static func writeOriginal(index: Int, to url: URL, byteCount: Int) throws {
        let byte = UInt8(index % 251)
        try Data(repeating: byte, count: byteCount).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index + 1_000))],
            ofItemAtPath: url.path
        )
    }

    private static func fileFingerprint(for url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return FileFingerprint(
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        )
    }
}
