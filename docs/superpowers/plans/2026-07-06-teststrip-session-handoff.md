# Teststrip Session Handoff — 2026-07-06 → 07 (overnight)

## State

`main`, clean tree, **1,473 tests / 5 skipped / 0 failures**, headless gate green (13 stages), `dist/Teststrip.app` builds. Catalog schema at migration **19**. Suite grew from 994 → 1,473 in one session.

## What landed (by theme)

**Import experience (perf, root-caused + fixed, then parked):** render-path caching + publication coalescing took the 600-image import from 32s-to-feedback / never-drains to 0.75s / 3.4s / instant drain. Two probe-harness bugs fixed first (System Events activation; CF-identity AX dedup) — the old 19.7s/48.9s numbers were partly artifact.

**Culling arc (verified live on Jesse's real photos):** auto-evaluate-on-import toggle → imported-set evaluation drain → recommended-frame stack entry → survey next-group advance → completion payoff + View Picks → ✦ markers → stack list rail → Potential Picks queue → visible Keep/Toss verdict strip → Close-Ups face panel. Plus loupe 1:1 pixel-peek with on-demand full-res render.

**ML + calibration:** smile / eyes-open / eye-sharpness signals (CIDetector). Calibration study over the real corpus found the focus heuristic lived in 0–0.15 raw — every 0–1 threshold was wrong (verdict read Toss for 100% of real photos). Fixed: focus-family calibrated `min(1, raw/0.15)`, provider versions bumped to "2", thresholds re-derived, defect terms corrected, and reads filter to the current provider version so stale v1 signals can't poison queues/rankings.

**Face recognition:** face-crop embeddings + clustering + People "needs a name" one-tap confirm band. Confirm-before-write absolute (audited).

**Flagship features (Jesse-approved evening scope, all merged in migration order 15→19):**
- Duplicate detection (15): content-hash dedup + import-new-only; hash narrows, exact byte-compare before any skip (no silent drops).
- Reject relocation (16): confirm-gated move-rejects-to-folder, first origin-relocating action; sidecars travel with originals, per-file atomic, reversible via manifest ("Move back").
- Autopilot (17): design-1b proposal→review→commit→undo-all. `commitAutopilotProposals` is the ONLY write path, reachable only via explicit gestures; runs persist provisional rows only. NL Ask via opt-in local-model config, deterministic fallback. Agents panel = honest projection over real work.
- Places (18/19): GPS ingest, bounded-SQL map clustering (no annotation materialization), throttled CLGeocoder reverse-geocoding with coordinate-rounded cache behind a swappable ReverseGeocoder protocol, TOP LOCATIONS, coverage badge.

**Daily-driver essentials:** export presets (Instagram/Print/Email, PNG, byte-budget stepping, size estimate), folder tree sidebar, `person:"Name"` search + tappable People rows, session restore, EXIF completeness (aperture/shutter/focal + loupe overlay), format-honest skip reporting, heif, grid search-fallback disclosure, app icon.

**Correctness:** an adversarial review of the day's diff found **24 verified cross-feature defects** (1 critical silent photo-drop, 9 major), all fixed with regression tests. Separately, a nondeterministic-JSON-key-order bug that spuriously bumped catalog generation on reconnect (false XMP conflicts) — fixed with sorted-keys encoding.

## Open threads (for the next session / dogfood)

1. **Live-verify the new flagship surfaces.** Cards 1/2/5 passed live on the real corpus (import+auto-eval, culling arc, quit/relaunch). NOT yet driven live: autopilot review/commit/undo, Places map, reject-relocation move+move-back, duplicate-detection preview, export presets. The e2e harness + activation/AX helpers are in place; run them (console must be unlocked — locked console = zero windows).
2. **Accessibility labels.** The live battery found in-content controls expose no AX text — blocks VoiceOver AND automation. Folder-sidebar rows were labeled correctly as a pattern to follow; the rest is a dedicated pass (held all day to avoid colliding with the feature streams; now safe).
3. **Threshold sign-off.** Calibrated Keep .7 / Toss .5 / likelyPick per-kind splits are arithmetic re-derivations from the study's marginals, not a re-measure. A post-calibration corpus re-run would validate; Jesse may also want a conservative↔aggressive bias knob.
4. **Reverse-geocode network confirmation.** The CLGeocoder smoke SKIPs in-sandbox (no geo backend); real-network "PASS Paris" must be confirmed on a networked run before trusting place names.
5. **Wave-2 backlog** (docs/superpowers/plans/2026-07-06-teststrip-feature-wave-backlog.md): grid keyboard ops, batch undo grouping (partly done by autopilot Task 1), Scenes-view best-first ranking, Narrative "Potential Picks cuts 50%" parity.
6. **Known scope limits:** leftover-singles prompt in-memory; autopilot run-summary approximates stack count on restore; backup-copy failures reuse the skipped-file issue channel; person filter is name-keyed intersection.

## Cleanup done
19GB e2e corpus copy deleted. Merged agent worktrees left for the harness to reap. Episodic-memory plugin still needs a rebuild (Node ABI mismatch) — unrelated to Teststrip.
