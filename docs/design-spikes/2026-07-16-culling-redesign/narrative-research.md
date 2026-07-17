# Narrative Select — Culling UX Teardown

Researched 2026-07-16 for the Teststrip culling-mode redesign. This goes deeper
than `docs/product/narrative-select-reference.md` (2026-07-06, a feature-name
mapping table) — it documents the actual interaction design, screen layouts,
badge taxonomy, and keyboard model, sourced from narrative.so marketing pages,
help.narrative.so support articles, and real in-app screenshots pulled from
their marketing videos. Written so a designer can work from it without
visiting the site.

Sources fetched: `narrative.so/select`, `/select/scenes-view`,
`/select/the-close-ups-panel`, `/select/face-assessments`,
`/features/ai-culling-first-pass`, plus ~14 help.narrative.so articles
(keyboard shortcuts, scenes, ratings, filters, survey mode, loupe view,
preferences, people filter, focus-score filter, shipping to Lightroom/Capture
One). Screenshots came from Mux-hosted product-demo videos embedded in the
marketing pages (frame-grabbed via the Mux thumbnail API), not from Contentful
marketing photography — they show the real app chrome, not mockups.

---

## 1. The workflow model end-to-end

Narrative's own framing is three named stages, shown as a horizontal flow on
the homepage: **Import and cull → Ship and Edit → Adjust and improve.**

1. **Import**: point Narrative at a card/folder; RAWs decode and preview
   instantly (their claim: "import 5,000+ RAWs in under 3 seconds" to first
   browsable state — see §7). No separate "generate previews" wait step from
   the user's point of view.
2. **Cull**: this is the mode this teardown is about. It happens inside one
   project ("shoot"). The user moves through **Grid View**, **Scenes View**,
   and **Loupe View** (the single-image view), applies ratings/rejects,
   filters down using AI assessments, and uses the Close-Ups panel to vet
   faces without leaving the current frame.
3. **Ship + Edit**: a single button (`⌘E`) opens a shipping dialog that sends
   the surviving/rated selection to Lightroom Classic/CC, Photoshop, or
   Capture One (Mac), optionally applying an AI edit preset in the same step.
   Rejected images are never moved/copied out of Narrative.

**Mental model of a "scene":** a scene is an automatically-detected burst /
near-duplicate cluster — time-adjacent frames of the same setup (portrait
poses, a detail shot repeated, a group photo taken several times to get
everyone's eyes open). Scene detection runs automatically on project creation
("takes a minute or two"); there is no manual grouping step. Every scene is
pre-ranked by their assessment engine so the best frame in the cluster is
first when you open it — the product's core promise is "stop comparing 14
near-identical frames yourself; we already sorted them."

Photos that don't cluster with anything (unique establishing shots, uniquely
framed candids) still show up in Grid View and Scenes View as singleton
"scenes" of 1 — nothing is hidden or orphaned; scene grouping is additive
organization on top of the same flat photo pool, not a separate destination.

**How you move through 2,000+ wedding photos:** the loop is Scenes View for
between-scene triage (spend ~1 decision per burst) dropping into Loupe View
only for scenes worth a closer look, with the Close-Ups panel open whenever
faces matter (i.e. most of a wedding shoot). Filters (Potential Picks, Focus
Score, People) are used to prune volume before or during this pass, not after.

---

## 2. Scenes View

Entered with **`S`** (there's also a Grid View `G` and a Loupe/single-image
view `E` — three named "workspaces", not stacked panels).

- **Formation**: automatic, time/visual-similarity clustering, runs once at
  project load. Not user-configurable beyond arrow-key navigation behavior in
  preferences.
- **Default order**: scenes are sorted in **"Rank Order,"** driven by their
  First Pass assessments — this puts scenes containing more/better potential
  picks first (this is a *scene-level* sort; independently, sort can also be
  Capture Time). Within a scene, frames are ranked by their pick assessment
  so the best frame is first.
- **Navigation**: `←`/`→` jump to the first image of the previous/next scene.
  `↑`/`↓` (or `⌘↑`/`⌘↓` — configurable in Preferences) move frame-to-frame
  *within* the current scene without leaving it. Jumping scenes shows a
  transient toast, e.g. **"Scene 2 of 4"** — confirmed in the demo-video
  frames (bottom-center overlay, black pill, ~1.5s fade). This toast is the
  *only* between-scene position indicator that isn't buried in a sidebar.
- **Batch select**: `⌘+Shift+click` (Mac) selects every image inside a scene
  in one gesture — used to bulk-apply a rating/reject to a whole burst.
- **Left-rail scene stack (Loupe View)**: when you're inside a scene, the
  left sidebar shows a vertical filmstrip: collapsed scene thumbnails above
  and below, and the **current scene expanded inline** into a numbered
  sub-list (1, 2, 3… up to the scene's frame count). Each sub-list row has a
  **colored left-edge bar** — this is the First Pass category color (see
  §4), not a star/flag color. In the screenshots this reads as blue for
  early/better-ranked frames and red for the tail of the stack — i.e. the
  rank ordering is made physically visible as a top-to-bottom color gradient
  in the sidebar, so "how much good material is left in this scene" is
  readable at a glance without opening each frame.
- **Grid View outline**: in Grid View, a scene cluster is shown as a group of
  thumbnails outlined with a colored border (salmon/orange in the tutorial
  overlay frame, purple/violet when a specific rank position is being
  called out) with a hover tooltip like **"Potential pick ranked 1 of 33
  (filtered view currently showing 13)"** — confirms Grid View is aware of
  both scene membership and current filter state simultaneously, and surfaces
  the rank number directly in a tooltip rather than making you infer it from
  position.
- **Status bar** (bottom of window, always visible): three counters —
  *project position* / *scene position* / *frame-in-scene position*, e.g.
  `14 of 42 · 2 of 4 · 1 of 13` — plus the current filename. This is the
  single source of truth for "where am I" and matches Jesse's reference
  screenshot (`47 of 211 · 2 of 15 · 17 of 17`) exactly.

---

## 3. Close-Ups Panel

Toggled with **`/`** or **`.`** (face mode) — a separate modifier combo
(`⌘/` or `⌘.`) opens it in **Pan Mode**. Panel size is adjustable with
`⌥+`/`⌥-`.

- **Two modes, auto-selected**: **Face Mode** when faces are detected (the
  common case for a wedding/portrait shoot) — crops and enlarges every
  detected face. **Pan Mode** when no faces are detected — instead shows a
  zoomed, draggable crop of the image center with a minimap in the corner, so
  the panel is never empty even on detail/landscape shots. (Their "Key
  Element Detection" feature — saliency-based subject finding instead of
  faces — feeds this same panel for non-portrait frames.)
- **Capacity and ordering**: up to **24 faces**; beyond that it picks "the
  most main subjects" to show first — i.e. faces are ranked by
  prominence/importance in the frame (likely size + centrality), not by
  left-to-right position or detection order.
- **Layout**: a grid of face crops beside the main loupe image, right-hand
  side. Column count reflows with face count / panel width — 2-wide for an
  8-person bridesmaid lineup, 3-wide for a 12-person group shot (confirmed in
  two different screenshots). Not a fixed 2-column grid.
- **Per-face badges**: each crop carries two independently-colored badges —
  an **eye/face-assessment badge** (eye icon + numeric score, e.g. green eye
  + "7") and a **focus-assessment badge** (separate icon + numeric score,
  e.g. green "6" = "Good Focus"). Hovering (or presumably tapping) expands
  both into a stacked two-line text tooltip, e.g.:
  ```
  👁 Eyes Mostly Open (Group Photo)
  6  Good Focus
  ```
  The **"(Group Photo)" qualifier is load-bearing** — it shows the eye
  assessment is threshold-adjusted for group shots vs. solo portraits (a
  strict standard for a couple's portrait would flag half of every group
  photo). See the full label taxonomy in §4.
- **Spacebar zoom**: `Space` zooms the main image to a preset level (default
  100%); if faces exist it zooms straight to the *primary* subject's face,
  and `←`/`→` then cycles between detected faces without leaving zoom. `Z`
  does the same zoom toggle but explicitly ignoring faces (useful for
  checking background/prop sharpness). Holding `Space` (rather than
  tapping) gives a momentary zoom that releases on key-up — a "peek" gesture.
  `Esc` resets the loupe view.
- **As you move between frames**: the Close-Ups panel re-populates per
  current frame — it is scoped to "faces in the image currently in the
  loupe," not a fixed set carried over between frames. Moving to the next
  frame in a scene re-crops/re-ranks/re-scores automatically.
- **Right-edge tool rail** (outside the close-up grid, always visible):
  small vertical stack of icon buttons — people, a crosshair/target icon,
  an image icon, a crop icon — plus, below them, a couple of colored
  **numeric pills** (seen as a yellow "5" and a red "!" in the reference
  screenshot). These read as global summary counts (e.g. worst focus score
  present, count of a specific rating) rather than per-face data — exact
  semantics weren't documented in help articles, worth low-fidelity cloning
  only if we independently verify the meaning.

---

## 4. Assessments (the core AI signal set)

Narrative names three separate assessment families and renders each
differently:

### 4a. Face Assessments (per-subject, shown as dots on the loupe + badges in Close-Ups)

This is the deepest part of their system — **18 distinct labeled states**
(they say "over 17… and we're adding to that all the time"), each mapped to
one of 5 severity colors. Full taxonomy, extracted directly from their legend
graphic (`images/first-pass-features.png`):

| Color | Label |
|---|---|
| Dark green | Eyes Fully Open |
| Dark green | Glasses |
| Green | Eyes Mostly Open |
| Green | Pose / Look Down |
| Green | Kissing + Eyes Shut |
| Green | Laugh + Eyes Shut |
| Green | Very Close |
| Green | Facing Away |
| Green | Smiling + Eyes Shut |
| Green | Smiling + Eyes Open |
| Yellow | Laugh + Eyes Open |
| Yellow | Kissing + Eyes Open |
| Yellow | Eyes Partially Open |
| Yellow | Eyes Obscured |
| Yellow | Squinting* |
| Orange | Eyes Barely Open |
| Red | Mid-Blink |
| Red | Eyes Closed |

Key design point: **this is not a raw eyes-open/closed detector** — it's
context-aware. "Kissing + Eyes Shut" and "Smiling + Eyes Shut" score *green*
(good) because closed eyes are expected/desirable in that context, while
plain "Eyes Closed" or "Mid-Blink" score *red*. "Very Close" and "Facing
Away" are compositional context flags (not directly about eyes) folded into
the same badge system. Group-photo thresholds are explicitly looser (the
"(Group Photo)" qualifier seen in the Close-Ups tooltip), presumably because
you're gambling on N pairs of eyes at once and a strict solo-portrait bar
would reject nearly every group frame.

**On the loupe (main image)**: each detected face gets a small colored dot
positioned near the face/collar (not literally on the pupils) — green/
yellow/red, sometimes with a black text-label tooltip on hover ("Very
Close", "Kissing + Eyes Closed"). This is shown for *every* detected face in
frame, including background guests at a recessional shot, not just the
nominal subject(s) — so a crowd shot can carry a dozen small dots.

**In the Close-Ups panel**: same signal, rendered as an eye-icon badge +
score chip (1–10 scale) in the bottom corner of each face crop, expandable
to the full text label on hover.

**Preferences control**: users can recolor the traffic-light palette, choose
how much detail shows in the Close-Ups panel (icons only vs. icons+text),
toggle whether background/incidental faces are scored at all, and set
whether assessment icons show in Face Zoom.

### 4b. Focus Assessments (per-subject, and whole-image)

- A **1–10 focus score**, computed per detected subject, factoring "the
  focus of each individual subject, how important those subjects are within
  the scene, and the overall context of the image" — i.e. it's a
  subject-weighted score, not a naive whole-frame sharpness map.
  - Text labels seen in the UI: **"Good Focus"**, **"Soft Focus"** (both with
    their numeric score attached).
- Shown: as the second badge/line in the Close-Ups panel (paired with the
  eye badge), as a colored line/underline near the face on the loupe per the
  help docs, and as a filterable **Focus Score** in the toolbar/filter bar
  (see §6).
- **Best-in-scene indicator**: a small blue icon on the thumbnail's focus
  badge marks the image with the highest (or tied-highest) focus score
  *within its scene* — i.e. focus score doubles as an intra-scene relative
  signal, similar in spirit to Image Assessments.
- Images with no detected face get **no focus score at all** (there's an
  explicit "No Focus Score" filter bucket) — focus assessment is currently
  face-anchored, not a generic global sharpness metric.

### 4c. Image Assessments ("First Pass" — relative in-scene quality ranking)

This is the whole-frame, whole-scene-relative ranking that drives Scenes
View ordering and the thumbnail hexagon badges. Two versions coexist:

**Original First Pass (3 categories)** — colored hexagon badge on every
thumbnail:
- 🔵 Blue = **Potential Pick**
- ⚪ Grey = **Unlikely Pick**
- 🔴 Red = **Undesirable**

**AI First Pass+ (beta, 5 categories)** — moves from purely relative to more
objective ranking:

| Color | Category | Meaning (their copy) |
|---|---|---|
| Dark blue | Best in scene | "Likely the best image from the scene" |
| Light blue | Above average | "No major issues detected — this could be a good option" |
| Grey | Average | "No major issues detected, but there are probably better options" |
| Pink | Below average | "Some issues detected; better options are very likely available" |
| Red | Undesirable | "Significant issues detected; almost certainly a poor choice" |

Critically, this is explicitly framed as **relative, not absolute**: their
own help copy says some "undesirable"-flagged images "may not be objectively
bad if viewed on their own – but they may be in the undesirable or unlikely
category because we believe there are better similar images in the scene."
This is an important product-philosophy point: the badge answers "is this
the shot to pick *from this burst*," not "is this technically a good photo"
— a meaningfully different claim than Teststrip's current per-image quality
signals.

**Strictness is user-tunable**: Preferences → AI First Pass settings offers
**Ruthless / Balanced (default) / Cautious**, shifting the distribution of
images across the 5 buckets without deleting or auto-selecting anything.

**Filter dropdown UI** (`images/first-pass-a.webp`): a checkbox list — "All
Image Assessments" plus one row per category with its color dot, label, and
(implicitly) a count — check/uncheck to show/hide that bucket, functioning
as a multi-select filter, not a single active filter.

---

## 5. Rating / selection model

Deliberately meaning-agnostic — Narrative does not prescribe what stars or
colors *mean*; their own help copy: "anything you want them to mean!"

- **Star ratings 1–5** (`1`–`5`), **`0`** clears.
- **Color ratings**: red/yellow/green/blue/purple (`6`,`7`,`8`,`9`,`P`),
  `⌘0` clears the color only, `⌘⌥0` clears everything.
- **Tag** (`T`, Mac-only) / **Untag** (`U`) — a binary flag Lightroom cannot
  read at all (XMP has no generic "tag" field they map to), but Narrative
  can still filter and ship by it internally.
- **Reject** (`X`, Mac-only) — rejected images are never moved/copied to the
  shipping destination; this is the closest thing to a "trash" flag, but
  it's non-destructive within Narrative itself (still browsable, just
  excluded from shipping).
- Applying **any** rating/keyboard action toggles a toast confirmation
  (**"Image tagged"** confirmed in a screenshot) — a small, centered,
  auto-dismissing black pill, matching the "toast notification" preference
  documented for keyboard-shortcut reminders.
- **Storage**: ratings write to XMP sidecars (except JPGs, presumably
  written into the file's own embedded XMP/EXIF). Sidecars must stay next to
  the source files for Lightroom/Capture One to pick the ratings up.
- **"Shipping" = handoff, not export-and-done**: `⌘E` / the SHIP+EDIT button
  opens a dialog to choose destination app, move-vs-copy, and (optionally)
  an AI edit preset to apply on the way out. Lightroom then imports via its
  own Import dialog reading the shipped folder (with a caveat: don't have
  Lightroom's import window already open, or the ship button silently no-ops).
  There is no "export as JPEG" step in the culling flow itself — shipping
  hands off RAWs + sidecars, editing happens downstream.

---

## 6. Filters

Filter bar lives in a collapsed-by-default panel opened via a funnel icon
"on the left of the application"; a **"…" (more) menu** lets the user choose
which filter types are visible in the toolbar at all (AI First Pass, People
(beta), Image Focus scores, Star ratings, Color ratings, Tags, Camera/Serial,
Capture Date, Lens, Folder). Each visible filter icon shows a small count
underneath (how many images currently match).

- **Potential Picks filter**: click the blue "potential pick" hexagon in the
  filter bar to show only First-Pass-flagged likely keepers. Their explicit
  claim: **cuts review volume roughly in half** ("you only need to look
  through half of your images... In most cases you'll pick something from
  these"). Framed as a fast first pass for a "sneak peek" delivery, not a
  replacement for a full review.
- **Focus Score filter**: dropdown with **All scores / X and Above / X and
  Below / Exact Score / No Focus Score**. Note: range filters (e.g. "6 and
  above") *exclude* images with no focus score unless you explicitly tick
  "Include Images without Image Focus scores" — an easy silent-omission trap
  worth avoiding in our own design (or at least surfacing the count that got
  excluded).
- **People Filter (beta, Standard plan+)**: opens a full-width panel listing
  every detected face as "Person N" (renameable — e.g. to "Bride"/"Groom"),
  each row showing 4 sample thumbnails plus a **thin horizontal coverage
  bar** — a mini timeline across the whole shoot with green segments marking
  where that person appears (tooltip: "Green indicates where this person
  appears in your shoot"). Multi-select with an **"any" vs (implicitly)
  "all"** toggle for combining people (e.g. "show me photos with the bride
  AND groom together" vs "either of them"). Selecting people collapses the
  gallery down to just their matching photos and the toolbar shows a
  live count chip ("2 people · 49 of 145").
- **Rating/color/star filters**: click to isolate that rating; `⌘/Ctrl+click`
  a filter to invert it (show everything *except* that rating) — e.g. hide
  all red-labeled images in one gesture.
- No formal AND/OR builder beyond the People Filter's any/all toggle — this
  is a fairly lightweight, icon-driven filter model, not a query builder.

---

## 7. Speed claims

Speed is treated as core to the pitch, not a footnote:

- **"Import 5,000+ RAWs in under 3 seconds"** — hero marketing claim (i.e.
  RAWs are browsable near-instantly after pointing Narrative at a folder;
  this is presumably to a low-res-but-present preview, with full quality
  arriving progressively, though marketing copy doesn't spell out the
  progressive-render detail).
- **"No loading times or wait periods during import/navigation"** — the
  reference doc's framing ("next image renders the moment you hit the arrow
  key") is corroborated by their own FAQ-level claims.
- Aggregate stats used as social proof: **2B+ images imported/year, 180
  countries, 253h saved per average user per year, 93% of users who try it
  recommend it.**
- Why it matters to their audience: wedding/event photographers routinely
  shoot 2,000–5,000+ RAWs per event and need to turn around a "sneak peek"
  gallery within a day or two — perceived per-image latency during a culling
  session of that size compounds into hours, so instant-transition browsing
  is a headline differentiator against Lightroom Classic (their own
  comparison page claims Lightroom fails "Instant rendering").

---

## 8. What they deliberately do NOT do

- **No auto-rejecting or auto-deleting.** First Pass/Image Assessments are
  informational badges and filters only — nothing is removed from the
  catalog or blocked from shipping without an explicit user action (rating,
  reject flag, or filter-then-manually-ship). Their own copy repeatedly
  stresses images "flagged undesirable" are not necessarily bad photos, just
  relatively worse *in that scene* — a hedge against over-trusting the AI.
- **No auto-editing during culling.** Editing (AI Presets, auto white
  balance/exposure/skin tone) is a separate product surface ("Edit"),
  applied only at ship-time if the user opts in — never silently applied
  during the cull pass.
- **No forced ranking/decision.** Scene rank order is a suggestion for scan
  order, not a gate — you can freely rate/reject any frame in any order,
  including ones First Pass marked undesirable.
- **Tag flag is deliberately non-standard.** They explicitly accept that the
  Tag rating won't round-trip into Lightroom's own rating model, rather than
  overloading a standard XMP field to fake compatibility.
- **No manual scene creation/editing (that we found).** Scene grouping
  appears to be fully automatic with no documented merge/split/manual-add
  affordance — if a designer wants that as a Teststrip feature, it would be
  new ground, not a Narrative pattern to copy.

---

## 9. Keyboard model (complete, from help.narrative.so)

| Key | Action | Section |
|---|---|---|
| `↑` / `↓` | Prev/Next image | Navigation |
| `←` / `→` | Prev/Next scene | Navigation |
| `⌘↑`/`⌘↓` (Mac) `Ctrl↑`/`Ctrl↓` (Win) | Cycle through images within a scene | Navigation |
| `⌘+Shift+click` thumbnail (Mac) `Ctrl+Shift+click` (Win) | Select all images in a scene | Navigation |
| `⌘Z` / `Ctrl Z` | Undo | Navigation |
| `⌘⇧Z` / `Ctrl⇧Z` | Redo | Navigation |
| `1`–`5` | Apply 1–5 star rating | Rating |
| `6` `7` `8` `9` `P` | Apply red / yellow / green / blue / purple color rating | Rating |
| `0` | Clear star rating | Rating |
| `⌘0` / `Ctrl0` | Clear color rating | Rating |
| `⌘⌥0` / `Ctrl+Alt+0` | Clear all ratings | Rating |
| `T` (Mac only) | Tag image | Rating |
| `U` (Mac only) | Untag image | Rating |
| `X` (Mac only) | Reject image | Rating |
| `⌘1`–`9`/`P` (Mac) `Ctrl1`–`9`/`P` (Win) | Toggle rating filter | Rating |
| `⌘+click` filter / `Ctrl+click` filter | Filter to hide images with this rating | Rating |
| `Space` | Toggle zoom mode (to primary face if present) | Zoom |
| `Z` | Toggle zoom mode, ignoring faces | Zoom |
| `+` / `−` | Zoom in/out | Zoom |
| `←` / `→` (while zoomed) | Prev/Next face in zoom mode | Zoom |
| `/` or `.` | Show/Hide Close-Ups panel: face mode | Close-Ups |
| `⌘/` or `⌘.` (Mac) `Ctrl/` or `Ctrl.` (Win) | Show/Hide Close-Ups panel: pan mode | Close-Ups |
| `⌥+`/`⌥−` (Mac) `Alt+`/`Alt−` (Win) | Increase/decrease Close-Ups panel size | Close-Ups |
| `⌘A` / `Ctrl A` | Select all thumbnails | Edit |
| `⌘[` / `Ctrl[` | Rotate image left | Edit |
| `⌘]` / `Ctrl]` | Rotate image right | Edit |
| `⌘E` / `Ctrl E` | Ship images to editing program | Edit |
| `G` | Grid view | Workspace |
| `S` | Scenes view | Workspace |
| `N` | Survey mode: image compare | Workspace |
| `Shift+N` | Survey mode: face compare | Workspace |
| `E` | Loupe view | Workspace |
| `F` | Fullscreen mode | Workspace |
| `Y` | Change filmstrip orientation | Workspace |
| `⌘Y` / `Ctrl Y` | Hide filmstrip | Workspace |
| `I` | Show/Hide shot information | Workspace |
| `C` | Show/Hide crop panel | Workspace |
| `Esc` | Reset loupe view | Workspace |
| `,` (comma) | Remove image from Survey Mode | Survey |

**Survey Mode** (`N` / `Esc` to close) deserves a callout even though it's
outside the four requested pages: select up to 12 images from any view, open
Survey Mode to compare them side by side (Image Compare, the default), or
switch to **Face Compare** (`Shift+N`) to compare up to 6 faces at once —
i.e. a dedicated "final two/three candidates" comparison tool, distinct from
both Scenes View (burst-level triage) and Close-Ups (single-frame face
detail). Extras beyond 12 shown as a count badge, bottom-right.

All shortcuts are user-customizable via Preferences → Keyboard Shortcuts, and
arrow-key scene-navigation behavior specifically is configurable there too.

---

## 10. Screenshot inventory

All images live alongside this doc in `images/`. Frame-grab filenames encode
the source video and the timestamp in seconds (`_tN`) they were pulled from;
these are real app screenshots captured from Narrative's own product-demo
videos (Mux-hosted, embedded in the marketing pages), not illustrator mockups.

| File | What it shows |
|---|---|
| `scenes-hero_t0.jpg` | Grid View: 6-col thumbnail grid, top toolbar (view-mode icons, color-rating swatch row with counts, CLEAR, filter funnel, "Scene rank" sort dropdown, SHIP+EDIT), right-edge tool rail, bottom 3-part status counter. |
| `scenes-hero_t9.jpg` | Loupe View: left sidebar showing the current scene expanded into a numbered sub-filmstrip with colored left-edge rank bars (blue→red gradient), main image with green face-assessment dots on a recessional/confetti shot, red-bar rows = lower-ranked frames in the stack. |
| `closeups-hero_t0.jpg` | Close-Ups panel core layout: 8-bridesmaid group shot in the loupe with per-face green/yellow dots; 2-column Close-Ups grid on the right with eye-icon+score badges per face; scene filmstrip on the left with "Scene 2" expanded. This is the same shot Jesse referenced from memory — confirms his description. |
| `closeups-hero_t12.jpg` | Same sequence, later frame: right-edge rail showing a yellow "5" pill and a red "!" pill — the summary chips Jesse recalled. |
| `face-hero_t4.jpg` | Loupe view, forehead-touching couple close-up, green crescent-icon badge labeled **"Very Close"** — a compositional/proximity assessment, not eye-state. |
| `face-hero_t6.jpg` | Wedding-aisle recessional kiss: green badge labeled **"Kissing + Eyes Closed"** plus scattered green/yellow dots on background guests — confirms assessments render for every detected face in frame, and that "eyes closed" is contextually fine during a kiss. |
| `face-action_t10.jpg` | 9-bridesmaid lineup, hover tooltip on one face showing stacked labels **"Eyes Barely Open (Group Photo)"** (orange) + **"Soft Focus"** (yellow, score 5) — confirms the two-assessment stack and the group-photo-specific threshold wording. |
| `closeups-action_t7.jpg` | Close-Ups grid close-up with tooltip **"Eyes Mostly Open (Group Photo)" / "Good Focus" (6)**; full ratings-variant toolbar visible (star counts, color-dot counts, flag icons with counts, filtered-count "12/211"). |
| `closeups-action_t13.jpg` | Same session, a black toast reading **"Image tagged"** centered under the main image — confirms the keyboard-action confirmation-toast pattern. |
| `people-hero_t10.jpg` | People Filter (beta) panel open: toolbar chip "2 people BETA · CLEAR · 49 of 145"; panel lists "Person 1"/"Person 2"/... each with 4 sample thumbnails and a thin coverage bar; cursor mid-rename of "Person 1". |
| `people-hero_t15.jpg` | Same panel after renaming to "Bride"/"Groom", with tooltip **"Green indicates where this person appears in your shoot"** pointing at the coverage bar. |
| `first-pass-features.png` | The complete 18-label face-assessment legend (icon + color + text for every state) — the source for the taxonomy table in §4a. |
| `first-pass-a.webp` | First Pass+ filter dropdown: checkbox list of the 5 categories (Best in scene / Above average / Average / Below average / Undesirable) with color dots, "Best in scene" checked; left filmstrip showing red-bar (Undesirable-heavy) frames. |
| `og-close-ups-panel.jpg` | 12-person black-tie wedding party shot with a **3-column** Close-Ups grid — confirms the panel's column count reflows with face count/panel width rather than staying fixed at 2. |

---

## 11. Opinions

**Genuinely strong:**

- **The scene-rank color bar in the sidebar filmstrip** is a small, cheap
  idea with outsized value: it turns "how much good material is left in this
  burst" into a glanceable gradient instead of a number you have to compute
  by scrolling. Teststrip's stack/scene UI should steal this outright.
- **Context-aware face assessment** ("Kissing + Eyes Shut" = good, "Eyes
  Closed" = bad) is the single most important design idea here. A naive
  eyes-open detector actively punishes photographers for capturing genuine
  emotional moments (kisses, big laughs) — Narrative clearly spent real
  effort disambiguating "eyes closed because that's the moment" from "eyes
  closed because bad luck." Teststrip's culling-signals plan (per the
  existing reference doc) should treat this as a hard requirement, not a
  stretch goal, once face-region focus/eye detection lands.
  - Practically: this needs a *smile+kiss/laugh classifier feeding the eye
    scorer as context*, which is more model surface than a bare eye-openness
    classifier. Worth scoping explicitly rather than discovering the gap
    after shipping a naive version.
- **Relative-not-absolute framing of Image Assessments**, stated plainly in
  their own docs, is an honest and correct hedge. It's the right way to talk
  about an AI ranking signal to a professional whose reputation depends on
  the output — "this is worse than its neighbors" is a defensible claim,
  "this is a bad photo" is not, given current model reliability.
- **The status-bar triple counter** (`project / scene / frame-in-scene`) is
  a small, unglamorous UI element that answers "where am I" without any
  interaction — worth copying verbatim.
- **Speed as the headline feature**, not a footnote, is worth taking
  seriously: for a 2,000+ photo culling session, per-image latency is the
  single biggest lever on whether a workflow feels good, and it's cheaper to
  build than any assessment model. Teststrip's CLAUDE.md already argues
  against chasing perf micro-optimization, but that's a different claim from
  "the interactive next-image path must never show a placeholder" — this is
  worth treating as a correctness bar, not a performance-budget nice-to-have.

**Weak points / wedding-specific bets that may not transfer:**

- **Everything assumes bursts.** Scenes View, rank-first ordering, and the
  "potential picks" filter all lean on the assumption that most shoots are
  dominated by near-duplicate clusters (portrait poses shot 10x, group
  photos shot 5x to land everyone's eyes open). A lifetime amateur photo
  archive — one photo per moment, shot on a phone over 15 years, minimal
  burst shooting — would see Scenes View degrade to mostly singleton
  "scenes," and the entire "best-frame-first" pitch stops paying for itself.
  Teststrip's actual dogfood use case (Jesse's own library) is much closer to
  this than to a wedding shoot; we should not assume Scenes View is the right
  *primary* mode for Teststrip the way it clearly is for Narrative — it may
  need to be one useful view among several rather than the workflow spine.
- **People Filter is a shallow layer over face-recognition** (name a
  detected face, filter by presence) — no relationship modeling
  (bride/groom/family vs. guest), no "confirm this cluster is one person"
  correction flow documented, and it's explicitly beta/paywalled. Teststrip's
  planned face-recognition/confirmed-person filtering (per the existing
  reference doc) already anticipates going further (confirmed identity with
  provenance) — good, don't regress to Narrative's simpler "beta" bar.
- **The right-edge rail's mystery pills** (yellow "5", red "!") were never
  documented in any help article we found — either an underdocumented
  feature or one still in flux. Don't clone UI we can't explain; flag for
  follow-up if we ever get hands-on access to a trial account.
- **Tag-flag/Lightroom incompatibility is an accepted rough edge**, not a
  solved problem — Narrative ships a rating type they know won't round-trip
  into the standard tool their own users live in. Teststrip's
  XMP-sidecar-first approach (writing standard fields, only on confirmed
  origin) is already a stricter and more portable design; nothing to import
  from this specific compromise.
- **Five-category "First Pass+" is still beta** and, by their own admission,
  a work in progress toward "more objective" scoring — i.e. even Narrative
  doesn't consider their relative-ranking-to-absolute-scoring transition
  solved. Worth resisting the urge to over-fit Teststrip's design to their
  current 5-bucket taxonomy; it may not be where they land either.
