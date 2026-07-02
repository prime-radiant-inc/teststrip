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
}

private func runCatalogScaleBenchmark(count: Int, root: URL) throws {
    let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
    try database.migrate()
    let repository = CatalogRepository(database: database)

    print("TeststripBench catalog scale")
    print("count: \(count)")

    try measure("seed assets") {
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

    let assetCount = try measure("count assets") {
        try repository.assetCount()
    }
    print("asset count: \(assetCount)")

    let firstPage = try measure("load first page") {
        try repository.allAssets(limit: 500)
    }
    print("first page rows: \(firstPage.count)")

    let middleOffset = max(count / 2, 0)
    let middlePage = try measure("load middle page") {
        try repository.allAssets(limit: 500, offset: middleOffset)
    }
    print("middle page offset: \(middleOffset)")
    print("middle page rows: \(middlePage.count)")

    let filterQuery = SetQuery(predicates: [.ratingAtLeast(4)])
    let filteredCount = try measure("count filtered 4+ star assets") {
        try repository.assetCount(matching: filterQuery)
    }
    print("filtered count: \(filteredCount)")

    let filteredPage = try measure("load filtered page") {
        try repository.allAssets(matching: filterQuery, limit: 500)
    }
    print("filtered page rows: \(filteredPage.count)")
}

private func runDeferredImportBenchmark(count: Int, root: URL) throws {
    print("TeststripBench deferred import")
    print("count: \(count)")
    let result = try measure("import deferred") {
        try ImportDeferredBenchmark(count: count, root: root).run()
    }
    print("imported assets: \(result.importedAssetCount)")
    print("catalog assets: \(result.catalogAssetCount)")
    print("pending previews: \(result.pendingPreviewCount)")
    print("progress events: \(result.progressEventCount)")
}

@discardableResult
private func measure<T>(_ label: String, work: () throws -> T) rethrows -> T {
    let start = Date()
    let value = try work()
    let elapsed = Date().timeIntervalSince(start)
    print("\(label): \(String(format: "%.3f", elapsed))s")
    return value
}
