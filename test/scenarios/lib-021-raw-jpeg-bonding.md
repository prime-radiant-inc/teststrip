# lib-021-raw-jpeg-bonding: a same-stem RAW+JPEG pair collapses to one badged tile, and rating/reject/move stay RAW-scoped while carrying the JPEG along

**What this covers**: RAW+JPEG bonding end to end — a RAW original and a
same-folder, same-stem working still (e.g. `frame.dng` + `frame.jpg`) import
as two catalog rows but one Library tile, and every downstream action (rate,
reject, relocate) treats the RAW as the addressable shot while the bonded
JPEG rides along silently.

- **Data model**: `assets.bonded_to_asset_id`
  (`Sources/TeststripCore/Catalog/CatalogMigrations.swift:21`) — the JPEG's
  row points at the RAW's id; a RAW is never a secondary. Pairing logic:
  `AssetBondPlanner.bonds(for:)`
  (`Sources/TeststripCore/People/AssetBondPlanner.swift:9-44`) — same
  standardized parent folder + case-insensitive stem, one side a RAW
  (`ImageIODecodeProvider.rawExtensions`, `.dng` included) and the other a
  working still (`.workingStillExtensions`, `.jpg` included),
  `Sources/TeststripCore/Decode/ImageIODecodeProvider.swift:7-22`.
  `CatalogRepository.setBond` (`:205-211`), `.bondedPrimaryID(of:)` (`:213-220`),
  `.bondedSecondaryIDs(of:)` (`:222-228`), `.assetIDsWithBondedSecondaries()`
  (`:230-237`) — all in `CatalogRepository.swift`.
- **Import-time pairing**: the real "Import Path" folder-import route
  (`IngestService`/`FolderScanner(supportedExtensions:
  ImageIODecodeProvider.catalogableExtensions)`,
  `Sources/TeststripApp/AppCatalog.swift:114`) bonds a RAW+JPEG pair the
  moment both exist in the catalog, in either arrival order or in the same
  batch — proven at the unit level by
  `Tests/TeststripCoreTests/IngestBondingTests.swift`, which catalogs the pair
  from plain, non-decodable byte content (no real pixel data needed for
  cataloging/bonding to occur).
- **Listing exclusion**: every asset-listing path defaults
  `includeBondedSecondaries: false`
  (`CatalogRepository.swift:321` `excludingSecondaries`, threaded through
  `allAssets`/`assetIDs`/`assetCount` `:330-412`), so a bonded JPEG never
  appears as its own row anywhere the grid reads from —
  `AppModel`'s `catalogContents(repository:query:sort:)`
  (`Sources/TeststripApp/AppModel.swift:13481-13494`), which calls
  `repository.allAssets(sort:)`, feeds `model.assets` (the Library grid's
  data source) with this same default.
- **The badge**: `RawBadgeLabel.text(isRaw:hasBondedStill:)`
  (`Sources/TeststripApp/LibraryGridView.swift:6366-6371`) returns
  `"RAW+JPEG"` only when `isRaw` and `hasBondedStill` are both true (a
  non-RAW can never carry the badge — bonding always makes the RAW the
  primary). Rendered bottom-trailing on `AssetGridCell`
  (`LibraryGridView.swift:9377-9382`, the `rawBadge(_:)` view at
  `:9449-9457`), driven by `model.assetIDsWithBondedSecondaries`
  (published at `AppModel.swift:2064`, refreshed at `:12701`) and wired at
  the grid's `ForEach` call site (`LibraryGridView.swift:2362-2371`).
- **Rate/reject stay RAW-scoped structurally, not incidentally**: the grid
  only ever selects/batch-selects ids present in `model.assets`, which never
  includes the bonded JPEG — so `setRatingForSelectedAssets`/
  `setFlagForSelectedAssets` (`AppModel.swift:6927-6935, 6937-6943`, via
  `updateSelectedAssetsMetadata` `:7617-7646`) can never target the JPEG's
  row, and `applyMetadataSnapshot`/`syncMetadataSidecar`
  (`AppModel.swift:8011-8025, 8027-8051`) key the sidecar write off the
  *edited* asset's own `originalURL` — the RAW's, always. Same story for the
  Inspector's rating stars (`Sources/TeststripApp/InspectorView.swift:953-978`,
  each helped `"Rate N"`) and flag buttons (`:980-999`, `"Pick"`/`"Reject"`).
- **Reject relocation carries the bonded secondary**: `rejectRelocationScope`
  (`AppModel.swift:11546-11558`) selects `rejectIDs` via
  `assetIDs(ids:matching:)`'s default `includeBondedSecondaries: false`, so
  only the RAW (if flagged reject) is ever counted in `moveCount`
  (`:1482`) or shown in the confirm sheet's title (`confirmationText`,
  `:1486-1488` — "Move 1 reject photo to \<folder\>", never "Move 2", even
  though two files move). `AppModel.moveRejectsToFolder`
  (`:11712-11783`) moves the primary, then fans out to
  `relocateBondedSecondaries` (`:11613-11656`, itself calling
  `bondedSecondaryAssets` `:11602-11604`), which relocates each bonded
  secondary via the same `CatalogRepository.relocateOriginal`
  (`Sources/TeststripCore/Catalog/CatalogRepository.swift:2437-2454`, rewrites
  `original_path`) and records its own
  `relocation_manifest_entries` row (`CatalogMigrations.swift:193-206`) under
  the same session id.

Sibling cards this one follows for format/mechanics: `app-010-move-rejects.md`
(the reject/move-rejects/move-back gesture and its confirm-sheet chrome),
`inspect-008-sidecar-write-semantics.md` (rate → sidecar assertions),
`lib-016-grid-badges.md` (grid chrome / AX-invisibility of overlay-only
labels), `lib-019-multiselect.md` (grid cell click/AX semantics, and the
as-yet-unexplored nested-`.contextMenu`-submenu AX path this card
deliberately avoids), `people-020-ai-label-provenance.md` (drives this exact
reject-relocation confirm sheet and its checkbox-matching quirk), and
`people-026-review-card-name-face.md` (the `script/vm_scenario_run.sh` VM
driving pattern this card uses throughout).

## Pre-state

Per CLAUDE.md, this is an interactive AX-driven card — it runs in the Tart VM
(`script/vm_scenario_run.sh`), never on Jesse's host console.

There is no existing RAW+JPEG fixture under `sample-data/photos/` (checked —
none of the seed variants in `script/build_and_run.sh` or
`script/vm_scenario_run.sh` produce one), so this card constructs the pair
itself using the real import mechanism: a same-stem `.dng` + `.jpg` pair
placed in a folder and imported via the real "Import Path" dev/automation
route (`script/submit_import_path.sh`, the same route `import-001`/`import-003`
use on the host — it drives the real `IngestPlanner.addFolder` ingest path,
not a test-only shortcut). Per `IngestBondingTests.swift`, the ingest scanner
only inspects path/extension for cataloging and bonding — plain non-image
byte content is sufficient (see Sharp edges for what that does and doesn't
prove).

```bash
# One-time / idempotent VM lifecycle:
script/vm_scenario_run.sh setup

# Build + prepare the "empty" (isolated, unseeded) catalog template and rsync
# the app + script/ into the VM:
script/vm_scenario_run.sh sync empty

# Launch once via the normal verb, purely to learn/create $FRESH — no data
# exists yet, so relaunching next loses nothing:
LAUNCH_OUTPUT=$(script/vm_scenario_run.sh launch empty)
echo "$LAUNCH_OUTPUT"
FRESH=$(echo "$LAUNCH_OUTPUT" | sed -n "s/^launched 'empty' fresh at \([^ ]*\).*/\1/p")

# `vm_scenario_run.sh launch` only ever sets
# TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY (cmd_launch's `open -n ... --env`
# line, script/vm_scenario_run.sh:263-269) — it has no way to also thread
# TESTSTRIP_REJECT_DESTINATION_DIR through for Step 3's deterministic
# destination. Relaunch the same $FRESH catalog directly with both env vars,
# reusing the exact `open -n <bundle> --env ...` invocation
# build_and_run.sh's own open_app() uses for multiple env vars
# (script/build_and_run.sh's open_args chaining):
REJECTS_DIR=/tmp/raw-jpeg-bonding-rejects   # do NOT mkdir — the app creates
                                            # it itself (LibraryGridView.swift:3262-3271)
script/vm_scenario_run.sh shell "pkill -x Teststrip 2>/dev/null || true; pkill -x TeststripApp 2>/dev/null || true; pkill -x TeststripWorker 2>/dev/null || true; sleep 1; open -n ~/teststrip-vm/dist/Teststrip.app --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=$FRESH --env TESTSTRIP_REJECT_DESTINATION_DIR=$REJECTS_DIR && sleep 2 && pgrep -x Teststrip"
script/vm_scenario_run.sh ax wait-vended Teststrip

# Build the RAW+JPEG fixture folder inside the VM (fake bytes — see Sharp
# edges; IngestBondingTests.swift proves this is enough for cataloging/bonding):
FIXTURE=/tmp/raw-jpeg-bonding-fixture
script/vm_scenario_run.sh shell "rm -rf $FIXTURE && mkdir -p $FIXTURE && printf 'raw bytes' > $FIXTURE/frame.dng && printf 'jpg bytes' > $FIXTURE/frame.jpg"

# Import it via the real dev/automation Import Path route:
script/vm_scenario_run.sh shell "cd ~/teststrip-vm && ./script/submit_import_path.sh Teststrip $FIXTURE"
```

## Steps

### 1. One tile, one badge

1. `script/vm_scenario_run.sh ax wait-vended Teststrip`; press ⌘2 for
   Library: `script/vm_scenario_run.sh key 'keystroke "2" using {command down}'`.
2. Resolve both rows' ids:
   ```bash
   RAW_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM assets WHERE original_path LIKE '%frame.dng';")
   JPEG_ID=$(script/vm_scenario_run.sh sql empty "SELECT id FROM assets WHERE original_path LIKE '%frame.jpg';")
   ```
3. **Ground-truth the bond** (the load-bearing assertion):
   ```bash
   script/vm_scenario_run.sh sql empty "SELECT count(*) FROM assets;"                                # 2 — both files cataloged
   script/vm_scenario_run.sh sql empty "SELECT bonded_to_asset_id FROM assets WHERE id='$JPEG_ID';"  # == $RAW_ID
   script/vm_scenario_run.sh sql empty "SELECT bonded_to_asset_id FROM assets WHERE id='$RAW_ID';"   # empty/NULL — a RAW is never a secondary
   script/vm_scenario_run.sh sql empty "SELECT count(*) FROM assets WHERE bonded_to_asset_id IS NULL;" # 1 — exactly one tile-eligible row, matching the predicate the grid's own listing query applies
   ```
4. **One tile, not two**: the grid cell's own accessible label is the
   filename (`LibraryGridView.swift:7098`,
   `.accessibilityLabel(asset.originalURL.lastPathComponent)`):
   ```bash
   script/vm_scenario_run.sh ax find --role AXButton --label "frame.dng"   # exit 0 — the RAW's tile exists
   script/vm_scenario_run.sh ax find --role AXButton --label "frame.jpg"   # must exit nonzero — the JPEG never gets its own grid cell
   ```
5. **Visual badge check** (AX cannot see this one — see Sharp edges):
   ```bash
   script/vm_scenario_run.sh shell "cd ~/teststrip-vm && ./script/capture_app_window.sh Teststrip /tmp/raw-jpeg-bonding-badge.png"
   ```
   Retrieve the PNG from the VM (`sshpass`/`scp` with the same
   `TESTSTRIP_VM_USER`/`TESTSTRIP_VM_PASS` credentials
   `vm_scenario_run.sh` uses — default `admin`/`admin` — there is no
   dedicated "pull a file" verb yet) and visually confirm a monospaced
   "RAW+JPEG" chip, bottom-trailing, over the one tile.

### 2. Rating writes only the RAW's sidecar

1. Select the shot: `script/vm_scenario_run.sh ax press --role AXButton --label "frame.dng"`.
2. Open the Inspector: ⌘I —
   `script/vm_scenario_run.sh key 'keystroke "i" using {command down}'`.
3. Rate it 5 stars (`InspectorView.swift:964-965`, helped `"Rate 5"`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Rate 5"
   script/vm_scenario_run.sh ax wait --role AXButton --contains "Rating 5"
   ```
4. **Ground-truth the catalog** — rating landed on the RAW row only:
   ```bash
   script/vm_scenario_run.sh sql empty "SELECT json_extract(metadata_json,'\$.rating') FROM assets WHERE id='$RAW_ID';"   # 5
   script/vm_scenario_run.sh sql empty "SELECT json_extract(metadata_json,'\$.rating') FROM assets WHERE id='$JPEG_ID';"  # 0 (untouched default)
   ```
5. **Wait for the (worker-queued) sidecar to drain**, then assert it exists
   only for the RAW:
   ```bash
   for i in $(seq 1 30); do
     script/vm_scenario_run.sh shell "test -f $FIXTURE/frame.dng.xmp" && break
     sleep 1
   done
   script/vm_scenario_run.sh shell "test -f $FIXTURE/frame.dng.xmp && echo 'RAW sidecar written'"
   script/vm_scenario_run.sh shell "grep -qiE 'Rating>?5|xmp:Rating=\"5\"' $FIXTURE/frame.dng.xmp && echo 'rating 5 in xmp'"
   script/vm_scenario_run.sh shell "test ! -e $FIXTURE/frame.jpg.xmp && echo 'no JPEG sidecar — OK'"
   ```

### 3. Reject + Move Rejects carries both files

1. With the shot still selected and the Inspector open, press "Reject"
   (`InspectorView.swift:991-999`, helped `"Reject"`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "Reject"
   script/vm_scenario_run.sh ax wait --role AXButton --contains "Flagged Reject"
   ```
2. **Ground-truth the flag** — RAW only, JPEG untouched:
   ```bash
   script/vm_scenario_run.sh sql empty "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id='$RAW_ID';"   # reject
   script/vm_scenario_run.sh sql empty "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id='$JPEG_ID';"  # NULL
   ```
3. Open the toolbar's "More actions" overflow menu, then "Move Rejects…"
   (`LibraryGridView.swift:344-406`; the menu button is helped `"More
   actions"`, the item's label is `"Move Rejects…"` at `:350`):
   ```bash
   script/vm_scenario_run.sh ax press --role AXButton --help "More actions"
   script/vm_scenario_run.sh ax press --role AXMenuItem --contains "Move Rejects"
   ```
4. With `TESTSTRIP_REJECT_DESTINATION_DIR` set at launch, the destination is
   already `$REJECTS_DIR` and the confirm sheet appears directly (no native
   panel — `resolvedDestinationFolder`, `LibraryGridView.swift:3262-3271`).
   Check the sheet's own wording before confirming — it must read **"Move 1
   reject photo to raw-jpeg-bonding-rejects"**, not "Move 2" (the bonded
   JPEG is carried but never independently counted,
   `AppModel.swift:1482,1486-1488`):
   ```bash
   script/vm_scenario_run.sh ax find --role AXButton --contains "Move 1 reject photo to raw-jpeg-bonding-rejects"
   ```
   Toggle the confirm checkbox on, then press the now-enabled primary button.
   The toggle's own accessible label is the *same* `confirmationText` string
   as the button (`LibraryGridView.swift:3442`), so per
   `people-020-ai-label-provenance.md`'s precedent driving this exact sheet, a
   bare `--role AXCheckBox` press (no label filter — it's the only checkbox
   in the sheet) is the reliable match, not a `--contains` filter on the
   checkbox itself (see `app-010-move-rejects.md` for the disabled/enabled
   gate assertion mechanics, not re-derived here since it's unchanged by
   bonding):
   ```bash
   script/vm_scenario_run.sh ax press --role AXCheckBox
   script/vm_scenario_run.sh ax press --role AXButton --contains "Move 1 reject photo to raw-jpeg-bonding-rejects"
   script/vm_scenario_run.sh ax wait --role AXButton --label "Move back"
   ```
5. **Assert both files physically relocated, neither orphaned at source**:
   ```bash
   script/vm_scenario_run.sh shell "test -f $REJECTS_DIR/frame.dng && test -f $REJECTS_DIR/frame.jpg && echo 'both at destination'"
   script/vm_scenario_run.sh shell "test ! -f $FIXTURE/frame.dng && test ! -f $FIXTURE/frame.jpg && echo 'both gone from source'"
   script/vm_scenario_run.sh shell "test -f $REJECTS_DIR/frame.dng.xmp && echo 'RAW sidecar traveled too'"
   ```
6. **Assert both rows' `original_path` updated, and both moves are on the
   manifest**:
   ```bash
   script/vm_scenario_run.sh sql empty "SELECT original_path FROM assets WHERE id='$RAW_ID';"    # $REJECTS_DIR/frame.dng
   script/vm_scenario_run.sh sql empty "SELECT original_path FROM assets WHERE id='$JPEG_ID';"   # $REJECTS_DIR/frame.jpg
   script/vm_scenario_run.sh sql empty "SELECT count(*) FROM relocation_manifest_entries;"        # 2 — this empty catalog's only relocation ever run, so an unscoped count is unambiguous
   ```

## Expected

- Step 1: exactly 2 catalog rows, the JPEG's `bonded_to_asset_id` equals the
  RAW's id, the RAW's own `bonded_to_asset_id` is NULL, and exactly one row
  passes `bonded_to_asset_id IS NULL`. The grid shows a tile labeled
  `frame.dng` and no tile labeled `frame.jpg`. **Fails if** two tiles render,
  no tile renders, or the JPEG's `bonded_to_asset_id` is NULL (bonding never
  happened).
- Step 2: `metadata_json.rating` is 5 on the RAW row and 0 on the JPEG row;
  `frame.dng.xmp` exists and encodes rating 5; `frame.jpg.xmp` does not
  exist. **Fails if** a JPEG sidecar appears at all, or the RAW's rating
  didn't take.
- Step 3: `metadata_json.flag` is `"reject"` on the RAW row only; the confirm
  sheet's count reads exactly 1 (never 2); after confirming, both
  `frame.dng`/`frame.dng.xmp` and `frame.jpg` exist at `$REJECTS_DIR` and not
  at `$FIXTURE`; both rows' `original_path` point at `$REJECTS_DIR`; the
  manifest has 2 entries. **Fails if** the JPEG is left behind at `$FIXTURE`
  (orphaned secondary — the exact regression this step exists to catch), if
  the sheet overcounts to "2", or if only one of the two rows' `original_path`
  updates.

## Cleanup

```bash
script/vm_scenario_run.sh shell "rm -rf $FRESH $FIXTURE $REJECTS_DIR"
script/vm_scenario_run.sh shell "pkill -x Teststrip 2>/dev/null || true; pkill -x TeststripWorker 2>/dev/null || true"
```
Per `test/scenarios/README.md`'s VM section, discard the run directory
(`$FRESH`, under `~/teststrip-vm/run/empty-<timestamp>`); no host catalog is
ever touched.

## Sharp edges

- **The "RAW+JPEG" badge's own `accessibilityLabel` never reaches the AX
  tree.** `AssetGridCell`'s outer `.accessibilityElement()`
  (`LibraryGridView.swift:7096-7099`, applied by the `assetActivation`
  modifier at `:7061-7106`) collapses every child view into one AX element
  whose label/value come from `assetSelectionAccessibilityValue`
  (`:7108-7117`), which calls `AssetGridCellAccessibilityValue.value(...)`
  (`:7749-7768`) — and that function's parameter list has no raw-badge
  parameter at all (only selection state, flag/rating/color/keyword badges,
  availability, and autopilot decision are threaded through, matching the
  file's own comment at `:7744-7748` about badge views never surfacing their
  own labels). This is the same swallowing lib-016 documents for border
  widths, but here it means the badge is *invisible to AX entirely*, not just
  imprecise — Step 1.5's screenshot is the only way to confirm the chip
  itself renders; every other assertion in this card falls back to catalog
  ground truth or the filename-based tile presence/absence check instead,
  per the brief's own guidance for exactly this situation.
- **The fixture files are non-decodable stand-ins**, matching
  `import-001-folder-in-place.md`'s and `IngestBondingTests.swift`'s
  precedent: plain bytes named `.dng`/`.jpg` catalog and bond correctly (the
  scanner only inspects path/extension), but ImageIO cannot render a real
  thumbnail from them. Expect the tile to show preview-status chrome
  ("Building preview"/"Preview issue" per `lib-016-grid-badges.md`) instead
  of a real image — that's expected and doesn't block any assertion here,
  none of which depend on decoded pixels.
- **`script/vm_scenario_run.sh launch` cannot thread
  `TESTSTRIP_REJECT_DESTINATION_DIR` through** — `cmd_launch`
  (`script/vm_scenario_run.sh:246-271`) hardcodes a single `--env
  TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=...` in its `open -n` call. This
  card works around the gap by manually reissuing the same `open -n
  <bundle> --env A=... --env B=...` invocation over `vm_scenario_run.sh
  shell`, chaining a second `--env` exactly the way
  `script/build_and_run.sh`'s own `open_app()` does when both
  `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY` and
  `TESTSTRIP_REJECT_DESTINATION_DIR` are set — not a new mechanism, just
  `vm_scenario_run.sh`'s existing primitive extended by hand for the one
  thing its `launch` verb doesn't expose. A follow-up could teach `launch`
  to accept extra `--env` pairs so future cards don't need to replicate this.
- **This card deliberately avoids driving the grid's nested
  `.contextMenu` → `Menu("Rate")`/`Menu("Flag")` submenus**
  (`LibraryGridView.swift:2376-2415`, `applyGridContextMenuRating`/
  `applyGridContextMenuFlag` at `:3072-3088`). The closest existing
  precedent, `lib-019-multiselect.md`, only drives one level of
  `.contextMenu` (the flat item "Cull These" via `--button right`) and
  itself flags uncertainty about that; no card in `test/scenarios/`
  demonstrates AX-driving a *nested* `Menu`-within-`.contextMenu` submenu
  one level deeper, so it isn't established as reachable. Since the
  Inspector's rating stars and flag buttons call the exact same
  `AppModel.setRatingForSelectedAssets`/`setFlagForSelectedAssets` the
  context-menu path calls, this card uses the Inspector controls instead —
  functionally identical, and this substitution is not itself a
  bonding-specific gap.
- **`ax_drive.sh` has no verb for checking `AXEnabled`/disabled state** — the
  confirm sheet's checkbox-gates-the-primary-button behavior
  (`RejectRelocationSheetPresentation.isMoveEnabled`,
  `LibraryGridView.swift:5174`) is exercised functionally here (check the
  box, then press) but not asserted for disabled-while-unchecked; that
  assertion already lives in `app-010-move-rejects.md` and isn't re-derived
  in this bonding-focused card.
- **`script/submit_import_path.sh` run via `vm_scenario_run.sh shell` (not
  the dedicated `ax` verb) is a first for this card set** — every prior
  citation of it (`import-001`, `import-003`) runs on the host. The
  mechanism is identical either way (it drives AX against whichever process
  is frontmost via `NSWorkspace`/`AXUIElement` calls, same TCC grants
  `vm_scenario_run.sh setup` already provisions for `ax_drive.sh`), but this
  is the first time it's spelled out for the VM path.

## Run status

NOT RUN — authored 2026-07-16 for Task 7 of the RAW+JPEG Bonding sub-project
(Tasks 1-6 already merged at `b26c3de0`), against
`.superpowers/sdd/task-7-brief.md`. Every symbol, line range, file path, AX
label/help string, SQL column/table, and `vm_scenario_run.sh`/`ax_drive.sh`
verb cited above was re-verified by reading the current-tree source and
scripts directly (not paraphrased from another card) before writing this
file — see the accompanying `.superpowers/sdd/task-7-report.md` for the
per-citation verification list. Pending a live run in the Tart VM per
`test/scenarios/README.md`'s "Running scenarios in a Tart VM" section.
