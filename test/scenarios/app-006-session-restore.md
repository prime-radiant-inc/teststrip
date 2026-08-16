# app-006-session-restore: quit and relaunch lands Jesse back where he left off

**What this covers**: Jesse quits mid-browse and relaunches; the app restores
his source, lens, scope, selection, sort, search, and filters — and never
restores a culling run automatically. `SessionRestoreState`
(`Sources/TeststripApp/SessionRestoreState.swift:9-46`) is now **v2**: it
persists `lens: LibraryLens` and `source: LibrarySource` (there is no
persisted `selectedView`/route any more — the old `LibraryViewMode` route
persistence and its `"search"`/`"copilot"` legacy-rawValue migration are both
gone), plus `selectedAssetSetID`, `selectedAssetID`, `sortOption`,
`librarySearchText`, the full filter set, and `detachedFilterPredicates`
(`SessionRestoreState.swift:16-45`). **No back-compat**: the struct's own
doc comment states it plainly — "v1 persisted a `selectedView` route and no
source at all. `load()` discards a mismatched version, so a v1 blob simply
cold-starts the app" (`SessionRestoreState.swift:10-12`). There is no
per-field migration path any more; a version mismatch discards the *entire*
blob (`SessionRestoreStore.load()`, `:72-79`, `state.version ==
SessionRestoreState.currentVersion` or `nil`).

**Culling is never restored, and the rule is simpler than "mid-cull"
suggests.** `applyRestoredSessionState` calls `selectLens(Self
.isRestorableLens(state.lens) ? state.lens : .grid)`
(`AppModel.swift:12370`). `isRestorableLens` (`AppModel.swift:12401-
12405`) is `lens != .cull` — **unconditional**. Its own doc comment reads
"Every lens survives a relaunch except Cull: a mid-cull quit relaunches on
the same source in Grid, because the run itself is not resumed here" — but
the check itself does not look at whether a culling run was actually active;
quitting while the Cull lens is merely *selected*, run active or not,
relaunches on the same source in Grid. Every other lens (Grid, Loupe,
Timeline, Map, People) restores as-is. `app-019-lens-shell.md`'s Step 9
already drives this exact rule live; this card's item 19/20 legs below are
this card's own independent coverage of the same rule from the
session-restore angle, not a duplicate to be skipped.

**Completion toasts never resurrect across relaunch.** The old
`LibraryGridChromePolicy.shouldShowImportCompletionSummary` this card used
to cite for the "no zombie completion panel" check does not exist —
`grep -rn "shouldShowImportCompletionSummary" Sources/` finds nothing. Its
successor is `ImportCompletionToastPresentation.toast(for:
isCurrentSessionActivity:isImporting:)` (`ImportCompletionToastPresentation
.swift:40-58`), which returns `nil` whenever `isCurrentSessionActivity` is
`false` — and `AppModel.isCurrentSessionActivity(id:)`
(`AppModel.swift:14401-14407`) is scoped to activities recorded in the
*current* process's lifetime, so a relaunch can never satisfy it for
anything from the prior run. The persisted work session and its sidebar
Imports row are unaffected by this and remain reachable.

Item 26 (`autopilotEnabled`/`defaultCreator`/`defaultCopyright` persist
under their own keys, separate from `SessionRestoreState`) is unchanged by
this push (`AppModel.swift:2485-2506`, `:4485-4488`) and still worth a
spot-check.

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
2. **Set a distinctive state.** In the Timeline lens (⌘4): type a search
   query (e.g. `rating:3`) into the token field; set the sort order to
   something non-default via the sort control; select an asset.
3. **Quit cleanly** (⌘Q via osascript in the VM shell). Wait for the process
   to exit.
4. **Inspect the persisted blob (ground truth).** In the VM:
   ```bash
   defaults read com.teststrip.app | grep -A2 SessionRestoreState
   ```
   The key must be `SessionRestoreState.<catalog root path under $RUN>`
   (item 24) and the JSON data must contain `"version":2`, `"lens":"timeline"`,
   the search text, sort option, and the selected asset id.
5. **Relaunch against `$RUN`** (same binary, same env). `ax wait-vended`.
   Assert: the Timeline lens renders, the token field shows the query, the
   same asset is selected (compare against the id from step 4), the sort
   control shows the non-default order.
6. **Culling never restores, unconditionally (item 19/20).** Switch to Cull
   (⌘1) against some source, quit, relaunch. Assert the app comes back with
   that same **source** selected but in the **Grid** lens, not Cull —
   regardless of whether a culling run was actively in progress at quit
   time. Repeat once more, this time actually advancing a frame or two in
   the Cull loupe before quitting, and confirm the outcome (Grid, same
   source) is identical — the rule does not care whether a run was active.
7. **Version gate, source of truth is the whole blob (item 22/23).** Quit.
   Edit the persisted blob directly: read the defaults key, rewrite its JSON
   `"version"` field to `1` (or any value other than `2`), write it back
   (`defaults export`/plistlib round-trip, since the blob is `Data`/JSON,
   not a plain string). Relaunch: the *entire* state must be discarded —
   the app comes up on defaults (Grid lens, `.allPhotos` source, empty
   search, default sort), not a partial restore of the fields that still
   parse. This replaces the prior revision's separate "legacy rawValue"
   and "unknown rawValue" sub-steps — there is no field-level migration left
   to exercise; `version` mismatch is the only discard path now, and it is
   all-or-nothing.
8. **Malformed JSON also discards cleanly (item 21).** Repeat step 7 but
   corrupt the JSON body itself (e.g. truncate it) instead of touching
   `version`. Relaunch: same clean-default outcome, no crash — restore is
   best-effort (`SessionRestoreStore.load()`'s `try?` decode returning
   `nil` on any decode failure, not just a version mismatch).
9. **No zombie completion toasts across relaunch.** Run an import (any
   route; the typed-path route avoids native panels), wait for the
   completion toast to appear, then quit without waiting for it to fade and
   relaunch against the same `$RUN`. The toast must NOT reappear (`ax find`
   for its "Import complete" label fails), while the import itself remains
   listed under the sidebar's Imports section and the Activity bell's
   "Recent Imports" receipt.

## Expected
- Step 4: the per-catalog-root key exists with version 2 and the exact
  values set in step 2. **Fails if** the key is global (not path-suffixed) —
  switching catalogs would cross-restore.
- Step 5: all facets restore (lens, search, selection, sort). **Fails if**
  any one silently resets — quote which.
- Step 6: relaunch after a Cull-lens quit always lands in Grid on the same
  source, whether or not a run was active. **Fails if** it restores to Cull,
  or if the two variants (idle vs. mid-run) behave differently — the rule is
  supposed to be unconditional.
- Step 9: no toast after relaunch, import still reachable via the sidebar
  and the bell. **Fails if** the pre-quit toast resurrects on relaunch (the
  persona-7 zombie) — even though its work session is persisted.
- Steps 7-8: a version mismatch or corrupt blob both yield a clean default
  launch with no crash and no partial restore. **Fails if** the app crashes
  on a corrupt blob (restore must be best-effort, item 21) or restores
  anything from a discarded state.

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

## Run status
**Reconciled 2026-08-09 (Task 13, unified-shell scenario-card sweep)**:
rewritten for `SessionRestoreState` v2. Replaced the deleted
`LibraryGridChromePolicy.shouldShowImportCompletionSummary` citation with
`ImportCompletionToastPresentation.toast(for:isCurrentSessionActivity:
isImporting:)` (verified: the old symbol has zero remaining references in
`Sources/`, and `isCurrentSessionActivity` still lives at
`AppModel.swift:14405-14407`, unmoved by this push). Re-specified what
persists: lens + source (not a raw `selectedView` route), with no
per-field/rawValue migration left — v1→v2 is a hard cutover, the whole blob
discards on any version mismatch, confirmed by reading
`SessionRestoreState.swift`'s own doc comment plus `SessionRestoreStore
.load()`'s implementation directly. Dropped Steps 7-8's old "legacy
`search`/`copilot` rawValue" and "unknown rawValue" sub-cases (there is no
`LibraryViewMode` rawValue decode left in the persisted state to corrupt
that way) and replaced them with a single version-mismatch step plus a
malformed-JSON step, which between them cover the same "best-effort,
all-or-nothing discard" invariant the deleted mechanism used to exercise
two different ways. Rewrote item 19/20's Cull-never-restores step to assert
the rule's actual unconditional shape (`isRestorableLens` is `lens != .cull`,
full stop — not "unless mid-cull") per `AppModel.swift:12401-12405`, and
noted this is independent coverage of the same rule `app-019-lens-shell
.md`'s Step 9 also drives, not a duplicate. Supersedes prior status: the
prior revision's `SessionRestoreState` v1 field list (`selectedView`, no
`source`, no `lens`) and its legacy-rawValue steps describe a schema and a
decode path this push replaced outright — any run against that structure
tested code that no longer exists. Needs a fresh VM run.
