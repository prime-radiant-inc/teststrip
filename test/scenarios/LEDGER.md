# Scenario Ledger — canonical status tracker

Single writer: the story-loop main thread. One row per capability card.
Status flow: Spec'd → Tested-Pass | Tested-Fail → Fixed → Verified.

| ID | Card | Status | Test method | Defect type | Actual result | Notes / open questions |
|---|---|---|---|---|---|---|
| cull-001-workspace-key-gating | cull-001-workspace-key-gating.md | Verified | VM e2e (ax+sql) | — | iter2 re-run all PASS post-fix; gate leak closed | iter1: investigate gate leak; fix card steps 6-7 |
| cull-002-loupe-navigation | cull-002-loupe-navigation.md | Fixed | VM e2e | — | stack nav = designed no-op on singleton seed; card corrected e76e5f3d; L/R/Space passed; awaiting re-run | card steps 6-7/Expected corrected 2026-07-10 to assert the no-op; real stack-to-stack nav still needs a multi-frame fixture |
| cull-003-rating-label-flag-keys | cull-003-rating-label-flag-keys.md | Fixed | VM e2e | Functional | double-fire root-caused: menu key-equivalents fire after monitor (nil return doesn't block) — menu equivalents removed 3f426d3c, live single-fire proven; awaiting re-run | needs fresh full card re-run to Verify |
| cull-004-stack-promote-return | cull-004-stack-promote-return.md | Tested-Fail | VM e2e | Testability | BLOCKED-FIXTURE multi-frame stacks; stackless no-op PASS | BLOCKED fixture gap: no seed produces multi-frame stacks (smoke 900s apart vs 2s builder gap; bench JPEGs lack EXIF DateTimeOriginal) |
| cull-005-scope-cycle | cull-005-scope-cycle.md | Fixed | VM e2e | Functional | same fix 3f426d3c; S cycles one/press proven; awaiting re-run | needs fresh full card re-run to Verify |
| cull-006-zoom-and-face-zoom | cull-006-zoom-and-face-zoom.md | Fixed | VM e2e | Testability | Screen Recording TCC granted in VM setup 842ea5b7; awaiting re-run | screenshot-diff method now runnable; card itself needs a fresh run |
| cull-007-exif-overlay-cycle | cull-007-exif-overlay-cycle.md | Fixed | VM e2e | Functional | same fix; I lands exposure-only proven; awaiting re-run | needs fresh full card re-run to Verify |
| cull-008-subview-keys-gcb | cull-008-subview-keys-gcb.md | Fixed | VM e2e | Functional | View-menu bare g/c/b equivalents re-set view after monitor — removed; G+Esc verified; awaiting re-run | needs fresh full card re-run to Verify |
| cull-009-keymap-overlay | cull-009-keymap-overlay.md | Fixed | VM e2e | Functional | Esc was consumed as returnToGrid leaving overlay stuck — Esc now dismisses overlay first d1a200c3 (4 tests); awaiting re-run | needs fresh full card re-run to Verify |
| cull-010-cullgrid-keys | cull-010-cullgrid-keys.md | Fixed | VM e2e | Testability | ax_drive --modifiers added 842ea5b7 (CGEvent clicks); awaiting re-run | batch-rating steps now runnable; card needs a fresh run |
| cull-011-hud | cull-011-hud.md | Tested-Pass | VM e2e (ax+sql) | — | counts track catalog exactly |  |
| cull-012-closeups-panel | cull-012-closeups-panel.md | Fixed | VM e2e | Environment | faces originals now synced + detection needs Evaluate Scope (card updated); 11 observations landed; awaiting re-run | open q: Close-Ups re-detects live vs face_observations table — counts may disagree; intended? |
| cull-013-filmstrip | cull-013-filmstrip.md | Tested-Fail | VM e2e | Testability | position text PASS; dividers BLOCKED-FIXTURE | shares stack fixture gap with cull-004 |
| cull-014-stack-rail | cull-014-stack-rail.md | Tested-Fail | VM e2e | Testability | BLOCKED-FIXTURE | Core action set unread — open question; inventory corrected: primary Keep keeps SELECTED frame, not recommendation; action set documented |
| cull-015-sidebar-sources | cull-015-sidebar-sources.md | Tested-Pass | VM e2e (ax+sql) | — | all source rows/counts correct |  |
| cull-016-completion-stage | cull-016-completion-stage.md | Tested-Pass | VM e2e (ax+sql) | — | completion, Review Picks, scope reappearance correct; banner items still fixture-blocked | adopts end-of-set-move-rejects; items 49-51 (session banners) blocked by stack fixture gap |
| cull-017-autopilot-review | cull-017-autopilot-review.md | Tested-Fail | VM e2e | Testability | BLOCKED-TOOLING: needs host fixture gen + submit_import_path equivalent in VM | adopts autopilot-review-commit-undo; open q: banner Dismiss may make Review unreachable for that run (one-way door) |
| cull-018-compare-survey | cull-018-compare-survey.md | Fixed | VM e2e | — | contenders toggle disabled-by-design without evaluation ranks; card warns AXPress on disabled succeeds; awaiting re-run | open q: shared monitor key semantics in compare; CONFIRMED UX inconsistency: Return uses stricter stack-guard and can silently no-op while Keep-primary button is enabled |
| cull-019-ab-compare | cull-019-ab-compare.md | Tested-Pass | VM e2e (ax+sql) | — | header/contender/keep-write verified via SQL |  |
| cull-020-pass-scope-and-undo | cull-020-pass-scope-and-undo.md | Fixed | VM e2e | Functional | double-fire fixed; stack parts remain fixture-blocked; awaiting re-run | adopts cull-pass-scope-and-undo |
| lib-001-sidebar-sections | lib-001-sidebar-sections.md | Spec'd | — | — | — |  |
| lib-002-saved-set-context-menus | lib-002-saved-set-context-menus.md | Spec'd | — | — | — | note: work-session menu is a single star-toggle whose title flips; possible dup SidebarRow.id across sections (List diffing footgun) |
| lib-003-token-grammar-fields | lib-003-token-grammar-fields.md | Spec'd | — | — | — |  |
| lib-004-bare-and-phrase-tokens | lib-004-bare-and-phrase-tokens.md | Spec'd | — | — | — |  |
| lib-005-token-readback-roundtrip | lib-005-token-readback-roundtrip.md | Tested-Pass | unit tests (LibraryQueryTokenTests 19/0, LibrarySearchIntentTests 11/0) | — | — | all round-trip + grammar assertions pass; AX spot-check pending VM batch |
| lib-006-query-field-and-tips | lib-006-query-field-and-tips.md | Spec'd | — | — | — |  |
| lib-007-add-filter-menu | lib-007-add-filter-menu.md | Spec'd | — | — | — |  |
| lib-008-chips-remove-clear | lib-008-chips-remove-clear.md | Spec'd | — | — | — |  |
| lib-009-sort-and-bar-extras | lib-009-sort-and-bar-extras.md | Spec'd | — | — | — |  |
| lib-010-result-header-save | lib-010-result-header-save.md | Spec'd | — | — | — | fiveStars queue drives a Rating>=4 chip — name/behavior mismatch to arbitrate |
| lib-011-view-toggle-routing | lib-011-view-toggle-routing.md | Spec'd | — | — | — |  |
| lib-012-grid-keys | lib-012-grid-keys.md | Spec'd | — | — | — |  |
| lib-013-library-loupe | lib-013-library-loupe.md | Spec'd | — | — | — | adopts library-loupe-no-cull-chrome |
| lib-014-map-clusters-scoping | lib-014-map-clusters-scoping.md | Spec'd | — | — | — | adopts places-map-and-geocode; verify 62e0a31 query scoping |
| lib-015-timeline | lib-015-timeline.md | Spec'd | — | — | — |  |
| lib-016-grid-badges | lib-016-grid-badges.md | Spec'd | — | — | — |  |
| lib-017-footer-density-zoom | lib-017-footer-density-zoom.md | Spec'd | — | — | — |  |
| lib-018-pagination | lib-018-pagination.md | Spec'd | — | — | — | BLOCKED fixture gap: assetPageSize=120 vs 24 smoke assets — pagination unreachable with current seeds |
| lib-019-multiselect | lib-019-multiselect.md | Spec'd | — | — | — |  |
| lib-020-token-query-filter | lib-020-token-query-filter.md | Spec'd | — | — | — | adopts token-query-filter |
| people-001-canvas-header | people-001-canvas-header.md | Spec'd | — | — | — |  |
| people-002-suggestion-cards | people-002-suggestion-cards.md | Spec'd | — | — | — | adopts people-name-face-group-happy-path |
| people-003-cluster-identity | people-003-cluster-identity.md | Spec'd | — | — | — | adopts people-cluster-by-identity |
| people-004-review-cards | people-004-review-cards.md | Spec'd | — | — | — |  |
| people-005-queue-keyboard | people-005-queue-keyboard.md | Spec'd | — | — | — | adopts people-confirm-writes-on-return |
| people-006-sheet-return-routing | people-006-sheet-return-routing.md | Spec'd | — | — | — | adopts people-naming-sheet-return-routing |
| people-007-name-selection | people-007-name-selection.md | Spec'd | — | — | — |  |
| people-008-person-cards-merge | people-008-person-cards-merge.md | Spec'd | — | — | — | open q: duplicate-name people; open q: duplicate-name people minted silently (people.name non-unique, no match-existing step) — product gap for Jesse |
| people-009-scan | people-009-scan.md | Spec'd | — | — | — |  |
| inspect-001-toggle-tabs | inspect-001-toggle-tabs.md | Spec'd | — | — | — |  |
| inspect-002-info-identity-exif | inspect-002-info-identity-exif.md | Spec'd | — | — | — | fixture gap: smoke seeds lack aperture/shutter/focal-length |
| inspect-003-sync-status-conflict-resolver | inspect-003-sync-status-conflict-resolver.md | Spec'd | — | — | — | conflict trigger inferred (fingerprint mismatch) — confirm on first live run |
| inspect-004-retry-surfaces | inspect-004-retry-surfaces.md | Spec'd | — | — | — | failure rows synthesized via SQL — proves retry wiring, not failure detection |
| inspect-005-describe-editing | inspect-005-describe-editing.md | Spec'd | — | — | — | open q: batch vs single-asset asymmetry; confirmed asymmetry: rating/flag/label batch vs keywords/caption/etc single-asset, note only near batch controls — UX question for Jesse |
| inspect-006-suggested-keywords-ocr | inspect-006-suggested-keywords-ocr.md | Spec'd | — | — | — | adopts inspector-describe-suggested-keyword |
| inspect-007-ai-verdicts | inspect-007-ai-verdicts.md | Spec'd | — | — | — |  |
| inspect-008-sidecar-write-semantics | inspect-008-sidecar-write-semantics.md | Spec'd | — | — | — | adopts rate-writes-xmp-happy-path |
| inspect-009-metadata-undo | inspect-009-metadata-undo.md | Spec'd | — | — | — |  |
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
