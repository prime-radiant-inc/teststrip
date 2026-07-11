# Trash for Rejects + UX Coherence Pass

**Date:** 2026-07-11
**Status:** Approved direction (Jesse: "write the spec, write the plan, implement")
**Rulings incorporated:** Finder Trash + Put Back; catalog rows removed on trash;
targets = Cull loupe chrome, Library toolbar/header, sheets & dialogs; guiding
principles = progressive disclosure ("important when you need it, not when you
don't") and a coherent icon/button/label design language.

## Part 1 — Move Rejects to Trash

### Behavior

- New action **"Move Rejects to Trash…"** everywhere "Move Rejects…" exists
  today: the Culling menu and the Cull end-of-set completion state. The two
  actions are siblings; folder relocation stays.
- Uses `NSWorkspace.recycle` (or `FileManager.trashItem`) so originals + their
  `.xmp` sidecars land in the **macOS Trash** — recoverable via Finder "Put
  Back" and via our banner.
- **Catalog rows are removed.** The relocation manifest gains a `trash` mode
  recording, per asset: the resulting Trash URL(s) returned by the API, the
  full catalog row snapshot (metadata JSON, source root linkage), and the
  preview-cache key. Cached previews are deleted with the row.
- The existing post-move banner appears with **"Move back"**: files are moved
  from their Trash URLs back to their original paths and the catalog rows are
  re-inserted from the snapshot (same asset IDs; previews regenerate). If a
  Trash URL no longer exists (user emptied the Trash), that asset is reported
  in the banner detail as unrecoverable and skipped; the rest restore.
- Preflight sheet mirrors the folder flow: count, per-file preview rows,
  warning copy stating files go to the macOS Trash and the catalog forgets
  them, single confirmation. The primary button is the verb: **"Move N to
  Trash"**.
- Same safety properties as folder relocation: per-file loop, abortable,
  `WorkSession` persisted first, re-entrancy guarded, failures become
  skip-with-issue rows.
- Non-destructive invariant holds: bytes are never modified; the Trash is a
  move, and Move Back restores byte-identical files.

### Testing

- Core: `RejectRelocationService` (or a sibling `TrashRelocationService`)
  unit tests with a temp-dir fake Trash via dependency-injected recycler
  (real `trashItem` in one integration test guarded to CI-safe temp volumes).
- Scenario card `app-017-move-rejects-to-trash.md`: trash N rejects in the VM,
  assert files present in the VM user's `~/.Trash`, catalog rows gone,
  previews gone; Move back → files restored byte-identical (checksum), rows
  re-inserted, counts restored. Ledger row added.

## Part 2 — UX coherence

### Principles (normative for every change below)

1. **Progressive disclosure.** A control or datum appears only when it can do
   something *now*: empty-state affordances replace disabled furniture;
   secondary actions live one click behind a menu/disclosure; counts and
   status appear when non-zero/non-default.
2. **One primary verb per surface.** At most one prominent (accent-filled)
   button per screen or sheet, and its label is the verb + object
   ("Import 240 Photos", "Move 71 to Trash"), never "OK"/"Confirm".
3. **One glyph per concept, one concept per glyph** (inventory below).
4. **Copy register:** actions in Title Case; explanatory copy in sentence
   case; counts in monospaced digits; no internal jargon in user-facing copy
   (keep "XMP" — photographers know it; kill "scope", "provider", "evaluation
   kind" in favor of "these photos", the provider's display name, and signal
   display names).

### 2a. Cull loupe chrome

- **HUD consolidation:** one row remains, but the pick/reject pills and the
  progress bar merge into a single session cluster:
  `✓ 38 · ✕ 71 · 209 left` with the thin progress bar beneath the cluster
  (not beside). Filename stays leading; scope chip renders **only when scope ≠
  All**; rating stars render **only when the current frame has a rating or a
  rating key was just pressed** (2s echo, same fade as the toast); the label
  dot only when set; the verdict text only when the assist has a read
  (already). Net: an undecided frame in default scope shows filename +
  session cluster, nothing else.
- **Stack rail:** hidden entirely when the session has no multi-frame stacks
  (today it shows an empty "Stacks · Auto-Grouped" header on singleton
  catalogs). Secondary stack actions (keep-top-ranked / keep-all / …) collapse
  into an ellipsis menu on the rail; **Keep** stays the single visible verb.
- **Cull sidebar:** "Diagnostics" disclosure group dissolves: its rows are click-to-cull
  review-queue sources, so they fold into "Cull From" under the same
  zero-count-omission rule (adjudicated during Task 7 — the original
  move-to-Activity idea misread them as status).
  Source rows with count 0 are **omitted, not disabled** (empty-state text
  "Nothing to cull" when all are empty).
- **Close-Ups panel:** unchanged behavior, but gains a header ellipsis to hide
  it for the session (progressive disclosure for face-free work).

### 2b. Library toolbar/header

- **Merge the Add-filter button into the search field**: the `plus.circle`
  menu becomes the field's leading accessory, rendered as
  `line.3.horizontal.decrease` per the glyph inventory (sparkles leaves the
  query field — it marks machine reads only). One query control instead of two.
- **Sort** becomes a compact `arrow.up.arrow.down` icon menu (AXHelp "Sort")
  next to the view toggle; the current sort shows as the menu's checked item,
  not a wide labeled picker.
- **Chip/result row renders only when it has content** (active tokens, a
  residual-text interpretation, or save-worthy state). No empty second row.
- **Import** stays the sole prominent button in Library. "Find Best Shots"
  and "Cull" toolbar buttons move into the Culling menu only (they're verbs,
  already there) — the toolbar keeps Import, the view toggle, search, sort,
  Activity — and the Cull button (Task 8 adjudication: its zero-selection
  whole-scope naming popover has no other reachable route). The "More" ellipsis menu absorbs Reconnect Sources and the
  auto-cull toggle unchanged.
- **Footer:** count + selection cluster left; density + zoom right
  (unchanged); "Load Previous/More" render only when the respective page
  exists (already) — restyle as quiet text buttons.

### 2c. Sheets & dialogs (one template)

Every sheet (Import review, Card import, Export, Move Rejects ×2, Batch
Metadata, Save Set/Search/Snapshot, Rename, Naming):

- Header: title (Title Case) + one-line sentence-case subtitle stating effect.
- Body: essence fields only; anything optional or rarely changed goes under a
  single **"Options"** disclosure (export sharpening-adjacent settings, second
  card copy, starred toggles).
- Footer: Cancel (plain) + one primary verb button with count baked in.
  Destructive/catalog-wide operations keep the explicit confirmation toggle;
  everything else drops extra toggles.
- All sheets share spacing/width tokens via one `SheetScaffold` view.

### 2d. Icon / button / label system (normative inventory)

| Concept | Glyph (SF Symbol) | Color | Never used for anything else |
|---|---|---|---|
| Pick / keep | `flag.fill` | green | ✓ |
| Reject / cut | `xmark` | red | ✓ |
| Rating | `star.fill` | yellow | ✓ |
| Color label | filled circle | label color | ✓ |
| Stack / set | `rectangle.stack` | neutral | ✓ |
| AI / provisional | `sparkles` | orange | all machine reads |
| Import | `square.and.arrow.down` | — | ✓ |
| Export | `square.and.arrow.up` | — | ✓ |
| Trash rejects | `trash` | red in destructive contexts | ✓ |
| Availability | `externaldrive.*` family | orange (stale: yellow) | ✓ |
| Activity/status | `bell` (idle) / progress / red badge | — | ✓ |
| Search/query | `magnifyingglass` submit; `line.3.horizontal.decrease` filter menu | — | sparkles no longer doubles as the query icon |

Rules: icon-only controls always carry `.help` (AXHelp) + tooltip; accent
fill is reserved for the one primary verb per surface; `sparkles` marks every
provisional/machine surface and nothing human-authored; monospaced digits for
every count. A `DesignGlyph` enum centralizes the symbol names so tests can
assert uniqueness (one glyph ↔ one concept) and the scenario cards can match
stable AXHelp strings.

### Testing (Part 2)

- Presentation-level tests for: HUD element visibility matrix (undecided
  default-scope frame shows only filename+cluster), stack-rail suppression on
  stackless sessions, chip-row emptiness gating, DesignGlyph uniqueness.
- Affected scenario cards updated in the same task that changes each surface
  (cards are the spec; a UI change without its card update is incomplete).
  Known affected: cull-011 (HUD), cull-014/015 (rail/sidebar), lib-006/007
  (query field/filter menu), lib-009 (sort), lib-010 (chip row), app-009/010
  (sheets), activity cards for AXHelp strings if changed.

## Out of scope

- No changes to workspaces/navigation structure (settled by the
  focused-workspaces redesign).
- No new features beyond trash; no perf work.
- Story-loop Functional fixes in flight (XMP retry drain, tolerant
  preview-level decode, unlabeled text fields) ride the story-loop, not this
  spec — except the unlabeled Describe text fields, which get labels as part
  of 2c/2d (they're a label-system violation).
