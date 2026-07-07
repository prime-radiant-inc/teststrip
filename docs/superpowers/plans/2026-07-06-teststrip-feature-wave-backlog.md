# Teststrip Feature-Wave Backlog — 2026-07-06

Ranked backlog for the "go big on features" wave, audited against `main` (clean, 1,206 tests) after the 2026-07-06 fix streams. Sources swept: `design-concept/Teststrip.dc.html` (surfaces 1a–5f), `docs/product/narrative-select-reference.md`, `Sources/TeststripApp/LiveMockupPlaceholder.swift` (ledger), `docs/superpowers/plans/2026-07-06-teststrip-session-handoff.md`, and the code itself (claims below were verified by reading the source, not the docs).

**Standing exclusions (not in this backlog unless Jesse re-opens by name):** Lightroom catalog migration, photo editing/develop, watched folders, iOS, production packaging/notarization.

**Gate that precedes everything:** the live e2e verification battery (handoff open thread 1). Nothing from today was verified in the running UI; the unlock watcher + five scenario cards are staged. Run it before or alongside wave 1 and fix what it finds.

**How to read:** BUILD-NOW = no product decision needed, clear value. DECISION-GATED = named decision required first. Sizes are LOC (implementation + tests, per our estimating convention). Rank = daily-driver value for a working photographer. "Depends on" names today's merged streams the item builds on.

---

## BUILD-NOW — ranked

### 1. Loupe 1:1 zoom / pixel-peek (+ neighbor full-res prefetch)
- **Cites:** design 2a (big loupe), t3 try-next "add a 1:1 pixel-peek loupe to 3b"; Narrative promise "next image renders the moment the arrow key is hit, previews never show low-res placeholders".
- **Why #1:** culling is the product core and you cannot confirm focus without 100% zoom. Verified: no zoom code exists anywhere in the app (`zoomScale`/`actualSize`/`scaleEffect` — zero hits); `PreviewLevel` already has `.large` (3200px) and `.original` (full-res), so the decode path exists and only the UI is missing.
- **Scope:** Z / double-click toggles 100% at cursor point, drag to pan, fit/fill/100% states surviving frame advance, and `.large`/`.original` prefetch for loupe neighbors so arrow-key advance never shows a soft placeholder.
- **Size:** ~700–1,000 LOC.
- **Touchpoints:** new `LoupeZoomView.swift`; small insertion in `LibraryGridView.swift` loupe region; `CullingShortcut`/`CullingKeyCaptureView.swift`; `Sources/TeststripCore/Preview/PreviewScheduler.swift`/`PreviewCache.swift`.
- **Depends on:** import-experience render-path caching stream (landed today). Adjacent to the Space-rebind decision (item E) but not blocked by it — use Z/click, leave Space alone.

### 2. Import-new-only + duplicate detection on card
- **Cites:** design 4a "No duplicates on card" / "2,310 **new** photos"; handoff card-import stream.
- **Why #2:** the everyday pro flow is shoot → import → keep shooting on the same card → import again. Verified: `FileFingerprint` is size+mtime only (change detection, not identity); in-place folder re-import matches by path (dogfooding runbook), but card import has **no** dedup — re-importing a card re-copies everything. `CardImportDestinationPreflight` checks only destination sanity.
- **Scope:** content-hash identity (fast hash: size + head/tail chunks, full hash on collision), catalog migration (next: 15) storing it, hash-at-ingest, card preflight scan producing "N new · M already in catalog" in the plan sheet, and skip-known-on-copy. Also fixes accidental double-import of overlapping folder trees.
- **Size:** ~900–1,400 LOC.
- **Touchpoints:** `Sources/TeststripCore/Support/FileFingerprint.swift` (or new `ContentIdentity`), `Catalog/CatalogMigrations.swift` + `CatalogRepository.swift`, `Ingest/IngestService.swift` + `LibraryImportService.swift` + `CardImportDestinationPreflight.swift`, `TeststripApp/ImportConfirmationDraft.swift`, worker protocol carriage.
- **Depends on:** card-import stream (landed today).

### 3. Grid keyboard-first operations
- **Cites:** design 1a (Studio, "everything visible", keyboard-quiet agent); Narrative "instant keyboard transitions"; task brief keyboard-first gaps.
- **Why #3:** verified: `LibraryGridView` has **no** key handling beyond shift/cmd click-selection modifiers — no arrow navigation, no rating/flag/label from the grid, no Enter-to-loupe. Every grid interaction is mouse-only today; that's the single biggest Photo-Mechanic-parity gap outside the loupe.
- **Scope:** arrow/home/end navigation with scroll-follow, P/X/0–5/6–9 acting on the grid selection through the existing metadata paths, Enter opens loupe at selection, Esc returns.
- **Size:** ~500–800 LOC.
- **Touchpoints:** `LibraryGridView.swift` grid region, new `GridKeyCaptureView.swift` (reuse the `CullingKeyCaptureView` NSView pattern), `AppModel` selection.
- **Depends on:** culling-arc keyboard plumbing (landed). **Collision note:** same file as item 1's insertion point — run after the loupe stream merges (first item of wave 2).

### 4. Folder tree navigation in the sidebar
- **Cites:** ledger `sidebar.folders-empty` ("not rendered until folders exist"); design 1a FOLDERS section.
- **Why #4:** folders now exist — card imports write `YYYY/YYYY-MM-DD/` dated folders (landed today) and Jesse's whole existing library is filed that way. Verified: `SetQuery.folderPrefix` predicate already exists in core; the gap is purely rendering a source-root folder tree and scoping on click.
- **Size:** ~450–700 LOC.
- **Touchpoints:** `SidebarView.swift` (484 lines, low collision risk), `AppModel` sidebar counts, `AppCatalog.swift`; core query support already present.
- **Depends on:** card-import dated folders (landed today).

### 5. Session restore
- **Cites:** task brief (livability at scale); handoff known limit #4 (leftover-singles prompt is in-memory, doesn't survive relaunch).
- **Why #5:** verified: the only persisted UI state in the entire app is `LibraryGridView.thumbnailWidth`. Every relaunch dumps you at the default route with no scope, selection, or in-flight culling context. For a daily driver over a 100k+ catalog that's a tax paid every single launch.
- **Scope:** persist and restore route (Library/Copilot/Timeline/People/Search), active scope/query, selection anchor, open culling session offer ("Resume culling Patagonia — 42 of 214 reviewed"), and persist the leftover-singles prompt.
- **Size:** ~400–700 LOC.
- **Touchpoints:** `AppModel.swift` (init/teardown region), `main.swift`, `AppStorage` or a small catalog state table.
- **Depends on:** culling-session persistence (landed).

### 6. Person filter — search predicate + people-scoped browsing
- **Cites:** Narrative "People Filter" (filter shoot by person(s), coverage counts); design 5c; ledger `sidebar.people`.
- **Why #6:** face recognition landed today with confirmed persisted people, but verified: `SetQuery` has no person predicate and `PeopleView` rows don't navigate to a person's photos. The payoff of naming people is finding them; right now there is none.
- **Scope:** `SetQuery.person(PersonID)` predicate + repository join, parser token (`person:Anna`), filter chip, PeopleView row click → scoped grid, per-person coverage counts, works in smart-collection rules for free via the existing rule presets path.
- **Size:** ~450–700 LOC.
- **Touchpoints:** `Sources/TeststripCore/Search/SetQuery.swift`, `CatalogRepository`, `PeopleView.swift`, search-chip region of `LibraryGridView.swift` (small), `LibrarySearchIntent.swift`.
- **Depends on:** face-recognition stream (landed today).

### 7. Export presets — the full 5f workflow
- **Cites:** design 5f; ledger `export.workflow` (stale — says "no export route is exposed", but today's minimal popover shipped: selected/visible/scope, Full-res + Web 2048px, quality, EXIF/IPTC carry). Update the ledger entry as part of this work.
- **Scope beyond today's popover:** named saved presets (+ New preset), long-edge/short-edge/dimensions/megapixels resize modes, color space (sRGB/Display P3/AdobeRGB), output sharpening, watermark (text/image, corner, opacity), export filename template (safe — renames copies, not catalog identity), destination memory, size estimate. Extract the popover into its own view.
- **Size:** ~1,200–1,800 LOC.
- **Touchpoints:** `Sources/TeststripCore/Export/ExportService.swift` (168 lines today) + new preset store, new `ExportView.swift` extracted from `LibraryGridView.swift:960`'s `exportPopover`.
- **Depends on:** minimal-export stream (landed today).

### 8. Grid sort controls + density presets
- **Cites:** design 1a header ("Sort · Capture Time ✦", "Comfortable / Compact").
- **Why:** verified: no sort control exists — order is fixed. Sorting by rating is how you review yesterday's cull; by filename is how you match a client's list. Density presets are a cheap add on top of the existing thumbnail-width storage.
- **Scope:** capture time / rating / filename / import order, ascending/descending, persisted; Comfortable/Compact presets mapping to thumbnail widths.
- **Size:** ~300–500 LOC.
- **Touchpoints:** `SetQuery` ordering support, `AppModel` query assembly, `LibraryGridView.swift` header region.

### 9. Batch undo grouping
- **Cites:** task brief (undo depth); verified in code: undo/redo exists (`Cmd+Z`/`Shift+Cmd+Z`, whole-`AssetMetadata` before/after snapshots) but batch operations append **one stack entry per asset** — undoing "apply keyword to 200" or "Keep #1 & #2 / reject visible" takes N presses of Cmd+Z, which in practice means a wrong batch action is unrecoverable.
- **Scope:** grouped `MetadataChange` entries (array of per-asset changes with a label), one Cmd+Z per user action, status message names what was undone ("Undid: Applied patagonia to 200 photos").
- **Size:** ~200–400 LOC.
- **Touchpoints:** `AppModel.swift` (`metadataUndoStack` region, all `append(MetadataChange(...))` sites).

### 10. Stack similarity threshold tuning
- **Cites:** ledger `culling.stack-cull` ("similarity threshold tuning is still pending") and design surface 3a currentImplementation.
- **Scope:** user-adjustable near-dupe distance (tighter/looser) with live regroup preview and per-catalog persistence; surfaces the distance/threshold rationale that already exists in the stack UI.
- **Size:** ~300–500 LOC.
- **Touchpoints:** `Sources/TeststripCore/Search/AssetStackBuilder.swift`, stack-rail region of culling UI, settings persistence.
- **Depends on:** visual-similarity stacks (landed).

### 11. 2-up A/B compare with synced zoom/pan
- **Cites:** design t2 try-next "add a 2-up A/B compare to 2b"; complements the shipped 4×2 survey and Top-3 contenders mode.
- **Why:** the last-two-frames decision is where survey grids are too small; synchronized 100% pan on two frames is how ties actually get broken.
- **Size:** ~500–800 LOC.
- **Touchpoints:** compare region of `LibraryGridView.swift`, reuses `LoupeZoomView` from item 1.
- **Depends on:** item 1 (loupe zoom) — sequence after it.

### 12. Stack best-first presentation audit
- **Cites:** Narrative "Scenes View" ("ranks by sharpness, best frame first") — reference doc explicitly flags "best-first ranked presentation needs audit".
- **Scope:** ensure stack rail, survey grid, and stack entry ordering put the recommended frame first everywhere (post-calibration ranking), with tests over the real ordering path.
- **Size:** ~200–400 LOC.
- **Depends on:** calibration stream (landed today) — do this after threshold sign-off (decision F) if possible.

### 13. GPS capture at ingest + inspector coordinates
- **Cites:** design 4a plan row ("geo"); upstream of 5b Places (which stays decision-gated); same pattern as today's aperture/shutter/focal ingest work.
- **Why:** verified: zero GPS handling anywhere in Sources. Capturing lat/lon/altitude into the catalog at ingest and showing coordinates in the inspector is cheap, is pure metadata completeness (no map), and means a future Places re-open doesn't require re-scanning 486k originals.
- **Size:** ~200–350 LOC.
- **Touchpoints:** metadata ingest path (where EXIF aperture/shutter landed today), `CatalogMigrations`, `InspectorView.swift`.

### 14. Key-element saliency close-up fallback
- **Cites:** Narrative "Key Element Detection" (saliency fallback when no faces); marked stock-candidate in the reference doc (Vision attention saliency).
- **Scope:** attention-saliency provider signal; Close-Ups panel shows the salient region crop when a frame has no faces; verdict rationale can cite "subject sharp/soft".
- **Size:** ~400–600 LOC.
- **Touchpoints:** `Sources/TeststripCore/Evaluation/` (new provider, follow `core-image-faces` pattern with provider versioning), `CloseUpFacesPresentation.swift`.
- **Depends on:** culling-ML signals stream + Close-Ups panel (landed today).

### 15. People: split person + face-box-level naming
- **Cites:** ledger `people.face-actions` ("Split person and face-box-level naming remain disabled future actions"), design 5a.
- **Why BUILD-NOW:** the governing product rule (confirm-before-write) is already established; no new decision needed. Split matters the first time clustering merges two people — which will happen during dogfooding.
- **Size:** ~500–800 LOC.
- **Touchpoints:** `PeopleView.swift`, `Sources/TeststripCore/People/` (suggestion builder, person_faces mutations).
- **Depends on:** face-recognition stream (landed today).

### 16. Work-history search and editing
- **Cites:** ledger `work.history` ("richer history search and editing are not built").
- **Scope:** filter/search sessions by type and text, rename, delete, star from the list.
- **Size:** ~300–500 LOC.
- **Touchpoints:** work-history sidebar region, `Sources/TeststripCore/Work/`.

### 17. Timeline jump-to-moment field
- **Cites:** design 1c ("Jump to any moment…").
- **Scope:** typed date/period jump ("oct 2019", "2024-03-14") scrolling the ribbon and scoping the grid; reuses existing date-predicate parsing.
- **Size:** ~150–250 LOC.
- **Touchpoints:** `TimelinePresentation.swift`, timeline region of the app.

### 18. Small-polish bundle (single stream)
- **Cites:** handoff known limits + design 4a mid-copy vision.
- **Scope:** backup failures get their own issue titling (today they reuse "Skipped <file>"); import panel surfaces evaluate/stack/keyword follow-up progress inline while copying (4a "runs automatically as photos copy" payoff); ledger refresh for 5f/export staleness.
- **Size:** ~200–400 LOC total.

---

## DECISION-GATED — each phrased as a question Jesse can answer in one line

- **A. Rename patterns on import** (design 4a "Rename · Patagonia_####"; explicitly excluded from today's card stream): *Should card imports offer file renaming — knowing the new name becomes catalog identity forever — and if yes, what default pattern?* Cost if yes: ~600–900 LOC (pattern engine, collision handling, plan-sheet row, worker carriage).
- **B. Second copy inside library root** (handoff open thread 3): *Should the backup second-copy destination be allowed inside the library root, or always blocked?* Cost: ~100–200 LOC either way.
- **C. Copilot NL search / autonomy scope** (design 1b — Autopilot, "Auto-culled 2,310 frames… Review / Undo all", agent task queue; ledger `search.agentic`/`library.copilot`; handoff open thread 3): *Do you want natural-language Ask at all — and if so, parse-only (LLM → existing deterministic filters) or full autopilot with review/undo-all?* Cost: parse-only ~1,500–2,500 LOC plus a local-vs-API model decision; autopilot ~3,000–5,000 LOC on top and touches the confirm-before-write rule.
- **D. Places / map** (design 5b; deferred earlier — "not a go-to-market front door unless Jesse reopens"): *Re-open Places?* Real cost: GPS ingest (item 13, small) + MapKit clustering route ~1,500–2,500 LOC + a reverse-geocoding pipeline for six-figure geotag counts — the hard part, since CLGeocoder is rate-limited and an offline geocoder is its own project.
- **E. Space rebinding** (handoff open thread 3; Narrative behavior): *Should Space zoom to the most important face (Narrative-style) instead of advancing frames?* Cost: ~150–300 LOC once item 1 lands.
- **F. Verdict aggressiveness sign-off** (handoff open thread 2): *Do the calibrated Keep .7 / Toss .5 splits match your eye on the real corpus, or do you want a conservative↔aggressive bias knob?* Cost of knob: ~200–300 LOC; a corpus re-run validation is queued regardless.
- **G. Reject disposal** (design 4b "Review 340 flagged before they're cut"): *Should Teststrip ever touch original files for rejects — offer "move rejected originals to Trash / a rejects folder" — or stay strictly flag-only?* Cost if yes: ~400–600 LOC with heavy confirmation UX; this is the app's first destructive-to-originals feature, so it's your call, not ours.
- **H. Video cataloging** (verified: video extensions are recognized and skipped with "video file not supported"): *Should video clips be cataloged — browse, poster-frame previews, metadata, no editing — instead of skipped?* Cost: ~1,500–2,500 LOC (AVFoundation poster/preview path, duration badges, format matrix).
- **I. Blink / looking-down eye assessment** (Narrative "Eye Assessments" full parity; reference doc: "beyond stock — do not overclaim"): *OK to bundle a non-stock model for blink/looking-down, or stay stock-only and drop that parity claim?* Cost if yes: model research + ~800–1,500 LOC provider work.

---

## Wave-1 composition — parallel worktree streams

**Collision reality:** `LibraryGridView.swift` (8,320 lines) and `AppModel.swift` (9,801 lines) are shared hotspots. Every stream must put new UI in **new files** and keep hotspot edits to small, distinct insertion points. Suggested merge order: core-heavy first.

Six streams, no meaningful file collisions:

| Stream | Item | Primary files | Hotspot touch |
|---|---|---|---|
| 1 | **Loupe 1:1 zoom + prefetch** (#1) | new `LoupeZoomView.swift`, `Preview/*`, `CullingKeyCaptureView.swift` | one insertion, loupe region of LibraryGridView |
| 2 | **Import-new-only / duplicate detection** (#2) | `Ingest/*`, `CatalogMigrations`, `ImportConfirmationDraft.swift` | import-sheet region only |
| 3 | **Folder tree sidebar** (#4) | `SidebarView.swift`, `AppCatalog.swift` | AppModel sidebar-counts region |
| 4 | **Session restore** (#5) | `main.swift`, AppModel init region | AppModel init/teardown only |
| 5 | **Export presets** (#7) | `Export/ExportService.swift`, new `ExportView.swift` | replaces `exportPopover` body at one site |
| 6 | **Person filter** (#6) | `Search/SetQuery.swift`, `PeopleView.swift`, `LibrarySearchIntent.swift` | one chip-row insertion |

**Held back from wave 1 on purpose:** grid keyboard ops (#3 by value) collides with stream 1 in `LibraryGridView`; it is the first wave-2 item the moment stream 1 merges, alongside sort controls (#8) and batch undo grouping (#9). 2-up A/B (#11) queues behind stream 1 for the same reason plus the zoom dependency.

**Wave-1 preconditions:** run the staged live e2e battery first (or in parallel on the 19GB corpus copy) — every wave-1 stream lands UI that today's suite can only verify headlessly.
