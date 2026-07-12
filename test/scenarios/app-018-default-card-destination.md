# app-018-default-card-destination: ⌘, sets a default card-import destination that persists and pre-fills new card imports

**What this covers**: Jesse sets his canonical card-import destination once in
Settings (⌘,) and never retypes it. The Settings scene hosts a "Card import"
section with a **Destination** row + **Choose…**/**Clear** buttons bound to
`model.defaultCardImportDestination`
(`Sources/TeststripApp/PreferencesView.swift`;
`CardImportPreferencePresentation`), persisted to defaults under
`AppModel.defaultCardImportDestination` (`AppModel.swift`, byline pattern).
The value pre-fills — never auto-writes — the card-import destination: the
typed-path sheet's Destination field is pre-filled from it
(`showImportCardPathSheet` → `ImportCardPathDraft.applyDefaultDestination`),
and the real-user panel route skips the destination panel and uses it
(`showImportCardPanel` → `LibraryGridChromePolicy.cardDestinationResolution`),
with a per-import **Change…** override on the confirmation sheet
(`ImportConfirmationDraft.setDestinationRoot`). Spec:
`docs/superpowers/specs/2026-07-12-default-card-import-destination-design.md`.

## Pre-state
Run in the Tart VM (relaunch cycle + defaults inspection):
```bash
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke   # note the run dir $RUN
script/vm_scenario_run.sh ax wait-vended Teststrip
```

## Steps
1. **Open Settings, find the Card import section.** Send ⌘, (osascript
   keystroke). `ax_drive.sh wait --contains "Card import"`. Assert a
   **Destination** row reading **"None"** (unset), a **Choose…** button, and
   the footer copy exactly: "Pre-fills the destination for new card imports.
   Originals are copied — never moved — into dated folders (YYYY/YYYY-MM-DD)."
   Assert **no Clear button** while unset.
2. **Set the destination (ground truth).** The Choose… button opens a native
   `NSOpenPanel` (not AX-drivable headlessly), so set the value the way the
   button does — write the default directly, then confirm the app persists and
   reads it. In the VM shell pick a real folder and set it:
   ```bash
   DEST="/Users/admin/CardDest"; mkdir -p "$DEST"
   # Explicit-path form — see Sharp edges: a stale ~/Library/Containers/
   # com.teststrip.app redirects the bare `defaults com.teststrip.app` CLI to a
   # container plist the (non-sandboxed) app ignores. This targets the same
   # store UserDefaults.standard uses.
   defaults write "$HOME/Library/Preferences/com.teststrip.app" AppModel.defaultCardImportDestination "$DEST"
   ```
   (The button's only effect is `model.defaultCardImportDestination = url.path`,
   whose `didSet` writes this same key — this step exercises the persistence
   contract without the un-drivable panel.)
3. **Reopens with the value + Clear shown.** ⌘Q; relaunch the same binary
   against the same `$RUN` dir (NOT a fresh `launch` — see app-006's sharp
   edge). `ax_drive.sh wait-vended Teststrip`; ⌘,. Assert the Destination row
   now reads `/Users/admin/CardDest` and a **Clear** button is present.
   **Fails if** the row still says "None" — the default didn't survive
   relaunch, defeating "set it once."
4. **Pre-fills the typed-path card-import sheet.** Relaunch the app in the VM
   with the typed-path route enabled (see Sharp edges) against the same `$RUN`.
   Open the card-import path sheet (Import ▾ → the card/typed path entry).
   Assert the **Destination folder path** field is pre-filled with
   `/Users/admin/CardDest`. **Fails if** the field is blank — the default
   didn't reach the sheet.
5. **Pre-fill only, never auto-write.** Setting a default must touch no photo
   or catalog. In the VM shell:
   ```bash
   sqlite3 "$RUN/Teststrip/catalog.sqlite" "SELECT count(*) FROM assets;"        # unchanged from seed (24)
   sqlite3 "$RUN/Teststrip/catalog.sqlite" \
     "SELECT count(*) FROM metadata_sync_state WHERE 1;"                          # no new sync rows from setting the default
   ```
   **Fails if** setting/pre-filling the destination created or mutated any
   asset or metadata row — report immediately (invariant violation).

## Expected
- Step 1: Settings shows the Card import section, "None", Choose…, exact
  footer, no Clear. **Fails if** the section or footer is missing.
- Steps 2-3: the defaults key holds the path and survives relaunch; the row
  shows the path and a Clear button. **Fails if** either resets.
- Step 4: the typed-path sheet's Destination field is pre-filled. **Fails if**
  blank.
- Step 5: no catalog/metadata rows created by setting the default. **Fails if**
  any appear.

## Cleanup
```bash
script/vm_scenario_run.sh shell
# then: defaults delete "$HOME/Library/Preferences/com.teststrip.app" AppModel.defaultCardImportDestination
#       rm -rf /Users/admin/CardDest "$RUN"
```

## Sharp edges
- **Choose…/Clear open native `NSOpenPanel`s and are not AX-drivable
  headlessly.** Step 2 sets the persisted key directly because that is exactly
  the button's effect (`model.defaultCardImportDestination = url.path` →
  `didSet` persists). The button wiring itself is covered by
  `CardImportPreferencePresentationTests`.
- **`defaults` store redirect on this VM (verified 2026-07-12):** the app is
  not sandboxed, so it reads/writes `~/Library/Preferences/com.teststrip.app.plist`
  via `UserDefaults.standard`, but a stale `~/Library/Containers/com.teststrip.app/`
  dir makes the bare `defaults <domain>` CLI redirect to the container plist
  the app ignores. Always use the explicit-path form
  (`defaults write "$HOME/Library/Preferences/com.teststrip.app" KEY VALUE`)
  for both write and read/delete, or Steps 3-4 read stale "None". A quick
  differential probe (write `AppModel.defaultCreator` the same way and confirm
  app-015's known-good byline path behaves identically) isolates this store
  mismatch from any real regression.
- **Typed-path route (Step 4)** needs the app launched with
  `TESTSTRIP_CARD_IMPORT_ROUTE=typed-path`. `vm_scenario_run.sh launch` does
  not pass it, so relaunch manually in the VM shell mirroring the verb's own
  `open` line, e.g.:
  `open -n /path/to/Teststrip.app --env TESTSTRIP_CARD_IMPORT_ROUTE=typed-path --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="$RUN"`.
  Confirm the run dir matches Step 2's so the saved default is read.
- **The panel-route skip and the confirmation-sheet Change… override are not
  AX-drivable** (native destination `NSOpenPanel`). They are covered by unit
  and presentation tests (`LibraryGridChromeTests.cardDestinationResolution`,
  `ImportConfirmationDraft.setDestinationRoot` tests). This card verifies the
  persistence + typed-sheet pre-fill legs live.
- SwiftUI commits on focus-loss; if a future revision makes the Destination
  editable inline, tab out before reading defaults.
