# Scenario Ledger — canonical status tracker

Single writer: the story-loop main thread. One row per capability card.
Status flow: Spec'd → Tested-Pass | Tested-Fail → Fixed → Verified.

| ID | Card | Status | Test method | Defect type | Actual result | Notes / open questions |
|---|---|---|---|---|---|---|
| cull-001-workspace-key-gating | cull-001-workspace-key-gating.md | Spec'd | — | — | — |  |
| cull-002-loupe-navigation | cull-002-loupe-navigation.md | Spec'd | — | — | — |  |
| cull-003-rating-label-flag-keys | cull-003-rating-label-flag-keys.md | Spec'd | — | — | — |  |
| cull-004-stack-promote-return | cull-004-stack-promote-return.md | Spec'd | — | — | — |  |
| cull-005-scope-cycle | cull-005-scope-cycle.md | Spec'd | — | — | — |  |
| cull-006-zoom-and-face-zoom | cull-006-zoom-and-face-zoom.md | Spec'd | — | — | — |  |
| cull-007-exif-overlay-cycle | cull-007-exif-overlay-cycle.md | Spec'd | — | — | — |  |
| cull-008-subview-keys-gcb | cull-008-subview-keys-gcb.md | Spec'd | — | — | — |  |
| cull-009-keymap-overlay | cull-009-keymap-overlay.md | Spec'd | — | — | — |  |
| cull-010-cullgrid-keys | cull-010-cullgrid-keys.md | Spec'd | — | — | — |  |
| cull-011-hud | cull-011-hud.md | Spec'd | — | — | — |  |
| cull-012-closeups-panel | cull-012-closeups-panel.md | Spec'd | — | — | — |  |
| cull-013-filmstrip | cull-013-filmstrip.md | Spec'd | — | — | — |  |
| cull-014-stack-rail | cull-014-stack-rail.md | Spec'd | — | — | — | Core action set unread — open question |
| cull-015-sidebar-sources | cull-015-sidebar-sources.md | Spec'd | — | — | — |  |
| cull-016-completion-stage | cull-016-completion-stage.md | Spec'd | — | — | — | adopts end-of-set-move-rejects |
| cull-017-autopilot-review | cull-017-autopilot-review.md | Spec'd | — | — | — | adopts autopilot-review-commit-undo |
| cull-018-compare-survey | cull-018-compare-survey.md | Spec'd | — | — | — | open q: shared monitor key semantics in compare |
| cull-019-ab-compare | cull-019-ab-compare.md | Spec'd | — | — | — |  |
| cull-020-pass-scope-and-undo | cull-020-pass-scope-and-undo.md | Spec'd | — | — | — | adopts cull-pass-scope-and-undo |
| lib-001-sidebar-sections | lib-001-sidebar-sections.md | Spec'd | — | — | — |  |
| lib-002-saved-set-context-menus | lib-002-saved-set-context-menus.md | Spec'd | — | — | — |  |
| lib-003-token-grammar-fields | lib-003-token-grammar-fields.md | Spec'd | — | — | — |  |
| lib-004-bare-and-phrase-tokens | lib-004-bare-and-phrase-tokens.md | Spec'd | — | — | — |  |
| lib-005-token-readback-roundtrip | lib-005-token-readback-roundtrip.md | Spec'd | — | — | — |  |
| lib-006-query-field-and-tips | lib-006-query-field-and-tips.md | Spec'd | — | — | — |  |
| lib-007-add-filter-menu | lib-007-add-filter-menu.md | Spec'd | — | — | — |  |
| lib-008-chips-remove-clear | lib-008-chips-remove-clear.md | Spec'd | — | — | — |  |
| lib-009-sort-and-bar-extras | lib-009-sort-and-bar-extras.md | Spec'd | — | — | — |  |
| lib-010-result-header-save | lib-010-result-header-save.md | Spec'd | — | — | — |  |
| lib-011-view-toggle-routing | lib-011-view-toggle-routing.md | Spec'd | — | — | — |  |
| lib-012-grid-keys | lib-012-grid-keys.md | Spec'd | — | — | — |  |
| lib-013-library-loupe | lib-013-library-loupe.md | Spec'd | — | — | — | adopts library-loupe-no-cull-chrome |
| lib-014-map-clusters-scoping | lib-014-map-clusters-scoping.md | Spec'd | — | — | — | adopts places-map-and-geocode; verify 62e0a31 query scoping |
| lib-015-timeline | lib-015-timeline.md | Spec'd | — | — | — |  |
| lib-016-grid-badges | lib-016-grid-badges.md | Spec'd | — | — | — |  |
| lib-017-footer-density-zoom | lib-017-footer-density-zoom.md | Spec'd | — | — | — |  |
| lib-018-pagination | lib-018-pagination.md | Spec'd | — | — | — |  |
| lib-019-multiselect | lib-019-multiselect.md | Spec'd | — | — | — |  |
| lib-020-token-query-filter | lib-020-token-query-filter.md | Spec'd | — | — | — | adopts token-query-filter |
| people-001-canvas-header | people-001-canvas-header.md | Spec'd | — | — | — |  |
| people-002-suggestion-cards | people-002-suggestion-cards.md | Spec'd | — | — | — | adopts people-name-face-group-happy-path |
| people-003-cluster-identity | people-003-cluster-identity.md | Spec'd | — | — | — | adopts people-cluster-by-identity |
| people-004-review-cards | people-004-review-cards.md | Spec'd | — | — | — |  |
| people-005-queue-keyboard | people-005-queue-keyboard.md | Spec'd | — | — | — | adopts people-confirm-writes-on-return |
| people-006-sheet-return-routing | people-006-sheet-return-routing.md | Spec'd | — | — | — | adopts people-naming-sheet-return-routing |
| people-007-name-selection | people-007-name-selection.md | Spec'd | — | — | — |  |
| people-008-person-cards-merge | people-008-person-cards-merge.md | Spec'd | — | — | — | open q: duplicate-name people |
| people-009-scan | people-009-scan.md | Spec'd | — | — | — |  |
| inspect-001-toggle-tabs | inspect-001-toggle-tabs.md | Spec'd | — | — | — |  |
| inspect-002-info-identity-exif | inspect-002-info-identity-exif.md | Spec'd | — | — | — |  |
| inspect-003-sync-status-conflict-resolver | inspect-003-sync-status-conflict-resolver.md | Spec'd | — | — | — |  |
| inspect-004-retry-surfaces | inspect-004-retry-surfaces.md | Spec'd | — | — | — |  |
| inspect-005-describe-editing | inspect-005-describe-editing.md | Spec'd | — | — | — | open q: batch vs single-asset asymmetry |
| inspect-006-suggested-keywords-ocr | inspect-006-suggested-keywords-ocr.md | Spec'd | — | — | — | adopts inspector-describe-suggested-keyword |
| inspect-007-ai-verdicts | inspect-007-ai-verdicts.md | Spec'd | — | — | — |  |
| inspect-008-sidecar-write-semantics | inspect-008-sidecar-write-semantics.md | Spec'd | — | — | — | adopts rate-writes-xmp-happy-path |
| inspect-009-metadata-undo | inspect-009-metadata-undo.md | Spec'd | — | — | — |  |
| import-001-folder-in-place | import-001-folder-in-place.md | Spec'd | — | — | — |  |
| import-002-card-copy | import-002-card-copy.md | Spec'd | — | — | — |  |
| import-003-menu-and-dev-path | import-003-menu-and-dev-path.md | Spec'd | — | — | — |  |
| import-004-new-only-dedupe | import-004-new-only-dedupe.md | Spec'd | — | — | — | adopts duplicate-detection-import-new-only |
| import-005-sidecar-on-import | import-005-sidecar-on-import.md | Spec'd | — | — | — |  |
| import-006-availability-badges | import-006-availability-badges.md | Spec'd | — | — | — |  |
| import-007-refresh-reconnect | import-007-refresh-reconnect.md | Spec'd | — | — | — |  |
| import-008-auto-cull-toggle | import-008-auto-cull-toggle.md | Spec'd | — | — | — |  |
| activity-001-icon-states | activity-001-icon-states.md | Spec'd | — | — | — | adopts activity-icon-states + quiet-activity-badge; known gap: no UI rescan trigger |
| activity-002-popover-import | activity-002-popover-import.md | Spec'd | — | — | — |  |
| activity-003-jobs-controls | activity-003-jobs-controls.md | Spec'd | — | — | — |  |
| activity-004-sources-conflicts-quiet | activity-004-sources-conflicts-quiet.md | Spec'd | — | — | — |  |
| activity-005-conflict-deep-link | activity-005-conflict-deep-link.md | Spec'd | — | — | — |  |
| activity-006-xmp-lifecycle | activity-006-xmp-lifecycle.md | Spec'd | — | — | — |  |
| worker-001-preview-lifecycle | worker-001-preview-lifecycle.md | Spec'd | — | — | — |  |
| worker-002-evaluation-verdicts | worker-002-evaluation-verdicts.md | Spec'd | — | — | — |  |
| worker-003-face-pipeline | worker-003-face-pipeline.md | Spec'd | — | — | — |  |
| worker-004-death-recovery | worker-004-death-recovery.md | Spec'd | — | — | — |  |
| worker-005-offline-reconnect | worker-005-offline-reconnect.md | Spec'd | — | — | — |  |
| worker-006-geocode-backfill | worker-006-geocode-backfill.md | Spec'd | — | — | — | network-dependent; SKIP offline |
| app-001-launch-scene | app-001-launch-scene.md | Spec'd | — | — | — |  |
| app-002-window-floors | app-002-window-floors.md | Spec'd | — | — | — | adopts workspace-minimum-width-floors |
| app-003-workspace-switching | app-003-workspace-switching.md | Spec'd | — | — | — | adopts workspace-switching |
| app-004-subview-menus | app-004-subview-menus.md | Spec'd | — | — | — |  |
| app-005-chrome-policy | app-005-chrome-policy.md | Spec'd | — | — | — | adopts ux-simplification-chrome |
| app-006-session-restore | app-006-session-restore.md | Spec'd | — | — | — |  |
| app-007-go-history | app-007-go-history.md | Spec'd | — | — | — |  |
| app-008-batch-metadata | app-008-batch-metadata.md | Spec'd | — | — | — |  |
| app-009-export | app-009-export.md | Spec'd | — | — | — | adopts export-presets-with-exif |
| app-010-move-rejects | app-010-move-rejects.md | Spec'd | — | — | — | adopts reject-relocation-move-and-back |
| app-011-find-best-shots | app-011-find-best-shots.md | Spec'd | — | — | — |  |
| app-012-autopilot-evaluate-commands | app-012-autopilot-evaluate-commands.md | Spec'd | — | — | — |  |
| app-013-diagnostics | app-013-diagnostics.md | Spec'd | — | — | — |  |
| app-014-updater | app-014-updater.md | Spec'd | — | — | — | Sparkle e2e untestable pre-release; static-only cap |
| app-015-preferences | app-015-preferences.md | Spec'd | — | — | — |  |
| app-016-menu-coverage-invariants | app-016-menu-coverage-invariants.md | Spec'd | — | — | — | unit-test method |
| dev-001-build-and-run-modes | dev-001-build-and-run-modes.md | Spec'd | — | — | — | usage drift: --real-corpus undocumented |
| dev-002-seed-variants | dev-002-seed-variants.md | Spec'd | — | — | — |  |
| dev-003-vm-harness | dev-003-vm-harness.md | Spec'd | — | — | — |  |
| dev-004-package-release-dry-run | dev-004-package-release-dry-run.md | Spec'd | — | — | — |  |
| dev-005-package-release-signing | dev-005-package-release-signing.md | Spec'd | — | — | — | needs Developer ID cert locally |
| dev-006-ax-drive | dev-006-ax-drive.md | Spec'd | — | — | — |  |
| dev-007-reset-isolated | dev-007-reset-isolated.md | Spec'd | — | — | — |  |
| dev-008-sample-downloads | dev-008-sample-downloads.md | Spec'd | — | — | — | network |
| dev-009-bench-seeds | dev-009-bench-seeds.md | Spec'd | — | — | — |  |
| dev-010-bench-benchmarks | dev-010-bench-benchmarks.md | Spec'd | — | — | — |  |
| dev-011-release-ci | dev-011-release-ci.md | Spec'd | — | — | — | needs tag + 7 secrets; static-only cap |
| dev-012-verifier-gates | dev-012-verifier-gates.md | Spec'd | — | — | — | KNOWN-STALE: verify_evaluation, verify_card_import_path |
