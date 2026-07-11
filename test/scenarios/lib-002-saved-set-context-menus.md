# lib-002-saved-set-context-menus: sidebar row context menus expose the correct per-row-type actions and write on confirm

**What this covers**: `SidebarView`'s per-row `.contextMenu` (built from
`AppModel.sidebarContextActions(for:)`, `AppModel.swift:4338-4392`) — plain
rows (All Photographs, folders, review queues, etc.) get an empty menu; a
saved-set row gets Rename/Duplicate/Freeze Snapshot (dynamic sets
only)/Star/Delete; a work-session row gets Star/Remove-equivalent (the code
only exposes a star toggle, see Sharp edges); the Rename/Duplicate/Freeze
sheets have the expected default text and blank-disabled behavior; the
Delete confirmation uses non-destructive copy; and each action can be
invoked directly through `AppModel.performSidebarContextAction` and
`AppModel.sidebarContextActions`/tone-tint helpers as an alternative to
driving the menu through AX.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`--smoke` now seeds ONE manual starred saved set out of the box:
"smoke-picks" / "Smoke Picks" (`SmokeCatalogSeeder`, `membership: .manual`,
`starred: true`) — drive the manual-set context-menu assertions against it
directly. Only the **dynamic**-set leg still requires creating a set live
through the app first:
1. A **manual** set: seeded ("Smoke Picks") — nothing to create.
2. A **dynamic** set: apply a Library query token (e.g. `rating:3`) and save
   the resulting smart-collection as a set, giving `membership: .dynamic`.

Confirm creation via SQL before proceeding:
```bash
sqlite3 "$DB" "SELECT id, name, json_extract(membership,'$') FROM asset_sets;"
```
No seed flag produces a dynamic set directly — that leg's prerequisite is
created in-app. Context menus are drivable with
`ax_drive.sh press --contains "Smoke Picks" --button right` (AXShowMenu;
see test/scenarios/README.md), which lifted this card's earlier
BLOCKED-TOOLING status.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. Right-click (or use the context-menu AX action on) a plain row with no
   actions, e.g. "All Photographs". Per
   `AppModel.sidebarContextActions(for:)`'s `default: return []`
   (`AppModel.swift:4389-4390`), assert the menu has zero items —
   `SidebarView.swift:189-197`'s `ForEach` over an empty array renders no
   `Button`s, so a context-menu invocation should show nothing (or macOS may
   show no menu at all).
3. Right-click the manual saved-set row. Assert the menu contains, in order:
   "Rename Set" (pencil), "Duplicate Set..." (plus.square.on.square),
   **no** "Freeze Snapshot..." (manual sets aren't dynamic —
   `AppModel.swift:4357-4363` gates it on `case .dynamic`), "Star Set" (star,
   since unstarred by default), "Delete Set..." (trash) —
   `AppModel.swift:4345-4376`.
4. Right-click the dynamic saved-set row. Assert the menu additionally
   contains "Freeze Snapshot..." (camera.aperture) between Duplicate and
   Star.
5. Right-click a work-session row (e.g. "Recent Import", if seeded by the
   smoke import). Assert the menu contains exactly one item: "Star Work"
   (or "Remove Star" if already starred) — `AppModel.swift:4382-4388`. There
   is no separate "Remove" action; see Sharp edges.
6. Click "Rename Set" on the manual set. Assert a sheet titled "Rename Set"
   appears (`SidebarView.swift:438-456`, now built on `SheetScaffold`)
   pre-filled with the row's current title (`assetSetRenameText = row.title`,
   `SidebarView.swift:202`). Clear the field entirely; assert the
   "Rename Set" button is disabled (`isPrimaryEnabled`, `SidebarView.swift`).
   Type a new name and confirm; assert `asset_sets.name` updates in `$DB`
   and the sidebar row's title updates.
7. Click "Duplicate Set..." on the manual set. Assert the sheet is titled
   "Duplicate Set" with action "Duplicate Set" (`SidebarView.swift:41`), and
   the name field defaults to `"Copy of <original title>"`
   (`SidebarView.swift:207`). Confirm; assert a **new** `asset_sets` row
   appears with that name and the same `membership` as the source
   (`AppModel.swift:4494-4499`), and the new set becomes selected
   (`saveAndSelect`, `AppModel.swift:4711-4723`).
8. Click "Freeze Snapshot..." on the dynamic set. Assert the sheet is titled
   "Freeze Snapshot" with action "Freeze Snapshot" (`SidebarView.swift:51`),
   and the name field defaults to `"<original title> Snapshot"`
   (`SidebarView.swift:213`). Confirm; assert a new `asset_sets` row appears
   with `membership` of kind `snapshot` containing the asset IDs the dynamic
   query matched *at freeze time* (`AppModel.swift:4508-...` resolves the
   query to a fixed ID list) — cross-check against
   `SELECT count(*) FROM assets WHERE <the same query predicate>` at the time
   of freezing.
9. Click "Star Set" on the (now-unstarred) manual set. Assert
   `asset_sets.starred` flips to 1 in `$DB`, the row's tone changes (see
   Expected), and the context menu's action label flips to "Remove Star" on
   a re-open.
10. Click "Delete Set..." on any saved set. Assert a
    `confirmationDialog` titled "Delete Set?" appears with a "Delete Set"
    destructive button and a "Cancel" button, and message text containing
    the exact non-destructive copy from
    `assetSetDeleteMessage` (`SidebarView.swift:115-119`):
    `"This removes \"<name>\" from Teststrip. Photos, originals, metadata,
    and XMP sidecars stay untouched. Work history that references this set
    may no longer reopen it."`
    Confirm; assert the row disappears from the sidebar and the
    `asset_sets` row is gone from `$DB`, while the underlying assets/files
    are untouched (assert `assets` row count and file mtimes on disk are
    unchanged — the non-destructive invariant).

## Expected
- Step 2: zero menu items on a plain row. **Fails if** any action appears.
- Step 3/4: exact action sets per row kind, with Freeze Snapshot present iff
  `membership` is `.dynamic`. **Fails if** Freeze Snapshot appears on the
  manual set, or is missing on the dynamic set, or actions are out of order.
- Step 5: exactly one action on a work-session row, a star toggle, no
  distinct "Remove" action exists in the model despite the inventory item's
  "Star/Remove" phrasing — see Sharp edges. **Fails if** a second action
  appears that this card's reading of `AppModel.swift:4377-4388` didn't
  anticipate (re-check the source if so — the code may have changed).
- Step 6: blank name disables Rename; confirmed rename persists to
  `asset_sets.name`. **Fails if** the button is enabled while blank, or the
  catalog value doesn't change.
- Step 7: default name is exactly `"Copy of <title>"`; duplicate persists as
  a new row with identical membership. **Fails if** the default text differs
  or the duplicate mutates the source set instead of creating a new one.
- Step 8: default name is exactly `"<title> Snapshot"`; freeze persists a
  `snapshot`-kind set with the query's matched IDs at that moment. **Fails
  if** the frozen set is still `dynamic` (i.e. re-evaluates live instead of
  being pinned) — that would defeat the point of "freezing."
- Step 9: starring flips `asset_sets.starred` and the menu label. **Fails if**
  the catalog value doesn't change or the label doesn't flip on reopen.
- Step 10: dialog copy matches exactly (word-for-word, including the
  original bytes/XMP reassurance); confirming deletes the `asset_sets` row
  only. **Fails if** the message text differs, or if confirming touches
  `assets` rows, original file bytes, or `.xmp` sidecars — this is a
  confirm-before-write/non-destructive assertion per `CLAUDE.md`, so treat
  any file-level side effect as a hard failure, not a nuance to soften.

## Tone tints (direct-actions cross-check)
Cross-check row tone against `SidebarRowView.tint`
(`SidebarView.swift:413-426`): `.neutral` → secondary/gray,
`.accent` → orange, `.positive` → green, `.warning` → yellow,
`.destructive` → red. Saved-set rows use `.accent` (orange) for dynamic sets
and `.neutral` for manual/snapshot sets (`AppModel.swift:11823`,
`assetSet.isDynamic ? .accent : .neutral`); the Recent Import row is
`.positive` (green, `AppModel.swift:11804`). Since AX doesn't expose SwiftUI
foreground color directly, verify tone via `capture_app_window.sh` screenshot
color-sampling on the row's icon glyph rather than an AX attribute, or treat
this sub-check as screenshot-evidence-only in the Run.

Also confirm direct-call equivalence (useful when AX menu driving is flaky):
`AppModel.performSidebarContextAction(_:)` (`AppModel.swift:4394-4409`) is a
`throws` dispatcher over `SidebarRowContextActionKind` — every menu action
except Rename can be invoked directly through it (Rename is intentionally
excluded, throwing `TeststripError.invalidState` per
`AppModel.swift:4396-4397`, because it needs the sheet's new-name text, not
just the action). This is documentation, not a separate falsifiable step —
a card driving the app can't call Swift methods directly; note it only if a
future unit-level regression test wants the equivalent coverage.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **No "Remove" action for work sessions exists in the model** despite this
  card's assigned inventory item naming "work-session menu Star/Remove" —
  `AppModel.sidebarContextActions(for:)`'s `.workSession` case
  (`AppModel.swift:4377-4388`) returns only a star-toggle action; there is no
  `SidebarRowContextActionKind` case for removing/unpinning a work session
  from the sidebar. Either the inventory description is stale, or a "Remove"
  action is missing from the implementation — flagging for Jesse to decide
  which; not fixing it here.
- **Duplicate saved-set row identity when starred** — see the same finding
  written up in `lib-001-sidebar-sections.md`'s Sharp edges: a starred
  saved-set row renders with the identical `SidebarRow.id` in both the
  Collections and Saved Sets sections. For *this* card that also means a
  context-menu action (e.g. Delete) triggered on the Collections-section
  copy of a starred row and the Saved-Sets-section copy of the same row
  should be behaviorally identical (both resolve to the same `AssetSetID`),
  but an AX driver matching by row label alone may click into either
  instance non-deterministically — worth a note in the Run if a starred-set
  step in this card ever misbehaves.
- Rename's exclusion from `performSidebarContextAction` (throwing rather than
  silently no-oping) is intentional per the code comment structure, not a
  bug — noting only because it stood out while reading.

## Run status
NOT RUN — headless authoring only; needs a live AX run. No live GUI launch,
`ax_drive.sh` invocation, or SQL dry-run against a seeded catalog was
performed for this card (the `asset_sets` empty-on-`--smoke` claim was
confirmed by reading `script/build_and_run.sh`'s seeding path, not by
querying a live catalog). Source line numbers above were read directly from
`Sources/TeststripApp/SidebarView.swift` and
`Sources/TeststripApp/AppModel.swift` on 2026-07-10.
