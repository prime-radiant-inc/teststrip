# app-001-launch-scene: the app launches into its one-window scene, dark, titled, on the right catalog

**What this covers**: Jesse double-clicks the app and gets a working window
every time. Inventory items 1-6: the single `WindowGroup` scene with
`NavigationSplitView` + inspector + Settings (`Sources/TeststripApp/main.swift:15-84`);
a single sidebar (`SidebarView`) whose "Stacks · Auto-Grouped" section
renders only while the Cull lens is selected
(`model.selectedLens == .cull`, `SidebarView.swift:46-53`); forced dark
mode (`.preferredColorScheme(.dark)`); `fatalError` on catalog open failure +
eager `Updater.shared` start; the catalog path and its
`TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY` override
(`Sources/TeststripApp/AppCatalog.swift:31-36,60-70`); and the window title =
`catalogDisplayName` with the "Local Catalog" fallback
(`AppModel.catalogDisplayName`, `Sources/TeststripApp/AppModel.swift:2806-2809`;
`LibraryGridView.swift:122`).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. **One window, split-view scene.** Via System Events, assert `count of
   windows of process "Teststrip"` is 1 and the window contains a sidebar
   (an `AXOutline`/sidebar group) plus a detail area (the grid). ⌘N must not
   mint a second catalog window: press it and assert window count stays
   exactly 1 (`CommandGroup(replacing: .newItem) {}` in `main.swift` removes
   the default File > New Window item entirely, so ⌘N has no handler and is a
   plain no-op — not a beep).
3. **Env override took effect (item 5).** Ground truth that the running
   instance is using the isolated dir, not Jesse's real catalog:
   ```bash
   test -n "$ISOLATED" && test -f "$DB" && echo "isolated catalog live"
   sqlite3 "$DB" "SELECT count(*) FROM assets;"   # 24 for --smoke
   ```
   Also assert `~/Library/Application Support/Teststrip/catalog.sqlite`'s
   mtime did not change across the run (capture before/after).
4. **Window title (item 6).** Read the window's AXTitle. It must equal the
   catalog root's directory name (the isolated dir's `Teststrip` folder name
   as `catalogDisplayName` computes it) — record the exact string. It must
   NOT be empty; "Local Catalog" appears only if the root name is blank.
5. **Forced dark (item 3).** Capture `script/capture_app_window.sh` and
   confirm dark chrome even when the VM/system appearance is set to Light
   (`defaults write -g AppleInterfaceStyle` absent = light). The screenshot
   is the evidence; re-read it.
6. **Updater started eagerly (item 4, observable half).** Within a few
   seconds of launch the Sparkle updater has been constructed — observable
   as a `defaults read com.teststrip.app SULastCheckTime` (or `SUHasLaunchedBefore`)
   key appearing in the app's defaults domain after first launch. Absence of
   both after 30s is a failure of the eager start.
7. **fatalError on a corrupted catalog (item 4, destructive-to-throwaway).**
   Quit the app. Corrupt the throwaway catalog:
   ```bash
   dd if=/dev/urandom of="$DB" bs=1k count=4 conv=notrunc
   ```
   Relaunch the same binary with `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=$ISOLATED`.
   Expect the process to die during init (crash/abort, exit status non-zero)
   rather than silently creating or opening a bad catalog. Capture the
   crash message: it should contain `Unable to open Teststrip catalog:`.

## Expected
- Step 2: exactly one window with sidebar+detail, unchanged by ⌘N. **Fails
  if** zero windows (check `IOConsoleLocked` first — a locked console mimics
  this) or window count becomes 2 after ⌘N.
- Step 3: `$DB` exists with 24 assets; the real catalog untouched. **Fails
  if** the real catalog's mtime changed — the override leaked.
- Step 4: non-empty AXTitle matching the catalog root name. **Fails if**
  blank or a hardcoded app name unrelated to the catalog root.
- Step 5: dark chrome under a light system appearance. **Fails if** the
  window renders light.
- Step 6: a Sparkle defaults key appears. **Fails if** none does — the eager
  `Updater.shared` start regressed.
- Step 7: non-zero exit with the `Unable to open Teststrip catalog:` message.
  **Fails if** the app launches anyway (it opened or recreated a corrupt DB —
  that risks silent data loss on Jesse's real catalog).

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```
Quit any launched instance; the step-7 corrupted catalog dies with the
isolated dir.

## Sharp edges
- Step 7 is intentionally destructive — but ONLY to the throwaway isolated
  catalog. Never point it at a real app-support dir. Double-check `$ISOLATED`
  is under `$TMPDIR` before the `dd`.
- SQLite is resilient: overwriting the first 4KB clobbers the file header,
  which reliably fails open. If SQLite still opens it (e.g. WAL recovery),
  corrupt more aggressively (`bs=1k count=64`) rather than declaring a pass.
- Whether `fatalError` shows as a crash-report dialog or a silent abort
  depends on how it is launched; assert on process exit + log message, not
  on any dialog.
- Step 6's exact Sparkle defaults key name is an educated guess
  (`SULastCheckTime`/`SUHasLaunchedBefore` are Sparkle's standard keys) —
  dump the whole domain (`defaults read com.teststrip.app | grep -i '^ *"SU'`)
  and record what actually appears before asserting on one key.
- The step-4 title depends on the isolated root's last path component;
  the sharp-eyed inventory note says production always shows "Teststrip"
  (the app-support folder name). Record the actual value; the assertion is
  "equals the catalog root's name", not a specific literal.
- **Step 7's fatalError is now narrower than "any bad catalog data."** It
  originally also fired for a single malformed `preview_generation_queue`
  row (e.g. an unknown `level` value from `inspect-004`'s earlier fixture
  bug), hard-crash-looping the app on a recoverable data issue. That's
  fixed: `CatalogRepository` now drops/logs malformed preview-queue rows
  instead of throwing, so catalog open survives them. Step 7's own
  probe — overwriting the SQLite file header with random bytes — still
  fails to open and still fatals as expected; that invariant (don't
  silently open/recreate a genuinely corrupt catalog) is unchanged.

## Run status
**Reconciled 2026-08-09 (Task 13 review follow-up, unified-shell push)**: the
intro's "the sidebar swaps `CullSidebarView`/`SidebarView` by workspace"
claim was stale — `CullSidebarView` was deleted in this push (a Task-13
review caught it as an orphan the sweep's grep pattern couldn't match on).
Corrected to the real structure: there is now one sidebar (`SidebarView`),
and its "Stacks · Auto-Grouped" section — the successor to what
`CullSidebarView` used to show — renders only while the Cull lens is
selected (`model.selectedLens == .cull`, `SidebarView.swift:46-53`), gated
inline in `SidebarView`'s own `body` rather than by swapping in a second
view. No step in this card drove the deleted claim live, so Steps 1-7 and
their Expected bullets are otherwise unaffected — this is a citation fix,
not a behavior rewrite.
**Supersedes prior status**: the "Verified" status above predates this
push's sidebar consolidation and describes the `CullSidebarView`/
`SidebarView` swap it deleted — not valid evidence for the current
structure, even though the steps it verified (window title, ⌘N, corrupt
catalog) are otherwise unaffected. Needs a fresh VM run.

## Fix notes (persona-fixes-5, 2026-07-11)
PENDING-VM: window title audit — the only `navigationTitle` in the app is
`model.catalogDisplayName` (LibraryGridView.swift); the "Library View"
string Sam saw is the sub-view Picker's control label, not a title
override. Added `.navigationSubtitle` naming the active sub-view so the
title bar reads "<catalog> — Grid/Loupe/…". Transient save-confirmation
status messages now auto-clear after 4s (`scheduleTransientStatusMessage
AutoClear`; ongoing "…"-suffixed work messages are exempt), unit-tested.
Live title-bar verification on the VM pending.
