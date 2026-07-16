# Culling a batch in Teststrip — tutorial for the reworked cull mode

> Design-spike artifact (2026-07-16). This tutorial is written as if the mode
> already exists. It is the UX contract the three HTML mockups in this
> directory implement — they vary the *presentation*, not this grammar.
> Synthesized from `narrative-research.md`, `teststrip-signals-inventory.md`,
> and `user-panel.md` (16 consensus demands, 3 adjudicated divergences,
> 5 traps).

---

## 1. What a cull run is

You cull in **runs**. A run takes any batch — a search result, an import, an
album, a folder — and walks you through it one decision at a time until every
photo carries *your* decision. Nothing in a run is destructive: picks and
rejects are flags in the catalog. Moving rejected files anywhere is a separate
ceremony you perform after the run, never during it.

Teststrip groups the batch into **stacks** before you start. A stack is a
burst — frames shot seconds apart, or near-duplicates that look alike (reshoots
of the same print, RAW brackets). A photo that stands alone is simply its own
stop on the walk. RAW+JPEG pairs are already one photo everywhere in Teststrip,
so you never cull the same exposure twice.

**If your batch has no bursts at all** — a lifetime of one-shot family photos —
the mode doesn't degrade, it just gets simpler: no stack chrome appears, and
every navigation key walks photo-by-photo. Same keys, same rhythm. Culling a
90s shoebox archive is a first-class use of this mode, not a fallback.

## 2. Starting a run

From any batch, press **⌘R** (or the **Cull this batch** button that sits on
every search result and import summary). The start card shows:

- **What's in the batch**: `211 photos · 63 stacks (batch is 34% bursts)`.
- **Lens** (default **Everything**): optionally narrow the run to
  **Potential Picks** or **Likely Issues**. Narrowing is loud: the run header
  will permanently read `Showing 96 of 211 — 115 hidden by lens`, and the
  completion summary reports the hidden count. Everything is one click away.
- **Auto-advance** (default on) and **Land on recommended frame** (default on).

Press **Return** to begin. Traversal is always **capture order** — the AI
never reorders your walk; it only marks frames *within* a stack.

## 3. Reading the screen

You work one burst at a time, then the next. The screen is organized around
that, with one home per fact — nothing renders twice:

- **The burst rail** (left): the current stack only — your working set,
  generous thumbs worked top to bottom, tinted along a best-to-worst gradient
  so "how much good material is left in this burst" is glanceable. The
  recommended frame wears **✦**; thumbs carry your decisions (P/X) and any
  tentative AI flags (**✨**, see §6). Stacks are auto-grouped and labeled by
  machine facts only (`RR14_0412–0417 · 6 · 14:02`) — nothing is pre-named.
  On a standalone photo the rail quiets down to that single thumb.
- **The stage** (center): the photograph, nothing else. It is always rendered
  at decision quality before any committing key will act — if you outrun the
  renderer you see an explicit "rendering…" shimmer, never a silent low-res
  proxy.
- **The faces & reads panel** (right): a report card per detected face,
  ordered by prominence — face crop, one traffic-light roll-up dot, an
  identity chip when the person is recognized, and chips for **eyes ·
  expression · focus · facing · light**. Judgments are context-aware: eyes
  shut during a kiss reads *shut · OK* and rolls up green; a mid-blink rolls
  up red. Background faces collapse to a dot row (**F** expands them).
  Below the faces, the whole-frame read: `Keep read 82% · sharpest in stack ·
  eyes open` — claims are score-gated, a frame with no signals says **No
  read yet**, and when a burst's top frames sit within the signal's noise
  floor the rail says **too close to call** across them and awards no ✦.
  Honest empty states hold the space: "no faces", "faces too small to read".
- **The run strip** (bottom): every stop in the batch — other bursts as
  count pills, standalones as small thumbs, the current stop highlighted,
  finished stops checkmarked. This is the "how much is left in the whole
  run" glance.
- **The counter** (always visible, beneath the strip):
  `47 of 211 · stack 12 of 63 · frame 3 of 17`, plus filename and a run
  progress bar that counts only *your* decisions — tentative AI flags never
  fill it.

## 4. The keys

Everything below works with either hand position — arrows, or home row.
No pointer is ever required; every hover affordance has a key twin.

**Move**

| Key | Action |
|---|---|
| `→` / `L` | Next stack (lands on its ✦, or frame 1 if no recommendation) |
| `←` / `H` | Previous stack |
| `↓` / `J` | Next frame in this stack |
| `↑` / `K` | Previous frame in this stack |
| `Space` | Skip — advance without deciding, always decision-free |

On a standalone photo there is no "within," so `↓`/`J` and `↑`/`K` simply walk
to the next/previous photo — no dead keys, one grammar.

**Decide**

| Key | Action |
|---|---|
| `P` | Pick this frame |
| `X` | Reject this frame |
| `U` | Clear the decision (back to undecided) |
| `Return` | **Commit the stack**: keep this frame (plus any you already picked), reject every still-undecided sibling, jump to the next stack. On a standalone photo: pick it and advance. |
| `⌘Z` | Undo — a stack commit undoes as **one unit** |

With auto-advance on, `P`/`X` move you to the next *undecided* frame in the
stack; deciding the last one carries you to the next stack. `Return` is inert
until the frame on stage has actually rendered at decision quality — speed
never launders a thumbnail into a decision.

**Grade** (optional, any time): `1`–`5` stars, `0` clears; `6`/`7`/`8`/`9`/`V`
color labels, `-` clears color.

**Look closer**: `Z` toggles 100% zoom — position and zoom level stay locked
while you flip frames within a stack, so you compare the same eye across nine
frames. `Shift+Z` jumps the zoom to the nearest face; press again to cycle
faces. `I` cycles the EXIF overlay. `/` toggles the faces panel; `F` expands
the background-face dot row into full report cards.

**Run control**: `A` toggles auto-advance. `S` cycles the visible scope
(everything / undecided / picks / rejects). `G`/`C`/`B` drop into grid,
compare, or A/B for the current stack — `Esc` comes back. `?` shows the key
map. All bare keys are remappable.

## 5. Working a burst

1. `→` lands you on the ✦ frame. The read pill says *why* it's recommended —
   claims are score-gated, so "sharpest" appears only when the focus signal
   genuinely separates the frames.
2. Glance at the close-ups: all eyes open? Blinkers show a red eye badge —
   contextually judged, so a kiss with closed eyes reads green, a mid-blink
   reads red.
3. Agree? **`Return`.** The stack collapses — kept frame flagged pick, the
   rest rejected, toast `Kept 1 · rejected 16`, and you're on the next
   stack's ✦. One key per burst is the blaze-through cadence: a
   6,000-frame wedding is ~700 Returns, not 6,000 decisions.
4. Not sure? `↓`/`↑` flip through frames — zoom stays locked — and `P`/`X`
   frames individually. Want two keepers? Pick both, then `Return` keeps
   everything you picked and rejects the rest.
5. Machine says **too close to call**? It means it: the top frames are
   indistinguishable to the signals. `C` throws them into Compare, or `B`
   pits two head-to-head (`,` / `.` to keep A or B).

## 6. What the AI does — and what it never does

- **Reads are advice.** The pill, the badges, the ✦, the rail gradient — all
  informational. The walk order never changes; nothing is hidden unless you
  chose a lens, and then the hiding is counted on screen.
- **Tentative flags are visible and inert.** Autopilot may pre-flag obvious
  burst losers with **✨X** (and likely keepers **✨P**). They render as ghost
  decisions, but they count for nothing: not in your progress bar, not in the
  Picks set, not in export, never in move-to-trash. Your `P`/`X`/`U` on a
  frame simply replaces its ghost.
- **Confirming is explicit and legible.** The only place tentative flags
  become yours is the **Review AI suggestions** surface at the end of the run
  — it lists exactly what would be confirmed, grouped by stack, before you
  accept any of it. No navigation or decision key ever silently confirms.
- **Honesty is enforced.** No signal, no verdict ("No read yet"); weak
  separation, no ranking ("too close to call"). A ✦ the mode can't defend is
  a ✦ it doesn't award.

## 7. Finishing a run

When the last stack is decided the **completion summary** appears:

```
Run complete — June 14 · Red Rocks
  Picked 214 · Rejected 1,682 · Undecided 47 · Skipped 12
  Never viewed 0 · ✨ awaiting review 96 · hidden by lens 0
```

Each line is a one-key jump (`1`–`6`) back into a scoped mini-run — clear the
undecideds, audit the never-viewed, open **Review AI suggestions**. From here,
and only here, the ceremonies: **Export picks…**, **Move rejects…** (to a
folder or Trash — with a manifest, undoable, and tentative-✨-only rejects are
*excluded and say so*), **Save picks as set**.

## 8. Leaving and coming back

A run persists everything — scope, position, panel state, every decision.
Quit mid-burst; reopening the batch offers **Resume run — 62% decided** and
puts you on the exact frame you left. Decisions made outside the run (in the
Library, on another day) are respected: the run counts them and walks you to
what's still undecided.

---

## Appendix: design decisions this tutorial locks in

| Decision | Source |
|---|---|
| Capture-order spine; AI marks, never reorders | Panel demand 2 (rank-order sort rejected) |
| One grammar with and without bursts; no dead keys on singles | Demands 1, 7; trap 1 |
| Land-on-✦ default with honest fallback ("no read yet" → frame 1) | Demand 5; divergence 1 |
| `Return` = stack commit, inert until rendered, one-unit undo | Demand 4; trap 3 |
| `Space` always decision-free | Demand 3 |
| Lenses opt-in with permanent shown/hidden accounting | Demand 8; trap 2 |
| ✨ tentative never counts as decided / never exports / never trashes | Demands 9, 10; existing provenance invariant |
| Score-gated rationale; "too close to call" over fabricated #1 | Demand 13; trap 5 |
| Whole-stack prefetch + next landing frame; explicit shimmer | Demand 11 |
| Zoom lock across within-stack navigation | Demand 12 |
| Rejects are flags; relocation is a post-run ceremony | Demand 14 |
| Exact resume; completion summary with one-key jumps | Demand 15 |
| Triple counter, stolen from Narrative verbatim (adapted) | Research §2/§11 |
| Rank-gradient stack rail | Research §11 |
| Context-aware eye judgment (kiss ≠ blink) | Research §4a |

## Spike outcome (2026-07-16)

Four mockups were built and played with; **mockup-e-workstation-v3.html is
the validated direction** ("this feels reasonable"). The two feedback rounds
that got there:

1. Round 2 killed mockup A's all-bursts left rail (wrong emphasis — "when
   I'm working through a group of photos, I should be all-in on those
   photos"), banned curated-looking stack names (machine facts only), and
   imposed one-home-per-fact deduplication.
2. Round 3 settled the layout: **current burst on the left rail** (the
   working set — "you work in a burst at a time, then the next"), **run in
   the bottom strip**, and **per-face report cards** on the right (eyes ·
   expression · focus · facing · light, prominence-tiered, identity chips,
   traffic-light roll-ups). §3 above reflects this.

Mockups A–C remain as the road not taken (A's original three-pane density,
B's immersive minimalism, C's all-frames-at-once burst board). C's spatial
comparison is still a candidate for the `C` compare surface *within* the
workstation direction.

**Open questions carried to the real design:**

- `Return` on a frame you already rejected: force-pick (current tutorial
  reading), inert, or warn?
- Should the commit toast double as a ~2s inline undo affordance? (The mass
  reject reads as violent when all siblings are visible at once.)
- Ambient visibility of ✨ ghosts on collapsed/undecided stops — does
  tentative-AI presence deserve one persistent pixel of chrome?
- "Any red faces in this frame?" needs answering without scrolling the face
  panel on 8-face group shots — pinned dot-summary row, or roll-up dots on
  the burst-rail thumbs (which would also make "which frame has no red"
  scannable per burst).

**Engineering implications noted along the way:** per-face display needs
per-face signal rows persisted (today smile/eyes/eyeSharpness aggregate
per-image); facing/head-pose is stock-derivable (Vision yaw/roll/pitch);
context-qualified eye judgment and occlusion are new model surface; no
saliency fallback exists for faceless frames; loupe prefetch (±1 frame) is
too shallow for whole-burst blaze-through.
