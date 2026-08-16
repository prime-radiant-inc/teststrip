# app-005-chrome-policy: the simplified chrome policy is live in the assembled UI

**What this covers**: Jesse lives in this chrome every session; the
simplification sweep must hold in the assembled window, not just in unit
tests. `LensChromePolicy` (`Sources/TeststripApp/LibraryGridView.swift:8260-
8316`) — the successor to `WorkspaceChromePolicy` after the workspace shell
was deleted — exposes ten chrome booleans (`showsBrowseChrome` plus nine
delegates: `showsSearchField`, `showsFilterTokens`, `showsImportButton`,
`showsFooter`, `showsInspector`, `showsImportMenu`, `showsCullButton`,
`showsExportButton`, `showsMoreMenu`), all gated on `view.lens`, not on a
`Workspace` case (`Workspace` no longer exists). Every delegate except
`showsInspector` is a bare call to `showsBrowseChrome`, which is `true` for
the four browse lenses (Grid/Loupe/Timeline/Map) and `false` for **both**
Cull and People — the "two focused lenses carry none of it" the enum's own
doc comment states. `showsInspector` is unconditionally `true` for every
lens, wired at `Sources/TeststripApp/main.swift:39-40`. Also the
UX-simplification sweep (spec `docs/superpowers/specs/2026-07-08-
teststrip-ux-simplification-proposal.md`) is a legibility pass over working
machinery — most of it only exists in the assembled AppKit chrome, where
unit tests and the headless gate can't see it. This card drives the live
window and asserts the new chrome is present and the old jargon is gone: the
marquee **Find Best Shots** action, the collapsed **Import ▾** / **⋯ More**
toolbar, the removal of the **Copilot** label, and the absence of the
three-Imports tangle. (There is no static "Review" sidebar row — the
sidebar's review-queue rows are named Picks/Likely Issues/etc. and only
render once their counts are non-zero; the sole surviving "Review" control
is the autopilot banner button, which appears only while ghosts exist.) It
also exercises the core promise that Find Best Shots never dead-ends the
user on a bare "0 keepers".

## Pre-state
- Fresh build, seeded isolated catalog so the grid and sidebar render real rows:
  ```bash
  ./script/build_and_run.sh --smoke
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```
- Keep the instance warm (drive shortly after launch; re-assert frontmost each
  poll — the `verify_people_clustering.sh` pattern). A long-idle instance parks
  its AX tree and this card will false-negative.

## Steps
1. **Confirm the app is vended.** `script/ax_drive.sh wait-vended Teststrip`.
2. **Run the chrome assertions.** `script/verify_ux_simplification_chrome.sh`
   drives `ax_drive.sh find` for each contract:
   - `Find Best Shots` (AXButton) is present.
   - The collapsed `Import` menu (AXButton) is present.
   - No top-level `Import Folder` **and** no top-level `Import Card` button
     remain (they moved under Import ▾).
   - No element anywhere still reads `Copilot`.
3. **Prove Find Best Shots lands on best shots, not a dead end.** AX-press
   `Find Best Shots`. `waitFor` the grid scope to change to a ranked view —
   the evaluation pass runs and the grid scopes down to a ranked set of
   photos (the "Potential Picks"/"Picks" breadcrumb literal is not currently
   rendered — naming drift, tracked separately — so do not gate the pass/fail
   on that exact string; assert instead that the scope count is non-zero and
   ranked, e.g. via `sqlite3` evaluation_signals growth), or (on a genuinely
   unrankable seed) the plain-language status
   `These look too distinct to auto-rank — rate a few to rank`. A bare
   `0 keepers` / `0 · 0` result is a **failure**.
4. **Cross-check the lens switcher, not a sub-view switcher.** The toolbar's
   `lensSwitcher` exposes all **six** lenses — `Cull`, `Grid`, `Loupe`,
   `Timeline`, `Map`, `People` — not a 4-way Library-only sub-view toggle;
   People is one of its six buttons now, not excluded from it. Assert
   `Search`, `Review`, `Places` are **not** switcher buttons (they live in
   the sidebar/toolbar elsewhere) — do **not** also assert People's absence
   here, since People is a legitimate lens button (the prior revision of
   this card asserted People's absence from the switcher, which was true
   under the old Library-sub-view-toggle design and is false now).
5. **Chrome policy per lens (`LensChromePolicy`).** Press ⌘2 (Grid): assert
   the search token field, Import ▾, Find Best Shots, Export, and the footer
   are present (`showsBrowseChrome(.grid) == true`). Press ⌘1 (Cull): assert
   *all* of those are absent (`showsBrowseChrome(.cull) == false`), and that
   ⌘I **does** open the inspector in place, without leaving Cull —
   `showsInspector` is unconditionally `true` and `AppModel.toggleInspector()`
   is a bare `isInspectorVisible.toggle()` with no lens-switching side
   effect (`AppModel.swift:4964-4968`). Press ⌘6 (People): assert the browse
   chrome (search field, Import ▾, Export, footer) is absent
   (`showsBrowseChrome(.people) == false`) and ⌘I opens the inspector here
   too.

## Expected
- Step 2: `verify_ux_simplification_chrome.sh` prints `PASS: …` and exits 0.
  **Fails if** any control is missing or the old jargon/three-Imports survive.
- Step 3: the app routes to a ranked queue or shows the plain-language line;
  the status/grid never shows a bare zero. Cross-check ground truth:
  ```bash
  sqlite3 "$DB" "SELECT count(*) FROM assets;"   # scope is non-empty; the
                                                 # route landed on real rows
  ```
- Step 4: exactly six lens buttons; `Search`/`Review`/`Places` are absent
  from the switcher (present elsewhere instead). **Fails if** People is
  reported absent from the switcher or if any of the three named controls
  IS found on the switcher.
- Step 5: browse chrome disappears in both Cull and People, never in Grid;
  ⌘I opens the inspector in place in every lens, including Cull. **Fails
  if** any browse control leaks into Cull/People, if browse chrome is
  missing in Grid, or if ⌘I fails to open the inspector, or changes the
  active lens, in any of the three lenses tried.

## Fixture status
Runnable with the standard `--smoke` seed (24 synthetic photos) — no special
fixture required. The plain-language branch in Step 3 is exercised when the
seed produces no likely-picks; the ranked-queue branch when it does. Either
outcome passes as long as the result is legible and never a bare zero.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- Views branch on `LensChromePolicy`, never on a raw lens/workspace case
  directly in the view body — if a step-5 assertion fails, cite which
  policy boolean disagrees with the rendered chrome (that is the
  regression, not the card).
- Step 3's full routing matrix (evaluate-then-route vs. picks vs.
  nothing-ranked) is app-011's job; here it is only a smoke check that the
  button never dead-ends.
- Activity (⇧⌘0 toolbar item) is global chrome and intentionally NOT gated by
  the policy — do not count its presence in Cull/People as a leak.
- `showsInspector`'s doc comment ("unified onto the Cull loupe in Task 5")
  and `toggleInspector`'s doc comment both explicitly disclaim any
  lens-switching side effect — if a live run ever sees ⌘I move the app out
  of Cull, that contradicts two independent doc comments and current source
  and is worth flagging loudly, not quietly working around.

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
rewritten for the lens shell. `WorkspaceChromePolicy` → `LensChromePolicy`
(same ten booleans, gated by `view.lens` — verified unchanged in count and
behavior, only the gating source and the enclosing type name changed).
Deleted the false `:59-60` claim that "⌘I does not open an inspector column
inside Cull — it switches to Library first": read directly,
`LensChromePolicy.showsInspector` (`LibraryGridView.swift:8289-8293`)
returns `true` unconditionally for every `LibraryViewMode`, and
`AppModel.toggleInspector()` (`AppModel.swift:4966-4968`) is
`isInspectorVisible.toggle()` with no branch on lens at all — there is no
code path left (if there ever was one on this branch) that redirects to
Library on ⌘I. Replaced it with the true contract: ⌘I toggles the inspector
in place, in every lens including Cull. Also corrected Step 4: the prior
revision asserted People's absence from the switcher, which is now false —
People is one of the switcher's six lens buttons; only `Search`/`Review`/
`Places` remain correctly excluded. Retitled ⌘2/⌘1/⌘3 to their lens meanings
(Grid/Cull/People is now ⌘6, not ⌘3 — ⌘3 is the Loupe lens) throughout Step
5. Supersedes prior status: this card is TWO stale claims deep independent
of the unified-shell push — the `:59-60` inspector claim was already false
before this push (per the task-13 brief's own flag, verified above against
source rather than taken on faith), and the People-excluded-from-switcher
claim became false only once this push made People a lens. Any prior
LEDGER `Tested-Fail` result for this card is unrelated to both of these
(a script/card drift on a different surface per the note it carried) and
remains uninformative either way. Needs a fresh VM run.
