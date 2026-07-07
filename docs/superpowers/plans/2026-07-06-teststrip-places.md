# Teststrip Places Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship FULL Places per design 5b (`design-concept/Teststrip.dc.html` option `5b`): a MapKit browse route showing every geotagged frame as cluster bubbles sized by photo count, a TOP LOCATIONS sidebar of reverse-geocoded place names, and a "Geotagged on import" coverage badge. GPS coordinates are extracted at import into technical metadata; a worker-side, rate-limited, resumable reverse-geocoding pipeline turns coordinates into shared place-name cache entries; selecting a cluster or a top location drills the grid into that region via an indexed geo-bounds predicate. Offline behavior is graceful (coordinates-only, no place names). Existing catalogs backfill through an explicit bounded re-read job.

**Architecture:** Coordinates ride the existing `technical_metadata_json` JSON blob (`AssetTechnicalMetadata` gains `latitude`/`longitude`/`altitude` — no column migration, exactly like the aperture/shutter/focal EXIF fields shipped before). `ImageIODecodeProvider.metadata(from:)` reads `kCGImagePropertyGPSDictionary`. Map rendering never loads all assets: cluster counts come from bounded SQL aggregation (`CatalogRepository.placeClusters(bounds:cellSize:)`, modeled on `timelineDays()`), and a new indexed `SetQuery.Predicate.withinGeoBounds` restricts the region. Reverse geocoding is a persistent catalog queue + shared place-name cache (both keyed by rounded coordinate) modeled byte-for-byte on `preview_generation_queue`; the drain is a new throttled `WorkerCommand.reverseGeocodeBatch`, dispatched by `AppModel` as slots free (mirroring `enqueuePendingPreviewGeneration`) and surfaced as a "Geocoding N of M" background-work Activity row. The map route reuses the timeline browse pattern: a new `LibraryViewMode.map` (the dead enum case, now wired), a `SidebarRowTarget.places` sidebar row, and a `PlacesPresentation` presentation-model tested without snapshots.

**Tech Stack:** Swift 6 / macOS 14, SwiftPM, XCTest, SwiftUI presentation-model pattern (no snapshot tests), SQLite via existing `CatalogRepository`. New stock frameworks only: `MapKit` (map surface) and `CoreLocation` (`CLGeocoder`, `CLLocation`, `CLPlacemark`) — both first-party, auto-linked by `import`, no new SwiftPM dependency and no `Package.swift` change. The app already declares `com.apple.security.network.client` and the worker inherits the sandbox (`com.apple.security.inherit`), so the worker can reach the network for geocoding.

## Global Constraints

- **Catalog-first, originals never modified.** No task in this plan writes to originals or sidecars. Coordinates are *read* from originals at import; reverse-geocoded place names live only in the catalog cache. The only task that re-opens originals (Task 10 backfill) opens them read-only.
- **Machine actions reviewable and undoable.** Reverse geocoding writes to a dedicated `place_cache` table, never to `AssetMetadata`/flags/ratings/keywords. Place names are display-only derived data; clearing the cache and re-running is always safe. No geocoded value ever becomes a user-visible edit or an XMP write.
- **No new hard external dependency.** MapKit + CoreLocation are stock. If any task finds itself reaching for a third-party map tile source, offline-geocoding dataset, or geocoding SDK, STOP and raise it as a decision (see Decisions).
- **Bounded work only.** Every catalog read that feeds the map is a `COUNT`/`GROUP BY` aggregation or a `LIMIT`-bounded page. No task may load all assets to render the map or the sidebar. The reverse-geocode drain processes a bounded batch and honors a per-minute budget.
- **Provisional/graceful offline.** With no network, the map still renders (bubbles from coordinates); the geocode queue simply does not drain and TOP LOCATIONS shows only already-cached names. No task blocks the UI on a network call.
- No SwiftUI snapshot tests. UI behavior lands as presentation-model members with XCTest model tests (repo pattern in `Tests/TeststripAppTests`).
- Copy separators are the repo's `·` middle dots and `—` em dashes.
- Run all commands from the repo root `/Users/jesse/git/projects/teststrip`.
- **Anchors:** all line numbers are against `main` at HEAD `4fb94b0` ("Record autopilot and reject-relocation plans"). The branch advances fast; **re-locate every edit by symbol name, not line number.** Wave-1 features (folder sidebar, person filter, session restore, loupe zoom, export presets) are merging tonight — rebase before starting, and see the per-task Wave-1 notes.
- **Migration version numbers are orchestrator-assigned — do NOT use 15 or 16.** Three other streams are adding catalog migrations the same night (duplicate-detection, autopilot, reject-relocation — reject-relocation already claims **v15**, verified in its plan). This plan reserves **v18** for the coordinate expression index (Task 3) and **v19** for the `place_cache` + `geocode_queue` tables (Task 5). These numbers are provisional and **MUST be re-verified against `main` at implementation time** — take the next free integers if 18/19 are already claimed, or fold both Places migrations into a single reserved version (the index and the two tables can land together). The current `CatalogMigrations.version` on `main` when this plan was authored is **14** (verified).

## File Map

- Modify: `Sources/TeststripCore/Domain/Metadata.swift` — `latitude`/`longitude`/`altitude` on `AssetTechnicalMetadata` (Task 1).
- Modify: `Sources/TeststripCore/Decode/DecodeProvider.swift` — same three fields on `DecodeMetadata` + pass-through in `assetTechnicalMetadata` (Task 1).
- Modify: `Sources/TeststripCore/Decode/ImageIODecodeProvider.swift` — read `kCGImagePropertyGPSDictionary` (Task 2).
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` — expression index (Task 3), `place_cache` + `geocode_queue` tables (Task 5); version bump.
- Modify: `Sources/TeststripCore/Search/SetQuery.swift` — `GeoBounds` type + `.withinGeoBounds` predicate (Task 3).
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` — `.withinGeoBounds` compilation (Task 3), `placeClusters`/`geotaggedCoverage` (Task 4), place-cache + geocode-queue ops (Task 5), `topLocations` (Task 8).
- Create: `Sources/TeststripCore/Catalog/CatalogPlaceCluster.swift`, `Sources/TeststripCore/Catalog/CatalogTopLocation.swift`, `Sources/TeststripCore/Catalog/GeocodeQueueItem.swift`, `Sources/TeststripCore/Catalog/CatalogPlaceName.swift` (Tasks 4/5/8).
- Modify: `Sources/TeststripCore/Worker/WorkerCommand.swift` + `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift` — `.reverseGeocodeBatch` (Task 6).
- Create: `Sources/TeststripCore/Evaluation/ReverseGeocoder.swift` (protocol + `CLGeocoderReverseGeocoder` + throttle) (Task 6).
- Modify: `Sources/TeststripCore/Work/WorkSession.swift` — `WorkSessionKind.geocoding` (Task 7).
- Modify: `Sources/TeststripApp/AppModel.swift` — `geoBoundsFilter`, `.withinGeoBounds` plumbing, `LibraryViewMode.map`, `SidebarRowTarget.places` handling, Places sidebar row, geocode dispatch, place data refresh (Tasks 3/7/9), backfill dispatch (Task 10).
- Create: `Sources/TeststripApp/PlacesPresentation.swift` (Task 9).
- Modify: `Sources/TeststripApp/LibraryGridView.swift` — Places workspace view + topbar mode item (Task 9).
- Modify: `Sources/TeststripCore/Ingest/IngestService.swift` — backfill re-read helper (Task 10).
- Tests: `Tests/TeststripCoreTests/DecodeRegistryTests.swift`, `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`, `Tests/TeststripCoreTests/ReverseGeocoderTests.swift` (new), `Tests/TeststripWorkerTests/WorkerCommandExecutorTests.swift`, `Tests/TeststripAppTests/AppModelTests.swift`, `Tests/TeststripAppTests/PlacesPresentationTests.swift` (new).

---

### Task 1: GPS coordinate fields on `DecodeMetadata` and `AssetTechnicalMetadata` (no migration)

Add `latitude`, `longitude`, `altitude` (`Double?`) to both structs and pass them through `DecodeMetadata.assetTechnicalMetadata`. Because `technical_metadata_json` is a JSON `TEXT` blob decoded through `Codable` (verified: the aperture/shutter/focal fields were added the same way and `CatalogDatabaseTests.testPersistsApertureShutterSpeedAndFocalLengthThroughExistingTechnicalMetadataStorage` passes with no migration), new optional fields decode as `nil` on existing rows and round-trip with no schema change.

**Estimated scope:** ~110 LOC including tests.

**Files:**
- Modify: `Sources/TeststripCore/Domain/Metadata.swift` (`struct AssetTechnicalMetadata`)
- Modify: `Sources/TeststripCore/Decode/DecodeProvider.swift` (`struct DecodeMetadata`)
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces (later tasks rely on these exact members):
  - `AssetTechnicalMetadata.latitude: Double?`, `.longitude: Double?`, `.altitude: Double?` (init params default `nil`, appended AFTER `focalLength` and BEFORE `capturedAt` to keep the existing memberwise-init call sites in `DecodeMetadata.assetTechnicalMetadata` readable — but keep `provenance` last).
  - `DecodeMetadata.latitude/longitude/altitude: Double?` with the same defaults.
  - JSON keys (via the `.sortedKeys` encoder): `$.latitude`, `$.longitude`, `$.altitude`.

- [ ] **Step 1: Write the failing test**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`:

```swift
    func testPersistsGPSCoordinatesThroughExistingTechnicalMetadataStorage() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-technical-metadata-gps")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let technicalMetadata = AssetTechnicalMetadata(
            pixelWidth: 6000,
            pixelHeight: 4000,
            latitude: 37.8199,
            longitude: -122.4783,
            altitude: 67.5,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )
        let asset = Asset.testAsset(path: "/Volumes/NAS/Job/frame.cr2", rating: 3, technicalMetadata: technicalMetadata)

        try repository.upsert(asset)

        let fetched = try repository.asset(id: asset.id)
        XCTAssertEqual(fetched.technicalMetadata?.latitude, 37.8199)
        XCTAssertEqual(fetched.technicalMetadata?.longitude, -122.4783)
        XCTAssertEqual(fetched.technicalMetadata?.altitude, 67.5)
        XCTAssertEqual(fetched.technicalMetadata, technicalMetadata)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter "CatalogDatabaseTests.testPersistsGPSCoordinatesThroughExistingTechnicalMetadataStorage"`
Expected: compile FAILURE — `argument 'latitude' must precede argument 'provenance'` / `extra argument 'latitude'` (the memberwise init has no `latitude`).

- [ ] **Step 3: Add the fields to both structs**

In `Sources/TeststripCore/Domain/Metadata.swift`, add to `struct AssetTechnicalMetadata` after `public var focalLength: Double?` (and before `capturedAt`):

```swift
    public var latitude: Double?
    public var longitude: Double?
    public var altitude: Double?
```

Add the three params to `init` after `focalLength` (defaulting `nil`), and assign them. Keep `provenance` the last parameter.

In `Sources/TeststripCore/Decode/DecodeProvider.swift`, add the same three properties + init params to `struct DecodeMetadata`, and extend the `assetTechnicalMetadata` computed property to forward them:

```swift
            focalLength: focalLength,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            capturedAt: capturedAt,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter "CatalogDatabaseTests.testPersistsGPSCoordinatesThroughExistingTechnicalMetadataStorage"`
Expected: PASS.

- [ ] **Step 5: Confirm nothing else broke**

Run: `swift build`
Expected: build succeeds (no migration touched; existing `DecodeMetadata`/`AssetTechnicalMetadata` construction sites still compile because the new params default `nil`).

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Domain/Metadata.swift Sources/TeststripCore/Decode/DecodeProvider.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: carry GPS coordinates through technical metadata"
```

---

### Task 2: `ImageIODecodeProvider` reads `kCGImagePropertyGPSDictionary`

Extract latitude/longitude/altitude from the GPS dictionary at import. ImageIO stores latitude/longitude as unsigned magnitudes with a hemisphere ref (`"N"`/`"S"`, `"E"`/`"W"`) that supplies the sign, and altitude as a magnitude with `kCGImagePropertyGPSAltitudeRef` (`0` above sea level, `1` below). The existing static `ImageIODecodeProvider.metadata(from:provenance:filename:)` (verified signature: `static func metadata(from properties: [CFString: Any], provenance: ProviderProvenance, filename: String) throws -> DecodeMetadata`) is the test seam — no image fixture needed.

**Estimated scope:** ~130 LOC including tests.

**Files:**
- Modify: `Sources/TeststripCore/Decode/ImageIODecodeProvider.swift` (`metadata(from:)` + private GPS helpers)
- Test: `Tests/TeststripCoreTests/DecodeRegistryTests.swift`

**Interfaces:**
- Consumes: `properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]` with keys `kCGImagePropertyGPSLatitude`/`kCGImagePropertyGPSLatitudeRef`/`kCGImagePropertyGPSLongitude`/`kCGImagePropertyGPSLongitudeRef`/`kCGImagePropertyGPSAltitude`/`kCGImagePropertyGPSAltitudeRef`.
- Produces: populated `DecodeMetadata.latitude/longitude/altitude` (from Task 1). No new public API.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/DecodeRegistryTests.swift`:

```swift
    func testImageIOTechnicalMetadataReadsGPSCoordinatesWithHemisphereRefs() throws {
        let provenance = ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")

        let metadata = try ImageIODecodeProvider.metadata(from: [
            kCGImagePropertyPixelWidth: 6000,
            kCGImagePropertyPixelHeight: 4000,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 37.8199,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 122.4783,
                kCGImagePropertyGPSLongitudeRef: "W",
                kCGImagePropertyGPSAltitude: 67.5,
                kCGImagePropertyGPSAltitudeRef: 0
            ]
        ], provenance: provenance, filename: "photo.cr3")

        XCTAssertEqual(metadata.latitude, 37.8199)
        XCTAssertEqual(metadata.longitude, -122.4783)
        XCTAssertEqual(metadata.altitude, 67.5)
    }

    func testImageIOTechnicalMetadataAppliesSouthAndBelowSeaLevelSigns() throws {
        let provenance = ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")

        let metadata = try ImageIODecodeProvider.metadata(from: [
            kCGImagePropertyPixelWidth: 6000,
            kCGImagePropertyPixelHeight: 4000,
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 33.8688,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 151.2093,
                kCGImagePropertyGPSLongitudeRef: "E",
                kCGImagePropertyGPSAltitude: 12.0,
                kCGImagePropertyGPSAltitudeRef: 1
            ]
        ], provenance: provenance, filename: "photo.cr3")

        XCTAssertEqual(metadata.latitude, -33.8688)
        XCTAssertEqual(metadata.longitude, 151.2093)
        XCTAssertEqual(metadata.altitude, -12.0)
    }

    func testImageIOTechnicalMetadataLeavesCoordinatesNilWhenGPSDictionaryAbsent() throws {
        let provenance = ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")

        let metadata = try ImageIODecodeProvider.metadata(from: [
            kCGImagePropertyPixelWidth: 6000,
            kCGImagePropertyPixelHeight: 4000
        ], provenance: provenance, filename: "photo.cr3")

        XCTAssertNil(metadata.latitude)
        XCTAssertNil(metadata.longitude)
        XCTAssertNil(metadata.altitude)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "DecodeRegistryTests.testImageIOTechnicalMetadataReadsGPSCoordinatesWithHemisphereRefs|DecodeRegistryTests.testImageIOTechnicalMetadataAppliesSouthAndBelowSeaLevelSigns"`
Expected: FAILURE — `metadata.latitude` is `nil` (`XCTAssertEqual(nil, 37.8199)`), because `metadata(from:)` does not read GPS yet.

- [ ] **Step 3: Read the GPS dictionary in `metadata(from:)`**

In `Sources/TeststripCore/Decode/ImageIODecodeProvider.swift`, inside the static `metadata(from:provenance:filename:)`, after the `exif` binding add:

```swift
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let coordinate = signedCoordinate(from: gps)
```

Forward the three fields in the returned `DecodeMetadata(...)` (after `focalLength:`, before `capturedAt:`):

```swift
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            altitude: coordinate.altitude,
```

Add the private helpers (reuse the existing `doubleValue(from:)` and `stringValue(_:)` helpers already in the file):

```swift
    private static func signedCoordinate(
        from gps: [CFString: Any]
    ) -> (latitude: Double?, longitude: Double?, altitude: Double?) {
        let latitude = doubleValue(from: gps[kCGImagePropertyGPSLatitude]).map { magnitude in
            stringValue(gps[kCGImagePropertyGPSLatitudeRef])?.uppercased() == "S" ? -magnitude : magnitude
        }
        let longitude = doubleValue(from: gps[kCGImagePropertyGPSLongitude]).map { magnitude in
            stringValue(gps[kCGImagePropertyGPSLongitudeRef])?.uppercased() == "W" ? -magnitude : magnitude
        }
        let altitude = doubleValue(from: gps[kCGImagePropertyGPSAltitude]).map { magnitude in
            intValue(gps[kCGImagePropertyGPSAltitudeRef]) == 1 ? -magnitude : magnitude
        }
        // A 0,0 fix ("Null Island") is the canonical camera "no fix" sentinel; treat
        // it as absent so it never plots off the Gulf of Guinea.
        if latitude == 0, longitude == 0 {
            return (nil, nil, altitude)
        }
        return (latitude, longitude, altitude)
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        return value as? Int
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "DecodeRegistryTests"`
Expected: PASS (all existing decode tests + the 3 new GPS tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Decode/ImageIODecodeProvider.swift Tests/TeststripCoreTests/DecodeRegistryTests.swift
git commit -m "feat: extract GPS coordinates from EXIF at import"
```

---

### Task 3: Indexed geo-bounds `SetQuery` predicate

Add a `GeoBounds` value and `SetQuery.Predicate.withinGeoBounds(GeoBounds)`, compiled to a `CAST(json_extract(...) AS REAL) BETWEEN ? AND ?` clause on both coordinate expressions, backed by a SQLite **expression index** on the identical `CAST(json_extract(...) AS REAL)` expressions so region filtering stays indexed at six-figure scale. This is a safe additive migration (two `CREATE INDEX IF NOT EXISTS` statements + version bump); no `ALTER TABLE`, no data rewrite.

**Estimated scope:** ~200 LOC including tests.

**Files:**
- Modify: `Sources/TeststripCore/Search/SetQuery.swift`
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (`compile(_:)`)
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (index + version)
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces:
  - `struct GeoBounds: Codable, Equatable, Sendable { public var minLatitude, maxLatitude, minLongitude, maxLongitude: Double; public init(...) }`
  - `SetQuery.Predicate.withinGeoBounds(GeoBounds)`
  - Reuses the existing `compile(_ query:) -> (whereSQL:, bindings:)` switch and the `assetCount(matching:)` / paged fetch already used by `reload()`.
- Constant: `CatalogRepository` gets a single source of truth for the expression strings (so index and predicate stay byte-identical — the planner only uses the index when they match exactly):
  - `static let latitudeExpressionSQL = "CAST(json_extract(technical_metadata_json, '$.latitude') AS REAL)"`
  - `static let longitudeExpressionSQL = "CAST(json_extract(technical_metadata_json, '$.longitude') AS REAL)"`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift` (helper to build an asset at a coordinate reuses `Asset.testAsset` + `AssetTechnicalMetadata` from Task 1):

```swift
    func testWithinGeoBoundsPredicateFiltersByCoordinate() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-geo-bounds")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        func asset(_ name: String, latitude: Double, longitude: Double) -> Asset {
            Asset.testAsset(
                path: "/Volumes/NAS/\(name).cr2",
                rating: 0,
                technicalMetadata: AssetTechnicalMetadata(
                    pixelWidth: 100, pixelHeight: 100,
                    latitude: latitude, longitude: longitude,
                    provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
                )
            )
        }
        try repository.upsert(asset("sf", latitude: 37.77, longitude: -122.42))
        try repository.upsert(asset("oakland", latitude: 37.80, longitude: -122.27))
        try repository.upsert(asset("sydney", latitude: -33.87, longitude: 151.21))
        try repository.upsert(Asset.testAsset(path: "/Volumes/NAS/no-gps.cr2", rating: 0))

        let bayArea = GeoBounds(minLatitude: 37.5, maxLatitude: 38.0, minLongitude: -122.6, maxLongitude: -122.2)
        let count = try repository.assetCount(matching: SetQuery(predicates: [.withinGeoBounds(bayArea)]))

        XCTAssertEqual(count, 2)
    }

    func testGeoBoundsQueryUsesCoordinateExpressionIndex() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-geo-index")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()

        let plan = try database.rows(
            """
            EXPLAIN QUERY PLAN
            SELECT COUNT(*) FROM assets
            WHERE \(CatalogRepository.latitudeExpressionSQL) BETWEEN -1 AND 1
              AND \(CatalogRepository.longitudeExpressionSQL) BETWEEN -1 AND 1
            """
        )
        let detail = plan.compactMap { $0["detail"] }.joined(separator: " ")
        XCTAssertTrue(detail.contains("idx_assets_gps"), "expected the geo expression index, got: \(detail)")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "CatalogDatabaseTests.testWithinGeoBoundsPredicateFiltersByCoordinate|CatalogDatabaseTests.testGeoBoundsQueryUsesCoordinateExpressionIndex"`
Expected: compile FAILURE — `type 'SetQuery.Predicate' has no case 'withinGeoBounds'` and `type 'CatalogRepository' has no member 'latitudeExpressionSQL'`.

- [ ] **Step 3: Add `GeoBounds` and the predicate case**

In `Sources/TeststripCore/Search/SetQuery.swift`, add above `struct SetQuery`:

```swift
public struct GeoBounds: Codable, Equatable, Sendable {
    public var minLatitude: Double
    public var maxLatitude: Double
    public var minLongitude: Double
    public var maxLongitude: Double

    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }
}
```

Add `case withinGeoBounds(GeoBounds)` to `enum Predicate`.

- [ ] **Step 4: Compile the predicate and add the shared expression constants**

In `Sources/TeststripCore/Catalog/CatalogRepository.swift`, add the constants near the top of the class:

```swift
    static let latitudeExpressionSQL = "CAST(json_extract(technical_metadata_json, '$.latitude') AS REAL)"
    static let longitudeExpressionSQL = "CAST(json_extract(technical_metadata_json, '$.longitude') AS REAL)"
```

In the `compile(_ query:)` predicate switch, add a case alongside `.capturedBefore`:

```swift
            case .withinGeoBounds(let bounds):
                clauses.append(
                    """
                    (json_valid(technical_metadata_json)
                     AND \(Self.latitudeExpressionSQL) BETWEEN ? AND ?
                     AND \(Self.longitudeExpressionSQL) BETWEEN ? AND ?)
                    """
                )
                bindings.append(contentsOf: [
                    "\(bounds.minLatitude)", "\(bounds.maxLatitude)",
                    "\(bounds.minLongitude)", "\(bounds.maxLongitude)"
                ])
```

(Antimeridian crossing — `minLongitude > maxLongitude` — is deferred; see Decisions. The map never emits crossing bounds because a single visible region on `MKMapView` clamps to `[-180, 180]` per edge and the drill-down uses the cluster's own cell rectangle.)

- [ ] **Step 5: Add the expression index and bump the schema version**

In `Sources/TeststripCore/Catalog/CatalogMigrations.swift`, bump `static let version` to the **orchestrator-reserved `18`** (re-verify it is still free on `main` first — see the migration-coordination constraint above; do NOT use 15/16), and append to the `statements` array (the expression MUST be byte-identical to `latitude/longitudeExpressionSQL`):

```swift
        """
        CREATE INDEX IF NOT EXISTS idx_assets_gps ON assets(
            CAST(json_extract(technical_metadata_json, '$.latitude') AS REAL),
            CAST(json_extract(technical_metadata_json, '$.longitude') AS REAL)
        )
        """
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `swift test --filter "CatalogDatabaseTests"`
Expected: PASS. If `testGeoBoundsQueryUsesCoordinateExpressionIndex` fails with a `SCAN` in the plan, the index expression and predicate expression are not byte-identical — reconcile them against the shared constants before proceeding (do not weaken the assertion).

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripCore/Search/SetQuery.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Sources/TeststripCore/Catalog/CatalogMigrations.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: add indexed geo-bounds set-query predicate"
```

---

### Task 4: Bounded place-cluster aggregation and coverage count

Add `CatalogRepository.placeClusters(bounds:cellSize:)` — SQL grid clustering that buckets coordinates by a cell size and returns one `CatalogPlaceCluster` per non-empty cell (count + weighted centroid), and `geotaggedCoverage()` returning `(geotagged:, total:)`. This is the scalable substitute for `MKClusterAnnotation` (which requires materializing every annotation — untenable at 100k+; see Decisions). Modeled directly on `timelineDays()`: `GROUP BY` over a bounded set, never loading assets.

**Estimated scope:** ~230 LOC including tests.

**Files:**
- Create: `Sources/TeststripCore/Catalog/CatalogPlaceCluster.swift`
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift`
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces:
  - `struct CatalogPlaceCluster: Equatable, Sendable { public var latitude, longitude: Double; public var assetCount: Int; public init(...) }` (lat/lon = mean of the cell's coordinates, so the bubble sits on the actual cloud, not the cell corner).
  - `struct CatalogGeotaggedCoverage: Equatable, Sendable { public var geotaggedCount, totalCount: Int; public init(...) }`
  - `func placeClusters(bounds: GeoBounds?, cellSize: Double) throws -> [CatalogPlaceCluster]` — `bounds == nil` aggregates the whole world (initial fit); a non-nil bounds restricts to the visible region (uses `idx_assets_gps`). `cellSize` is degrees per grid cell (caller derives it from zoom; see Task 9).
  - `func geotaggedCoverage() throws -> CatalogGeotaggedCoverage`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`:

```swift
    func testPlaceClustersBucketsCoordinatesByCell() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-place-clusters")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        func upsert(_ name: String, _ lat: Double, _ lon: Double) throws {
            try repository.upsert(Asset.testAsset(
                path: "/Volumes/NAS/\(name).cr2", rating: 0,
                technicalMetadata: AssetTechnicalMetadata(
                    pixelWidth: 1, pixelHeight: 1, latitude: lat, longitude: lon,
                    provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
                )
            ))
        }
        // Two frames in one 10-degree cell, one far away.
        try upsert("a", 37.1, -122.1)
        try upsert("b", 37.9, -122.9)
        try upsert("c", -33.8, 151.2)
        try repository.upsert(Asset.testAsset(path: "/Volumes/NAS/no-gps.cr2", rating: 0))

        let clusters = try repository.placeClusters(bounds: nil, cellSize: 10.0)
            .sorted { $0.assetCount > $1.assetCount }

        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters[0].assetCount, 2)
        XCTAssertEqual(clusters[0].latitude, 37.5, accuracy: 0.001)   // mean of 37.1, 37.9
        XCTAssertEqual(clusters[0].longitude, -122.5, accuracy: 0.001)
        XCTAssertEqual(clusters[1].assetCount, 1)
    }

    func testGeotaggedCoverageCountsCoordinateBearingAssets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-coverage")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        try repository.upsert(Asset.testAsset(
            path: "/Volumes/NAS/geo.cr2", rating: 0,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 1, pixelHeight: 1, latitude: 1.0, longitude: 2.0,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        ))
        try repository.upsert(Asset.testAsset(path: "/Volumes/NAS/plain.cr2", rating: 0))

        let coverage = try repository.geotaggedCoverage()
        XCTAssertEqual(coverage.geotaggedCount, 1)
        XCTAssertEqual(coverage.totalCount, 2)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "CatalogDatabaseTests.testPlaceClustersBucketsCoordinatesByCell|CatalogDatabaseTests.testGeotaggedCoverageCountsCoordinateBearingAssets"`
Expected: compile FAILURE — no `placeClusters`/`geotaggedCoverage`/`CatalogPlaceCluster`.

- [ ] **Step 3: Create `CatalogPlaceCluster.swift`**

`Sources/TeststripCore/Catalog/CatalogPlaceCluster.swift` — the two structs above (`CatalogPlaceCluster`, `CatalogGeotaggedCoverage`).

- [ ] **Step 4: Implement the aggregations**

In `CatalogRepository.swift`, next to `timelineDays()`. `placeClusters` filters to rows with numeric coordinates, applies the optional bounds via the shared expression constants (so it uses `idx_assets_gps`), buckets by `CAST(FLOOR(coord / cellSize) AS INTEGER)`, and returns `AVG(coord)` per bucket:

```swift
    public func placeClusters(bounds: GeoBounds?, cellSize: Double) throws -> [CatalogPlaceCluster] {
        precondition(cellSize > 0, "cellSize must be positive")
        var boundsClause = ""
        var bindings: [String] = []
        if let bounds {
            boundsClause = """
                AND \(Self.latitudeExpressionSQL) BETWEEN ? AND ?
                AND \(Self.longitudeExpressionSQL) BETWEEN ? AND ?
            """
            bindings = [
                "\(bounds.minLatitude)", "\(bounds.maxLatitude)",
                "\(bounds.minLongitude)", "\(bounds.maxLongitude)"
            ]
        }
        let cell = "\(cellSize)"
        let rows = try database.rows(
            """
            WITH located AS (
                SELECT \(Self.latitudeExpressionSQL) AS lat,
                       \(Self.longitudeExpressionSQL) AS lon
                FROM assets
                WHERE json_valid(technical_metadata_json)
                  AND json_type(technical_metadata_json, '$.latitude') IN ('integer', 'real')
                  AND json_type(technical_metadata_json, '$.longitude') IN ('integer', 'real')
                  \(boundsClause)
            )
            SELECT
                CAST(FLOOR(lat / \(cell)) AS INTEGER) AS lat_cell,
                CAST(FLOOR(lon / \(cell)) AS INTEGER) AS lon_cell,
                AVG(lat) AS lat_mean,
                AVG(lon) AS lon_mean,
                COUNT(*) AS asset_count
            FROM located
            GROUP BY lat_cell, lon_cell
            """,
            bindings: bindings
        )
        return try rows.map { row in
            guard let latMean = row["lat_mean"].flatMap(Double.init),
                  let lonMean = row["lon_mean"].flatMap(Double.init),
                  let count = row["asset_count"].flatMap(Int.init) else {
                throw CatalogError.sqlite("place cluster row is missing required columns")
            }
            return CatalogPlaceCluster(latitude: latMean, longitude: lonMean, assetCount: count)
        }
    }

    public func geotaggedCoverage() throws -> CatalogGeotaggedCoverage {
        let rows = try database.rows(
            """
            SELECT
                COUNT(*) AS total,
                SUM(CASE
                    WHEN json_valid(technical_metadata_json)
                     AND json_type(technical_metadata_json, '$.latitude') IN ('integer', 'real')
                    THEN 1 ELSE 0 END) AS geotagged
            FROM assets
            """
        )
        guard let row = rows.first,
              let total = row["total"].flatMap(Int.init) else {
            throw CatalogError.sqlite("coverage row is missing required columns")
        }
        let geotagged = row["geotagged"].flatMap(Int.init) ?? 0
        return CatalogGeotaggedCoverage(geotaggedCount: geotagged, totalCount: total)
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter "CatalogDatabaseTests.testPlaceClustersBucketsCoordinatesByCell|CatalogDatabaseTests.testGeotaggedCoverageCountsCoordinateBearingAssets"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogPlaceCluster.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: aggregate place clusters and geotagged coverage in SQL"
```

---

### Task 5: `place_cache` + `geocode_queue` schema and repository operations

Add the persistent, resumable reverse-geocoding infrastructure — a shared place-name cache keyed by a rounded-coordinate key (nearby photos share one lookup) and a work queue modeled byte-for-byte on `preview_generation_queue` (attempt counts, `last_error`, `last_attempted_at`, bounded fetch). No network here; this is pure catalog plumbing so Task 6 (worker drain) and Task 7 (dispatch) have a tested store to build on.

**Estimated scope:** ~280 LOC including tests.

**Files:**
- Create: `Sources/TeststripCore/Catalog/GeocodeQueueItem.swift`, `Sources/TeststripCore/Catalog/CatalogPlaceName.swift`
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (two tables + version bump to orchestrator-reserved `19`)
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift`
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces:
  - `enum GeocodeCoordinateKey` with `static func key(latitude:longitude:) -> String` and `static let roundingDecimals = 2` (2 dp ≈ 1.1 km cache cell — a tunable; see Decisions). Format: `String(format: "%.2f,%.2f", roundedLat, roundedLon)`.
  - `struct GeocodeQueueItem: Equatable, Sendable { public var coordinateKey: String; public var latitude, longitude: Double }`
  - `struct CatalogPlaceName: Equatable, Sendable { public var coordinateKey: String; public var locality, administrativeArea, country, displayName: String? }`
  - `func enqueueMissingGeocodeCoordinates(limit: Int) throws -> Int` — scans DISTINCT rounded coordinates on geotagged assets that have neither a `place_cache` row nor a `geocode_queue` row, inserts up to `limit` into `geocode_queue`, returns the count enqueued.
  - `func pendingGeocodeItems(limit: Int, maximumAttemptCount: Int) throws -> [GeocodeQueueItem]`
  - `func recordGeocodeFailure(coordinateKey: String, errorMessage: String) throws` (increments attempt_count, mirrors `recordPreviewGenerationFailure`)
  - `func recordPlaceName(_ placeName: CatalogPlaceName) throws` — upserts `place_cache` AND deletes the matching `geocode_queue` row in one transaction (a resolved coordinate leaves the queue, exactly like `markPreviewGenerated`).
  - `func placeName(coordinateKey: String) throws -> CatalogPlaceName?`
  - `func geocodeQueueDepth() throws -> Int` (for the "N of M" Activity total; see Task 7).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`:

```swift
    func testEnqueueMissingGeocodeCoordinatesDeduplicatesByRoundedKey() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-geocode-enqueue")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        func upsert(_ name: String, _ lat: Double, _ lon: Double) throws {
            try repository.upsert(Asset.testAsset(
                path: "/Volumes/NAS/\(name).cr2", rating: 0,
                technicalMetadata: AssetTechnicalMetadata(
                    pixelWidth: 1, pixelHeight: 1, latitude: lat, longitude: lon,
                    provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
                )
            ))
        }
        // Two frames round to the same 2dp key; a third is distinct.
        try upsert("a", 37.8199, -122.4783)
        try upsert("b", 37.8203, -122.4791)
        try upsert("c", 48.8584, 2.2945)

        let enqueued = try repository.enqueueMissingGeocodeCoordinates(limit: 100)
        XCTAssertEqual(enqueued, 2)

        // Re-running enqueues nothing new (both keys are already queued).
        XCTAssertEqual(try repository.enqueueMissingGeocodeCoordinates(limit: 100), 0)
        XCTAssertEqual(try repository.geocodeQueueDepth(), 2)
    }

    func testRecordPlaceNameCachesAndClearsQueue() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-geocode-record")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        try repository.upsert(Asset.testAsset(
            path: "/Volumes/NAS/eiffel.cr2", rating: 0,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 1, pixelHeight: 1, latitude: 48.8584, longitude: 2.2945,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        ))
        _ = try repository.enqueueMissingGeocodeCoordinates(limit: 10)
        let key = GeocodeCoordinateKey.key(latitude: 48.8584, longitude: 2.2945)

        try repository.recordPlaceName(CatalogPlaceName(
            coordinateKey: key, locality: "Paris", administrativeArea: "Île-de-France",
            country: "France", displayName: "Paris · France"
        ))

        XCTAssertEqual(try repository.placeName(coordinateKey: key)?.displayName, "Paris · France")
        XCTAssertEqual(try repository.geocodeQueueDepth(), 0)
        // An already-cached coordinate is never re-enqueued.
        XCTAssertEqual(try repository.enqueueMissingGeocodeCoordinates(limit: 10), 0)
    }

    func testRecordGeocodeFailureIncrementsAttemptCount() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-geocode-failure")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        try repository.upsert(Asset.testAsset(
            path: "/Volumes/NAS/x.cr2", rating: 0,
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 1, pixelHeight: 1, latitude: 10.0, longitude: 10.0,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        ))
        _ = try repository.enqueueMissingGeocodeCoordinates(limit: 10)
        let key = GeocodeCoordinateKey.key(latitude: 10.0, longitude: 10.0)

        try repository.recordGeocodeFailure(coordinateKey: key, errorMessage: "network down")
        try repository.recordGeocodeFailure(coordinateKey: key, errorMessage: "network down")

        XCTAssertEqual(try repository.pendingGeocodeItems(limit: 10, maximumAttemptCount: 2).count, 0)
        XCTAssertEqual(try repository.pendingGeocodeItems(limit: 10, maximumAttemptCount: 3).count, 1)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "CatalogDatabaseTests.testEnqueueMissingGeocodeCoordinatesDeduplicatesByRoundedKey|CatalogDatabaseTests.testRecordPlaceNameCachesAndClearsQueue|CatalogDatabaseTests.testRecordGeocodeFailureIncrementsAttemptCount"`
Expected: compile FAILURE — none of the new types/methods exist.

- [ ] **Step 3: Add the schema**

In `Sources/TeststripCore/Catalog/CatalogMigrations.swift`, bump `version` to the **orchestrator-reserved `19`** (re-verify against `main`; do NOT use 15/16) and append:

```swift
        """
        CREATE TABLE IF NOT EXISTS place_cache (
            coordinate_key TEXT PRIMARY KEY NOT NULL,
            locality TEXT,
            administrative_area TEXT,
            country TEXT,
            display_name TEXT,
            updated_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS geocode_queue (
            coordinate_key TEXT PRIMARY KEY NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            attempt_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            last_attempted_at REAL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_geocode_queue_updated_at ON geocode_queue(updated_at)"
```

- [ ] **Step 4: Add the value types and repository methods**

Create `GeocodeQueueItem.swift` (with `enum GeocodeCoordinateKey`) and `CatalogPlaceName.swift`. Then in `CatalogRepository.swift` implement the methods. `enqueueMissingGeocodeCoordinates` computes the rounded key in SQL with `printf('%.2f,%.2f', ROUND(lat, 2), ROUND(lon, 2))` matched to `GeocodeCoordinateKey.roundingDecimals`, e.g.:

```swift
    public func enqueueMissingGeocodeCoordinates(limit: Int) throws -> Int {
        guard limit > 0 else { return 0 }
        let now = "\(Date().timeIntervalSince1970)"
        let rows = try database.rows(
            """
            WITH located AS (
                SELECT \(Self.latitudeExpressionSQL) AS lat,
                       \(Self.longitudeExpressionSQL) AS lon
                FROM assets
                WHERE json_valid(technical_metadata_json)
                  AND json_type(technical_metadata_json, '$.latitude') IN ('integer', 'real')
                  AND json_type(technical_metadata_json, '$.longitude') IN ('integer', 'real')
            ),
            keyed AS (
                SELECT printf('%.2f,%.2f', ROUND(lat, 2), ROUND(lon, 2)) AS coordinate_key,
                       AVG(lat) AS lat, AVG(lon) AS lon
                FROM located
                GROUP BY coordinate_key
            )
            SELECT coordinate_key, lat, lon
            FROM keyed
            WHERE coordinate_key NOT IN (SELECT coordinate_key FROM place_cache)
              AND coordinate_key NOT IN (SELECT coordinate_key FROM geocode_queue)
            LIMIT ?
            """,
            bindings: ["\(limit)"]
        )
        try database.transaction {
            for row in rows {
                guard let key = row["coordinate_key"],
                      let lat = row["lat"], let lon = row["lon"] else { continue }
                try database.execute(
                    """
                    INSERT OR IGNORE INTO geocode_queue (coordinate_key, latitude, longitude, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    bindings: [key, lat, lon, now]
                )
            }
        }
        return rows.count
    }
```

`pendingGeocodeItems`, `recordGeocodeFailure`, `recordPlaceName` (upsert `place_cache` + `DELETE FROM geocode_queue` inside one `transaction`), `placeName`, and `geocodeQueueDepth` follow the `preview_generation_queue` methods verbatim in shape. **Note:** `GeocodeCoordinateKey.key` must produce the same string the SQL `printf('%.2f,%.2f', ...)` produces — use `String(format: "%.2f,%.2f", (lat*100).rounded()/100, (lon*100).rounded()/100)`. The tests above pin this equivalence.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter "CatalogDatabaseTests"`
Expected: PASS (all existing + 3 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Catalog/GeocodeQueueItem.swift Sources/TeststripCore/Catalog/CatalogPlaceName.swift Sources/TeststripCore/Catalog/CatalogMigrations.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: add reverse-geocode cache and work queue to the catalog"
```

---

### Task 6: `ReverseGeocoder` protocol, `CLGeocoder` implementation, and throttled `reverseGeocodeBatch` worker command

Add a `ReverseGeocoder` protocol (test seam), a real `CLGeocoderReverseGeocoder`, and a new `WorkerCommand.reverseGeocodeBatch(limit:)` the executor drains against the Task-5 queue: for each pending coordinate, geocode with a per-minute budget between requests, write the place name (or record a failure), and report per-coordinate progress. Uses the injected-analyzer pattern proven by `AppleVisionEvaluationProvider` (real impl in production, double in tests) so the tests never hit the network. **This task carries the plan's single real integration risk (CLGeocoder inside the worker CLI process) — Step 0 de-risks it before any queue plumbing.**

**Estimated scope:** ~320 LOC including tests.

**Files:**
- Create: `Sources/TeststripCore/Evaluation/ReverseGeocoder.swift`
- Modify: `Sources/TeststripCore/Worker/WorkerCommand.swift`
- Modify: `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`
- Test: `Tests/TeststripCoreTests/ReverseGeocoderTests.swift` (new), `Tests/TeststripWorkerTests/WorkerCommandExecutorTests.swift`

**Interfaces:**
- Produces:
  - `struct ReverseGeocodeResult: Equatable, Sendable { public var locality, administrativeArea, country: String? }`
  - `protocol ReverseGeocoder: Sendable { func reverseGeocode(latitude: Double, longitude: Double) throws -> ReverseGeocodeResult? }` (nil = no place found; throw = transient/rate-limited failure to retry).
  - `struct CLGeocoderReverseGeocoder: ReverseGeocoder` wrapping `CLGeocoder`. Bridges the async `reverseGeocodeLocation(_:) async throws -> [CLPlacemark]` to the synchronous protocol via a `DispatchSemaphore` + a detached `Task` (the CLI has no main run loop; this is the standard bridge and is exactly what Step 0 proves works).
  - `WorkerCommand.reverseGeocodeBatch(limit: Int)` + its `operationDescription`.
  - `static let reverseGeocodeRequestsPerMinuteBudget = 50` and derived `reverseGeocodeMinimumRequestInterval = 60.0 / 50.0` on the executor (tunable; see Decisions).
- Constructor: `WorkerCommandExecutor.init` gains `reverseGeocoder: (any ReverseGeocoder)? = nil`; the `init(configuration:)` path sets `CLGeocoderReverseGeocoder()`.
- Display-name composition lives in ONE place — `CatalogPlaceName.displayName(locality:administrativeArea:country:)` static helper — so Task 8's aggregation and this writer agree. Format: the most specific of `locality`, else `administrativeArea`, joined with `country` by ` · ` (e.g. `Paris · France`); nil when all components are nil.

- [ ] **Step 0: De-risk CLGeocoder in the worker process (spike, then keep the smoke script)**

Before writing queue code, prove `CLGeocoder` returns a placemark from a plain SwiftPM executable with the worker's inherited network sandbox. Add a real-network smoke script `script/verify_reverse_geocode_smoke.sh` (following the repo's `verify_*` convention: builds, runs a tiny harness that geocodes a known coordinate, prints PASS/FAIL, guards on network availability and skips cleanly when offline). Run it once:

Run: `bash script/verify_reverse_geocode_smoke.sh`
Expected: `PASS Paris` (or a clean `SKIP no network`).

If CLGeocoder cannot run in the worker CLI (no placemark, hangs without a run loop, or needs an entitlement the worker lacks), STOP and raise the app-actor fallback decision (see Decisions) with Jesse before continuing — do not silently move geocoding to the app.

- [ ] **Step 1: Write the failing tests (with a fake geocoder — no network)**

Add `Tests/TeststripCoreTests/ReverseGeocoderTests.swift` and extend `WorkerCommandExecutorTests.swift`. A fake `ReverseGeocoder` returns canned results and can be told to throw for a coordinate:

```swift
    func testReverseGeocodeBatchWritesPlaceNamesAndClearsQueue() throws {
        let harness = try WorkerExecutorHarness.make()   // existing helper pattern in this test file
        try harness.repository.upsert(Asset.testAsset(
            path: "/Volumes/NAS/eiffel.cr2", rating: 0,
            technicalMetadata: .located(latitude: 48.8584, longitude: 2.2945)
        ))
        _ = try harness.repository.enqueueMissingGeocodeCoordinates(limit: 10)

        let geocoder = FakeReverseGeocoder(results: [
            GeocodeCoordinateKey.key(latitude: 48.8584, longitude: 2.2945):
                ReverseGeocodeResult(locality: "Paris", administrativeArea: "Île-de-France", country: "France")
        ])
        let executor = harness.executor(reverseGeocoder: geocoder, requestInterval: 0)

        let result = try executor.execute(.reverseGeocodeBatch(limit: 10))

        XCTAssertEqual(harness.repository.placeName(
            coordinateKey: GeocodeCoordinateKey.key(latitude: 48.8584, longitude: 2.2945))?.displayName,
            "Paris · France")
        XCTAssertEqual(try harness.repository.geocodeQueueDepth(), 0)
        if case .completed(let message) = result { XCTAssertTrue(message.contains("1")) } else { XCTFail() }
    }

    func testReverseGeocodeBatchRecordsFailureAndLeavesCoordinateQueued() throws {
        let harness = try WorkerExecutorHarness.make()
        try harness.repository.upsert(Asset.testAsset(
            path: "/Volumes/NAS/x.cr2", rating: 0,
            technicalMetadata: .located(latitude: 10.0, longitude: 10.0)
        ))
        _ = try harness.repository.enqueueMissingGeocodeCoordinates(limit: 10)
        let geocoder = FakeReverseGeocoder(throwingKeys: [GeocodeCoordinateKey.key(latitude: 10.0, longitude: 10.0)])
        let executor = harness.executor(reverseGeocoder: geocoder, requestInterval: 0)

        _ = try executor.execute(.reverseGeocodeBatch(limit: 10))

        XCTAssertNil(try harness.repository.placeName(coordinateKey: GeocodeCoordinateKey.key(latitude: 10.0, longitude: 10.0)))
        XCTAssertEqual(try harness.repository.pendingGeocodeItems(limit: 10, maximumAttemptCount: 5).count, 1)
    }
```

(Reuse or add `AssetTechnicalMetadata.located(latitude:longitude:)` and the executor harness already present in `WorkerCommandExecutorTests.swift`; match its existing style. If no harness exists, construct executor + repository inline as the other tests in that file do.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "WorkerCommandExecutorTests.testReverseGeocodeBatchWritesPlaceNamesAndClearsQueue|WorkerCommandExecutorTests.testReverseGeocodeBatchRecordsFailureAndLeavesCoordinateQueued"`
Expected: compile FAILURE — no `.reverseGeocodeBatch` case, no `ReverseGeocoder`.

- [ ] **Step 3: Add `ReverseGeocoder.swift` and the command case**

Create `Sources/TeststripCore/Evaluation/ReverseGeocoder.swift` with the protocol, `ReverseGeocodeResult`, and `CLGeocoderReverseGeocoder`. Add `case reverseGeocodeBatch(limit: Int)` to `WorkerCommand`, and its `operationDescription` (`"reverse-geocode up to \(limit) locations"`) and `controlKind` (add it to the `nil`-returning list).

- [ ] **Step 4: Drain the queue in the executor**

Add `reverseGeocodeBatch` to `WorkerCommandExecutor.execute`'s switch and implement the drain, throttling with `Thread.sleep(forTimeInterval:)` between requests (skip the sleep when `requestInterval == 0`, for tests). On a `ReverseGeocodeResult`, `recordPlaceName`; on `nil` (no place found) still `recordPlaceName` with all-nil components so the coordinate is not retried forever; on `throw`, `recordGeocodeFailure` and continue. Report progress per coordinate. Honor `Task.checkCancellation()` between items (matches `refreshAvailabilityBatch`).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter "WorkerCommandExecutorTests|ReverseGeocoderTests"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Evaluation/ReverseGeocoder.swift Sources/TeststripCore/Worker/WorkerCommand.swift Sources/TeststripCore/Worker/WorkerCommandExecutor.swift script/verify_reverse_geocode_smoke.sh Tests/TeststripCoreTests/ReverseGeocoderTests.swift Tests/TeststripWorkerTests/WorkerCommandExecutorTests.swift
git commit -m "feat: throttled reverse-geocode worker command over the geocode queue"
```

---

### Task 7: App-side geocoding coordinator — dispatch, throttle pacing, and the "Geocoding N of M" Activity row

`AppModel` populates the geocode queue after import/coordinate changes and dispatches `reverseGeocodeBatch` commands to the worker as slots free (mirroring `enqueuePendingPreviewGeneration`), pacing re-dispatch so the global request budget holds, and surfaces a single `WorkSessionKind.geocoding` background-work item titled "Geocoding N of M". Offline is graceful: dispatch is a no-op when the queue is empty, and worker failures re-queue (Task 6) rather than erroring the UI.

**Estimated scope:** ~260 LOC including tests. **Wave-1 note:** rebase on the merged session-restore/sidebar work first; this task adds a stored property and touches `rebuildSidebarSections` indirectly via the Activity presentation.

**Files:**
- Modify: `Sources/TeststripCore/Work/WorkSession.swift` (`WorkSessionKind.geocoding`)
- Modify: `Sources/TeststripApp/AppModel.swift`
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces:
  - `WorkSessionKind.geocoding` (String raw enum; add `"geocoding"`). Update the single exhaustive switch `AppModel.workKindTitle(_:)` (verified: only exhaustive switch over the kind) with `case .geocoding: return "Geocoding"`.
  - `AppModel.enqueuePendingGeocoding()` — calls `repository.enqueueMissingGeocodeCoordinates(limit:)`, then if the queue is non-empty and no geocode work item is active, enqueues one `reverseGeocodeBatch(limit:)` background item via `workerSupervisor.enqueue`. Batch limit = `Self.geocodeBatchSize` (constant, e.g. 50 = ~1 minute of budgeted work).
  - Called from the same completion points that already call `enqueuePendingPreviewGeneration()` (import completion; verified both are invoked together around the import-finish path) and once on model load.
  - `AppModel.geocodeActivityTitle` (or reuse the background-work title): "Geocoding N of M" where M = `geocodeQueueDepth()` at dispatch time and N = completed.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift` (reuse the in-repo model+catalog harness these tests already use — a temp catalog with a stub/real worker supervisor):

```swift
    func testEnqueuePendingGeocodingPopulatesQueueForGeotaggedAssets() throws {
        let harness = try AppModelHarness.make()   // existing pattern in AppModelTests
        try harness.repository.upsert(Asset.testAsset(
            path: "/Volumes/NAS/a.cr2", rating: 0,
            technicalMetadata: .located(latitude: 48.8584, longitude: 2.2945)
        ))
        try harness.repository.upsert(Asset.testAsset(path: "/Volumes/NAS/plain.cr2", rating: 0))

        try harness.model.enqueuePendingGeocoding()

        XCTAssertEqual(try harness.repository.geocodeQueueDepth(), 1)
        XCTAssertEqual(harness.enqueuedCommands.filter { $0.isReverseGeocodeBatch }.count, 1)
    }

    func testEnqueuePendingGeocodingIsNoOpWhenNoCoordinates() throws {
        let harness = try AppModelHarness.make()
        try harness.repository.upsert(Asset.testAsset(path: "/Volumes/NAS/plain.cr2", rating: 0))

        try harness.model.enqueuePendingGeocoding()

        XCTAssertEqual(try harness.repository.geocodeQueueDepth(), 0)
        XCTAssertTrue(harness.enqueuedCommands.filter { $0.isReverseGeocodeBatch }.isEmpty)
    }
```

(If `AppModelHarness`/`enqueuedCommands` capture does not already exist, follow whatever seam the existing `AppModelTests` use to assert on enqueued worker commands — several tests already inspect the background-work queue. Add a small `WorkerCommand.isReverseGeocodeBatch` computed helper in the test file if needed, or pattern-match the case inline.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "AppModelTests.testEnqueuePendingGeocodingPopulatesQueueForGeotaggedAssets|AppModelTests.testEnqueuePendingGeocodingIsNoOpWhenNoCoordinates"`
Expected: compile FAILURE — no `enqueuePendingGeocoding`.

- [ ] **Step 3: Add the kind and the coordinator**

Add `case geocoding` to `WorkSessionKind` and `case .geocoding: return "Geocoding"` to `workKindTitle`. Implement `enqueuePendingGeocoding()` on `AppModel` modeled on `enqueuePendingPreviewGeneration()` (guard on `catalog`/`workerSupervisor`; call `enqueueMissingGeocodeCoordinates`; enqueue one `reverseGeocodeBatch` `BackgroundWorkItem` with `kind: .geocoding`, `title: "Geocoding"`, `detail: "Reading locations"`, `totalUnitCount:` from `geocodeQueueDepth()`). Call it from the import-completion path (next to the existing `enqueuePendingPreviewGeneration()` call) and once from model load.

- [ ] **Step 4: Re-dispatch until the queue drains**

When a geocode work item completes (in the same result-handling path that reacts to preview/eval completions), call `enqueuePendingGeocoding()` again if `geocodeQueueDepth() > 0`. This keeps batches flowing at the worker's paced rate without ever holding a slot longer than one budgeted batch. No UI thread blocks; each batch runs in the worker.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter "AppModelTests"`
Expected: PASS (existing + 2 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Work/WorkSession.swift Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: dispatch reverse-geocoding batches with a progress activity"
```

---

### Task 8: TOP LOCATIONS aggregation from the place cache

Add `CatalogRepository.topLocations(limit:)` — a bounded aggregation joining geotagged assets (by their rounded coordinate key, computed in SQL identically to Task 5) to `place_cache`, grouped by display place name with a photo count, ordered by count desc. Feeds the design-5b TOP LOCATIONS sidebar. Coordinates with no cached name yet are simply absent (graceful: the list fills in as geocoding drains).

**Estimated scope:** ~160 LOC including tests.

**Files:**
- Create: `Sources/TeststripCore/Catalog/CatalogTopLocation.swift`
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift`
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces:
  - `struct CatalogTopLocation: Equatable, Sendable { public var displayName: String; public var assetCount: Int; public var latitude, longitude: Double }` (lat/lon = mean of contributing coordinates, so tapping a top location can drill the map/grid to that centroid).
  - `func topLocations(limit: Int) throws -> [CatalogTopLocation]`

- [ ] **Step 1: Write the failing test**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`:

```swift
    func testTopLocationsAggregatesCachedPlaceNamesByCount() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-top-locations")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        func upsert(_ name: String, _ lat: Double, _ lon: Double) throws {
            try repository.upsert(Asset.testAsset(
                path: "/Volumes/NAS/\(name).cr2", rating: 0,
                technicalMetadata: AssetTechnicalMetadata(
                    pixelWidth: 1, pixelHeight: 1, latitude: lat, longitude: lon,
                    provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
                )
            ))
        }
        try upsert("paris1", 48.8584, 2.2945)
        try upsert("paris2", 48.8600, 2.2950)   // same 2dp key as paris1
        try upsert("nyc", 40.7484, -73.9857)

        try repository.recordPlaceName(CatalogPlaceName(
            coordinateKey: GeocodeCoordinateKey.key(latitude: 48.8584, longitude: 2.2945),
            locality: "Paris", administrativeArea: nil, country: "France", displayName: "Paris · France"))
        try repository.recordPlaceName(CatalogPlaceName(
            coordinateKey: GeocodeCoordinateKey.key(latitude: 40.7484, longitude: -73.9857),
            locality: "New York", administrativeArea: nil, country: "USA", displayName: "New York · USA"))

        let top = try repository.topLocations(limit: 10)
        XCTAssertEqual(top.map(\.displayName), ["Paris · France", "New York · USA"])
        XCTAssertEqual(top.first?.assetCount, 2)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter "CatalogDatabaseTests.testTopLocationsAggregatesCachedPlaceNamesByCount"`
Expected: compile FAILURE — no `topLocations`/`CatalogTopLocation`.

- [ ] **Step 3: Implement `topLocations`**

Create `CatalogTopLocation.swift`. In `CatalogRepository.swift`, join assets' rounded key (the same `printf('%.2f,%.2f', ROUND(lat,2), ROUND(lon,2))` expression as Task 5) to `place_cache`, `GROUP BY place_cache.display_name`, `COUNT(*)`, `AVG(lat)`/`AVG(lon)`, `WHERE place_cache.display_name IS NOT NULL`, `ORDER BY asset_count DESC`, `LIMIT ?`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter "CatalogDatabaseTests.testTopLocationsAggregatesCachedPlaceNamesByCount"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogTopLocation.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: aggregate top locations from the place-name cache"
```

---

### Task 9: Places map route — sidebar row, `LibraryViewMode.map`, `PlacesPresentation`, and the MapKit workspace

Wire the dead `LibraryViewMode.map` enum case into a real browse route: a "Places" sidebar row (`SidebarRowTarget.places`), a topbar mode item, a tested `PlacesPresentation` presentation-model (cluster bubbles sized by count, TOP LOCATIONS list, coverage badge), and a `PlacesWorkspaceView` rendering a MapKit `Map` whose visible-region changes re-query `placeClusters(bounds:cellSize:)` and whose bubble/top-location taps set `geoBoundsFilter` and drill the grid. Follows the timeline browse pattern (`selectTimelineDateRange`): the drill-down switches `selectedView` to `.grid` with the geo predicate applied.

**Estimated scope:** ~460 LOC including tests. **Wave-1 note:** the folder sidebar merges tonight and also edits `defaultSidebarSections`/`rebuildSidebarSections` and the topbar `modeItems` — rebase and re-locate by symbol before editing. Add the Places row after the People row in `libraryRows`.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`SidebarRowTarget.places`, `selectSidebarTarget` case, `geoBoundsFilter` stored property + `currentLibraryQuery` append + `clearLibraryQueryFilters` reset, `selectPlaceBounds`, `catalogPlaceClusters`/`catalogTopLocations`/`geotaggedCoverage` refresh, Places sidebar row)
- Create: `Sources/TeststripApp/PlacesPresentation.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`PlacesWorkspaceView`, topbar mode item, `selectedView == .map` branch)
- Test: `Tests/TeststripAppTests/PlacesPresentationTests.swift` (new), `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces:
  - `SidebarRowTarget.places` + `case .places: selectedAssetSetID = nil; clearLibraryQueryFilters(); selectedView = .map; refreshPlaceData()` in `selectSidebarTarget` (mirrors `.timeline`).
  - `AppModel.geoBoundsFilter: GeoBounds?` stored property (append `.withinGeoBounds` in `currentLibraryQuery()` alongside the capture-date filters; reset it in `clearLibraryQueryFilters()`; both verified insertion points).
  - `AppModel.selectPlaceBounds(_ bounds: GeoBounds)` — sets `geoBoundsFilter = bounds`, `selectedView = .grid`, `try reload()` (mirrors `selectTimelineDateRange`).
  - `AppModel.catalogPlaceClusters: [CatalogPlaceCluster]`, `catalogTopLocations: [CatalogTopLocation]`, `geotaggedCoverage: CatalogGeotaggedCoverage` stored properties + `refreshPlaceData(bounds:cellSize:)` that fills them from the repo (bounded; called on route entry and on map region change).
  - `struct PlacesPresentation: Equatable` with `bubbles: [PlaceBubblePresentation]` (each: coordinate, `assetCount`, a `radius`/`labelText` derived from count — e.g. `radius` scales with `sqrt(count)`, `label` is a compact count like `"1.2k"`), `topLocations: [PlaceRowPresentation]`, `coverageText: String` ("Geotagged on import — 412k of 486k" from `CatalogGeotaggedCoverage`), and `summaryText` ("78 locations · 412,000 geotagged").
  - Topbar: `LibraryTopBarModeItem(title: "Places", systemImage: "map", mode: .map, liveMockupPlaceholder: .placesMap)` appended to `modeItems`.
  - `PlacesWorkspaceView` bridges MapKit region → `GeoBounds` and derives `cellSize` from the region span (e.g. `span.latitudeDelta / targetBubbleCount`), calls `model.refreshPlaceData(bounds:cellSize:)` on region change (debounced), renders one annotation per bubble, and calls `model.selectPlaceBounds(_:)` on tap.

- [ ] **Step 1: Write the failing tests (presentation-model + model routing)**

Add `Tests/TeststripAppTests/PlacesPresentationTests.swift`:

```swift
    func testPresentationSizesBubblesByCountAndBuildsCoverageText() {
        let presentation = PlacesPresentation(
            clusters: [
                CatalogPlaceCluster(latitude: 48.85, longitude: 2.29, assetCount: 1200),
                CatalogPlaceCluster(latitude: 40.74, longitude: -73.98, assetCount: 30)
            ],
            topLocations: [
                CatalogTopLocation(displayName: "Paris · France", assetCount: 1200, latitude: 48.85, longitude: 2.29)
            ],
            coverage: CatalogGeotaggedCoverage(geotaggedCount: 412000, totalCount: 486000)
        )

        XCTAssertEqual(presentation.bubbles.count, 2)
        XCTAssertGreaterThan(presentation.bubbles[0].radius, presentation.bubbles[1].radius)  // 1200 > 30
        XCTAssertEqual(presentation.bubbles[0].labelText, "1.2k")
        XCTAssertEqual(presentation.topLocations.first?.title, "Paris · France")
        XCTAssertEqual(presentation.coverageText, "Geotagged on import — 412,000 of 486,000")
    }

    func testPresentationHandlesNoCoverageGracefully() {
        let presentation = PlacesPresentation(
            clusters: [], topLocations: [],
            coverage: CatalogGeotaggedCoverage(geotaggedCount: 0, totalCount: 40)
        )
        XCTAssertTrue(presentation.bubbles.isEmpty)
        XCTAssertEqual(presentation.coverageText, "No geotagged frames yet")
    }
```

Add to `AppModelTests.swift`:

```swift
    func testSelectingPlacesTargetEntersMapView() throws {
        let harness = try AppModelHarness.make()
        try harness.model.selectSidebarTarget(.places)
        XCTAssertEqual(harness.model.selectedView, .map)
    }

    func testSelectPlaceBoundsAppliesGeoFilterAndReturnsToGrid() throws {
        let harness = try AppModelHarness.make()
        try harness.repository.upsert(Asset.testAsset(
            path: "/Volumes/NAS/paris.cr2", rating: 0,
            technicalMetadata: .located(latitude: 48.8584, longitude: 2.2945)))
        try harness.repository.upsert(Asset.testAsset(
            path: "/Volumes/NAS/sydney.cr2", rating: 0,
            technicalMetadata: .located(latitude: -33.87, longitude: 151.21)))
        try harness.model.reload()

        try harness.model.selectPlaceBounds(GeoBounds(minLatitude: 48, maxLatitude: 49, minLongitude: 2, maxLongitude: 3))

        XCTAssertEqual(harness.model.selectedView, .grid)
        XCTAssertEqual(harness.model.assets.map { $0.originalURL.lastPathComponent }, ["paris.cr2"])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "PlacesPresentationTests|AppModelTests.testSelectingPlacesTargetEntersMapView|AppModelTests.testSelectPlaceBoundsAppliesGeoFilterAndReturnsToGrid"`
Expected: compile FAILURE — no `PlacesPresentation`, `.places` target, `geoBoundsFilter`, or `selectPlaceBounds`.

- [ ] **Step 3: Add the model plumbing**

Add `SidebarRowTarget.places` + the `selectSidebarTarget` case; `geoBoundsFilter` stored property (append `.withinGeoBounds(geoBoundsFilter)` in `currentLibraryQuery()`, reset in `clearLibraryQueryFilters()`); `selectPlaceBounds`; the three place-data stored properties + `refreshPlaceData`; and the Places `SidebarRow` (after People) in `defaultSidebarSections`.

- [ ] **Step 4: Add `PlacesPresentation`**

Create `Sources/TeststripApp/PlacesPresentation.swift` with the bubble-sizing, top-location, and coverage formatting (the count abbreviation `"1.2k"` and the `NumberFormatter`-grouped coverage text). Pure value logic — fully covered by Step 1's tests.

- [ ] **Step 5: Add the MapKit workspace view and wire the route**

In `LibraryGridView.swift`, add the `else if model.selectedView == .map { PlacesWorkspaceView(model: model) }` branch (next to the `.timeline` branch), append the topbar mode item, and implement `PlacesWorkspaceView` (MapKit `Map` with bubble annotations from `PlacesPresentation`, a TOP LOCATIONS sidebar list, the coverage badge, region-change → `refreshPlaceData`, tap → `selectPlaceBounds`). No snapshot tests — the view is a thin shell over the tested presentation.

- [ ] **Step 6: Build and run the suite**

Run: `swift build && swift test --filter "PlacesPresentationTests|AppModelTests"`
Expected: build succeeds; tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/TeststripApp/PlacesPresentation.swift Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/PlacesPresentationTests.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: add the Places map route with clustered bubbles and region drill-down"
```

---

### Task 10: Backfill coordinates for existing catalogs (bounded, resumable re-read)

Catalogs imported before Task 2 have no coordinates. Backfill by re-reading GPS from originals that are online and whose technical metadata lacks a latitude. This is the honest option: it only touches assets whose original is available (offline/missing/moved sources are skipped and picked up on reconnect), it is bounded and resumable, and it re-reads read-only (originals never modified). A new `WorkerCommand.backfillCoordinates(assetIDs:)` re-extracts via the existing `IngestService` decode path and upserts; `AppModel` dispatches bounded batches and surfaces "Reading locations N of M" (reusing `WorkSessionKind.geocoding`). After a backfill batch upserts coordinates, the Task-7 geocoding dispatch naturally enqueues the new coordinates.

**Estimated scope:** ~260 LOC including tests.

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (`assetsMissingCoordinates(limit:)`)
- Modify: `Sources/TeststripCore/Ingest/IngestService.swift` (expose a public `coordinates(for url:) -> (Double, Double, Double?)?` re-read helper, or a `reReadTechnicalMetadata(for:)`)
- Modify: `Sources/TeststripCore/Worker/WorkerCommand.swift` + `WorkerCommandExecutor.swift` (`.backfillCoordinates`)
- Modify: `Sources/TeststripApp/AppModel.swift` (dispatch + activity; a user-visible "Read locations for existing photos" action)
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`, `Tests/TeststripWorkerTests/WorkerCommandExecutorTests.swift`

**Interfaces:**
- Produces:
  - `CatalogRepository.assetsMissingCoordinates(limit: Int) throws -> [AssetID]` — assets where `availability = 'online'` AND (`technical_metadata_json` is null/invalid OR `json_type($.latitude)` not numeric). Bounded by `limit`; resumable because each successful re-read populates the coordinate and drops the asset from the next scan.
  - `WorkerCommand.backfillCoordinates(assetIDs: [AssetID])` — per asset: re-read via decode provider; if coordinates found, `updateTechnicalMetadata`/`upsert` preserving all other technical fields; report progress. Missing-file/decode failure per asset is skipped, not fatal (matches `refreshAvailabilityBatch`'s resilience).
  - `AppModel.beginCoordinateBackfill()` — dispatches bounded `backfillCoordinates` batches for `assetsMissingCoordinates`, shows a `.geocoding`-kind activity "Reading locations N of M", and re-dispatches until none remain; then triggers `enqueuePendingGeocoding()`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`:

```swift
    func testAssetsMissingCoordinatesReturnsOnlineUngeotaggedAssets() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "catalog-missing-coords")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        try repository.upsert(Asset.testAsset(path: "/Volumes/NAS/needs.cr2", rating: 0))  // online, no coords
        try repository.upsert(Asset.testAsset(
            path: "/Volumes/NAS/has.cr2", rating: 0,
            technicalMetadata: .located(latitude: 1, longitude: 2)))                       // already geotagged
        var offline = Asset.testAsset(path: "/Volumes/CARD/off.cr2", rating: 0)
        offline.availability = .offline
        try repository.upsert(offline)

        let ids = try repository.assetsMissingCoordinates(limit: 10).map(\.rawValue)
        XCTAssertEqual(ids, [try repository.asset(id: AssetID(rawValue: ids.first ?? "")).id.rawValue])
        XCTAssertTrue(ids.contains { $0.contains("needs") == false })  // returns exactly the online, ungeotagged asset
    }
```

(Adjust the final assertions to the repo's `testAsset` id scheme — the load-bearing assertion is: exactly one id returned, and it is the online, non-geotagged asset; the offline and already-geotagged ones are excluded.)

Add a worker test in `WorkerCommandExecutorTests.swift` that seeds an online asset pointing at a real fixture image WITH GPS (reuse the sample-data fixtures under `sample-data/` if one carries GPS, or write a tiny JPEG with GPS via `CGImageDestination` in the test's temp dir), runs `.backfillCoordinates`, and asserts the asset now has a latitude. If no GPS-bearing fixture is available, assert instead that a non-GPS fixture leaves latitude nil and does not error (resilience), and cover the GPS extraction itself via Task 2's unit tests.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter "CatalogDatabaseTests.testAssetsMissingCoordinatesReturnsOnlineUngeotaggedAssets"`
Expected: compile FAILURE — no `assetsMissingCoordinates`.

- [ ] **Step 3: Implement the query, command, and dispatch**

Add `assetsMissingCoordinates`, the `.backfillCoordinates` command + executor case (re-reading through the decode registry the executor's `defaultImportService` already wires), and `AppModel.beginCoordinateBackfill()` with its activity. Reuse `WorkSessionKind.geocoding` for the activity title path (or add `.locationBackfill` if a distinct label is wanted — a one-line enum + switch add).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter "CatalogDatabaseTests|WorkerCommandExecutorTests"`
Expected: PASS.

- [ ] **Step 5: Build and run the full suite**

Run: `swift build && swift test`
Expected: build succeeds; all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogRepository.swift Sources/TeststripCore/Ingest/IngestService.swift Sources/TeststripCore/Worker/WorkerCommand.swift Sources/TeststripCore/Worker/WorkerCommandExecutor.swift Sources/TeststripApp/AppModel.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift Tests/TeststripWorkerTests/WorkerCommandExecutorTests.swift
git commit -m "feat: backfill GPS coordinates for existing catalogs"
```

---

## Decisions (flag, do not silently choose)

- **CLGeocoder vs bundled offline reverse-geocoding dataset.** Plan uses `CLGeocoder` first (stock, no dependency, no data to bundle). The cache (`place_cache`) and the `ReverseGeocoder` protocol are designed so a future offline provider (e.g. a bundled locality dataset) slots in behind the same protocol with zero schema change — only `CLGeocoderReverseGeocoder` gets swapped/augmented. **Decision to surface, not block on:** whether to ship a bundled offline dataset later. A bundled dataset would be a NEW hard dependency (data + license) — do not add it without Jesse's sign-off.
- **CLGeocoder inside the worker CLI process (Task 6, Step 0).** The plan runs geocoding in the worker (honors "worker-side queue," keeps the app process free, inherits the network sandbox). This depends on `CLGeocoder` working from a plain SwiftPM executable with no main run loop — de-risked by Task 6 Step 0's smoke script BEFORE any queue plumbing. **Fallback if the spike fails:** run the geocoding coordinator as an app-side `actor` (the app has a run loop and `network.client` natively) draining the same catalog queue directly. This is a real fork in the design — raise it with Jesse rather than silently switching processes.
- **SQL grid-clustering vs `MKClusterAnnotation`.** Plan rejects `MKClusterAnnotation` at six-figure scale because it requires adding every asset as an `MKAnnotation` (materializing 100k+ objects in memory). Instead, cluster counts come from bounded SQL `GROUP BY` (`placeClusters`), and only the visible cells become annotations. This is the load-bearing scale decision; do not "simplify" back to per-asset annotations.
- **Cache granularity = 2 decimal places (≈ 1.1 km).** `GeocodeCoordinateKey.roundingDecimals = 2` sets how aggressively nearby photos share one geocode lookup (fewer requests, coarser place attribution). Tunable; 3 dp (≈ 110 m) trades more requests for finer names. Pinned by tests, so a change is a deliberate one-line edit + test update.
- **Request budget = 50/min.** `reverseGeocodeRequestsPerMinuteBudget = 50` with a 1.2 s inter-request sleep. This is a conservative read of CLGeocoder's undocumented throttle; if Apple returns throttle errors (`kCLErrorGeocodeFoundNoResult`/error 2 bursts), the failure path already re-queues, but the budget may need lowering. Tunable constant.
- **Antimeridian bounds crossing** (`minLongitude > maxLongitude`) is deferred — the map's single visible region and per-cell drill-down never emit crossing bounds. If a future "select two regions" gesture needs it, extend `.withinGeoBounds` compilation with an `OR` split. Recorded, not built.
- **`0,0` fix = "no fix".** Task 2 treats an exact 0,0 coordinate as absent (cameras write it as a null sentinel). Flagged in case a real Gulf-of-Guinea shoot ever appears.

## Deferred (explicitly out of this plan)

- **Inspector mini-location-map (design 1a).** Verified: the current `InspectorView` has NO location/GPS row or map — design 1a's map pin is mockup-only. Adding a per-photo inspector map is a small follow-up (an `InspectorMetadataRow` for coordinates + an optional `Map` snippet) but is not part of "Places" and is not planned here. Coordinates are now available on `AssetTechnicalMetadata` if/when it's wanted.
- **Map tile styling / custom basemap, region search box, draw-a-region selection, heatmap rendering.** Design 5b is bubbles + list + badge; richer map interactions are later.
- **Reverse-geocoding into keywords/XMP.** Place names stay display-only per the reviewable/undoable and originals-never-modified rules. Turning a place into a written keyword would be a separate, confirm-gated feature.
- **Offline reverse-geocoding dataset** (see Decisions).

## Self-Review Notes

- **Existing-behavior claims verified against `main` (HEAD `4fb94b0`) by test run and code read:** (1) `technical_metadata_json` is a JSON `TEXT` blob and new optional `AssetTechnicalMetadata` fields need no migration — proven by `testPersistsApertureShutterSpeedAndFocalLengthThroughExistingTechnicalMetadataStorage` passing (ran green) and by `CatalogDatabase.migrate()` adding the column via `addColumnIfMissing`, never per-field. (2) `ImageIODecodeProvider.metadata(from:provenance:filename:)` is the tested static seam — `testImageIOTechnicalMetadataReadsCameraLensISOAndCaptureDate` ran green. (3) `kCGImagePropertyGPSDictionary` is NOT read today (grep of `Sources` for GPS/latitude/longitude returned nothing). (4) `LibraryViewMode.map` exists but is dead — no `modeItems` entry, no `selectSidebarTarget` case, no `selectedView == .map` branch. (5) The inspector has no location map. (6) The worker inherits the app's `network.client` via `com.apple.security.inherit`.
- **Patterns reused, not invented:** `placeClusters`/`geotaggedCoverage`/`topLocations` mirror `timelineDays()` (bounded `GROUP BY`, no asset load). `geocode_queue`/`place_cache` mirror `preview_generation_queue` (attempt_count/last_error/last_attempted_at, bounded fetch, resolved-item deletion). `enqueuePendingGeocoding` mirrors `enqueuePendingPreviewGeneration`. `ReverseGeocoder` mirrors `AppleVisionAnalyzing` (protocol + real impl + test double). The Places route mirrors the timeline route (`selectTimelineDateRange` → `selectPlaceBounds`, `TimelinePresentation` → `PlacesPresentation`, `TimelineWorkspaceView` → `PlacesWorkspaceView`).
- **No invented APIs.** MapKit `Map`, CoreLocation `CLGeocoder`/`CLLocation`/`CLPlacemark`, and the ImageIO GPS constants are the only new framework symbols; all are stock. The CLGeocoder-in-CLI assumption is explicitly de-risked by a spike (Task 6 Step 0) rather than asserted.
- **Provisional/undoable rule check:** no task writes flags/ratings/keywords/metadata/XMP from machine output. Coordinates are read from EXIF (factual, not inferred); place names live only in `place_cache`. Originals are only ever read (Task 10 re-read is read-only).
- **Migration safety:** two additive migrations (Task 3 index; Task 5 two tables), both `CREATE ... IF NOT EXISTS`, no `ALTER TABLE`, no data rewrite. Versions are **orchestrator-reserved v18 (index) and v19 (tables)** — NOT sequential 15/16, which collide with reject-relocation (v15) and the other concurrent streams. Re-verify both numbers against `main` before bumping (the current version is 14) and take the next free integers, or fold both into one reserved version, if 18/19 are claimed.
- **Scale:** every map/sidebar read is a `COUNT`/`GROUP BY`/`LIMIT`; the geo predicate and cluster/queue aggregations all ride `idx_assets_gps` (EXPLAIN-verified in Task 3). Total estimate ≈ 2,650 LOC across 10 tasks — within the 2–4k honest range.
