# ux-simplification-chrome: the legibility sweep is live in the assembled UI

**What this covers**: the UX-simplification sweep (spec
`docs/superpowers/specs/2026-07-08-teststrip-ux-simplification-proposal.md`) is
a legibility pass over working machinery — most of it only exists in the
assembled AppKit chrome, where unit tests and the headless gate can't see it.
This card drives the live window and asserts the new chrome is present and the
old jargon is gone: the marquee **Find Best Shots** action, the collapsed
**Import ▾** / **⋯ More** toolbar, the **Copilot → Review** rename, and the
absence of the three-Imports tangle. It also exercises the core promise that
Find Best Shots never dead-ends the user on a bare "0 keepers".

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
   - A `Review` sidebar row (AXStaticText) is present.
3. **Prove Find Best Shots lands on best shots, not a dead end.** AX-press
   `Find Best Shots`. `waitFor` the grid scope to change to the ranked view —
   either the **Potential Picks** / **Picks** breadcrumb, or (on a genuinely
   unrankable seed) the plain-language status
   `These look too distinct to auto-rank — rate a few to rank`. A bare
   `0 keepers` / `0 · 0` result is a **failure**.
4. **Cross-check the switcher de-dup.** The top view-switcher exposes only
   `Grid`, `Loupe`, `Compare` — assert `Search`, `Review`, `Timeline`,
   `People`, `Places` are **not** switcher buttons (they live in the sidebar).

## Expected
- Step 2: `verify_ux_simplification_chrome.sh` prints `PASS: …` and exits 0.
  **Fails if** any control is missing or the old jargon/three-Imports survive.
- Step 3: the app routes to a ranked queue or shows the plain-language line;
  the status/grid never shows a bare zero. Cross-check ground truth:
  ```bash
  sqlite3 "$DB" "SELECT count(*) FROM assets;"   # scope is non-empty; the
                                                 # route landed on real rows
  ```
- Step 4: exactly three switcher buttons; the five set-routes are absent from
  the switcher (present in the sidebar instead).

## Fixture status
Runnable with the standard `--smoke` seed (24 synthetic photos) — no special
fixture required. The plain-language branch in Step 3 is exercised when the
seed produces no likely-picks; the ranked-queue branch when it does. Either
outcome passes as long as the result is legible and never a bare zero.
