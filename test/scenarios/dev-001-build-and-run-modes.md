# dev-001-build-and-run-modes: build_and_run.sh flag surface

**What this covers**
As a developer I want `script/build_and_run.sh`'s CLI surface (help, unknown
flags, build-only, and a launch/quit smoke verify) to behave exactly as
documented, so a future flag change doesn't silently break the dev workflow.
Covers the capability-inventory entries for local build/run tooling and the
`--verify-smoke` isolated-launch path. Script under test: `script/build_and_run.sh`.

## Pre-state
- Repo checked out at `/Users/jesse/git/projects/teststrip`, working directory
  is the repo root.
- No app instance running: `pkill -x Teststrip; pkill -x TeststripApp; pkill -x TeststripWorker` (ignore failures).

## Steps
1. Help text:
   ```bash
   ./script/build_and_run.sh --help
   echo "exit=$?"
   ```
2. Unknown flag:
   ```bash
   ./script/build_and_run.sh --bogus-flag
   echo "exit=$?"
   ```
3. Build only (compiles + assembles + signs the app bundle, does not launch):
   ```bash
   ./script/build_and_run.sh --build
   echo "exit=$?"
   ls -d dist/Teststrip.app
   ```
4. **Host-console-touching.** Launch/quit verification with the smoke seed
   (24 synthetic photos into a throwaway isolated app-support dir), then quit
   immediately — do not drive the UI further:
   ```bash
   ./script/build_and_run.sh --verify-smoke
   echo "exit=$?"
   # then quit the launched instance:
   pkill -x Teststrip
   ```

## Expected
- Step 1: exit code `0`. Stdout (the script writes `usage()` to stderr, but
  `--help` is handled as a case arm that calls `usage` then `exit 0` — capture
  combined output) contains the literal substring:
  `usage: ./script/build_and_run.sh [run|--build|--build-sandboxed|--sandboxed|--verify|--verify-sandboxed|--isolated|--verify-isolated|--smoke|--verify-smoke|--sample-photos|--verify-sample-photos|--faces|--verify-faces|--real-corpus|--verify-real-corpus|--debug|--logs|--telemetry]`
  (confirmed live: `--help` prints this line and exits 0.)
- Step 2: exit code `2`. Same usage string printed to stderr (confirmed live:
  unknown flag `--bogus-flag` produced exit 2 with the identical usage line).
- Step 3: exit code `0`. Output contains `Built /Users/jesse/git/projects/teststrip/dist/Teststrip.app`.
  `dist/Teststrip.app` exists as a directory after the run. No app process is
  launched (`pgrep -x Teststrip` finds nothing attributable to this step).
- Step 4: the script's internal `verify_app()` loop polls up to 40 times at
  0.25s for `pgrep -x Teststrip` to succeed, then prints
  `Teststrip is running from <dist path>` and
  `Teststrip is using isolated application support at <mktemp dir>`, then
  returns 0 (script exit 0). If it fails to start within 10s, `verify_app()`
  prints `Teststrip did not start` to stderr and returns 1 (script exit
  reflects that failure since `set -euo pipefail` is active and this is the
  last command in the `--verify` case arm).

## Cleanup
```bash
pkill -x Teststrip 2>/dev/null || true
pkill -x TeststripApp 2>/dev/null || true
pkill -x TeststripWorker 2>/dev/null || true
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **Usage-text/behavior drift bug**: the `usage()` line (script line ~44) does
  not list `--real-corpus` or `--verify-real-corpus` even though the `case`
  statement at ~line 223 fully handles both (seeds a real photo corpus from
  `sample-data/photos/jesse-pictures` or `$TESTSTRIP_REAL_CORPUS_DIR`, with
  `BACKGROUND_OPEN=1` so the app opens without stealing focus). Anyone reading
  only `--help` output would not discover these two working modes. Do not fix
  this — noted here per instructions.
- `--build` and `build` (no leading dashes) are both accepted as the same
  case arm, as are several other flags (e.g. `--verify`/`verify`,
  `--smoke`/`smoke`). The dashless forms are undocumented in `usage()` too,
  which only shows the dashed spelling.
- `stop_running_app` (pkill of Teststrip/TeststripApp/TeststripWorker) runs
  before every mode except `--build`/`build`, so a `--verify-smoke` run will
  silently kill any instance you left open from a prior manual dogfood
  session — don't run this card against your real console session.
- The isolated app-support directory path is only surfaced in the script's
  own stdout (`... is using isolated application support at ...`); there is
  no separate flag to print it without launching. Other cards recover it via
  `ps eww` grep on `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY` (see
  `import-cull-pick-happy-path.md`'s Pre-state) rather than scraping this
  line, since the line's exact prefix could change.
- `--verify` modes never exit the app for you — step 4 above explicitly
  `pkill`s afterward. Skipping that leaves a live instance and a live worker
  process running against a throwaway catalog.
