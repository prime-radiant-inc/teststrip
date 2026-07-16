# RAW + JPEG Bonding — Design Spec

**Date:** 2026-07-15

## Goal

Bond a RAW file and its sibling JPEG (the same shot, captured RAW+JPEG) into
**one logical asset** throughout the UI: one tile you cull, rate, keyword, and
assign people to, backed by two files on disk. The RAW is the primary (the
master original); its sibling JPEG is a hidden secondary that travels with it.
This is a catalog data-model change, **not** the existing time-burst visual
stacking.

## Background (grounded)

- **A RAW and its JPEG are two separate catalog rows today.** `assets` is keyed
  on a unique `original_path` (`CatalogMigrations.swift`, schema `version = 21`);
  import creates one `Asset` per source file (`IngestService` loop → one `Asset`
  per file; `FolderScanner` appends every supported file), and content-hash dedup
  only collapses byte-identical files — a RAW and JPEG differ, so both import.
- **`Asset` has no file-kind field.** It stores `originalURL: URL`
  (`Sources/TeststripCore/Domain/Asset.swift`) and derives everything from the
  extension. The only RAW awareness is the computed `Asset.isRawOriginal`
  (`Asset.swift:41`, `ImageIODecodeProvider.rawExtensions`), already consumed by
  autopilot's tie-break ("keep the RAW", `AutopilotProposalPlanner`) and a compare
  "RAW" badge (`LibraryGridView.swift:6454`).
- **Listings flow through a few central queries.** `CatalogRepository.loadAssets(whereSQL:…)`
  (`:244`) backs the `allAssets(…)` variants (`:203`–`:243`); the id-listing
  queries are `SELECT id FROM assets …` (`:261`, and the `…matching` variants).
  Fetch-by-explicit-ids (`assets(ids:)`, `:340`) is separate — callers that
  already hold ids should still resolve any row.
- **Sidecars are per-file** — `XMPSidecarStore.sidecarURL(forOriginalAt:)` derives
  `frame.dng.xmp` / `frame.jpg.xmp`; `metadata_sync_state.sidecar_path` tracks one
  per asset. The only existing same-basename logic is XMP sidecar *ownership*
  disambiguation (`XMPSidecarStore.hasSiblingWithSameBasename`,
  `claimedSidecarExtension`), never asset pairing.
- **File-moving operations** that relocate/trash originals:
  `RejectRelocationService.trash(originalFrom:…)`, `Recycler.trash`,
  `CatalogRepository.relocateOriginal(assetID:to:)`, and the app entry points
  `AppModel.moveRejectsToFolder` / `moveRejectsToTrash`.
- **Time-burst stacking is ephemeral** (`AssetStackBuilder`, computed folder+2s
  runs); nothing persists a pair.
- **Provenance model:** user edits carry `origin='user'` and mirror to `.xmp`;
  AI labels are `origin='ai'`, tentative, never sidecar'd. Identity has no XMP
  field.

## Approach (decided)

**Bonded pair, RAW primary** (chosen over a full one-row merge). Keep both rows;
the JPEG becomes a hidden secondary pointing at the RAW primary. This respects
the pervasive one-file-per-asset assumption (previews, decode, per-file sidecars,
the unique-path index all stay intact), keeps both files first-class, is
reversible, and matches the code's existing "prefer the RAW" lean. Listings hide
secondaries at the central query layer, so every surface shows one tile per shot.

## Data model

Add a nullable column to `assets`:

| column | meaning |
|---|---|
| `bonded_to_asset_id` TEXT NULL | on a **secondary** (the JPEG), the id of its **primary** (the RAW). NULL on a primary and on any unpaired asset. |

- Schema `version` bumps **21 → 22**; the column is added with the existing
  `addColumnIfMissing` migration pattern (idempotent, no table rebuild).
- "Is this row a secondary?" = `bonded_to_asset_id IS NOT NULL`. "A shot's
  secondaries" = `SELECT … WHERE bonded_to_asset_id = <primaryID>`.
- Paths are untouched, so the `original_path` unique index and content-hash dedup
  are unaffected.

## Pairing rule

Two (or more) assets bond into one shot when, **in the same parent folder**, they
share a **case-insensitive filename stem** and:

- exactly the **RAW** among them (an `Asset.isRawOriginal` extension) is the
  **primary**, and
- each sibling that is a **working still** (`ImageIODecodeProvider.workingStillExtensions`
  — jpg/jpeg/heic/heif/tif/tiff/png) becomes a **secondary** pointing at that RAW.

Consequences and edges:

- **Two JPEGs for one RAW** (e.g. `IMG.CR3` + `IMG.JPG` + `IMG.HEIC`): both
  working stills bond to the RAW (decided).
- **No RAW in the stem group** (only working stills share a stem): no bonding —
  there is no primary to bond to; each stays standalone and visible.
- **Multiple RAWs share a stem** (rare, e.g. `.CR3` + `.DNG`): pick the primary
  deterministically (RAW files sorted by `original_path`, first wins); any other
  RAW is left standalone (a RAW is never demoted to a hidden secondary — we never
  hide original RAW bytes). Only working stills become secondaries.
- **A stem with just one file:** standalone, unchanged.

## Seeding the bonds

Bonds are computed in two places, both idempotent (re-running never
double-bonds — it upserts `bonded_to_asset_id`):

1. **Backfill migration** (one-time, on catalog open at schema 22): scan existing
   `assets`, group by (parent folder, lowercased stem), apply the pairing rule,
   and set `bonded_to_asset_id` on the working-still rows. This retro-pairs the
   current library.
2. **At import:** after ingesting a batch, a newly-added file that matches an
   existing unpaired sibling in the same folder+stem gets bonded (RAW arrives →
   adopt existing sibling stills as secondaries; still arrives → bond it to an
   existing RAW). Reuses the same pairing routine as the backfill.

## Listings — one tile per shot

Add `bonded_to_asset_id IS NULL` to the central listing queries: `loadAssets`
(the `SELECT * FROM assets` path) and the `SELECT id FROM assets …` /
`…matching` id queries in `CatalogRepository`. Every listing surface — the
Library grid, the cull filmstrip, People, timeline — then shows only primaries
and unpaired assets. **Fetch-by-explicit-ids stays unfiltered** (a caller holding
a specific id, including a secondary's, still resolves it).

Each shot that has a bonded secondary shows a small **RAW+JPEG** badge (extending
the existing `isRawOriginal` "RAW" badge at `LibraryGridView.swift:6454`). The
presentation learns "this primary has secondaries" from a lightweight repository
lookup (e.g. `bondedSecondaryExtensions(for:)` returning the bonded stills'
extensions), so the badge can read "RAW+JPEG".

**Which queries filter, which don't** — the guiding principle the plan must apply
per query site:

- **Filter out secondaries** (`bonded_to_asset_id IS NULL`): user-facing *listing*
  queries (the grid/filmstrip/People/timeline asset lists) **and** the user-facing
  *count* aggregates that feed sidebar/section totals — so a bonded shot counts
  once, not twice.
- **Do NOT filter:** processing/queue paths (preview generation, evaluation) that
  must still touch every file, and fetch-by-explicit-id (`assets(ids:)`), which
  resolves any row including a secondary. Bonding hides the JPEG from view; it
  does not remove it from the catalog's processing.

## Metadata & sidecars — RAW-only (decided)

All user metadata (rating, flag, keyword, caption, creator/copyright, person
assignment, pick/reject) targets the **primary (RAW)** row and mirrors to the
**RAW's** `.xmp` exactly as today. The hidden JPEG secondary is **not**
independently edited and its sidecar is **not** mirrored — edits live on the RAW
only. (If the shot is ever unbonded later, the JPEG returns to whatever state it
last had.) This keeps the write path unchanged and honors the non-destructive /
identity-has-no-XMP invariants.

## Preview & display

The shot renders the **RAW's** preview (the primary), through the existing
preview pipeline unchanged. Both files still get previews and evaluation signals
generated as today — we do **not** special-case secondaries out of the
preview/eval queues (simplest correct; no perf tuning). The bonded JPEG's own
preview is simply never surfaced in a listing.

## File operations — both files travel together (correctness requirement)

Operations that **move original bytes** must carry the bonded secondary's file
alongside the primary's, or the hidden JPEG would be orphaned (left behind,
invisible, no longer in the primary's folder):

- **Move-rejects-to-folder / move-rejects-to-trash**
  (`AppModel.moveRejectsToFolder` / `moveRejectsToTrash` →
  `RejectRelocationService` / `Recycler`): when a rejected shot's RAW is
  relocated or trashed, its bonded working-still file is relocated/trashed to the
  same destination in the same gesture, and `relocateOriginal` updates both rows'
  paths (the bond, keyed by id, survives the move).
- This fan-out is **core**, not optional — it is the difference between a clean
  move and an orphaned invisible file.

Note the tentative-flag invariant still governs *whether* a shot is eligible to
be moved/trashed at all (an AI-only reject never relocates); bonding only changes
*which files* move once a committed reject does.

## Export

In this first cut, exporting a bonded shot exports the **primary (RAW)** — the
shot is represented by its master. Emitting the sibling JPEG too ("export
RAW+JPEG") is a deliberate **later** enhancement, not part of this cut. (Flagged
for your review — say if you'd rather the first cut export the JPEG, or both.)

## Time-burst stacking interaction

Unchanged, and incidentally cleaner: because secondaries are hidden at the query
layer, `AssetStackBuilder` operates on primaries only, so a RAW+JPEG pair no
longer shows up as an incidental 2-frame "captured within 2s" burst.

## Provenance & invariant compliance

- Bonding is a catalog-structure fact; it writes no `.xmp` and never modifies
  original bytes.
- User edits on the shot remain `origin='user'` on the RAW with the RAW sidecar;
  AI labels remain `origin='ai'`, tentative, non-sidecar'd — unchanged.
- Hiding a secondary never drops data: the JPEG row persists (with its own
  sidecar history), so bonding is fully reversible at the data level.

## Non-goals (YAGNI / scope — decided)

- **No unbond UI gesture** in this cut (the model is reversible — set
  `bonded_to_asset_id = NULL` — but no button yet).
- **No RAW⇄JPEG preview toggle** in the loupe.
- **No "export RAW+JPEG"** (export takes the primary; see above).
- No merge to a single row / multi-file asset (that was the rejected approach).
- No change to the time-burst stacker, the worker, or the decode/preview
  pipeline.

## Testing

- **Repository / model:** `bonded_to_asset_id` round-trips; the pairing routine
  bonds a RAW + its stills by folder+stem, leaves a no-RAW stem group unbonded,
  handles two-JPEGs-one-RAW, and is idempotent (re-run doesn't change bonds).
- **Listing filter:** the central listing queries exclude secondaries; a
  fetch-by-id of a secondary still resolves. Assert one tile per shot for a
  seeded RAW+JPEG pair, and the RAW+JPEG badge signal.
- **Backfill migration:** an existing catalog with unpaired RAW+JPEG rows becomes
  bonded on open at schema 22; idempotent on a second open.
- **Import pairing:** importing a JPEG into a folder that already has its RAW
  bonds it (and vice-versa).
- **File-op fan-out:** moving/trashing a rejected bonded shot relocates/trashes
  **both** files and updates both rows' paths; assert no orphaned JPEG remains
  and the JPEG is not left visible.
- **Negative / invariant:** a tentative (AI-only) reject does **not** relocate
  either file; bonding writes no `.xmp`; the hidden JPEG's sidecar is not written
  on a shot edit (RAW-only).
- **End-to-end scenario card** (VM-bound, authored not run): seed a folder with a
  RAW+JPEG pair, confirm the Library shows one tile with a RAW+JPEG badge, rate
  it and confirm only the RAW sidecar is written, reject+move it and confirm both
  files land in the destination. Assert against catalog ground truth
  (`bonded_to_asset_id`, `original_path`, sidecar presence).

## Open decisions

**Resolved:** approach (bonded pair, RAW primary); sidecar (RAW-only); scope
(core auto-bond + hide + badge + migration + file-op fan-out; reversible model;
no unbond UI / preview toggle / RAW+JPEG export); two-JPEGs-one-RAW (bond both).

**Flagged for spec review:** export takes the primary (RAW) in the first cut —
confirm that's what you want, versus exporting the JPEG or both.
