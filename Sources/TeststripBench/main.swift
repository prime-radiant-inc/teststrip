import Foundation
import TeststripCore

let arguments = CommandLine.arguments
let count = Int(arguments.dropFirst().first ?? "10000") ?? 10000
let fileManager = FileManager.default
let root = fileManager.temporaryDirectory.appendingPathComponent("teststrip-bench", isDirectory: true)
if fileManager.fileExists(atPath: root.path) {
    try fileManager.removeItem(at: root)
}
try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
try database.migrate()
let repository = CatalogRepository(database: database)

var assets: [Asset] = []
assets.reserveCapacity(count)
let start = Date()
for index in 0..<count {
    let asset = Asset(
        id: AssetID(rawValue: "bench-\(index)"),
        originalURL: URL(fileURLWithPath: "/Volumes/NAS/Photos/frame-\(index).dng"),
        volumeIdentifier: "NAS",
        fingerprint: FileFingerprint(size: Int64(index + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(index))),
        availability: index.isMultiple(of: 2) ? .online : .offline,
        metadata: AssetMetadata(rating: index % 6)
    )
    assets.append(asset)
}
try repository.upsert(assets)

let elapsed = Date().timeIntervalSince(start)
print("inserted \(count) assets in \(String(format: "%.3f", elapsed))s")
