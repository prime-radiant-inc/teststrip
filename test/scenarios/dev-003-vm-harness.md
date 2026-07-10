# dev-003-vm-harness: Tart VM scenario-running harness

**What this covers**
As a developer I want `script/vm_scenario_run.sh`'s verbs (setup, sync,
launch, ax, sql, ip, shell, destroy) to behave as documented in
`test/scenarios/README.md`'s "Running scenarios in a Tart VM" section, so
cards can be driven inside the VM when the host console is locked/stolen.
Script under test: `script/vm_scenario_run.sh`.

## Pre-state
**This card is documented/inspected, not executed live.** A real run needs
`script/vm_scenario_run.sh setup` completed (Tart installed via
`brew install cirruslabs/cli/tart`, `sshpass` installed, and a
`ghcr.io/cirruslabs/macos-tahoe-base:latest` VM cloned/booted) — none of that
exists in this environment/session, and per this card's authoring
instructions no VM was actually launched. Every step below is written from
reading `script/vm_scenario_run.sh` source directly (paths, commands, exit
handling) rather than from captured live output. Where the script's behavior
is unambiguous from source, it's stated as fact; where it would require a
live VM to confirm, that is flagged explicitly.

## Steps

1. **Setup idempotence.** `script/vm_scenario_run.sh setup` twice in a row.
   ```bash
   script/vm_scenario_run.sh setup
   script/vm_scenario_run.sh setup
   ```
   `cmd_setup` (source: checks `tart list | awk '{print $2}' | grep -qx "$VM_NAME"`
   before cloning, and checks `tart list | grep "^local *$VM_NAME .*running"`
   before booting) — a second call should skip both `tart clone` and
   `tart run`, going straight to `mkdir -p` on the remote dirs and re-running
   the TCC grant SQL (which uses `INSERT OR REPLACE`, so it's idempotent too).

2. **Sync (build + seed + rsync), idempotent template reuse.**
   ```bash
   script/vm_scenario_run.sh sync smoke faces
   script/vm_scenario_run.sh sync smoke faces   # second call
   ```
   `cmd_sync` always runs `./script/build_and_run.sh --build` locally (host
   never runs `swift build` inside the VM), then for each variant calls
   `seed_locally`, which checks `[[ -f "$dir/Teststrip/catalog.sqlite" ]]` —
   if the seed template already exists it prints
   `'<variant>' seed template already exists at <dir> (idempotent template —
   cmd_launch stamps a fresh copy per launch; pass --reseed to force
   regeneration)` and returns without reseeding (unless a second positional
   arg to `seed_locally` is `--reseed`). Then it rsyncs `dist/`, `script/`,
   `test/scenarios/`, and each requested variant's seed dir into the VM, and
   codesigns the app bundle remotely.

3. **Launch: fresh timestamped copy + `original_path` rewrite.**
   ```bash
   script/vm_scenario_run.sh launch smoke
   ```
   `cmd_launch` builds `fresh="$REMOTE_ROOT/run/$variant-$(date +%s)"`, kills
   any running app processes in the VM, `cp -R`s the synced seed template
   into `$fresh`, then runs, against `$fresh/Teststrip/catalog.sqlite`:
   ```sql
   UPDATE assets SET original_path = replace(original_path, '<local_seed>', '<fresh>');
   ```
   where `<local_seed>` is the **host's** local seed directory path (from
   `seed_dir_for "$variant"`, e.g. `$TMPDIR/teststrip-vm-seeds/smoke`) — this
   is the literal path baked into `original_path` by
   `seed-app-catalog`/`seed-sample-catalog` at seed time on the host, since
   seeding always runs on the host in `cmd_sync`. The rewrite exists because a
   plain `cp -R` only relocates the catalog file, not the string values
   inside it — every `original_path` would otherwise point at a host path
   that never existed inside the VM. Then it `open -n`s the app bundle with
   `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=$fresh` and confirms via `pgrep`.

4. **`ax` verb forwards to `ax_drive.sh` inside the VM.**
   ```bash
   script/vm_scenario_run.sh ax wait-vended Teststrip
   ```
   `cmd_ax` is `ssh_cmd "cd '$REMOTE_ROOT' && ./script/ax_drive.sh $(printf '%q ' "$@")"` —
   a thin ssh-and-forward wrapper; all arguments are shell-quoted and passed
   through verbatim to the VM's copy of `script/ax_drive.sh` (synced in step
   2 as part of the `script/` rsync).

5. **`sql` verb queries the VM catalog.**
   ```bash
   script/vm_scenario_run.sh sql smoke "SELECT count(*) FROM assets;"
   ```
   `cmd_sql` runs, over ssh:
   `latest=$(ls -dt '$REMOTE_ROOT'/run/$variant-* | head -1); sqlite3 "$latest/Teststrip/catalog.sqlite" <sql>`
   — it always targets the most-recently-launched timestamped copy for that
   variant, not a fixed path, so it must be run after `launch`.

6. **`ip` verb prints the VM's current IP.**
   ```bash
   script/vm_scenario_run.sh ip
   ```
   Calls `vm_ip`, which polls `tart ip "$VM_NAME"` up to 30 times at 2s
   intervals and echoes the first non-empty result to stdout; times out with
   `timed out waiting for $VM_NAME IP` to stderr and exit 1 if the VM never
   reports an IP.

## Expected
- Step 1: second `setup` call completes without invoking `tart clone` or
  `tart run` (only observable live via `tart` command tracing — not verified
  in this session).
- Step 2: second `sync smoke faces` call prints the "seed template already
  exists ... pass --reseed to force regeneration" line for both `smoke` and
  `faces` (from source, unconditionally true on a second call as long as
  `$dir/Teststrip/catalog.sqlite` exists) — **not confirmed live**.
- Step 3: `launch smoke` output ends with
  `launched 'smoke' fresh at $REMOTE_ROOT/run/smoke-<epoch>` and the
  in-line `pgrep -x Teststrip` at the end of the remote command succeeds
  (nonempty PID) — **not confirmed live**.
- Step 4: `ax wait-vended Teststrip` exits 0 once the VM's app subtree is
  vended (mirrors `ax_drive.sh`'s own host semantics; see
  `test/scenarios/README.md`) — **not confirmed live**.
- Step 5: returns the row count from the launched copy's catalog, e.g. `24`
  for a freshly launched `smoke` copy — **not confirmed live**.
- Step 6: stdout is a single IPv4-looking line (Tart's private-network IP for
  the VM) — **not confirmed live**.

## Cleanup
```bash
script/vm_scenario_run.sh destroy   # stops and tart-deletes the VM entirely
```
`cmd_destroy` runs `tart stop "$VM_NAME"` (ignoring failure) then
`tart delete "$VM_NAME"` — this is destructive to the whole VM, not just the
run state; only do this when done with the VM harness for good, not between
cards (between cards, just re-`launch` a variant for a fresh copy).

## Sharp edges
- **The `--reseed` flag does not exist in `cmd_sync`'s argument handling.**
  `cmd_sync` (source, ~line 155-156) parses only `variants=("${@:-}")` — every
  positional argument to `sync` is treated as a variant name, and it calls
  `seed_locally "$v"` with a single argument. `seed_locally`'s own signature
  does accept a second parameter checked against the literal string
  `--reseed` (line 131: `[[ "${2:-}" == "--reseed" ]]`), but nothing in
  `cmd_sync` or the top-level `case` dispatcher ever supplies that second
  argument — there is no code path by which a user-facing `--reseed` flag on
  the `sync` command reaches `seed_locally`. The printed hint
  ("pass --reseed to force regeneration") is misleading: passing
  `script/vm_scenario_run.sh sync smoke --reseed` would just treat `--reseed`
  as an unknown seed variant name and fail with
  `unknown seed variant: --reseed (want smoke|faces|empty)` from
  `seed_dir_for`. `test/scenarios/README.md`'s own prose gets this right —
  it says to delete `$TMPDIR/teststrip-vm-seeds/<variant>` to force a reseed,
  and explicitly notes "pass a second positional isn't needed" — but the
  script's own runtime message contradicts the README by implying a
  `--reseed` flag exists on `sync`. This is the real sharp edge: the flag
  name from the task brief doesn't exist as a working CLI option, only the
  manual-delete workaround (`rm -rf $TMPDIR/teststrip-vm-seeds/<variant>`)
  actually works, and the script's own hint text is a latent bug worth fixing
  separately (not fixed here per instructions).
- `cmd_launch`'s `original_path` rewrite is a plain SQL `replace()` on a
  string prefix; if a variant's local seed path is a prefix of some other
  unrelated substring elsewhere in `original_path` (unlikely given seed dirs
  are absolute paths under `$TMPDIR`), the rewrite could corrupt data. Not
  exercised here.
- `destroy` is unconditionally destructive (stop + delete) with no
  confirmation prompt — the whole VM is gone, and the next `setup` re-clones
  from the base image from scratch.
- All ssh/scp/rsync helpers (`ssh_cmd`, `scp_to_vm`) shell out with
  `SSHPASS="$VM_PASS" sshpass -e ...` and hardcoded `admin`/`admin`
  credentials by default (`TESTSTRIP_VM_USER`/`TESTSTRIP_VM_PASS`) — fine for
  a throwaway local Tart VM, not a pattern to reuse anywhere credentials
  matter.
- `usage()` is generated by `sed`-extracting lines 2-40 of the script's own
  header comment rather than a hand-written usage string — if that comment
  block is edited without care for line count, `--help`/`help`/no-args output
  could silently truncate or overflow past the intended section.
