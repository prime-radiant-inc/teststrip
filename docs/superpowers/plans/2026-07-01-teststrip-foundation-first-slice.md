# Teststrip Foundation First Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first Teststrip foundation slice: a native macOS Swift app backed by a real catalog model, ingest path, preview pipeline, metadata state, work/session model, worker boundary, and provider seams.

**Architecture:** Use a Swift Package as the initial development unit. Keep domain logic in `TeststripCore`, the supervised worker protocol in `TeststripWorker`, and the native SwiftUI shell in `TeststripApp`. Persist catalog state in SQLite through a small local wrapper so the first slice has a real database without broad service machinery.

**Tech Stack:** Swift Package Manager, Swift 6, macOS 14+, SwiftUI, AppKit escape hatches as needed, SQLite3, XCTest, ImageIO/CoreGraphics, Foundation XML APIs, URLSession.

---

## Scope

This plan implements the foundation slice from `docs/superpowers/specs/2026-07-01-teststrip-design.md`. It does not build polished culling, photo editing, Lightroom migration, watched folders, a direct camera protocol integration, or an always-on background agent.

Card/camera ingest in this slice means filesystem-visible cards, mounted camera storage, and folders. A direct ImageCaptureCore source can use the same ingest interfaces in a future plan.

## File Structure

Create this structure:

```text
Package.swift
Sources/
  TeststripCore/
    Catalog/
      CatalogDatabase.swift
      CatalogError.swift
      CatalogMigrations.swift
      CatalogRepository.swift
    Decode/
      DecodeProvider.swift
      DecodeRegistry.swift
      ImageIODecodeProvider.swift
    Domain/
      Asset.swift
      Metadata.swift
      ProviderProvenance.swift
      SourceAvailability.swift
    Evaluation/
      EvaluationProvider.swift
      EvaluationSignal.swift
      LocalHTTPModelProvider.swift
    Ingest/
      FolderScanner.swift
      IngestPlanner.swift
      IngestService.swift
    Metadata/
      MetadataSyncQueue.swift
      XMPPacket.swift
    Preview/
      PreviewCache.swift
      PreviewLevel.swift
      PreviewRenderer.swift
      PreviewScheduler.swift
    Search/
      AssetSet.swift
      SetQuery.swift
    Support/
      FileFingerprint.swift
      StableID.swift
      TeststripError.swift
    Work/
      WorkSession.swift
      WorkSessionRepository.swift
  TeststripWorker/
    main.swift
    WorkerCommand.swift
    WorkerProtocol.swift
  TeststripApp/
    main.swift
    AppModel.swift
    SidebarView.swift
    LibraryGridView.swift
    ActivityView.swift
    InspectorView.swift
  TeststripBench/
    main.swift
Tests/
  TeststripCoreTests/
    CatalogDatabaseTests.swift
    DecodeRegistryTests.swift
    EvaluationProviderTests.swift
    FolderImportTests.swift
    MetadataSyncTests.swift
    PreviewRendererTests.swift
    PreviewSchedulerTests.swift
    SearchSetTests.swift
    TestSupport.swift
    WorkSessionTests.swift
  TeststripWorkerTests/
    WorkerProtocolTests.swift
  TeststripAppTests/
    AppModelTests.swift
```

## Task 1: Bootstrap Swift Package And Test Support

**Files:**
- Create: `Package.swift`
- Create: `Sources/TeststripCore/Support/TeststripError.swift`
- Create: `Sources/TeststripWorker/main.swift`
- Create: `Sources/TeststripApp/main.swift`
- Create: `Sources/TeststripBench/main.swift`
- Create: `Tests/TeststripCoreTests/TestSupport.swift`
- Test: `Tests/TeststripCoreTests/TestSupportTests.swift`
- Create: `Tests/TeststripWorkerTests/PlaceholderTests.swift`
- Create: `Tests/TeststripAppTests/PlaceholderTests.swift`

- [ ] **Step 1: Create the Swift package manifest**

Create `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Teststrip",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TeststripCore", targets: ["TeststripCore"]),
        .executable(name: "TeststripApp", targets: ["TeststripApp"]),
        .executable(name: "TeststripWorker", targets: ["TeststripWorker"]),
        .executable(name: "TeststripBench", targets: ["TeststripBench"])
    ],
    targets: [
        .target(
            name: "TeststripCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "TeststripWorker",
            dependencies: ["TeststripCore"]
        ),
        .executableTarget(
            name: "TeststripApp",
            dependencies: ["TeststripCore"]
        ),
        .executableTarget(
            name: "TeststripBench",
            dependencies: ["TeststripCore"]
        ),
        .testTarget(
            name: "TeststripCoreTests",
            dependencies: ["TeststripCore"]
        ),
        .testTarget(
            name: "TeststripWorkerTests",
            dependencies: ["TeststripCore", "TeststripWorker"]
        ),
        .testTarget(
            name: "TeststripAppTests",
            dependencies: ["TeststripCore", "TeststripApp"]
        )
    ]
)
```

- [ ] **Step 1a: Add minimal executable and test target placeholders**

Create `Sources/TeststripWorker/main.swift`:

```swift
// Placeholder entry point replaced by the worker protocol task.
```

Create `Sources/TeststripApp/main.swift`:

```swift
// Placeholder entry point replaced by the native app shell task.
```

Create `Sources/TeststripBench/main.swift`:

```swift
// Placeholder entry point replaced by the benchmark task.
```

Create `Tests/TeststripWorkerTests/PlaceholderTests.swift`:

```swift
import XCTest

final class PlaceholderWorkerTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

Create `Tests/TeststripAppTests/PlaceholderTests.swift`:

```swift
import XCTest

final class PlaceholderAppTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 2: Write the failing support test**

Create `Tests/TeststripCoreTests/TestSupportTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class TestSupportTests: XCTestCase {
    func testTemporaryDirectoryCreatesUniqueFolders() throws {
        let first = try TestDirectories.makeTemporaryDirectory(named: "support")
        let second = try TestDirectories.makeTemporaryDirectory(named: "support")

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertNotEqual(first, second)
    }

    func testTeststripErrorHasStableMessage() {
        let error = TeststripError.invalidState("catalog is closed")

        XCTAssertEqual(error.errorDescription, "catalog is closed")
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run:

```bash
swift test --filter TestSupportTests
```

Expected: FAIL because `TestDirectories` and `TeststripError` do not exist.

- [ ] **Step 4: Add minimal support implementation**

Create `Sources/TeststripCore/Support/TeststripError.swift`:

```swift
import Foundation

public enum TeststripError: LocalizedError, Equatable {
    case invalidState(String)
    case unsupportedFormat(String)
    case io(String)
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .invalidState(let message),
             .unsupportedFormat(let message),
             .io(let message),
             .database(let message):
            return message
        }
    }
}
```

Create `Tests/TeststripCoreTests/TestSupport.swift`:

```swift
import Foundation

enum TestDirectories {
    static func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
swift test --filter TestSupportTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

Run:

```bash
git status --short
git add Package.swift Sources/TeststripCore/Support/TeststripError.swift Sources/TeststripWorker/main.swift Sources/TeststripApp/main.swift Sources/TeststripBench/main.swift Tests/TeststripCoreTests/TestSupport.swift Tests/TeststripCoreTests/TestSupportTests.swift Tests/TeststripWorkerTests/PlaceholderTests.swift Tests/TeststripAppTests/PlaceholderTests.swift
git commit -m "Bootstrap Swift package" -m "Create the Swift Package layout for Teststrip's core library, app executable, worker executable, benchmark executable, and XCTest targets. Add shared test support and a small domain error type used by catalog and pipeline work."
```

## Task 2: Domain Model For Assets, Metadata, Provenance, And Availability

**Files:**
- Create: `Sources/TeststripCore/Domain/Asset.swift`
- Create: `Sources/TeststripCore/Domain/Metadata.swift`
- Create: `Sources/TeststripCore/Domain/ProviderProvenance.swift`
- Create: `Sources/TeststripCore/Domain/SourceAvailability.swift`
- Create: `Sources/TeststripCore/Support/StableID.swift`
- Test: `Tests/TeststripCoreTests/AssetDomainTests.swift`

- [ ] **Step 1: Write the failing domain tests**

Create `Tests/TeststripCoreTests/AssetDomainTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class AssetDomainTests: XCTestCase {
    func testAssetStoresExternalOriginalAndAvailability() {
        let asset = Asset(
            id: AssetID(rawValue: "asset-1"),
            originalURL: URL(fileURLWithPath: "/Volumes/Archive/2024/frame.dng"),
            volumeIdentifier: "ArchiveVolume",
            fingerprint: FileFingerprint(size: 42, modificationDate: Date(timeIntervalSince1970: 10), contentHash: "abc"),
            availability: .offline,
            metadata: AssetMetadata(rating: 4, colorLabel: .green, flag: .pick, keywords: ["Patagonia"])
        )

        XCTAssertEqual(asset.id.rawValue, "asset-1")
        XCTAssertEqual(asset.availability, .offline)
        XCTAssertEqual(asset.metadata.rating, 4)
        XCTAssertTrue(asset.metadata.keywords.contains("Patagonia"))
    }

    func testMetadataRejectsInvalidRating() {
        XCTAssertThrowsError(try AssetMetadata.validated(rating: 6, colorLabel: nil, flag: nil, keywords: [])) { error in
            XCTAssertEqual(error as? TeststripError, .invalidState("rating must be between 0 and 5"))
        }
    }

    func testProviderProvenanceIdentifiesSignalSource() {
        let provenance = ProviderProvenance(provider: "AppleVision", model: "aesthetics", version: "1", settingsHash: "default")

        XCTAssertEqual(provenance.provider, "AppleVision")
        XCTAssertEqual(provenance.model, "aesthetics")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter AssetDomainTests
```

Expected: FAIL because domain types do not exist.

- [ ] **Step 3: Add domain implementation**

Create `Sources/TeststripCore/Support/StableID.swift`:

```swift
import Foundation

public protocol StableID: Hashable, Codable, Sendable {
    var rawValue: String { get }
    init(rawValue: String)
}

public extension StableID {
    static func new() -> Self {
        Self(rawValue: UUID().uuidString)
    }
}
```

Create `Sources/TeststripCore/Domain/SourceAvailability.swift`:

```swift
public enum SourceAvailability: String, Codable, Sendable {
    case online
    case offline
    case missing
    case moved
    case stale
}
```

Create `Sources/TeststripCore/Domain/Metadata.swift`:

```swift
public enum ColorLabel: String, Codable, Sendable, CaseIterable {
    case red
    case yellow
    case green
    case blue
    case purple
}

public enum PickFlag: String, Codable, Sendable {
    case pick
    case reject
}

public struct AssetMetadata: Codable, Equatable, Sendable {
    public var rating: Int
    public var colorLabel: ColorLabel?
    public var flag: PickFlag?
    public var keywords: [String]
    public var caption: String?
    public var creator: String?
    public var copyright: String?

    public init(
        rating: Int = 0,
        colorLabel: ColorLabel? = nil,
        flag: PickFlag? = nil,
        keywords: [String] = [],
        caption: String? = nil,
        creator: String? = nil,
        copyright: String? = nil
    ) {
        self.rating = rating
        self.colorLabel = colorLabel
        self.flag = flag
        self.keywords = keywords
        self.caption = caption
        self.creator = creator
        self.copyright = copyright
    }

    public static func validated(
        rating: Int,
        colorLabel: ColorLabel?,
        flag: PickFlag?,
        keywords: [String]
    ) throws -> AssetMetadata {
        guard (0...5).contains(rating) else {
            throw TeststripError.invalidState("rating must be between 0 and 5")
        }
        return AssetMetadata(rating: rating, colorLabel: colorLabel, flag: flag, keywords: keywords)
    }
}
```

Create `Sources/TeststripCore/Domain/ProviderProvenance.swift`:

```swift
public struct ProviderProvenance: Codable, Equatable, Sendable {
    public var provider: String
    public var model: String
    public var version: String
    public var settingsHash: String

    public init(provider: String, model: String, version: String, settingsHash: String) {
        self.provider = provider
        self.model = model
        self.version = version
        self.settingsHash = settingsHash
    }
}
```

Create `Sources/TeststripCore/Support/FileFingerprint.swift`:

```swift
import Foundation

public struct FileFingerprint: Codable, Equatable, Sendable {
    public var size: Int64
    public var modificationDate: Date
    public var contentHash: String?

    public init(size: Int64, modificationDate: Date, contentHash: String? = nil) {
        self.size = size
        self.modificationDate = modificationDate
        self.contentHash = contentHash
    }
}
```

Create `Sources/TeststripCore/Domain/Asset.swift`:

```swift
import Foundation

public struct AssetID: StableID {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct Asset: Codable, Equatable, Sendable {
    public var id: AssetID
    public var originalURL: URL
    public var volumeIdentifier: String?
    public var fingerprint: FileFingerprint
    public var availability: SourceAvailability
    public var metadata: AssetMetadata

    public init(
        id: AssetID,
        originalURL: URL,
        volumeIdentifier: String?,
        fingerprint: FileFingerprint,
        availability: SourceAvailability,
        metadata: AssetMetadata
    ) {
        self.id = id
        self.originalURL = originalURL
        self.volumeIdentifier = volumeIdentifier
        self.fingerprint = fingerprint
        self.availability = availability
        self.metadata = metadata
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter AssetDomainTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripCore/Domain Sources/TeststripCore/Support/StableID.swift Sources/TeststripCore/Support/FileFingerprint.swift Tests/TeststripCoreTests/AssetDomainTests.swift
git commit -m "Add asset domain model" -m "Define the catalog-level asset, metadata, provenance, availability, stable id, and fingerprint types that make external non-destructive originals explicit. Include validation for user-facing metadata ratings."
```

## Task 3: SQLite Catalog Schema And Asset Repository

**Files:**
- Create: `Sources/TeststripCore/Catalog/CatalogError.swift`
- Create: `Sources/TeststripCore/Catalog/CatalogMigrations.swift`
- Create: `Sources/TeststripCore/Catalog/CatalogDatabase.swift`
- Create: `Sources/TeststripCore/Catalog/CatalogRepository.swift`
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

- [ ] **Step 1: Write the failing catalog repository tests**

Create `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class CatalogDatabaseTests: XCTestCase {
    func testMigratesAndPersistsAsset() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 3)
        try repository.upsert(asset)

        let fetched = try repository.asset(id: asset.id)

        XCTAssertEqual(fetched, asset)
    }

    func testMetadataUpdateIncrementsCatalogGeneration() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 1)
        try repository.upsert(asset)

        try repository.updateMetadata(assetID: asset.id) { metadata in
            metadata.rating = 5
            metadata.flag = .pick
        }

        let fetched = try repository.asset(id: asset.id)
        let generation = try repository.catalogGeneration(assetID: asset.id)
        XCTAssertEqual(fetched.metadata.rating, 5)
        XCTAssertEqual(fetched.metadata.flag, .pick)
        XCTAssertEqual(generation, 2)
    }

    func testFetchesAllAssetsForGridLoading() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let first = Asset.testAsset(path: "/Volumes/NAS/Job/a.cr2", rating: 2)
        let second = Asset.testAsset(path: "/Volumes/NAS/Job/b.cr2", rating: 5)
        try repository.upsert(first)
        try repository.upsert(second)

        let assets = try repository.allAssets(limit: 100)

        XCTAssertEqual(assets.map(\.id), [first.id, second.id])
    }
}

private extension Asset {
    static func testAsset(path: String, rating: Int) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "NAS",
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: "hash"),
            availability: .online,
            metadata: AssetMetadata(rating: rating)
        )
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter CatalogDatabaseTests
```

Expected: FAIL because catalog types do not exist.

- [ ] **Step 3: Add catalog schema and SQLite wrapper**

Create `Sources/TeststripCore/Catalog/CatalogError.swift`:

```swift
public enum CatalogError: Error, Equatable {
    case notFound(String)
    case sqlite(String)
}
```

Create `Sources/TeststripCore/Catalog/CatalogMigrations.swift`:

```swift
enum CatalogMigrations {
    static let version = 1

    static let statements = [
        """
        CREATE TABLE IF NOT EXISTS catalog_meta (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS assets (
            id TEXT PRIMARY KEY NOT NULL,
            original_path TEXT NOT NULL,
            volume_identifier TEXT,
            fingerprint_json TEXT NOT NULL,
            availability TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            catalog_generation INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_assets_original_path ON assets(original_path)",
        "CREATE INDEX IF NOT EXISTS idx_assets_availability ON assets(availability)"
    ]
}
```

Create `Sources/TeststripCore/Catalog/CatalogDatabase.swift`:

```swift
import Foundation
import SQLite3

public final class CatalogDatabase: @unchecked Sendable {
    private let handle: OpaquePointer

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }

    public static func open(at url: URL) throws -> CatalogDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw CatalogError.sqlite("unable to open catalog database")
        }
        return CatalogDatabase(handle: handle)
    }

    public func migrate() throws {
        for statement in CatalogMigrations.statements {
            try execute(statement)
        }
        try execute(
            "INSERT OR REPLACE INTO catalog_meta (key, value) VALUES ('schema_version', ?)",
            bindings: ["\(CatalogMigrations.version)"]
        )
    }

    func execute(_ sql: String, bindings: [String] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogError.sqlite(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogError.sqlite(lastError)
        }
    }

    func rows(_ sql: String, bindings: [String] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogError.sqlite(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var result: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                if let value = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: value)
                }
            }
            result.append(row)
        }
        return result
    }

    private func bind(_ bindings: [String], to statement: OpaquePointer?) throws {
        for (index, value) in bindings.enumerated() {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
                throw CatalogError.sqlite(lastError)
            }
        }
    }

    private var lastError: String {
        String(cString: sqlite3_errmsg(handle))
    }
}
```

Create `Sources/TeststripCore/Catalog/CatalogRepository.swift`:

```swift
import Foundation

public final class CatalogRepository {
    private let database: CatalogDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: CatalogDatabase) {
        self.database = database
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func upsert(_ asset: Asset) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO assets (id, original_path, volume_identifier, fingerprint_json, availability, metadata_json, catalog_generation, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                original_path = excluded.original_path,
                volume_identifier = excluded.volume_identifier,
                fingerprint_json = excluded.fingerprint_json,
                availability = excluded.availability,
                metadata_json = excluded.metadata_json,
                catalog_generation = assets.catalog_generation + 1,
                updated_at = excluded.updated_at
            """,
            bindings: [
                asset.id.rawValue,
                asset.originalURL.path,
                asset.volumeIdentifier ?? "",
                try encode(asset.fingerprint),
                asset.availability.rawValue,
                try encode(asset.metadata),
                now,
                now
            ]
        )
    }

    public func asset(id: AssetID) throws -> Asset {
        let rows = try database.rows("SELECT * FROM assets WHERE id = ?", bindings: [id.rawValue])
        guard let row = rows.first else {
            throw CatalogError.notFound(id.rawValue)
        }
        return try decodeAsset(row)
    }

    public func allAssets(limit: Int) throws -> [Asset] {
        let rows = try database.rows(
            "SELECT * FROM assets ORDER BY created_at ASC, id ASC LIMIT ?",
            bindings: ["\(limit)"]
        )
        return try rows.map(decodeAsset)
    }

    public func updateMetadata(assetID: AssetID, _ update: (inout AssetMetadata) throws -> Void) throws {
        var asset = try asset(id: assetID)
        try update(&asset.metadata)
        try upsert(asset)
    }

    public func catalogGeneration(assetID: AssetID) throws -> Int {
        let rows = try database.rows("SELECT catalog_generation FROM assets WHERE id = ?", bindings: [assetID.rawValue])
        guard let value = rows.first?["catalog_generation"], let intValue = Int(value) else {
            throw CatalogError.notFound(assetID.rawValue)
        }
        return intValue
    }

    private func decodeAsset(_ row: [String: String]) throws -> Asset {
        guard let id = row["id"],
              let path = row["original_path"],
              let fingerprintJSON = row["fingerprint_json"],
              let availabilityRaw = row["availability"],
              let availability = SourceAvailability(rawValue: availabilityRaw),
              let metadataJSON = row["metadata_json"] else {
            throw CatalogError.sqlite("asset row is missing required columns")
        }

        return Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: row["volume_identifier"].flatMap { $0.isEmpty ? nil : $0 },
            fingerprint: try decode(FileFingerprint.self, from: fingerprintJSON),
            availability: availability,
            metadata: try decode(AssetMetadata.self, from: metadataJSON)
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try encoder.encode(value), encoding: .utf8)!
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try decoder.decode(type, from: Data(string.utf8))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter CatalogDatabaseTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripCore/Catalog Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "Add SQLite catalog repository" -m "Create the first catalog schema and repository for external assets. Store metadata and fingerprints as encoded structured values while tracking a catalog generation for XMP conflict detection and worker coordination."
```

## Task 4: Set/Search Model And Work Session Membership

**Files:**
- Create: `Sources/TeststripCore/Search/AssetSet.swift`
- Create: `Sources/TeststripCore/Search/SetQuery.swift`
- Create: `Sources/TeststripCore/Work/WorkSession.swift`
- Create: `Sources/TeststripCore/Work/WorkSessionRepository.swift`
- Test: `Tests/TeststripCoreTests/SearchSetTests.swift`
- Test: `Tests/TeststripCoreTests/WorkSessionTests.swift`

- [ ] **Step 1: Write failing tests for set semantics**

Create `Tests/TeststripCoreTests/SearchSetTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class SearchSetTests: XCTestCase {
    func testManualSetPreservesExplicitMembershipAndOrdering() {
        let set = AssetSet.manual(
            id: AssetSetID(rawValue: "set-1"),
            name: "Portfolio candidates",
            assetIDs: [AssetID(rawValue: "b"), AssetID(rawValue: "a")]
        )

        XCTAssertEqual(set.membership, .manual([AssetID(rawValue: "b"), AssetID(rawValue: "a")]))
        XCTAssertFalse(set.isDynamic)
    }

    func testDynamicSetStoresStructuredQuery() {
        let query = SetQuery(predicates: [
            .ratingAtLeast(4),
            .keyword("Patagonia"),
            .availability(.online)
        ])
        let set = AssetSet.dynamic(id: AssetSetID(rawValue: "set-2"), name: "Online Patagonia Picks", query: query)

        XCTAssertTrue(set.isDynamic)
        XCTAssertEqual(set.membership, .dynamic(query))
    }
}
```

Create `Tests/TeststripCoreTests/WorkSessionTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class WorkSessionTests: XCTestCase {
    func testWorkSessionReferencesSetsInsteadOfOwningMembership() {
        let input = AssetSetID(rawValue: "input")
        let output = AssetSetID(rawValue: "accepted")
        let session = WorkSession(
            id: WorkSessionID(rawValue: "session-1"),
            kind: .culling,
            intent: "one hero per burst",
            status: .running,
            inputSetIDs: [input],
            outputSetIDs: [output],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 11)
        )

        XCTAssertEqual(session.inputSetIDs, [input])
        XCTAssertEqual(session.outputSetIDs, [output])
        XCTAssertEqual(session.intent, "one hero per burst")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter SearchSetTests
swift test --filter WorkSessionTests
```

Expected: FAIL because set and work session types do not exist.

- [ ] **Step 3: Add set/query/work models**

Create `Sources/TeststripCore/Search/SetQuery.swift`:

```swift
public struct SetQuery: Codable, Equatable, Sendable {
    public enum Predicate: Codable, Equatable, Sendable {
        case ratingAtLeast(Int)
        case keyword(String)
        case availability(SourceAvailability)
        case folderPrefix(String)
        case importBatch(String)
    }

    public var predicates: [Predicate]

    public init(predicates: [Predicate]) {
        self.predicates = predicates
    }
}
```

Create `Sources/TeststripCore/Search/AssetSet.swift`:

```swift
public struct AssetSetID: StableID {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct AssetSet: Codable, Equatable, Sendable {
    public enum Membership: Codable, Equatable, Sendable {
        case manual([AssetID])
        case dynamic(SetQuery)
        case snapshot([AssetID])
    }

    public var id: AssetSetID
    public var name: String
    public var membership: Membership
    public var starred: Bool

    public var isDynamic: Bool {
        if case .dynamic = membership { return true }
        return false
    }

    public static func manual(id: AssetSetID, name: String, assetIDs: [AssetID]) -> AssetSet {
        AssetSet(id: id, name: name, membership: .manual(assetIDs), starred: false)
    }

    public static func dynamic(id: AssetSetID, name: String, query: SetQuery) -> AssetSet {
        AssetSet(id: id, name: name, membership: .dynamic(query), starred: false)
    }
}
```

Create `Sources/TeststripCore/Work/WorkSession.swift`:

```swift
import Foundation

public struct WorkSessionID: StableID {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum WorkSessionKind: String, Codable, Sendable {
    case ingest
    case previewGeneration
    case recognition
    case culling
    case collecting
    case searchSort
    case keywording
    case xmpSync
    case export
}

public enum WorkSessionStatus: String, Codable, Sendable {
    case queued
    case running
    case paused
    case completed
    case failed
    case cancelled
}

public struct WorkSession: Codable, Equatable, Sendable {
    public var id: WorkSessionID
    public var kind: WorkSessionKind
    public var intent: String
    public var status: WorkSessionStatus
    public var inputSetIDs: [AssetSetID]
    public var outputSetIDs: [AssetSetID]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: WorkSessionID,
        kind: WorkSessionKind,
        intent: String,
        status: WorkSessionStatus,
        inputSetIDs: [AssetSetID],
        outputSetIDs: [AssetSetID],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.intent = intent
        self.status = status
        self.inputSetIDs = inputSetIDs
        self.outputSetIDs = outputSetIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

Create `Sources/TeststripCore/Work/WorkSessionRepository.swift`:

```swift
public protocol WorkSessionRepository: Sendable {
    func save(_ session: WorkSession) throws
    func session(id: WorkSessionID) throws -> WorkSession
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter SearchSetTests
swift test --filter WorkSessionTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripCore/Search Sources/TeststripCore/Work Tests/TeststripCoreTests/SearchSetTests.swift Tests/TeststripCoreTests/WorkSessionTests.swift
git commit -m "Model sets and work sessions" -m "Represent asset membership as sets and searches while keeping work sessions as activity records that reference input and output sets. This preserves the design distinction between workflow history and reusable catalog membership."
```

## Task 5: Decode Provider Registry

**Files:**
- Create: `Sources/TeststripCore/Decode/DecodeProvider.swift`
- Create: `Sources/TeststripCore/Decode/DecodeRegistry.swift`
- Create: `Sources/TeststripCore/Decode/ImageIODecodeProvider.swift`
- Test: `Tests/TeststripCoreTests/DecodeRegistryTests.swift`

- [ ] **Step 1: Write failing decode registry tests**

Create `Tests/TeststripCoreTests/DecodeRegistryTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class DecodeRegistryTests: XCTestCase {
    func testRegistrySelectsProviderByFileExtension() throws {
        let provider = FakeDecodeProvider(name: "fake", extensions: ["cr2", "dng"])
        let registry = DecodeRegistry(providers: [provider])

        let selected = try registry.provider(for: URL(fileURLWithPath: "/tmp/photo.CR2"))

        XCTAssertEqual(selected.name, "fake")
    }

    func testRegistryThrowsForUnsupportedFormat() {
        let registry = DecodeRegistry(providers: [])

        XCTAssertThrowsError(try registry.provider(for: URL(fileURLWithPath: "/tmp/photo.lytro"))) { error in
            XCTAssertEqual(error as? TeststripError, .unsupportedFormat("no decode provider for lytro"))
        }
    }
}

private struct FakeDecodeProvider: DecodeProvider {
    let name: String
    let supportedExtensions: Set<String>

    init(name: String, extensions: [String]) {
        self.name = name
        self.supportedExtensions = Set(extensions)
    }

    func canDecode(url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    func metadata(for url: URL) throws -> DecodeMetadata {
        DecodeMetadata(pixelWidth: 1, pixelHeight: 1, provenance: ProviderProvenance(provider: name, model: "fake", version: "1", settingsHash: "default"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter DecodeRegistryTests
```

Expected: FAIL because decode types do not exist.

- [ ] **Step 3: Add provider protocol and registry**

Create `Sources/TeststripCore/Decode/DecodeProvider.swift`:

```swift
import Foundation

public struct DecodeMetadata: Codable, Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var provenance: ProviderProvenance

    public init(pixelWidth: Int, pixelHeight: Int, provenance: ProviderProvenance) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.provenance = provenance
    }
}

public protocol DecodeProvider: Sendable {
    var name: String { get }
    func canDecode(url: URL) -> Bool
    func metadata(for url: URL) throws -> DecodeMetadata
}
```

Create `Sources/TeststripCore/Decode/DecodeRegistry.swift`:

```swift
import Foundation

public struct DecodeRegistry: Sendable {
    private let providers: [DecodeProvider]

    public init(providers: [DecodeProvider]) {
        self.providers = providers
    }

    public func provider(for url: URL) throws -> DecodeProvider {
        if let provider = providers.first(where: { $0.canDecode(url: url) }) {
            return provider
        }
        let ext = url.pathExtension.lowercased()
        throw TeststripError.unsupportedFormat("no decode provider for \(ext)")
    }
}
```

Create `Sources/TeststripCore/Decode/ImageIODecodeProvider.swift`:

```swift
import Foundation
import ImageIO

public struct ImageIODecodeProvider: DecodeProvider {
    public let name = "ImageIO"

    private let extensions: Set<String> = [
        "jpg", "jpeg", "heic", "tif", "tiff", "png",
        "dng", "cr2", "cr3", "nef", "arw", "raf", "rw2", "orf"
    ]

    public init() {}

    public func canDecode(url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    public func metadata(for url: URL) throws -> DecodeMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw TeststripError.unsupportedFormat("ImageIO could not read \(url.lastPathComponent)")
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return DecodeMetadata(
            pixelWidth: width,
            pixelHeight: height,
            provenance: ProviderProvenance(provider: name, model: "ImageIO", version: "1", settingsHash: "default")
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter DecodeRegistryTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripCore/Decode Tests/TeststripCoreTests/DecodeRegistryTests.swift
git commit -m "Add decode provider registry" -m "Introduce the image decode provider abstraction and an ImageIO-backed provider so format support can expand without hardcoding one RAW path into catalog or preview code."
```

## Task 6: Preview Levels, Cache, And Scheduling Policy

**Files:**
- Create: `Sources/TeststripCore/Preview/PreviewLevel.swift`
- Create: `Sources/TeststripCore/Preview/PreviewCache.swift`
- Create: `Sources/TeststripCore/Preview/PreviewScheduler.swift`
- Test: `Tests/TeststripCoreTests/PreviewSchedulerTests.swift`

- [ ] **Step 1: Write failing preview scheduling tests**

Create `Tests/TeststripCoreTests/PreviewSchedulerTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class PreviewSchedulerTests: XCTestCase {
    func testVisibleLoupeRequestPromotesToLargePreview() {
        let scheduler = PreviewScheduler()
        let request = scheduler.request(
            assetID: AssetID(rawValue: "asset-1"),
            context: .loupe(isVisible: true, requestedFullResolution: false)
        )

        XCTAssertEqual(request.level, .large)
        XCTAssertEqual(request.priority, .visible)
    }

    func testGridPrefetchUsesGridLevelWithNearbyPriority() {
        let scheduler = PreviewScheduler()
        let request = scheduler.request(
            assetID: AssetID(rawValue: "asset-2"),
            context: .grid(distanceFromViewport: 12)
        )

        XCTAssertEqual(request.level, .grid)
        XCTAssertEqual(request.priority, .nearby)
    }

    func testFullResolutionOnlyWhenRequested() {
        let scheduler = PreviewScheduler()
        let request = scheduler.request(
            assetID: AssetID(rawValue: "asset-3"),
            context: .loupe(isVisible: true, requestedFullResolution: true)
        )

        XCTAssertEqual(request.level, .original)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter PreviewSchedulerTests
```

Expected: FAIL because preview types do not exist.

- [ ] **Step 3: Add preview level and scheduler implementation**

Create `Sources/TeststripCore/Preview/PreviewLevel.swift`:

```swift
public enum PreviewLevel: String, Codable, CaseIterable, Sendable {
    case micro
    case grid
    case medium
    case large
    case original

    public var maxPixelDimension: Int? {
        switch self {
        case .micro: return 160
        case .grid: return 512
        case .medium: return 1600
        case .large: return 3200
        case .original: return nil
        }
    }
}
```

Create `Sources/TeststripCore/Preview/PreviewCache.swift`:

```swift
import Foundation

public struct PreviewCacheKey: Hashable, Sendable {
    public var assetID: AssetID
    public var level: PreviewLevel
}

public struct PreviewCache: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(for key: PreviewCacheKey) -> URL {
        root
            .appendingPathComponent(key.assetID.rawValue, isDirectory: true)
            .appendingPathComponent("\(key.level.rawValue).jpg")
    }
}
```

Create `Sources/TeststripCore/Preview/PreviewScheduler.swift`:

```swift
public enum PreviewContext: Equatable, Sendable {
    case grid(distanceFromViewport: Int)
    case loupe(isVisible: Bool, requestedFullResolution: Bool)
    case timeline
}

public enum PreviewPriority: Int, Codable, Sendable {
    case visible = 0
    case nearby = 1
    case background = 2
}

public struct PreviewRequest: Equatable, Sendable {
    public var assetID: AssetID
    public var level: PreviewLevel
    public var priority: PreviewPriority
}

public struct PreviewScheduler: Sendable {
    public init() {}

    public func request(assetID: AssetID, context: PreviewContext) -> PreviewRequest {
        switch context {
        case .timeline:
            return PreviewRequest(assetID: assetID, level: .micro, priority: .background)
        case .grid(let distance):
            let priority: PreviewPriority = distance <= 0 ? .visible : (distance <= 24 ? .nearby : .background)
            return PreviewRequest(assetID: assetID, level: .grid, priority: priority)
        case .loupe(let isVisible, let requestedFullResolution):
            return PreviewRequest(
                assetID: assetID,
                level: requestedFullResolution ? .original : .large,
                priority: isVisible ? .visible : .nearby
            )
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter PreviewSchedulerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripCore/Preview Tests/TeststripCoreTests/PreviewSchedulerTests.swift
git commit -m "Add preview scheduling model" -m "Define the preview pyramid levels, cache key paths, and viewport-aware scheduling policy that keeps normal browsing on local previews unless original pixels are explicitly requested."
```

## Task 7: Preview Renderer

**Files:**
- Create: `Sources/TeststripCore/Preview/PreviewRenderer.swift`
- Test: `Tests/TeststripCoreTests/PreviewRendererTests.swift`

- [ ] **Step 1: Write failing preview renderer test**

Create `Tests/TeststripCoreTests/PreviewRendererTests.swift`:

```swift
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TeststripCore

final class PreviewRendererTests: XCTestCase {
    func testRendererCreatesBoundedGridPreview() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "preview-render")
        let source = directory.appendingPathComponent("source.jpg")
        let output = directory.appendingPathComponent("grid.jpg")
        try writeTestJPEG(to: source, width: 1200, height: 800)

        let renderer = PreviewRenderer()
        try renderer.render(sourceURL: source, level: .grid, destinationURL: output)

        let dimensions = try renderer.dimensions(of: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), PreviewLevel.grid.maxPixelDimension!)
    }

    private func writeTestJPEG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TeststripError.io("could not create test bitmap context")
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create test jpeg")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write test jpeg")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter PreviewRendererTests
```

Expected: FAIL because `PreviewRenderer` does not exist.

- [ ] **Step 3: Add preview renderer implementation**

Create `Sources/TeststripCore/Preview/PreviewRenderer.swift`:

```swift
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct PreviewDimensions: Equatable, Sendable {
    public var width: Int
    public var height: Int
}

public struct PreviewRenderer: Sendable {
    public init() {}

    public func render(sourceURL: URL, level: PreviewLevel, destinationURL: URL) throws {
        guard let maxDimension = level.maxPixelDimension else {
            throw TeststripError.invalidState("original preview level is not rendered into cache")
        }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw TeststripError.unsupportedFormat("could not read \(sourceURL.lastPathComponent)")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw TeststripError.unsupportedFormat("could not render preview for \(sourceURL.lastPathComponent)")
        }

        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TeststripError.io("could not create preview destination")
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write preview \(destinationURL.path)")
        }
    }

    public func dimensions(of url: URL) throws -> PreviewDimensions {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw TeststripError.unsupportedFormat("could not inspect \(url.lastPathComponent)")
        }
        return PreviewDimensions(width: width, height: height)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter PreviewRendererTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripCore/Preview/PreviewRenderer.swift Tests/TeststripCoreTests/PreviewRendererTests.swift
git commit -m "Add preview renderer" -m "Render bounded JPEG previews from source images using ImageIO so the preview pyramid has a real generation path before worker scheduling is connected."
```

## Task 8: Folder Scanner And Ingest Planner

**Files:**
- Create: `Sources/TeststripCore/Ingest/FolderScanner.swift`
- Create: `Sources/TeststripCore/Ingest/IngestPlanner.swift`
- Create: `Sources/TeststripCore/Ingest/IngestService.swift`
- Test: `Tests/TeststripCoreTests/FolderImportTests.swift`

- [ ] **Step 1: Write failing ingest tests**

Create `Tests/TeststripCoreTests/FolderImportTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class FolderImportTests: XCTestCase {
    func testFolderScannerFindsSupportedImageFiles() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "scan")
        try Data("raw".utf8).write(to: root.appendingPathComponent("one.CR2"))
        try Data("jpg".utf8).write(to: root.appendingPathComponent("two.jpg"))
        try Data("txt".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let scanner = FolderScanner(supportedExtensions: ["cr2", "jpg"])
        let files = try scanner.scan(root: root).map(\.lastPathComponent).sorted()

        XCTAssertEqual(files, ["one.CR2", "two.jpg"])
    }

    func testAddFolderPlanDoesNotMoveOriginals() throws {
        let source = URL(fileURLWithPath: "/Volumes/NAS/Job")
        let plan = IngestPlanner.addFolder(source)

        XCTAssertEqual(plan.mode, .addInPlace)
        XCTAssertEqual(plan.sourceRoot, source)
        XCTAssertNil(plan.destinationRoot)
    }

    func testCardCopyPlanComputesDestination() throws {
        let source = URL(fileURLWithPath: "/Volumes/Card/DCIM")
        let destination = URL(fileURLWithPath: "/Photos/2026")
        let plan = IngestPlanner.copyFromCard(source: source, destinationRoot: destination)

        XCTAssertEqual(plan.mode, .copyToDestination)
        XCTAssertEqual(plan.destinationRoot, destination)
    }

    func testIngestServiceCatalogsFolderAssetsInPlace() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "ingest")
        let image = root.appendingPathComponent("one.jpg")
        try Data("jpg".utf8).write(to: image)
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let service = IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"]))

        let imported = try service.ingest(plan: IngestPlanner.addFolder(root), repository: repository)

        XCTAssertEqual(imported.count, 1)
        let fetched = try repository.asset(id: imported[0].id)
        XCTAssertEqual(fetched.originalURL, image)
        XCTAssertEqual(fetched.availability, .online)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter FolderImportTests
```

Expected: FAIL because ingest types do not exist.

- [ ] **Step 3: Add folder scanner and ingest planner**

Create `Sources/TeststripCore/Ingest/FolderScanner.swift`:

```swift
import Foundation

public struct FolderScanner: Sendable {
    private let supportedExtensions: Set<String>

    public init(supportedExtensions: Set<String>) {
        self.supportedExtensions = supportedExtensions
    }

    public func scan(root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw TeststripError.io("unable to scan \(root.path)")
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            if supportedExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files
    }
}
```

Create `Sources/TeststripCore/Ingest/IngestPlanner.swift`:

```swift
import Foundation

public struct IngestPlan: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case addInPlace
        case copyToDestination
    }

    public var mode: Mode
    public var sourceRoot: URL
    public var destinationRoot: URL?
}

public enum IngestPlanner {
    public static func addFolder(_ source: URL) -> IngestPlan {
        IngestPlan(mode: .addInPlace, sourceRoot: source, destinationRoot: nil)
    }

    public static func copyFromCard(source: URL, destinationRoot: URL) -> IngestPlan {
        IngestPlan(mode: .copyToDestination, sourceRoot: source, destinationRoot: destinationRoot)
    }
}
```

Create `Sources/TeststripCore/Ingest/IngestService.swift`:

```swift
import Foundation

public struct IngestService: Sendable {
    public var scanner: FolderScanner

    public init(scanner: FolderScanner) {
        self.scanner = scanner
    }

    public func files(for plan: IngestPlan) throws -> [URL] {
        try scanner.scan(root: plan.sourceRoot)
    }

    public func ingest(plan: IngestPlan, repository: CatalogRepository) throws -> [Asset] {
        let sourceFiles = try files(for: plan)
        var assets: [Asset] = []
        for sourceFile in sourceFiles {
            let originalURL = try catalogURL(for: sourceFile, plan: plan)
            let fingerprint = try fingerprint(for: originalURL)
            let asset = Asset(
                id: .new(),
                originalURL: originalURL,
                volumeIdentifier: originalURL.pathComponents.dropFirst().first,
                fingerprint: fingerprint,
                availability: .online,
                metadata: AssetMetadata()
            )
            try repository.upsert(asset)
            assets.append(asset)
        }
        return assets
    }

    private func catalogURL(for sourceFile: URL, plan: IngestPlan) throws -> URL {
        switch plan.mode {
        case .addInPlace:
            return sourceFile
        case .copyToDestination:
            guard let destinationRoot = plan.destinationRoot else {
                throw TeststripError.invalidState("copy ingest requires destination root")
            }
            try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
            let destination = destinationRoot.appendingPathComponent(sourceFile.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: sourceFile, to: destination)
            }
            return destination
        }
    }

    private func fingerprint(for url: URL) throws -> FileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        return FileFingerprint(size: size, modificationDate: modificationDate)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter FolderImportTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripCore/Ingest Tests/TeststripCoreTests/FolderImportTests.swift
git commit -m "Add folder ingest planning" -m "Create the first ingest primitives for adding folders in place and planning card-style copies from filesystem-visible sources. Keep import preservation separate from downstream preview or recognition work."
```

## Task 9: Metadata Sync Queue And XMP Packet Round Trip

**Files:**
- Create: `Sources/TeststripCore/Metadata/MetadataSyncQueue.swift`
- Create: `Sources/TeststripCore/Metadata/XMPPacket.swift`
- Test: `Tests/TeststripCoreTests/MetadataSyncTests.swift`

- [ ] **Step 1: Write failing metadata sync tests**

Create `Tests/TeststripCoreTests/MetadataSyncTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class MetadataSyncTests: XCTestCase {
    func testXMPPacketRoundTripsPortableMetadata() throws {
        let metadata = AssetMetadata(
            rating: 5,
            colorLabel: .green,
            flag: .pick,
            keywords: ["Patagonia", "mountains"],
            caption: "Fitz Roy sunrise",
            creator: "Jesse",
            copyright: "Copyright Jesse"
        )

        let xml = try XMPPacket(metadata: metadata).xmlData()
        let parsed = try XMPPacket.parse(xml)

        XCTAssertEqual(parsed.metadata.rating, 5)
        XCTAssertEqual(parsed.metadata.colorLabel, .green)
        XCTAssertEqual(parsed.metadata.keywords, ["Patagonia", "mountains"])
        XCTAssertEqual(parsed.metadata.caption, "Fitz Roy sunrise")
    }

    func testSyncQueueTracksPendingWriteWithCatalogGeneration() {
        let item = MetadataSyncItem(
            assetID: AssetID(rawValue: "asset-1"),
            sidecarURL: URL(fileURLWithPath: "/Photos/frame.xmp"),
            catalogGeneration: 7,
            lastSyncedFingerprint: "old"
        )

        XCTAssertEqual(item.catalogGeneration, 7)
        XCTAssertEqual(item.lastSyncedFingerprint, "old")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter MetadataSyncTests
```

Expected: FAIL because metadata sync types do not exist.

- [ ] **Step 3: Add XMP packet and queue item implementation**

Create `Sources/TeststripCore/Metadata/MetadataSyncQueue.swift`:

```swift
import Foundation

public struct MetadataSyncItem: Codable, Equatable, Sendable {
    public var assetID: AssetID
    public var sidecarURL: URL
    public var catalogGeneration: Int
    public var lastSyncedFingerprint: String?

    public init(assetID: AssetID, sidecarURL: URL, catalogGeneration: Int, lastSyncedFingerprint: String?) {
        self.assetID = assetID
        self.sidecarURL = sidecarURL
        self.catalogGeneration = catalogGeneration
        self.lastSyncedFingerprint = lastSyncedFingerprint
    }
}
```

Create `Sources/TeststripCore/Metadata/XMPPacket.swift`:

```swift
import Foundation

public struct XMPPacket: Equatable, Sendable {
    public var metadata: AssetMetadata

    public init(metadata: AssetMetadata) {
        self.metadata = metadata
    }

    public func xmlData() throws -> Data {
        let document = XMLDocument(rootElement: XMLElement(name: "xmpmeta"))
        let root = document.rootElement()!
        root.addAttribute(XMLNode.attribute(withName: "xmlns:ts", stringValue: "https://teststrip.app/xmp") as! XMLNode)

        func add(_ name: String, _ value: String?) {
            guard let value else { return }
            let element = XMLElement(name: name, stringValue: value)
            root.addChild(element)
        }

        add("rating", "\(metadata.rating)")
        add("colorLabel", metadata.colorLabel?.rawValue)
        add("flag", metadata.flag?.rawValue)
        add("caption", metadata.caption)
        add("creator", metadata.creator)
        add("copyright", metadata.copyright)

        let keywords = XMLElement(name: "keywords")
        for keyword in metadata.keywords {
            keywords.addChild(XMLElement(name: "keyword", stringValue: keyword))
        }
        root.addChild(keywords)

        return document.xmlData(options: [.nodePrettyPrint])
    }

    public static func parse(_ data: Data) throws -> XMPPacket {
        let document = try XMLDocument(data: data)
        let root = document.rootElement()
        func text(_ name: String) -> String? {
            root?.elements(forName: name).first?.stringValue
        }
        let keywordNodes = root?.elements(forName: "keywords").first?.elements(forName: "keyword") ?? []
        let keywords = keywordNodes.compactMap(\.stringValue)
        let metadata = AssetMetadata(
            rating: Int(text("rating") ?? "0") ?? 0,
            colorLabel: text("colorLabel").flatMap(ColorLabel.init(rawValue:)),
            flag: text("flag").flatMap(PickFlag.init(rawValue:)),
            keywords: keywords,
            caption: text("caption"),
            creator: text("creator"),
            copyright: text("copyright")
        )
        return XMPPacket(metadata: metadata)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter MetadataSyncTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripCore/Metadata Tests/TeststripCoreTests/MetadataSyncTests.swift
git commit -m "Add metadata sync primitives" -m "Create the portable metadata packet and queued sidecar sync item used by catalog-first XMP mirroring. Track catalog generation and last synced fingerprints for conflict detection."
```

## Task 10: Evaluation Provider Scaffolding

**Files:**
- Create: `Sources/TeststripCore/Evaluation/EvaluationSignal.swift`
- Create: `Sources/TeststripCore/Evaluation/EvaluationProvider.swift`
- Create: `Sources/TeststripCore/Evaluation/LocalHTTPModelProvider.swift`
- Test: `Tests/TeststripCoreTests/EvaluationProviderTests.swift`

- [ ] **Step 1: Write failing evaluation provider tests**

Create `Tests/TeststripCoreTests/EvaluationProviderTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class EvaluationProviderTests: XCTestCase {
    func testSignalStoresTypedValueAndProvenance() {
        let signal = EvaluationSignal(
            assetID: AssetID(rawValue: "asset-1"),
            kind: .focus,
            value: .score(0.92),
            confidence: 0.8,
            provenance: ProviderProvenance(provider: "AppleVision", model: "focus", version: "1", settingsHash: "default")
        )

        XCTAssertEqual(signal.kind, .focus)
        XCTAssertEqual(signal.value, .score(0.92))
        XCTAssertEqual(signal.provenance.provider, "AppleVision")
    }

    func testLocalHTTPProviderBuildsOpenAICompatibleRequest() throws {
        let provider = LocalHTTPModelProvider(
            endpoint: URL(string: "http://localhost:11434/v1/chat/completions")!,
            model: "llava"
        )

        let request = try provider.request(for: URL(fileURLWithPath: "/tmp/frame.jpg"), prompt: "Describe culling signals")

        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNotNil(request.httpBody)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter EvaluationProviderTests
```

Expected: FAIL because evaluation provider types do not exist.

- [ ] **Step 3: Add evaluation signal and local HTTP provider**

Create `Sources/TeststripCore/Evaluation/EvaluationSignal.swift`:

```swift
public enum EvaluationKind: String, Codable, Sendable {
    case focus
    case motionBlur
    case exposure
    case aesthetics
    case object
    case faceQuality
    case ocrText
    case colorPalette
    case novelty
}

public enum EvaluationValue: Codable, Equatable, Sendable {
    case score(Double)
    case label(String)
    case text(String)
    case vector([Double])
}

public struct EvaluationSignal: Codable, Equatable, Sendable {
    public var assetID: AssetID
    public var kind: EvaluationKind
    public var value: EvaluationValue
    public var confidence: Double
    public var provenance: ProviderProvenance

    public init(assetID: AssetID, kind: EvaluationKind, value: EvaluationValue, confidence: Double, provenance: ProviderProvenance) {
        self.assetID = assetID
        self.kind = kind
        self.value = value
        self.confidence = confidence
        self.provenance = provenance
    }
}
```

Create `Sources/TeststripCore/Evaluation/EvaluationProvider.swift`:

```swift
import Foundation

public protocol EvaluationProvider: Sendable {
    var name: String { get }
    func evaluate(assetID: AssetID, previewURL: URL) async throws -> [EvaluationSignal]
}
```

Create `Sources/TeststripCore/Evaluation/LocalHTTPModelProvider.swift`:

```swift
import Foundation

public struct LocalHTTPModelProvider: Sendable {
    public var endpoint: URL
    public var model: String

    public init(endpoint: URL, model: String) {
        self.endpoint = endpoint
        self.model = model
    }

    public func request(for imageURL: URL, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "text", "text": "image_path:\(imageURL.path)"]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter EvaluationProviderTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripCore/Evaluation Tests/TeststripCoreTests/EvaluationProviderTests.swift
git commit -m "Add evaluation provider scaffolding" -m "Represent typed recognition and evaluation signals with provenance and add a local HTTP model request builder to exercise the future cloud/local-provider boundary without wiring provider-specific UI."
```

## Task 11: Worker Protocol And Supervision Boundary

**Files:**
- Create: `Sources/TeststripWorker/WorkerCommand.swift`
- Create: `Sources/TeststripWorker/WorkerProtocol.swift`
- Modify: `Sources/TeststripWorker/main.swift`
- Test: `Tests/TeststripWorkerTests/WorkerProtocolTests.swift`

- [ ] **Step 1: Write failing worker protocol tests**

Create `Tests/TeststripWorkerTests/WorkerProtocolTests.swift`:

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripWorker

final class WorkerProtocolTests: XCTestCase {
    func testWorkerCommandRoundTripsThroughJSONLine() throws {
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .large)

        let line = try WorkerProtocolEncoder.encode(command)
        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, command)
    }

    func testPauseAndCancelCommandsAreExplicit() throws {
        XCTAssertEqual(try WorkerProtocolEncoder.decode(try WorkerProtocolEncoder.encode(.pause)).controlKind, .pause)
        XCTAssertEqual(try WorkerProtocolEncoder.decode(try WorkerProtocolEncoder.encode(.cancelAll)).controlKind, .cancelAll)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter WorkerProtocolTests
```

Expected: FAIL because worker protocol types do not exist.

- [ ] **Step 3: Add JSON-line worker protocol**

Create `Sources/TeststripWorker/WorkerCommand.swift`:

```swift
import Foundation
import TeststripCore

public enum WorkerControlKind: String, Codable, Equatable, Sendable {
    case pause
    case cancelAll
}

public enum WorkerCommand: Codable, Equatable, Sendable {
    case generatePreview(assetID: AssetID, level: PreviewLevel)
    case syncMetadata(assetID: AssetID)
    case runEvaluation(assetID: AssetID, provider: String)
    case pause
    case cancelAll

    public var controlKind: WorkerControlKind? {
        switch self {
        case .pause: return .pause
        case .cancelAll: return .cancelAll
        case .generatePreview, .syncMetadata, .runEvaluation: return nil
        }
    }
}
```

Create `Sources/TeststripWorker/WorkerProtocol.swift`:

```swift
import Foundation

public enum WorkerProtocolEncoder {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ command: WorkerCommand) throws -> String {
        let data = try encoder.encode(command)
        return String(data: data, encoding: .utf8)! + "\n"
    }

    public static func decode(_ line: String) throws -> WorkerCommand {
        try decoder.decode(WorkerCommand.self, from: Data(line.utf8))
    }
}
```

Replace `Sources/TeststripWorker/main.swift`:

```swift
import Foundation
import TeststripCore

while let line = readLine() {
    do {
        let command = try WorkerProtocolEncoder.decode(line)
        let response = "accepted \(command)\n"
        FileHandle.standardOutput.write(Data(response.utf8))
    } catch {
        let response = "error \(error)\n"
        FileHandle.standardError.write(Data(response.utf8))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
swift test --filter WorkerProtocolTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripWorker Tests/TeststripWorkerTests/WorkerProtocolTests.swift
git commit -m "Add supervised worker protocol" -m "Create the initial JSON-line worker command protocol with explicit preview, metadata sync, evaluation, pause, and cancel commands. This gives the UI process a manageable worker boundary before real task execution is added."
```

## Task 12: SwiftUI App Shell And View Model

**Files:**
- Modify: `Sources/TeststripApp/main.swift`
- Create: `Sources/TeststripApp/AppModel.swift`
- Create: `Sources/TeststripApp/SidebarView.swift`
- Create: `Sources/TeststripApp/LibraryGridView.swift`
- Create: `Sources/TeststripApp/ActivityView.swift`
- Create: `Sources/TeststripApp/InspectorView.swift`
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

- [ ] **Step 1: Write failing app model tests**

Create `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class AppModelTests: XCTestCase {
    func testAppModelStartsWithStudioLayoutSections() {
        let model = AppModel.demo()

        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Library"))
        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Work"))
        XCTAssertEqual(model.selectedView, .grid)
    }

    func testSelectingAssetUpdatesInspector() {
        var model = AppModel.demo()
        let asset = model.assets[0]

        model.select(asset.id)

        XCTAssertEqual(model.selectedAsset?.id, asset.id)
    }

    func testLoadsAssetsFromCatalogRepository() throws {
        let directory = try makeTemporaryDirectory(named: "app-model")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "catalog-asset"),
            originalURL: URL(fileURLWithPath: "/Photos/catalog.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(rating: 5)
        )
        try repository.upsert(asset)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.assets.map(\.id), [asset.id])
        XCTAssertEqual(model.selectedAsset?.id, asset.id)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter AppModelTests
```

Expected: FAIL because app model types do not exist.

- [ ] **Step 3: Add app model and minimal SwiftUI shell**

Create `Sources/TeststripApp/AppModel.swift`:

```swift
import Foundation
import Observation
import TeststripCore

public enum LibraryViewMode: String, Sendable {
    case grid
    case loupe
    case compare
    case timeline
    case map
    case people
}

public struct SidebarSection: Identifiable, Equatable {
    public var id: String { title }
    public var title: String
    public var rows: [String]
}

@Observable
public final class AppModel {
    public var sidebarSections: [SidebarSection]
    public var selectedView: LibraryViewMode
    public var assets: [Asset]
    public var selectedAssetID: AssetID?

    public var selectedAsset: Asset? {
        assets.first { $0.id == selectedAssetID }
    }

    public init(sidebarSections: [SidebarSection], selectedView: LibraryViewMode, assets: [Asset]) {
        self.sidebarSections = sidebarSections
        self.selectedView = selectedView
        self.assets = assets
        self.selectedAssetID = assets.first?.id
    }

    public static func demo() -> AppModel {
        let asset = Asset(
            id: AssetID(rawValue: "demo-1"),
            originalURL: URL(fileURLWithPath: "/Photos/demo.jpg"),
            volumeIdentifier: "Demo",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(rating: 4, colorLabel: .green, flag: .pick, keywords: ["demo"])
        )
        return AppModel(
            sidebarSections: [
                SidebarSection(title: "Library", rows: ["All Photographs", "Folders", "People", "Places"]),
                SidebarSection(title: "Work", rows: ["Recent", "Starred"])
            ],
            selectedView: .grid,
            assets: [asset]
        )
    }

    public static func load(repository: CatalogRepository) throws -> AppModel {
        AppModel(
            sidebarSections: [
                SidebarSection(title: "Library", rows: ["All Photographs", "Folders", "People", "Places"]),
                SidebarSection(title: "Work", rows: ["Recent", "Starred"])
            ],
            selectedView: .grid,
            assets: try repository.allAssets(limit: 500)
        )
    }

    public func select(_ assetID: AssetID) {
        selectedAssetID = assetID
    }
}
```

Replace `Sources/TeststripApp/main.swift`:

```swift
import SwiftUI

struct TeststripApplication: App {
    @State private var model = AppModel.demo()

    var body: some Scene {
        WindowGroup("Teststrip") {
            NavigationSplitView {
                SidebarView(model: model)
            } content: {
                LibraryGridView(model: model)
            } detail: {
                InspectorView(model: model)
            }
            .frame(minWidth: 1100, minHeight: 720)
        }
    }
}

TeststripApplication.main()
```

Create `Sources/TeststripApp/SidebarView.swift`:

```swift
import SwiftUI

struct SidebarView: View {
    var model: AppModel

    var body: some View {
        List {
            ForEach(model.sidebarSections) { section in
                Section(section.title) {
                    ForEach(section.rows, id: \.self) { row in
                        Text(row)
                    }
                }
            }
        }
        .navigationTitle("Teststrip")
    }
}
```

Create `Sources/TeststripApp/LibraryGridView.swift`:

```swift
import SwiftUI

struct LibraryGridView: View {
    var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(model.assets, id: \.id.rawValue) { asset in
                    Button {
                        model.select(asset.id)
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.gray.opacity(0.35))
                                .aspectRatio(3.0 / 2.0, contentMode: .fit)
                            Text(asset.metadata.rating > 0 ? String(repeating: "★", count: asset.metadata.rating) : " ")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .padding(6)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .navigationTitle("All Photographs")
    }
}
```

Create `Sources/TeststripApp/ActivityView.swift`:

```swift
import SwiftUI

struct ActivityView: View {
    var body: some View {
        Text("No active work")
            .foregroundStyle(.secondary)
            .padding()
    }
}
```

Create `Sources/TeststripApp/InspectorView.swift`:

```swift
import SwiftUI

struct InspectorView: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let asset = model.selectedAsset {
                Text(asset.originalURL.lastPathComponent)
                    .font(.headline)
                Text("Availability: \(asset.availability.rawValue)")
                Text("Rating: \(asset.metadata.rating)")
                Text("Keywords: \(asset.metadata.keywords.joined(separator: ", "))")
            } else {
                Text("No selection")
            }
            Spacer()
            ActivityView()
        }
        .padding()
        .frame(minWidth: 260)
    }
}
```

- [ ] **Step 4: Run tests and build app**

Run:

```bash
swift test --filter AppModelTests
swift build --product TeststripApp
```

Expected: both commands PASS.

- [ ] **Step 5: Commit**

Run:

```bash
git status --short
git add Sources/TeststripApp Tests/TeststripAppTests/AppModelTests.swift
git commit -m "Add native app shell" -m "Create the first SwiftUI Studio-style shell with Library and Work sidebar sections, a grid surface, and an inspector. Keep behavior in AppModel so the initial UI can be tested without screenshot assertions."
```

## Task 13: Performance Harness For Catalog Scale

**Files:**
- Modify: `Sources/TeststripBench/main.swift`

- [ ] **Step 1: Add benchmark executable**

Replace `Sources/TeststripBench/main.swift`:

```swift
import Foundation
import TeststripCore

let arguments = CommandLine.arguments
let count = Int(arguments.dropFirst().first ?? "10000") ?? 10000
let root = FileManager.default.temporaryDirectory.appendingPathComponent("teststrip-bench", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
try database.migrate()
let repository = CatalogRepository(database: database)

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
    try repository.upsert(asset)
}

let elapsed = Date().timeIntervalSince(start)
print("inserted \(count) assets in \(String(format: "%.3f", elapsed))s")
```

- [ ] **Step 2: Run benchmark smoke command**

Run:

```bash
swift run TeststripBench 1000
```

Expected: command prints `inserted 1000 assets in ...s` and exits 0.

- [ ] **Step 3: Commit**

Run:

```bash
git status --short
git add Sources/TeststripBench/main.swift
git commit -m "Add catalog benchmark harness" -m "Add a simple executable for inserting synthetic catalog rows so future work can measure catalog throughput and scale changes against explicit large-catalog targets."
```

## Task 14: Full Verification Checkpoint

**Files:**
- Modify only if verification exposes a real bug in files touched by earlier tasks.

- [ ] **Step 1: Run complete test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Build all products**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Run app and worker smoke commands**

Run:

```bash
swift run TeststripWorker <<< '{"pause":{}}'
swift run TeststripBench 1000
```

Expected:

- `TeststripWorker` exits 0 after accepting or reporting the pause command.
- `TeststripBench` prints `inserted 1000 assets in ...s`.

- [ ] **Step 4: Inspect git state**

Run:

```bash
git status --short
```

Expected: no uncommitted tracked source changes. Generated build artifacts should remain outside git.

If verification required fixes, commit them with a message that names the failed command and the root cause.

## Implementation Notes

- Keep commits small and task-scoped. Do not use `git add -A`; run `git status --short` and add only files from the current task.
- Do not skip failing-test steps. If a test unexpectedly passes before implementation, inspect why the behavior already exists and adjust the test to cover the missing contract.
- Do not add broad UI polish during the foundation plan. The shell only needs to prove the layout hypothesis and connect to testable state.
- Do not wire direct full-resolution NAS reads into normal grid browsing. The preview scheduler and cache boundary exist to prevent that.
- Keep machine-generated evaluations separate from user metadata and XMP until explicitly accepted by a user workflow.
