import Foundation
import TeststripCore

let arguments = CommandLine.arguments
let count = Int(arguments.dropFirst().first ?? "100000") ?? 100000
let fileManager = FileManager.default
let root = fileManager.temporaryDirectory.appendingPathComponent("teststrip-bench", isDirectory: true)
if fileManager.fileExists(atPath: root.path) {
    try fileManager.removeItem(at: root)
}
try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
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
                fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index))),
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

@discardableResult
func measure<T>(_ label: String, work: () throws -> T) rethrows -> T {
    let start = Date()
    let value = try work()
    let elapsed = Date().timeIntervalSince(start)
    print("\(label): \(String(format: "%.3f", elapsed))s")
    return value
}
