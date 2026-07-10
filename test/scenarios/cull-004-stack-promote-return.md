# cull-004-stack-promote-return: Return promotes one frame and rejects every sibling as one atomic gesture; no-op without stack membership

**What this covers**: as a photographer working a burst, I want `Return` (and
the rail's "Keep" button, which is the same action) to pick the frame I'm
looking at and reject every other frame in its stack in a single write/undo
unit — and to do nothing when the current frame isn't part of any stack.
Covers:
- `promoteCurrentFrameAndRejectSiblings()` (`Sources/TeststripApp/
  AppModel.swift:5351-5359`): guards on stack membership (persisted
  `selectedWorkStackAssetIDs` *or* an in-memory `cullingStacks()` match) and,
  if neither holds, returns without doing anything — the no-op case.
- `applyCullingStackDecision` (`:5376-5412`): the shared write path — loops
  every asset in the stack, sets `pick` on the target and `reject` on every
  other member, batches all changes into one `MetadataChange` array, and
  records **one** undo group via `recordMetadataChangeGroup` (label `"Flag ·
  N"` when more than one asset changed, `"Flag"` otherwise, `:5398-5399`) —
  this is the atomicity the story hinges on.
- The rail's "Keep" button is the identical code path, not a parallel
  reimplementation: `CullingStackListView`'s `.keepSelectedAndRejectAlternates`
  action -> `keepSelectedStackFrame()` -> `model.promoteCurrentFrameAndRejectSiblings()`
  (`Sources/TeststripApp/LibraryGridView.swift:4313-4318`, wired from the
  action enum at `:4334-4345` and the rail presentation's button title/help
  at `:5555-5556`, `"Keep frame N · cut M"` / `"Keep selected frame and
  reject stack alternates"`).
- Return's key binding: `CullingShortcut.init(event:)` maps the Return/keypad-
  Enter keycodes to `.promoteAndRejectSiblings`
  (`CullingKeyCaptureView.swift:159-160`), dispatched at
  `AppModel.swift:5438-5440`.

## Investigating whether `--smoke` can produce a persisted stack (`work-stack-`)

Grepped the app source for every write site of an `asset_sets` row whose id
is prefixed `work-stack-` and for every caller of `AssetStackBuilder`:

- The only writer is `saveCullingStackInputSets` (`AppModel.swift:10614-
  10636`), which upserts `AssetSet.manual(id: "work-stack-<session>-<n>",
  ...)` for every **multi-frame** stack (`assetIDs.count > 1`) the builder
  finds over a specific import's output assets.
- `saveCullingStackInputSets` is called from exactly two places, both inside
  `beginCullingFromLatestImportCompletion()`/`beginStackCullingFromLatestImportCompletion()`
  (`AppModel.swift:4166-4273`) — i.e. only right after an import completes,
  never on-demand against an already-imported/static catalog.
- `beginStackCullingFromLatestImportCompletion()` is wired to exactly one UI
  affordance: the **"Cull stacks"** button in the post-import completion
  banner (`kind: .stackGrouping`, title `"Cull stacks"`, enabled only when
  `summary.stackCount > 0` — `LibraryGridView.swift:8011-8021`, dispatched at
  `:1510-1511`). This *is* a reachable UI gesture — import something, then
  click "Cull stacks" — but it only produces `work-stack-` sets when the
  import's own frames actually group into a multi-frame `AssetStack`.
- `AssetStackBuilder.stacks(from:)` (`Sources/TeststripCore/Search/
  AssetStackBuilder.swift:28-99`) groups two adjacent-in-catalog-order assets
  into the same stack only if `isCaptureTimeNeighbor` (same folder **and**
  `technicalMetadata.capturedAt` within 2s of each other) or a visual-
  similarity vector distance <= 0.05. Checked the only synthetic-fixture
  generator that produces multi-frame import folders,
  `DuplicateFixtureSeeder`/`BenchmarkImageFixtures.writeJPEG`
  (`Sources/TeststripBench/DuplicateFixtureSeeder.swift`,
  `BenchmarkImageFixtures.swift:8-36`): it writes plain JPEGs with **no EXIF
  `DateTimeOriginal`/TIFF `DateTime` at all**, and `ImageIODecodeProvider`
  only derives `capturedAt` from those two EXIF fields
  (`Sources/TeststripCore/Decode/ImageIODecodeProvider.swift:136-137`) — no
  filesystem-mtime fallback. So every asset imported from `seed-dup-fixtures`'s
  `card1`/`card2` folders has `capturedAt == nil`, `isCaptureTimeNeighbor`
  always returns false for them, and (absent visual-similarity vectors, which
  require a worker evaluation pass that hasn't run yet at import time) the
  builder partitions them into all-singleton stacks — `summary.stackCount ==
  0`, so **the "Cull stacks" button stays disabled** for this fixture.
- No other seed command (`seed-geo-fixtures`, `seed-app-catalog` /
  `--smoke`, `seed-sample-catalog`, `seed-real-corpus-catalog`) targets
  bursts specifically. `SmokeCatalogSeeder` (used by `--smoke`) assigns
  `capturedAt` 900s apart per asset (`Sources/TeststripBench/
  SmokeCatalogSeeder.swift:105`) — also outside the 2s gap, and `--smoke`
  never runs an import through `beginStackCullingFromLatestImportCompletion`
  anyway (it seeds the catalog directly, bypassing `IngestService`).

**Conclusion**: there is a real, reachable UI path to create a persisted
stack (import -> "Cull stacks" completion action), but no existing fixture
generator produces EXIF timestamps close enough together (or a same-folder,
sub-2s capture cluster) to make `AssetStackBuilder` actually group frames
into a multi-frame stack from a *synthetic* import. A **real burst** from
`sample-data/photos/` (multiple frames shot within ~2s, same folder) might
incidentally qualify, but confirming that requires inspecting live EXIF
`DateTimeOriginal` values on files under `sample-data/photos/` — not done
here (no display/EXIF tooling available in this text-only pass). This card
tests what's reachable without that fixture and documents the rest as a gap.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Fallback: `script/vm_scenario_run.sh setup && sync smoke && launch smoke`,
then `vm_scenario_run.sh ax ...` / `sql smoke ...`.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘1 for Cull, scope to
   "All" with `S`.
2. Select an asset with no stack-mates — in `--smoke`'s 900s-apart
   `capturedAt` seed, every asset is a singleton stack
   (`AssetStackBuilder`'s 2s gap never matches), so any asset qualifies.
   Record its id and pre-state flag:
   ```bash
   LONE=$(sqlite3 "$DB" "SELECT id FROM assets WHERE json_extract(metadata_json,'\$.flag') IS NULL ORDER BY rowid LIMIT 1;")
   sqlite3 "$DB" "SELECT json_extract(metadata_json,'\$.flag') FROM assets WHERE id = '$LONE';"   # expect NULL
   ```
3. Press `Return`. Assert **no-op**: the flag is still NULL and no undo
   group was pushed (check the Undo menu item / `⌘Z` availability — if
   `script/ax_drive.sh find --role AXMenuItem --label Undo` reports disabled,
   or a subsequent ⌘Z has no effect on `$LONE`, that confirms nothing was
   recorded). This is a true no-op, not just "picks the lone frame with zero
   siblings to reject": `private func cullingStacks()` (`AppModel.swift:5643-
   5645`) filters `allCullingStacks(for:)` down to `{ $0.assetIDs.count > 1
   }` *before* `promoteCurrentFrameAndRejectSiblings`'s guard
   (`:5352-5356`) checks membership, so a singleton never satisfies
   `cullingStacks().contains(where:...)`. Even if it somehow did,
   `selectedCullingStackDecisionContext()` (`:5837-5839`) independently
   throws `"selected asset is not in a culling stack"` unless
   `stack.assetIDs.count > 1`. Both checks agree: lone frames are a hard
   no-op, confirmed by reading source (no live ambiguity to resolve).

## Expected
- Step 3: true no-op — `$LONE`'s flag stays NULL and no undo entry is
  pushed. **Fails if** Return picks the lone frame anyway (would contradict
  the double guard read in source — a real regression worth flagging, not
  silently accepting).
- Rail-Keep-equals-Return claim: verified by reading source
  (`LibraryGridView.swift:4313-4318` calls the identical
  `model.promoteCurrentFrameAndRejectSiblings()`), not independently driven
  live in this card — `cull-pass-scope-and-undo.md` already exercises the
  Return path's multi-sibling atomicity; a live run of *this* card should
  additionally click the rail's "Keep frame N · cut M" button once (on any
  multi-frame stack it can find, if `--smoke` or a future seed ever produces
  one) and spot-check the resulting write matches Return's.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **Cannot fully test the multi-sibling promote-and-reject atomicity here** —
  that requires a persisted or derived multi-frame stack, which `--smoke`
  doesn't have and no fixture generator reliably produces (see investigation
  above). `cull-pass-scope-and-undo.md` already covers that path assuming a
  persisted stack exists; this card's gap is specifically about *proving a
  fixture can create one* for a from-scratch run, which it cannot yet do.
- **Recommended next step for real stack coverage**: either (a) add a
  burst-fixture generator (JPEGs in one folder with EXIF `DateTimeOriginal`
  values <=2s apart) to `TeststripBench`, or (b) confirm a real burst exists
  under `sample-data/photos/` and thread it through `--sample-photos`/
  `--real-corpus`. Neither exists today; this is the concrete gap to raise.

## Run status
UNRUN — SQL not yet dry-run against a live catalog; needs human-present
execution per test/scenarios/README.md.
