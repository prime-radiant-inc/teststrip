# Teststrip Usable Alpha Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Teststrip from a working foundation build into a usable macOS alpha for fast, non-destructive photo catalog management, browsing, culling, metadata/XMP sync, preview-based offline work, and local-first agentic evaluation.

**Architecture:** Teststrip is a native macOS app with SwiftUI/AppKit UI surfaces, a SQLite-backed catalog as the operational source of truth, external originals, a persistent preview cache, catalog-first metadata edits, automatic XMP sidecar mirroring for portable fields, and one supervised local worker helper for long-running import, preview, XMP, source, and recognition work. The app must remain responsive when originals live on NAS, removable, cloud-synced, or offline volumes.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, AppKit where needed, SQLite3, ImageIO/CoreGraphics, Vision, JSON-lines worker protocol, shell-first app verification scripts, Accessibility/CoreGraphics UI automation.

---

## Current Snapshot

- Branch: `wip/teststrip-usable-foundation`
- Snapshot commit: current branch HEAD; see the commit ledger below for completed slices.
- Product posture: foundation/dev build moving toward usable alpha, not yet a polished photo app.
- Current slice focused verification: `swift test --filter CompareSurveyPresentationTests/testFocusMetricsIncludeLocalFramingAndAestheticScores` failed first because Compare only surfaced Focus from the new local signal set, then passed after adding framing/aesthetic scores to the Compare quality lane. `swift test --filter CompareSurveyPresentationTests` also passed.
- Last focused unit verification: `swift test --filter PeoplePresentationTests` passed after replacing the People review strip hard-coded status with live queue/scan/empty copy. Earlier focused verification: `swift test --filter 'SearchWorkspacePresentationTests/testGeneratedRefinementsSuggestConcreteRulesWithoutRepeatingActiveFilters|LiveMockupPlaceholderTests/testSearchRefineLedgerTracksGeneratedRefinementsAndSuggestedActions'` passed after adding generated Search refinements, and `swift test --filter 'SearchWorkspacePresentationTests|LiveMockupPlaceholderTests'` passed after refreshing the Search/ledger surface. Earlier focused verification: `swift test --filter PeoplePresentationTests` passed after adding the People Apple Vision scan action, and `swift test --filter 'PeoplePresentationTests|LiveMockupPlaceholderTests/testPeopleLedgerTracksUnnamedFaceReviewEntrypointsWithoutNamedIdentities'` passed after refreshing the People mockup ledger. Earlier focused verification: `swift test --filter 'CatalogDatabaseTests/testDeletesAssetSetWithoutDeletingAssets|AppModelTests/testDeletingSavedAssetSetPersistsRefreshesSidebarAndClearsActiveScope|AppModelTests/testSidebarContextActionsExposeSavedSetRenameAndStarToggle|AppModelTests/testSidebarContextActionsDoNotExposeFreezeForManualSavedSets'` passed after adding saved-set delete lifecycle, and `swift test --filter LiveMockupPlaceholderTests` passed after refreshing the Smart Collections mockup ledger. Earlier focused verification: `swift test --filter LiveMockupPlaceholderTests` passed after refreshing the dead-UI/live-mockup ledger for built cross-page batch selection and Smart Collection rule presets. Earlier focused verification: `swift test --filter 'DecodeRegistryTests|LibraryImportServiceTests/testAddFolderCatalogsRecognizedUnsupportedRawWithoutPreviewWork|LibraryImportServiceTests/testCatalogsMetadataOnlyDecodeProviderAssetWithoutQueuingPreviews|AppModelTests/testBatchSelectionPrunesAssetsOutsideReloadedScope|AppModelTests/testBatchSelectionKeepsMatchingAssetsOutsideReloadedPage|WorkerCommandExecutorTests/testImportFolderCommandCatalogsRecognizedUnsupportedRawWithoutPreviewWork|AppCatalogTests/testDefaultImportServiceCatalogsRecognizedUnsupportedRawWithoutPreviewWork|ImportConfirmationDraftTests/testFolderDraftCountsRecognizedUnsupportedRawFilesByDefault'` passed after adding catalog-only RAW import behavior and fixing filter-scope batch selection pruning. Earlier focused verification: `swift test --filter SmartCollectionBuilderPresentationTests`, `swift test --filter AppModelTests/testApplyingSmartCollectionRulePresetNarrowsCurrentQuery`, and focused batch-selection/metadata save filters passed after adding cross-page batch selection and smart rule presets; `swift test --filter BenchmarkCommandTests`, `bash script/test_import_preview_drain_verifier_metrics.sh`, and `script/verify_import_preview_drain.sh 100 5 10` passed after adding the import-preview-drain verifier; `swift test --filter AppModelTests/testWorkerBackedBatchMetadataRefreshesXmpStateOnceForBatch` passed after batching worker-backed metadata sync refreshes; `swift test --filter 'AppModelTests/testVisibleBatchMetadataAppliesPortableFieldsAndWritesXmpSidecars|AppModelTests/testSelectedBatchMetadataAppliesOnlySelectedAssetsAndWritesXmpSidecars|AppModelTests/testCurrentScopeBatchMetadataAppliesBeyondLoadedPageAndWritesXmpSidecars|AppModelTests/testCurrentScopeBatchMetadataAppliesExplicitSetBeyondLoadedPage|AppModelTests/testWorkerBackedBatchMetadataRefreshesXmpStateOnceForBatch|AppModelTests/testSelectingAssetQueuesWorkerMetadataSyncCheckWhenSupervisorConfigured|AppModelTests/testRatingSelectedAssetQueuesXmpWhenSidecarCannotBeWritten'` passed for nearby batch/XMP behavior. Earlier focused verification: `swift test --filter CopilotPresentationTests` passed after expanding Copilot review triage rows; `bash script/test_preview_render_verifier_metrics.sh` and `script/verify_preview_render.sh 100 5` passed after adding the preview-render verifier. Earlier Duplicate Set verification: `swift test --filter 'AppModelTests/testDuplicatingSavedAssetSetCopiesMembershipAndSelectsCopy|AppModelTests/testFreezingDynamicSavedAssetSetCreatesSelectedSnapshot|AppModelTests/testSidebarContextActionsExposeSavedSetRenameAndStarToggle|AppModelTests/testSidebarContextActionsDoNotExposeFreezeForManualSavedSets'` passed after adding Duplicate Set. Earlier saved-set Freeze Snapshot checks passed: `swift test --filter 'AppModelTests/testFreezingDynamicSavedAssetSetCreatesSelectedSnapshot|AppModelTests/testSidebarContextActionsExposeSavedSetRenameAndStarToggle|AppModelTests/testSidebarContextActionsDoNotExposeFreezeForManualSavedSets'`. Earlier Search related-filter checks passed: `swift test --filter 'SearchWorkspacePresentationTests|LiveMockupPlaceholderTests/testSearchRefineLedgerTracksSuggestedActionsWithoutGeneratedRefinements'`. Earlier saved-set rename checks passed: `swift test --filter 'AppModelTests/testRenamingSavedAssetSetPersistsAndRefreshesSidebar|AppModelTests/testSidebarContextActionsExposeSavedSetRenameAndStarToggle|AppModelTests/testTogglingSavedAssetSetStarredPersistsAndRefreshesSidebar'`. Earlier batch-aware Save Selection checks passed: `swift test --filter 'AppModelTests/testSavingSelectionAsManualSetUsesSelectedBatchInLoadedOrder|AppModelTests/testManualSetSaveAffordancesReflectSelectedBatch|AppModelTests/testSavingSelectedAssetCreatesSelectedManualSet|AppModelTests/testManualSetSaveAffordancesReflectSelectionAndCatalog|AppModelTests/testSavingSelectedAssetAsManualSetRequiresSelection'`. Earlier selected-batch metadata checks passed: `swift test --filter 'AppModelTests/testSelectedBatchMetadataAppliesOnlySelectedAssetsAndWritesXmpSidecars|AppModelTests/testBatchSelectionDoesNotReplacePrimarySelection|LibraryGridChromeTests/testBatchMetadataReviewPresentationSummarizesSelectedBatch|LiveMockupPlaceholderTests/testKeywordingLedgerTracksCurrentScopeBatchMetadataGaps'`. Earlier Timeline scroll checks passed: `swift test --filter 'TimelinePresentationTests/testBuildsMonthAndDayScrubberFromCatalogTimelineDays|TimelinePresentationTests/testTimelineContentScrollPolicy|LiveMockupPlaceholderTests/testTimelineLedgerTracksBuiltYearRibbonAndFocusedScrubberControls'`. Earlier all-catalog batch metadata checks passed: `swift test --filter 'LibraryGridChromeTests/testBatchMetadataReviewPresentation|LiveMockupPlaceholderTests/testKeywordingLedgerTracksCurrentScopeBatchMetadataGaps'`. Earlier Timeline checks passed: `swift test --filter 'TimelinePresentationTests/testBuildsMonthAndDayScrubberFromCatalogTimelineDays|LiveMockupPlaceholderTests/testTimelineLedgerTracksBuiltYearRibbonAndFocusedScrubberControls'`. Earlier current-scope batch metadata checks passed: `swift test --filter 'LiveMockupPlaceholderTests/testKeywordingLedgerTracksCurrentScopeBatchMetadataGaps|LibraryGridChromeTests/testBatchMetadataReviewPresentation|AppModelTests/testCurrentScopeBatchMetadata'`. Earlier advanced Search checks passed: `swift test --filter 'LibrarySearchIntentTests|AppModelTests/testActiveLibraryFilter|AppModelTests/testApplyingLibrarySearchIntentFiltersCatalogResults|AppModelTests/testSavingCurrentLibraryQuery'`. Earlier persisted stack rail checks passed: `swift test --filter 'AppModelTests/testCullingShortcutMovesBetweenPersistedStackSets|AppModelTests/testSelectedCullingStackScopeUsesPersistedStackSetMembership|CullingStackRailPresentationTests'`. Earlier persisted stack-cull checks passed: `swift test --filter 'AppModelTests/testCompare|AppModelTests/testBeginningStackCullingFromLatestImport|AppModelTests/testCullingShortcut|LiveMockupPlaceholderTests/testCompareLedgerTracksStackCullActionsAndRemainingSimilarityGap'`. Earlier inspector checks passed: `swift test --filter InspectorViewTests/testAssetIdentitySplitsFilenameExtensionAndStatus` and `bash -n script/verify_import_path.sh script/submit_import_path.sh script/verify_keyboard_culling.sh script/verify_grid_activation.sh script/verify_grid_selection_feedback.sh script/verify_evaluation.sh script/verify_imported_grid_culling.sh` after strengthening selected-inspector rating accessibility and AX walker identity. Earlier review/Copilot checks passed: `swift test --filter 'AppModelTests/testReviewQueueSignalFiltersUseUserFacingQueueNames|AppModelTests/testActiveLibraryFilterRowsBridgeConcreteFiltersToExistingTargets|AppModelTests/testLoadExposesReviewQueuesAndSelectingQueueAppliesFilter|CopilotPresentationTests'`. Earlier import-plan checks passed: `swift test --filter 'ImportFolderPathDraftTests|ImportConfirmationDraftTests|PlaceholderTests'`. Earlier People checks passed: `swift test --filter PeoplePresentationTests`, `swift test --filter LiveMockupPlaceholderTests/testPeopleSidebarRowIsMarkedAsLiveMockupPlaceholder`, and `swift test --filter 'PeoplePresentationTests|LiveMockupPlaceholderTests/testPeopleSidebarRowIsMarkedAsLiveMockupPlaceholder|AppModelTests/testLoadExposesReviewQueuesAndSelectingQueueAppliesFilter'`. Earlier top-bar checks passed: `swift test --filter 'LibraryTopBarPresentationTests|PlaceholderTests'`. Earlier Search checks passed: `swift test --filter SearchWorkspacePresentationTests`, `swift test --filter 'SearchWorkspacePresentationTests|LibrarySearchIntentTests|PlaceholderTests'`, and `swift test --filter 'SearchWorkspacePresentationTests|PlaceholderTests|AppModelTests/testLoadExposesReviewQueuesAndSelectingQueueAppliesFilter|AppModelTests/testReviewQueueCountsRefreshAfterMetadataChanges'`. Earlier culling recommendation checks passed: `swift test --filter CullingStackRailPresentationTests` and `swift test --filter 'CullingStackRailPresentationTests|AppModelTests/testCullingShortcut|AppModelTests/testBeginningStackCullingFromLatestImport'`. Earlier visible-batch metadata and Copilot primary-action checks passed: `swift test --filter 'AppModelTests/testVisibleBatchMetadataAppliesPortableFieldsAndWritesXmpSidecars|LibraryGridChromeTests/testBatchMetadata|PlaceholderTests/testKeywordingLedgerTracksVisibleBatchMetadataWithoutAllScopeEditing|CopilotPresentationTests'`. Earlier sandbox-aware import runtime policy checks also passed: `swift test --filter 'AppCatalogTests|AppModelTests/testBeginImportFolderWithWorkerImportsDisabledRunsLocalImportAndGeneratesPreview'`, `bash -n script/build_and_run.sh`, `plutil -lint config/macos/Teststrip.entitlements config/macos/TeststripWorker.entitlements`, and `script/build_and_run.sh --build-sandboxed` plus `codesign -d --entitlements :-` inspection without launching the UI. Earlier running-import work-session, work-session sidebar context actions, metadata verifier, People, worker skipped-count/idle-stop, import resilience, worker/source, grid layout/chrome, XMP conflict/reconnect, and catalog-scale verifier focused tests passed across the preceding slices.
- Last broad unit verification: `swift test` passed after adding framing/aesthetic Compare metrics, with 868 tests, 1 skipped, and 0 failures. Earlier `swift test` passed after adding local framing/aesthetic evaluation signals, with 867 tests, 1 skipped, and 0 failures. Earlier `swift test` passed after adding the isolated test-data reset helper, with 866 tests, 1 skipped, and 0 failures. Earlier `./script/verify_headless_workflows.sh` passed after adding app workflow resource snapshots, including full `swift test` with 866 tests, 1 skipped, and 0 failures plus the non-focus-stealing headless verifier scripts.
- Current slice app workflow verification: No foreground app workflow run was performed for framing/aesthetic Compare metrics because this was a presentation-model change covered by focused tests and SwiftUI compilation; Jesse asked to minimize focus-stealing UI automation while actively using the machine.
- Last app workflow verification: No app workflow run was performed for the People review strip status fix because focused presentation tests plus SwiftUI compilation cover the changed behavior and Jesse asked to minimize focus-stealing automation. Earlier app workflow verification: No app workflow run was performed for generated Search refinements because focused presentation/ledger tests plus SwiftUI compilation cover the changed behavior and Jesse asked to minimize focus-stealing automation. Earlier app workflow verification: No app workflow run was performed for the People scan action because focused presentation/ledger tests plus SwiftUI compilation cover the changed behavior and Jesse asked to minimize focus-stealing automation. Earlier app workflow verification: No app workflow run was performed for the saved-set delete lifecycle or Smart Collections ledger refresh because focused model/repository/ledger tests plus SwiftUI compilation cover the changed behavior and Jesse asked to minimize focus-stealing automation. Earlier app workflow verification: No app workflow run was performed for the live-mockup ledger refresh because it is code-level tracking and Jesse asked to minimize focus-stealing automation. Earlier no app workflow run was performed for the catalog-only RAW import and batch-selection scope-pruning slice because focused model/core/worker tests cover the changed behavior and Jesse asked to minimize focus-stealing automation. Earlier no app workflow run was performed for the cross-page batch selection and smart rule preset slice because focused model/presentation tests cover the changed behavior and Jesse asked to minimize focus-stealing automation. Earlier no app workflow run was performed for the import-preview-drain verifier slice because it is covered by non-UI benchmark/script tests and Jesse asked to minimize focus-stealing automation. Earlier no extra app workflow run was performed for the bulk metadata sync queue refresh slice because it changes model/worker behavior and Jesse asked to minimize focus-stealing automation; focused model tests and full `swift test` cover the changed behavior. Earlier app workflow verification: No extra app workflow run was performed for the Copilot review-triage or preview-render verifier slices to minimize focus stealing; focused presentation tests, verifier scripts, and full `swift test` cover the changed behavior. Earlier Duplicate Set app workflow verification: No extra app workflow run was performed for Duplicate Set to minimize focus stealing; focused model tests cover membership-preserving duplication, selected-copy reload, starred placement, context-action ordering, and SwiftUI compilation covered the shared duplicate/freeze sheet wiring. Earlier no extra app workflow run was performed for dynamic saved-set Freeze Snapshot to minimize focus stealing; focused model tests cover snapshot membership persistence, count/sidebar refresh, dynamic-only context action exposure, stability after source metadata changes, and SwiftUI compilation covered the sheet wiring. Earlier no extra app workflow run was performed for deterministic Search related filters to minimize focus stealing; focused presentation and ledger tests cover ordering, zero-count exclusion, active-filter exclusion, actionable targets, and honest placeholder copy. Earlier no extra app workflow run was performed for saved-set rename to minimize focus stealing; focused model tests cover persistence, sidebar refresh, active filter copy, and context action ordering, while SwiftUI compilation covered the rename sheet wiring. Earlier no extra app workflow run was performed for batch-aware Save Selection to minimize focus stealing; focused model tests cover loaded-order batch membership, affordance enablement, naming, and single-photo fallback. Earlier no extra app workflow run was performed for selected-batch metadata to minimize focus stealing; focused model/presentation tests and read-only review covered command-selected metadata writes and primary-selection preservation. Earlier no extra app workflow run was performed for the Timeline scroll-position sync to minimize focus stealing; focused presentation and policy tests cover the scroll targets and SwiftUI wiring. Earlier no extra app workflow run was performed for the all-catalog confirmation popover to minimize focus stealing; focused presentation tests cover the popover state. `./script/build_and_run.sh --verify-smoke` launched an isolated smoke catalog after the focused Timeline scrubber UI change. Attempts to switch the smoke app from Grid to Timeline through AppleScript and one coordinate click did not change the visible route, so `/tmp/teststrip-timeline-focused-scrubber-smoke.png` and `/tmp/teststrip-timeline-focused-scrubber-smoke-2.png` captured normal nonblank Grid windows rather than the Timeline route. The smoke app was stopped; Timeline behavior is covered by focused presentation tests in this slice. Earlier `./script/build_and_run.sh --verify-smoke` launched an isolated smoke catalog after the current-scope batch metadata UI change, `./script/capture_app_window.sh Teststrip /tmp/teststrip-current-scope-batch-smoke.png` captured a normal nonblank Library window, and the smoke app was stopped. Earlier `./script/build_and_run.sh --verify-smoke && TESTSTRIP_AX_IMPORTED_GRID_COUNT=4 TESTSTRIP_AX_IMPORTED_GRID_TARGET_INDEX=2 TESTSTRIP_AX_TIMEOUT_SECONDS=20 ./script/verify_imported_grid_culling.sh Teststrip` remains blocked in this desktop session: the app launches and CoreGraphics can capture a normal Library window, but Arc stays frontmost and macOS refuses programmatic Teststrip activation, so Accessibility exposes only the application/menu proxy and the verifier cannot find `Import Path`. The AX walker also had a real bug, now fixed in `f24f281`: `CFHash(AXUIElement)` can collide for the app root and SwiftUI window proxy, so verifier walkers now use `ObjectIdentifier`. Earlier `./script/build_and_run.sh --verify-smoke && ./script/capture_app_window.sh Teststrip /tmp/teststrip-review-copilot-polish-smoke.png` launched an isolated smoke catalog and captured a normal Library window after the review/Copilot polish slice. The capture shows the review queue sidebar; Copilot row status behavior is covered by focused presentation tests to avoid extra focus-stealing UI automation. Earlier `./script/build_and_run.sh --verify-smoke && ./script/capture_app_window.sh Teststrip /tmp/teststrip-import-plan-smoke.png` launched an isolated smoke catalog and captured a normal Library window after the import-plan UI change. The capture did not open the import confirmation sheet; the staged import-plan contract is covered by focused presentation tests. Earlier `./script/build_and_run.sh --verify-smoke && ./script/capture_app_window.sh Teststrip /tmp/teststrip-people-handoff-final-smoke.png` launched an isolated smoke catalog and captured a normal Library window with the People sidebar detail changed to `Face review`. Computer Use/AppKit activation could not reliably bring the People route forward because Arc stayed frontmost, so that smoke verified launch/sidebar copy rather than an interactive People-route click. Earlier `./script/build_and_run.sh --verify-smoke` launched an isolated smoke catalog after the inspector XMP merge action, and `./script/capture_app_window.sh Teststrip /tmp/teststrip-inspector-conflict-action-smoke.png` captured a normal Library window. That smoke did not show an active XMP conflict; the conflict action ordering and model merge path are covered by focused tests. Additional UI automation was intentionally avoided for the footer-density slice to minimize focus stealing while Jesse is using the machine. Earlier no app launch was run for the diagnostics slice to minimize focus stealing; `./script/build_and_run.sh --verify-smoke` launched an isolated smoke catalog after the Activity row-control change, and `./script/capture_app_window.sh Teststrip /tmp/teststrip-worker-control-smoke.png` captured a normal Library window with Activity idle state visible. Earlier `./script/build_and_run.sh --sample-photos` plus one Computer Use switch to loupe verified the `TESTSTRIP READS` culling verdict pill renders without truncating its primary copy. The previous Computer Use pass opened the Needs Keywords review queue and verified the Smart Collection builder popover showed the proposed name, one active rule, 12 matches, suggestion chips, Starred toggle, and Create/Cancel controls. Before that, Computer Use switch to Compare verified the corrected N-up survey grid: selected primary first, alternates visible, Pick/Reject/Loupe actions present, and no blank side column. Earlier repeated `script/build_and_run.sh --verify-smoke` launches plus 600-image AX import probes completed, but the large-import UX blocker remains open. The best intermediate run after coalescing worker-progress reloads showed feedback around 14.9s and target visibility around 34.1s; the latest full-slice run showed feedback around 19.7s, target visibility around 48.9s, and preview drain still incomplete after the verifier's sample window. A submit-only Import Path probe measured the target asset reaching the catalog around 0.12s after submit and import work finishing around 0.53s after submit, which means current slowness is mostly UI/AX visibility and preview-drain behavior rather than raw catalog import.

### Recent Completed Slices

- `688411a`: surfaced local framing and aesthetics score signals in Survey Compare's quality lane, keeping the copy neutral and avoiding best-shot claims while making the new local evaluation output useful during comparison.
- `93e5240`: expanded `local-image-metrics` to emit provisional framing and aesthetics scores from cached-preview composition, focus, exposure, and color metrics, giving local-first evaluation broader visible signal coverage without requiring LM Studio/Ollama.
- `343e4d5`: added `script/reset_isolated_test_data.sh`, a dry-run-by-default cleanup helper for stale isolated `teststrip-app-support.*` smoke catalogs that only deletes marked Teststrip test roots and skips running app-support directories.
- `440dd4d`: strengthened the metadata-write benchmark and verifier so XMP confidence includes parsed sidecar metadata matching the catalog, not just file counts and sync fingerprints.
- `c2fde6f`: made source bookmark repair rows actionable from the Sources sidebar by carrying the source-root path into a shared reconnect sheet.
- `995d693`: surfaced stale or failed source bookmark restore as a warning row in the Sources sidebar.
- `712ebb6`: refreshed stored security-scoped bookmark data when reconnecting a source root to a mounted location.
- `d05fb88`: exposed source-root bookmark repair state in diagnostics after stale or failed security-scoped bookmark restoration.
- `c0f8978`: added headless workflow verification for worker recovery, including non-focus-stealing import/preview/source/XMP checks.
- `ea8cfea`: made the local-HTTP model smoke report vector signal count and whether a visual-similarity vector was returned, giving provider smoke runs a concrete similarity-output gate.
- `9711768`: added explicit visual-similarity evaluation signals, grouped stacks from persisted visual vectors when present, wired compare/latest-import culling to those stacks, and kept threshold calibration honest as remaining work.
- `859998c`: added a local preview focus signal to `local-image-metrics`, using a bounded edge-detail heuristic with honest provenance so culling/search can use focus signals without a remote model.
- `8e24a81`: refreshed the top chrome live-mockup ledger after replacing stale catalog chrome copy with the real catalog identity.
- `66a1066`: replaced hard-coded `Master Catalog` top chrome with the catalog root display name and test coverage for the catalog identity presentation.
- `12b5c04`: defined functionality-first alpha gates, explicitly keeping the ignored real-photo corpus out of git and shifting near-term work away from latency tuning unless a feature gate is unusable.
- `14d77e1`: expanded Survey Compare from a four-frame adaptive set to up to eight visible contenders in a four-column 4x2 survey layout, updated group/evaluation scope tests, and refreshed the compare live-mockup ledger without claiming unbuilt similarity ranking.
- `1e51f5d`: made persisted stack culling decisions refresh the owning culling work session progress from decided catalog flags and mark the session completed once every persisted stack asset has a decision.
- `6994c9e`: changed the import-complete keyword action from immediate top-keyword apply into a latest-import review workflow that opens the imported set and visible-scope batch metadata review before any catalog/XMP write.
- `03607ed`: made Smart Collection suggestion rows contextual from real review queue counts, hiding empty or already-active suggestions while still routing through concrete preset sequences.
- `2ba3ba9`: replaced static Smart Collection suggestion text with actionable suggestion rows that apply concrete preset sequences through the existing Add Rule path.
- `7b595ee`: preserved selected dynamic Smart Collection rules when applying Add Rule presets, while keeping manual/snapshot saved sets scoped back to catalog-wide preset behavior.
- `1cc6ab5`: replaced the People review strip hard-coded `0 matched` status with live queue/scan/empty-state copy from the People presentation.
- `420b9ad`: added deterministic generated Search refinements from review queue counts, skipping already-active filters and applying suggestions through the existing Smart Collection rule preset path so Search narrows the current result set.
- `2fb5c5d`: exposed a People-surface Apple Vision scan action for visible cached previews, reusing the existing worker-backed local evaluation path while keeping named identities and clustering explicitly unbuilt.
- `4b097f3`: refreshed the Smart Collections live-mockup ledger so saved-set delete confirmation is recorded as built while freeform rule editing and generated suggestions remain open.
- `88d25bb`: added saved-set deletion from the sidebar with destructive confirmation, repository-only set removal that leaves photos/originals/metadata/XMP untouched, active-scope cleanup, and saved/starred sidebar refresh.
- `7785bc9`: refreshed the code-level live-mockup/dead-UI ledger so Smart Collections now records built Add Rule presets, keywording records command/shift page-spanning batch metadata, and the remaining gaps are freeform rule editing, generated suggestions, and freeform bulk keyword review.
- `f56aec8`: separated decode routing from catalogability so recognized unsupported RAW families such as Sigma/Foveon X3F are discovered and cataloged without preview jobs, kept metadata-only providers out of doomed preview queues, and pruned selected-batch IDs on filter scope changes while preserving in-scope cross-page selections.
- `9b823a7`: added ordered cross-page batch selection with shift-click range selection, preserving visible/catalog order for manual sets and selected-batch metadata, and made the Smart Collection builder's Add Rule affordance apply concrete filter presets through the existing catalog query path.
- `2b01a60`: added an import-preview-drain benchmark and verifier that imports generated JPEG sources with previews deferred, drains queued preview work through the import service recovery path, and checks import/drain timing plus zero remaining pending previews.
- `b7063db`: batched visible/selected/current-scope metadata edits so worker-backed XMP sync records pending rows before enqueue, queues sync work in one supervisor batch, and avoids per-asset metadata/sidebar refresh churn.
- `73af51d`: expanded Copilot review triage rows to cover Needs Keywords, Needs Evaluation, Faces Found, OCR Found, Likely Issues, and Provider Failures using existing review queues, with zero-count status copy and existing primary-action priority preserved.
- `ecf97fa`: added a repeatable preview-render verifier script with alpha thresholds for generated-preview correctness and timing, plus shell metric tests and performance-harness documentation.
- `c3b34e7`: added Duplicate Set from the sidebar for saved sets, preserving membership, selecting the copy, and reusing the name/starred sheet shared with Freeze Snapshot.
- `37edfd5`: added a dynamic saved-set Freeze Snapshot context action with a name/starred sheet, static snapshot persistence, sidebar/count refresh, and immediate snapshot selection.
- `7b079fb`: added deterministic Search related filters from nonzero review queues, excluding active filters and keeping generated refinements explicitly unbuilt.
- `895c1be`: added saved-set rename from the sidebar context menu with catalog persistence, sidebar refresh, and active-scope copy updates.
- `4ef17ad`: made Save Selection honor command-selected loaded assets in loaded grid order, while preserving the single-photo fallback and updating the toolbar help copy.
- `8140466`: added command-selected loaded-asset batches, selected-batch metadata apply through catalog/XMP writeback, selected-batch grid chrome, and footer clear/count affordances while preserving primary selection.
- `2a7f944`: centered focused Timeline scrubber chips and main month/day sections on route load and focus changes, backed by focused target IDs and content-scroll policy tests.
- `a82cd50`: added an explicit confirmation toggle before Current Scope batch metadata can apply to the whole catalog, while leaving narrowed search/filter/set scopes one-step.
- `cc529b2`: added focused day state and a compact focus label to the Timeline month/day scrubber, rendered a highlighted focused day chip, and updated the Timeline ledger to leave only scroll-position syncing pending.
- `ec06ded`: added current-scope batch metadata for active search/filter scopes and explicit sets beyond the loaded thumbnail page, exposed a Visible/Current Scope picker in the batch metadata popover, and refreshed the live-mockup ledger for remaining multi-select/all-catalog-confirmation gaps.
- `f8930e6`: expanded Ask/search field parsing to folder/path, color label, ISO, captured date ranges and single-day date filters, source availability, evaluation signal kind, and XMP pending/conflict state, with strict invalid-date handling.
- `cf928c0`: made the culling stack rail consume explicit persisted work-stack scope and evaluation signals instead of relying only on loaded-scope capture-time grouping.
- `a5b2f39`: made latest-import stack culling persist detected time-adjacent stacks as hidden work-stack asset sets, records those stack sets as the culling session input, lets stack accept/navigation use persisted membership, and marks active persisted stack sets as candidate stacks in Compare.
- `f24f281`: hardened selected-inspector rating accessibility, made keyboard-culling verification require visible inspector rating feedback before catalog persistence, and fixed AX verifier walkers to use `ObjectIdentifier` instead of `CFHash`.
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
- `11143b3`: added code-level `LiveMockupPlaceholder` markers for scaffolded live-mockup UI, currently tagging the People sidebar placeholder and the agentic-search promise in the search box.
- `b12cccf`: added a selectable People live-mockup route from the sidebar and toolbar, plus a placeholder registry covering People navigation, People face actions, agentic search, and empty work history.
- `369b619`: made overview grid cells use cataloged technical dimensions for true photo aspect ratios, while falling back to the old 3:2 frame for missing or invalid dimensions.
- `fd56661`: made the shared import progress banner appear as soon as import work is active, including before any assets are visible in the grid.
- `b6c7149`: added focused tests proving folder/card import entrypoints do not enqueue duplicate work while an import is already running.
- `a1e1144`: added source availability presentation for offline, missing, moved, and stale originals on grid thumbnails and the culling loupe overlay, without changing catalog/preview source-access rules.
- `09f8a6e`: added a compact import-complete summary backed by the completed import work session and output set, with Open and Cull actions plus a live-mockup placeholder marker for the richer designer payoff surface.
- `528f54b`: expanded code-level live-mockup placeholder tracking for search refine, smart collections, import payoff, culling assist, culling filmstrip, stack cull, and survey compare, and attached markers to visible fallback controls where they exist.
- `195d2ba`: added Search as a selectable live-mockup route from the sidebar and toolbar, preserving existing query/filter state and showing a search summary band plus the existing result grid.
- `09eab92`: reshaped Compare into a survey-style live mockup with a primary frame, alternates, frame/recommendation header, real Pick/Reject/Loupe actions, and presentation tests while preserving existing compare preview behavior.
- `c95ae1f`: corrected the Compare Survey visual layout from a squeezed split pane to an adaptive N-up grid with the selected primary first, backed by the ordered presentation contract and verified with sample photos through Computer Use.
- `a6a7d88`: replaced the compact saved-search popover with a Smart Collection builder live mockup that shows current filter rules, filtered match count, suggestion chips, starred state, and the existing dynamic query save action.
- `b5dd2df`: replaced the static culling Assist placeholder with a selected-frame `TESTSTRIP READS` verdict pill backed by persisted evaluation signals and tested signal prioritization.
- `d0d6800`: clarified active import progress with visible phase labels and counts for starting, scanning, cataloging, copying, and preview-building states across the import banner, empty-catalog import state, and footer.
- `1c9d386`: stopped direct grid clicks from recentering the selected thumbnail while preserving auto-scroll for programmatic selection from import, keyboard navigation, filters, and culling advance.
- `4973f32`: expanded the Smart Collection builder from a compact popover into a split live mockup with parsed rule rows, Teststrip suggestions, and a loaded-page thumbnail preview while preserving dynamic saved-search creation.
- `00d07c2`: made sidebar rows richer and closer to the Studio mockup with structured details, counts, tones, and compact custom row rendering for library, source, sync, AI, saved set, and work rows.
- `ff22c48`: added a rapid-cull filmstrip beneath the loupe surface with fixed-size fit thumbnails, selected-frame context, rating/flag badges, and centered-window presentation tests.
- `f116ddc`: added an in-content Studio-style top chrome with catalog identity, breadcrumbs, active-filter count, Ask/search, compact view switching, primary Import action, and a top-chrome live-mockup marker.
- `98bf87b`: added metadata-backed decision badges to Survey Compare tiles and disabled group-action affordances that stay honest until real stack membership exists.
- `d3d5b6d`: refined the inspector selected-asset header with filename stem, extension badge, captured date when available, rating, and source availability while keeping full filename accessibility.
- `b96766d`: added real catalog-backed counts for the Picks, Rejects, 5 Stars, and Needs Keywords review queues, refreshing them after metadata edits, XMP sidecar conflict resolution, and import completion.
- `7a8f236`: added real count badges for Starred and Saved Sets sidebar rows across dynamic, manual, and snapshot memberships, including refresh after metadata edits and import completion.
- `f40234f`: added a catalog-backed Needs Evaluation review queue for assets without persisted evaluation signals, plus sidebar count refresh after worker evaluation completion.
- `23095a6`: grouped selected-photo evaluation signals in the inspector into technical quality, faces, text, objects/content, and color/look sections with confidence and provider/model provenance.
- `758dd51`: fixed culling progress counts to cover the active catalog query or explicit saved set instead of only the loaded thumbnail window.
- `288f66a`: made preview generation classify offline or missing originals as source availability changes instead of burning preview retry attempts, and refresh the loaded asset/source sidebar when the worker reports that state.
- `6ce902b`: added a code-level designer-surface ledger covering mockup ids 1a through 5f with shipped/partial/live-mockup/deferred status, tightened stale placeholder descriptions, and marked the top-bar Ask/search field as agentic-search placeholder UI.
- `e27eddf`: fixed preview recovery after unavailable-original failures so failed in-memory preview work no longer blocks requeueing after source recovery, source-filtered views reload after preview availability changes, and the worker path no longer overclaims moved-file detection.
- `51bd8e6`: aligned the preview completion test with real worker side effects before asserting completed preview work state.
- `ec0a185`: replaced fake People identities/counts with real face-signal and face-quality coverage from catalog evaluation summaries while keeping clustering and naming actions disabled and marked as live-mockup placeholders.
- `3eb7465`: expanded the import-complete banner into a partial payoff panel with real imported count, preview status, Open/Cull actions, adaptive layout, and disabled/annotated stack/face/keyword follow-ups.
- `b469b7c`: added selected-asset keyword suggestions from persisted object-label evaluation signals and let users accept a suggestion through the existing catalog/XMP keyword writeback path.
- `cd11dc5` / `0404ef2`: added focus-aware Survey Compare with per-contender persisted evaluation signals, cached-preview-scoped compare evaluation, and clearer confidence-based signal selection naming.
- `7e2b3d3`: added the first decode capability matrix and provider boundary so ImageIO can declare working still formats and best-effort RAW families without attempting a decode.
- `9a86a87`: corrected Sigma/Foveon X3F from ImageIO best-effort to explicitly unsupported until a future non-ImageIO RAW provider exists.
- `dfd7716`: added selected-photo XMP pending/conflict detail in the inspector and an explicit retry path for pending sidecar writes through direct catalog writeback or the managed worker.
- `2cdd1a9`: made Survey Compare's primary recommendation actionable for the current compare set, marking the primary Pick and visible alternates Reject without claiming real stack detection.
- `306c8d8`: added a bounded import source summary with supported-photo count, counted bytes, capped `N+` display, and routed typed Import Path through the same confirmation sheet.
- `bfe1602`: added deterministic Ask/search parsing for crisp photographer terms, mapping picks/rejects, star ratings, needs-keywords/evaluation, and camera/lens/keyword prefixes into structured catalog predicates while preserving plain text fallback.
- `bb3ba81`: added a catalog-backed Timeline route with capture-day counts, sidebar/top-mode navigation, day drill-down through existing date predicates, and visible batch keyword suggestions/apply from object-label signals through catalog/XMP writeback.
- `b47e57a`: made every TeststripBench command emit a parseable `benchmark-summary` JSON line with numeric metrics and measured step durations while keeping the existing human-readable output.
- `5989a8e`: added a 100k synthetic catalog guard proving Timeline day drill-down keeps AppModel's loaded asset window bounded and constrained to the selected capture day.
- `3ec8a1a`: made Activity row cancel buttons target individual background work items, preserving queued/running unrelated work and using the existing worker-supervisor restart path for dispatched cancellations.
- `68566b7`: routed Compare footer actions through a testable presentation model and marked the deferred Keep all / Choose manually controls with live-mockup placeholders.
- `b9d4513`: added frozen snapshot set creation from the current asset scope, capturing all matching IDs beyond the loaded thumbnail page and exposing it beside dynamic smart-collection saves.
- `91ffb15`: exposed XMP Pending and XMP Conflicts in the compact filter bar using the existing metadata-sync query/chip path.
- `d197930`: added a structured diagnostics snapshot and `Support > Copy Diagnostics` report covering catalog/preview paths, worker configuration/enabled state, XMP counts, background queue counts, source status, source roots, source-root security bookmark repair needs, and recent failures.
- `5a89ce1`: added catalog-backed Review queues for Faces Found, OCR Found, and Likely Issues, with sidebar counts, navigation, and active-filter chips.
- `7c33f5e`: added durable per-asset/per-provider evaluation failure tracking, automatic clear-on-success for the same provider, worker failure recording, and a Provider Failures review queue.
- `d8084c2`: bounded import confirmation source-summary scans by total entries visited as well as supported-photo count, so huge unsupported/NAS/cloud folders do not block the confirmation UI before import starts.
- `9596ac3`: added explicit regression coverage that machine object-label evaluation signals remain provisional suggestions until the user accepts them into catalog metadata/XMP.
- `82d3a8f`: tightened running-evaluation cancellation coverage to the local HTTP model provider, documenting that cancelling a slow provider call uses worker-level `cancelAll`, marks the evaluation cancelled, and starts queued work.
- `9b3e066`: expanded catalog-scale benchmark coverage to representative indexed filters and added catalog-first XMP conflict merge resolution for filling missing catalog fields from sidecar metadata.
- `6aed16b`: added `script/verify_catalog_scale.sh`, a repeatable 100k catalog scale verifier with machine-readable metrics and threshold checks for page/filter queries.
- `d819fd0`: exposed the lower-risk `Merge Missing` XMP conflict action in the inspector before destructive `Use Catalog` and `Use XMP` choices.
- `8b4fcfc`: preserved existing unambiguous Adobe-style `frame.xmp` sidecar paths when reconnecting remounted source roots.
- `2c1baac`: moved grid density and thumbnail-size controls into the Library footer and made grid spacing derive from the same density presentation, matching the Studio mockup footer while preserving true-aspect thumbnails.
- `e7813c7`: preflighted preview generation for stale originals so changed source bytes do not silently refresh cached previews or clear pending preview work.
- `9e2c7fb`: made add-in-place folder imports tolerate a scanned source file disappearing before cataloging, report skipped source files in `LibraryImportResult`, and surface skipped-file counts in AppModel import completion copy while leaving card-copy conflicts fail-fast.
- `881d892`: carried skipped source-file counts through worker-backed imports and exposed idle worker process state plus a stop-idle-worker control in Activity/diagnostics.
- `905a59a`: pulled the People mockup closer to live SwiftUI with an unnamed face-review strip, catalog-backed face review cards, and an explicit named-people empty state while keeping naming/merge/dismiss disabled.
- `ee204a9`: added a repeatable metadata-write verifier script that checks catalog updates, XMP sidecars, synced fingerprints, zero pending sync, and unchanged originals through the benchmark summary contract.
- `2e50524`: exposed model-backed sidebar context actions so recent/starred work sessions can be starred or unstarred from the same sidebar menu path as saved sets.
- `34cf22a`: records non-worker imports in Recent Work as soon as they start, persisting the running work session so the sidebar/history no longer waits for completion or cancellation.
- `388ddec`: added a sandbox-aware runtime policy that requires security-scoped import access in sandboxed runs, keeps imports and initial preview generation in-process when those grants are required, and added explicit sandboxed dev-bundle signing modes with entitlement inspection.
- `a017553`: made the import payoff's Cull stacks action real by counting time-adjacent stacks in the imported set, disabling the action when no stack exists, and starting culling with the first detected stack selected.
- `5caa0c5`: fixed import stack culling for large imported sets by finding the first time-adjacent stack across the full explicit import output set and loading the page that starts at that stack before selection.
- `bc5f21d`: added reusable app/worker CPU and RSS metric snapshots to the app workflow verifier and Import Path metrics so foreground workflow runs produce practical process-resource evidence.
- `33142f2`: exposed Compact, Comfortable, and Large as explicit Library footer density controls so the Large thumbnail state no longer appears selected as Comfortable.
- `1c07165`: opens the import work-output set when a completed import would otherwise remain hidden behind an active filter or saved scope, so a successful import cannot leave the grid looking stale or empty.
- `a15f4c2`: made typed-folder import review visibly stateful by showing a reviewing spinner/status, disabling duplicate submission during preflight, moving confirmation draft construction off the immediate button path, and ignoring stale completions when the sheet is dismissed.
- `3bda023`: added a non-focus-stealing local HTTP model smoke verifier that starts a tiny OpenAI-compatible localhost stub, runs the real `TeststripBench local-http-smoke` command, asserts model signals plus a visual-similarity vector, and wires that gate into `script/verify_headless_workflows.sh`.
- `a193905`: added a visible-batch metadata review popover that applies keywords, caption, creator, and copyright to loaded visible assets through catalog-first/XMP writeback while keeping all-scope batch review marked as unbuilt.
- `5e3d768`: added Copilot read-scope chips and a primary action button that routes to existing XMP/review queues or runs visible local evaluation without claiming autonomous planning.
- `04d6929`: added an actionable culling stack recommendation when persisted focus/quality signals identify a best frame, while leaving top-N stack ranking disabled until real ranking/decision persistence exists.
- `87fb1c5`: added Search refine-rail suggested actions for existing save dynamic set, freeze snapshot, and non-empty review-queue workflows, with shared review-queue presentation metadata.
- `d0f1d92`: annotated partial top-bar routes with their existing live-mockup placeholders so Search, Copilot, Timeline, Compare, and People remain trackable from code.
- `0f56399`: made People face-review cards route into existing Faces Found and face-quality review targets, and renamed the sidebar detail to `Face review` to avoid implying finished identity clustering.
- Current slice: added provider-signal Search refinements so object-label, OCR, and people evaluation summaries can propose concrete Search rules while skipping active filters.
- `eab16ba`: added staged import-plan rows for imported-set culling, likely stacks, keyword review, and face review, plus a code-level live-mockup marker for the empty Folders sidebar row.
- `ea60cd8`: kept Faces Found/OCR Found active filters and saved-search names in review-language, and made Copilot zero-count review rows render as explanatory status rows instead of dead disabled buttons.

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
- Add-in-place folder imports can skip and report source files that disappear or become unreadable after scan, so one flaky NAS/cloud/removable file no longer fails the whole import. Card/camera copy conflicts remain fail-fast.
- Worker-backed add-in-place imports preserve skipped source-file counts through the worker result/protocol/event path, so direct and helper-backed completion copy stay consistent.
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
- Decode providers separately declare whether they can decode a file and whether the file type is catalogable, so Teststrip can keep long-tail archive files visible before a renderer exists.
- Decode providers now expose `DecodeCapability` metadata so Teststrip can distinguish working still formats, best-effort ImageIO RAW candidates, and unsupported formats without attempting a decode.
- Current RAW capability documentation lives in `docs/architecture/raw-decode-capability.md`; DNG, CRW, CR2, CR3, NEF, ARW, RAF, RWL, RW2, SRW, and ORF are best-effort ImageIO candidates, while Sigma/Foveon X3F is recognized/catalogable but unsupported for metadata and preview rendering until a dedicated provider exists.
- Default app, worker, import-confirmation, and sample-seeding import paths use catalogable extensions, so recognized unsupported RAW files can create catalog rows instead of being invisible.
- Preview levels include micro, grid, medium, and large. Original/full decode is intentionally not part of ordinary browsing.
- Imports record pending micro/grid preview work in `preview_generation_queue`.
- Import preview scheduling consults decode capability when a registry is available and skips formats that cannot render previews, including catalog-only X3F and future metadata-only providers.
- Demand-driven preview requests record pending work before dispatching worker generation.
- Browsing prefers cached previews. Grid display falls back to micro while grid preview work catches up. Loupe/compare paths prefer large, then medium, then grid, then micro.
- Launch/load does not synchronously render all pending previews. App-model recovery enqueues bounded worker jobs when a worker supervisor is available.
- Automatic preview recovery is capped at 40 queued items and enqueued as a batch to avoid one observable queue update per recovered preview.
- Preview recovery skips unavailable originals and rows that have failed too many automatic attempts.
- Preview generation preflights source availability and keeps preview work pending without burning retry attempts when an original is offline, missing, or stale after the catalog last saw it online.
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
- Accepted Teststrip keyword suggestions write through the same catalog-first/XMP sidecar path as manual keyword edits.
- Sidecar convention is collision-safe by default: append `.xmp` to the full original filename, for example `frame.cr2.xmp`.
- Existing Adobe-style sidecars such as `frame.xmp` are read/updated only when that basename is not ambiguous.
- Teststrip never writes original image bytes on the XMP path.
- Writeback preserves unrelated XMP properties when updating an existing sidecar.
- Failed sidecar writes record pending sync items and do not roll back catalog edits.
- Worker-backed metadata edits record pending sync before enqueueing helper work.
- Selection-triggered XMP checks are coalesced.
- Sidebar exposes `XMP Pending (n)` and `XMP Conflicts (n)` catalog scopes.
- Inspector exposes selected-photo XMP pending/conflict detail including sidecar filename/path and catalog generation, with conflict actions or pending retry shown in place.
- Selected pending XMP sync can be retried explicitly; direct retries write sidecars without touching original bytes and worker-backed retries reuse the managed XMP queue.
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
- Grid thumbnails and culling loupe metadata now show source-state badges/details for offline, missing, moved, and stale originals so cached-preview-only mode is visible instead of feeling broken.
- Reconnect flow can remap a cataloged old source root to a newly mounted root when matching relative files and fingerprints exist.
- Reconnect remains available from catalog source-root history even when the currently loaded page has no unavailable assets.
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
- Activity rows can cancel individual active background items; queued cancellations leave the helper and unrelated work alone, while dispatched cancellations terminate/restart the helper only where the synchronous worker protocol requires it.
- Activity shows when the helper process is idle and exposes a stop control that terminates only when no queued, running, or paused work remains.
- Worker commands and JSON-lines protocol live in core so the app and worker share the same contract.
- Worker import completion events carry skipped source-file counts as required protocol data instead of allowing helper-backed imports to silently lose that state.
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

- `local-image-metrics` reads cached previews and emits exposure, color-palette, focus, and provisional motion-blur/softness signals.
- `apple-vision` reads cached previews and emits face-quality, OCR, object-label, and visual-similarity feature-print signals through Apple's Vision APIs.
- `local-http-model` is opt-in through worker launch configuration and can return broader provisional model signals such as aesthetics and framing.
- App launch can pass local HTTP model config from `TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT`, `TESTSTRIP_LOCAL_HTTP_MODEL`, and `TESTSTRIP_LOCAL_HTTP_MODEL_TIMEOUT`.
- Local HTTP requests use an OpenAI-compatible chat-completions shape and embed cached previews as `image_url` data URLs.
- HTTP responses can be raw JSON or prose/fence-wrapped JSON; the provider extracts the JSON object.
- Retry behavior exists for transient transport failures and retryable response statuses.
- Evaluation output is persisted as typed `EvaluationSignal` rows with provider/model/version/settings provenance, including framing as a first-class model-provided signal kind.
- Recognition can be requested for selected, visible, compare, and current-scope cached assets; current-scope evaluation can enqueue cached assets beyond the loaded grid page while skipping uncached assets.
- Selected-frame evaluation signals now feed a compact culling verdict presentation so the rapid-cull header can show a real `TESTSTRIP READS` state with supporting quality rationale instead of a static placeholder.
- Selected-photo object-label signals now feed Inspector keyword suggestions, remaining provisional until the user explicitly accepts one into keywords/XMP.
- Survey Compare can show persisted focus, motion blur, exposure, and face-quality signals for each visible contender, and can enqueue evaluation only for compare frames that already have cached previews.
- `TeststripBench local-http-smoke <endpoint> <model> <image> [timeout]` exercises LM Studio/Ollama-style endpoints.

### UI And Automation

Built files include:

- `Sources/TeststripApp/LibraryGridView.swift`
- `Sources/TeststripApp/InspectorView.swift`
- `Sources/TeststripApp/SidebarView.swift`
- `Sources/TeststripApp/PeopleView.swift`
- `Sources/TeststripApp/CullingKeyCaptureView.swift`
- `Sources/TeststripApp/CachedPreviewImage.swift`
- `Sources/TeststripApp/LiveMockupPlaceholder.swift`

Current behavior:

- Studio-style shell exists: top chrome, sidebar, library grid, inspector, toolbar utility actions, activity/work surface. Top-bar routes that open partial live-mockup surfaces now carry code-level `LiveMockupPlaceholder` markers.
- Sidebar rows now render custom compact rows with icons, titles, optional details, count badges, and tone coloring. Row metadata is structured instead of baking counts into titles.
- Review queues show catalog-backed counts for Picks, Rejects, 5 Stars, Needs Keywords, Needs Evaluation, Faces Found, OCR Found, Likely Issues, and Provider Failures, and selecting those rows applies the matching catalog filters. Active filter chips and saved-search names keep Faces Found/OCR Found in review-language even though the catalog query uses underlying evaluation signal predicates.
- People is selectable from the sidebar and top chrome as a live mockup backed by real face-signal coverage. It now shows an unnamed face-review strip with live queue/scan status, a visible Apple Vision scan action for cached visible previews, and catalog-backed face review cards for face detections/quality signals; those cards route into the existing Faces Found and face-quality review targets. Users can name selected photos as a confirmed person, merge confirmed people, and dismiss selected photos from face-review queues while preserving the underlying evaluation signals. The sidebar labels this surface as `Face review`, and automatic clustering, split, and face-box-level naming remain disabled placeholders.
- Library grid renders cached previews and sizes overview cells from cataloged technical dimensions so portrait and panoramic photos keep their own aspect ratios without reading originals.
- Grid thumbnail density is user-configurable from the toolbar and persists as an app preference.
- Selection and inspector metadata display exist; the inspector now keeps the selected cached preview and asset header fixed above scrollable compact metadata controls in a fixed-size preview box, keeps Activity pinned below the inspector content, and formats technical metadata through tested display models.
- Active filters are summarized as visible chips below the search/filter controls.
- Live-mockup placeholders can be tagged in code with `LiveMockupPlaceholder`, including stable ids, intended behavior, and current fallback notes. The current registry tracks top chrome, People navigation, People face actions, empty Folders navigation, Places/map, agentic search, search refine, smart collections builder, batch keywording, export workflow, import plan, import-complete summary, culling assist, culling filmstrip, stack cull, focus compare, survey compare, and empty work history.
- `LiveMockupDesignSurfaces` maps every designer mockup id from `1a` through `5f` to current shipped/partial/live-mockup/deferred implementation status so deferred surfaces like Places and Export do not quietly reopen product scope.
- Search is a first-class library route in the sidebar and top chrome. It reuses the current catalog query/filter state, deterministically parses crisp Ask/search terms into structured predicates including camera, lens, keyword, folder/path, color label, ISO, captured date ranges, single-day date, source availability, signal kind, and XMP pending/conflict fields, keeps the filter rail visible, shows parsed filter chips, saved-set counts, a grouped Teststrip Reads refine rail beside results, and suggested actions for existing save dynamic set, freeze snapshot, and non-empty review-queue workflows, then displays the normal result grid as a live mockup for the fuller Search/Sets surface.
- Copilot is a first-class library route in the sidebar and top chrome. It summarizes scope, filters, work, XMP state, review queues, and local signal coverage, shows real review triage rows for Needs Keywords, Needs Evaluation, Faces Found, OCR Found, Likely Issues, and Provider Failures, offers one concrete primary action over existing flows such as XMP conflict review, provider-failure review, likely-issue review, pending XMP review, needs-evaluation review, or running visible local signals, and renders zero-count review queues as explanatory status rows rather than dead disabled buttons.
- Timeline is a first-class library route in the sidebar and top chrome. It uses catalog-backed capture-day summaries, groups days by month with catalog counts, shows a focused year/month/day scrubber for the loaded window, centers focused scrubber chips and month/day content sections, preserves loaded thumbnail activation, and lets day/month/year drill-down reuse existing captured-date predicates.
- Starred and Saved Sets sidebar rows show catalog-backed count badges for dynamic saved searches and explicit manual/snapshot sets.
- Smart Collection creation now has a split live-mockup builder popover reachable from active library filters. It parses current filter chips into rule rows, shows Teststrip-suggested templates, offers Add Rule presets for concrete catalog filters, previews loaded matching thumbnails, keeps Starred state, writes through the existing dynamic saved-query path, and saved sets can be deleted through explicit confirmation.
- Compare now uses a survey-style live mockup instead of the original flat adaptive grid: the selected frame becomes the primary candidate, active persisted stack sets are treated as candidate stacks, up to eight visible frames render in a four-column 4x2 survey grid ordered primary first followed by alternates, metadata-backed decision badges and focus/quality metric lanes render on tiles, preview/evaluation requests stay scoped to cached progressive compare behavior, Pick/Reject/Loupe actions write through existing metadata/navigation paths, and the current compare set can apply the primary recommendation by marking the primary Pick and visible alternates Reject.
- The import-complete summary is an expanded partial payoff panel with real import count, preview status, Open/Cull actions, time-adjacent stack counts when detected, a latest-import keyword review action when suggestions exist, dismiss behavior, and a disabled/annotated face naming follow-up.
- Import Path shows a pre-import plan for in-place cataloging, XMP sidecars, cached previews, and managed background work.
- Folder and card import confirmation now perform a capped source preview count using recognized photo-file extensions, show counted bytes, and display honest `N+` copy when the cap is hit. Typed Import Path now resolves into the same confirmation sheet before starting work. The confirmation plan distinguishes immediate import work from follow-up setup rows for imported-set culling, likely stacks, provisional keyword review, and Faces Found review; geo/map follow-up and automatic face naming remain out of scope.
- Active import work shows the shared progress banner immediately, even when the grid has no visible assets yet.
- Import progress copy now distinguishes starting, scanning, cataloging, copying, and preview-building phases with tested presentation rules and visible counts where available.
- Completed imports show an expanded summary panel with the imported photo count, preview status/failure count, Open action for the imported output set, Cull action that starts a culling work session from that set, Cull stacks action that persists each detected time-adjacent stack as a hidden work-stack set and starts culling with the first stack set selected, keyword suggestion review through the batch metadata popover, disabled unbuilt face follow-up, and dismiss behavior.
- Folder and card import entrypoints refuse duplicate import submissions while an import is already running.
- Culling sessions now start and reopen in loupe view with a culling header, reviewed-progress bar, pick/reject counts, selected-frame `TESTSTRIP READS` verdict with compact supporting quality rationale, fixed-height bottom filmstrip, stable rating/label/flag command rail, visible frame position, persisted stack-set navigation/acceptance and rail presentation for import stack culls, visual-similarity vector stack grouping with distance/threshold rationale when Apple Vision or local-model signals exist, work-session progress/completion from decided catalog flags, reviewed/pick/reject detail in recent/starred work history, a session Picks output set once accepted frames exist, stale empty Picks output cleanup when picks are cleared, and concrete Keep recommended / Keep top 2 actions when persisted focus/quality signals rank frames in the current stack.
- Work sessions point to input/output sets, recent and starred work sessions are visible in the sidebar, older starred sessions remain visible even when they fall outside the displayed recent-work cap, and reopening a session prefers its output set when one exists.
- Command-selected, shift-range, and page-spanning batch assets can be saved as manual saved sets in visible/catalog order, with the existing single-photo Save Selection fallback preserved.
- Saved sets can be renamed, duplicated, or deleted from the sidebar context menu; dynamic saved sets can also be frozen into named/starred static snapshots, with catalog persistence, sidebar/count refresh, immediate duplicate/snapshot selection, and active-scope cleanup when a selected set is deleted.
- Ratings, flags, labels, and keywords have app-model/catalog plumbing. The inspector can show object-label-backed keyword suggestions and accept them into catalog/XMP metadata; visible loaded assets and latest-import completions can also aggregate object-label batch keyword suggestions, seed a batch metadata draft, and apply keywords/caption/creator/copyright to command-selected loaded assets, visible assets, or the current search/filter/set scope through the same catalog/XMP path. Worker-backed batch metadata persists catalog edits, records pending XMP rows before enqueue, and queues sync work in one supervisor batch to avoid per-asset UI churn. Current Scope metadata requires explicit confirmation before it targets the whole catalog.
- Keyboard culling probe verifies selecting a thumbnail, clearing rating, sending `5`, seeing `Rating: 5` in the inspector, and then confirming catalog persistence when the app is truly foregrounded and its AX window tree is visible.
- Grid activation and selected-thumbnail feedback AX probes exist.
- CoreGraphics capture script exists for visual review.
- Evaluation AX probe exists for selected-photo evaluation.
- Submit-only Import Path helper exists for measuring catalog/import latency without continuously walking the app accessibility tree.

## Known Gaps

### Alpha-Blocking Gaps

- Preview throughput and UI churn under large preview backlogs are not good enough yet. The 600-image import path completed, but many previews were still pending after the initial wait and app CPU stayed high while draining.
- Import UX is improved but not complete. The app now shows visible active-import feedback, phase labels, post-import preview continuation, an Import Path plan, tested duplicate-import guards, runtime missing folder/card-source/card-destination errors, core card-destination policy guards, capped source previews, honest follow-up setup rows, a compact import-complete action summary, and a sandbox-aware required security-scope policy for packaged dev runs. Completed imports persist security-scoped bookmark data for catalog source roots when macOS provides it, model load restores access from stored bookmarks for the app session, stale/failed bookmark restore is visible in diagnostics and the Sources sidebar as a repair-needed actionable reconnect row, and source-root reconnect persists a fresh bookmark for the mounted root when macOS provides one. A restrained sandboxed UI import smoke still needs work.
- Clicking/selection needs one more accepted imported-photo verification pass. Direct grid clicks no longer recenter the thumbnail under the pointer, which was the likely root cause of the weird click feeling, and policy tests cover pointer-vs-programmatic selection scroll behavior. The imported-grid AX probe exists and now checks selection feedback plus visible inspector rating, but the latest run is blocked by desktop foregrounding: Teststrip launches behind Arc and Accessibility exposes only the application/menu proxy until Teststrip can be made genuinely frontmost.
- Library mockup parity is improving but incomplete. The overview grid now uses cataloged dimensions for true aspect-ratio cells, the filter rail is closer to the Studio mockup's Ask/search treatment, the inspector preview size is pinned and fixed above metadata scrolling, the inspector header/metadata controls have initial mockup-derived passes, the culling/loupe chrome now has verdict and filmstrip passes, imported-set stack culling uses real time-adjacent stack counts and explicit visual-similarity vector signals from Apple Vision or local models when present with distance/threshold rationale, persists detected stacks as hidden work-stack sets, can navigate/accept/render stack membership beyond the initial loaded page, writes session Picks output sets after accepted frames exist, and records reviewed/pick/reject decision detail in work history, stack culling can act on a persisted-signal single-frame recommendation or top-two scored keep action and refresh culling work-session progress from decided stack flags, People has a face-review strip with live queue/scan status, visible Apple Vision scan action, actionable review handoff, manual naming, manual confirmed-person merge, selected-photo face-review dismissal, and persisted named rows, Search has advanced field parsing, a grouped refine rail, deterministic generated refinements plus provider-signal refinements, deterministic related filters, and existing-workflow suggested actions, Copilot has real primary actions plus keyword/evaluation/face/OCR/issue/failure review triage over existing queues, Timeline has a catalog-backed year-density ribbon, focused month/day scrubber, and focused scroll syncing, Compare has an eight-frame four-column survey-style pass with metadata badges, active persisted-stack membership, and signal-backed recommendation or neutral ranking copy, Smart Collections has a split builder, concrete Add Rule presets that compose with selected dynamic saved-set rules, typed freeform rule editing through the existing search parser, contextual deterministic suggestion rows plus provider-signal suggestions for object/OCR/people signals, delete confirmation, and dynamic-to-frozen snapshot path, selected/visible/latest-import/current-scope batch metadata review exists for portable fields with all-catalog confirmation and typed keyword preview chips, selected/current-scope object-label suggestions can be accepted for matching assets across selected photos, the full active query, or a saved set, command/shift page-spanning batches can be frozen into manual saved sets, saved sets can be renamed, duplicated, or deleted with confirmation from the sidebar, dynamic saved sets can be frozen from the sidebar, the sidebar has richer count/detail rows and real review-queue/saved-set/timeline counts, the top chrome has a first Studio-style pass, and major dead UI gaps plus all designer surfaces are tagged in code, but similarity threshold tuning and broader natural-language Search planning still need visual passes against the design concept.
- The current RAW story has an explicit ImageIO capability matrix and provider boundary, but still lacks real RAW fixture coverage and a non-ImageIO provider for unsupported or weakly supported families such as Sigma/Foveon X3F. Lytro support remains out of scope.
- Evaluation is scaffolding plus early useful providers, not finished face/person/object/aesthetic workflow. The People view now uses real face-signal coverage for review cards, hands those cards off to existing review targets, can request Apple Vision evaluation for visible cached previews, and supports manual naming/merge/dismiss actions for confirmed people state; local metrics emit focus/exposure/color plus a coarse provisional motion-blur/softness score, local HTTP model output can carry aesthetics/framing labels, and object labels can be accepted as selected-photo, selected-batch, visible-batch, latest-import, or full current-scope keyword suggestions, but real automatic face clustering, identity recognition, split, face-box-level naming, richer label review, and broader reprocessing flows are not wired yet.
- Search/sets/work sessions are partially built but not yet the full user-facing model. The Ask/search field now parses a narrow deterministic grammar into catalog predicates, related review filters, generated concrete refinements, and provider-signal refinements from object/OCR/people evaluation summaries, and culling sessions can produce a work-session output set of accepted frames, but clusters, broader work-session-derived sets, richer query editing, and broader natural-language planning need more implementation.
- Smart collections have a stronger live builder for current filters, concrete Add Rule preset rows that compose with selected dynamic saved-set rules, typed freeform rule editing through the existing search parser, contextual deterministic suggestion rows, provider-signal suggestions for object/OCR/people evaluation summaries, duplicate/delete saved-set lifecycle, and a dynamic-to-frozen snapshot path. Broader provider-authored query planning is still not complete.
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

## Functional Alpha Gates

These are the current alpha gates. Performance must remain respectable enough to avoid obviously broken workflows, but the alpha focus is functionality and designer mockup parity rather than deeper latency tuning.

- [ ] **Import and source flow:** A user can add an existing folder in place, copy/import from a card-style source, understand preflight failures, see unambiguous progress, open the imported result set, and recover from duplicate/empty/unreadable-source cases without wondering whether the app is stuck.
- [x] **Real corpus smoke:** The ignored local corpus under `sample-data/photos/jesse-pictures` imports without committing sample files, catalogs mixed JPEG/DNG/RAF files honestly, preserves originals, and exposes unsupported/partial RAW files without overclaiming preview support. Latest verification: `./script/verify_real_corpus_smoke.sh sample-data/photos/jesse-pictures` on 2026-07-05 scanned 194 candidates, selected/imported/cataloged 3 representative assets, classified 1 working still and 2 best-effort RAWs, reported 0 unsupported files, and left all selected originals/sidecars unchanged.
- [ ] **Library browsing and mockup parity:** The Library grid, loupe, inspector, filter rail, top chrome, footer density controls, and sidebar are close enough to the designer mockups to use as the actual alpha surface, with dead or scaffolded UI marked by `LiveMockupPlaceholder`.
- [ ] **Selection, rating, and metadata:** Imported photos can be clicked, selected, rated, labeled, flagged, rejected, keyworded, and inspected with immediate catalog updates and no destructive writes to originals.
- [ ] **Catalog-first XMP:** Portable metadata writes catalog first, mirrors automatically to XMP when possible, shows pending/conflict states, supports safe conflict resolution, and leaves originals untouched.
- [ ] **Culling over arbitrary sets:** Culling works over any saved search, frozen snapshot, manual set, work-session output set, latest import, or detected stack set. Compare/survey supports the current eight-frame layout and can apply Pick/Reject decisions to the active set.
- [ ] **Search, sets, and work sessions:** Users can build and save practical smart collections, freeze snapshots, save manual selections, revisit recent/starred work sessions, and treat “photos from this work session” as a queryable set rather than a separate top-level container.
- [x] **People alpha:** People is no longer only a placeholder. The app can run local face evaluation, show face-review queues, persist minimal user-confirmed people/grouping state, and support naming/merge/dismiss review actions without implying Apple Photos-level identity recognition.
- [ ] **Recognition and provisional labels:** Local-first evaluation produces visible provenance-backed signals for faces, objects/content, OCR, focus, motion blur/softness, exposure, color/look, visual similarity, model-provided aesthetics/framing, and provider failures. Machine labels remain provisional until the user accepts them into metadata/XMP.
- [ ] **Offline and reconnect behavior:** Cached previews allow browsing and culling when originals are on an offline NAS/removable/cloud-backed volume, and reconnect remains reachable from source-root history while preserving unambiguous sidecar paths and source-root identity.
- [ ] **Worker control:** Long-running import, preview, metadata, source, and recognition work is visible, cancelable, and recoverable. The user can stop idle worker work, and runaway background work is treated as an alpha blocker.
- [ ] **Dev build and verification:** The macOS dev app builds reliably with the helper staged, focused tests cover new behavior, smoke verification uses non-focus-stealing captures by default, and focus-stealing UI automation is reserved for explicit approval or idle time.

## Next Build Slices

**Current priority note:** Jesse redirected the near-term push toward working feature coverage and designer mockup parity rather than latency-first tuning. Keep the preview/backlog evidence because it matters for pro catalogs, but do not spend alpha effort optimizing latency unless a feature gate is unusable. Lead with pulling the remaining designer surfaces into SwiftUI as honest live mockups, filling them out progressively, and replacing placeholder paths with real workflows. Keep focus-stealing UI automation minimal while Jesse is using the computer.

### Slice 1: Preview Throughput And UI Coalescing

**Why this still matters:** A photo manager that imports but then burns CPU and drains previews slowly will feel broken. This remains important for import, browsing, NAS/offline workflows, and culling, but it is no longer the lead lane ahead of working feature coverage and mockup parity.

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

- [x] Make import state unambiguous before, during, and after path submission.
- [x] Disable duplicate import submission while an import is starting or running.
- [x] Surface completed import count and whether preview generation is continuing after catalog/import completion.
- [x] Surface imported results even when the pre-existing filter or saved scope would otherwise hide newly imported photos.
- [x] Surface a clearer current import phase while path submission is scanning and cataloging.
- [x] Add honest import follow-up setup rows for culling, likely stacks, keyword review, and face review without reintroducing geo/map scope or automatic face naming.
- [x] Show clear empty-folder/no-recognized-photo-file preflight state before import starts.
- [x] Show clear typed-path file and unreadable-folder errors before import confirmation.
- [x] Show clear missing/unreadable source preflight errors in the import confirmation sheet.
- [x] Show clear duplicate import errors while another import is running.
- [x] Show clear runtime failed-folder/card-source errors before worker/local import starts.
- [x] Show clear runtime missing card-destination errors before worker/local card import starts.
- [x] Reject unsafe card destinations at the core ingest boundary, including missing roots, non-folders, source-as-destination, destinations nested inside the source, and sources nested inside the destination.
- [x] Add an injectable required security-scope access policy with clear pre-start import errors.
- [x] Enable required security-scope policy in a sandboxed packaged build once signing/entitlements exist.
- [x] Add model/presentation tests for import state transitions rather than brittle SwiftUI snapshots.
- [x] Extend AX import verifier to catch apparent no-op after submit and sheet-dismissed-with-no-visible-progress states. Current coverage adds a post-submit visible-feedback gate and `feedback_visible_seconds`.
- [x] Add the imported-grid selection/rating AX probe in Slice 3. The probe exists and is stronger, but current acceptance is blocked by Teststrip foregrounding/AX window visibility in this desktop session.
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
- [x] Teach Ask/search to parse advanced filter fields for folder/path, color, ISO, date, source availability, signal kind, and XMP state.
- [x] Add the Studio-style top chrome with catalog identity, breadcrumbs, Ask/search, compact view switching, and primary Import.
- [x] Add compare decision badges and a current-compare-set primary action without claiming real stack ranking.
- [x] Expand Survey Compare to an eight-frame four-column/4x2 grid while keeping unbuilt best/blink/soft claims out of the UI.
- [x] Pin the inspector/sidebar selected-preview box to a stable X/Y size so it does not expand with the detail column or selected image.
- [x] Refine the inspector asset header with display name, extension badge, captured date, rating, and availability.
- [x] Bring the loupe/culling surface closer to the mockup with top-level progress, decision counts, and stable flag/rating/label controls.
- [x] Add the rapid-cull bottom filmstrip with fixed-size thumbnails, current-frame context, and visible rating/flag state.
- [x] Make the import payoff's Cull stacks action use real time-adjacent stack counts and select the first detected stack when starting culling.
- [x] Persist detected import stack sets as hidden catalog sets and make stack accept/navigation/Compare use that membership.
- [x] Make the culling stack rail render explicit persisted stack membership instead of rediscovering only loaded-scope time-adjacent stacks.
- [x] Add concrete Keep recommended and Keep top 2 actions for culling stacks when persisted quality signals identify ranked frames.
- [x] Move library density and thumbnail-size controls into the Studio-style footer, expose Compact/Comfortable/Large presets, and make compact density use tighter grid spacing without cropping true-aspect thumbnails.
- [x] Fix the root cause if click handling, hit testing, focus capture, selection identity, or grid cell accessibility is wrong.
- [x] Add the least brittle model/UI tests that would have failed for the root cause.
- [ ] Verify all grid/culling scripts after Jesse is not actively using the computer.
- [x] Verify full `swift test`.
- [x] Commit.

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

- [x] Document the actual current ImageIO-supported extension set and what Teststrip claims versus merely attempts.
- [x] Add provider capability metadata for metadata read, embedded-preview usefulness, preview rendering, full render, and unsupported formats.
- [x] Keep ImageIO as the default provider where it works.
- [x] Add explicit fixture hooks for DNG, CRW, CR2, Fuji RAW, and Sigma/Foveon RAW. If real sample files are not committed, tests skip with explicit sample-missing messages instead of pretending coverage exists.
- [ ] Add or collect licensed real RAW sample files for DNG, CRW, CR2, Fuji RAW, and Sigma/Foveon RAW.
- [x] Add a clean provider capability seam for future LibRaw/RawSpeed-style providers without implementing the whole provider now.
- [ ] Make import still catalog unsupported/partial formats when metadata or embedded previews can be read.
- [x] Verify focused decode tests and full `swift test`.
- [x] Commit.

**Acceptance:** We know exactly which formats work, which are best-effort, and where a future decoder provider plugs in. The app should not silently overpromise RAW support.

**Current result:** Partially accepted. The ImageIO capability matrix and future provider seam are built and documented, X3F is no longer overclaimed, and opt-in RAW fixture hooks exist through `TESTSTRIP_RAW_FIXTURE_DIRECTORY`. Remaining work is collecting licensed real RAW samples, running fixture-backed coverage for DNG, CRW, CR2, Fuji RAW, and long-tail RAW samples, plus deciding whether unsupported-but-important formats should be cataloged through a separate non-decode import path.

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

- [x] Add user-facing conflict detail for selected conflicted assets.
- [x] Add explicit retry action for pending XMP sync items when a source becomes writable again.
- [x] Add a lower-risk selected-conflict `Merge Missing` action that fills catalog gaps from sidecar metadata before destructive catalog-vs-XMP choices.
- [x] Make bulk metadata edits avoid UI stalls while still recording pending sync before worker dispatch.
- [x] Add tests for sidecar changed externally, catalog changed locally, both changed, selected merge resolution, and pending sync retry behavior.
- [x] Preserve unambiguous Adobe-style sidecar paths when reconnecting source roots.
- [x] Verify full `swift test` and a headless sidecar-content flow that edits rating/label/keyword-style portable metadata, parses written sidecars, checks catalog/sidecar equality, confirms sync fingerprints, and confirms originals are unchanged.
- [x] Commit.

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

- [x] Promote selected-frame evaluation signals into the rapid-cull `TESTSTRIP READS` verdict surface with provider confidence detail and compact supporting quality rationale.
- [x] Promote evaluation results into fuller user-visible signal groups: technical quality, faces, OCR, objects/content, color/look, and provider provenance.
- [x] Make People face-review cards hand off to existing Faces Found / face-quality review targets without implying finished person clustering.
- [x] Add People/face grouping data model only after deciding the smallest useful grouping behavior. Built as manual confirmed-person groups over selected/batch photos, merge, and dismiss; automatic identity recognition, split, and face-box-level naming remain disabled placeholders.
- [x] Add review filters for unevaluated, faces found, OCR found, likely issues, and provider failures. Built as catalog-backed Review queues with durable per-asset/per-provider failure state for provider failures.
- [x] Surface the broader review queues in Copilot triage without implying autonomous review or fake generated recommendations.
- [x] Add cancellation-aware provider execution or worker-level cancellation behavior for slow local HTTP calls.
- [x] Add first-class framing signals for model providers and local provisional motion-blur/softness, framing, and aesthetics signals from cached-preview metrics.
- [x] Add current-scope recognition evaluation so users can evaluate cached assets in the active search/set/filter beyond the loaded grid page.
- [x] Keep machine labels provisional unless the user explicitly accepts them into keywords/XMP.
- [x] Verify provider tests and `TeststripBench local-http-smoke` through `script/verify_local_http_model_smoke.sh` against a local OpenAI-compatible stub endpoint.
- [ ] Keep real LM Studio/Ollama endpoint smoke as an optional environment-specific check when one is available.
- [x] Commit.

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

- [x] Define the minimum user-facing set types for alpha: import batch, manual selection, saved search, frozen snapshot, and work-session-derived set.
- [x] Add query predicates for rating, color label, pick/reject, keyword, date, folder, source availability, XMP state, and evaluation signal kind.
- [x] Add a catalog-backed import/work-output batch predicate so work-session output sets can be used as a query.
- [x] Add sidebar sections for recent/starred work sessions next to saved sets/searches.
- [x] Keep older starred work sessions visible next to the capped recent work list.
- [x] Make culling operate on the active set, not only the whole library or last import.
- [x] Make persisted stack culling sessions expose accepted frames as a work-session output set.
- [x] Make ordinary culling sessions over arbitrary sets refresh progress and expose accepted frames as a work-session output set.
- [x] Add tests that a work session points to input/output/generated sets rather than owning a separate membership system.
- [x] Verify full `swift test` and one app workflow at the model level: import/set recovery, save a filtered/manual set, start a culling session over it, star/reopen work sessions, and recover output sets from sidebar-backed work sessions are covered by focused AppModel tests; focus-stealing UI automation is still reserved for approved/idle windows.
- [x] Commit.

**Acceptance:** "Photos that are part of this job/work session" is implemented as a queryable set, and photographers can cull arbitrary sets instead of being forced into import-batch workflows.

### Slice 8: Smart Collection Builder And Filter Bar

**Files to inspect first:**

- `Sources/TeststripCore/Search/SetQuery.swift`
- `Sources/TeststripApp/LibraryGridView.swift`
- `Sources/TeststripApp/SidebarView.swift`
- `Sources/TeststripApp/AppModel.swift`
- `Tests/TeststripCoreTests/SearchSetTests.swift`

**Work:**

- [x] Build a compact advanced filter bar for camera/lens/ISO/date/rating/label/flag/keyword/source/evaluation filters once the underlying predicate set exists.
- [x] Save current filter expressions as dynamic smart collections through the builder popover.
- [x] Expand the builder toward the designer mockup with parsed rule rows and a live loaded-result thumbnail preview.
- [x] Support frozen snapshots separately from dynamic saved searches.
- [x] Surface existing save dynamic set, freeze snapshot, and non-empty review-queue workflows as Search suggested actions.
- [x] Add model tests for predicate round-trip and dynamic-vs-frozen behavior.
- [x] Verify common indexed searches through the repeatable 100k alpha-scale catalog verifier.
- [ ] Extend the same indexed-search threshold gate to seeded 500k/1M catalogs when those runs are cheap enough for routine verification.
- [x] Commit.

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

- [x] Make benchmark commands print machine-readable summaries in addition to human text.
- [x] Add a repeatable import benchmark for large folders with previews deferred.
- [x] Add preview render throughput benchmark for cached generated images.
- [x] Add a dedicated preview render throughput benchmark for a small real-image sample directory.
- [x] Add metadata/XMP bulk edit benchmark.
- [x] Add a repeatable catalog-scale verifier script with alpha thresholds for page/filter query timings.
- [x] Add a repeatable preview-render verifier script with alpha thresholds for generated preview correctness and timing.
- [x] Add a repeatable metadata-write verifier script with alpha thresholds for catalog/XMP writeback correctness and timing.
- [x] Add a repeatable import-preview-drain verifier script with alpha thresholds for deferred import correctness, preview recovery, and timing.
- [x] Add memory and CPU snapshots to app workflow scripts where practical.
- [x] Set initial green thresholds for the 100k alpha catalog verifier after measuring current local behavior.
- [ ] Set red/yellow/green thresholds for app workflow and larger 500k/1M stress paths after measuring current local behavior.
- [x] Update `docs/architecture/performance.md` with measured evidence and caveats.
- [x] Commit.

**Acceptance:** Future agents cannot accidentally call the app fast without running the same scale checks.

### Slice 10: Dev Packaging, Diagnostics, And Recovery

**Files to inspect first:**

- `script/build_and_run.sh`
- `Sources/TeststripApp/AppCatalog.swift`
- `Sources/TeststripApp/main.swift`
- `Sources/TeststripCore/Worker/WorkerSupervisor.swift`
- `docs/architecture/worker-management.md`

**Work:**

- [x] Keep dev app bundle signing/helper staging reliable.
- [x] Add diagnostics export for catalog path, preview cache path, worker path, pending work counts, source status counts, and recent worker failures.
- [x] Add a reset-only-isolated-test-data helper if current smoke scripts leave confusing state.
- [x] Add non-focus-stealing worker recovery smoke for catalog-persisted pending preview work promoted into queued/running worker-visible work. Latest verification: `script/verify_worker_recovery.sh 4 5` passed on 2026-07-05 with 4 catalog assets, 1 running worker command, 3 queued items, and 4 pending preview records.
- [ ] Decide later whether notarization belongs before private alpha. Do not do production packaging work until Jesse asks.
- [ ] Commit.

**Acceptance:** Jesse can run and test the app repeatedly without needing to babysit hidden app-support state or worker leftovers.

## Verification Commands

Use these as the default confidence ladder:

```bash
./script/verify_headless_workflows.sh
```

Use these only for explicit/idle-time UI automation, because they launch or foreground the app:

```bash
./script/build_and_run.sh --verify-smoke
./script/verify_app_workflows.sh Teststrip
./script/verify_grid_activation.sh Teststrip
./script/verify_grid_selection_feedback.sh Teststrip
./script/verify_keyboard_culling.sh Teststrip
./script/verify_imported_grid_culling.sh Teststrip
./script/verify_evaluation.sh Teststrip
# Expected-red until the large-import preview/AX visibility blocker is resolved.
TESTSTRIP_AX_IMPORT_COUNT=600 TESTSTRIP_AX_TIMEOUT_SECONDS=45 ./script/verify_import_path.sh Teststrip
```

For scale checks:

```bash
swift run TeststripBench catalog-baseline
swift run TeststripBench catalog-stress
script/verify_catalog_scale.sh 100000
script/verify_metadata_write.sh 1000
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
