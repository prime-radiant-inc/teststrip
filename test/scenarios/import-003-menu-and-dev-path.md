# import-003-menu-and-dev-path: File menu exposes Import Folder/Card/Path as distinct items, mirrored by the toolbar, both disabled mid-import

**What this covers**: inventory items 3, 4. The File menu (`FileCommands` in
`Sources/TeststripApp/main.swift:202-231`) exposes three distinct import
entries — `"Import Folder…"`, `"Import From Card…"`, and a dev-gated
`"Import Path…"` — plus `"Export…"`, each a separate `Button` with its own AX
title (`AppMenuCoveragePresentation.importFolderActionID` /
`importFromCardActionID` / `importPathActionID`,
`Sources/TeststripApp/main.swift:116-119`). All three import items — and the
toolbar's mirrored `Import ▾` menu / `Import Path` button
(`Sources/TeststripApp/LibraryGridView.swift:269-306`) — are `.disabled` while
`model.isImporting` is true, so a running import can't be started twice from
either surface.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
- A slow-to-import fixture folder with enough files that the import stays
  `isImporting == true` long enough to observe the disabled state before it
  drains (a handful of files is normally enough given the app's synchronous
  per-file catalog flush cadence; if it completes too fast, use a larger N):
  ```bash
  SLOWFIXTURE=$(mktemp -d)/slow
  mkdir -p "$SLOWFIXTURE"
  for n in $(seq 1 40); do printf 'frame-%d' "$n" > "$SLOWFIXTURE/frame-$n.jpg"; done
  ```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`.
2. **Menu distinctness, idle state**: open the File menu and assert all four
   items exist with exact, distinct AX titles — no two import entries share a
   title, and none is the toolbar's collapsed `"Import"` label:
   ```bash
   script/ax_drive.sh find --role AXMenuItem --label "Import Folder…"
   script/ax_drive.sh find --role AXMenuItem --label "Import From Card…"
   script/ax_drive.sh find --role AXMenuItem --label "Import Path…"
   script/ax_drive.sh find --role AXMenuItem --label "Export…"
   ```
   (`Import Path…` is expected to be present because the isolated launch
   always sets `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY`, which is the sole
   gate per `LibraryGridChromePolicy.shouldExposeImportPathControl`,
   `Sources/TeststripApp/LibraryGridView.swift:8342-8345` — not a build
   config or a separate dev flag. A real (non-isolated) launch would hide it.)
3. **Toolbar mirrors the same routes, idle state**: assert the toolbar
   `Import` menu button and (since this is an isolated launch) the `Import
   Path` button are both present and enabled:
   ```bash
   script/ax_drive.sh find --role AXButton --help "Import photos from a folder or a memory card"
   script/ax_drive.sh find --role AXButton --help "Import a folder by typed path (dev/automation)"
   ```
4. **Start a slow import** via the typed-path route so the sheet needs no
   native panel:
   ```bash
   script/submit_import_path.sh Teststrip "$SLOWFIXTURE"
   ```
5. **While `isImporting` is true**, immediately re-check both surfaces:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM assets WHERE original_path LIKE '$SLOWFIXTURE/%';"
   ```
   (poll this alongside the AX checks below — it climbing toward 40 confirms
   the import is genuinely in flight while the disabled-state assertions run,
   not that it already finished)
   - File menu: `ax_drive.sh find --role AXMenuItem --label "Import Folder…"`
     still finds the item (menu items don't disappear when disabled — assert
     via the AX disabled/enabled state, e.g. `AXEnabled == false`, not
     presence/absence).
   - Toolbar: the `Import` menu button and `Import Path` button both report
     `AXEnabled == false`.
6. Wait for the import to complete (`sqlite3` count reaches 40, or the
   toolbar buttons re-enable); re-check both surfaces are enabled again.

## Expected
- Step 2: all four File-menu titles are exact matches and mutually distinct
  — `"Import Folder…"`, `"Import From Card…"`, `"Import Path…"`, `"Export…"`.
  **Fails if** any title is missing, renamed, or two entries collapse to the
  same AX title (a menu-building regression would make Import Folder and
  Import From Card indistinguishable to a driver matching by label).
- Step 3: toolbar entry points exist with the AXHelp text quoted above.
  **Fails if** the toolbar only exposes a subset of what the File menu
  exposes (item 4 requires both surfaces expose the same set of routes).
- Step 5: **fails if** any import control (menu item or toolbar button)
  remains `AXEnabled == true` while `sqlite3` confirms the import is still in
  progress — that's a double-import hazard, not just a UI polish gap.
- Step 6: **fails if** the controls stay disabled after the import visibly
  completes (count reaches 40) — a stuck `isImporting` flag would strand the
  user unable to import again without relaunching.

## Cleanup
```bash
rm -rf "$SLOWFIXTURE"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- `AppMenuCoveragePresentation.fileMenuActionIDs`
  (`Sources/TeststripApp/main.swift:121`) only lists
  `[importFolderActionID, importFromCardActionID, exportActionID]` — it
  omits `importPathActionID`. That's consistent with Import Path being a
  dev/automation-only entry not meant for the "real" coverage enumeration,
  but a driver that walks `fileMenuActionIDs` to assert full menu coverage
  will miss Import Path entirely; this card checks it separately in Step 2.
- The dev-gating condition is **not** a compile-time flag or a distinct env
  var — it's "isolated launch sets `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY`
  to a non-empty path," the same variable `build_and_run.sh` always exports
  for `--isolated`/`--smoke`/etc. A card or driver that assumes a dedicated
  `TESTSTRIP_SHOW_IMPORT_PATH`-style flag would be wrong; grep
  `shouldExposeImportPathControl` before trusting any other description of
  this gate.
- Step 5's fixture-size approach (40 tiny files) is a best-effort way to keep
  `isImporting` true long enough to observe — the actual duration depends on
  the app's flush/progress cadence (`eagerCatalogPersistenceLimit = 10`,
  `Sources/TeststripCore/Ingest/IngestService.swift:37`). If a live run
  finds 40 files complete too fast to observe the disabled window reliably,
  increase N rather than trying to synchronize on a race.

## Run status
BLOCKED-CONSOLE — no host GUI/display in this environment; no AX steps were
executed live. Source-confirmed the menu structure, exact AX titles, and
`.disabled(isImporting)` wiring: `Sources/TeststripApp/main.swift:116-121,
198-229` (File menu), `Sources/TeststripApp/LibraryGridView.swift:269-306`
(toolbar), `Sources/TeststripApp/LibraryGridView.swift:8342-8345`
(`shouldExposeImportPathControl` gate) — read 2026-07-10. No SQL in this card
needed a live catalog beyond the generic `assets` count query, ground-truthed
against a seeded `--smoke` catalog the same day (schema per
`CatalogMigrations.swift:12-25`). Needs a human-present or console-unlocked
re-run to observe the actual disabled-state transition during a live import.
