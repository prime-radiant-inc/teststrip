# Teststrip Jesse-Shippable Alpha — Re-Prioritized Design

**Date:** 2026-07-06
**Status:** Awaiting Jesse's review
**Supersedes the sequencing (not the content) of:** `docs/superpowers/plans/2026-07-03-teststrip-usable-alpha.md`

## Goal

Jesse lives in Teststrip daily on his real photo library. "Shippable" means shippable to Jesse only: no packaging, signing, or notarization work. The dev bundle from `./script/build_and_run.sh` is the distribution.

## Decisions (Jesse, 2026-07-06)

- Foreground/focus-stealing UI automation may run freely on this machine.
- Minimal resized-JPEG export is in scope: format/quality/resize to a destination, one or two presets.
- Dogfooding starts with one large real subtree (a few thousand photos) imported in place, then graduates to the full library.
- All breadth work is frozen until after the dogfood gate: Search/Copilot/Timeline/People/Smart Collections polish, new review queues, new AI surfaces.

## Why Re-Prioritize

The 2026-07-03 plan accumulated ~200 slices and 994 passing tests, but 10 of 12 functional alpha gates remain unchecked, and nearly every live-app verification was deferred. Three findings drive the new sequencing:

1. **The first-import experience is the one measured alpha blocker, and it was deprioritized.** A 600-image foreground import showed ~19.7s to first visible feedback (budget: 1.5s) and ~48.9s until the imported photo was visible, with the preview backlog undrained after the sample window and app CPU high throughout. The backend is exonerated: the submit-only probe put the asset in the catalog in 0.12s. The cost is SwiftUI invalidation churn and preview-drain behavior. This sits outside the headless gate ("Expected-red"), so it cannot regress-detect.
2. **The app has essentially never been used in anger.** The real-corpus smoke imported three photos. The true defect list is unknown; unit tests cannot substitute for a real import of a real tree.
3. **Export does not exist**, and Jesse's daily workflow needs resized-JPEG output.

### Approaches considered

- **Continue breadth-first (status quo):** rejected — it defers the two things that decide daily usability (first-import feel, real use).
- **Dogfood-first, fix whatever surfaces:** rejected as the opener — the known import-experience defect would dominate the first session and mask everything behind it.
- **Fix the front door, then dogfood, with cheap essentials in parallel (chosen):** Phase 1 removes the known blocker, Phase 2 finds the unknown ones with Jesse in the loop, Phase 3 fills the known daily-driver gaps without blocking either.

## Phase 1 — Real-Scale First-Import Experience

The front door: import must feel alive from the first second.

- Root-cause the feedback/visibility latency before fixing (systematic-debugging). Known suspects from prior evidence: SwiftUI invalidation churn during import/preview events, preview refill gaps (recovery capped at 40 items, single-command worker dispatch), and AX-walk measurement inflation that must be separated from real user-perceived latency (verify with CPU sampling and screen-capture timing, not only AX polls).
- Fix preview-drain throughput with bounded CPU: aggressive-but-bounded refill, decide whether the synchronous helper needs batch preview commands before adding concurrency (do not add parallel original reads until disk/NAS impact is understood).
- Acceptance (600-image foreground import): first visible feedback ≤ 1.5s; imported target thumbnail visible ≤ 10s; app responsive while previews drain; drain completes without sustained UI churn or pegged CPU. Then repeat at 5,000 images: responsiveness holds, drain time scales roughly linearly.
- Verification: existing headless drain/import verifiers, submit-only probe, and the foreground AX probe — now runnable freely. Add the foreground import probe's headline metrics to the routine verification ladder so this cannot silently regress again.

## Phase 2 — Dogfood Gate

This is the alpha gate; everything else serves it.

- Prep: a one-liner launch path for Jesse against his real library subtree, in place, non-destructive, using the normal (non-sandboxed) dev build with real app-support state. Confirm catalog location is explicit and easy to back up.
- Before handing over, run the full foreground verification suite (grid activation, selection feedback, keyboard culling, imported-grid culling, evaluation) against an imported real corpus and fix what fails.
- Jesse imports a big subtree, then browses, culls, rates, keywords, and relaunches. Defects go into a ranked list; fixes ship in tight loops.
- Real-world XMP interop check happens here: Teststrip sidecars read back correctly against Jesse's existing tools, and pre-existing Adobe-style `.xmp` files in the tree behave per the ambiguity rules.
- Gate: Jesse completes import → browse → cull → rate/keyword → isolate picks → quit/relaunch with state intact, without once wondering whether the app is stuck.
- Graduate to the full library import when the subtree session is clean.

## Phase 3 — Daily-Driver Essentials (parallel with Phases 1–2)

- **Minimal export (new feature):** resized-JPEG export of the current selection/scope — format/quality/long-edge resize, destination folder, presets "Full-res JPEG" and "Web 2048px". Writes only to the chosen destination; originals and catalog untouched. No watermarking, print presets, color-space controls, or export history.
- **Honest search copy:** in Grid mode, unparsed Ask text silently becomes plain text search with no disclosure; either rename the affordance or disclose the fallback the way the Search route already does.
- **Format honesty on real trees:** videos, HEIC oddities, and long-tail files in a real library must land in skip reporting, not silence.
- **App icon:** cheap, and it matters for a daily driver.

## Frozen Until After the Dogfood Gate

Search/Copilot/Timeline/People/Smart Collections polish; new review queues; new AI surfaces; natural-language search planning; similarity-threshold tuning; Places/map; packaging/notarization; RAW long-tail fixtures (CRW/X3F); anything on the 2026-07-03 plan's breadth list not named above. Standing product decisions (non-destructive, catalog-first, no editing, no watched folders, no Lightroom migration, no iOS) all hold.

## Sequencing And Model Right-Sizing

- Phase 1 starts immediately; it is the hardest work and gets the strongest model tier.
- Phase 3 export is an independent surface and starts in parallel on a mid-tier model; copy/icon fixes are small-model work.
- Phase 2 starts the moment Phase 1 acceptance passes; triage fixes are sized per defect.
- Verification runs and mechanical checks go to small/cheap models or plain scripts.

## Risks

- The AX-probe latency numbers are partly measurement artifact; Phase 1 must establish user-perceived numbers (screen capture timing, CPU profiles) before and after, or we may fix the probe instead of the product.
- The sandboxed build diverges behaviorally (worker imports disabled under required security scope). The alpha uses the default non-sandboxed dev build; do not switch builds mid-dogfood.
- A real library will surface unknown formats, paths, and volumes; Phase 2's triage loop absorbs these rather than pre-engineering for them.

## Verification Discipline

TDD for every fix and feature per repo rules. The headless gate (`./script/verify_headless_workflows.sh`) stays the confidence ladder; foreground probes now run freely and the import-experience metrics join the routine ladder. All test failures are ours to fix regardless of origin.
