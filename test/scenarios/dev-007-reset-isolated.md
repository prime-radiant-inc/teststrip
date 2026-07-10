# dev-007-reset-isolated: Isolated test-data reset is marker-gated and running-app-safe

**What this covers**
As a developer running scenario cards repeatedly, I want
`script/reset_isolated_test_data.sh` to (a) default to a dry-run report of
what it *would* delete, (b) only ever consider directories that carry a real
Teststrip marker, (c) refuse to delete a directory a running instance is
still using, and (d) actually delete under `--delete`. Every card's Cleanup
section (see `test/scenarios/README.md` step 5) leans on this script never
eating state it shouldn't — this card is the ground-truth check on that
safety net. Covers `script/reset_isolated_test_data.sh` only; no other
script or capability-inventory entry.

## Pre-state
- Repo checkout, no build required — this is a pure bash + filesystem script.
- `ROOT="${TESTSTRIP_ISOLATED_TEST_DATA_ROOT:-${TMPDIR:-/tmp}}"` (the script's
  own default resolution). Do not override `TESTSTRIP_ISOLATED_TEST_DATA_ROOT`
  for this card — exercise the real default so the dry-run scan reflects
  Jesse's actual `$TMPDIR` state.

## Steps
1. **Default (dry-run) behavior**, run from repo root:
   ```bash
   ./script/reset_isolated_test_data.sh
   echo "exit=$?"
   ```
2. **Marker mechanism.** Read `has_teststrip_marker()` in the script (lines
   50–55): a candidate directory `$ROOT/teststrip-app-support.*` is only
   considered deletable if it has at least one of:
   - `Teststrip/catalog.sqlite` (file)
   - `Teststrip/Previews` (dir)
   - `Teststrip/SmokeOriginals` (dir)

   Confirm this live against whatever `teststrip-app-support.*` dirs already
   exist in `$ROOT` from prior card runs — every line printed in step 1 is
   either `would_delete` (marker present) or `skip_unmarked` (marker absent).
   No extra directory creation needed if any already exist; if `$ROOT` is
   clean, create one throwaway marked dir yourself to exercise the branch:
   ```bash
   FIXTURE="$ROOT/teststrip-app-support.dev007fixture"
   mkdir -p "$FIXTURE/Teststrip/Previews"
   ./script/reset_isolated_test_data.sh   # should report would_delete for $FIXTURE
   ```
3. **Running-app safety check.** Read `running_app_support_directories()`
   (lines 32–48): it shells out to `/bin/ps eww -axo command=` and greps
   every process's argv/environ line for a `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=`
   token (the isolated launch mechanism sets this env var on the app
   process — see `script/build_and_run.sh`). `is_running_support_root()`
   then skips any marked candidate whose path matches one of those live
   values, printing `skip_running` instead of `would_delete`/`deleted`. The
   script also honors a test seam,
   `TESTSTRIP_RUNNING_APP_SUPPORT_DIRECTORIES`, that substitutes for the `ps`
   scan — use it here so the check is exercised deterministically without
   needing a real running app instance:
   ```bash
   TESTSTRIP_RUNNING_APP_SUPPORT_DIRECTORIES="$FIXTURE" \
     ./script/reset_isolated_test_data.sh
   ```
4. **`--delete` actually removes**, using only the fixture this card created
   (never a directory the card didn't create — see Sharp edges on why that
   matters for shared `$TMPDIR`):
   ```bash
   test -d "$FIXTURE" && echo "fixture present before delete"
   ./script/reset_isolated_test_data.sh --delete
   test -d "$FIXTURE" || echo "fixture removed"
   ```
5. **`--help`/unknown-arg exit codes** (from the script's `usage()`/case
   block, lines 7–25):
   ```bash
   ./script/reset_isolated_test_data.sh --help; echo "help exit=$?"
   ./script/reset_isolated_test_data.sh --bogus 2>&1; echo "bogus exit=$?"
   ```

## Expected
- Step 1: exit code `0`. Output is one line per `teststrip-app-support.*`
  entry under `$ROOT`, each prefixed `teststrip_reset_isolated_test_data`
  and tagged `would_delete <path>` or `skip_unmarked <path>`; if none exist,
  a single `teststrip_reset_isolated_test_data none root=$ROOT` line. Actual
  captured output on this machine (illustrative, will vary run to run):
  ```
  teststrip_reset_isolated_test_data would_delete /var/folders/.../teststrip-app-support.7PKQWK
  teststrip_reset_isolated_test_data skip_unmarked /var/folders/.../teststrip-app-support.manual.9CJVgv
  ```
  **Fails if** any `--delete`-only side effect occurs on a plain invocation
  (no `rm -rf` should run without `--delete` — verify no fixture directories
  disappear as a side effect of step 1/2/3/5).
- Step 2: `$FIXTURE` (marker: `Teststrip/Previews`) appears as
  `would_delete $FIXTURE`, never `skip_unmarked`, confirming the three-way
  marker check accepts a preview-cache-only directory (no catalog.sqlite
  required).
- Step 3: with `TESTSTRIP_RUNNING_APP_SUPPORT_DIRECTORIES="$FIXTURE"` set,
  the line for `$FIXTURE` changes to
  `teststrip_reset_isolated_test_data skip_running $FIXTURE`. **Fails if**
  it still reports `would_delete` — the running-instance guard is the whole
  point of this card.
- Step 4: `fixture present before delete` prints; after `--delete`, the line
  for `$FIXTURE` reads `teststrip_reset_isolated_test_data deleted $FIXTURE`
  and `fixture removed` prints (the `test -d` check confirms the directory
  is actually gone on disk, not just reported gone).
- Step 5: `--help` exits `0` and prints `usage: ./script/reset_isolated_test_data.sh [--delete]`
  to stderr; `--bogus` exits `2` with the same usage line on stderr.

## Cleanup
Step 4 already deletes `$FIXTURE` via the script under test — that *is* the
assertion, not an afterthought. If step 4 is skipped for any reason, remove
it manually: `rm -rf "$FIXTURE"`. This card creates no other state; it never
runs `./script/build_and_run.sh`, so there is no launched app instance to
quit and no host-console interaction.

## Sharp edges
- `$ROOT` is the *shared* `$TMPDIR`/`TESTSTRIP_ISOLATED_TEST_DATA_ROOT` —
  other cards' and sibling agents' `teststrip-app-support.*` directories may
  legitimately be present during step 1's scan. This card must only ever
  `--delete` the directory it created itself (`$FIXTURE`); never run a bare
  `--delete` in a shared environment expecting it to be scoped to this card.
- The `TESTSTRIP_RUNNING_APP_SUPPORT_DIRECTORIES` test seam (step 3) is not
  documented in the script's `--help` text — it's discoverable only by
  reading the source. Worth calling out if `--help` output is ever
  "improved," since removing the seam silently would break this card.
- `skip_unmarked` directories are silently left alone forever, even under
  `--delete` — there is no force-delete-anything mode. If `$TMPDIR` ever
  accumulates genuinely stale unmarked `teststrip-app-support.*` dirs (e.g.
  from a killed process mid-init before the marker file/dir was created),
  this script will never clean them up.
