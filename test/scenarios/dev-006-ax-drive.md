# dev-006: ax_drive.sh verb surface + host-without-TCC failure mode

**What this covers**
As a developer I want `script/ax_drive.sh` — the reusable accessibility
driver every interactive scenario card is built on (`wait-vended`, `find`,
`wait`, `press`, `type`) — to behave exactly as documented: each verb exits
0/1/2 per its contract, and running it on the bare host without Accessibility
(TCC) trust granted fails fast rather than hanging. Covers the
capability-inventory entry for `script/ax_drive.sh`, and the VM-driving
pattern in `test/scenarios/README.md` ("Running scenarios in a Tart VM") that
wraps the same verbs through `script/vm_scenario_run.sh ax ...`.

## Pre-state
- Repo checked out at `/Users/jesse/git/projects/teststrip`, working
  directory the repo root.
- For the verb-surface steps (VM path): a Tart VM already set up per
  `test/scenarios/README.md`'s "Running scenarios in a Tart VM" section
  (`script/vm_scenario_run.sh setup` run once previously, TCC pre-granted via
  the SIP-disabled Cirrus base image's direct TCC.db grant). This card does
  not itself run `vm_scenario_run.sh setup`/`sync`/`launch` — those are
  covered by whichever VM-lifecycle card exists (none seen in this repo yet;
  if absent, treat steps 2-6 below as documented-but-unrun and rely on the
  README's own worked example, which lists the identical verb sequence).
- For the host-without-TCC step: run directly on this Mac's Terminal, no VM
  needed. This step is read-only and non-destructive — `ax_drive.sh` fails
  fast on a permission/lookup check before touching anything, so it's safe to
  execute for real.

## Steps

### 1. Host invocation without a running target app (captured live, no VM)
```bash
cd /Users/jesse/git/projects/teststrip
pkill -x Teststrip 2>/dev/null || true   # ensure no target app is running
./script/ax_drive.sh wait-vended Teststrip
echo "exit: $?"
```

### 2-6. Verb surface via the VM harness (documented pattern; run when a VM is set up)
```bash
script/vm_scenario_run.sh launch smoke
script/vm_scenario_run.sh ax wait-vended Teststrip
script/vm_scenario_run.sh ax find --role AXButton --label Import
script/vm_scenario_run.sh ax wait --role AXStaticText --contains "Reviewing"
script/vm_scenario_run.sh ax press --role AXButton --help "Rate 5"
script/vm_scenario_run.sh ax type --contains "Person name" --text "Test Person"
```

## Expected

### Step 1 (captured live on this Mac, 2026-07-09/10)
```
No running app named Teststrip
```
printed to **stderr**, exit code **2**.

This Mac's Terminal already holds Accessibility trust (a prior interactive
session granted it), so `AXIsProcessTrusted()` at
`script/ax_drive.sh` (the `swift -e` heredoc, guard near the top) returns
true and the script proceeds past the TCC gate to the next guard — "no
running app named `<appName>`" (`FileHandle.standardError.write(Data("No
running app named \(appName)\n"...` then `exit(2)`). **Both** guards exit
`2`: this card could not reproduce the *specifically untrusted* branch
(`"Accessibility is not trusted for this process"`, same exit code 2) live on
this machine, because Terminal is already trusted here — see Sharp edges.
The two branches are exit-code-identical (both `2`) but message-distinct, so
a caller checking only the exit code cannot tell "untrusted" from "app not
running" apart; only the stderr text disambiguates them.

### Steps 2-6 (verb contract, per `script/ax_drive.sh` source and
`test/scenarios/README.md`'s documented verb list — not re-executed live in
this card; VM setup is out of scope here)
- `wait-vended [App]`: polls up to `TESTSTRIP_AX_TIMEOUT_SECONDS` (default
  20s) re-asserting frontmost via `osascript`/System Events each iteration;
  prints `vended` and exits 0 once the window subtree is non-menu-populated;
  exits 1 with `Window never vended for <App> within <N>s (locked console, or
  app not launching windows?)` on timeout.
- `find MATCHSPEC`: prints each matching element's label/help/role, one per
  line; exits 0 if ≥1 match, exits 1 with `No element matched (role=... ...)
  within <N>s` otherwise.
- `wait MATCHSPEC`: identical matching/exit contract to `find` but is meant
  to be read as "assert appearance" (same code path in the script — `find`
  and `wait` share the `case "find", "wait":` branch).
- `press MATCHSPEC`: `AXUIElementPerformAction(..., kAXPressAction)` on the
  first match; prints `pressed: <label>` and exits 0 on `.success`; exits 1
  with `AXPress failed: <AXError rawValue>` otherwise.
- `type MATCHSPEC --text STR`: defaults `--role` to `AXTextField` when unset;
  focuses the first match then sets `kAXValueAttribute` to `STR`; prints
  `typed into: <label>` and exits 0 on `.success`; exits 1 with `set value
  failed: <AXError rawValue>` otherwise.
- All verbs: usage/argument errors (no verb, `-h`/`--help`/`help`, unknown
  verb, unknown option) exit **2** (the same code as the TCC-untrusted and
  no-app-found guards) — `script/ax_drive.sh` overloads exit 2 for "usage
  error" and "permission/lookup error" alike; only stderr text
  disambiguates. (Header comment: `Exit: 0 success, 1 not found / timeout, 2
  usage/permission error.`)

## Cleanup
```bash
pkill -x Teststrip 2>/dev/null || true
```
(Only relevant if step 2-6 were actually run against a VM or host instance.)
Step 1 above launches nothing and needs no cleanup.

## Sharp edges
- **Could not reproduce the "untrusted" branch live on this Mac.** This
  machine's Terminal already carries `kTCCServiceAccessibility` trust from
  prior interactive scenario-card work, so `AXIsProcessTrusted()` returns
  true and step 1 falls through to the "no running app" guard instead of the
  "Accessibility is not trusted for this process" guard. Both print to
  stderr and both exit `2`, but the message text differs
  (`"Accessibility is not trusted for this process"` vs. `"No running app
  named <appName>"`) — a future run of this card on a genuinely
  untrusted process (a fresh CI runner, a revoked-TCC shell, or the
  `--in-terminal` codesigned binary path rather than ad-hoc `/usr/bin/swift
  -e`) would need to re-capture the exact untrusted-branch stderr text to
  close this gap. Do not assume the message shown above is the untrusted
  one — it is not.
- `/usr/bin/swift -e` invocations get their own ephemeral TCC identity
  separate from the parent shell in some macOS versions; if that's true here,
  the "trusted" result above may be incidental to how this particular
  Terminal/swift combination was previously exercised rather than a durable
  guarantee — worth a follow-up if this card is ever used to gate CI.
- `find` and `wait` are exit/output-identical in the source (same `case
  "find", "wait":` arm) — `wait`'s only distinguishing behavior from `find`
  is that a caller *retries* it in a loop expecting eventual truth, but the
  script itself already loops internally up to `TESTSTRIP_AX_TIMEOUT_SECONDS`
  for every verb, so `wait` and `find` are functionally the same call today;
  the two-verb split exists for docs/intent clarity, not different code
  paths.
- The VM path (steps 2-6) was not executed for this card — no
  `vm_scenario_run.sh setup` state was verified to exist in this session, and
  re-running `setup`/`sync`/`launch` is out of scope per the task brief
  (interactive GUI driving beyond a launch+quit smoke check was not
  authorized). A future pass should actually run the VM sequence and replace
  this documented-pattern block with captured real output, per the "evidence
  you re-read" principle in `test/scenarios/README.md`.
