# Scenario Ledger — canonical status tracker

Single writer: the story-loop main thread. One row per capability card.
Status flow: Spec'd → Tested-Pass | Tested-Fail → Fixed → Verified.

| ID | Card | Status | Test method | Defect type | Actual result | Notes / open questions |
|---|---|---|---|---|---|---|
| cull-001-workspace-key-gating | cull-001-workspace-key-gating.md | Verified | VM e2e (ax+sql) | — | iter2 re-run all PASS post-fix; gate leak closed | iter1: investigate gate leak; fix card steps 6-7 |
| cull-002-loupe-navigation | cull-002-loupe-navigation.md | Verified | VM e2e (ax+sql) | — | iter3 post-fix re-run PASS; single-fire confirmed via SQL deltas | card steps 6-7/Expected corrected 2026-07-10 to assert the no-op; real stack-to-stack nav still needs a multi-frame fixture |
| cull-003-rating-label-flag-keys | cull-003-rating-label-flag-keys.md | Verified | VM e2e (ax+sql) | — | iter3 post-fix re-run PASS; single-fire confirmed via SQL deltas | needs fresh full card re-run to Verify |
| cull-004-stack-promote-return | cull-004-stack-promote-return.md | Verified | VM e2e | — | burst fixture: promote gesture verified live incl. single undo group | BLOCKED fixture gap: no seed produces multi-frame stacks (smoke 900s apart vs 2s builder gap; bench JPEGs lack EXIF DateTimeOriginal) |
| cull-005-scope-cycle | cull-005-scope-cycle.md | Verified | VM e2e (ax+sql) | — | iter3 post-fix re-run PASS; single-fire confirmed via SQL deltas | needs fresh full card re-run to Verify |
| cull-006-zoom-and-face-zoom | cull-006-zoom-and-face-zoom.md | Verified | VM e2e (ax+sql) | — | iter3 post-fix re-run PASS; single-fire confirmed via SQL deltas | screenshot-diff method now runnable; card itself needs a fresh run |
| cull-007-exif-overlay-cycle | cull-007-exif-overlay-cycle.md | Verified | VM e2e (ax+sql) | — | iter3 post-fix re-run PASS; single-fire confirmed via SQL deltas | needs fresh full card re-run to Verify |
| cull-008-subview-keys-gcb | cull-008-subview-keys-gcb.md | Verified | VM e2e (ax+sql) | — | iter3 post-fix re-run PASS; single-fire confirmed via SQL deltas | needs fresh full card re-run to Verify |
| cull-009-keymap-overlay | cull-009-keymap-overlay.md | Verified | VM e2e (ax+sql) | — | iter3 post-fix re-run PASS; single-fire confirmed via SQL deltas | needs fresh full card re-run to Verify |
| cull-010-cullgrid-keys | cull-010-cullgrid-keys.md | Verified | VM e2e (ax+sql) | — | iter3 post-fix re-run PASS; single-fire confirmed via SQL deltas | batch-rating steps now runnable; card needs a fresh run |
| cull-011-hud | cull-011-hud.md | Tested-Pass | VM e2e (ax+sql) | — | counts track catalog exactly |  |
| cull-012-closeups-panel | cull-012-closeups-panel.md | Verified | VM e2e (ax+sql) | — | iter3 post-fix re-run PASS; single-fire confirmed via SQL deltas | open q: Close-Ups re-detects live vs face_observations table — counts may disagree; intended? |
| cull-013-filmstrip | cull-013-filmstrip.md | Verified | VM e2e | — | burst re-run PASS (divider visual occluded by Dock — position math verified) | shares stack fixture gap with cull-004 |
| cull-014-stack-rail | cull-014-stack-rail.md | Verified | VM e2e | — | burst re-run PASS (flaw-dot leg unfalsifiable without flaw signals) | Core action set unread — open question; inventory corrected: primary Keep keeps SELECTED frame, not recommendation; action set documented |
| cull-015-sidebar-sources | cull-015-sidebar-sources.md | Tested-Pass | VM e2e (ax+sql) | — | all source rows/counts correct |  |
| cull-016-completion-stage | cull-016-completion-stage.md | Tested-Pass | VM e2e (ax+sql) | — | completion, Review Picks, scope reappearance correct; banner items still fixture-blocked | adopts end-of-set-move-rejects; items 49-51 (session banners) blocked by stack fixture gap |
| cull-017-autopilot-review | cull-017-autopilot-review.md | Tested-Fail | VM e2e | Testability | BLOCKED-TOOLING: needs host fixture gen + submit_import_path equivalent in VM | adopts autopilot-review-commit-undo; open q: banner Dismiss may make Review unreachable for that run (one-way door) |
| cull-018-compare-survey | cull-018-compare-survey.md | Tested-Pass | VM e2e (ax+sql) | — | core verified; worker-eval steps (Evaluate Compare/contenders/refill) unexercised — needs evaluated fixture | open q: shared monitor key semantics in compare; CONFIRMED UX inconsistency: Return uses stricter stack-guard and can silently no-op while Keep-primary button is enabled |
| cull-019-ab-compare | cull-019-ab-compare.md | Tested-Pass | VM e2e (ax+sql) | — | header/contender/keep-write verified via SQL |  |
| cull-020-pass-scope-and-undo | cull-020-pass-scope-and-undo.md | Verified | VM e2e | — | stack leg PASS on burst; full card now green | adopts cull-pass-scope-and-undo |
| lib-001-sidebar-sections | lib-001-sidebar-sections.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-002-saved-set-context-menus | lib-002-saved-set-context-menus.md | Verified | VM e2e | — | iter3 re-run PASS post right-click fix (work-session leg vacuous on smoke) | note: work-session menu is a single star-toggle whose title flips; possible dup SidebarRow.id across sections (List diffing footgun) |
| lib-003-token-grammar-fields | lib-003-token-grammar-fields.md | Tested-Fail | VM e2e | UX | unquoted multi-word value silently drops trailing words (camera:SmokeCam 1 → 24 not 8); quoted works — Jesse decision: auto-quote/greedy-consume or document-only |  |
| lib-004-bare-and-phrase-tokens | lib-004-bare-and-phrase-tokens.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-005-token-readback-roundtrip | lib-005-token-readback-roundtrip.md | Tested-Pass | unit + VM spot-check | — | unit pass; AX spot-check pass except card drift (expected 10 vs actual 9 chips) — card fix queued | all round-trip + grammar assertions pass; AX spot-check pending VM batch |
| lib-006-query-field-and-tips | lib-006-query-field-and-tips.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-007-add-filter-menu | lib-007-add-filter-menu.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-008-chips-remove-clear | lib-008-chips-remove-clear.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-009-sort-and-bar-extras | lib-009-sort-and-bar-extras.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-010-result-header-save | lib-010-result-header-save.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS | fiveStars queue drives a Rating>=4 chip — name/behavior mismatch to arbitrate |
| lib-011-view-toggle-routing | lib-011-view-toggle-routing.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-012-grid-keys | lib-012-grid-keys.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-013-library-loupe | lib-013-library-loupe.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS | adopts library-loupe-no-cull-chrome |
| lib-014-map-clusters-scoping | lib-014-map-clusters-scoping.md | Tested-Pass | VM e2e | Environment | clusters+query-scoping PASS; geocode legs blocked (CLGeocoder unreachable from VM) — SKIP-offline honored | adopts places-map-and-geocode; verify 62e0a31 query scoping |
| lib-015-timeline | lib-015-timeline.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-016-grid-badges | lib-016-grid-badges.md | Verified | VM e2e | — | iter3 re-run PASS post a11y fix; screenshots verified |  |
| lib-017-footer-density-zoom | lib-017-footer-density-zoom.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-018-pagination | lib-018-pagination.md | Tested-Pass | VM e2e | Testability | reachable legs PASS on smokebig; Load Previous needs >240 fixture | BLOCKED fixture gap: assetPageSize=120 vs 24 smoke assets — pagination unreachable with current seeds |
| lib-019-multiselect | lib-019-multiselect.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS |  |
| lib-020-token-query-filter | lib-020-token-query-filter.md | Tested-Pass | VM e2e (ax+sql) | — | iter1 PASS | adopts token-query-filter |
| people-001-canvas-header | people-001-canvas-header.md | Tested-Pass | VM e2e | — | PASS |  |
| people-002-suggestion-cards | people-002-suggestion-cards.md | Tested-Pass | VM e2e | — | PASS (pre-attach-ruling build; re-verify post-merge) | adopts people-name-face-group-happy-path |
| people-003-cluster-identity | people-003-cluster-identity.md | Tested-Pass | VM e2e | — | PASS; tap sub-leg blocked (no click verb) | adopts people-cluster-by-identity |
| people-004-review-cards | people-004-review-cards.md | Tested-Pass | VM e2e | — | PASS; disabled-state leg unreachable per card |  |
| people-005-queue-keyboard | people-005-queue-keyboard.md | Tested-Pass | VM e2e | — | PASS (shared session with 006 — rerun isolated before Verified) | adopts people-confirm-writes-on-return |
| people-006-sheet-return-routing | people-006-sheet-return-routing.md | Tested-Pass | VM e2e | — | PASS (shared session caveat) | adopts people-naming-sheet-return-routing |
| people-007-name-selection | people-007-name-selection.md | Tested-Pass | VM e2e | — | PASS (pre-attach-ruling build; re-verify post-merge) |  |
| people-008-person-cards-merge | people-008-person-cards-merge.md | Tested-Pass | VM e2e | Testability | merge/counts PASS; card-body tap blocked (no CGEvent click verb); dup-name probe confirmed dup rows — since FIXED by 93415485, re-verify | open q: duplicate-name people; open q: duplicate-name people minted silently (people.name non-unique, no match-existing step) — product gap for Jesse |
| people-009-scan | people-009-scan.md | Tested-Pass | VM e2e | — | PASS; two timing sub-legs unobservable |  |
| inspect-001-toggle-tabs | inspect-001-toggle-tabs.md | Tested-Pass | VM e2e | — | PASS; width/no-selection legs unmeasurable in VM |  |
| inspect-002-info-identity-exif | inspect-002-info-identity-exif.md | Tested-Pass | VM e2e | — | PASS; summary child text not AX-exposed (note) | fixture gap: smoke seeds lack aperture/shutter/focal-length |
| inspect-003-sync-status-conflict-resolver | inspect-003-sync-status-conflict-resolver.md | Tested-Fail | VM e2e | Functional | FAIL: pending-XMP Retry never drains (2 presses, 2+min, worker alive; later edit syncs) — fix queued; Part B resolutions not run (budget) | conflict trigger inferred (fingerprint mismatch) — confirm on first live run |
| inspect-004-retry-surfaces | inspect-004-retry-surfaces.md | Tested-Fail | VM e2e | Functional | provider-retry PASS; BUT invalid PreviewLevel row fatalErrors app into crash loop (main.swift:34) — tolerant-decode fix queued; card doc bug too | failure rows synthesized via SQL — proves retry wiring, not failure detection |
| inspect-005-describe-editing | inspect-005-describe-editing.md | Tested-Pass | VM e2e | — | core+asymmetry proven pre-ruling; rerun post-batch-fields merge; creator/copyright fields untargetable (unlabeled AXTextFields — a11y gap, fix queued) | open q: batch vs single-asset asymmetry; confirmed asymmetry: rating/flag/label batch vs keywords/caption/etc single-asset, note only near batch controls — UX question for Jesse |
| inspect-006-suggested-keywords-ocr | inspect-006-suggested-keywords-ocr.md | Tested-Fail | VM e2e | Testability | smoke lacks keyword signals (card fixture bug); faces chips over budget | adopts inspector-describe-suggested-keyword |
| inspect-007-ai-verdicts | inspect-007-ai-verdicts.md | Tested-Pass | VM e2e | — | PASS |  |
| inspect-008-sidecar-write-semantics | inspect-008-sidecar-write-semantics.md | Tested-Pass | VM e2e | — | PASS | adopts rate-writes-xmp-happy-path |
| inspect-009-metadata-undo | inspect-009-metadata-undo.md | Tested-Pass | VM e2e | — | PASS |  |
| import-001-folder-in-place | import-001-folder-in-place.md | Spec'd | — | — | — |  |
| import-002-card-copy | import-002-card-copy.md | Spec'd | — | — | — | open q: per-file skip vs whole-batch failure on collision — card accepts either, confirm live |
| import-003-menu-and-dev-path | import-003-menu-and-dev-path.md | Spec'd | — | — | — |  |
| import-004-new-only-dedupe | import-004-new-only-dedupe.md | Spec'd | — | — | — | adopts duplicate-detection-import-new-only |
| import-005-sidecar-on-import | import-005-sidecar-on-import.md | Spec'd | — | — | — | first-import conflict unreachable (planner folds unconditionally); second-import framing used |
| import-006-availability-badges | import-006-availability-badges.md | Spec'd | — | — | — |  |
| import-007-refresh-reconnect | import-007-refresh-reconnect.md | Spec'd | — | — | — |  |
| import-008-auto-cull-toggle | import-008-auto-cull-toggle.md | Spec'd | — | — | — |  |
| import-009-cull-pick-journey | import-009-cull-pick-journey.md | Spec'd | — | — | — | adopts import-cull-pick-happy-path (cross-area journey) |
| activity-001-icon-states | activity-001-icon-states.md | Spec'd | — | — | — | adopts activity-icon-states + quiet-activity-badge; known gap: no UI rescan trigger |
| activity-002-popover-import | activity-002-popover-import.md | Spec'd | — | — | — | suspected bug: completed-with-errors import surfacing gap in popover |
| activity-003-jobs-controls | activity-003-jobs-controls.md | Spec'd | — | — | — | fixture gap: >4 concurrent jobs may not be exercisable (smoke drains fast) |
| activity-004-sources-conflicts-quiet | activity-004-sources-conflicts-quiet.md | Spec'd | — | — | — |  |
| activity-005-conflict-deep-link | activity-005-conflict-deep-link.md | Spec'd | — | — | — |  |
| activity-006-xmp-lifecycle | activity-006-xmp-lifecycle.md | Spec'd | — | — | — |  |
| worker-001-preview-lifecycle | worker-001-preview-lifecycle.md | Spec'd | — | — | — |  |
| worker-002-evaluation-verdicts | worker-002-evaluation-verdicts.md | Spec'd | — | — | — |  |
| worker-003-face-pipeline | worker-003-face-pipeline.md | Spec'd | — | — | — | 2000-observation cap source-grounded only; no fixture reaches it |
| worker-004-death-recovery | worker-004-death-recovery.md | Spec'd | — | — | — |  |
| worker-005-offline-reconnect | worker-005-offline-reconnect.md | Spec'd | — | — | — | open q: no confirmed UI trigger for post-reconnect availability re-probe |
| worker-006-geocode-backfill | worker-006-geocode-backfill.md | Spec'd | — | — | — | network-dependent; SKIP offline |
| app-001-launch-scene | app-001-launch-scene.md | Spec'd | — | — | — |  |
| app-002-window-floors | app-002-window-floors.md | Spec'd | — | — | — | adopts workspace-minimum-width-floors |
| app-003-workspace-switching | app-003-workspace-switching.md | Spec'd | — | — | — | adopts workspace-switching |
| app-004-subview-menus | app-004-subview-menus.md | Spec'd | — | — | — |  |
| app-005-chrome-policy | app-005-chrome-policy.md | Spec'd | — | — | — | adopts ux-simplification-chrome |
| app-006-session-restore | app-006-session-restore.md | Spec'd | — | — | — | harness note: launch mints fresh state dir per call — relaunch must reuse run dir; a relaunch verb would simplify |
| app-007-go-history | app-007-go-history.md | Spec'd | — | — | — |  |
| app-008-batch-metadata | app-008-batch-metadata.md | Spec'd | — | — | — |  |
| app-009-export | app-009-export.md | Spec'd | — | — | — | adopts export-presets-with-exif |
| app-010-move-rejects | app-010-move-rejects.md | Spec'd | — | — | — | adopts reject-relocation-move-and-back |
| app-011-find-best-shots | app-011-find-best-shots.md | Spec'd | — | — | — | outcome C (nothing-ranked) needs a zero-rank fixture; mark NOT-RUN if unproducible |
| app-012-autopilot-evaluate-commands | app-012-autopilot-evaluate-commands.md | Spec'd | — | — | — |  |
| app-013-diagnostics | app-013-diagnostics.md | Spec'd | — | — | — |  |
| app-014-updater | app-014-updater.md | Spec'd | — | — | — | Sparkle e2e untestable pre-release; static-only cap; Sparkle e2e untestable pre-release; static-only cap. Defaults key names unverified until first live run |
| app-015-preferences | app-015-preferences.md | Spec'd | — | — | — |  |
| app-016-menu-coverage-invariants | app-016-menu-coverage-invariants.md | Tested-Pass | unit tests (MenuCoveragePresentationTests 8/0) | — | — | unit-test method; gap: Run Autopilot/Scan for Faces/Evaluate Photo/Scope not enumerated — renames uncatchable; DRY-RUN PASSED (8 tests) during authoring; all coverage invariants pass |
| dev-001-build-and-run-modes | dev-001-build-and-run-modes.md | Tested-Pass | host CLI e2e | — | all assertions pass incl. exit codes | usage drift: --real-corpus undocumented; CONFIRMED Documentation defect: usage() omits --real-corpus (live-verified) |
| dev-002-seed-variants | dev-002-seed-variants.md | Tested-Pass | host CLI e2e | — | pass; 1 flake retry (catalog-init race) |  |
| dev-003-vm-harness | dev-003-vm-harness.md | Spec'd | — | Environment | BLOCKED-CONCURRENT iter1 (VM held); re-run iter2 | CONFIRMED Documentation defect: --reseed hint names a flag with no dispatch path; sync smoke --reseed would error |
| dev-004-package-release-dry-run | dev-004-package-release-dry-run.md | Tested-Pass | host CLI e2e | — | pass; 1 flake retry (build race) |  |
| dev-005-package-release-signing | dev-005-package-release-signing.md | Tested-Pass | static + partial CLI | — | signing path documented, not exercised (cap noted) | needs Developer ID cert locally |
| dev-006-ax-drive | dev-006-ax-drive.md | Spec'd | — | Environment | step1 pass; rest BLOCKED-CONCURRENT; re-run iter2 |  |
| dev-007-reset-isolated | dev-007-reset-isolated.md | Verified | host CLI e2e | Functional | post-fix re-run all 5 assertions pass (fix 6b25be77 confirmed live) |  |
| dev-008-sample-downloads | dev-008-sample-downloads.md | Tested-Fail | host CLI e2e | Logistical | face-model manifest URL is literal REPLACE-ME.example.com — download permanently broken | network |
| dev-009-bench-seeds | dev-009-bench-seeds.md | Tested-Pass | host CLI e2e | — | pass; note: negative-overwrite exits via fatalError/SIGABRT not clean error |  |
| dev-010-bench-benchmarks | dev-010-bench-benchmarks.md | Tested-Pass | host CLI e2e | — | benchmark-summary contract holds |  |
| dev-011-release-ci | dev-011-release-ci.md | Tested-Pass | static checks only | — | static-only cap — never promotes past Tested-Pass; 3 secrets still missing | needs tag + 7 secrets; static-only cap; needs tag + 7 secrets; static-only cap. 3 secrets currently missing (cert b64/password, app-specific pw) — next v* tag will fail |
| dev-012-verifier-gates | dev-012-verifier-gates.md | Tested-Pass | host CLI e2e + solo swift test | — | legs 2-13 live pass; leg1 dispute resolved by controller solo run 1693/0 | Jesse decision: delete-or-keep stale gui verifiers? KNOWN-STALE: verify_evaluation, verify_card_import_path; KNOWN-STALE gui verifiers; ALSO live swift-test failure seen under concurrent-agent contention (WorkerEntrypointTests truncated worker JSON) — re-run solo before logging Functional; solo swift test 1693/0 — earlier failure was agent contention (Environment), not product; follow-up: verify_people_clustering.sh presses Evaluate Scope as AXButton (now a menu item), masked by || true |
