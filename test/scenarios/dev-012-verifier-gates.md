# dev-012-verifier-gates: Headless verifier gate, run locally; app-workflow gate, documented only

**What this covers**
As a developer I want to know which legs of the local headless verification
gate (`script/verify_headless_workflows.sh`) are actually green in this
environment before trusting it as a pre-tag/pre-merge check, and to have the
two known-stale GUI legs of `script/verify_app_workflows.sh` documented
rather than silently assumed working. This covers the "local verification
gates are honestly characterized" leg of the capability inventory. Scripts:
`script/verify_headless_workflows.sh` (run live, host-console-touching,
non-interactive/no AX driving — it's a headless `swift test` + CLI-only
smoke harness) and `script/verify_app_workflows.sh` (read only, **not run**
in this card — it drives the live GUI via AX, out of scope here per the
brief).

## Pre-state
Fresh checkout, repo root, no prior isolated catalog state required —
`verify_headless_workflows.sh` builds and seeds its own throwaway state via
`build_and_run.sh --build-sandboxed` internally.

## Steps
1. Read both scripts in full to know exactly what each leg does before
   running anything:
   ```bash
   cat script/verify_headless_workflows.sh
   cat script/verify_app_workflows.sh
   ```
2. Run the headless gate live and capture full output:
   ```bash
   ./script/verify_headless_workflows.sh 2>&1 | tee /tmp/headless_run.log
   echo "exit: $?"
   ```
3. Do **not** run `verify_app_workflows.sh` in this card — note its legs from
   the read in step 1 instead.

## Expected

`verify_headless_workflows.sh` runs these legs in order (`set -euo pipefail`,
so it stops at the first failure):
1. `swift test`
2. `build_and_run.sh --build-sandboxed`
3. `verify_metadata_write.sh 100 5`
4. `verify_card_import_smoke.sh 12 5`
5. `verify_import_preview_drain.sh 100 5 10`
6. `verify_source_availability.sh 120 5`
7. `verify_offline_reconnect_smoke.sh 5`
8. `verify_preview_render.sh 12 5`
9. `verify_local_http_model_smoke.sh 5 3 1`
10. `verify_real_local_http_model_smoke.sh`
11. `verify_real_corpus_smoke.sh`
12. `verify_raw_fixtures.sh`
13. `verify_worker_recovery.sh 24 5`

**Actual result on this run (2026-07-10, repo HEAD on
`fix-worker-death-recovery`): leg 1 (`swift test`) failed, so the script
exited before reaching legs 2-13 — none of them ran.**

`swift test` output: 1693 tests executed, 5 skipped, 2 failures (1
unexpected), in `WorkerEntrypointTests`:
```
Test Case '-[TeststripWorkerTests.WorkerEntrypointTests testRefreshAvailabilityCommandUpdatesCatalogThroughWorkerProcess]' started.
.../Tests/TeststripWorkerTests/WorkerEntrypointTests.swift:166: error: ... XCTAssertEqual failed: threw error "dataCorrupted(...\"The given data was not valid JSON.\"...\"Unexpected end of file\"...)"
.../Tests/TeststripWorkerTests/WorkerEntrypointTests.swift:170: error: ... XCTAssertEqual failed: ("online") is not equal to ("missing")
Test Case '...testRefreshAvailabilityCommandUpdatesCatalogThroughWorkerProcess]' failed (4.862 seconds).
Test Suite 'WorkerEntrypointTests' failed ... Executed 4 tests, with 2 failures (1 unexpected) in 10.124 (10.125) seconds
```
`WorkerEntrypointTests` runs the real out-of-process worker binary end to end
(`testImportFolderCommandCatalogsThroughWorkerProcess` etc. pass); the
failing test writes/reads a real JSON-lines command through the worker
process and got a truncated/empty response on the refresh-availability round
trip, then asserted a stale `"online"` status where `"missing"` was expected
— reads as a real race or resource contention against the worker process (not
an obviously flaky assertion; and not something this card fixes per its
"observation, not a fix card" scope). This is a **legitimate hard failure of
leg 1**, meaning legs 2-13 are **unverified in this environment run** — do
not claim they're green without a clean `swift test` first.

**Fails if** a future run reports all 13 legs green with no caveats when
`swift test` itself is red — that would be a false "success" claim this card
exists to prevent.

`verify_app_workflows.sh` legs (read, not executed): launches via
`build_and_run.sh --verify-smoke` with `TESTSTRIP_CARD_IMPORT_ROUTE=typed-path`,
then in order: `verify_grid_activation.sh`, `verify_grid_selection_feedback.sh`,
`verify_keyboard_culling.sh`, `verify_import_path.sh`, with a resource-usage
snapshot (`emit_app_workflow_snapshot`) after each step. `verify_evaluation.sh`
and `verify_card_import_path.sh` were **removed** (2026-07-10) — see Sharp
edges.

## Cleanup
```bash
rm -f /tmp/headless_run.log
```
`verify_headless_workflows.sh` and the `swift test` run leave no isolated app
state behind by themselves (each internal script manages its own throwaway
workspace); no `--delete` reset needed since no `build_and_run.sh --smoke`
instance was launched by this card directly.

## Sharp edges
- **`verify_evaluation.sh` and `verify_card_import_path.sh` were deleted**
  (2026-07-10, this fix round): they were KNOWN-STALE — the
  post-UX-simplification sweep demoted the top-level "Evaluate" button and
  "Import Card" entry into menus (More ▾ → Analyze ▾ → Evaluate; Import ▾ →
  From Card…), and these two verifiers drove the old top-level controls,
  masked with `|| true` so they never actually gated anything. They're
  superseded by the VM scenario cards (this card, lib-\*/people-\* cards
  driving current chrome), so removing them loses no real coverage. Their
  legs were removed from `verify_app_workflows.sh` accordingly.
- `verify_people_clustering.sh`'s "Evaluate Scope" `AXButton` press (also
  `|| true`-masked, also stale — the control is now a People-menu item, not a
  top-level button) was dropped rather than guessed at; `people-009-scan.md`
  is the card that drives the current People-menu scan path live.
- The headless gate's leg-1 failure in this run means this card cannot
  honestly report legs 2-13 (`verify_metadata_write.sh` through
  `verify_worker_recovery.sh`) as passing, skipped, or failing — they simply
  never got a chance to run. A re-run after the `swift test` regression is
  fixed (or on a green `swift test` commit) is needed to get real leg-by-leg
  status for 2-13.
- `verify_app_workflows.sh` was read but intentionally not executed in this
  card (it drives the live GUI via AX, out of scope per the brief); its
  known-stale legs above are documented from the script's own comment, not
  from a live run.
