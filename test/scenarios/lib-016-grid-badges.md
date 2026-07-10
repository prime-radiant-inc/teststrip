# lib-016-grid-badges: thumbnail chrome — selection borders, metadata overlay, availability, batch/autopilot badges, preview status

**What this covers**: every piece of chrome `AssetGridCell` draws over a
thumbnail (`Sources/TeststripApp/LibraryGridView.swift:8644-8790`) — selection
border width/color, the bottom-left metadata overlay (flag/rating/color
label/keyword count), the top-right source-availability badge (4 non-online
states), the top-left batch-selection checkmark and KEEP/CUT autopilot badge,
and the preview-status badge shown while a thumbnail hasn't rendered yet.
Companion unit coverage: `Tests/TeststripAppTests/LibraryGridChromeTests.swift`
(chrome logic in isolation) — this card proves the same logic renders
correctly in the assembled view.

Exact values, verified by source read (not paraphrase):

**Selection border** (`AssetGridSelectionChrome.border`, lines 8630-8642, and
`selectionBorder`, lines 8702-8715):
- Primary selection (`isSelected`): `Color.orange`, **`lineWidth: 3`**, plus a
  `shadow(color: .orange.opacity(0.45), radius: 3)`.
- Batch selection only (`isBatchSelected`, not primary): `Color.orange.opacity(0.72)`,
  **`lineWidth: 2`**.
- Neither: no border drawn (`EmptyView`).
- If both flags are true, primary wins (`border(isSelected:isBatchSelected:)`
  checks `isSelected` first).

**Metadata overlay** (`metadataOverlay`, lines 8759+, backed by
`AssetGridMetadataBadgePresentation`, line 7150+): bottom-left-anchored
`HStack`, left to right: flag badge (pick/reject tone icon+color), rating
text (yellow caption2), color-label dot (8x8 filled circle), keyword-count
badge (only when `asset.metadata.keywords.count > 0`, accessibility label
`"N keyword"`/`"N keywords"`).

**Availability badge** (`AssetSourceStatusPresentation.presentation(for:)`,
lines 8436-8465) — 4 non-online states, each with title/detail/SF Symbol,
rendered top-trailing via `sourceStatusBadge`:
| `SourceAvailability` | title | systemImage | tint |
| --- | --- | --- | --- |
| `.online` | (no badge — `nil`) | — | — |
| `.offline` | "Offline" | `externaldrive.badge.xmark` | orange |
| `.missing` | "Missing" | `photo.badge.exclamationmark` | orange |
| `.moved` | "Moved" | `arrowshape.turn.up.right` | orange |
| `.stale` | "Stale" | `clock.badge.exclamationmark` | **yellow** (only state with a different tint, per `AssetSourceStatusPresentation.tint`, line 8467-8474) |

**Batch checkbox + autopilot KEEP/CUT** (top-leading `HStack`, lines 8682-8692):
- `batchSelectionBadge` (line 8742): `checkmark.circle.fill`, black+orange,
  a11y label "Batch selected" — shown only when `isBatchSelected`.
- `autopilotBadge` (line 8749, driven by `AutopilotBadgePresentation.badge`,
  lines 3318-3329): `.pick` proposal → text **"KEEP"**, green; `.reject`
  proposal → text **"CUT"**, red; `.keyword` proposal or `nil` → no badge.
  Both render as a bold caption2 capsule over `black.opacity(0.55)`.

**Preview-status badge** (`AssetGridPreviewStatusPresentation.presentation`,
lines 7111-7147) — shown only while `previewURL == nil`, 3 states (not the
"generating/ready/failed" guessed in the brief — "ready" has no badge, it's
just the rendered thumbnail):
- Active generation for `.grid`/`.micro` preview levels → title **"Building
  preview"**, icon `clock.arrow.circlepath`.
- Queued (not yet actively generating) with an attempt/error recorded → title
  **"Preview issue"**, icon `exclamationmark.triangle.fill`.
- Queued, no attempt/error yet → title **"Preview queued"**, icon `clock`.
- Once `previewURL` is non-nil, no badge — the thumbnail itself is the "ready"
  state.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`--smoke`'s 24 synthetic assets are all locally-online originals with
generated previews by the time the worker settles, so the availability badge
and preview-status badge are **not naturally exercised** by this fixture —
see Sharp edges. Metadata-overlay badges (flag/rating/color-label/keyword)
and selection borders are exercisable against `--smoke`'s pre-seeded ratings.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. Pick one asset the seed data rates 3 (`SELECT id FROM assets WHERE
   json_extract(metadata_json,'$.rating')=3 LIMIT 1;`); scroll it into view
   and confirm the grid cell shows a yellow rating badge.
3. Click a cell once (plain click, no modifiers) — confirm its border is the
   3pt solid orange primary-selection border (visually distinguish from a
   ⌘-click batch selection below; AX doesn't expose stroke width directly, so
   this step needs `script/capture_app_window.sh` and pixel/visual
   inspection, or a snapshot diff against `LibraryGridChromeTests` fixtures).
4. ⌘-click a second, different cell (batch-select while keeping the first
   cell's primary selection). Confirm: the first cell keeps its 3pt primary
   border; the second cell shows the 2pt lighter batch border *and* the
   top-left `checkmark.circle.fill` badge with a11y label "Batch selected".
5. If any asset in the `--smoke` fixture has a nonzero keyword count
   (`SELECT id FROM assets WHERE json_extract(metadata_json,'$.keywords') !=
   '[]';` — adjust to the actual JSON shape per `CatalogMigrations.swift`),
   scroll to it and confirm the keyword-count badge renders with the
   accessibility label `"N keyword(s)"`.
6. Immediately after `--smoke` launch (before the worker finishes previews),
   capture the window and check for a "Building preview"/"Preview queued"
   badge on not-yet-rendered cells — this is a narrow timing window, note in
   Run status if missed.

## Expected
- Step 2: rating badge renders and matches the catalog value exactly for that
  asset. **Fails if** the badge shows a stale/wrong rating, or renders for an
  asset the catalog doesn't have rated.
- Steps 3-4: primary vs. batch border widths/colors match the source values
  above; both can coexist on different cells simultaneously. **Fails if** a
  batch-selected cell's badge or border is missing, or if primary/batch chrome
  is swapped.
- Step 5: keyword badge presence/count matches catalog ground truth exactly.
- Step 6: **honest failure expected** — `--smoke` almost certainly finishes
  preview generation before a human/agent can drive fast enough to catch the
  transient badge; document whichever way it lands rather than forcing a
  result.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **No `--smoke` fixture exercises the availability badge at all** (offline/
  missing/moved/stale) — all 4 states require an asset whose original is
  actually offline/deleted/relocated/touched on disk, which no seed script
  currently produces. `reject-relocation-move-and-back.md` incidentally
  produces a `.moved`-adjacent state via its move-and-back gesture but doesn't
  assert on this specific badge. This is a fixture gap worth flagging, not
  something to fake around in this card.
- The KEEP/CUT autopilot badge needs a pending Autopilot proposal in place
  (`autopilotDecision` param) — `--smoke` alone won't have one; pair this
  step with `autopilot-review-commit-undo.md`'s pre-state (run Autopilot
  first) if this specific badge needs live verification.
- Preview-status badge states are timing-dependent and effectively
  unreachable once the worker catches up — a deliberately slow/broken preview
  fixture would be needed to force "Preview issue" reliably; none exists
  today.

## Run status
NOT RUN — no live GUI launch performed for this task (headless-only
constraint). All chrome values verified by direct source read at
`Sources/TeststripApp/LibraryGridView.swift:7107-7148, 8420-8475, 8630-8790,
3318-3329`. Needs a live AX session plus `capture_app_window.sh` visual
inspection for Steps 3-4 (border widths aren't AX-queryable) and a
human-present retry for the timing-dependent Step 6.
