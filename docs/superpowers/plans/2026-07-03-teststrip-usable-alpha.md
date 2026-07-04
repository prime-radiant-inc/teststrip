# Teststrip Usable Alpha Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Teststrip from a working foundation build into a usable macOS alpha for fast, non-destructive photo catalog management, browsing, culling, metadata/XMP sync, preview-based offline work, and local-first agentic evaluation.

**Architecture:** Teststrip is a native macOS app with SwiftUI/AppKit UI surfaces, a SQLite-backed catalog as the operational source of truth, external originals, a persistent preview cache, catalog-first metadata edits, automatic XMP sidecar mirroring for portable fields, and one supervised local worker helper for long-running import, preview, XMP, source, and recognition work. The app must remain responsive when originals live on NAS, removable, cloud-synced, or offline volumes.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, AppKit where needed, SQLite3, ImageIO/CoreGraphics, Vision, JSON-lines worker protocol, shell-first app verification scripts, Accessibility/CoreGraphics UI automation.

---

## Current Snapshot

- Branch: `wip/teststrip-usable-foundation`
- Snapshot commit: `b84aa2e Improve inspector mockup parity`
- Product posture: foundation/dev build moving toward usable alpha, not yet a polished photo app.
- Last broad unit verification: `swift test` passed with 456 tests after the inspector mockup-parity pass.
- Last app workflow verification: `script/build_and_run.sh --sample-photos`, Computer Use inspection of the running app, `script/verify_grid_activation.sh`, `script/verify_grid_selection_feedback.sh`, `script/verify_keyboard_culling.sh`, and `TESTSTRIP_AX_TIMEOUT_SECONDS=20 script/verify_imported_grid_culling.sh Teststrip` passed after the inspector mockup-parity pass. Earlier repeated `script/build_and_run.sh --verify-smoke` launches plus 600-image AX import probes completed, but the large-import UX blocker remains open. The best intermediate run after coalescing worker-progress reloads showed feedback around 14.9s and target visibility around 34.1s; the latest full-slice run showed feedback around 19.7s, target visibility around 48.9s, and preview drain still incomplete after the verifier's sample window. A submit-only Import Path probe measured the target asset reaching the catalog around 0.12s after submit and import work finishing around 0.53s after submit, which means current slowness is mostly UI/AX visibility and preview-drain behavior rather than raw catalog import. Before that, `script/build_and_run.sh --verify-sample-photos` plus Computer Use verified the Needs Keywords review row and real WordPress sample-photo grid behavior.

### Recent Completed Slices

- `2a55910` / `41a8dd8` / `64a7821`: added real free stock-photo sample fixtures and made `script/build_and_run.sh --sample-photos` seed a clean sample catalog.
- `04a291f`: made the standalone sample downloader default to the WordPress Photo Directory sample set and added `--print-config`.
- `3088489`: added persisted thumbnail-size/density control.
- `9274ad1`: added built-in review queues for common culling filters.
- `235c878` / `127cf13`: made import progress and imported-grid culling observable through AX probes.
- `5563caa`: kept the footer explicit after import completion while preview generation continues.
- `59c4219`: added selected-photo preview at the top of the inspector.
- `7351798`: added active filter chips under the search/filter bar.
- `f2b57f3` / `51f0d1f`: made culling sessions loupe-first and added frame/shortcut guidance to the loupe overlay.
- `edc6f08`: added an Import Path plan explaining non-destructive cataloging, XMP sidecars, cached previews, and managed background work before the user imports.
- `7b68f7e`: fixed stale XMP pending state when worker sync finds the sidecar already matches the catalog.
- `a44a1da`: staged Import Folder and Import Card through confirmation sheets that summarize source, destination, and the non-destructive/XMP/preview/background-work plan before work starts.
- `64e707e`: added a catalog-backed Needs Keywords review queue and active filter chip for unkeyworded assets.
- `037162c`: clarified import verifier metrics so target visibility, import completion, worker CPU, and preview drain are reported separately.
- `5c153fa`: made ingest persist the first cataloged assets eagerly and then in batches, carrying cataloged IDs in progress events for earlier grid updates.
- `81ec38a`: reduced import-time UI churn by batching worker queue notifications, exposing only the first cataloged asset during a running worker import, shrinking the default grid page/window to 120/240 assets, reducing automatic preview recovery from 200 to 40 queued items, and making evaluation toolbar enablement avoid preview-cache scans.
- `a4efda0`: improved library mockup parity by preserving thumbnail aspect ratios in the overview grid, tightening the Ask/search filter rail, and pinning the inspector selected-preview box to a stable size.
- `feed363`: improved culling/loupe mockup parity with a denser rapid-cull header, command rail, and layout framing backed by existing culling state.
- `b84aa2e`: improved inspector mockup parity with compact rating/flag/label controls, scrollable metadata sections, pinned Activity, tested filename/status/technical display models, keyword chips, and highlighted Teststrip evaluation signals.

## Product Decisions To Preserve

- V1 is macOS first. iOS portability can matter later, but it should not distort the first UI architecture.
- Teststrip is 100% non-destructive and external-file based. Originals stay where the photographer keeps them unless the user explicitly chooses card/camera ingest copy behavior.
- The catalog is operational truth. UI reads and writes catalog state first; XMP is the automatic portability layer.
- Lightroom catalog migration is out of scope.
- Watched folders are out of scope for v1.
- Pre-import culling is out of scope. Import/catalog first; culling works over arbitrary catalog sets after assets exist.
- Map/location is not a go-to-market front door unless Jesse reopens that decision.
- Local-first recognition/evaluation is the default. Provider boundaries should support Apple local APIs, local HTTP providers such as LM Studio/Ollama, and future opt-in cloud providers.
- The worker must be manageable: visible, bounded, pausable for future dispatch, cancellable, timeout-protected, and normally stopped with the app.
- Jobs are work sessions/history, not the main asset container. Sets/searches/clusters are the asset membership concept. A work session points to input, generated, and output sets.

## What Is Built

### App Shell And Build

- Native SwiftPM macOS app target in `Sources/TeststripApp`.
- Worker executable target in `Sources/TeststripWorker`.
- Bench/smoke target in `Sources/TeststripBench`.
- Build/run script: `script/build_and_run.sh`.
- Packaged dev app flow stages `TeststripWorker` as a signed helper at `Contents/Helpers/TeststripWorker`.
- Isolated app-support launches are supported through `TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY` so tests and smoke runs do not touch the user's real catalog.

### Catalog And Domain Model

Built files include:

- `Sources/TeststripCore/Catalog/CatalogDatabase.swift`
- `Sources/TeststripCore/Catalog/CatalogMigrations.swift`
- `Sources/TeststripCore/Catalog/CatalogRepository.swift`
- `Sources/TeststripCore/Domain/Asset.swift`
- `Sources/TeststripCore/Domain/Metadata.swift`
- `Sources/TeststripCore/Domain/SourceAvailability.swift`
- `Sources/TeststripCore/Work/WorkSession.swift`
- `Sources/TeststripCore/Search/AssetSet.swift`
- `Sources/TeststripCore/Search/SetQuery.swift`

Current behavior:

- SQLite catalog stores assets, folders, source roots, work sessions, saved asset sets, preview queue state, metadata sync state, evaluation signals, and source availability state.
- Grid/library paging uses repository APIs rather than loading the whole catalog. The default grid page is 120 assets with a 240-asset loaded window.
- Synthetic catalog benchmarks exist for 500k and 1M asset scale targets.
- Current debug benchmark evidence in `docs/architecture/performance.md` shows first-page and filtered-page catalog loads stay in milliseconds for synthetic 500k/1M catalogs.

### Import And Ingest

Built files include:

- `Sources/TeststripCore/Ingest/FolderScanner.swift`
- `Sources/TeststripCore/Ingest/IngestPlanner.swift`
- `Sources/TeststripCore/Ingest/IngestService.swift`
- `Sources/TeststripCore/Ingest/LibraryImportService.swift`
- `Sources/TeststripApp/FolderSelectionPanel.swift`
- `Sources/TeststripApp/ImportFolderPathDraft.swift`

Current behavior:

- Add existing folders in place.
- Card/import copy flow exists at the service level through ingest planning and app UI plumbing.
- Imports record catalog source roots.
- Imports catalog assets before downstream analysis.
- Import worker activity is persisted to `work_sessions` while queued/running.
- Interrupted queued/running/paused ingest sessions reconcile as failed on next load instead of disappearing or falsely appearing active.
- Duplicate and empty imports now report clearly.
- The AX import verifier can create temporary images, open the Import Path sheet, submit a path, and wait until imported thumbnails appear.
- Worker import progress exposes the first cataloged asset once during a running import, then keeps the visible grid stable until completion instead of reloading the page for every cataloged progress event.

### Decode And Preview

Built files include:

- `Sources/TeststripCore/Decode/DecodeProvider.swift`
- `Sources/TeststripCore/Decode/DecodeRegistry.swift`
- `Sources/TeststripCore/Decode/ImageIODecodeProvider.swift`
- `Sources/TeststripCore/Preview/PreviewCache.swift`
- `Sources/TeststripCore/Preview/PreviewGenerationItem.swift`
- `Sources/TeststripCore/Preview/PreviewLevel.swift`
- `Sources/TeststripCore/Preview/PreviewRenderer.swift`
- `Sources/TeststripCore/Preview/PreviewScheduler.swift`
- `Sources/TeststripApp/CachedPreviewImage.swift`

Current behavior:

- Decode registry exists with an ImageIO-backed provider.
- Supported extension plumbing exists for common still formats and RAW-ish formats handled by ImageIO.
- Preview levels include micro, grid, medium, and large. Original/full decode is intentionally not part of ordinary browsing.
- Imports record pending micro/grid preview work in `preview_generation_queue`.
- Demand-driven preview requests record pending work before dispatching worker generation.
- Browsing prefers cached previews. Grid display falls back to micro while grid preview work catches up. Loupe/compare paths prefer large, then medium, then grid, then micro.
- Launch/load does not synchronously render all pending previews. App-model recovery enqueues bounded worker jobs when a worker supervisor is available.
- Automatic preview recovery is capped at 40 queued items and enqueued as a batch to avoid one observable queue update per recovered preview.
- Preview recovery skips unavailable originals and rows that have failed too many automatic attempts.
- Recent work optimized preview refill responsiveness by avoiding durable write churn and all-work scans while refilling the pending preview queue.

### Metadata And XMP

Built files include:

- `Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift`
- `Sources/TeststripCore/Metadata/MetadataSyncQueue.swift`
- `Sources/TeststripCore/Metadata/XMPPacket.swift`
- `Sources/TeststripCore/Metadata/XMPSidecarStore.swift`

Current behavior:

- Catalog edits are immediate and do not wait on sidecar writes.
- Automatic XMP writeback covers supported portable fields: ratings, color labels, pick/reject flags, keywords, captions, creator, and copyright.
- Sidecar convention is collision-safe by default: append `.xmp` to the full original filename, for example `frame.cr2.xmp`.
- Existing Adobe-style sidecars such as `frame.xmp` are read/updated only when that basename is not ambiguous.
- Teststrip never writes original image bytes on the XMP path.
- Writeback preserves unrelated XMP properties when updating an existing sidecar.
- Failed sidecar writes record pending sync items and do not roll back catalog edits.
- Worker-backed metadata edits record pending sync before enqueueing helper work.
- Selection-triggered XMP checks are coalesced.
- Sidebar exposes `XMP Pending (n)` and `XMP Conflicts (n)` catalog scopes.
- Launch-time pending sync retries are bounded and skip unavailable originals or unwritable sidecar folders.

### Source Availability And Reconnect

Built files include:

- `Sources/TeststripCore/Domain/SourceAvailabilityProbe.swift`
- `Sources/TeststripApp/SourceReconnectPathDraft.swift`

Current behavior:

- Availability states include online, offline, missing, moved, and stale.
- `/Volumes/<name>` paths can be treated as offline when the volume is unmounted rather than immediately missing.
- Availability refreshes do not increment metadata generations, so they should not create false XMP conflicts.
- Normal browsing reads catalog rows and cached previews instead of probing originals on the grid hot path.
- Loaded-window source refreshes can enqueue bounded source-scan batches through the worker.
- Sidebar exposes unavailable/questionable source scopes.
- Reconnect flow can remap a cataloged old source root to a newly mounted root when matching relative files and fingerprints exist.
- Reconnect refreshes sidebar/source summaries, moves XMP sync state to the new sidecar path, marks restored originals online, and resumes bounded pending preview generation.

### Worker Management

Built files include:

- `Sources/TeststripCore/Work/BackgroundWorkQueue.swift`
- `Sources/TeststripCore/Worker/WorkerCommand.swift`
- `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`
- `Sources/TeststripCore/Worker/WorkerProtocol.swift`
- `Sources/TeststripCore/Worker/WorkerSupervisor.swift`
- `Sources/TeststripCore/Worker/WorkerTransport.swift`
- `Sources/TeststripApp/ActivityView.swift`

Current behavior:

- Background work queue enforces a maximum number of running items.
- Work is visible through app-model projections and Activity UI.
- Queue dispatch can pause/resume. Already-dispatched synchronous helper work remains running and timeout-protected rather than being mislabeled as paused.
- Cancel terminates the worker transport where needed.
- Worker commands and JSON-lines protocol live in core so the app and worker share the same contract.
- WorkerSupervisor supports batch enqueue for sets of background work that should produce a single queue-change notification.
- `FoundationWorkerTransport` launches the helper, writes commands to stdin, and streams stdout/stderr responses.
- Worker stderr fails the oldest dispatched item and keeps the queue moving.
- Worker commands have supervisor-level timeouts.
- Managed worker queue caps source scans, XMP sync, and recognition to one running item per kind while unrelated work can use remaining global capacity.
- Current helper executes commands synchronously, so the supervisor sends one worker command to the helper at a time even when visible queue capacity is larger.

### Evaluation And Recognition Provider Scaffolding

Built files include:

- `Sources/TeststripCore/Evaluation/EvaluationProvider.swift`
- `Sources/TeststripCore/Evaluation/EvaluationSignal.swift`
- `Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift`
- `Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift`
- `Sources/TeststripCore/Evaluation/LocalHTTPModelProvider.swift`
- `Sources/TeststripBench/LocalHTTPModelSmoke.swift`

Current behavior:

- `local-image-metrics` reads cached previews and emits exposure and color-palette signals.
- `apple-vision` reads cached previews and emits face-quality, OCR, and object-label signals through Apple's Vision APIs.
- `local-http-model` is opt-in through worker launch configuration.
- App launch can pass local HTTP model config from `TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT`, `TESTSTRIP_LOCAL_HTTP_MODEL`, and `TESTSTRIP_LOCAL_HTTP_MODEL_TIMEOUT`.
- Local HTTP requests use an OpenAI-compatible chat-completions shape and embed cached previews as `image_url` data URLs.
- HTTP responses can be raw JSON or prose/fence-wrapped JSON; the provider extracts the JSON object.
- Retry behavior exists for transient transport failures and retryable response statuses.
- Evaluation output is persisted as typed `EvaluationSignal` rows with provider/model/version/settings provenance.
- `TeststripBench local-http-smoke <endpoint> <model> <image> [timeout]` exercises LM Studio/Ollama-style endpoints.

### UI And Automation

Built files include:

- `Sources/TeststripApp/LibraryGridView.swift`
- `Sources/TeststripApp/InspectorView.swift`
- `Sources/TeststripApp/SidebarView.swift`
- `Sources/TeststripApp/CullingKeyCaptureView.swift`
- `Sources/TeststripApp/CachedPreviewImage.swift`

Current behavior:

- Studio-style shell exists: sidebar, library grid, inspector, toolbar actions, activity/work surface.
- Library grid renders cached previews.
- Grid thumbnail density is user-configurable from the toolbar and persists as an app preference.
- Selection and inspector metadata display exist; the inspector now shows the selected cached preview above compact metadata controls in a fixed-size preview box, keeps Activity pinned below scrollable inspector content, and formats technical metadata through tested display models.
- Active filters are summarized as visible chips below the search/filter controls.
- Import Path shows a pre-import plan for in-place cataloging, XMP sidecars, cached previews, and managed background work.
- Culling sessions now start and reopen in loupe view with a culling header, reviewed-progress bar, pick/reject counts, stable rating/label/flag command rail, and visible frame position.
- Ratings, flags, labels, and keywords have app-model/catalog plumbing.
- Keyboard culling probe verifies selecting a thumbnail, clearing rating, sending `5`, and seeing `Rating: 5` in the inspector.
- Grid activation and selected-thumbnail feedback AX probes exist.
- CoreGraphics capture script exists for visual review.
- Evaluation AX probe exists for selected-photo evaluation.
- Submit-only Import Path helper exists for measuring catalog/import latency without continuously walking the app accessibility tree.

## Known Gaps

### Alpha-Blocking Gaps

- Preview throughput and UI churn under large preview backlogs are not good enough yet. The 600-image import path completed, but many previews were still pending after the initial wait and app CPU stayed high while draining.
- Import UX is improved but not complete. The app now shows visible post-import preview continuation and an Import Path plan, but starting/running import phases, duplicate submission prevention, permission/security-scope failures, and richer card-source staging still need work.
- Clicking/selection needs a stronger regression harness. We have AX probes, but the user observed weird broken clicking after import, and this should be treated as a real usability risk until verified under imported-photo conditions.
- Library mockup parity is improving but incomplete. The overview grid now preserves image aspect ratio inside stable cells, the filter rail is closer to the Studio mockup's Ask/search treatment, the inspector preview size is pinned, the inspector metadata controls have an initial mockup-derived pass, and the culling/loupe chrome has an initial design pass, but sidebar density and saved/search set surfaces still need visual passes against the design concept.
- The current RAW story is only the first abstraction and ImageIO-backed path. We still need an explicit decoder capability matrix and provider-swapping plan for formats Jesse named: DNG, CRW, CR2, Fuji RAW, Sigma/Foveon RAW, and specialty long-tail files. Lytro support remains out of scope.
- Evaluation is scaffolding plus early useful providers, not finished face/person/object/aesthetic workflow. People grouping, review UI, accepted labels, and reprocessing flows are not complete.
- Search/sets/work sessions are partially built but not yet the full user-facing model. Saved/ad hoc sets, clusters, work-session-derived sets, and query builder UX need more implementation.
- Smart collections are not yet a complete end-user builder.
- The app is not packaged/notarized as a production distributable. Current app bundle work is dev/smoke focused.

### Important Non-Alpha Gaps

- iOS has not started.
- Cloud model providers are not production features; local HTTP smoke coverage exists as the early proxy.
- Map/location should stay deferred unless reopened.
- Lightroom migration remains out of scope.
- Photo editing/develop tools remain out of scope.

## Usable Alpha Definition

Teststrip reaches usable alpha when a photographer can:

- Create or open a catalog without touching unrelated app-support state.
- Add an existing folder in place or ingest/copy from a card into a chosen destination.
- See thumbnails quickly and understand import/index/preview progress.
- Browse imported images without UI stalls or accidental original reads from slow volumes.
- Select, rate, label, flag, reject, keyword, and inspect photos with immediate UI acknowledgement.
- Trust automatic XMP writeback for supported portable metadata and see pending/conflict states.
- Quit/relaunch without losing import, preview, XMP, source, or work-session state.
- Browse and cull from cached previews when originals are offline.
- Reconnect moved/remounted sources safely.
- Start, pause, resume, cancel, and understand background work.
- Run local-first evaluation on selected or scoped images and see provenance-backed signals.
- Use search/sets/work sessions enough to cull or collect an arbitrary set, not only an import batch.

## Next Build Slices

### Slice 1: Preview Throughput And UI Coalescing

**Why this is first:** A photo manager that imports but then burns CPU and drains previews slowly will feel broken. This is the highest-leverage next slice because it affects import, browsing, NAS/offline workflows, and culling.

**Files to inspect first:**

- `Sources/TeststripApp/AppModel.swift`
- `Sources/TeststripApp/CachedPreviewImage.swift`
- `Sources/TeststripCore/Preview/PreviewScheduler.swift`
- `Sources/TeststripCore/Work/BackgroundWorkQueue.swift`
- `Sources/TeststripCore/Worker/WorkerSupervisor.swift`
- `Sources/TeststripCore/Worker/WorkerCommandExecutor.swift`
- `Tests/TeststripAppTests/AppModelTests.swift`
- `Tests/TeststripCoreTests/WorkerSupervisorTests.swift`
- `Tests/TeststripCoreTests/PreviewSchedulerTests.swift`
- `script/verify_import_path.sh`

**Likely work:**

- [x] Add a focused test that imports a large batch, completes import activity, and proves preview queue refill does not rescan all background work or publish per-preview global UI churn.
- [x] Coalesce preview completion state refreshes so the grid/toolbar/activity surface updates at human-visible intervals or meaningful batches.
- [ ] Keep pending preview queue recovery bounded, but make refill aggressive enough that worker idle gaps are small.
- [ ] Decide whether the synchronous helper needs batch preview commands before adding more worker concurrency. Do not add more parallel original reads until the disk/NAS impact is understood.
- [x] Extend `script/verify_import_path.sh` to report import completion time, pending preview count after a fixed window, final drain time, and process CPU snapshot.
- [ ] Verify with `swift test --filter AppModelTests --filter WorkerSupervisorTests` only if supported by SwiftPM filtering; otherwise run the focused test files separately.
- [x] Verify with full `swift test`.
- [x] Verify with `./script/build_and_run.sh --verify-smoke`.
- [x] Verify with `TESTSTRIP_AX_IMPORT_COUNT=600 TESTSTRIP_AX_TIMEOUT_SECONDS=75 ./script/verify_import_path.sh Teststrip`.
- [x] Commit with a message explaining the measured before/after preview backlog behavior.

**Acceptance:** 600-image import should stay visibly responsive, import completion should not wait for all downstream previews, preview backlog should drain without sustained UI churn, and the verifier should print enough timing/counter evidence for future regressions.

**Current result:** Not accepted yet. The verifier now has enough timing/counter evidence, and import completion is independent from downstream preview drain, but 600-image visible-feedback/target-visible timings remain too slow and noisy. Continue with a tighter SwiftUI invalidation/AX traversal investigation before calling the import UX usable.

### Slice 2: Import UX Hardening

**Files to inspect first:**

- `Sources/TeststripApp/LibraryGridView.swift`
- `Sources/TeststripApp/FolderSelectionPanel.swift`
- `Sources/TeststripApp/ImportFolderPathDraft.swift`
- `Sources/TeststripApp/ActivityView.swift`
- `Sources/TeststripApp/AppModel.swift`
- `Tests/TeststripAppTests/FolderSelectionPanelTests.swift`
- `Tests/TeststripAppTests/ImportFolderPathDraftTests.swift`
- `Tests/TeststripAppTests/AppModelTests.swift`
- `script/verify_import_path.sh`

**Work:**

- [ ] Make import state unambiguous before, during, and after path submission.
- [ ] Disable duplicate import submission while an import is starting or running.
- [x] Surface completed import count and whether preview generation is continuing after catalog/import completion.
- [ ] Surface a clearer current import phase while path submission is scanning and cataloging.
- [ ] Show clear duplicate, empty-folder, failed-folder, and permission/security-scope errors.
- [ ] Add model tests for import state transitions rather than brittle SwiftUI snapshots.
- [x] Extend AX import verifier to catch apparent no-op after submit and sheet-dismissed-with-no-visible-progress states. Current coverage adds a post-submit visible-feedback gate and `feedback_visible_seconds`.
- [ ] Add the imported-grid selection/rating AX probe in Slice 3.
- [ ] Verify with focused tests, full `swift test`, `./script/verify_app_workflows.sh Teststrip`, and manual/AX import smoke.
- [ ] Commit.

**Acceptance:** A user should never wonder whether import started, whether it is still working, or whether preview/indexing is separate from the safe cataloging step.

### Slice 3: Imported Grid Selection And Culling Reliability

**Files to inspect first:**

- `Sources/TeststripApp/LibraryGridView.swift`
- `Sources/TeststripApp/CachedPreviewImage.swift`
- `Sources/TeststripApp/CullingKeyCaptureView.swift`
- `Sources/TeststripApp/InspectorView.swift`
- `Sources/TeststripApp/AppModel.swift`
- `Tests/TeststripAppTests/CullingKeyCaptureTests.swift`
- `Tests/TeststripAppTests/CachedPreviewImageTests.swift`
- `script/verify_grid_activation.sh`
- `script/verify_grid_selection_feedback.sh`
- `script/verify_keyboard_culling.sh`
- `script/capture_app_window.sh`

**Work:**

- [x] Reproduce selection/click behavior with an imported catalog, not only the seeded smoke catalog.
- [x] Add an AX probe that imports several images, clicks the second or third imported thumbnail, verifies selection feedback, then applies a rating and verifies the inspector/catalog state.
- [x] Use CoreGraphics capture to verify the UI is not blank or visually occluded after import.
- [x] Fix overview thumbnails so the grid shows true photo aspect ratios instead of cropping every image into a fixed 3:2 tile. Preserve stable hit targets and metadata overlays while doing this.
- [x] Bring the library filter rail closer to the Studio mockup by making Ask/search visually primary, keeping advanced filters compact, and preserving the Search catalog accessibility contract.
- [x] Pin the inspector/sidebar selected-preview box to a stable X/Y size so it does not expand with the detail column or selected image.
- [x] Bring the loupe/culling surface closer to the mockup with top-level progress, decision counts, and stable flag/rating/label controls.
- [ ] Fix the root cause if click handling, hit testing, focus capture, selection identity, or grid cell accessibility is wrong.
- [ ] Add the least brittle model/UI tests that would have failed for the root cause.
- [ ] Verify all grid/culling scripts and full `swift test`.
- [ ] Commit.

**Acceptance:** Imported photos can be clicked, selected, rated, and inspected reliably through both human interaction and AX automation.

### Slice 4: RAW Decode Capability Matrix And Provider Boundary

**Files to inspect first:**

- `Sources/TeststripCore/Decode/DecodeProvider.swift`
- `Sources/TeststripCore/Decode/DecodeRegistry.swift`
- `Sources/TeststripCore/Decode/ImageIODecodeProvider.swift`
- `Sources/TeststripCore/Preview/PreviewRenderer.swift`
- `Sources/TeststripCore/Ingest/FolderScanner.swift`
- `Tests/TeststripCoreTests/DecodeRegistryTests.swift`
- `Tests/TeststripCoreTests/PreviewRendererTests.swift`

**Work:**

- [ ] Document the actual current ImageIO-supported extension set and what Teststrip claims versus merely attempts.
- [ ] Add provider capability metadata: embedded preview, metadata read, working preview render, full render, and known unsupported.
- [ ] Keep ImageIO as the default provider where it works.
- [ ] Add fixtures or fixture hooks for DNG, CRW, CR2, Fuji RAW, and Sigma/Foveon RAW. If real sample files are not committed, tests should skip with explicit sample-missing messages instead of pretending coverage exists.
- [ ] Add a clean adapter seam for future LibRaw/RawSpeed-style providers without implementing the whole provider now.
- [ ] Make import still catalog unsupported/partial formats when metadata or embedded previews can be read.
- [ ] Verify focused decode/preview tests and full `swift test`.
- [ ] Commit.

**Acceptance:** We know exactly which formats work, which are best-effort, and where a future decoder provider plugs in. The app should not silently overpromise RAW support.

### Slice 5: XMP Conflict And Pending Sync UX

**Files to inspect first:**

- `Sources/TeststripCore/Metadata/MetadataSyncPlanner.swift`
- `Sources/TeststripCore/Metadata/MetadataSyncQueue.swift`
- `Sources/TeststripCore/Metadata/XMPSidecarStore.swift`
- `Sources/TeststripApp/SidebarView.swift`
- `Sources/TeststripApp/InspectorView.swift`
- `Sources/TeststripApp/AppModel.swift`
- `Tests/TeststripCoreTests/MetadataSyncTests.swift`
- `Tests/TeststripAppTests/AppModelTests.swift`

**Work:**

- [ ] Add user-facing conflict detail for selected conflicted assets.
- [ ] Add explicit retry action for pending XMP sync items when a source becomes writable again.
- [ ] Make bulk metadata edits avoid UI stalls while still recording pending sync before worker dispatch.
- [ ] Add tests for sidecar changed externally, catalog changed locally, both changed, and offline/read-only pending sync.
- [ ] Verify full `swift test` and a small manual app flow that edits rating/label/keyword and inspects sidecar output.
- [ ] Commit.

**Acceptance:** Catalog-first metadata feels instant, sidecar writeback is automatic, and pending/conflict states are visible enough that users can trust the non-destructive workflow.

### Slice 6: Evaluation V1 That Photographers Can See

**Files to inspect first:**

- `Sources/TeststripCore/Evaluation/AppleVisionEvaluationProvider.swift`
- `Sources/TeststripCore/Evaluation/LocalImageMetricsEvaluationProvider.swift`
- `Sources/TeststripCore/Evaluation/LocalHTTPModelProvider.swift`
- `Sources/TeststripCore/Evaluation/EvaluationSignal.swift`
- `Sources/TeststripApp/InspectorView.swift`
- `Sources/TeststripApp/SidebarView.swift`
- `Sources/TeststripApp/AppModel.swift`
- `Tests/TeststripCoreTests/EvaluationProviderTests.swift`
- `script/verify_evaluation.sh`

**Work:**

- [ ] Promote evaluation results into user-visible signal groups: technical quality, faces, OCR, objects/content, color/look, and provider provenance.
- [ ] Add People/face grouping data model only after deciding the smallest useful grouping behavior. Do not imply Apple Photos-level identity recognition unless Teststrip actually owns clustering and naming.
- [ ] Add review filters for unevaluated, faces found, OCR found, likely issues, and provider failures.
- [ ] Add cancellation-aware provider execution or worker-level cancellation behavior for slow local HTTP calls.
- [ ] Keep machine labels provisional unless the user explicitly accepts them into keywords/XMP.
- [ ] Verify provider tests, `script/verify_evaluation.sh`, and `TeststripBench local-http-smoke` against a real local endpoint when one is available.
- [ ] Commit.

**Acceptance:** A selected or scoped set can be evaluated locally, signals are visible with provenance, and no provisional machine output contaminates user metadata by default.

### Slice 7: Search, Sets, Clusters, And Work Sessions As One Model

**Files to inspect first:**

- `Sources/TeststripCore/Search/AssetSet.swift`
- `Sources/TeststripCore/Search/SetQuery.swift`
- `Sources/TeststripCore/Work/WorkSession.swift`
- `Sources/TeststripCore/Work/WorkSessionRepository.swift`
- `Sources/TeststripApp/SidebarView.swift`
- `Sources/TeststripApp/LibraryGridView.swift`
- `Sources/TeststripApp/AppModel.swift`
- `Tests/TeststripCoreTests/SearchSetTests.swift`
- `Tests/TeststripCoreTests/WorkSessionTests.swift`

**Work:**

- [ ] Define the minimum user-facing set types for alpha: import batch, manual selection, saved search, frozen snapshot, and work-session-derived set.
- [ ] Add query predicates for rating, color label, pick/reject, keyword, date, folder, source availability, XMP state, and evaluation signal kind.
- [ ] Add sidebar sections for recent/starred work sessions next to saved sets/searches.
- [ ] Make culling operate on the active set, not only the whole library or last import.
- [ ] Add tests that a work session points to input/output/generated sets rather than owning a separate membership system.
- [ ] Verify full `swift test` and one app workflow: import, save a filtered set, start a culling session over it, star the session, relaunch, and recover it from sidebar.
- [ ] Commit.

**Acceptance:** "Photos that are part of this job/work session" is implemented as a queryable set, and photographers can cull arbitrary sets instead of being forced into import-batch workflows.

### Slice 8: Smart Collection Builder And Filter Bar

**Files to inspect first:**

- `Sources/TeststripCore/Search/SetQuery.swift`
- `Sources/TeststripApp/LibraryGridView.swift`
- `Sources/TeststripApp/SidebarView.swift`
- `Sources/TeststripApp/AppModel.swift`
- `Tests/TeststripCoreTests/SearchSetTests.swift`

**Work:**

- [ ] Build a compact advanced filter bar for camera/lens/ISO/date/rating/label/flag/keyword/source/evaluation filters once the underlying predicate set exists.
- [ ] Save filter expressions as smart collections.
- [ ] Support frozen snapshots separately from dynamic saved searches.
- [ ] Add model tests for predicate round-trip and dynamic-vs-frozen behavior.
- [ ] Verify that common indexed searches stay under the intended timing target on seeded 500k/1M catalogs.
- [ ] Commit.

**Acceptance:** Users can create and revisit smart collections without needing an agent/chat interaction.

### Slice 9: Scale And Performance Gates

**Files to inspect first:**

- `Sources/TeststripBench/BenchmarkCommand.swift`
- `Sources/TeststripBench/ImportDeferredBenchmark.swift`
- `Sources/TeststripBench/MetadataWriteBenchmark.swift`
- `Sources/TeststripBench/PreviewRenderBenchmark.swift`
- `Sources/TeststripBench/SmokeCatalogSeeder.swift`
- `Sources/TeststripCore/Catalog/CatalogRepository.swift`
- `Sources/TeststripCore/Preview/PreviewScheduler.swift`
- `docs/architecture/performance.md`

**Work:**

- [ ] Make benchmark commands print machine-readable summaries in addition to human text.
- [ ] Add a repeatable import benchmark for large folders with previews deferred.
- [ ] Add preview render throughput benchmark for cached generated images and a small real-image sample directory.
- [ ] Add metadata/XMP bulk edit benchmark.
- [ ] Add memory and CPU snapshots to app workflow scripts where practical.
- [ ] Set initial red/yellow/green thresholds for alpha only after measuring current local behavior.
- [ ] Update `docs/architecture/performance.md` with measured evidence and caveats.
- [ ] Commit.

**Acceptance:** Future agents cannot accidentally call the app fast without running the same scale checks.

### Slice 10: Dev Packaging, Diagnostics, And Recovery

**Files to inspect first:**

- `script/build_and_run.sh`
- `Sources/TeststripApp/AppCatalog.swift`
- `Sources/TeststripApp/main.swift`
- `Sources/TeststripCore/Worker/WorkerSupervisor.swift`
- `docs/architecture/worker-management.md`

**Work:**

- [ ] Keep dev app bundle signing/helper staging reliable.
- [ ] Add diagnostics export for catalog path, preview cache path, worker path, pending work counts, source status counts, and recent worker failures.
- [ ] Add a reset-only-isolated-test-data helper if current smoke scripts leave confusing state.
- [ ] Add crash/relaunch recovery smoke for queued/running worker-visible work.
- [ ] Decide later whether notarization belongs before private alpha. Do not do production packaging work until Jesse asks.
- [ ] Commit.

**Acceptance:** Jesse can run and test the app repeatedly without needing to babysit hidden app-support state or worker leftovers.

## Verification Commands

Use these as the default confidence ladder:

```bash
swift test
./script/build_and_run.sh --verify-smoke
./script/verify_app_workflows.sh Teststrip
./script/verify_grid_activation.sh Teststrip
./script/verify_grid_selection_feedback.sh Teststrip
./script/verify_keyboard_culling.sh Teststrip
./script/verify_imported_grid_culling.sh Teststrip
./script/verify_evaluation.sh Teststrip
TESTSTRIP_AX_IMPORT_COUNT=600 TESTSTRIP_AX_TIMEOUT_SECONDS=45 ./script/verify_import_path.sh Teststrip
```

For scale checks:

```bash
swift run TeststripBench catalog-baseline
swift run TeststripBench catalog-stress
swift run TeststripBench local-http-smoke <endpoint> <model> <image> [timeout]
```

For visual review:

```bash
./script/capture_app_window.sh Teststrip /tmp/teststrip-window.png
```

## Execution Discipline

- Keep changes narrow and commit each slice independently.
- Prefer model/core tests for behavior and AX/CoreGraphics probes for user-visible macOS behavior.
- Do not write brittle tests that assert whole rendered SwiftUI or shell strings.
- Do not add backward compatibility or migration paths unless Jesse explicitly approves them.
- Do not broaden scope into maps, Lightroom migration, photo editing, watched folders, or iOS while closing the usable alpha gap.
- When a UI bug is reported, reproduce through the running app or AX/CoreGraphics before fixing symptoms.
- When a performance bug is reported, capture counts/timing/CPU before and after the change.
