# RAW + JPEG Bonding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bond a RAW file and its sibling JPEG (same shot) into one logical asset — one tile you cull/rate/keyword/assign-people to, backed by two files, RAW as primary.

**Architecture:** A nullable `bonded_to_asset_id` on `assets` (JPEG secondary → RAW primary). A pure pairing planner computes bonds by folder+stem; a backfill migration retro-pairs the library and import pairs incrementally. Display listing/count queries hide secondaries; processing queues and fetch-by-id do not. File-moving operations carry the bonded file along.

**Tech Stack:** Swift 6, SwiftPM, SQLite. Core in `Sources/TeststripCore`, app in `Sources/TeststripApp`, tests in `Tests/TeststripCoreTests` / `Tests/TeststripAppTests` (`@testable import`).

**Reference:** the design spec at `docs/superpowers/specs/2026-07-15-raw-jpeg-bonding-design.md`.

## Global Constraints

- **Approach is decided:** bonded pair, RAW primary — NOT a one-row merge. Keep both rows; the JPEG (secondary) carries `bonded_to_asset_id` = the RAW's id; primaries and unpaired assets are NULL.
- **RAW is never demoted:** a RAW file is never made a hidden secondary. Only working stills (`ImageIODecodeProvider.workingStillExtensions`) become secondaries, and only when a RAW shares their folder+stem.
- **Sidecar is RAW-only:** all user metadata stays on the RAW primary and mirrors to the RAW's `.xmp` exactly as today. The hidden JPEG is never independently edited; **no** sidecar mirroring to the JPEG.
- **Which queries filter, which don't:** user-facing *listing* and *count* queries exclude secondaries (`bonded_to_asset_id IS NULL`); processing/enqueue paths (preview generation, evaluation) and fetch-by-explicit-id do NOT filter — the JPEG is hidden from view, not removed from processing.
- **File-op fan-out is a correctness requirement:** moving/trashing a rejected bonded shot moves/trashes BOTH files (else the hidden JPEG orphans in place).
- **Provenance invariants unchanged:** bonding writes no `.xmp` and never modifies original bytes; user edits remain `origin='user'`, AI labels `origin='ai'` (tentative, never sidecar'd). A tentative-only reject still never relocates.
- Smallest reasonable change; match surrounding style. No vacuous tests; no tests of trivially-true behavior. The final gate is `make verify` (controller runs it — note: in a worktree, symlink the gitignored `sample-data/photos` and `sample-data/models` from the main checkout first, and remove them before cleanup).
- Every user-facing change gets a scenario card under `test/scenarios/` (authored, not run — VM+AuraFace bound).

## Extension taxonomy (used by the pairing rule)

`ImageIODecodeProvider` (`Sources/TeststripCore/Decode/ImageIODecodeProvider.swift`), all `public static let Set<String>`:
- `rawExtensions` — dng/cr2/cr3/nef/arw/… (a file is RAW iff its lowercased extension is in here; same test as `Asset.isRawOriginal`).
- `workingStillExtensions` — jpg/jpeg/heic/heif/tif/tiff/png.

---

### Task 1: `bonded_to_asset_id` column + pairing planner + repository accessors

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogMigrations.swift` (bump `version`)
- Modify: `Sources/TeststripCore/Catalog/CatalogDatabase.swift:35` (`migrate()` — add the column)
- Create: `Sources/TeststripCore/People/AssetBondPlanner.swift` — pure pairing (put in a new `Bonding/` dir if preferred; keep it in Core)
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (bond accessors)
- Create: `Tests/TeststripCoreTests/AssetBondPlannerTests.swift`
- Create: `Tests/TeststripCoreTests/CatalogBondingTests.swift`

**Interfaces:**
- Produces:
  - `enum AssetBondPlanner { static func bonds(for assets: [BondInput]) -> [AssetID: AssetID] }` where `struct BondInput { let id: AssetID; let originalURL: URL }`, returning `secondaryID → primaryID`.
  - `CatalogRepository.setBond(secondaryID: AssetID, primaryID: AssetID?) throws`
  - `CatalogRepository.bondedPrimaryID(of: AssetID) throws -> AssetID?`
  - `CatalogRepository.bondedSecondaryIDs(of primaryID: AssetID) throws -> [AssetID]`
  - `CatalogRepository.assetIDsWithBondedSecondaries() throws -> Set<AssetID>` (for the badge)

- [ ] **Step 1: Write the failing planner test**

Create `Tests/TeststripCoreTests/AssetBondPlannerTests.swift`:

```swift
import XCTest
@testable import TeststripCore

final class AssetBondPlannerTests: XCTestCase {
    private func input(_ id: String, _ path: String) -> AssetBondPlanner.BondInput {
        AssetBondPlanner.BondInput(id: AssetID(rawValue: id), originalURL: URL(fileURLWithPath: path))
    }

    func testBondsWorkingStillToRawBySameFolderAndStem() {
        let bonds = AssetBondPlanner.bonds(for: [
            input("raw", "/photos/IMG_1.CR3"),
            input("jpg", "/photos/IMG_1.JPG"),
        ])
        XCTAssertEqual(bonds, [AssetID(rawValue: "jpg"): AssetID(rawValue: "raw")])
    }

    func testBondsBothWorkingStillsToTheRaw() {
        let bonds = AssetBondPlanner.bonds(for: [
            input("raw", "/p/IMG_1.CR3"),
            input("jpg", "/p/IMG_1.JPG"),
            input("heic", "/p/IMG_1.HEIC"),
        ])
        XCTAssertEqual(bonds, [
            AssetID(rawValue: "jpg"): AssetID(rawValue: "raw"),
            AssetID(rawValue: "heic"): AssetID(rawValue: "raw"),
        ])
    }

    func testNoRawInStemGroupProducesNoBonds() {
        let bonds = AssetBondPlanner.bonds(for: [
            input("a", "/p/IMG_1.JPG"),
            input("b", "/p/IMG_1.HEIC"),
        ])
        XCTAssertTrue(bonds.isEmpty)
    }

    func testDifferentFoldersDoNotBond() {
        let bonds = AssetBondPlanner.bonds(for: [
            input("raw", "/a/IMG_1.CR3"),
            input("jpg", "/b/IMG_1.JPG"),
        ])
        XCTAssertTrue(bonds.isEmpty)
    }

    func testMultipleRawsNeverHideARaw() {
        // Two RAWs + one still sharing a stem: the still bonds to a deterministic
        // primary RAW; neither RAW is bonded (a RAW is never a hidden secondary).
        let bonds = AssetBondPlanner.bonds(for: [
            input("cr3", "/p/IMG_1.CR3"),
            input("dng", "/p/IMG_1.DNG"),
            input("jpg", "/p/IMG_1.JPG"),
        ])
        XCTAssertNil(bonds[AssetID(rawValue: "cr3")])
        XCTAssertNil(bonds[AssetID(rawValue: "dng")])
        // still bonds to the first RAW by sorted original_path (/p/IMG_1.CR3 < /p/IMG_1.DNG)
        XCTAssertEqual(bonds[AssetID(rawValue: "jpg")], AssetID(rawValue: "cr3"))
    }

    func testCaseInsensitiveStemAndExtension() {
        let bonds = AssetBondPlanner.bonds(for: [
            input("raw", "/p/img_1.cr3"),
            input("jpg", "/p/IMG_1.jpg"),
        ])
        XCTAssertEqual(bonds, [AssetID(rawValue: "jpg"): AssetID(rawValue: "raw")])
    }
}
```

- [ ] **Step 2: Run, verify it fails to compile** — `swift test --filter AssetBondPlannerTests` → FAIL (`AssetBondPlanner` undefined).

- [ ] **Step 3: Implement the pure planner**

Create `Sources/TeststripCore/People/AssetBondPlanner.swift`:

```swift
import Foundation

/// Pure pairing: given a set of assets (by id + original file URL), decide which
/// working-still files are secondaries of which RAW primary. Two assets bond when
/// they share a parent folder and a case-insensitive filename stem and one is a
/// RAW; the RAW is the primary and each working still becomes its secondary. A
/// RAW is never a secondary (we never hide original RAW bytes); a stem group with
/// no RAW produces no bonds.
enum AssetBondPlanner {
    struct BondInput: Equatable {
        let id: AssetID
        let originalURL: URL
    }

    /// Returns `secondaryID → primaryID` for every working still that bonds.
    static func bonds(for assets: [BondInput]) -> [AssetID: AssetID] {
        var groups: [String: [BondInput]] = [:]
        for asset in assets {
            let folder = asset.originalURL.deletingLastPathComponent().standardizedFileURL.path
            let stem = asset.originalURL.deletingPathExtension().lastPathComponent.lowercased()
            groups["\(folder)\n\(stem)", default: []].append(asset)
        }

        var bonds: [AssetID: AssetID] = [:]
        for group in groups.values {
            let raws = group
                .filter { isRaw($0.originalURL) }
                .sorted { $0.originalURL.path < $1.originalURL.path }
            guard let primary = raws.first else { continue }
            for asset in group where isWorkingStill(asset.originalURL) {
                bonds[asset.id] = primary.id
            }
        }
        return bonds
    }

    private static func isRaw(_ url: URL) -> Bool {
        ImageIODecodeProvider.rawExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isWorkingStill(_ url: URL) -> Bool {
        ImageIODecodeProvider.workingStillExtensions.contains(url.pathExtension.lowercased())
    }
}
```

- [ ] **Step 4: Run planner tests — PASS** (`swift test --filter AssetBondPlannerTests`, 6 tests).

- [ ] **Step 5: Add the column to the schema + migration**

In `CatalogMigrations.swift`: change `static let version = 21` → `22`.

In `CatalogDatabase.swift` `migrate()` (alongside the other `addColumnIfMissing` calls, ~`:56`):

```swift
        try addColumnIfMissing(table: "assets", column: "bonded_to_asset_id", definition: "TEXT")
```

(Also add `bonded_to_asset_id TEXT` to the `CREATE TABLE assets` statement in `CatalogMigrations.swift` for fresh databases, matching how `content_hash` appears in both places.)

- [ ] **Step 6: Write the failing repository accessor test**

Create `Tests/TeststripCoreTests/CatalogBondingTests.swift`. Use the existing test helper pattern for an in-memory/temp catalog (mirror a sibling test such as an existing `CatalogRepository` test's setup — find one in `Tests/TeststripCoreTests/` and reuse its make-catalog helper; do not invent a helper). The test must:

```swift
// after inserting a RAW asset "raw" and a JPEG asset "jpg":
try repo.setBond(secondaryID: AssetID(rawValue: "jpg"), primaryID: AssetID(rawValue: "raw"))
XCTAssertEqual(try repo.bondedPrimaryID(of: AssetID(rawValue: "jpg")), AssetID(rawValue: "raw"))
XCTAssertNil(try repo.bondedPrimaryID(of: AssetID(rawValue: "raw")))
XCTAssertEqual(try repo.bondedSecondaryIDs(of: AssetID(rawValue: "raw")), [AssetID(rawValue: "jpg")])
XCTAssertEqual(try repo.assetIDsWithBondedSecondaries(), [AssetID(rawValue: "raw")])
// clearing:
try repo.setBond(secondaryID: AssetID(rawValue: "jpg"), primaryID: nil)
XCTAssertNil(try repo.bondedPrimaryID(of: AssetID(rawValue: "jpg")))
```

- [ ] **Step 7: Run, verify it fails** (`setBond` undefined / column missing).

- [ ] **Step 8: Implement the repository accessors**

In `CatalogRepository.swift`:

```swift
    public func setBond(secondaryID: AssetID, primaryID: AssetID?) throws {
        try database.execute(
            "UPDATE assets SET bonded_to_asset_id = ?, updated_at = ? WHERE id = ?",
            bindings: [primaryID?.rawValue, "\(Date().timeIntervalSince1970)", secondaryID.rawValue]
        )
    }

    public func bondedPrimaryID(of assetID: AssetID) throws -> AssetID? {
        let rows = try database.rows(
            "SELECT bonded_to_asset_id FROM assets WHERE id = ?", bindings: [assetID.rawValue]
        )
        guard let value = rows.first?["bonded_to_asset_id"] as? String, !value.isEmpty else { return nil }
        return AssetID(rawValue: value)
    }

    public func bondedSecondaryIDs(of primaryID: AssetID) throws -> [AssetID] {
        let rows = try database.rows(
            "SELECT id FROM assets WHERE bonded_to_asset_id = ? ORDER BY original_path ASC",
            bindings: [primaryID.rawValue]
        )
        return try rows.map(decodeAssetID)
    }

    public func assetIDsWithBondedSecondaries() throws -> Set<AssetID> {
        let rows = try database.rows(
            "SELECT DISTINCT bonded_to_asset_id FROM assets WHERE bonded_to_asset_id IS NOT NULL"
        )
        return Set(rows.compactMap { ($0["bonded_to_asset_id"] as? String).map { AssetID(rawValue: $0) } })
    }
```

Match the codebase's actual `database.execute`/`database.rows` binding conventions and row-decoding helpers (check how neighboring methods bind an optional/`nil` and read a column — adjust the above to the real API; e.g. if bindings are `[String]` only, use the established nil-binding pattern).

- [ ] **Step 9: Run bonding tests — PASS**, then `swift build`.

- [ ] **Step 10: Commit**

```bash
git add Sources/TeststripCore/Catalog/CatalogMigrations.swift \
        Sources/TeststripCore/Catalog/CatalogDatabase.swift \
        Sources/TeststripCore/People/AssetBondPlanner.swift \
        Sources/TeststripCore/Catalog/CatalogRepository.swift \
        Tests/TeststripCoreTests/AssetBondPlannerTests.swift \
        Tests/TeststripCoreTests/CatalogBondingTests.swift
git commit -m "feat: bonded_to_asset_id column, pairing planner, bond accessors"
```

---

### Task 2: Backfill bonds over the existing catalog (one-time, idempotent)

**Goal:** on opening a catalog at schema 22, retro-pair existing RAW+JPEG rows once.

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (add `backfillBonds()` + a `catalog_meta` gate)
- Modify: the catalog open/prepare site that already runs after `CatalogDatabase.migrate()` (find it — search for where `migrate()` is called and the repository is constructed; the backfill call goes there, once)
- Modify/Create: `Tests/TeststripCoreTests/CatalogBondingTests.swift` (add backfill cases)

**Interfaces:**
- Consumes: `AssetBondPlanner.bonds(for:)`, `setBond`, the existing `allAssets()`/asset iteration to get `(id, originalURL)`.
- Produces: `CatalogRepository.backfillBonds() throws` — idempotent: reads all assets, computes `AssetBondPlanner.bonds`, applies via `setBond`, and marks a `catalog_meta` key so it runs at most once per catalog.

- [ ] **Step 1: Write the failing test**

Add to `CatalogBondingTests.swift`: insert an unpaired RAW `/p/IMG.CR3` and JPEG `/p/IMG.JPG` (both `bonded_to_asset_id` NULL), call `try repo.backfillBonds()`, assert the JPEG is now bonded to the RAW; call `backfillBonds()` a second time and assert bonds are unchanged (idempotent) and the gate prevents re-scan (assert via a second call being a no-op — e.g., pre-set an unrelated bond and confirm the second backfill doesn't clear/rewrite it).

- [ ] **Step 2: Run, verify fail** (`backfillBonds` undefined).

- [ ] **Step 3: Implement `backfillBonds()`**

```swift
    /// One-time retro-pairing of existing RAW+JPEG rows. Idempotent and gated by
    /// a catalog_meta flag so it runs at most once per catalog; safe to call on
    /// every open.
    public func backfillBonds() throws {
        let gateKey = "bonded_backfill_v1"
        if try metaValue(forKey: gateKey) == "done" { return }
        let inputs = try allAssets(includeBondedSecondaries: true).map {
            AssetBondPlanner.BondInput(id: $0.id, originalURL: $0.originalURL)
        }
        for (secondary, primary) in AssetBondPlanner.bonds(for: inputs) {
            try setBond(secondaryID: secondary, primaryID: primary)
        }
        try setMetaValue("done", forKey: gateKey)
    }
```

Use the catalog's real `catalog_meta` read/write helpers (find the existing schema_version read/write in `CatalogDatabase`/`CatalogRepository` and reuse the same accessor; do not invent `metaValue`/`setMetaValue` if a differently-named helper exists). `allAssets(includeBondedSecondaries:)` is added in Task 3 — if Task 3 lands after this task in your order, use a direct `SELECT id, original_path FROM assets` here instead so this task is self-contained.

- [ ] **Step 4: Wire the call site** — after `migrate()` at catalog open, call `repository.backfillBonds()` once.

- [ ] **Step 5: Run tests — PASS**; `swift build`.

- [ ] **Step 6: Commit** (`feat: backfill RAW+JPEG bonds on catalog open`).

---

### Task 3: Hide secondaries from display listings and counts

**Goal:** listing and user-facing count queries return one row per shot (primaries + unpaired); processing/enqueue and fetch-by-id are unaffected.

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (`loadAssets`, the `allAssets(...)` variants, `assetIDs(...)`, `assetCount()`)
- Modify: any display caller that must opt in/out (trace callers of `assetIDs()` — enqueue/processing callers keep secondaries)
- Create: `Tests/TeststripCoreTests/CatalogListingBondingTests.swift`

**Interfaces:**
- Produces: an `includeBondedSecondaries: Bool = false` parameter on the display-listing methods (`allAssets(...)`, and `loadAssets`), defaulting to **false** (exclude secondaries). A private helper composes the predicate onto an existing `whereSQL`:

```swift
    /// ANDs the "primaries + unpaired only" filter onto a WHERE fragment that is
    /// either "" or " WHERE …". Used by display listings; processing/enqueue and
    /// fetch-by-id never call this.
    private static func excludingSecondaries(_ whereSQL: String) -> String {
        let predicate = "bonded_to_asset_id IS NULL"
        return whereSQL.isEmpty ? " WHERE \(predicate)" : "\(whereSQL) AND \(predicate)"
    }
```

- [ ] **Step 1: Write the failing test**

`CatalogListingBondingTests.swift`: insert a RAW primary and a JPEG bonded to it (via `setBond`), plus one standalone asset. Assert:
- `allAssets()` returns the primary + standalone but NOT the secondary (2 rows).
- `allAssets(includeBondedSecondaries: true)` returns all 3.
- `assets(ids: [secondaryID], limit: 1)` (fetch-by-id) STILL returns the secondary (unfiltered).
- `assetCount()` counts 2 (primary + standalone), not 3.
- A processing/enqueue id path still sees the secondary (assert whichever method preview-enqueue uses returns the secondary id — identify it while tracing callers; if it is `assetIDs()`, assert `assetIDs()` includes the secondary because enqueue must still process it).

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement the filter**

Route `loadAssets` and the `allAssets(...)` variants through `excludingSecondaries(...)` when `includeBondedSecondaries == false` (the default). Add `bonded_to_asset_id IS NULL` to `assetCount()` (`SELECT COUNT(*) FROM assets WHERE bonded_to_asset_id IS NULL`). **Trace every caller** of `assetIDs()`/`allAssets()`: display callers (the grid `reload`, section listings, count displays) get the filter; processing/enqueue callers (preview generation, evaluation) pass `includeBondedSecondaries: true` or use an explicitly-unfiltered id method. Leave `assets(ids:)` and any by-id fetch untouched.

- [ ] **Step 4: Run tests — PASS**; `swift build`.

- [ ] **Step 5: Commit** (`feat: hide bonded secondaries from listings and counts`).

---

### Task 4: Pair newly-imported files

**Goal:** importing a file that matches an existing unpaired sibling bonds it.

**Files:**
- Modify: `Sources/TeststripCore/Ingest/IngestService.swift` (after the import loop creates assets, ~`:200`–`:210`, run pairing over the affected folders)
- Create/Modify: `Tests/TeststripCoreTests/` ingest pairing test (reuse the existing IngestService test harness — find it under `Tests/TeststripCoreTests/`)

**Interfaces:**
- Consumes: `AssetBondPlanner.bonds(for:)`, `CatalogRepository.setBond`, the repository's asset lookup for the affected folders.

- [ ] **Step 1: Write the failing test** — using the existing ingest test harness: import a RAW; then import its sibling JPEG into the same folder; assert the JPEG ends `bonded_to_asset_id` = the RAW. Also the reverse order (JPEG first, then RAW) bonds the JPEG. (If the existing catalog already has the RAW, importing the JPEG must bond it; assert via `bondedPrimaryID`.)

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement** — after the ingest batch persists assets, for each affected parent folder, load that folder's assets (`id`, `originalURL`) and run `AssetBondPlanner.bonds(for:)`, applying `setBond` for any not-yet-set bond. Keep it idempotent (only set when changed). Scope the recompute to the imported files' folders (do not rescan the whole catalog on every import).

- [ ] **Step 4: Run tests — PASS**; `swift build`.

- [ ] **Step 5: Commit** (`feat: bond RAW+JPEG siblings at import`).

---

### Task 5: RAW+JPEG badge on the shot

**Goal:** a shot that has a bonded secondary shows a "RAW+JPEG" badge (extending the existing "RAW" badge).

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (the badge at `:6454`; the grid/loupe reads a `Set<AssetID>` of primaries-with-secondaries)
- Modify: `Sources/TeststripApp/AppModel.swift` (expose `assetIDsWithBondedSecondaries` as a cached `Set<AssetID>`, refreshed on `reload`)
- Create: `Tests/TeststripAppTests/` presentation test for the badge label (find the presentation that owns the RAW badge; test its "RAW" vs "RAW+JPEG" decision as a pure function if one exists — if the badge is inline SwiftUI with no seam, extract a tiny pure helper `RawBadgeLabel.text(isRaw:hasBondedStill:) -> String?` and test that)

**Interfaces:**
- Consumes: `CatalogRepository.assetIDsWithBondedSecondaries()`.
- Produces: `AppModel.assetIDsWithBondedSecondaries: Set<AssetID>` (loaded on reload), and a pure badge-label helper.

- [ ] **Step 1: Write the failing test** for the badge-label helper: `isRaw:true, hasBondedStill:true → "RAW+JPEG"`; `isRaw:true, hasBondedStill:false → "RAW"`; `isRaw:false, hasBondedStill:false → nil`. (A non-RAW primary with a bonded still cannot occur — a bonded primary is always the RAW — so `isRaw:false, hasBondedStill:true` need not render; assert it returns "RAW+JPEG" only via the isRaw path or document the invariant.)

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement** the helper + wire it: `AppModel` loads `assetIDsWithBondedSecondaries` on reload; the grid cell reads membership and passes `hasBondedStill` into the badge; the badge renders `RawBadgeLabel.text(...)`.

- [ ] **Step 4: Run tests — PASS**; `swift build`.

- [ ] **Step 5: Commit** (`feat: RAW+JPEG badge on bonded shots`).

---

### Task 6: File-op fan-out — move/trash carry the bonded file

**Goal:** rejecting-and-moving/trashing a bonded shot moves/trashes both files and updates both rows' paths; no orphaned JPEG.

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`moveRejectsToFolder` `:11581`, `moveRejectsToTrash` `:11674` — expand each reject to its bonded secondaries)
- Create: `Tests/TeststripAppTests/` (or `Tests/TeststripCoreTests/`) fan-out test

**Interfaces:**
- Consumes: `CatalogRepository.bondedSecondaryIDs(of:)`, `RejectRelocationService.move`/`trash`, `CatalogRepository.relocateOriginal`.

- [ ] **Step 1: Write the failing test** — seed a bonded RAW+JPEG shot on disk in a temp dir, mark the RAW rejected, run the move-to-folder (or trash) path, and assert: (a) both the RAW and the JPEG files are at the destination (none left in the source folder), (b) both asset rows' `original_path` updated via `relocateOriginal`, (c) the bond survives (`bondedPrimaryID(of: jpg)` still the RAW). Add the invariant-negative: a shot whose reject flag is AI-tentative (`origin='ai'`, unconfirmed) is NOT moved — neither file relocates. (Reuse the existing reject-relocation test harness; find it under `Tests/`.)

- [ ] **Step 2: Run, verify fail** (JPEG left behind / secondary row path stale).

- [ ] **Step 3: Implement** — in `moveRejectsToFolder`/`moveRejectsToTrash`, for each reject `assetID`, look up `bondedSecondaryIDs(of: assetID)`; for each secondary, compute its destination (same destination folder, secondary's own filename), invoke the same `RejectRelocationService.move`/`trash`, and `relocateOriginal(assetID: secondary, to: …)`. Preserve the existing rollback/manifest behavior (each file+sidecar move already rolls back on failure). Do NOT relocate a shot that isn't a committed reject (the existing tentative-flag gate stays in force — bonding only adds which files move once a committed reject does).

- [ ] **Step 4: Run tests — PASS**; `swift build`.

- [ ] **Step 5: Commit** (`feat: move/trash carry the bonded JPEG with the RAW`).

---

### Task 7: End-to-end scenario card

**Files:**
- Create: `test/scenarios/photos-001-raw-jpeg-bonding.md` (pick the next free number; there is no `photos-*` series yet — confirm with `ls test/scenarios/` and choose an appropriate `<area>-<n>` name)

- [ ] **Step 1: Author the card** — read `test/scenarios/README.md` and a sibling card first. Cover the shot lifecycle against a seeded RAW+JPEG folder: (1) the Library shows **one** tile with a **RAW+JPEG** badge (assert `bonded_to_asset_id` in the catalog: the JPEG points at the RAW); (2) rating the shot writes **only** the RAW's `.xmp` (assert the JPEG's `.xmp` is absent/unchanged); (3) reject + move-to-folder relocates **both** files and both rows' `original_path` update. Reference only real UI/paths/symbols; assert catalog ground truth; note AX-driving realities. Authored, not run.

- [ ] **Step 2: Commit** (`docs: scenario card for RAW+JPEG bonding`).

---

## Self-Review

- **Spec coverage:** data model + planner (T1), backfill (T2), listing/count filter (T3), import pairing (T4), badge (T5), file-op fan-out (T6), e2e card (T7). All spec sections mapped.
- **Placeholders:** integration steps (T2 call site, T3 caller tracing, T4/T6 harness reuse) name the exact target and behavior + test; where a helper name might differ in the real API, the step says to match the existing convention rather than invent. Test steps carry real code.
- **Type consistency:** `AssetBondPlanner.BondInput`/`bonds` (T1) used in T2/T4; `setBond`/`bondedPrimaryID`/`bondedSecondaryIDs`/`assetIDsWithBondedSecondaries` (T1) used in T2/T3/T5/T6; `includeBondedSecondaries` (T3) used by T2's backfill read. `AssetID(rawValue:)` (no string-literal init) used throughout.
