# Shared spec for the three culling mockups

All three mockups implement `tutorial.md`'s grammar over THIS dataset, so they
can be compared like-for-like. They differ in layout and interaction
philosophy only.

## Ground rules

- One **self-contained** `.html` file each. No external requests of any kind
  (no CDNs, fonts, images). Must work opened via `file://` in Safari and
  Chrome. Inline CSS/JS only.
- Dark, photo-app aesthetic (near-black stage, restrained accent colors).
  These are design-spike toys — polish the *feel of the loop*, not pixel art.
- **Fake photos**: render each frame as a CSS/SVG placeholder — a distinct
  hue family per stack, a big frame label (e.g. "Kiss · 6/9"), simple shapes
  or emoji suggesting the content. Communicate the machine's focus read
  physically: sharp frames crisp, soft frames with a CSS `blur()` of 1–3px.
  Closed eyes = a visible badge on the face chip/dot, not just data.
- **Working keyboard** per the tutorial: `←→↑↓`, `H L J K`, `P X U`,
  `Return` (stack commit: keep current + already-picked, reject undecided
  siblings, advance; pick+advance on singles), `Space` (skip, always
  decision-free), `1–5`/`0`, `Z` (fake 2× zoom, position sticky across
  within-stack nav), `/` (close-ups toggle where applicable), `A`
  (auto-advance toggle), `S` (scope cycle), `?` (key overlay), `⌘Z` or
  `Backspace` (undo; stack commit undoes as one unit), `Esc` (close overlay).
- **Honest states are mandatory**: land-on-✦; "No read yet" for unscored
  frames (never a fake verdict); "too close to call" for the bouquet-toss
  top-3 (no ✦ awarded there); ✨ ghost flags render distinctly and never fill
  the progress bar.
- **Always visible**: triple counter (`N of 35 · stack N of 9 · frame N of M`),
  user-decision-only progress bar, auto-advance state.
- **Return is inert until "rendered"**: simulate with a ~250ms shimmer when a
  frame first appears; Return during shimmer flashes the shimmer, does not
  commit.
- **Completion summary** when all stacks are decided: picked / rejected /
  undecided / skipped / never viewed / ✨ awaiting review, plus stub buttons
  (Review AI suggestions — opens a list of the ✨ ghosts; Move rejects… — stub
  noting tentative-only rejects excluded; Export picks — stub).
- A small persistent hint bar (dismissible with `?`) so Jesse can play
  without reading the tutorial first.

## The dataset (identical in all three)

Batch: **"June 14 — Red Rocks wedding + archive strays" · 35 frames · 9 stops**
(4 multi-frame stacks, 5 standalone photos), in capture order:

1. **Stack "Lineup" — 6 frames** (ceremony group, 8 faces, teal hues).
   Focus .82/.85/.88/.79/.84/.81; eyes-open 1/.75/1/.5/.88/1.
   **✦ frame 3** — "sharpest · all eyes open". Frame 4 carries **✨X**
   (autopilot: "2 eyes shut · softer"). Read pills per frame (e.g. f3
   "Keep read 84%", f4 "Toss read 62%").
2. **Single "Venue wide"** (no faces, amber). Focus .90 → "Keep read 78% ·
   sharp". No close-ups (no faces).
3. **Stack "First kiss" — 9 frames** (rose hues, 2 faces). **✦ frame 6** —
   "peak moment · eyes-shut OK (kiss)" — the context-aware eye judgment demo:
   closed eyes here read GREEN. Frames 8–9 soft tail, both **✨X**.
4. **Single "Rings detail"** (violet, no faces). **Unscored → "No read yet"**.
5. **Stack "Bouquet toss" — 12 frames** (sky hues, action). Frames 5/6/7
   focus .84/.85/.84 → **"too close to call — 5·6·7", no ✦**; frames 9–12
   motion-blur tail (blurry placeholders), all four **✨X**. Frame 1 ✨P.
6. **Single "Grandma · scan 1974"** (sepia, 1 face). Focus .55 → "Mixed read
   55%".
7. **Stack "Scan reshoots" — 3 frames** (sepia, near-identical; grouped by
   visual similarity, not time). **Unscored → "No read yet", lands frame 1,
   no ✦** — the archive near-dupe story.
8. **Single "Phone snap 2009"** (green, 3 faces, slightly soft). "Toss read
   58% · soft".
9. **Single "Portrait — Ted"** (slate, 1 face, eyes shut). **"Toss read 61% ·
   eyes shut"** — deliberately a photo a human may keep anyway; overriding
   the machine should feel completely frictionless.

Seed ✨ ghosts exactly as listed (8 total: 7 ✨X — Lineup f4, Kiss f8+f9,
Bouquet f9–f12 — plus 1 ✨P, Bouquet f1). All 35 frames start undecided by
the user.
