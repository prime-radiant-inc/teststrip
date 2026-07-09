# UX Persona Pass — Synthesis & Fix Spec

**Date:** 2026-07-08
**Status:** Synthesis of a 6-persona critique of the *post-simplification* UI.
Tier A = implement now (defects + legibility, aligned with the approved
"simpler & clearer" direction). Tier B = product decisions held for Jesse.

**Implementation status (2026-07-08): all of Tier A and Tier B landed on `main`.**
Tier A: A1 Review-row a11y, A2 icon labels, A3 (safe subset — "keep" not
"commit", de-doubled subtitle), A4 signal verdicts + "What Teststrip sees"
headers, A5 People/Places empty states, A6 flattened Evaluate + ⇧⌘E, A7 search
placeholder + tips popover. Tier B: batch pick/reject/rate across a selection,
default byline preference (Settings ⌘,), "Saved to sidecar" confirmation, Batch
Metadata command ⌥⌘M, search-field dedup, Cull/Find-Best-Shots differentiated
(NOT merged, per recommendation). Deferred with rationale: the wide
"photographs→photos"/"Needs Evaluation" rename (matcher-entangled) and the
People all-caps eyebrows (coherent tested pattern). A4's rendered verdicts are
unit-verified but were not visually confirmed live (no worker signals this
session).

## Method

Six persona subagents (first-timer, event/wedding photographer, family
archivist, photojournalist, returning power-user, and a design critic) reviewed
**ground-truth accessibility-tree dumps** of five live screens (Library, Review,
People, Places, Find-Best-Shots outcome) plus the SwiftUI source. Screenshots
were unavailable (Screen Recording TCC gap), so the AX render — the exact
labels/buttons/copy the user sees — was the evidence. Every code-level claim
below was re-verified at its source site.

## Convergent themes (what ≥3 personas independently flagged)

1. **Machine output reads like a debug console.** The Find-Best-Shots / Pick
   inspector shows `TESTSTRIP READS` / `TESTSTRIP SUGGESTS` / `TESTSTRIP SIGNALS`
   and raw floats + pipeline names (`Motion blur: 0.84`,
   `100% - local-image-metrics/preview-color-focus-metrics`). First-timer's #1;
   design critic's #1. The core "here are your best shots" payoff moment.
2. **One state, three-plus names.** "Needs Evaluation" / "Not analyzed yet" /
   "without local signals" / "AI" / "signals" all name the same idea. Also
   "photographs" vs "photos" vs "frames"; "Favorite" vs "Pick" vs "star".
3. **Empty states report plumbing instead of inviting.** Places renders
   decorative region/city buttons (`Arctic Circle`, `Bering Sea`) atop
   `No geotagged frames yet`; People repeats "Run evaluation to find faces
   before naming people." 2–3×; "Locations appear here as geocoding finishes."
4. **Icon-only controls carry no accessible label**, so AX/VoiceOver reads the
   wrong word: rating stars → "Favorite", reject → "Close", clear-flag →
   "Remove", per-field Apply → "Selected", save-as-set → `rectangle.stack.badge.plus`.
5. **Depth got buried too deep.** Evaluate is `More ▸ Analyze ▸ Evaluate`
   (3 levels) with **no keyboard shortcut**, while Find Best Shots got ⇧⌘B.

## Discounted (verified NOT real)

- **"Import Path clutter."** `shouldExposeImportPathControl` gates it to isolated
  test launches only (`TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY`). It appeared in
  the dumps only because they were captured from a smoke build; it never ships
  to a real session. No change.

---

## Tier A — implement now (defects + legibility)

Each is an unambiguous correctness/legibility fix consistent with the approved
simplification. All get an end-to-end assertion against the AX render.

### A1. Copilot/Review row accessibility defect (pure bug)
`actionRowContent` applies `.help(...)` to an `.accessibilityElement(children:
.combine)` HStack with 4 child views, so the help string is emitted 4× and the
value doubles the title (`Not analyzed yet, Not analyzed yet, 24`). Fix: set one
explicit `.accessibilityLabel("\(title), \(countText)")` + single
`.accessibilityHint(statusText)` on the row; stop leaning on combine+help.
*File:* `CopilotView.swift:283-326`.

### A2. Accessible labels for icon-only controls
Add `.accessibilityLabel` matching the visible intent:
rating stars → "Rate 1"…"Rate 5" (not "Favorite"); reject → "Reject" (not
"Close"); clear-flag → "Clear flag"; per-field Apply → "Apply Keywords/Caption/
Creator/Copyright" (`InspectorView.swift:903`); save-as-set → "Save as Set".

### A3. Terminology unification (one word per concept)
- Unevaluated state: **"Not analyzed yet"** everywhere; retire "Needs
  Evaluation", "without local signals", "All catalog photos have local signals".
- Object noun: **"photos"** everywhere (retire "photographs", "frames").
- Machine-output headers: replace `TESTSTRIP READS/SUGGESTS/SIGNALS` with one
  human set — **"What Teststrip sees"**, **"Suggestions"**, **"Why this scored"**.
- Find-Best-Shots help: "…until you **keep** them" (retire "commit").

### A4. Humanize the signal readout (biggest single win)
In the Pick inspector, lead with a plain verdict per signal ("Sharp",
"Slightly soft", "Motion blur", "Well exposed") derived from the score, and move
the raw float + provenance string behind the existing Advanced disclosure.
*Files:* `InspectorView.swift` signal rows, `CopilotView.swift` metric rows.

### A5. Empty states that invite
- Places: when `0 geotagged`, suppress the decorative region/city buttons; show
  one line — "None of these photos have location data (no GPS recorded)."
- People: emit the scan prompt **once**; add the next step ("Scan to find faces,
  then name them here").
- Rename "Scan current scope" → **"Find Faces"**; keep the technical detail in help.

### A6. Flatten + accelerate Evaluate
Drop the "Analyze" wrapper so Evaluate/Evaluate Visible/Evaluate Scope sit one
level under **More**; add a menu-bar **Find ▸ Evaluate** command with a keyboard
shortcut. *Files:* `LibraryGridView.swift:231-255`, `main.swift` Find menu.

### A7. Search placeholder + token help
Shorten placeholder to "Search photos, people, places…"; move the 15-token
reference from the always-on tooltip into a "Search tips" help popover.

---

## Tier B — product decisions held for Jesse (recommendations, not yet built)

1. **Batch pick/reject/rate across a multi-selection.** *Source-confirmed gap:*
   `setRatingForSelectedAsset`/`setFlagForSelectedAsset` act only on the single
   focused asset; there is a batch path for keyword suggestions but none for
   rating/flag/reject/color. Event photographer's #1 — "select 12 near-dupes,
   reject 11" is impossible in one gesture. **Recommend building it** (highest-
   leverage real feature), but it's beyond "legibility" so it's your call.
2. **Default Creator/Copyright (byline) preference.** *Source-confirmed absent.*
   A wire shooter retypes the same byline every session. Recommend a one-time
   preference that pre-fills both fields.
3. **Positive "written to sidecar" confirmation.** Today `metadataSyncStatus`
   renders only on `.pending`/`.conflict`; a successful write shows nothing, so
   silence means both "saved" and "not wired". Recommend a transient "Saved to
   sidecar" confirmation.
4. **Promote Batch Metadata out of the More menu.** Photojournalist wants it
   top-level; it's currently `More ▸ Batch Metadata…`. Placement decision.
5. **Find Best Shots vs Cull as two hero verbs.** The design critic wants them
   merged; but "Find Best Shots" is the marquee action **you just approved** and
   the two do different jobs (evaluate+rank vs start a culling session).
   **Recommend NOT merging** — instead differentiate their help text so the
   distinction is legible. Flagged because it touches a just-locked decision.
6. **Second search field.** The critic calls the top-chrome + filter-bar search
   boxes redundant. Needs a look: confirm whether they're genuinely duplicate or
   contextual (global vs scoped) before removing either.

## E2E scenario cards

| Card | Covers | Falsification |
| --- | --- | --- |
| review-row-a11y-single-help | A1 | AX help/value for a Review queue row repeats a phrase >1× or doubles the title |
| icon-control-labels | A2 | Any rating star reads "Favorite", reject reads "Close", or an Apply button reads "Selected" in the AX tree |
| terminology-photos-not-analyzed | A3 | "photographs", "Needs Evaluation", or "without local signals" appears on a primary surface |
| signal-verdict-plain | A4 | The Pick inspector shows a raw float (e.g. "0.84") outside the Advanced disclosure |
| places-people-empty-invite | A5 | Places shows a region/city button while `0 geotagged`, or the People scan prompt renders twice |
| evaluate-one-level-shortcut | A6 | Evaluate requires opening more than one menu, or has no menu-bar keyboard command |
