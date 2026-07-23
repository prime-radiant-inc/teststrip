# import-cull-pick-happy-path: A first session, import to picks

**What this covers**: the everyday dogfood journey end to end — import a
folder → previews render and auto-evaluate → open culling → read the Keep/Toss
verdict strip → accept a recommended frame → see it land in Picks. This is the
narrative-select loop Teststrip exists for. If a layer between import and picks
regresses (evaluation never drains, verdict strip stays blank, "View Picks"
shows nothing), this card catches it where per-feature unit tests can't.

## Pre-state
- Fresh build, isolated catalog (starts with synthetic seed already cataloged;
  we import a *new* folder on top so the import path is exercised for real):
  ```bash
  ./script/build_and_run.sh --smoke
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```
- A fixture folder of a handful of JPEGs to import: `IMP=$(mktemp -d)/shoot`.
  Reuse the same JPEG-writing path the import verifiers use; a small burst
  (5–10 frames, some sharp, some soft) gives the verdict strip something to
  rank. Record the baseline: `A0=$(sqlite3 "$DB" "SELECT count(*) FROM assets;")`.

## Steps
1. **Import the folder.** `script/activate_app.sh Teststrip`. Use the typed
   **Import Path** entry (avoids the native panel — same approach as
   `script/verify_import_path.sh`), type `$IMP`, and in the confirmation sheet
   leave **"Read imported frames automatically"** ON (default; it now lives
   under the sheet's "Options" disclosure, unopened). Press the primary
   button — labeled **"Import N Photos"** (N = the scanned count; match with
   `--contains "Import"` or use Return, bound to `.keyboardShortcut(.defaultAction)`).
2. **Wait for import + evaluation to drain.** `waitFor` the completion panel
   (an `AXStaticText` / button set including **"Start culling"** and
   **"Review imported frames"**). Watch the Activity panel drain if needed.
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets;"    # must be A0 + (frames imported)
   ```
3. **Enter culling.** AX-press **"Start culling"** (or "Review imported
   frames"). `waitFor` the culling surface.
4. **Assert the verdict strip reads.** Re-dump; find an `AXStaticText` matching
   exactly **"Keep"** or **"Toss"** on the selected frame — no "read" suffix,
   no percentage (a Mixed/indecisive read renders no verdict label at all).
5. **Accept a recommendation.** AX-press the recommended-frame action
   (accessible label begins **"Keep recommended"** or **"Keep primary"**).
   Re-dump; confirm the picked frame now shows a pick/keep badge.
6. **See it in Picks.** AX-press **"View Picks"** (or open the **"Potential
   Picks"** queue). `waitFor` the picked frame to appear there.

## Expected
- Step 2: asset count rose by exactly the number of imported frames; the
  completion panel offers culling actions. **Fails if** the count didn't rise
  (import silently no-op'd) or the completion panel never appears within 30s.
- Step 4: a literal `Keep` or `Toss` string, exactly that word, no suffix.
  **Fails if** the strip is blank or shows a placeholder — evaluation didn't
  reach the render — or if it shows the old `Keep read N%`/`Toss read N%`
  wording. Quote the actual string. (Per the calibration note, a read that
  seems *wrong* is a threshold issue, not a test failure — record the value,
  don't fail the card on the verdict's polarity. If the read lands Mixed, no
  verdict label renders at all — that's the honest-states behavior, not a
  missing-render bug; pick a different fixture frame to test the render
  itself.)
- Step 5: the accepted frame gains a pick/keep badge. **Fails if** pressing the
  recommendation changes nothing.
- Step 6: the picked frame is present in the Picks/Potential Picks view.
  **Fails if** Picks is empty after an accepted recommendation — the pick
  didn't propagate. Present-but-scrolled-off ≠ absent: scroll the queue before
  concluding it's missing.

## Cleanup
```bash
rm -rf "$(dirname "$IMP")"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- Evaluation is asynchronous. Don't enter culling (step 3) until the Activity
  panel shows the imported set's reads drained, or the verdict strip will be
  legitimately blank and step 4 will misfire on timing, not on a real bug.
- The recommended-frame action's exact label varies with stack shape
  ("Keep recommended \<frame\>", "Keep primary", "Keep #1 & #2"). Match on the
  **"Keep "** prefix + a rank/frame token, not an exact string.
- This card asserts the *flow*, not verdict correctness. Verdict-threshold
  sign-off is a separate concern (see the handoff's threshold thread).
