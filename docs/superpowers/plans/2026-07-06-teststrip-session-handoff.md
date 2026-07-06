# Teststrip Session Handoff — 2026-07-06 (evening)

## State

`main`, clean tree, 1,206 tests / 5 skipped / 0 failures, headless gate green, `dist/Teststrip.app` built with icon. Suite grew from 994 to 1,206 today; every merge was TDD'd and full-suite-verified.

## What landed today (by merge, all on main)

- **Import experience:** render-path caching + publication coalescing; 600-image import measured at 0.75s first feedback / 3.4s target visible / instant drain (was 32s / never-drains). Probe harness itself fixed first (System Events activation, CF-identity AX dedup) — old 19.7s/48.9s numbers were partly artifact.
- **Export:** popover with selected/visible/current-scope, Full-res + Web 2048px presets, resize/quality, EXIF/IPTC carry checkbox (orientation reset + dimension-tag handling proven by test).
- **XMP interop (dogfood-critical):** Jesse's 79 real `frame.xmp` sidecars bind via `photoshop:SidecarForExtension` and update in place (no dual sidecars); unparsable sidecars surface as conflicts with Use Catalog recovery; `xmp:Rating="-1"` reads as reject flag.
- **Culling ML:** smile / eyesOpen / eyeSharpness signals (CIDetector provider `core-image-faces`), surfaced in verdict pill, stack rationale, survey badges, compare lanes.
- **Culling arc:** import-plan auto-evaluate toggle (default ON), imported-set evaluation drain, recommended-frame stack entry, survey next-group advance, completion payoff → View Picks, ✦ markers, stack list rail, Potential Picks queue, verdict strip, Close-Ups face panel.
- **Face recognition:** face_observations/person_faces/dismissed_faces (migration 14), face-crop feature prints, suggestion builder (centroid match then clustering), People "needs a name" one-tap confirm band. Confirm-before-write absolute.
- **Calibration (important):** measured study over the real corpus (`docs/superpowers/plans/2026-07-06-calibration-study.md`) showed the focus heuristic lives in 0–0.15 raw — every 0–1-scale threshold was wrong (verdict read Toss for 100% of real photos). Fixed: focus-family calibrated `min(1, raw/0.15)` with provider version bumps to "2", thresholds re-derived (verdict Keep .7/Toss .5; per-kind likelyPick focus .8 / aesthetics .65 / faceQuality .45; focus defect .4; motionBlur defect removed; eyesOpen defect only at 0.0). Old persisted signals are version-1 raw scale — re-evaluate any pre-existing dev catalog before trusting reads.
- **Culling polish:** filmstrip reject dimming + decision bars, stack-chip flaw dots, leftover-singles prompt, nav chevrons + keyboard legend, honest brightness-delta lane copy (not "EV"), manual-cull session dedup.
- **Focus compare:** Top-3 contenders mode, rank chips, honest comparative verdict copy, Keep #1 & #2.
- **Card import:** organize-into `YYYY/YYYY-MM-DD/` dated folders (default ON, matches Jesse's filing), optional second-copy backup with per-file failure isolation, worker-protocol carriage, dated-folder basename-collision conflict fix. Rename patterns deliberately excluded (catalog-identity implications — needs Jesse).
- **Fixes:** sorted-keys metadata JSON (nondeterministic key order was intermittently bumping catalog generation on reconnect → false XMP conflicts); EXIF aperture/shutter/focal at ingest + loupe overlay; format-honest video/unknown skip reporting; heif; grid search fallback disclosure; app icon.

## Open threads

1. **Live verification is the gate.** Nothing today was verified in the running UI — the console was locked (GUI apps launch windowless; see memory `locked-console-no-windows`). An unlock watcher + five e2e scenario cards are staged (`scratchpad/e2e-cards.md`, 19GB real-corpus copy ready). Run the battery on unlock, fix what it finds. Foreground probe suite + 5,000-image scale run also queued.
2. **Threshold sign-off:** calibrated splits are arithmetic re-derivations; a corpus re-run post-calibration would validate (calibration agent's caveat). Jesse may also want different Keep/Toss aggressiveness.
3. **Jesse decisions pending:** rename patterns on import; second-copy-inside-library-root rule; Copilot/Places/NL-search scope; whether Space rebinds to zoom-to-face.
4. **Known scope limits:** leftover-singles prompt is in-memory (doesn't survive relaunch); `canRequestAssetEvaluations` stales during pure drain (moot at current drain speed); backup failures reuse the skipped-file issue channel ("Skipped <file>" titling).

## Cleanup notes

Worktrees under `.claude/worktrees/agent-*` can be pruned once branches are confirmed merged (`git branch --merged main`). The e2e corpus copy (19GB) at scratchpad/e2e-corpus should be deleted after the live battery runs.
