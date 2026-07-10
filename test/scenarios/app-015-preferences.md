# app-015-preferences: ⌘, opens Settings and the default byline persists across relaunch

**What this covers**: Jesse types his byline once; every future caption
pre-fills it. Inventory item 49: the Settings scene (⌘,) hosts
`PreferencesView` with Creator/Copyright fields bound to
`model.defaultCreator`/`defaultCopyright`
(`Sources/TeststripApp/PreferencesView.swift`;
`Sources/TeststripApp/main.swift:86-88`), persisted to defaults under
`AppModel.defaultCreator`/`AppModel.defaultCopyright`
(`AppModel.swift:2085-2091`) — pre-fill only, never auto-written to a photo.

## Pre-state
Run in the Tart VM (relaunch cycle + defaults inspection):
```bash
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke   # note the run dir $RUN
script/vm_scenario_run.sh ax wait-vended Teststrip
```

## Steps
1. **Open Settings.** Send ⌘, (osascript keystroke). `ax_drive.sh wait
   --contains "Default byline"`. Assert two text fields with prompts
   "Your name / byline" and "© 2026 Your Name", plus the footer text
   explaining pre-fill ("Nothing is written to a photo until you apply it").
2. **Set values.** Type `Scenario Tester` into Creator and
   `© 2026 Scenario` into Copyright. Close the Settings window.
3. **Persisted (ground truth).** In the VM shell:
   ```bash
   defaults read com.teststrip.app AppModel.defaultCreator     # Scenario Tester
   defaults read com.teststrip.app AppModel.defaultCopyright   # © 2026 Scenario
   ```
4. **Survives relaunch.** ⌘Q; relaunch the same binary against the same
   `$RUN` dir (NOT a fresh `launch` — see app-006's sharp edge). Reopen ⌘,:
   both fields show the saved values.
5. **Pre-fill only, never auto-write.** With the byline set, assert no
   asset picked it up without a gesture:
   ```bash
   sqlite3 "$RUN/Teststrip/catalog.sqlite" \
     "SELECT count(*) FROM assets WHERE metadata_json LIKE '%Scenario Tester%';"   # 0
   ```
   Then open the inspector's caption/metadata surface for one asset, apply
   the pre-filled creator via its explicit apply gesture, and re-run the
   query: exactly 1, and that asset's sidecar now carries the creator.

## Expected
- Step 1: ⌘, opens the Settings scene with both fields. **Fails if** the
  shortcut is inert or the fields are missing.
- Steps 3-4: both defaults keys hold the typed values and survive relaunch.
  **Fails if** either resets — Jesse would retype his byline every session.
- Step 5: count is 0 before the gesture and exactly 1 after. **Fails if**
  >0 before (auto-write — invariant violation, report immediately).

## Cleanup
```bash
script/vm_scenario_run.sh shell
# then: defaults delete com.teststrip.app AppModel.defaultCreator
#       defaults delete com.teststrip.app AppModel.defaultCopyright
#       rm -rf "$RUN"
```

## Sharp edges
- SwiftUI TextFields commit on focus-loss/Return; tab out of each field
  before reading defaults or the write may not have landed yet.
- The Settings window is a separate window — `ax_drive.sh` matches within
  the frontmost app but confirm which window vends the fields; match the
  empty fields by their prompt text (`--contains`).
- Step 5's apply gesture lives in the inspector caption flow — if its
  control names have drifted, dump the inspector AX tree first; the
  load-bearing assertion is the before/after count pair, not the exact
  control label.
