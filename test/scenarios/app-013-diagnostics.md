# app-013-diagnostics: Support ▸ Copy Diagnostics puts a truthful report on the pasteboard

**What this covers**: When something breaks, Jesse copies diagnostics into a
bug report; the report must be real and complete. Inventory item 44:
Support ▸ Copy Diagnostics writes `model.diagnosticsReportText` to
`NSPasteboard.general` and sets the status "Copied diagnostics"
(`SupportCommands.copyDiagnostics`, `Sources/TeststripApp/main.swift:498-518`;
report shape in `AppDiagnosticsReport.text`,
`Sources/TeststripApp/AppModel.swift:1138-1179`).

## Pre-state
Run in the Tart VM — the assertion is `pbpaste` in the *app's* GUI session,
and clobbering/reading the host pasteboard mid-session is both flaky and
rude:
```bash
script/vm_scenario_run.sh sync smoke
script/vm_scenario_run.sh launch smoke
script/vm_scenario_run.sh ax wait-vended Teststrip
```

## Steps
1. **Poison the pasteboard first** so the assertion can't pass vacuously:
   in the VM shell, `echo "sentinel-$(date +%s)" | pbcopy`.
2. **Invoke the menu item.** Via System Events in the VM, click
   Support ▸ Copy Diagnostics.
3. **Read it back.** In the VM shell:
   ```bash
   pbpaste > /tmp/diag.txt; head -20 /tmp/diag.txt
   ```
4. **Assert content, not just presence.** `/tmp/diag.txt` must:
   - start with the line `Teststrip Diagnostics`;
   - contain `Catalog root:` and `Catalog database:` lines whose paths point
     at the VM's isolated run dir (cross-check against the actual dir);
   - contain `Worker enabled:` / `Worker process:` lines matching reality
     (if the worker is running, `running`);
   - contain `Assets loaded/total:` with the seeded count (24 for smoke);
   - NOT contain the step-1 sentinel.
5. **Status feedback.** Assert the status chrome shows "Copied diagnostics"
   (screenshot the footer in Library, or `ax_drive.sh wait --contains
   "Copied diagnostics"`).

## Expected
- Step 4: every listed line present with values matching independently
  observed reality (paths, asset count, worker state). **Fails if** the
  sentinel survives (nothing was copied), the report is truncated, or any
  value contradicts ground truth (e.g. claims `Worker process: running`
  while `pgrep` finds none — a lying diagnostic is worse than none).
- Step 5: the status message renders. **Fails if** the copy is silent —
  Jesse can't tell it worked.

## Cleanup
```bash
script/vm_scenario_run.sh shell   # then: pbcopy < /dev/null; rm /tmp/diag.txt
```
Delete the VM run dir per the launch variant's convention.

## Sharp edges
- `pbpaste` over ssh reads the ssh session's pasteboard only if the session
  attaches to the user's GUI bootstrap; on the Tart VM's auto-login session
  this works, but if `pbpaste` returns empty while the UI visibly copied,
  run it via `launchctl asuser <uid>` or an osascript
  `the clipboard as text` fallback before declaring failure.
- The report embeds live queue counts that change while previews generate;
  assert on stable lines (header, paths, totals), not transient counters.
