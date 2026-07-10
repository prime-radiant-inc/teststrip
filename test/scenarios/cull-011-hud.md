# cull-011-hud: The Cull HUD's at-a-glance counters, progress bar, and verdict fallback

**What this covers**: As a photographer culling a shoot I want the strip of
counters above the loupe to tell me exactly where I am in the set — filename,
stars, scope, undecided count, progress, pick/reject pills — without opening a
side panel, and I want the verdict chip to be honest about whether a frame has
actually been read yet. Covered inventory items 32 (undecided/progress math)
and 33 (verdict fallback rules). Source: `cullHUD`/`cullHUDPresentation` at
`Sources/TeststripApp/LibraryGridView.swift:3771-3831`, `CullHUDPresentation`
init at `Sources/TeststripApp/CullHUDPresentation.swift:6-37`,
`CullingProgressSummary` at `Sources/TeststripApp/AppModel.swift:123-141` +
`cullingProgressSummary` at `:2261-2269`, and `CullingAssistPresentation`
verdict synthesis at `Sources/TeststripApp/LibraryGridView.swift:7688-7768`.

Exact computation (read from source, not guessed):
- `undecidedCount = max(totalCount - pickCount - rejectCount, 0)`
- `progressFraction = reviewedCount / totalCount` where `reviewedCount =
  pickCount + rejectCount` (i.e. progress is fraction *decided*, not fraction
  *picked*) — `totalCount == 0` renders `0`.
- `pickCount`/`rejectCount` come from `cullingDecisionCounts()`, which counts
  over the **current scope's query** (`currentLibraryQuery()` + a `.flag`
  predicate), not the whole catalog — so these numbers are scope-relative.
- Verdict fallback in `cullHUDPresentation`:
  `verdict = assistPresentation.verdictText ?? (tone == .waiting ? nil :
  assistPresentation.title)`. `CullingAssistPresentation.verdict(for:)`
  requires `CullingStackRecommendation.normalizedQualityRead` with
  `kindCount >= 2` (at least two distinct scored quality kinds) to produce a
  `"Keep read N%"` / `"Toss read N%"` / `"Mixed read N%"` verdictText at all.
  With **zero** evaluation signals for the selected asset: `signals` is empty,
  `verdict(for:)` returns nil, and the presentation falls to the `"No read
  yet"` / `.waiting` branch — but because `tone == .waiting`, the HUD's final
  `verdict` is **nil**, so **no verdict chip renders at all** (the `"No read
  yet"` string is internal `title`, never shown in the HUD). With **one**
  signal (still < 2 kinds for a quality read) the HUD falls back to showing
  that signal's own `title` (a real string, tone non-`.waiting`). With **two+**
  quality-kind signals the HUD shows the synthesized `"Keep/Toss/Mixed read
  N%"` verdictText.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
script/ax_drive.sh wait-vended Teststrip
script/ax_drive.sh press --role AXButton --help "Cull" # or ⌘1 per workspace-switching.md convention
```

## Steps
1. Record scope-relative ground truth for the default scope (`all`, per
   `CullScope`):
   ```bash
   TOTAL=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")
   PICKS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='pick';")
   REJECTS=$(sqlite3 "$DB" "SELECT count(*) FROM assets WHERE json_extract(metadata_json,'\$.flag')='reject';")
   UNDECIDED=$((TOTAL - PICKS - REJECTS))
   ```
   (`--smoke` pre-seeds 11/24 flagged; confirm `PICKS + REJECTS` matches that
   split before trusting `UNDECIDED`.)
2. Open the loupe on the first frame (`script/ax_drive.sh press --role
   AXButton --label "<first filename>"` or arrow-key into the loupe per the
   grid-activation convention other cards use). Assert the HUD's "N left"
   text matches `UNDECIDED`:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "$UNDECIDED left"
   ```
3. Pick one previously-undecided frame (`P`) and reject another (`X`).
   Recompute `UNDECIDED2=$((UNDECIDED - 2))` and assert the HUD updates:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "$UNDECIDED2 left"
   ```
   Also assert the Picks/Rejects pill counts incremented by one each (find the
   pill's `AXValue`/label containing the new counts — read the exact
   accessibility surface `cullingCountPill` exposes before matching).
4. Cross-check one specific asset's filename/stars/scope/color-label pills
   against its actual `metadata_json`:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.rating'), json_extract(metadata_json,'\$.colorLabel') FROM assets WHERE id = '<focused-asset-id>';"
   ```
   Assert the rendered star count (`cullHUDRatingStars`) equals the rating and
   the filename text equals `originalURL.lastPathComponent` for that row
   (join against `assets.original_path` or whatever column holds it — verify
   the column name against the schema before running).
5. **Verdict fallback — no-signal case.** Find an asset with zero rows in
   `evaluation_signals` for the selected asset (check whichever table backs
   `EvaluationSignal` — confirm the exact table name against
   `CatalogMigrations.swift` before querying; do not guess), select it in the
   loupe, and assert **no verdict chip renders**:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "read yet" # expect failure/absent
   ```
   Fails if the literal string "No read yet" (or any verdict text) is found —
   the source computes it internally but the HUD suppresses it when
   `tone == .waiting`.
6. **Verdict fallback — real signal case.** Select an asset with 2+ distinct
   evaluation-signal kinds (focus + object detection, etc.) and assert the
   verdict chip shows one of `"Keep read "`, `"Toss read "`, `"Mixed read "`
   followed by a percentage:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "read " # then read its exact text
   ```

## Expected
- Step 2: HUD "N left" == sqlite-derived `UNDECIDED`. **Fails if** it
  reflects only the visible page, or drifts from the pick/reject counts.
- Step 3: HUD counters increment atomically with the P/X keystrokes — no lag,
  no double-count. **Fails if** the pill counts don't match `PICKS+1` /
  `REJECTS+1` exactly.
- Step 4: filename/stars/label pills match the focused asset's own
  `metadata_json` row, not a stale/neighboring asset's. **Fails if** they lag
  behind a selection change.
- Step 5: **Fails if** any verdict text renders for a signal-less asset — the
  HUD is supposed to render nothing, not a placeholder string.
- Step 6: **Fails if** the verdict text is missing, or shows the single-signal
  `title` fallback instead of the synthesized read (i.e. fewer than 2 quality
  kinds were actually present, invalidating the fixture choice — re-pick an
  asset, don't weaken the assertion).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- `pickCount`/`rejectCount` are **scope-relative** (computed off
  `currentLibraryQuery()`), not global catalog totals — if scope isn't `all`
  when you record `TOTAL`/`PICKS`/`REJECTS`, the HUD numbers won't match a
  naive `SELECT count(*) FROM assets` baseline. Force scope to `all` first
  (press `S` until the scope chip reads "All", or check `CullScope` default).
- The exact table/column names for `EvaluationSignal` persistence (step 5/6)
  were not verified against `CatalogMigrations.swift` in this pass — read the
  migration file's evaluation-signals table before writing the real query;
  don't guess the schema.
- The AX surface for `cullingCountPill` (step 3) wasn't independently
  confirmed — `find --contains` against the pill's rendered count text may
  need `--role AXStaticText` vs `AXButton`; inspect the live AX tree with
  `ax_drive.sh find` broadly before locking the match predicate.
- Step 1's default scope assumption (`all`) is inferred from `CullScope`
  usage elsewhere in the codebase (`cull-pass-scope-and-undo.md` cycles
  through it with `S`) but this card does not independently re-derive
  `CullScope`'s raw cases/default — confirm before running.

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md
