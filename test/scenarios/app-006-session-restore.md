# app-006-session-restore: quit and relaunch lands Jesse back where he left off

**What this covers**: Jesse quits mid-browse and relaunches; the app restores
his route, scope, selection, sort, search, and filters — and never restores a
culling session automatically. Inventory items 18-26
(`Sources/TeststripApp/SessionRestoreState.swift`,
`Tests/TeststripAppTests/AppModelSessionRestoreTests.swift`):
`SessionRestoreState` v1 restores view + asset set + asset + sort + search +
full filter set (18); culling is never restored (19); non-restorable routes
fall back to `.grid` (20); restore is best-effort with silent drops (21);
legacy `"search"`/`"copilot"` rawValues decode to `.grid`, unknown rawValues
throw `dataCorrupted` and discard the whole state (22,
`LibraryViewMode.init(from:)`, `Sources/TeststripApp/AppModel.swift:22-44`);
version gate: only `version == 1` loads (23); the defaults key is
per-catalog-root: `SessionRestoreState.<catalog root path>` (24); nil
defaults disables restore — unit-test-only, not driven here (25);
`autopilotEnabled`/`defaultCreator`/`defaultCopyright` persist separately
under their own keys (26).

## Pre-state
Run in the Tart VM — this card requires a quit/relaunch cycle against the
*same* isolated state, which `vm_scenario_run.sh launch` alone can't do (it
copies a fresh template every call). Instead:
```bash
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke      # note the run dir it prints:
RUN=~/teststrip-vm/run/<smoke-timestamp>    # (path inside the VM)
```
Relaunches must reuse `$RUN` by launching the app binary directly in the VM
shell with `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=$RUN` — do NOT call
`launch` again (that mints a new state dir and vacuously "fails" restore).

## Steps
1. `script/vm_scenario_run.sh ax wait-vended Teststrip`.
2. **Set a distinctive state.** In Library (⌘2): switch sub-view to
   Timeline; type a search query (e.g. `rating:3`) into the token field;
   set the sort order to something non-default via the sort control;
   select an asset.
3. **Quit cleanly** (⌘Q via osascript in the VM shell). Wait for the process
   to exit.
4. **Inspect the persisted blob (ground truth).** In the VM:
   ```bash
   defaults read com.teststrip.app | grep -A2 SessionRestoreState
   ```
   The key must be `SessionRestoreState.<catalog root path under $RUN>`
   (item 24) and the JSON data must contain `"version":1`,
   `"selectedView":"timeline"`, the search text, sort option, and the
   selected asset id.
5. **Relaunch against `$RUN`** (same binary, same env). `ax wait-vended`.
   Assert: Timeline renders, the token field shows the query, the same
   asset is selected (compare against the id from step 4), the sort control
   shows the non-default order.
6. **Culling never restores (item 19).** Switch to Cull (⌘1), start
   interacting (advance a frame or two), quit, relaunch. Assert the app
   comes back in a Library route, not mid-cull — the persisted
   `selectedView` must never be a cull mode.
7. **Legacy rawValue migration (item 22).** Quit. Edit the blob directly:
   read the defaults key, rewrite its JSON `selectedView` to `"search"`,
   write it back (`defaults write` with the hex/plist data, or a small
   python plistlib edit over the app's plist after `defaults export`).
   Relaunch: the app must come up on the Library **grid** (legacy `search`
   → `.grid`), silently, no error surface.
8. **Unknown rawValue discards (item 22/21).** Repeat step 7 with
   `selectedView` = `"nonsense-mode"`. Relaunch: the whole state is
   discarded (decode throws `dataCorrupted`, load returns nil) — the app
   comes up on defaults (grid, empty search) rather than crashing or
   half-restoring.
9. **Version gate (item 23).** Repeat with `"version":2` and a valid view.
   Relaunch: state discarded, defaults again.

## Expected
- Step 4: the per-catalog-root key exists with version 1 and the exact
  values set in step 2. **Fails if** the key is global (not path-suffixed) —
  switching catalogs would cross-restore.
- Step 5: all five facets restore. **Fails if** any one (view, search,
  selection, sort, set scope) silently resets — quote which.
- Step 6: relaunch never lands in a cull view. **Fails if** it does.
- Steps 7-9: `"search"` lands on grid; unknown rawValue and version≠1 both
  yield a clean default launch with no crash and no partial restore.
  **Fails if** the app crashes on a corrupt blob (restore must be
  best-effort, item 21) or restores anything from a discarded state.

## Cleanup
Delete the VM run dir and the defaults keys created:
```bash
script/vm_scenario_run.sh shell   # then: rm -rf "$RUN"; defaults delete com.teststrip.app
```
(Only delete the domain in the VM, never on the host.)

## Sharp edges
- `vm_scenario_run.sh launch` copies a FRESH template per call — using it
  for the relaunch silently tests nothing. Relaunch by exec'ing the app
  with the same `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY`.
- The restore state lives in the VM user's `defaults` (`.standard` of the
  app), NOT in the catalog sqlite — copying `$RUN` around does not carry it.
- The blob is stored as `Data` (JSON) under the defaults key; editing it
  needs an export/edit/import round-trip (`defaults export com.teststrip.app
  - | plutil`/python plistlib), not a naive `defaults write` of a string.
- Item 26: while in the defaults domain, also spot-check that
  `AppModel.defaultCreator`/`AppModel.defaultCopyright` and the autopilot
  toggle persist under their own separate keys (set them in app-015's flow);
  here just assert their keys are distinct from the SessionRestoreState key.
- Step 2's "non-default sort" — confirm the actual default first so the
  assertion is baseline-relative.
