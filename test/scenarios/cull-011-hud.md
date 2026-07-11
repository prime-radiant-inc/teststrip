# cull-011-hud: The Cull HUD's progressive-disclosure cluster and verdict fallback

**Rewritten for Task 6 (2026-07-11), per spec §2a:** the old HUD showed a
separate "N left" text, a separate progress bar, and separate Picks/Rejects
pills — all unconditionally, alongside an always-visible scope chip and
rating stars. That layout is gone. The pick/reject pills, the undecided
count, and the progress bar are now merged into one monospaced-digit session
cluster (`✓ 38 · ✕ 71 · 209 left`) with the thin progress bar rendered
*beneath* the cluster (not beside it). The scope chip, rating stars, and
color-label dot are now progressively disclosed — each renders only when it
carries information: scope chip only when scope ≠ All; rating stars only
when the frame has a rating **or** a rating key was pressed in the last 2s
(the same fade/timing source as the decision toast); label dot only when a
color label is set. An undecided frame in the default (`all`) scope with no
rating and no label now shows only the filename and the session cluster —
nothing else. This card's old step 2/3/4 assertions (a standalone "N left"
string, separate Picks/Rejects pill labels, unconditional scope chip and
stars) no longer match the rendered surface; they're replaced below.

**What this covers**: As a photographer culling a shoot I want the strip
above the loupe to tell me exactly where I am in the set — filename, session
cluster (picks/rejects/undecided, with progress beneath), and only the
scope/rating/label state that's actually meaningful right now — without
opening a side panel, and I want the verdict chip to be honest about whether
a frame has actually been read yet. Covered inventory items 32
(undecided/progress math) and 33 (verdict fallback rules), plus the Task 6
progressive-disclosure matrix. Source: `cullHUD`, `cullHUDPresentation`, and
`isRatingEchoActive` in `Sources/TeststripApp/LibraryGridView.swift`;
`CullHUDPresentation` (`showsScopeChip`/`showsRating`/`showsLabelDot`/
`sessionClusterText`) in `Sources/TeststripApp/CullHUDPresentation.swift`;
`CullingProgressSummary` at `Sources/TeststripApp/AppModel.swift:123-141` +
`cullingProgressSummary` at `:2261-2269`; `CullingAssistPresentation` verdict
synthesis in `Sources/TeststripApp/LibraryGridView.swift`; and the
decision-toast timing state (`isDecisionToastVisible`,
`lastCullingMetadataDecision`) that the rating echo window reuses.

Exact computation (read from source, not guessed):
- `undecidedCount = max(totalCount - pickCount - rejectCount, 0)`
- `progressFraction = reviewedCount / totalCount` where `reviewedCount =
  pickCount + rejectCount` (i.e. progress is fraction *decided*, not fraction
  *picked*) — `totalCount == 0` renders `0`.
- `pickCount`/`rejectCount` come from `cullingDecisionCounts()`, which counts
  over the **current scope's query** (`currentLibraryQuery()` + a `.flag`
  predicate), not the whole catalog — so these numbers are scope-relative.
- `sessionClusterText = "✓ \(pickCount) · ✕ \(rejectCount) · \(undecidedCount) left"`,
  rendered with `.monospacedDigit()`.
- `showsScopeChip = (scope != .all)`.
- `showsRating = (rating > 0) || isRatingEchoActive`, where
  `isRatingEchoActive` is true only while `isDecisionToastVisible` is true
  (the same 2s-then-fade timer driving the decision toast) **and**
  `lastCullingMetadataDecision.assetID` matches the selected asset **and**
  its `decisionText` is a rating decision (`"Rated N"` or `"Cleared
  rating"` — pick/reject/label decisions do not trigger the echo).
- `showsLabelDot = (colorLabel != nil)`.
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
2. Open the loupe on the first frame, choosing one that is **unrated,
   unlabeled, and undecided**, with scope at the default `all`
   (`script/ax_drive.sh press --role AXButton --label "<first filename>"` or
   arrow-key into the loupe per the grid-activation convention other cards
   use). Assert the session cluster renders and matches ground truth, and
   that the scope chip and rating stars are **absent**:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "✓ $PICKS · ✕ $REJECTS · $UNDECIDED left"
   script/ax_drive.sh find --role AXStaticText --contains "All" # expect failure/absent (no scope chip in default scope)
   ```
   Inspect the AX tree for the rating-stars group and confirm it isn't
   present for this asset (the group is entirely absent, not present-with-
   zero-stars — check the exact AX role/identifier `cullHUDRatingStars`
   exposes before asserting absence, since a naive `find` for "Rating" text
   may not exist even when rendered, verify against a rated asset first).
3. Pick one previously-undecided frame (`P`) and reject another (`X`).
   Recompute `UNDECIDED2=$((UNDECIDED - 2))`, `PICKS2=$((PICKS + 1))`,
   `REJECTS2=$((REJECTS + 1))`, and assert the merged cluster updates
   atomically:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "✓ $PICKS2 · ✕ $REJECTS2 · $UNDECIDED2 left"
   ```
4. **Rating echo window.** On an unrated asset, press a rating key (e.g. `3`).
   Immediately (within 2s) assert the rating stars are visible:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "Rating 3"
   ```
   Wait 3s (past the echo window) and re-check: with a nonzero rating the
   stars remain visible (rating > 0 keeps them shown independent of the echo).
   Repeat on a *different* unrated asset, press `0` (clear rating) to produce
   `"Cleared rating"` — assert stars are visible within the 2s window, then
   assert they disappear once the window elapses (rating is back to 0 and the
   echo has faded).
5. Cross-check one specific rated, labeled, non-default-scope asset's
   filename/stars/scope/color-label state against its actual `metadata_json`:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.rating'), json_extract(metadata_json,'\$.colorLabel') FROM assets WHERE id = '<focused-asset-id>';"
   ```
   Assert the rendered star count (`cullHUDRatingStars`) equals the rating,
   the scope chip is present and reads the non-`all` scope's label, the label
   dot is present with the correct color, and the filename text equals
   `originalURL.lastPathComponent` for that row (join against
   `assets.original_path` or whichever column holds it — verify the column
   name against the schema before running).
6. **Verdict fallback — no-signal case.** Find an asset with zero rows in
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
7. **Verdict fallback — real signal case.** Select an asset with 2+ distinct
   evaluation-signal kinds (focus + object detection, etc.) and assert the
   verdict chip shows one of `"Keep read "`, `"Toss read "`, `"Mixed read "`
   followed by a percentage:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "read " # then read its exact text
   ```

## Expected
- Step 2: session cluster == sqlite-derived `✓ PICKS · ✕ REJECTS · UNDECIDED
  left`, and the scope chip / rating stars are entirely absent for an
  unrated, default-scope, undecided frame. **Fails if** the cluster reflects
  only the visible page, drifts from the pick/reject counts, or the scope
  chip/stars render with empty/zero placeholder content instead of being
  absent.
- Step 3: the cluster updates atomically with the P/X keystrokes — no lag,
  no double-count. **Fails if** the numbers don't match `PICKS2`/`REJECTS2`/
  `UNDECIDED2` exactly.
- Step 4: rating stars appear immediately on a rating keystroke (including
  clear-to-zero) and stay visible for the 2s echo window even when the
  resulting rating is 0, then disappear once both the window has elapsed and
  the rating is 0. **Fails if** stars never appear for a "Cleared rating"
  echo, or stay visible indefinitely after the window elapses with rating 0.
- Step 5: filename/stars/scope chip/label dot match the focused asset's own
  `metadata_json` row and current scope, not a stale/neighboring asset's.
  **Fails if** they lag behind a selection change.
- Step 6: **Fails if** any verdict text renders for a signal-less asset — the
  HUD is supposed to render nothing, not a placeholder string.
- Step 7: **Fails if** the verdict text is missing, or shows the single-signal
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
  (press `S` until the scope chip is absent, since `all` no longer renders a
  chip at all — check `CullScope` default).
- The exact table/column names for `EvaluationSignal` persistence (steps
  6/7) were not verified against `CatalogMigrations.swift` in this pass —
  read the migration file's evaluation-signals table before writing the real
  query; don't guess the schema.
- The AX surface for the merged session cluster (steps 2/3) wasn't
  independently confirmed against a live AX tree — `find --contains` against
  the cluster's rendered text may need adjustment for the exact Unicode glyphs
  (`✓`/`✕`/`·`) the accessibility tree exposes; inspect with `ax_drive.sh
  find` broadly before locking the match predicate.
- The rating-echo timing (step 4) is driven by the same `isDecisionToastVisible`
  state as the decision toast, on a `Task.sleep(for: .seconds(2))` — timing
  assertions in a driven test need slack around the 2s boundary (poll near
  1.5s and again near 2.5s rather than asserting exactly at 2.0s) to avoid
  flaking on scheduling jitter.
- Step 1's default scope assumption (`all`) is inferred from `CullScope`
  usage elsewhere in the codebase (`cull-pass-scope-and-undo.md` cycles
  through it with `S`) but this card does not independently re-derive
  `CullScope`'s raw cases/default — confirm before running.

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md
