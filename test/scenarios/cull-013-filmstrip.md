# cull-013-filmstrip: The Cull filmstrip is scope-filtered, shows stack position, and tiles carry decision badges

**What this covers**: As a photographer scanning a burst I want the filmstrip
beneath the loupe to show only the frames in my current scope, tell me where
I am within an auto-grouped stack, and let me jump to any tile while seeing
at a glance which ones are already decided. Covered inventory items 36
(scope-filtered with dividers exactly between stacks), 37 ("frame X/N · stack
A/B" label), 38 (tile badges: recommended-marker/decision-bar/dim-if-decided/
click-to-select). Source: `cullingFilmstrip` at
`Sources/TeststripApp/LibraryGridView.swift:3919-3966`, `CullFilmstripPresentation`
(divider placement + position text) at
`Sources/TeststripApp/CullFilmstripPresentation.swift:6-37`, tile rendering
(`filmstripTile`/`filmstripDecisionBar`) at `LibraryGridView.swift:4109-4171`.

**Exact position-text format** (read from source, corrects the assignment's
guessed format): `"frame \(frameIndex+1) / \(totalFrames) · stack
\(stackIndex+1) / \(stacks.count)"` — lowercase "frame"/"stack", `/` not
"of", only rendered when there's a selection *and* the selected asset is
inside one of the auto-grouped stacks; otherwise it falls back to `"N
frame(s)"` (plural handling per `CullFilmstripPresentation.positionText`
line 33).

**Frame numbers are catalog-wide in the unscoped view.** When the cull
scope is All and the catalog exceeds one 120-asset page, the caption's frame
number and total come from the page offset and `model.totalAssetCount`
(`frameNumberOffset`/`totalFrameCount` on `CullFilmstripPresentation`), so
it agrees with the header's "Frame X of Y" — assert the caption's total
equals `SELECT count(*) FROM assets`, never the loaded-page size (the
persona-7 "frame 1 / 120 vs Frame 1 of 130" drift). Scoped views
(picks/rejects/unrated) stay scope-local by design.

**Stack grouping is auto-derived, not the persisted `asset_sets` rows.** The
filmstrip's stacks come from `model.allCullingStacks(for: scopedAssets)` —
the in-memory `AssetStackBuilder` clustering by capture-time proximity
(`candidateStackMaximumCaptureGap = 2` seconds, `AppModel.swift:2184`), the
same builder that backs the auto-grouped rows in `CullSidebarView`. This is a
**different mechanism** from the `work-stack-` `asset_sets` rows used by the
Return-gesture card (`cull-pass-scope-and-undo.md`). **`--smoke`'s synthetic
photos are seeded 900 seconds apart** (`SmokeCatalogSeeder.swift:105`), which
is far outside the 2-second auto-grouping window — so `--smoke` will show
**zero multi-frame auto-stacks** and the divider/position-text-with-stack
assertions are untestable on it. Use the `burst` seed variant
(`TeststripBench seed-burst-catalog`), which guarantees 4 multi-frame
auto-stacks (3/4/3/4 frames, capture times 1s apart) plus 4 singles.

## Pre-state
```bash
# The `burst` variant guarantees multi-frame auto-stacks (4 groups of
# 3/4/3/4 frames with capture times 1s apart, inside AssetStackBuilder's
# 2s gap) plus 4 singles:
script/vm_scenario_run.sh sync burst && script/vm_scenario_run.sh launch burst
script/vm_scenario_run.sh ax wait-vended
# ground truth via: script/vm_scenario_run.sh sql burst "..."
# (Host equivalent: swift run TeststripBench seed-burst-catalog <appsupport>.)
```

## Steps
1. Cycle scope with `S` to "All" and record the scope's ground-truth tile
   count (same query pattern `cull-005`-style cards use — total assets in
   the active `CullScope` predicate):
   ```bash
   TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
   ```
   Assert the filmstrip renders exactly `TOTAL` tiles (count `AXButton`
   children under the filmstrip region — inspect the AX subtree first to
   find the right container role before writing the final `find`/count
   command).
2. Cycle scope with `S` to "Picks". Recompute:
   ```bash
   PICKS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick';")
   ```
   Assert the filmstrip's visible tile count matches `PICKS`.
3. **If an auto-stack of 2+ frames exists** in the current scope (verify via
   `model.allCullingStacks` behavior indirectly — no direct SQL for
   in-memory clustering; infer from close EXIF capture timestamps in the
   `--faces` fixture, or just watch for a divider rendering), select a frame
   inside it and assert the position label matches the exact format:
   ```bash
   script/ax_drive.sh find --contains "frame " # then read full text, compare against "frame N / TOTAL · stack S / C"
   ```
   If no auto-stack forms in this scope with this fixture, **do not** fake
   this assertion — mark it skipped and say so plainly in the run log.
4. Click a filmstrip tile directly (not the currently-selected one):
   ```bash
   script/ax_drive.sh press --role AXButton --label "<other-frame-filename>"
   ```
   Assert the loupe's focused asset changed to that tile's asset — cross
   check via the HUD filename text (per `cull-011-hud.md`) or:
   ```bash
   sqlite3 "$DB" "SELECT id FROM assets WHERE ..." # confirm the clicked tile's id now == model.selectedAssetID via AX filename match
   ```
5. Pick one currently-undecided tile (`P`) and assert its own filmstrip tile
   now shows the decision bar/dim styling that a still-undecided neighbor
   tile does not:
   ```bash
   script/ax_drive.sh find --role AXButton --label "<picked-filename>"
   ```
   Read the `AXValue`/accessibility-value text of that tile
   (`filmstripTileAccessibilityValue`) and compare it against an undecided
   tile's — the picked one should read a "Picked" decision-state segment
   (confirm the exact string emitted by
   `filmstripTileAccessibilityValue`/`filmstripDecisionOverlay` — not fully
   read in this pass, read it before asserting the literal string).

## Expected
- Step 1/2: filmstrip tile count == scope's sqlite-derived count exactly.
  **Fails if** the filmstrip shows all frames regardless of scope, or lags a
  scope change.
- Step 3: label text matches the exact `"frame X / N · stack A / B"` format
  when a selection sits inside a multi-frame auto-stack; falls back to `"N
  frame(s)"` otherwise. **Fails if** the format differs from source (e.g.
  uses "of" instead of "/"), or if a divider appears *within* a stack's own
  tiles rather than exactly at its boundary — same-scope adjacent frames
  from the same stack must render with no divider between them.
- Step 4: clicking a tile moves loupe focus to that exact asset.
  **Fails if** it's a no-op or focuses the wrong asset.
- Step 5: a decided tile visibly differs (dim + decision-bar/value) from an
  undecided one. **Fails if** the decision state doesn't propagate to the
  filmstrip after a P/X keystroke without a scope refresh.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **`--smoke`'s 900-second seed spacing makes auto-stacking untestable on
  it** — this card must use `--faces` (or another fixture with genuinely
  close capture timestamps) and even then auto-stack formation is not
  guaranteed; verify before trusting step 3, and report honestly if no
  auto-stack ever forms rather than weakening the assertion or borrowing the
  unrelated `work-stack-` persisted-set fixture (that mechanism is
  independent of the filmstrip's grouping, per source).
- Step 3's divider-boundary assertion in "Expected" needs a scope with at
  **least two distinct auto-stacks** to be meaningful (a divider check
  against a single-stack scope can't distinguish "correctly placed" from
  "never rendered"); this may need `--real-corpus` instead of `--faces` if
  `--faces`'s handful of photos cluster into only one stack.
- The exact accessibility-value string for a "picked" filmstrip tile (step 5)
  was not read from `filmstripTileAccessibilityValue`'s full switch in this
  pass beyond seeing the `decisionState` cases (`undecided`/`picked`/
  `rejected`) — read the full function before hard-coding the expected
  string in a runner.
- AX container/role for counting filmstrip tiles (step 1/2) wasn't
  independently confirmed against a live AX dump — `filmstripTile` is a
  plain `Button`, so `--role AXButton` scoped to the filmstrip's frame
  region is the working assumption; verify against the live tree since the
  loupe also has other `AXButton`s (rating stars, etc.) that a blind
  `find`-count could double-count.

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md
