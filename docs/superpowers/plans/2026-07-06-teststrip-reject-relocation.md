# Teststrip Reject Relocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit, confirm-gated **Move rejects to folder…** action. This is Teststrip's FIRST feature that relocates originals on disk, so its safety design is the whole point: it shows a preflight naming exactly what will move (count, bytes, destination preview, sidecars coming along), requires an explicit confirmation naming the count, moves each original **with its XMP sidecar** preserving relative structure, updates catalog paths **per file only after that file's bytes are actually on disk**, never leaves a file looking like an unexpected external move, skips-with-issue rather than aborts on a per-file failure, is abortable mid-run, and is **reversible** via a persisted relocation manifest that powers a one-click "Move back."

**Architecture:** Three layers, mirroring the existing reconnect/import patterns.

- **Core filesystem move** — a new `RejectRelocationPlanner` computes collision-safe destination URLs under a common-ancestor-preserving relative layout (pure, no I/O, fully unit-testable), and a new `RejectRelocationService` performs the on-disk move of one original + its sidecar with rollback-on-partial-failure. This mirrors `IngestService.copyOriginalFile`/`copyAdjacentSidecar` (Sources/TeststripCore/Ingest/IngestService.swift:336-395), which is the repo's established "move an original and its sidecar together" pattern.
- **Catalog path rewrite** — a new `CatalogRepository.relocateOriginal(assetID:to:)` re-fingerprints the file at its new location and atomically rewrites `original_path`, `volume_identifier`, `availability = .online`, and the `metadata_sync_state.sidecar_path` in one transaction. This is exactly what `reconnectSourceRoot` (CatalogRepository.swift:1097-1148) does per asset, minus the fingerprint-match gate (we *are* the mover, so we adopt the destination fingerprint rather than requiring it to match).
- **Reversible manifest** — a new `work_sessions` row of `kind = .relocation` records the run in Activity, and a new `relocation_manifest_entries` table stores the per-file `from → to` for both original and sidecar. "Move back" replays the manifest in reverse through the same service + `relocateOriginal`.

The app-layer scope is **reject-flagged assets in the current library scope** (`currentAssetScopeIDs` ∩ `SetQuery(predicates: [.flag(.reject)])`). This is the most predictable, reviewable scope and it composes with the folder sidebar, the person filter, saved sets, and a rejects filter — see the Scope Decision note below for why this beats session-bound scoping.

**Tech Stack:** Swift 6 / macOS 14, SwiftPM, XCTest, SwiftUI presentation-model pattern (no snapshot tests), SQLite via existing `CatalogRepository` / `CatalogDatabase` migrations. No new external dependencies.

## Global Constraints

- **Originals move only on explicit, count-confirmed user action.** No task moves a file without the user having confirmed a checkbox that names the exact count. Nothing auto-triggers; there is no watched-folder or post-cull auto-move.
- **Per-file catalog updates follow per-file disk moves — never a bulk catalog rewrite ahead of the bytes.** The loop moves file N's bytes (original + sidecar), then updates file N's catalog row, then records file N's manifest entry, then advances. A crash or abort at any point leaves the catalog truthful and the manifest able to reverse whatever already moved.
- **Skip-with-issue, never abort-the-run on a per-file failure.** A file that can't move (unavailable original, unwritable destination, name still colliding after disambiguation) is recorded as a `WorkSessionIssue` and the loop continues.
- **No deletion, no Trash.** Files are moved, never removed. "Move back" is the only automated reversal.
- **A Teststrip move must never read as an external move.** Because the catalog row is rewritten to the new path with a freshly-read destination fingerprint and `availability = .online` in the same pass, `SourceAvailabilityProbe` (Sources/TeststripCore/Domain/SourceAvailabilityProbe.swift) never sees the asset as `.moved`/`.missing`/`.stale`. The move is recorded as a first-class `.relocation` work session.
- No SwiftUI snapshot tests. UI behavior lands as presentation-model structs with XCTest model tests (repo pattern in `Tests/TeststripAppTests`).
- Copy separators are the repo's `·` middle dots and `—` em dashes.
- Run all commands from the repo root `/Users/jesse/git/projects/teststrip`.
- **Anchors:** all line numbers are against `main` at commit `240f19a` (HEAD when this plan was authored). The branch advances rapidly and both `AppModel.swift` and `LibraryGridView.swift` move constantly — **re-locate every insertion point by symbol name, not by line number**, and note your own HEAD before starting.
- **Wave-1 dependency:** the folder sidebar, person filter, session restore, loupe zoom, and export presets are merging the same night. This plan only *consumes* their effect on library scope through the existing `currentAssetScopeIDs(repository:)` (AppModel.swift:7755) and `currentLibraryQuery()` (AppModel.swift:7568); it does not touch their code. Rebase before starting Task 4.

## Scope Decision — why current-scope rejects, not session-bound rejects

The task brief floats "current filter/set/session picks output complement." Session-bound scoping (move the culling session's rejects specifically) was rejected: a culling session persists a **Picks** output set but no "rejects" set exists (`refreshCullingSessionOutputSet`, AppModel.swift:8011, only ever materializes picks), so a session-rejects scope would require inventing and maintaining a second output set purely to feed this action. Current-scope scoping is simpler, already reviewable (the preflight lists every file), and composes: after a stack cull the user is looking at that session's frames; applying a rejects filter or just running the action over the current scope reaches exactly the rejects the user just made. The command therefore operates on **reject-flagged assets within the current library scope**, and the culling-completion banner offers it as a shortcut that operates on that same scope.

## Structure Decision — preserve relative layout under the moved set's common ancestor

Flat-into-one-folder was rejected: burst-shot RAW files share basenames across day-subfolders (`DSC_0001.NEF` in `Day1/` and `Day2/`), so a flat move collides constantly and destroys the provenance a photographer reads from folder structure. Per-source-root reconstruction was rejected as more machinery than the payoff justifies (rejects from one shoot usually share an ancestor anyway). The chosen rule: compute the **longest common ancestor directory** of the moved originals, and recreate each file's path *relative to that ancestor* beneath the destination. All-in-one-folder degenerates to flat automatically; cross-subfolder sets keep their subfolders. A collision-safe suffix (`-2`, `-3`, mirroring `ExportService.availableDestinationURL`, Sources/TeststripCore/Export/ExportService.swift:152) is the backstop for any residual name clash (including a pre-existing file already sitting at the destination).

## File Map

- Create: `Sources/TeststripCore/Relocation/RejectRelocationPlanner.swift` — pure destination-URL planner (Task 3).
- Create: `Sources/TeststripCore/Relocation/RejectRelocationService.swift` — filesystem move of one original + sidecar with rollback (Task 3).
- Create: `Sources/TeststripCore/Relocation/RelocationManifestEntry.swift` — the per-file `from → to` record (Task 1).
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` — schema v15 + `relocation_manifest_entries` table (Task 1).
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` — manifest CRUD (Task 1) + `relocateOriginal(assetID:to:)` (Task 2).
- Modify: `Sources/TeststripCore/Work/WorkSession.swift` — add `WorkSessionKind.relocation` (Task 1).
- Modify: `Sources/TeststripApp/AppModel.swift` — preflight (Task 4), execute (Task 5), reverse (Task 6), published state.
- Modify: `Sources/TeststripApp/FolderSelectionPanel.swift` — a rejects-destination chooser (Task 7).
- Modify: `Sources/TeststripApp/LibraryGridView.swift` — command button, preflight sheet, confirmation gate, move-back banner (Task 7).
- Tests: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`, `Tests/TeststripCoreTests/RejectRelocationServiceTests.swift` (new), `Tests/TeststripAppTests/AppModelTests.swift`, `Tests/TeststripAppTests/RejectRelocationPreflightTests.swift` (new).

---

### Task 1: Schema — relocation manifest table, entry type, and `.relocation` work-session kind

The persistence spine for reversibility: a `.relocation` work-session kind so runs show in Activity like every other work session, and a `relocation_manifest_entries` table holding the per-file `from → to` for original and sidecar, keyed by session. Migrations are idempotent `CREATE TABLE IF NOT EXISTS` applied on every open (CatalogDatabase.swift:32-50), so adding a statement and bumping `CatalogMigrations.version` is the whole migration.

**Estimated scope:** ~200 LOC including tests.

**Files:**
- Modify: `Sources/TeststripCore/Work/WorkSession.swift:11-22` (`WorkSessionKind`)
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift:2` (`version`), `:4-180` (`statements`)
- Create: `Sources/TeststripCore/Relocation/RelocationManifestEntry.swift`
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (add CRUD near `save(_ session:)` at :843)
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces:
  - `WorkSessionKind.relocation`
  - `RelocationManifestEntry` — `Equatable, Sendable` struct: `assetID: AssetID`, `originalFrom: URL`, `originalTo: URL`, `sidecarFrom: URL?`, `sidecarTo: URL?`
  - `CatalogRepository.saveRelocationManifestEntry(_ entry: RelocationManifestEntry, sessionID: WorkSessionID) throws`
  - `CatalogRepository.relocationManifestEntries(sessionID: WorkSessionID) throws -> [RelocationManifestEntry]`
  - `CatalogRepository.deleteRelocationManifest(sessionID: WorkSessionID) throws`

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`:

```swift
    func testPersistsRelocationManifestEntriesInInsertionOrder() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "relocation-manifest")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let sessionID = WorkSessionID(rawValue: "relocation-1")
        let first = RelocationManifestEntry(
            assetID: AssetID(rawValue: "a1"),
            originalFrom: URL(fileURLWithPath: "/Shoot/Day1/a1.cr2"),
            originalTo: URL(fileURLWithPath: "/Rejects/Day1/a1.cr2"),
            sidecarFrom: URL(fileURLWithPath: "/Shoot/Day1/a1.cr2.xmp"),
            sidecarTo: URL(fileURLWithPath: "/Rejects/Day1/a1.cr2.xmp")
        )
        let second = RelocationManifestEntry(
            assetID: AssetID(rawValue: "a2"),
            originalFrom: URL(fileURLWithPath: "/Shoot/Day2/a2.cr2"),
            originalTo: URL(fileURLWithPath: "/Rejects/Day2/a2.cr2"),
            sidecarFrom: nil,
            sidecarTo: nil
        )

        try repository.saveRelocationManifestEntry(first, sessionID: sessionID)
        try repository.saveRelocationManifestEntry(second, sessionID: sessionID)

        XCTAssertEqual(try repository.relocationManifestEntries(sessionID: sessionID), [first, second])
        XCTAssertEqual(try repository.relocationManifestEntries(sessionID: WorkSessionID(rawValue: "other")), [])
    }

    func testDeleteRelocationManifestRemovesOnlyThatSession() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "relocation-manifest-delete")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let kept = WorkSessionID(rawValue: "keep")
        let removed = WorkSessionID(rawValue: "remove")
        let keptEntry = RelocationManifestEntry(
            assetID: AssetID(rawValue: "k"),
            originalFrom: URL(fileURLWithPath: "/a/k.cr2"),
            originalTo: URL(fileURLWithPath: "/b/k.cr2"),
            sidecarFrom: nil,
            sidecarTo: nil
        )
        try repository.saveRelocationManifestEntry(keptEntry, sessionID: kept)
        try repository.saveRelocationManifestEntry(
            RelocationManifestEntry(
                assetID: AssetID(rawValue: "r"),
                originalFrom: URL(fileURLWithPath: "/a/r.cr2"),
                originalTo: URL(fileURLWithPath: "/b/r.cr2"),
                sidecarFrom: nil,
                sidecarTo: nil
            ),
            sessionID: removed
        )

        try repository.deleteRelocationManifest(sessionID: removed)

        XCTAssertEqual(try repository.relocationManifestEntries(sessionID: removed), [])
        XCTAssertEqual(try repository.relocationManifestEntries(sessionID: kept), [keptEntry])
    }

    func testRelocationWorkSessionKindRoundTrips() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "relocation-session-kind")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let session = WorkSession(
            id: WorkSessionID(rawValue: "relocation-session"),
            kind: .relocation,
            intent: "move-rejects",
            title: "Move rejects",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        try repository.save(session)

        XCTAssertEqual(try repository.session(id: session.id).kind, .relocation)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "CatalogDatabaseTests.testPersistsRelocationManifestEntriesInInsertionOrder|CatalogDatabaseTests.testDeleteRelocationManifestRemovesOnlyThatSession|CatalogDatabaseTests.testRelocationWorkSessionKindRoundTrips"`
Expected: compile FAILURE — no `RelocationManifestEntry`, no `.relocation` case, no `saveRelocationManifestEntry`.

- [ ] **Step 3: Add the kind, the entry type, the table, and the CRUD**

In `Sources/TeststripCore/Work/WorkSession.swift`, add to `enum WorkSessionKind` (after `case export`):

```swift
    case relocation
```

Create `Sources/TeststripCore/Relocation/RelocationManifestEntry.swift`:

```swift
import Foundation

/// One file's move recorded for reversal: where the original (and its sidecar,
/// if any) came from and went to. The reversal replays these to → from.
public struct RelocationManifestEntry: Equatable, Sendable {
    public var assetID: AssetID
    public var originalFrom: URL
    public var originalTo: URL
    public var sidecarFrom: URL?
    public var sidecarTo: URL?

    public init(
        assetID: AssetID,
        originalFrom: URL,
        originalTo: URL,
        sidecarFrom: URL?,
        sidecarTo: URL?
    ) {
        self.assetID = assetID
        self.originalFrom = originalFrom
        self.originalTo = originalTo
        self.sidecarFrom = sidecarFrom
        self.sidecarTo = sidecarTo
    }
}
```

In `Sources/TeststripCore/Catalog/CatalogMigrations.swift`, bump `static let version = 14` to `15`, and append this statement to the `statements` array (after the `dismissed_faces` table, before the closing `]`):

```swift
        ,
        """
        CREATE TABLE IF NOT EXISTS relocation_manifest_entries (
            session_id TEXT NOT NULL,
            sequence INTEGER NOT NULL,
            asset_id TEXT NOT NULL,
            original_from_path TEXT NOT NULL,
            original_to_path TEXT NOT NULL,
            sidecar_from_path TEXT,
            sidecar_to_path TEXT,
            created_at REAL NOT NULL,
            PRIMARY KEY (session_id, asset_id)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_relocation_manifest_session ON relocation_manifest_entries(session_id, sequence)"
```

(The `sequence` column preserves insertion order for reversal; `PRIMARY KEY (session_id, asset_id)` makes re-recording the same asset idempotent.)

In `Sources/TeststripCore/Catalog/CatalogRepository.swift`, add the CRUD near `save(_ session:)` (~:843):

```swift
    public func saveRelocationManifestEntry(_ entry: RelocationManifestEntry, sessionID: WorkSessionID) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO relocation_manifest_entries (
                session_id, sequence, asset_id,
                original_from_path, original_to_path,
                sidecar_from_path, sidecar_to_path, created_at
            )
            VALUES (
                ?,
                (SELECT COALESCE(MAX(sequence), -1) + 1 FROM relocation_manifest_entries WHERE session_id = ?),
                ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT(session_id, asset_id) DO UPDATE SET
                original_from_path = excluded.original_from_path,
                original_to_path = excluded.original_to_path,
                sidecar_from_path = excluded.sidecar_from_path,
                sidecar_to_path = excluded.sidecar_to_path
            """,
            bindings: [
                sessionID.rawValue,
                sessionID.rawValue,
                entry.assetID.rawValue,
                entry.originalFrom.path,
                entry.originalTo.path,
                entry.sidecarFrom?.path ?? "",
                entry.sidecarTo?.path ?? "",
                now
            ]
        )
    }

    public func relocationManifestEntries(sessionID: WorkSessionID) throws -> [RelocationManifestEntry] {
        let rows = try database.rows(
            "SELECT * FROM relocation_manifest_entries WHERE session_id = ? ORDER BY sequence ASC",
            bindings: [sessionID.rawValue]
        )
        return try rows.map(decodeRelocationManifestEntry)
    }

    public func deleteRelocationManifest(sessionID: WorkSessionID) throws {
        try database.execute(
            "DELETE FROM relocation_manifest_entries WHERE session_id = ?",
            bindings: [sessionID.rawValue]
        )
    }

    private func decodeRelocationManifestEntry(_ row: [String: String]) throws -> RelocationManifestEntry {
        guard let assetID = row["asset_id"],
              let originalFrom = row["original_from_path"],
              let originalTo = row["original_to_path"] else {
            throw CatalogError.sqlite("relocation manifest row is missing required columns")
        }
        return RelocationManifestEntry(
            assetID: AssetID(rawValue: assetID),
            originalFrom: URL(fileURLWithPath: originalFrom),
            originalTo: URL(fileURLWithPath: originalTo),
            sidecarFrom: row["sidecar_from_path"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) },
            sidecarTo: row["sidecar_to_path"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        )
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "CatalogDatabaseTests.testPersistsRelocationManifestEntriesInInsertionOrder|CatalogDatabaseTests.testDeleteRelocationManifestRemovesOnlyThatSession|CatalogDatabaseTests.testRelocationWorkSessionKindRoundTrips"`
Expected: PASS

Then guard the schema/session suites:

Run: `swift test --filter "CatalogDatabaseTests|WorkSessionTests"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Work/WorkSession.swift Sources/TeststripCore/Catalog/CatalogMigrations.swift Sources/TeststripCore/Relocation/RelocationManifestEntry.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: persist relocation manifest entries and a relocation work-session kind"
```

---

### Task 2: Catalog — atomic per-file path rewrite `relocateOriginal(assetID:to:)`

The catalog side of one file's move: after the bytes land, rewrite the asset's `original_path`, `volume_identifier`, `availability`, and its `metadata_sync_state.sidecar_path` in one transaction, adopting a freshly-read destination fingerprint. This is `reconnectSourceRoot`'s inner per-asset block (CatalogRepository.swift:1130-1139) hoisted into a public single-asset method, dropping the fingerprint-match gate because *we* are the mover. It re-fingerprints at the destination (rather than assuming size/mtime survived the move) so the catalog stays truthful even across a cross-volume move where mtime could shift.

**Estimated scope:** ~110 LOC including tests.

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (add near `reconnectSourceRoot` at :1097; reuses private `fingerprint(for:)` at :2080, `volumeIdentifier(for:)` at :2090, `updateMetadataSyncSidecarPathIfPresent(assetID:sidecarURL:)` at :2215)
- Test: `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`

**Interfaces:**
- Produces: `CatalogRepository.relocateOriginal(assetID: AssetID, to newOriginalURL: URL) throws` — rewrites the asset row and its sidecar-sync path in one transaction; throws `CatalogError.notFound` for an unknown asset and `TeststripError.io` when the destination file cannot be read.
- Consumes: `XMPSidecarStore().sidecarURL(forOriginalAt:)` (Sources/TeststripCore/Metadata/XMPSidecarStore.swift:17) for the new sidecar path.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripCoreTests/CatalogDatabaseTests.swift`:

```swift
    func testRelocateOriginalRewritesPathFingerprintAndAvailability() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "relocate-original")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let fromURL = directory.appendingPathComponent("from.cr2")
        let toURL = directory.appendingPathComponent("moved/to.cr2")
        try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("photo-bytes".utf8).write(to: toURL)
        let asset = Asset(
            id: AssetID(rawValue: "relocate-me"),
            originalURL: fromURL,
            volumeIdentifier: "Old",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .missing,
            metadata: AssetMetadata(rating: 3, flag: .reject)
        )
        try repository.upsert(asset)

        try repository.relocateOriginal(assetID: asset.id, to: toURL)

        let updated = try repository.asset(id: asset.id)
        XCTAssertEqual(updated.originalURL, toURL)
        XCTAssertEqual(updated.availability, .online)
        XCTAssertEqual(updated.metadata.flag, .reject, "the move must not disturb the reject flag or rating")
        XCTAssertEqual(updated.metadata.rating, 3)
        let attributes = try FileManager.default.attributesOfItem(atPath: toURL.path)
        XCTAssertEqual(updated.fingerprint.size, (attributes[.size] as? NSNumber)?.int64Value)
    }

    func testRelocateOriginalUpdatesPendingSidecarSyncPath() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "relocate-sidecar-path")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let fromURL = directory.appendingPathComponent("from.cr2")
        let toURL = directory.appendingPathComponent("moved/to.cr2")
        try FileManager.default.createDirectory(at: toURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("photo-bytes".utf8).write(to: toURL)
        let asset = Asset(
            id: AssetID(rawValue: "relocate-sidecar"),
            originalURL: fromURL,
            volumeIdentifier: "Old",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)
        try repository.recordMetadataSyncPending(MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: XMPSidecarStore().sidecarURL(forOriginalAt: fromURL),
            catalogGeneration: 1,
            lastSyncedFingerprint: ""
        ))

        try repository.relocateOriginal(assetID: asset.id, to: toURL)

        let pending = try XCTUnwrap(repository.pendingMetadataSyncItem(assetID: asset.id))
        XCTAssertEqual(pending.sidecarURL, XMPSidecarStore().sidecarURL(forOriginalAt: toURL))
    }

    func testRelocateOriginalThrowsWhenDestinationMissing() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "relocate-missing-dest")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "relocate-missing"),
            originalURL: directory.appendingPathComponent("from.cr2"),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try repository.upsert(asset)

        XCTAssertThrowsError(try repository.relocateOriginal(
            assetID: asset.id,
            to: directory.appendingPathComponent("does-not-exist.cr2")
        ))
    }
```

The `MetadataSyncItem` initializer used above is verified against `Sources/TeststripCore/Metadata/MetadataSyncQueue.swift:10` — `init(assetID:sidecarURL:catalogGeneration:lastSyncedFingerprint:lastSyncedAt:)` with `lastSyncedFingerprint: String?` and `lastSyncedAt` defaulted. If it has drifted, adjust the labels to match the real initializer; do not invent labels.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "CatalogDatabaseTests.testRelocateOriginalRewritesPathFingerprintAndAvailability|CatalogDatabaseTests.testRelocateOriginalUpdatesPendingSidecarSyncPath|CatalogDatabaseTests.testRelocateOriginalThrowsWhenDestinationMissing"`
Expected: compile FAILURE — `value of type 'CatalogRepository' has no member 'relocateOriginal'`.

- [ ] **Step 3: Write the minimal implementation**

In `Sources/TeststripCore/Catalog/CatalogRepository.swift`, add after `reconnectSourceRoot(from:to:)`:

```swift
    /// Rewrites one asset's path after Teststrip itself has moved the file's
    /// bytes to `newOriginalURL`. Adopts the destination's fingerprint (rather
    /// than requiring a match) because this is a deliberate, catalog-authored
    /// move, and updates the sidecar sync path so a pending XMP write follows
    /// the file. One transaction: the row and its sync state move together.
    public func relocateOriginal(assetID: AssetID, to newOriginalURL: URL) throws {
        let asset = try asset(id: assetID)
        guard let destinationFingerprint = Self.fingerprint(for: newOriginalURL) else {
            throw TeststripError.io("relocation destination is unreadable \(newOriginalURL.path)")
        }
        try database.transaction {
            var relocatedAsset = asset
            relocatedAsset.originalURL = newOriginalURL
            relocatedAsset.volumeIdentifier = Self.volumeIdentifier(for: newOriginalURL)
            relocatedAsset.fingerprint = destinationFingerprint
            relocatedAsset.availability = .online
            try upsert(relocatedAsset)
            try updateMetadataSyncSidecarPathIfPresent(
                assetID: assetID,
                sidecarURL: XMPSidecarStore().sidecarURL(forOriginalAt: newOriginalURL)
            )
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "CatalogDatabaseTests.testRelocateOriginalRewritesPathFingerprintAndAvailability|CatalogDatabaseTests.testRelocateOriginalUpdatesPendingSidecarSyncPath|CatalogDatabaseTests.testRelocateOriginalThrowsWhenDestinationMissing"`
Expected: PASS

Run: `swift test --filter "CatalogDatabaseTests|MetadataSyncTests"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogRepository.swift Tests/TeststripCoreTests/CatalogDatabaseTests.swift
git commit -m "feat: rewrite catalog path atomically after Teststrip relocates an original"
```

---

### Task 3: Core — destination planner and filesystem move service

The on-disk half: a pure `RejectRelocationPlanner` that maps a set of source originals to collision-safe destination URLs under the common-ancestor-preserving layout (fully testable without touching disk), and a `RejectRelocationService` that moves one original + its adjacent XMP sidecar to a planned destination with rollback if the pair can't complete. The service mirrors `IngestService.copyOriginalFile`/`copyAdjacentSidecar` (Sources/TeststripCore/Ingest/IngestService.swift:336-395) but *moves* instead of copies and rolls back the sidecar if the original move fails, so a partial move never orphans a sidecar or half-moves a pair.

**Estimated scope:** ~300 LOC including tests.

**Files:**
- Create: `Sources/TeststripCore/Relocation/RejectRelocationPlanner.swift`
- Create: `Sources/TeststripCore/Relocation/RejectRelocationService.swift`
- Test: `Tests/TeststripCoreTests/RejectRelocationServiceTests.swift` (new)

**Interfaces:**
- Produces:
  - `RejectRelocationPlanner(destinationRoot: URL)` with `func plan(originals: [URL]) -> [RejectRelocationPlan]`
  - `RejectRelocationPlan` — `Equatable, Sendable`: `originalFrom: URL`, `originalTo: URL`
  - `RejectRelocationService()` with `func move(originalFrom: URL, originalTo: URL) throws -> RejectRelocationMoveResult` and `func moveBack(_ entry: RelocationManifestEntry) throws`
  - `RejectRelocationMoveResult` — `Equatable, Sendable`: `originalFrom`, `originalTo`, `sidecarFrom: URL?`, `sidecarTo: URL?`
- Consumes: `XMPSidecarStore().existingSidecarURL(forOriginalAt:)` (XMPSidecarStore.swift:25), `XMPSidecarStore().sidecarURL(forOriginalAt:)` (:17), `RelocationManifestEntry` (Task 1).

Design notes the implementer must honor:
- The planner computes the longest common ancestor **directory** of all `originals` (via `deletingLastPathComponent().standardizedFileURL.pathComponents` prefix intersection). Each destination is `destinationRoot + (source path relative to the common ancestor)`. A single-folder input degenerates to flat. Collision-safe disambiguation appends `-2`, `-3`, … before the extension, tracking claimed names case-insensitively across the batch **and** checking `FileManager.fileExists` for files already sitting at the destination — same rule as `ExportService.availableDestinationURL` (ExportService.swift:152-167). The planner is pure and does not create directories.
- The service's `move(originalFrom:originalTo:)`:
  1. Resolve the source sidecar via `existingSidecarURL(forOriginalAt: originalFrom)`; the destination sidecar is `sidecarURL(forOriginalAt: originalTo)`.
  2. `createDirectory(at: originalTo.deletingLastPathComponent(), withIntermediateDirectories: true)`.
  3. If a source sidecar exists, `moveItem` it to the destination sidecar first.
  4. `moveItem` the original. If **this** throws, move the sidecar back to its source (best-effort) and rethrow as `TeststripError.io` — leaving no orphan and no half-moved pair.
  5. Return the `RejectRelocationMoveResult` with both from/to (sidecar fields nil when there was no sidecar).
- `moveBack(_ entry:)` reverses: move the original `to → from` (recreating the source directory), and the sidecar `to → from` when present, best-effort symmetric rollback. Skip (no throw) when the `to` file is already absent, so a re-run of "move back" is idempotent.

- [ ] **Step 1: Write the failing tests**

Create `Tests/TeststripCoreTests/RejectRelocationServiceTests.swift`:

```swift
import Foundation
import XCTest
@testable import TeststripCore

final class RejectRelocationServiceTests: XCTestCase {
    func testPlannerPreservesStructureBeneathCommonAncestor() throws {
        let planner = RejectRelocationPlanner(destinationRoot: URL(fileURLWithPath: "/Rejects"))
        let plans = planner.plan(originals: [
            URL(fileURLWithPath: "/Shoot/Day1/a.cr2"),
            URL(fileURLWithPath: "/Shoot/Day2/b.cr2")
        ])
        XCTAssertEqual(plans, [
            RejectRelocationPlan(
                originalFrom: URL(fileURLWithPath: "/Shoot/Day1/a.cr2"),
                originalTo: URL(fileURLWithPath: "/Rejects/Day1/a.cr2")
            ),
            RejectRelocationPlan(
                originalFrom: URL(fileURLWithPath: "/Shoot/Day2/b.cr2"),
                originalTo: URL(fileURLWithPath: "/Rejects/Day2/b.cr2")
            )
        ])
    }

    func testPlannerSingleFolderIsEffectivelyFlat() throws {
        let planner = RejectRelocationPlanner(destinationRoot: URL(fileURLWithPath: "/Rejects"))
        let plans = planner.plan(originals: [
            URL(fileURLWithPath: "/Shoot/a.cr2"),
            URL(fileURLWithPath: "/Shoot/b.cr2")
        ])
        XCTAssertEqual(plans.map(\.originalTo), [
            URL(fileURLWithPath: "/Rejects/a.cr2"),
            URL(fileURLWithPath: "/Rejects/b.cr2")
        ])
    }

    func testPlannerDisambiguatesCollidingBasenames() throws {
        let planner = RejectRelocationPlanner(destinationRoot: URL(fileURLWithPath: "/Rejects"))
        // Both share the common ancestor /Shoot, so both flatten to the same basename.
        let plans = planner.plan(originals: [
            URL(fileURLWithPath: "/Shoot/x.cr2"),
            URL(fileURLWithPath: "/Shoot/x.cr2")
        ])
        XCTAssertEqual(plans.map(\.originalTo), [
            URL(fileURLWithPath: "/Rejects/x.cr2"),
            URL(fileURLWithPath: "/Rejects/x-2.cr2")
        ])
    }

    func testMoveRelocatesOriginalAndSidecarTogether() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "reject-move-pair")
        let source = directory.appendingPathComponent("shoot")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let originalFrom = source.appendingPathComponent("frame.cr2")
        let sidecarFrom = source.appendingPathComponent("frame.cr2.xmp")
        try Data("raw".utf8).write(to: originalFrom)
        try Data("<xmp/>".utf8).write(to: sidecarFrom)
        let originalTo = directory.appendingPathComponent("rejects/frame.cr2")

        let result = try RejectRelocationService().move(originalFrom: originalFrom, originalTo: originalTo)

        XCTAssertFalse(FileManager.default.fileExists(atPath: originalFrom.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarFrom.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalTo.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.sidecarTo?.path ?? "/missing"))
        XCTAssertEqual(result.originalFrom, originalFrom)
        XCTAssertEqual(result.originalTo, originalTo)
        XCTAssertEqual(result.sidecarFrom, sidecarFrom)
    }

    func testMoveWithoutSidecarLeavesSidecarFieldsNil() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "reject-move-solo")
        let originalFrom = directory.appendingPathComponent("solo.jpg")
        try Data("jpeg".utf8).write(to: originalFrom)
        let originalTo = directory.appendingPathComponent("rejects/solo.jpg")

        let result = try RejectRelocationService().move(originalFrom: originalFrom, originalTo: originalTo)

        XCTAssertNil(result.sidecarFrom)
        XCTAssertNil(result.sidecarTo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalTo.path))
    }

    func testMoveBackRestoresBothFiles() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "reject-move-back")
        let rejects = directory.appendingPathComponent("rejects")
        try FileManager.default.createDirectory(at: rejects, withIntermediateDirectories: true)
        let originalTo = rejects.appendingPathComponent("frame.cr2")
        let sidecarTo = rejects.appendingPathComponent("frame.cr2.xmp")
        try Data("raw".utf8).write(to: originalTo)
        try Data("<xmp/>".utf8).write(to: sidecarTo)
        let entry = RelocationManifestEntry(
            assetID: AssetID(rawValue: "back"),
            originalFrom: directory.appendingPathComponent("shoot/frame.cr2"),
            originalTo: originalTo,
            sidecarFrom: directory.appendingPathComponent("shoot/frame.cr2.xmp"),
            sidecarTo: sidecarTo
        )

        try RejectRelocationService().moveBack(entry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.originalFrom.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(entry.sidecarFrom).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalTo.path))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter RejectRelocationServiceTests`
Expected: compile FAILURE — no `RejectRelocationPlanner`, `RejectRelocationPlan`, `RejectRelocationService`, `RejectRelocationMoveResult`.

- [ ] **Step 3: Write the planner and the service**

Create `Sources/TeststripCore/Relocation/RejectRelocationPlanner.swift`:

```swift
import Foundation

public struct RejectRelocationPlan: Equatable, Sendable {
    public var originalFrom: URL
    public var originalTo: URL

    public init(originalFrom: URL, originalTo: URL) {
        self.originalFrom = originalFrom
        self.originalTo = originalTo
    }
}

/// Maps reject originals to destination URLs beneath `destinationRoot`,
/// preserving each file's path relative to the moved set's longest common
/// ancestor directory, with case-insensitive collision disambiguation. Pure:
/// no filesystem side effects.
public struct RejectRelocationPlanner: Sendable {
    public var destinationRoot: URL

    public init(destinationRoot: URL) {
        self.destinationRoot = destinationRoot
    }

    public func plan(originals: [URL]) -> [RejectRelocationPlan] {
        guard !originals.isEmpty else { return [] }
        let ancestorComponents = Self.commonAncestorComponents(of: originals)
        var claimedNames: Set<String> = []
        return originals.map { original in
            let relativeComponents = Array(original.standardizedFileURL.pathComponents.dropFirst(ancestorComponents.count))
            let destination = Self.disambiguatedURL(
                base: destinationRoot,
                relativeComponents: relativeComponents,
                claimedNames: &claimedNames
            )
            return RejectRelocationPlan(originalFrom: original, originalTo: destination)
        }
    }

    private static func commonAncestorComponents(of originals: [URL]) -> [String] {
        let directoryComponentLists = originals.map {
            $0.standardizedFileURL.deletingLastPathComponent().pathComponents
        }
        guard var shared = directoryComponentLists.first else { return [] }
        for components in directoryComponentLists.dropFirst() {
            var prefixLength = 0
            while prefixLength < shared.count,
                  prefixLength < components.count,
                  shared[prefixLength] == components[prefixLength] {
                prefixLength += 1
            }
            shared = Array(shared.prefix(prefixLength))
        }
        return shared
    }

    private static func disambiguatedURL(
        base: URL,
        relativeComponents: [String],
        claimedNames: inout Set<String>
    ) -> URL {
        let directoryComponents = relativeComponents.dropLast()
        var directory = base
        for component in directoryComponents {
            directory = directory.appendingPathComponent(component, isDirectory: true)
        }
        let filename = relativeComponents.last ?? ""
        let baseName = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = filename
        var suffix = 2
        while claimedNames.contains(candidate.lowercased())
            || FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix).\(ext)"
            suffix += 1
        }
        claimedNames.insert(candidate.lowercased())
        return directory.appendingPathComponent(candidate)
    }
}
```

Create `Sources/TeststripCore/Relocation/RejectRelocationService.swift`:

```swift
import Foundation

public struct RejectRelocationMoveResult: Equatable, Sendable {
    public var originalFrom: URL
    public var originalTo: URL
    public var sidecarFrom: URL?
    public var sidecarTo: URL?

    public init(originalFrom: URL, originalTo: URL, sidecarFrom: URL?, sidecarTo: URL?) {
        self.originalFrom = originalFrom
        self.originalTo = originalTo
        self.sidecarFrom = sidecarFrom
        self.sidecarTo = sidecarTo
    }
}

/// Moves one reject original and its adjacent XMP sidecar together, rolling the
/// sidecar back if the original move fails so a partial run never orphans a
/// sidecar or half-moves a pair.
public struct RejectRelocationService: Sendable {
    private let sidecarStore = XMPSidecarStore()

    public init() {}

    public func move(originalFrom: URL, originalTo: URL) throws -> RejectRelocationMoveResult {
        let sidecarFrom = sidecarStore.existingSidecarURL(forOriginalAt: originalFrom)
        let sidecarTo = sidecarFrom == nil ? nil : sidecarStore.sidecarURL(forOriginalAt: originalTo)
        try createDirectory(at: originalTo.deletingLastPathComponent())

        if let sidecarFrom, let sidecarTo {
            try moveItem(from: sidecarFrom, to: sidecarTo)
        }
        do {
            try moveItem(from: originalFrom, to: originalTo)
        } catch {
            if let sidecarFrom, let sidecarTo {
                try? FileManager.default.moveItem(at: sidecarTo, to: sidecarFrom)
            }
            throw error
        }
        return RejectRelocationMoveResult(
            originalFrom: originalFrom,
            originalTo: originalTo,
            sidecarFrom: sidecarFrom,
            sidecarTo: sidecarTo
        )
    }

    public func moveBack(_ entry: RelocationManifestEntry) throws {
        try createDirectory(at: entry.originalFrom.deletingLastPathComponent())
        if let sidecarTo = entry.sidecarTo, let sidecarFrom = entry.sidecarFrom,
           FileManager.default.fileExists(atPath: sidecarTo.path) {
            try moveItem(from: sidecarTo, to: sidecarFrom)
        }
        guard FileManager.default.fileExists(atPath: entry.originalTo.path) else { return }
        try moveItem(from: entry.originalTo, to: entry.originalFrom)
    }

    private func createDirectory(at url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw TeststripError.io("could not create relocation directory \(url.path): \(error.localizedDescription)")
        }
    }

    private func moveItem(from: URL, to: URL) throws {
        do {
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            throw TeststripError.io("could not move \(from.path) to \(to.path): \(error.localizedDescription)")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RejectRelocationServiceTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripCore/Relocation/RejectRelocationPlanner.swift Sources/TeststripCore/Relocation/RejectRelocationService.swift Tests/TeststripCoreTests/RejectRelocationServiceTests.swift
git commit -m "feat: plan and execute reject original+sidecar moves with rollback"
```

---

### Task 4: App — preflight over current-scope rejects

The reviewable half of the safety contract: `rejectRelocationPreflight(destinationFolder:)` computes exactly what a move would do — the reject-flagged assets in the current scope, their total bytes (original + sidecar), how many carry sidecars, a preview of destination paths, and per-file warnings (unavailable original, already inside the destination) — without moving anything. The result feeds a preflight sheet in Task 7. Scope is `currentAssetScopeIDs(repository:)` (AppModel.swift:7755) intersected with `SetQuery(predicates: [.flag(.reject)])` via `assetIDs(ids:matching:)` (CatalogRepository.swift:161), so it honors the folder sidebar / person filter / saved set / rejects filter that produced the current view.

**Estimated scope:** ~210 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (add the preflight computation near `currentAssetScopeIDs` at :7755; place the presentation struct near `ExportCompletionSummary` at :857)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`, `Tests/TeststripAppTests/RejectRelocationPreflightTests.swift` (new)

**Interfaces:**
- Produces:
  - `public struct RejectRelocationPreflight: Equatable, Sendable` with stored `assetIDs: [AssetID]`, `originalURLs: [URL]`, `plans: [RejectRelocationPlan]`, `sidecarCount: Int`, `totalByteCount: Int64`, `unavailableCount: Int`, `alreadyInDestinationCount: Int`, `destinationFolder: URL`, plus computed `var moveCount: Int`, `var confirmationText: String`, `var summaryText: String`, `var destinationPreview: [String]` (up to 8 relative destination paths).
  - `public func rejectRelocationPreflight(destinationFolder: URL) throws -> RejectRelocationPreflight`
- Consumes: `RejectRelocationPlanner` (Task 3), `currentAssetScopeIDs(repository:)` (:7755), `assetIDs(ids:matching:)` (:161), `XMPSidecarStore().existingSidecarURL(forOriginalAt:)`.

Copy specifics for `RejectRelocationPreflight` (match repo separators):
- `confirmationText` = `"Move \(moveCount) reject \(moveCount == 1 ? "photo" : "photos") to \(destinationFolder.lastPathComponent)"`.
- `summaryText` = `"\(moveCount) \(moveCount == 1 ? "file" : "files") · \(sidecarCount) \(sidecarCount == 1 ? "sidecar" : "sidecars") · \(ByteCountFormatter.string(fromByteCount: totalByteCount, countStyle: .file))"` — verify `ByteCountFormatter` usage against any existing byte formatting in the file; if none exists, this is the introduction and is fine.
- `moveCount` excludes assets counted in `unavailableCount` and `alreadyInDestinationCount` (those are reported but not moved).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testRejectRelocationPreflightCountsRejectsSidecarsAndBytesInScope() throws {
        let directory = try makeTemporaryDirectory(named: "reject-preflight")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let rejectOriginal = shoot.appendingPathComponent("reject.cr2")
        let rejectSidecar = shoot.appendingPathComponent("reject.cr2.xmp")
        let keeperOriginal = shoot.appendingPathComponent("keeper.cr2")
        try Data(repeating: 0, count: 100).write(to: rejectOriginal)
        try Data(repeating: 0, count: 20).write(to: rejectSidecar)
        try Data(repeating: 0, count: 100).write(to: keeperOriginal)
        let reject = makeAsset(id: "pf-reject", path: rejectOriginal.path, rating: 0, flag: .reject)
        let keeper = makeAsset(id: "pf-keeper", path: keeperOriginal.path, rating: 4, flag: .pick)
        let (model, _) = try makeModelWithCatalogAssets(named: "reject-preflight-model", assets: [reject, keeper])

        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: directory.appendingPathComponent("rejects", isDirectory: true)
        )

        XCTAssertEqual(preflight.assetIDs, [reject.id])
        XCTAssertEqual(preflight.moveCount, 1)
        XCTAssertEqual(preflight.sidecarCount, 1)
        XCTAssertEqual(preflight.totalByteCount, 120)
        XCTAssertEqual(preflight.confirmationText, "Move 1 reject photo to rejects")
    }

    func testRejectRelocationPreflightRespectsCurrentSetScope() throws {
        let directory = try makeTemporaryDirectory(named: "reject-preflight-scope")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let inScope = shoot.appendingPathComponent("in.cr2")
        let outOfScope = shoot.appendingPathComponent("out.cr2")
        try Data(repeating: 0, count: 10).write(to: inScope)
        try Data(repeating: 0, count: 10).write(to: outOfScope)
        let inScopeReject = makeAsset(id: "scope-in", path: inScope.path, rating: 0, flag: .reject)
        let outOfScopeReject = makeAsset(id: "scope-out", path: outOfScope.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "reject-preflight-scope-model",
            assets: [inScopeReject, outOfScopeReject]
        )
        try repository.upsert(AssetSet.manual(
            id: AssetSetID(rawValue: "only-in"),
            name: "Only In",
            assetIDs: [inScopeReject.id]
        ))
        try model.reload()
        try model.applyAssetSet(id: AssetSetID(rawValue: "only-in"))

        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: directory.appendingPathComponent("rejects", isDirectory: true)
        )

        XCTAssertEqual(preflight.assetIDs, [inScopeReject.id])
    }

    func testRejectRelocationPreflightFlagsUnavailableOriginals() throws {
        let missingReject = makeAsset(
            id: "pf-missing",
            path: "/Volumes/Gone/missing.cr2",
            rating: 0,
            flag: .reject,
            availability: .missing
        )
        let (model, _) = try makeModelWithCatalogAssets(named: "reject-preflight-missing", assets: [missingReject])

        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: URL(fileURLWithPath: "/tmp/rejects", isDirectory: true)
        )

        XCTAssertEqual(preflight.unavailableCount, 1)
        XCTAssertEqual(preflight.moveCount, 0)
    }
```

Add a focused presentation test in `Tests/TeststripAppTests/RejectRelocationPreflightTests.swift`:

```swift
import XCTest
import TeststripCore
@testable import TeststripApp

final class RejectRelocationPreflightTests: XCTestCase {
    func testConfirmationTextSingularizesOnePhoto() {
        let preflight = RejectRelocationPreflight(
            assetIDs: [AssetID(rawValue: "a")],
            originalURLs: [URL(fileURLWithPath: "/Shoot/a.cr2")],
            plans: [RejectRelocationPlan(
                originalFrom: URL(fileURLWithPath: "/Shoot/a.cr2"),
                originalTo: URL(fileURLWithPath: "/Rejects/a.cr2")
            )],
            sidecarCount: 0,
            totalByteCount: 100,
            unavailableCount: 0,
            alreadyInDestinationCount: 0,
            destinationFolder: URL(fileURLWithPath: "/Rejects", isDirectory: true)
        )
        XCTAssertEqual(preflight.confirmationText, "Move 1 reject photo to Rejects")
        XCTAssertEqual(preflight.moveCount, 1)
    }
}
```

(Confirm `RejectRelocationPreflight`'s memberwise initializer is `public` — declare the struct and its stored properties `public` and add an explicit `public init(...)`, since a struct's synthesized memberwise init is `internal`. If the presentation test drives you to expose more computed helpers, add them to the struct rather than the test.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testRejectRelocationPreflightCountsRejectsSidecarsAndBytesInScope|AppModelTests.testRejectRelocationPreflightRespectsCurrentSetScope|AppModelTests.testRejectRelocationPreflightFlagsUnavailableOriginals|RejectRelocationPreflightTests"`
Expected: compile FAILURE — no `RejectRelocationPreflight`, no `rejectRelocationPreflight`.

- [ ] **Step 3: Write the presentation struct and the computation**

In `Sources/TeststripApp/AppModel.swift`, add the struct near `ExportCompletionSummary` (~:857):

```swift
public struct RejectRelocationPreflight: Equatable, Sendable {
    public var assetIDs: [AssetID]
    public var originalURLs: [URL]
    public var plans: [RejectRelocationPlan]
    public var sidecarCount: Int
    public var totalByteCount: Int64
    public var unavailableCount: Int
    public var alreadyInDestinationCount: Int
    public var destinationFolder: URL

    public init(
        assetIDs: [AssetID],
        originalURLs: [URL],
        plans: [RejectRelocationPlan],
        sidecarCount: Int,
        totalByteCount: Int64,
        unavailableCount: Int,
        alreadyInDestinationCount: Int,
        destinationFolder: URL
    ) {
        self.assetIDs = assetIDs
        self.originalURLs = originalURLs
        self.plans = plans
        self.sidecarCount = sidecarCount
        self.totalByteCount = totalByteCount
        self.unavailableCount = unavailableCount
        self.alreadyInDestinationCount = alreadyInDestinationCount
        self.destinationFolder = destinationFolder
    }

    public var moveCount: Int { plans.count }

    public var hasMovableFiles: Bool { moveCount > 0 }

    public var confirmationText: String {
        "Move \(moveCount) reject \(moveCount == 1 ? "photo" : "photos") to \(destinationFolder.lastPathComponent)"
    }

    public var summaryText: String {
        let sidecarText = "\(sidecarCount) \(sidecarCount == 1 ? "sidecar" : "sidecars")"
        let sizeText = ByteCountFormatter.string(fromByteCount: totalByteCount, countStyle: .file)
        return "\(moveCount) \(moveCount == 1 ? "file" : "files") · \(sidecarText) · \(sizeText)"
    }

    public var destinationPreview: [String] {
        plans.prefix(8).map { plan in
            plan.originalTo.path.replacingOccurrences(
                of: destinationFolder.standardizedFileURL.path + "/",
                with: ""
            )
        }
    }

    public var warningText: String? {
        var parts: [String] = []
        if unavailableCount > 0 {
            parts.append("\(unavailableCount) unavailable \(unavailableCount == 1 ? "original is" : "originals are") skipped")
        }
        if alreadyInDestinationCount > 0 {
            parts.append("\(alreadyInDestinationCount) already in the destination")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
```

Add the computation near `currentAssetScopeIDs` (~:7755):

```swift
    public func rejectRelocationPreflight(destinationFolder: URL) throws -> RejectRelocationPreflight {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let scopeIDs = try currentAssetScopeIDs(repository: catalog.repository)
        let rejectIDs = try catalog.repository.assetIDs(
            ids: scopeIDs,
            matching: SetQuery(predicates: [.flag(.reject)])
        )
        let sidecarStore = XMPSidecarStore()
        let destinationRootPath = destinationFolder.standardizedFileURL.path
        var movableAssetIDs: [AssetID] = []
        var movableOriginalURLs: [URL] = []
        var sidecarCount = 0
        var totalByteCount: Int64 = 0
        var unavailableCount = 0
        var alreadyInDestinationCount = 0
        for assetID in rejectIDs {
            let asset = try catalog.repository.asset(id: assetID)
            guard FileManager.default.fileExists(atPath: asset.originalURL.path) else {
                unavailableCount += 1
                continue
            }
            if asset.originalURL.standardizedFileURL.path.hasPrefix(destinationRootPath + "/") {
                alreadyInDestinationCount += 1
                continue
            }
            movableAssetIDs.append(assetID)
            movableOriginalURLs.append(asset.originalURL)
            totalByteCount += Self.fileByteCount(at: asset.originalURL)
            if let sidecarURL = sidecarStore.existingSidecarURL(forOriginalAt: asset.originalURL) {
                sidecarCount += 1
                totalByteCount += Self.fileByteCount(at: sidecarURL)
            }
        }
        let plans = RejectRelocationPlanner(destinationRoot: destinationFolder).plan(originals: movableOriginalURLs)
        return RejectRelocationPreflight(
            assetIDs: movableAssetIDs,
            originalURLs: movableOriginalURLs,
            plans: plans,
            sidecarCount: sidecarCount,
            totalByteCount: totalByteCount,
            unavailableCount: unavailableCount,
            alreadyInDestinationCount: alreadyInDestinationCount,
            destinationFolder: destinationFolder
        )
    }

    private static func fileByteCount(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return 0 }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "AppModelTests.testRejectRelocationPreflightCountsRejectsSidecarsAndBytesInScope|AppModelTests.testRejectRelocationPreflightRespectsCurrentSetScope|AppModelTests.testRejectRelocationPreflightFlagsUnavailableOriginals|RejectRelocationPreflightTests"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift Tests/TeststripAppTests/RejectRelocationPreflightTests.swift
git commit -m "feat: compute a preflight for moving current-scope rejects to a folder"
```

---

### Task 5: App — execute the move (per-file loop, manifest, work session, completion state)

The action itself: given a confirmed preflight, move each file one at a time — bytes first, then that file's catalog row, then that file's manifest entry — recording a `.relocation` work session so the run shows in Activity and skipping-with-issue on any per-file failure. An abort flag checked at the top of each iteration stops the loop cleanly; whatever already moved stays recorded and reversible. On completion the model publishes a summary that Task 7 renders as a banner with a "Move back" button.

**Estimated scope:** ~280 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (published state near `cullingSessionCompletion` at :1220; the action near `rejectRelocationPreflight`; reuse `recordRecentActivity` at :8992, `reload()` at :6764)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces:
  - `public struct RejectRelocationSummary: Equatable, Identifiable, Sendable` — `sessionID: WorkSessionID`, `movedCount: Int`, `sidecarCount: Int`, `skippedCount: Int`, `destinationFolder: URL`; `var id: String { sessionID.rawValue }`; `var detailText: String`.
  - `public private(set) var rejectRelocationSummary: RejectRelocationSummary?`
  - `public private(set) var isRelocatingRejects: Bool`
  - `@discardableResult public func moveRejectsToFolder(_ preflight: RejectRelocationPreflight) throws -> RejectRelocationSummary`
  - `public func abortRejectRelocation()` — sets a flag the loop honors between files.
  - `public func dismissRejectRelocationSummary()`
- Consumes: `RejectRelocationService` (Task 3), `relocateOriginal(assetID:to:)` (Task 2), `saveRelocationManifestEntry(_:sessionID:)` (Task 1), `recordRecentActivity(_:intent:inputSetIDs:outputSetIDs:)` (:8992), `reload()` (:6764), `WorkSessionIssue(kind:sourceURL:message:)` (WorkSession.swift:33). Reuse the existing `.skippedSourceFile` issue kind — do not add a new one.

Implementation requirements the implementer must honor (state them as comments):
- Guard `!isRelocatingRejects` at entry; set/reset with `defer`.
- Generate one `WorkSessionID(rawValue: "relocation-\(UUID().uuidString)")` up front. Save a `WorkSession(kind: .relocation, status: .running, …)` **before** the loop so a mid-run crash still leaves an Activity row and a partial manifest.
- The loop pairs `preflight.assetIDs[i]` with `preflight.plans[i]` (equal length by construction). For each: check the abort flag (break if set); `service.move(...)`; on throw, append a `.skippedSourceFile` `WorkSessionIssue`, `continue` (no catalog change); on success, `relocateOriginal(...)` then `saveRelocationManifestEntry(...)`.
- After the loop, save the session as `.completed` (or `.cancelled` if aborted before finishing) with `failureCount = skipped`, `issues`, and a `detail`. Call `recordRecentActivity(AppWorkActivity(workSession: session))` so it lands in `recentWork` and the sidebar.
- `try reload()` so the grid reflects moved paths, then publish `rejectRelocationSummary` and set `statusMessage`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testMoveRejectsToFolderMovesOriginalsSidecarsAndRewritesCatalog() throws {
        let directory = try makeTemporaryDirectory(named: "move-rejects")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let original = shoot.appendingPathComponent("reject.cr2")
        let sidecar = shoot.appendingPathComponent("reject.cr2.xmp")
        try Data("raw".utf8).write(to: original)
        try Data("<xmp/>".utf8).write(to: sidecar)
        let reject = makeAsset(id: "mv-reject", path: original.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(named: "move-rejects-model", assets: [reject])
        let destination = directory.appendingPathComponent("rejects", isDirectory: true)
        let preflight = try model.rejectRelocationPreflight(destinationFolder: destination)

        let summary = try model.moveRejectsToFolder(preflight)

        XCTAssertEqual(summary.movedCount, 1)
        XCTAssertEqual(summary.sidecarCount, 1)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        let movedOriginal = destination.appendingPathComponent("reject.cr2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedOriginal.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("reject.cr2.xmp").path))
        let updated = try repository.asset(id: reject.id)
        XCTAssertEqual(updated.originalURL, movedOriginal)
        XCTAssertEqual(updated.availability, .online)
        XCTAssertEqual(updated.metadata.flag, .reject)
    }

    func testMoveRejectsRecordsAReversibleManifestAndActivity() throws {
        let directory = try makeTemporaryDirectory(named: "move-rejects-manifest")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let original = shoot.appendingPathComponent("reject.cr2")
        try Data("raw".utf8).write(to: original)
        let reject = makeAsset(id: "mf-reject", path: original.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(named: "move-rejects-manifest-model", assets: [reject])
        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: directory.appendingPathComponent("rejects", isDirectory: true)
        )

        let summary = try model.moveRejectsToFolder(preflight)

        let entries = try repository.relocationManifestEntries(sessionID: summary.sessionID)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.assetID, reject.id)
        XCTAssertEqual(entries.first?.originalFrom, original)
        XCTAssertEqual(try repository.session(id: summary.sessionID).kind, .relocation)
        XCTAssertTrue(model.recentWork.contains { $0.id == summary.sessionID.rawValue })
        XCTAssertEqual(model.rejectRelocationSummary?.sessionID, summary.sessionID)
    }

    func testMoveRejectsSkipsUnwritableDestinationWithoutTouchingCatalog() throws {
        let directory = try makeTemporaryDirectory(named: "move-rejects-skip")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let goodOriginal = shoot.appendingPathComponent("good.cr2")
        let blockedOriginal = shoot.appendingPathComponent("blocked.cr2")
        try Data("raw".utf8).write(to: goodOriginal)
        try Data("raw".utf8).write(to: blockedOriginal)
        let good = makeAsset(id: "skip-good", path: goodOriginal.path, rating: 0, flag: .reject)
        let blocked = makeAsset(id: "skip-blocked", path: blockedOriginal.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(named: "move-rejects-skip-model", assets: [good, blocked])
        // Occupy the blocked destination with a directory sharing its target filename so its moveItem throws.
        let destination = directory.appendingPathComponent("rejects", isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination.appendingPathComponent("blocked.cr2"),
            withIntermediateDirectories: true
        )
        let preflight = try model.rejectRelocationPreflight(destinationFolder: destination)

        let summary = try model.moveRejectsToFolder(preflight)

        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.movedCount, 1)
        // The blocked asset keeps its original catalog path; the good one moved.
        XCTAssertEqual(try repository.asset(id: blocked.id).originalURL, blockedOriginal)
        XCTAssertNotEqual(try repository.asset(id: good.id).originalURL, goodOriginal)
    }
```

Before running, confirm the collision test actually forces a throw: the planner's disambiguation checks `fileExists`, so a pre-existing directory at `blocked.cr2` would be side-stepped to `blocked-2.cr2` and NOT throw. Adjust the test to guarantee a real move failure instead — e.g. make the destination path unwritable by pointing `destinationFolder` at a location whose parent is a regular file, or drop this specific assertion approach and instead delete the source original between preflight and move so `service.move` throws `couldn't move` — pick whichever reliably produces a per-file `moveItem` failure on the test platform, and keep the assertion that the skipped asset's catalog path is untouched.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testMoveRejectsToFolderMovesOriginalsSidecarsAndRewritesCatalog|AppModelTests.testMoveRejectsRecordsAReversibleManifestAndActivity|AppModelTests.testMoveRejectsSkipsUnwritableDestinationWithoutTouchingCatalog"`
Expected: compile FAILURE — no `moveRejectsToFolder`, no `rejectRelocationSummary`.

- [ ] **Step 3: Write the implementation**

In `Sources/TeststripApp/AppModel.swift`, add the summary type near `RejectRelocationPreflight`:

```swift
public struct RejectRelocationSummary: Equatable, Identifiable, Sendable {
    public var sessionID: WorkSessionID
    public var movedCount: Int
    public var sidecarCount: Int
    public var skippedCount: Int
    public var destinationFolder: URL

    public var id: String { sessionID.rawValue }

    public var detailText: String {
        let movedText = "Moved \(movedCount) reject \(movedCount == 1 ? "photo" : "photos") to \(destinationFolder.lastPathComponent)"
        guard skippedCount > 0 else { return movedText }
        return "\(movedText) · \(skippedCount) skipped"
    }
}
```

Add published state near `cullingSessionCompletion` (:1220):

```swift
    public private(set) var rejectRelocationSummary: RejectRelocationSummary?
    public private(set) var isRelocatingRejects = false
    private var rejectRelocationAbortRequested = false
```

Add the action near `rejectRelocationPreflight`:

```swift
    @discardableResult
    public func moveRejectsToFolder(_ preflight: RejectRelocationPreflight) throws -> RejectRelocationSummary {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard !isRelocatingRejects else {
            throw TeststripError.invalidState("a relocation is already running")
        }
        isRelocatingRejects = true
        rejectRelocationAbortRequested = false
        defer { isRelocatingRejects = false }

        let sessionID = WorkSessionID(rawValue: "relocation-\(UUID().uuidString)")
        let service = RejectRelocationService()
        // Persist a running session before the loop so a crash still leaves an
        // Activity row and a partial, reversible manifest.
        try catalog.repository.save(Self.relocationWorkSession(
            id: sessionID,
            status: .running,
            destinationFolder: preflight.destinationFolder,
            movedCount: 0,
            skippedCount: 0,
            issues: []
        ))

        var movedCount = 0
        var sidecarCount = 0
        var issues: [WorkSessionIssue] = []
        for (assetID, plan) in zip(preflight.assetIDs, preflight.plans) {
            if rejectRelocationAbortRequested { break }
            do {
                let result = try service.move(originalFrom: plan.originalFrom, originalTo: plan.originalTo)
                try catalog.repository.relocateOriginal(assetID: assetID, to: result.originalTo)
                try catalog.repository.saveRelocationManifestEntry(
                    RelocationManifestEntry(
                        assetID: assetID,
                        originalFrom: result.originalFrom,
                        originalTo: result.originalTo,
                        sidecarFrom: result.sidecarFrom,
                        sidecarTo: result.sidecarTo
                    ),
                    sessionID: sessionID
                )
                movedCount += 1
                if result.sidecarTo != nil { sidecarCount += 1 }
            } catch {
                issues.append(WorkSessionIssue(
                    kind: .skippedSourceFile,
                    sourceURL: plan.originalFrom,
                    message: error.localizedDescription
                ))
            }
        }

        let finalStatus: WorkSessionStatus = rejectRelocationAbortRequested ? .cancelled : .completed
        let session = Self.relocationWorkSession(
            id: sessionID,
            status: finalStatus,
            destinationFolder: preflight.destinationFolder,
            movedCount: movedCount,
            skippedCount: issues.count,
            issues: issues
        )
        try catalog.repository.save(session)
        recordRecentActivity(AppWorkActivity(workSession: session))
        try reload()

        let summary = RejectRelocationSummary(
            sessionID: sessionID,
            movedCount: movedCount,
            sidecarCount: sidecarCount,
            skippedCount: issues.count,
            destinationFolder: preflight.destinationFolder
        )
        rejectRelocationSummary = summary
        statusMessage = summary.detailText
        return summary
    }

    public func abortRejectRelocation() {
        rejectRelocationAbortRequested = true
    }

    public func dismissRejectRelocationSummary() {
        rejectRelocationSummary = nil
    }

    private static func relocationWorkSession(
        id: WorkSessionID,
        status: WorkSessionStatus,
        destinationFolder: URL,
        movedCount: Int,
        skippedCount: Int,
        issues: [WorkSessionIssue]
    ) -> WorkSession {
        WorkSession(
            id: id,
            kind: .relocation,
            intent: "move-rejects-to-folder",
            title: "Move rejects to \(destinationFolder.lastPathComponent)",
            detail: "Moved \(movedCount) · skipped \(skippedCount)",
            status: status,
            inputSetIDs: [],
            outputSetIDs: [],
            completedUnitCount: movedCount,
            totalUnitCount: movedCount + skippedCount,
            failureCount: skippedCount,
            issues: issues,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
```

(Note: `recordRecentActivity` re-saves the session via `AppWorkActivity.workSession(...)` (AppModel.swift:10126). That round-trip is verified to preserve `kind`, `status`, `issues`, and `failureCount` — `AppWorkActivity(workSession:)` at :820 copies them and `workSession(...)` copies them back — so the double-save keeps `kind: .relocation`. It does reset `createdAt`/`updatedAt` to "now", which is acceptable for an Activity row. Since we call `recordRecentActivity` AFTER `catalog.repository.save(session)`, the Activity re-save simply overwrites with an equivalent row.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "AppModelTests.testMoveRejectsToFolderMovesOriginalsSidecarsAndRewritesCatalog|AppModelTests.testMoveRejectsRecordsAReversibleManifestAndActivity|AppModelTests.testMoveRejectsSkipsUnwritableDestinationWithoutTouchingCatalog"`
Expected: PASS

Run: `swift test --filter AppModelTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: move current-scope rejects to a folder with a reversible manifest"
```

---

### Task 6: App — reverse a relocation (Move back)

The reversal that makes the whole feature safe to try: replay a session's manifest in reverse, moving each original (and sidecar) back and rewriting the catalog to the source path via `relocateOriginal`. Skip-with-issue per file (the current file already gone, the source path re-occupied), and on full success delete the manifest and clear the summary banner.

**Estimated scope:** ~150 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (near `moveRejectsToFolder`)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces: `@discardableResult public func moveBackRelocation(sessionID: WorkSessionID) throws -> Int` — returns the count moved back; deletes the manifest and clears `rejectRelocationSummary` when nothing was skipped.
- Consumes: `relocationManifestEntries(sessionID:)` (Task 1), `RejectRelocationService.moveBack(_:)` (Task 3), `relocateOriginal(assetID:to:)` (Task 2), `deleteRelocationManifest(sessionID:)` (Task 1), `reload()`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/TeststripAppTests/AppModelTests.swift`:

```swift
    func testMoveBackRelocationRestoresFilesAndCatalogPaths() throws {
        let directory = try makeTemporaryDirectory(named: "move-back")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let original = shoot.appendingPathComponent("reject.cr2")
        let sidecar = shoot.appendingPathComponent("reject.cr2.xmp")
        try Data("raw".utf8).write(to: original)
        try Data("<xmp/>".utf8).write(to: sidecar)
        let reject = makeAsset(id: "mb-reject", path: original.path, rating: 0, flag: .reject)
        let (model, repository) = try makeModelWithCatalogAssets(named: "move-back-model", assets: [reject])
        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: directory.appendingPathComponent("rejects", isDirectory: true)
        )
        let summary = try model.moveRejectsToFolder(preflight)
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))

        let restored = try model.moveBackRelocation(sessionID: summary.sessionID)

        XCTAssertEqual(restored, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
        XCTAssertEqual(try repository.asset(id: reject.id).originalURL, original)
        XCTAssertEqual(try repository.relocationManifestEntries(sessionID: summary.sessionID), [])
        XCTAssertNil(model.rejectRelocationSummary)
    }

    func testMoveBackRelocationIsIdempotentWhenAlreadyRestored() throws {
        let directory = try makeTemporaryDirectory(named: "move-back-twice")
        let shoot = directory.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: shoot, withIntermediateDirectories: true)
        let original = shoot.appendingPathComponent("reject.cr2")
        try Data("raw".utf8).write(to: original)
        let reject = makeAsset(id: "mb2-reject", path: original.path, rating: 0, flag: .reject)
        let (model, _) = try makeModelWithCatalogAssets(named: "move-back-twice-model", assets: [reject])
        let preflight = try model.rejectRelocationPreflight(
            destinationFolder: directory.appendingPathComponent("rejects", isDirectory: true)
        )
        let summary = try model.moveRejectsToFolder(preflight)
        _ = try model.moveBackRelocation(sessionID: summary.sessionID)

        // Manifest already deleted; a second call restores nothing and does not throw.
        XCTAssertEqual(try model.moveBackRelocation(sessionID: summary.sessionID), 0)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "AppModelTests.testMoveBackRelocationRestoresFilesAndCatalogPaths|AppModelTests.testMoveBackRelocationIsIdempotentWhenAlreadyRestored"`
Expected: compile FAILURE — no `moveBackRelocation`.

- [ ] **Step 3: Write the implementation**

In `Sources/TeststripApp/AppModel.swift`, add near `moveRejectsToFolder`:

```swift
    @discardableResult
    public func moveBackRelocation(sessionID: WorkSessionID) throws -> Int {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        let entries = try catalog.repository.relocationManifestEntries(sessionID: sessionID)
        guard !entries.isEmpty else { return 0 }
        let service = RejectRelocationService()
        var restoredCount = 0
        var skippedCount = 0
        // Reverse order so nested-directory recreations undo cleanly.
        for entry in entries.reversed() {
            do {
                try service.moveBack(entry)
                if FileManager.default.fileExists(atPath: entry.originalFrom.path) {
                    try catalog.repository.relocateOriginal(assetID: entry.assetID, to: entry.originalFrom)
                    restoredCount += 1
                } else {
                    skippedCount += 1
                }
            } catch {
                skippedCount += 1
                errorMessage = error.localizedDescription
            }
        }
        if skippedCount == 0 {
            try catalog.repository.deleteRelocationManifest(sessionID: sessionID)
            if rejectRelocationSummary?.sessionID == sessionID {
                rejectRelocationSummary = nil
            }
        }
        try reload()
        statusMessage = "Moved back \(restoredCount) \(restoredCount == 1 ? "photo" : "photos")"
        return restoredCount
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "AppModelTests.testMoveBackRelocationRestoresFilesAndCatalogPaths|AppModelTests.testMoveBackRelocationIsIdempotentWhenAlreadyRestored"`
Expected: PASS

Run: `swift test --filter AppModelTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/AppModelTests.swift
git commit -m "feat: reverse a reject relocation from its manifest"
```

---

### Task 7: UI — command, preflight sheet, confirmation gate, move-back banner

The surface: a "Move rejects to folder…" toolbar command that opens a preflight sheet (count, size, sidecar tally, destination preview, warnings), gates the move behind a count-naming confirmation checkbox exactly like the all-catalog export toggle (LibraryGridView.swift:1006-1009), and after the move shows a summary banner carrying a "Move back" button. Presentation-model tests only — no snapshot tests.

**Estimated scope:** ~200 LOC including tests.

**Files:**
- Modify: `Sources/TeststripApp/FolderSelectionPanel.swift` (add `chooseRejectDestinationFolder` mirroring `chooseExportDestinationFolder` at :60-70, with its own remembered-directory key)
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (toolbar button + `@State` near the export state at :25-28; preflight sheet; summary banner in `LoupeView`/grid footer)
- Test: `Tests/TeststripAppTests/RejectRelocationPreflightTests.swift` (extend with a sheet-presentation struct test)

**Interfaces:**
- Consumes: `model.rejectRelocationPreflight(destinationFolder:)` (Task 4), `model.moveRejectsToFolder(_:)` (Task 5), `model.moveBackRelocation(sessionID:)` (Task 6), `model.rejectRelocationSummary` (Task 5), `model.isRelocatingRejects` (Task 5), `FolderSelectionPanel.chooseRejectDestinationFolder()` (this task).
- Produces (optional but recommended for testability): a small `RejectRelocationSheetPresentation` struct that turns a `RejectRelocationPreflight?` + confirmation-bool into `titleText`/`summaryText`/`destinationPreviewRows`/`isMoveEnabled`/`moveButtonTitle`, so the enable/confirm logic has an XCTest instead of living only in the view.

Design specifics:
- The command belongs in the same toolbar `ToolbarItemGroup` as Export/Batch Metadata (LibraryGridView.swift:190-201). Disable it when `isImporting || model.assets.isEmpty || model.isRelocatingRejects`. Label: `Label("Move Rejects", systemImage: "tray.and.arrow.down")` with `.help("Move reject-flagged photos in the current view to a folder")`.
- Tapping it calls `FolderSelectionPanel.chooseRejectDestinationFolder()`; on a chosen URL, compute `try model.rejectRelocationPreflight(destinationFolder:)` into a `@State var rejectRelocationPreflight: RejectRelocationPreflight?` and present a sheet.
- Sheet content: title `"Move rejects to \(preflight.destinationFolder.lastPathComponent)"`, `preflight.summaryText`, a scrolling `preflight.destinationPreview` list (relative paths), `preflight.warningText` when present, a confirmation `Toggle(preflight.confirmationText, isOn: $isRejectRelocationConfirmed)`, a Cancel button, and a primary `Button(preflight.confirmationText)` disabled unless `preflight.hasMovableFiles && isRejectRelocationConfirmed`. The primary action calls `try model.moveRejectsToFolder(preflight)`, dismisses the sheet, and resets the confirmation toggle. Route thrown errors to `model.errorMessage` (match the existing `chooseExportDestinationAndExport` do/catch at LibraryGridView.swift:2686-...).
- Summary banner: reuse the `CullingCompletionBannerView` visual pattern (LibraryGridView.swift:2746-2795). When `model.rejectRelocationSummary != nil`, show `summary.detailText`, a `Button("Move back") { try? model.moveBackRelocation(sessionID: summary.sessionID) }`, and a `Button("Dismiss") { model.dismissRejectRelocationSummary() }`. Place it in the grid footer inset so it shows regardless of loupe/grid mode (the culling banner is loupe/compare-only; this action runs from the grid toolbar, so anchor it in the shared footer near `footer` at LibraryGridView.swift:207).

- [ ] **Step 1: Write the failing test**

Extend `Tests/TeststripAppTests/RejectRelocationPreflightTests.swift`:

```swift
    func testSheetPresentationDisablesMoveUntilConfirmed() {
        let preflight = RejectRelocationPreflight(
            assetIDs: [AssetID(rawValue: "a")],
            originalURLs: [URL(fileURLWithPath: "/Shoot/a.cr2")],
            plans: [RejectRelocationPlan(
                originalFrom: URL(fileURLWithPath: "/Shoot/a.cr2"),
                originalTo: URL(fileURLWithPath: "/Rejects/a.cr2")
            )],
            sidecarCount: 0,
            totalByteCount: 100,
            unavailableCount: 0,
            alreadyInDestinationCount: 0,
            destinationFolder: URL(fileURLWithPath: "/Rejects", isDirectory: true)
        )
        XCTAssertFalse(RejectRelocationSheetPresentation(preflight: preflight, isConfirmed: false).isMoveEnabled)
        XCTAssertTrue(RejectRelocationSheetPresentation(preflight: preflight, isConfirmed: true).isMoveEnabled)
        XCTAssertEqual(RejectRelocationSheetPresentation(preflight: preflight, isConfirmed: true).destinationPreviewRows, ["a.cr2"])
    }

    func testSheetPresentationDisablesMoveWhenNothingMovable() {
        let empty = RejectRelocationPreflight(
            assetIDs: [],
            originalURLs: [],
            plans: [],
            sidecarCount: 0,
            totalByteCount: 0,
            unavailableCount: 2,
            alreadyInDestinationCount: 0,
            destinationFolder: URL(fileURLWithPath: "/Rejects", isDirectory: true)
        )
        XCTAssertFalse(RejectRelocationSheetPresentation(preflight: empty, isConfirmed: true).isMoveEnabled)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "RejectRelocationPreflightTests.testSheetPresentationDisablesMoveUntilConfirmed|RejectRelocationPreflightTests.testSheetPresentationDisablesMoveWhenNothingMovable"`
Expected: compile FAILURE — no `RejectRelocationSheetPresentation`.

- [ ] **Step 3: Add the presentation struct, the folder chooser, and the view wiring**

Add `RejectRelocationSheetPresentation` to `Sources/TeststripApp/LibraryGridView.swift` (near `ExportReviewPresentation` at :3897):

```swift
struct RejectRelocationSheetPresentation: Equatable {
    var titleText: String
    var summaryText: String
    var warningText: String?
    var destinationPreviewRows: [String]
    var isMoveEnabled: Bool
    var moveButtonTitle: String

    init(preflight: RejectRelocationPreflight, isConfirmed: Bool) {
        titleText = "Move rejects to \(preflight.destinationFolder.lastPathComponent)"
        summaryText = preflight.summaryText
        warningText = preflight.warningText
        destinationPreviewRows = preflight.destinationPreview
        isMoveEnabled = preflight.hasMovableFiles && isConfirmed
        moveButtonTitle = preflight.confirmationText
    }
}
```

In `Sources/TeststripApp/FolderSelectionPanel.swift`, add a `rejectDestinationParentKey` constant and a `chooseRejectDestinationFolder`/`configureRejectDestinationPanel` pair mirroring the export chooser (:60-70, :132-145), with prompt `"Move Here"` and message `"Select where reject photos should be moved."`.

Wire the toolbar button, the `@State` (`rejectRelocationPreflight: RejectRelocationPreflight?`, `isRejectRelocationConfirmed = false`), the `.sheet(item:)` (make `RejectRelocationPreflight` `Identifiable` by adding `public var id: String { destinationFolder.path }` if needed for `sheet(item:)`, or drive it with a `@State var isShowingRejectRelocation: Bool` + a separate optional — match whichever sheet-presentation idiom the file already uses for the export/import sheets), and the footer banner as described above. Route all thrown calls into `model.errorMessage`.

- [ ] **Step 4: Run test to verify it passes, then build the app target**

Run: `swift test --filter RejectRelocationPreflightTests`
Expected: PASS

Run: `swift build`
Expected: build succeeds (the view wiring compiles).

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/FolderSelectionPanel.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/RejectRelocationPreflightTests.swift
git commit -m "feat: add the Move rejects to folder command, preflight sheet, and move-back banner"
```

---

### Final verification

- [ ] **Full suite**

Run: `swift build && swift test`
Expected: build succeeds; all tests PASS.

- [ ] **Headless workflow ladder**

Run: `./script/verify_headless_workflows.sh`
Expected: PASS (no regression from the new relocation surface).

---

## RAW+JPEG pairing note (read before implementing)

Teststrip has **no** RAW+JPEG pair concept: every file on disk is its own `Asset` (Sources/TeststripCore/Domain/Asset.swift). A RAW and a JPEG shot together are two independent assets that happen to share a basename and a capture time. Stacks (`AssetStackBuilder`, Sources/TeststripCore/Search/AssetStackBuilder.swift) group frames by capture-time proximity or visual similarity within a folder; they are not RAW/JPEG pairs. Consequences this plan relies on and the implementer must not "fix":

- **The action operates on files whose asset carries `flag == .reject`.** A RAW+JPEG pair rated together during culling gets both frames flagged reject (the culling gestures flag the selected/decided asset), so both move independently — each as its own preflight row, catalog rewrite, and manifest entry. A pair where only one variant was flagged moves only that variant. This is correct and intended: the unit of the move is the flagged file, not a synthetic pair.
- **The only "companion" the move keeps physically together is the XMP sidecar** (`frame.cr2.xmp` or Adobe-style `frame.xmp`), resolved per original via `XMPSidecarStore.existingSidecarURL` and moved in the same `service.move` call. A JPEG sibling of a RAW is a *separate asset*, not a sidecar, and is moved only if it too is flagged reject.

Document this behavior in the preflight sheet copy if space allows (e.g. the sidecar tally already communicates "sidecars come along"); do not attempt to auto-include an unflagged RAW/JPEG sibling.

## Deferred (explicitly out of this plan)

- **Batch progress UI during a large move.** The loop publishes a final summary; a live per-file progress bar (like import) is a follow-up if a real move feels slow. `isRelocatingRejects` is exposed so a spinner can be added without new model work.
- **Move-back from Activity history.** This plan clears the summary banner as the move-back entry point and keeps the manifest until reversed; surfacing a "Move back" affordance on old `.relocation` rows in the Activity list is a follow-up (the manifest and `moveBackRelocation(sessionID:)` already support it).
- **Relocating non-reject scopes** (move picks, move a color label). Out of scope; the plumbing generalizes but YAGNI.
- **A dedicated "Rejects" smart filter.** The action already composes with `.flag(.reject)` scoping; a one-click rejects view is a separate small feature.

## Self-Review Notes

- **Safety-contract coverage:** preflight naming the count → Task 4 + Task 7 confirmation gate; per-file-move-then-per-file-catalog-update → Task 5 loop ordering (Global Constraints); skip-with-issue → Task 5 `catch` appends `.skippedSourceFile` and `continue`; abortable → Task 5 `rejectRelocationAbortRequested` checked at loop top; never-looks-external → Task 2 rewrites path + fingerprint + `.online` in one transaction; reversible → Tasks 1/3/6 manifest + `moveBack`; sidecars move with originals → Task 3 `service.move` sidecar-first with rollback; originals-never-modified-except-here → this is the confirm-gated exception the alpha design authorizes.
- **Type consistency:** `RelocationManifestEntry` fields match across Tasks 1/3/5/6; `RejectRelocationPlan` produced by the planner (Task 3) and consumed by preflight (Task 4) and execute (Task 5) with identical shape; `RejectRelocationPreflight` init is the same in Tasks 4/5/6/7 tests; `RejectRelocationSummary.sessionID` links Task 5 output to Task 6 input and Task 7 banner.
- **No invented APIs:** every consumed signature was verified against `main@240f19a` — `currentAssetScopeIDs(repository:)` (:7755), `assetIDs(ids:matching:)` (CatalogRepository:161), `updateMetadataSyncSidecarPathIfPresent` (:2215), `fingerprint(for:)` (:2080), `volumeIdentifier(for:)` (:2090), `XMPSidecarStore.existingSidecarURL`/`sidecarURL` (:25/:17), `recordRecentActivity` (:8992), `reload()` (:6764), `WorkSessionIssue(kind:sourceURL:message:)` (WorkSession:33). The two spots flagged for the implementer to re-verify before relying on them are the `MetadataSyncItem` initializer labels (Task 2 test) and `AppWorkActivity.workSession(...)` round-trip of `kind`/`issues` (Task 5) — both called out inline.
- **Migration safety:** `relocation_manifest_entries` is a `CREATE TABLE IF NOT EXISTS` added to the idempotent statement list with `version` bumped to 15 (CatalogDatabase applies all statements every open); no destructive `ALTER`.
