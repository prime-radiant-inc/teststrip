# UX Simplification Proposal — "Simpler and Clearer"

**Date:** 2026-07-08
**Status:** Proposal for Jesse's review (before/after; approve → implementation plan)

Grounded in two live persona walkthroughs (first-time user; working event
photographer). Both reached the same verdict: **the plumbing is
Photo-Mechanic-grade, but the app speaks to its author, not to a photographer.**
The fixes below are legibility, not new features. (Two correctness bugs —
arrow-nav double-step and autopilot "0 keepers" — are being fixed separately;
this doc is the chrome.)

Guiding principle: **one obvious path from "import" to "here are my best
shots," and hide the machine's internals until asked.**

---

## 1. The core path: "Find my best shots" (the #1 ask from both personas)

Today a newcomer's core job dead-ends: they press **Run Autopilot** and get
"0 keepers · 0 rejects," or they can't tell which of Evaluate / Evaluate
Visible / Evaluate Scope / Autopilot to press.

**Change:** one prominent primary action — **"Find Best Shots"** — that
evaluates if needed, ranks, and lands the user on a ranked/Picks view. It
subsumes the manual "Evaluate" step (a newcomer should never press Evaluate by
hand) and replaces the raw "Run Autopilot" button. It must always produce a
legible result (the autopilot fix guarantees no bare "0 keepers").

---

## 2. Toolbar: ~14 controls → ~5

| Before (14) | After |
| --- | --- |
| Import Folder, Import Path, Import Card | **Import ▾** (Folder / From Card; drop "Import Path" from the primary bar — it's a typed-path dev entry) |
| Evaluate, Evaluate Visible, Evaluate Scope | folded into **Find Best Shots** (with an "Analyze ▾" for power users under ⋯) |
| Autopilot ☑, Run Autopilot | **Find Best Shots** (the toggle becomes a setting in ⋯/Preferences) |
| Cull | **Cull** (keep) |
| Export | **Export** (keep) |
| Move Rejects, Reconnect Sources, Batch Metadata | **⋯ More** menu |
| Hide Sidebar | keep (standard) |

Result primary bar: **Import ▾ · Find Best Shots · Cull · Export · ⋯**

---

## 3. Rename "Copilot" → "Review", and lead with output not diagnostics

"Copilot" means nothing to a photographer, and its screen is an engineering
dashboard (AGENTS: idle, LOCAL SIGNALS, Provider Failures, "Freeze Results",
XMP synced). Rename to **Review** (or "To Do"), and open it on the actual
output — **Top Picks**, **Needs your eyes** — with the agent-status /
local-signals / provider-failures / freeze-results panels moved behind an
**Advanced / Diagnostics** disclosure.

---

## 4. De-jargon the labels

| Before | After |
| --- | --- |
| Copilot | Review |
| Autopilot | Auto-cull (or folded into "Find Best Shots") |
| Signal (filter) | AI score (or remove from primary filters) |
| XMP (filter/status) | Metadata sync |
| Needs Evaluation | Not analyzed yet (or hide from the sidebar) |
| Provider Failures, Local signals, Freeze Results | Advanced/Diagnostics only |
| per-signal "100% - local-image-metrics/preview-color-focus" | plain "Sharpness / Exposure score" |

---

## 5. First-run empty state

On a genuinely empty catalog (real first launch), show a single **"Import
photos to get started"** call-to-action instead of an ambiguous grid (today the
seed masquerades as the user's own library). One unambiguous first action.

---

## 6. De-duplicate navigation vs. view-switching

Search, Copilot/Review, Timeline, People, Places appear **both** in the sidebar
and the top view-switcher. Split the responsibilities:
- **Sidebar = what set you're looking at** (Library, saved searches, Folders,
  People, Places, review queues).
- **Top switcher = how you view the current set** (Grid · Loupe · Compare).

Remove the duplicated entries from the switcher.

---

## 7. Filter bar: default-simple, "More filters" for the rest

The filter row exposes 16+ controls including Signal / XMP / Source. Default to
**Sort · Rating · Flag · Keyword**; tuck Camera / Lens / ISO / Source / Signal /
XMP behind **More filters ▾**.

---

## What is deliberately NOT changing

The good parts the personas praised stay exactly as they are: bare-key
rating/flag/label with instant XMP-sidecar writes, non-destructive editing,
one-click smart-collection scoping, and the scoped Export with resize + optional
EXIF carry. This is a legibility pass over working machinery, not a rework.

---

## Open decisions for Jesse

1. **Naming:** "Find Best Shots" vs "Auto-cull" vs keep "Autopilot"? "Review"
   vs "To Do" for the Copilot rename?
2. **Scope of the first pass:** do all 7, or start with the 3 highest-impact
   (core path #1, toolbar #2, Copilot→Review #3) and iterate?
3. **Autopilot toggle fate:** demote to a setting, or keep visible?

## Suggested sequencing (if approved)

Wave 1 (highest impact, matches both personas' top-3): #1 core path, #2 toolbar
collapse, #3 Copilot→Review. Wave 2: #4 de-jargon, #5 empty state. Wave 3: #6
nav de-dup, #7 filter density. Each wave is independently shippable and
verifiable with an automated persona-style scenario.
