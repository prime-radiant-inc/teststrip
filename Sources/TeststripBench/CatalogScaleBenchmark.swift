import Foundation
import TeststripCore

public struct CatalogScaleBenchmarkResult: Equatable {
    public var assetCount: Int
    public var firstPageRows: Int
    public var middlePageOffset: Int
    public var middlePageRows: Int
    public var filteredRating4PlusCount: Int
    public var filteredPageRows: Int
    public var pickedCount: Int
    public var greenLabelCount: Int
    public var keywordBatch10Count: Int
    public var offlineCount: Int
    public var folderFrameCount: Int
    public var cameraSmokeCam2Count: Int
    public var lens50mmCount: Int
    public var isoAtLeast500Count: Int
    public var recentCaptureCount: Int
}

public struct CatalogScaleBenchmark {
    public var count: Int
    public var root: URL

    public init(count: Int, root: URL) {
        self.count = max(0, count)
        self.root = root
    }

    public func run() throws -> CatalogScaleBenchmarkResult {
        var recorder = BenchmarkSummaryRecorder(benchmark: "catalog_scale", count: count)
        return try run(recordingInto: &recorder)
    }

    public func run(recordingInto recorder: inout BenchmarkSummaryRecorder) throws -> CatalogScaleBenchmarkResult {
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        try recorder.measure("seed_assets") {
            try seedAssets(repository: repository)
        }

        let assetCount = try recorder.measure("count_assets") {
            try repository.assetCount()
        }
        recorder.recordMetric("asset_count", assetCount)

        let firstPage = try recorder.measure("load_first_page") {
            try repository.allAssets(limit: 500)
        }
        recorder.recordMetric("first_page_rows", firstPage.count)

        let middleOffset = max(count / 2, 0)
        let middlePage = try recorder.measure("load_middle_page") {
            try repository.allAssets(limit: 500, offset: middleOffset)
        }
        recorder.recordMetric("middle_page_offset", middleOffset)
        recorder.recordMetric("middle_page_rows", middlePage.count)

        let ratingQuery = SetQuery(predicates: [.ratingAtLeast(4)])
        let filteredRating4PlusCount = try recorder.measure("count_filtered_rating_4_plus") {
            try repository.assetCount(matching: ratingQuery)
        }
        recorder.recordMetric("filtered_rating_4_plus_count", filteredRating4PlusCount)

        let filteredPage = try recorder.measure("load_filtered_page") {
            try repository.allAssets(matching: ratingQuery, limit: 500)
        }
        recorder.recordMetric("filtered_page_rows", filteredPage.count)

        let pickedCount = try count(
            query: SetQuery(predicates: [.flag(.pick)]),
            metric: "picked_count",
            measurement: "count_picked",
            repository: repository,
            recorder: &recorder
        )
        let greenLabelCount = try count(
            query: SetQuery(predicates: [.colorLabel(.green)]),
            metric: "green_label_count",
            measurement: "count_green_label",
            repository: repository,
            recorder: &recorder
        )
        let keywordBatch10Count = try count(
            query: SetQuery(predicates: [.keyword("batch-10")]),
            metric: "keyword_batch_10_count",
            measurement: "count_keyword_batch_10",
            repository: repository,
            recorder: &recorder
        )
        let offlineCount = try count(
            query: SetQuery(predicates: [.availability(.offline)]),
            metric: "offline_count",
            measurement: "count_offline",
            repository: repository,
            recorder: &recorder
        )
        let folderFrameCount = try count(
            query: SetQuery(predicates: [.folderPrefix("/Volumes/NAS/Photos")]),
            metric: "folder_frame_count",
            measurement: "count_folder",
            repository: repository,
            recorder: &recorder
        )
        let cameraSmokeCam2Count = try count(
            query: SetQuery(predicates: [.camera("SmokeCam 2")]),
            metric: "camera_smokecam_2_count",
            measurement: "count_camera_smokecam_2",
            repository: repository,
            recorder: &recorder
        )
        let lens50mmCount = try count(
            query: SetQuery(predicates: [.lens("50mm")]),
            metric: "lens_50mm_count",
            measurement: "count_lens_50mm",
            repository: repository,
            recorder: &recorder
        )
        let isoAtLeast500Count = try count(
            query: SetQuery(predicates: [.isoAtLeast(500)]),
            metric: "iso_at_least_500_count",
            measurement: "count_iso_at_least_500",
            repository: repository,
            recorder: &recorder
        )
        let recentCaptureCount = try count(
            query: SetQuery(predicates: [.capturedAtOrAfter(captureDate(at: max(count / 2, 0)))]),
            metric: "recent_capture_count",
            measurement: "count_recent_capture",
            repository: repository,
            recorder: &recorder
        )

        return CatalogScaleBenchmarkResult(
            assetCount: assetCount,
            firstPageRows: firstPage.count,
            middlePageOffset: middleOffset,
            middlePageRows: middlePage.count,
            filteredRating4PlusCount: filteredRating4PlusCount,
            filteredPageRows: filteredPage.count,
            pickedCount: pickedCount,
            greenLabelCount: greenLabelCount,
            keywordBatch10Count: keywordBatch10Count,
            offlineCount: offlineCount,
            folderFrameCount: folderFrameCount,
            cameraSmokeCam2Count: cameraSmokeCam2Count,
            lens50mmCount: lens50mmCount,
            isoAtLeast500Count: isoAtLeast500Count,
            recentCaptureCount: recentCaptureCount
        )
    }

    private func seedAssets(repository: CatalogRepository) throws {
        let batchSize = 1_000
        for batchStart in stride(from: 0, to: count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, count)
            let assets = (batchStart..<batchEnd).map(Self.asset)
            try repository.upsert(assets)
        }
    }

    private func count(
        query: SetQuery,
        metric: String,
        measurement: String,
        repository: CatalogRepository,
        recorder: inout BenchmarkSummaryRecorder
    ) throws -> Int {
        let value = try recorder.measure(measurement) {
            try repository.assetCount(matching: query)
        }
        recorder.recordMetric(metric, value)
        return value
    }

    private static func asset(index: Int) -> Asset {
        let colorLabels = ColorLabel.allCases
        let flag: PickFlag? = index.isMultiple(of: 3) ? .pick : (index.isMultiple(of: 5) ? .reject : nil)
        return Asset(
            id: AssetID(rawValue: "bench-\(index)"),
            originalURL: URL(fileURLWithPath: "/Volumes/NAS/Photos/frame-\(index).dng"),
            volumeIdentifier: "NAS",
            fingerprint: FileFingerprint(
                size: Int64(index + 1),
                modificationDate: Date(timeIntervalSince1970: TimeInterval(index))
            ),
            availability: index.isMultiple(of: 2) ? .online : .offline,
            metadata: AssetMetadata(
                rating: index % 6,
                colorLabel: colorLabels[index % colorLabels.count],
                flag: flag,
                keywords: ["bench", "batch-\(index / 10)"],
                caption: "Benchmark frame \(index + 1)"
            ),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                cameraMake: "Teststrip",
                cameraModel: "SmokeCam \(index % 3 + 1)",
                lensModel: "\(35 + (index % 4) * 15)mm",
                isoSpeed: 100 + (index % 5) * 200,
                capturedAt: captureDate(at: index),
                provenance: ProviderProvenance(
                    provider: "TeststripBench",
                    model: "CatalogScaleBenchmark",
                    version: "1",
                    settingsHash: "default"
                )
            )
        )
    }

    private static func captureDate(at index: Int) -> Date {
        Date(timeIntervalSince1970: 1_704_067_200 + TimeInterval(index * 900))
    }

    private func captureDate(at index: Int) -> Date {
        Self.captureDate(at: index)
    }
}
