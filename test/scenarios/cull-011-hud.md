# cull-011-hud: The Cull HUD's progressive-disclosure cluster

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
opening a side panel. Covered inventory item 32 (undecided/progress math),
plus the Task 6 progressive-disclosure matrix. The verdict-fallback rules
(inventory item 33) are **not** covered by this card: the HUD itself carries
no verdict at all — `CullHUDPresentation`'s doc comment states "the assist
verdict is deliberately absent (one home per fact): the right panel's reads
card owns it," and `cullHUDPresentation(for:)`
(`Sources/TeststripApp/LibraryGridView.swift`) builds the struct with no
verdict field or fallback logic whatsoever. That assertion belongs to, and is
already covered by, `cull-024-honest-states.md`'s Reads-panel steps (its
step 4 and Source section cite the same `CullReadsCardPresentation`/
`CullingAssistPresentation` verdict synthesis this card previously,
incorrectly, attributed to the HUD). Source: `cullHUD`, `cullHUDPresentation`,
and `isRatingEchoActive` in `Sources/TeststripApp/LibraryGridView.swift`;
`CullHUDPresentation` (`showsScopeChip`/`showsRating`/`showsLabelDot`/
`sessionClusterText`) in `Sources/TeststripApp/CullHUDPresentation.swift`;
`CullingProgressSummary` at `Sources/TeststripApp/AppModel.swift:119-137` +
`cullingProgressSummary` at `:2754-2763` (line numbers drift as the file grows;
re-grep `struct CullingProgressSummary`/`var cullingProgressSummary` if these
are stale again); and the decision-toast timing state
(`isDecisionToastVisible`, `lastCullingMetadataDecision`) that the rating
echo window reuses.

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
  its `isRatingDecision` is true (the feedback carries the originating
  `CullingCommand`; only the `.rating` case — including clear-to-zero —
  triggers the echo; pick/reject/label decisions do not).
- `showsLabelDot = (colorLabel != nil)`.

The HUD has no verdict field and no verdict-fallback logic —
`cullHUDPresentation(for:)` builds `CullHUDPresentation` from exactly
`filename`/`rating`/`colorLabel`/`summary`/`scope`/`isRatingEchoActive`,
nothing else. The `"Keep"`/`"Toss"` verdict text (and its no-signal/
single-signal/Mixed fallback rules) is synthesized by
`CullReadsCardPresentation.presentation(for:)` and rendered in the right
panel's reads card, not this HUD — see `cull-024-honest-states.md`.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
script/ax_drive.sh wait-vended Teststrip
script/ax_drive.sh press --role AXButton --help "Cull" # or ⌘1 (Cull lens) per app-019-lens-shell.md convention
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
   use).

   **Fixture gap (confirmed 2026-07-28): no `--smoke` asset ever satisfies all
   three conditions.** `Sources/TeststripBench/SmokeCatalogSeeder.swift`
   (~line 134-147) unconditionally cycles `colorLabel =
   ColorLabel.allCases[index % 5]` for every one of the 24 seeded assets, so
   `colorLabel` is never nil — the label dot can never be absent on this
   fixture. Separately, `rating = index % 6` and `flag = index%5==0 ? .reject
   : (index%3==0 ? .pick : nil)` mean every index with `rating == 0` is also a
   multiple of 3, hence always decided (pick or reject) — no undecided asset
   ever has `rating == 0`. Test the three progressive-disclosure booleans
   independently instead of requiring one asset that satisfies all three:
   - **Session cluster + scope chip absence** — undecided, scope `all`, any
     rating (e.g. `smoke-1`, rating 1, undecided):
     ```bash
     script/ax_drive.sh find --role AXStaticText --contains "$PICKS picks, $REJECTS rejects, $UNDECIDED left"
     script/ax_drive.sh find --role AXStaticText --contains "Cull filter" # expect failure/absent (no scope chip when scope == all)
     ```
     (The rendered glyph text is `✓ N · ✕ N · N left`, but SwiftUI's
     `.accessibilityLabel` override replaces what the AX tree exposes with the
     spelled-out form above — confirmed live; searching for the glyph string
     finds nothing even though it's what's on screen.)
   - **Rating-stars absence** — any asset with `rating == 0` (decided is fine;
     flag doesn't gate `showsRating`), e.g. `smoke-0`/`smoke-6`/`smoke-12`/
     `smoke-18`:
     ```bash
     script/ax_drive.sh find --contains "Rating 0" # expect failure/absent
     ```
     Do **not** search bare `"Rating"` — it collides with the loupe's bottom
     metadata overlay (`"Rating: 0"`) and menu items (`"Clear Rating (0)"`)
     that exist regardless of the HUD. The HUD's rating-stars group has role
     **AXImage** (one match per star glyph, so a positive search returns 5
     hits for `"Rating N"`), not `AXStaticText` — verify against a rated asset
     first (`smoke-1`, rating 1, → `find --contains "Rating 1"`, no `--role`
     needed) before asserting absence.
   - **Label-dot absence**: **not executable against `--smoke`** — every asset
     has a color label (see fixture gap above). If this needs coverage, seed a
     fixture variant with at least one nil-colorLabel asset, or accept the
     `showsLabelDot == false` branch as covered only by
     `CullHUDPresentationTests` unit coverage.
3. Pick one previously-undecided frame (`P`) and reject another (`X`).
   Recompute `UNDECIDED2=$((UNDECIDED - 2))`, `PICKS2=$((PICKS + 1))`,
   `REJECTS2=$((REJECTS + 1))`, and assert the merged cluster updates
   atomically:
   ```bash
   script/ax_drive.sh find --role AXStaticText --contains "$PICKS2 picks, $REJECTS2 rejects, $UNDECIDED2 left"
   ```
   **Auto-advance overshoots a plain arrow-key navigation between the two
   decisions.** Any culling decision (P/X/rating/color-label/clear) advances
   the loupe to the next frame automatically when `cullAutoAdvanceEnabled`
   (default on, footer chip "Auto-advance on/off", toggled by `A` —
   `Sources/TeststripApp/AppModel.swift` `applyCullingCommandAndAdvance`).
   So after pressing `P`, the loupe has *already* moved to the next frame;
   a driver that then presses → to "move to the next frame" before pressing
   `X` actually skips one frame further and may land on an already-decided
   one. Re-verify the focused asset's id/flag (`ax_drive.sh find --contains
   "Frame N"` cross-checked against sqlite, or just read the DB by frame
   position) before the second decision, rather than counting arrow-presses.
4. **Rating echo window.** **First toggle auto-advance off (press `A`; confirm
   the footer chip reads "Auto-advance off").** This is required, not
   optional: `isRatingEchoActive(for:)` only reads true for the asset
   *currently displayed* (`feedback.assetID == asset.id`), but every rating
   keystroke routes through `applyCullingCommandAndAdvance`, which — with
   auto-advance on (the default) — advances the loupe to the next frame in
   the same synchronous call that applies the rating, before any render can
   show the echo on the rated frame. Confirmed live: with auto-advance on,
   pressing a rating key immediately moves "Frame N" → "Frame N+1" and the
   star echo never appears on the just-rated asset; with auto-advance off the
   loupe stays put and the echo behaves exactly per spec (see Run status).

   On an asset with `rating == 0` (e.g. `smoke-6`/`smoke-12`/`smoke-18` in
   `--smoke` — flag doesn't matter), press a rating key (e.g. `3`).
   Immediately (within 2s) assert the rating stars are visible:
   ```bash
   script/ax_drive.sh find --contains "Rating 3" # role is AXImage, not AXStaticText — 5 hits, one per star
   ```
   Wait 3s (past the echo window) and re-check: with a nonzero rating the
   stars remain visible (rating > 0 keeps them shown independent of the echo).
   Repeat on a *different* `rating == 0` asset, press `0` (clear rating; it's
   already 0, but pressing it still fires a `.rating(0)` decision and its
   echo) to produce `"Cleared rating"` — assert stars are visible within the
   2s window (`find --contains "Rating 0"`), then assert they disappear once
   the window elapses (rating is back to 0 and the echo has faded).
5. Cross-check one specific rated, labeled, non-default-scope asset's
   filename/stars/scope/color-label state against its actual `metadata_json`:
   ```bash
   sqlite3 "$DB" "SELECT id, json_extract(metadata_json,'\$.rating'), json_extract(metadata_json,'\$.colorLabel') FROM assets WHERE id = '<focused-asset-id>';"
   ```
   Assert the rendered star count (`cullHUDRatingStars`) equals the rating
   (`find --contains "Rating N"`), the scope chip is present and reads the
   non-`all` scope's label (its AX text is `"Cull filter: <Label>"`, e.g.
   `"Cull filter: Unrated"` when scoped via `S` — not the bare label; `find
   --label "Unrated"` alone will not match), the label dot is present with
   the correct color (`find --contains "<Color> label"`, e.g. `"Blue label"`
   — role AXUnknown, not AXStaticText), and the filename text equals
   `originalURL.lastPathComponent` for that row (join against
   `assets.original_path` — confirmed column name live).
6. **Hover-reveal decision controls (Jesse's ruling 2026-07-11; cull loupe
   only — the library loupe stays chrome-free).** With the cull loupe open,
   move the pointer over the stage: a P/X/star control cluster (AX label
   "Cull decision controls") fades in near the bottom edge. Assert:
   - it appears on pointer movement and disappears after ~1.5s of pointer
     idle (poll near 1.0s and again near 2.0s — same slack rationale as the
     rating-echo timing);
   - pressing any culling key (e.g. →) hides it immediately;
   - clicking its Pick control writes `flag='pick'` for the focused asset in
     the catalog, identical to pressing `P` (same
     `applyCullingShortcut(.pick)` path);
   - in the **library** loupe the cluster never appears on hover;
   - the buttons' AXHelp/tooltips teach the keys (persona-8): the Pick
     button's help is "Pick this photo (P)" and Reject's is
     "Reject this photo (X)" (`script/ax_drive.sh find --help "Pick this photo (P)"`).
   State machine unit coverage: `CullLoupeHoverControlsTests`; presentation:
   `Sources/TeststripApp/CullLoupeHoverControlsPresentation.swift`.
   BLOCKED: `ax_drive.sh`/`vm_scenario_run.sh` have no verb that simulates
   pointer *movement* (only clicks — `AXPress`/a `CGEvent` click at a matched
   element's center). Attempted 2026-07-28 with two ad hoc `CGEvent`
   `.mouseMoved` injections on the VM (one single-shot via
   `.cghidEventTap`, one 20-step incremental sweep via `.cgSessionEventTap`
   with an explicit re-frontmost first); `NSEvent.mouseLocation` confirmed
   the OS cursor genuinely relocated to the intended point inside the loupe
   stage both times, but the SwiftUI `.onContinuousHover`-driven "Cull
   decision controls" overlay never appeared either time. Whether that's a
   restriction on synthetic hover delivery in this VM/remote-session context
   or something else wasn't root-caused — needs either a real pointing
   device (VNC-driven mouse) or a harness verb built and validated for
   continuous-hover simulation (`cliclick` is not installed on the current
   VM image) before this step can be driven live.

## Expected
- Step 2: session cluster (AX text `"PICKS picks, REJECTS rejects, UNDECIDED
  left"`) == sqlite-derived ground truth on an undecided, default-scope
  frame, and the scope chip / rating stars are each independently absent when
  their own condition doesn't hold (scope == all; rating == 0) — see the
  fixture-gap note in Step 2 for why one asset satisfying all three at once
  isn't obtainable from `--smoke`. **Fails if** the cluster reflects only the
  visible page, drifts from the pick/reject counts, or the scope chip/stars
  render with empty/zero placeholder content instead of being absent.
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
- Step 6: controls appear on hover, hide on 1.5s idle and on any keystroke,
  and the Pick click writes the same catalog flag as `P`. **Fails if** the
  cluster appears in the library loupe, never hides, or its buttons write
  through a different code path than the keys.

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
  chip at all — check `CullScope` default). Jesse ruled (2026-07-11) the
  session-cluster counts stay set totals as-is — resolved, no longer an open
  question.
- The hover-reveal controls (step 6) share the loupe stage's hover surface
  with zoom/pan gestures — any pointer movement over the stage re-reveals
  the cluster; that's by design. Reduced-motion users get no fade animation
  (`.identity` transition); visibility timing is identical.
- **Confirmed live (2026-07-28): the AX surface for the merged session
  cluster does *not* expose the rendered glyphs.** `Text(sessionClusterText)`
  carries an explicit `.accessibilityLabel("\(pickCount) picks,
  \(rejectCount) rejects, \(undecidedCount) left")` in
  `Sources/TeststripApp/LibraryGridView.swift`, and that override — not the
  `✓ N · ✕ N · N left` glyph string that's actually painted on screen — is
  what `ax_drive.sh find` sees (role `AXStaticText`). Match on the spelled-out
  form; the glyph string will never be found via AX even though it's what a
  screenshot shows.
- **Confirmed live: `--smoke`'s `SmokeCatalogSeeder` can't produce the Step
  2 fixture.** Every seeded asset gets a non-nil `colorLabel` (cycles all 5
  `ColorLabel` cases with no gap), and every `rating == 0` index is also a
  pick/reject index (both keyed off `index % 3`/`index % 5`/`index % 6`), so
  no asset is ever simultaneously undecided + rating 0 + unlabeled. See Step
  2 for the per-boolean substitute assertions this card now uses instead.
- **Confirmed live: any culling decision — not just P/X — auto-advances the
  loupe when `cullAutoAdvanceEnabled` (default on).** This affects two
  things: (1) a driver navigating by counting arrow-presses after a decision
  will overshoot by one frame (Step 3); (2) the rating-echo window (Step 4)
  is unobservable in the HUD with auto-advance on at all, because the
  displayed asset changes in the same call that applies the rating, before
  any render shows the echo on the rated frame. Toggle auto-advance off
  (`A`) before Step 4.
- The rating-echo timing (step 4) is driven by the same `isDecisionToastVisible`
  state as the decision toast, on a `Task.sleep(for: .seconds(2))` — timing
  assertions in a driven test need slack around the 2s boundary (poll near
  1.5s and again near 2.5s rather than asserting exactly at 2.0s) to avoid
  flaking on scheduling jitter.
- Step 1's default scope assumption is confirmed:
  `public private(set) var cullScope: CullScope = .all`
  (`Sources/TeststripApp/AppModel.swift`); `CullScope`'s raw cases are
  `[unrated, picks, rejects, all]`, cycled by `S` via `CullScope.next()`.
- No verb in `ax_drive.sh`/`vm_scenario_run.sh` simulates pointer movement
  (only clicks); Step 6 needs one — see its BLOCKED note above for what was
  tried on 2026-07-28.

## Run status
2026-07-28 — app 878f1939, driven live via `script/vm_scenario_run.sh`
against the `smoke` seed in the `teststrip-e2e` Tart VM.
**PASS-WITH-CARD-FIXES** (steps 1-5); **step 6 remains BLOCKED** (no
hover-simulation primitive; not an app defect — see Step 6 and Sharp edges).

- Step 1 (ground truth): PASS. `TOTAL=24 PICKS=6 REJECTS=5 UNDECIDED=13`
  (`PICKS+REJECTS=11` matches the documented 11/24-flagged smoke split).
- Step 2: PASS on the assertions this fixture can produce.
  - Session cluster on undecided `smoke-1` (rating 1, scope all): AX text
    `"6 picks, 5 rejects, 13 left"` — matches ground truth.
  - Scope chip absent at scope `all`: confirmed (`"Cull filter"` not found
    anywhere in the tree).
  - Rating stars absent at `rating == 0` (`smoke-0`, decided/reject):
    confirmed absent (`"Rating 0"` not found); confirmed present at
    `rating == 1` (`smoke-1` → `"Rating 1"`, 5 `AXImage` hits) and via a
    color-label positive control (`smoke-0` → `"Red label"` found, role
    `AXUnknown`).
  - Label-dot absence: **NOT EXECUTABLE** — fixture gap (every smoke asset
    has a color label; see Step 2/Sharp edges).
- Step 3: PASS. Baseline 6/6/12 (after an earlier auto-advance-overshoot
  false start documented below) → picked `smoke-4` (undecided → pick) →
  cluster `"7 picks, 6 rejects, 11 left"` confirmed via AX + sqlite → rejected
  `smoke-7` (undecided → reject) → cluster `"7 picks, 7 rejects, 10 left"`
  confirmed via AX + sqlite. Both transitions atomic, no lag, no
  double-count. (First attempt hit the auto-advance overshoot described in
  Sharp edges — picking `smoke-1` then arrowing once landed on already-picked
  `smoke-3` instead of undecided `smoke-2`; net counts still happened to
  balance by coincidence, but the intended "reject a previously-undecided
  frame" wasn't what occurred, so it was redone cleanly with per-step sqlite
  verification.)
- Step 4: PASS, after toggling auto-advance off (see Sharp edges — with it on,
  the echo is unobservable by design). On `smoke-12` (rating 0): pressed `3`,
  `"Rating 3"` visible immediately (<1.5s), still visible 3s+ later (rating
  stays 3). Then pressed `0` on the same asset (rating 3 → 0): `"Rating 0"`
  visible immediately, confirmed absent again 3s+ later once the echo window
  elapsed. Frame stayed put throughout (auto-advance off), confirmed via
  "Frame N" text each time.
- Step 5: PASS. `smoke-13` (scope `Unrated`): `metadata_json` shows
  `rating=1, colorLabel=blue, flag=null`. Rendered: filename "smoke-13.jpg",
  `"Rating 1"` (1 star), `"Cull filter: Unrated"` chip present, `"Blue
  label"` dot present. All four match ground truth.
- Step 6: BLOCKED — see the step's own note and Sharp edges. No app-code
  changes were made or needed; this is a harness gap.

Tally: 1 full pass (step 1) + 4 steps passing on every assertion the fixture
supports (steps 2 partial/3/4/5) + 1 step blocked by a harness limitation
(step 6). No app bugs found — every discrepancy traced to AX-label-vs-render
text (by design), the smoke fixture's fixed color-label/rating cycling, or
auto-advance's documented default-on behavior, not to `CullHUDPresentation`
logic, which matched its spec exactly in every live check.

**Reconciled 2026-08-09 (Task 13, unified-shell preamble sweep)**: Pre-state
cited `app-003-workspace-switching.md`'s convention for landing on the Cull
loupe via ⌘1; that card was replaced wholesale by this push (now a stub
pointing at `app-019-lens-shell.md`), so the citation is repointed there.
⌘1's actual effect (select the Cull lens) is unchanged. Preamble/citation
only; the assertions (session cluster, rating echo, hover-reveal controls)
were not affected. Supersedes prior status: the 2026-07-28 PASS-WITH-
CARD-FIXES evidence above is unaffected — it never depended on which
convention doc the launch comment cited.
