# Real-Scale Import Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a 600-image import show first visible feedback within 1.5s, keep the app responsive while previews drain, and unstarve the worker, by removing catalog queries from SwiftUI render paths.

**Architecture:** AppModel's `latestImport*` computed properties run SQLite queries and per-row JSON decoding on every access, and `LibraryGridView.body` → `topInsetContent` evaluates them on every render pass. Convert them to stored presentation state refreshed on the events that can change them, following the same cached-presentation pattern the model already uses for review-queue counts. The worker dispatch loop rides the main thread, so unblocking the main thread is also the preview-drain fix; deeper worker changes are gated on re-measurement.

**Tech Stack:** Swift 6, SwiftUI, SQLite3, XCTest, shell verifiers under `script/`.

## Global Constraints

- TDD: every behavior change lands with a failing-first test (superpowers:test-driven-development).
- Smallest reasonable change; no drive-by refactoring of AppModel.
- Public getter names (`latestImportCompletionSummary`, `latestImportFlaggedReviewAssetCount`, `latestImportFaceReviewAssetCount`, `latestImportBatchKeywordSuggestions`, `canRequestLatestImportAssetEvaluations`) keep their signatures so LibraryGridView and ~30 existing tests keep compiling.
- No backward-compatibility paths; no new dependencies.
- Foreground UI automation is allowed freely (Jesse, 2026-07-06).
- All measured claims must come from the commands in Task 3, not estimates.

## Measured Evidence (2026-07-06, this machine)

Baseline via fixed probes (commits `7569ed8`, `ba0e88d` fixed the probe harness itself; single-image run passes at `feedback_visible_seconds=0.622`):

- 600-image `verify_import_path.sh`: `feedback_visible_seconds=32.405`, `target_visible_seconds=34.974`, `app_cpu_percent=62.1`, `worker_cpu_percent=2.2`, `pending_previews_after_sample=982`, `preview_drain_completed=false`, 982→809 pending in a 31s window (~5.6 previews/s; the same machine drains 400/s headless via `script/verify_import_preview_drain.sh 100`).
- `sample Teststrip` during import (scratchpad `app-during-import.txt`): 3448/7081 main-thread samples inside `LibraryGridView.body.getter` (LibraryGridView.swift:181) → `topInsetContent` (LibraryGridView.swift:418) → `importCompletionSummary(_:)` (LibraryGridView.swift:984) → `AppModel.latestImportFlaggedReviewAssetCount` (AppModel.swift:1611) → `latestImportCompletionSummary` (AppModel.swift:1764) → `latestImportStackSummary` (AppModel.swift:1836) → `latestImportStacks` (AppModel.swift:7274) → `CatalogRepository.assets(ids:limit:offset:)` (CatalogRepository.swift:187) with JSONDecoder per row.
- `sample Teststrip` during drain (`app-during-drain.txt`): 4024/7333 main-thread samples in `topInsetContent`, split across `latestImportCompletionSummary` (evaluated ≥3× per pass), `canRequestLatestImportAssetEvaluations`, `latestImportFlaggedReviewAssetCount`, `latestImportBatchKeywordSuggestions`.
- `sample TeststripWorker` during drain: blocked in `__read_nocancel` on stdin — starved, not slow. WorkerSupervisor handles output lines and dispatches on `DispatchQueue.main` (WorkerSupervisor.swift:66-75), so a saturated main thread throttles dispatch.

**Root cause:** repository-backed computed properties evaluated inside SwiftUI `body` on every render; render invalidations are constant during import/drain; the pegged main thread both delays visible feedback and starves worker dispatch. One root cause, both symptoms.

---

### Task 1: Cache the import-completion panel state on AppModel

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (getters at 1585-1623, 1764-1847, plus `canRequestLatestImportAssetEvaluations` and `latestImportBatchKeywordSuggestions` near 1585; find exact refresh hook sites listed in Step 3)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Consumes: existing `CatalogRepository` query methods; existing refresh sites that already recompute review-queue counts after imports, metadata edits, evaluation completion, and preview queue changes.
- Produces: `private(set) var latestImportPresentation: LatestImportPresentation` (stored struct with fields `summary: ImportCompletionSummary?`, `flaggedReviewAssetCount: Int`, `faceReviewAssetCount: Int`, `batchKeywordSuggestions: [BatchKeywordSuggestion]`, `canRequestAssetEvaluations: Bool`) plus `func refreshLatestImportPresentation()`. The five existing public getter names remain but return the stored fields.

- [ ] **Step 1: Write the failing cachedness test.** In `AppModelTests.swift`, copy the fixture from the existing `latestImportFlaggedReviewAssetCount` test (AppModelTests.swift:~8595-8610: catalog-backed model with a completed import activity and one likely-issue asset). New test: assert count == 1; then insert a second likely-issue evaluation signal for another imported asset **directly through the repository** (same repository calls the fixture used, bypassing AppModel); assert `latestImportFlaggedReviewAssetCount` is **still 1** (cached — this is the failing assertion today, because the live getter sees 2); then call the model's public refresh path (`model.refreshLatestImportPresentation()`) and assert it becomes 2.
- [ ] **Step 2: Run it and confirm it fails** with `swift test --filter AppModelTests/<newTestName>` — expected failure: count is 2 before refresh (getter is live, not cached).
- [ ] **Step 3: Implement the cache.** Add the `LatestImportPresentation` struct and stored property; move the bodies of the five getters into a builder `private func buildLatestImportPresentation() -> LatestImportPresentation`; getters return stored fields. Call `refreshLatestImportPresentation()` from every site that can change the panel: (a) worker/local import completion handling (`handleWorkerCommandCompleted` import branch and the local-fallback completion path), (b) the coalesced preview queue-change handling inside `onQueueChanged` (AppModel.swift:2173-2192) — only when preview work state changed, (c) metadata/evaluation refresh sites that already refresh review-queue counts, (d) `AppModel.load`/init after `rebuildSidebarSections()`, (e) import-completion dismiss. Keep the builder cheap when there is no import-completion activity (early return nil summary without repository calls).
- [ ] **Step 4: Run the new test to green**, then `swift test --filter AppModelTests` — the ~30 existing `latestImport*`/summary tests are the regression net; every one must pass without edits to their assertions. Any that fail mark a missing refresh hook — add the hook, do not weaken the test.
- [ ] **Step 5: Full `swift test`** — expected: all pass (994 baseline, 5 skipped).
- [ ] **Step 6: Commit** with a message recording the root cause (repository queries in SwiftUI body) and the caching approach.

### Task 2: Verify the render path no longer queries the catalog

- [ ] **Step 1:** Rebuild and rerun the reproduction: `./script/build_and_run.sh --verify-smoke && ./script/submit_import_path.sh Teststrip <600-image dir>` then `sample Teststrip 10 -file /tmp/after-fix-import.txt` immediately, and again ~30s later during drain.
- [ ] **Step 2:** Assert in the samples: `latestImportStacks`, `latestImportCompletionSummary`, and `CatalogRepository.assets` no longer appear under `LibraryGridView.body`; main-thread share of `topInsetContent` drops to noise (<5%).
- [ ] **Step 3:** If `topInsetContent` still dominates, sample deeper, identify the next repository-in-body offender, and return to Task 1's pattern for it (one fix at a time). Known second-tier candidates from the drain sample: none above 5% after the five getters, but verify empirically.

### Task 3: Re-measure the 600-image foreground gates

- [ ] **Step 1:** `./script/build_and_run.sh --verify-smoke && TESTSTRIP_AX_IMPORT_COUNT=600 TESTSTRIP_AX_TIMEOUT_SECONDS=75 ./script/verify_import_path.sh Teststrip`
- [ ] **Step 2:** Acceptance: `feedback_visible_seconds ≤ 1.5`, `target_visible_seconds ≤ 10`, `preview_drain_completed=true` within the 30s sample window at 600 images or a measured drain rate ≥ 50 previews/s, `app_cpu_percent` below 40 during drain.
- [ ] **Step 3:** If feedback passes but drain rate stays < 50/s with worker idle: the main thread is no longer the bottleneck and the synchronous one-command-per-preview dispatch is. Only then design batch preview worker commands (`WorkerCommand.generatePreview` is one command per asset per level today — 1,200 round trips for 600 images). That is a separate plan; measure first.
- [ ] **Step 4:** Repeat at `TESTSTRIP_AX_IMPORT_COUNT=5000` per the spec; record metrics. Acceptance: app stays responsive (feedback ≤ 1.5s), drain scales roughly linearly.
- [ ] **Step 5:** Update `docs/architecture/performance.md` and the alpha plan's snapshot with the new measured numbers, replacing the invalidated 19.7s/48.9s evidence and noting the probe fixes (`7569ed8`, `ba0e88d`).
- [ ] **Step 6:** Commit docs + any threshold changes.

### Task 4: Keep this measurable — add the foreground import gate to the routine ladder

- [ ] **Step 1:** Add the 600-image `verify_import_path.sh` run (with its acceptance thresholds as env defaults) to `script/verify_app_workflows.sh` so the foreground suite regress-detects import feel; headless gate stays unchanged.
- [ ] **Step 2:** Run `./script/verify_app_workflows.sh Teststrip` end-to-end once; fix any probe-harness breakage it surfaces (activation fix `7569ed8` applies to all probes already).
- [ ] **Step 3:** Commit.
