# Persona 8 — Dana, first-run skeptic

Session date: 2026-07-11. Build: main @ 22861c84. VM: teststrip-e2e (Tart), empty catalog variant.

Dana's deal: a friend said "try Teststrip, it's better than dragging photos around in Finder."
Dana has one camera dump folder and about an hour of patience. If the app makes her read a
manual to import a folder, it's gone.

## 0:00 — Before the app even opens

(Harness note, not Dana's experience: the VM was up but SSH-dead on first contact; had to
restart it. Root cause turned out to be host-side: a Tailscale exit node with
ExitNodeAllowLANAccess=false was blackholing the VM's vmnet subnet (192.168.65/24 → utun13).
Fixed with `tailscale set --exit-node-allow-lan-access=true`. Dana doesn't see any of this,
but it cost the session ~25 minutes. Not a Teststrip bug.)

## 0:01 — Cold open (empty catalog, all three workspaces)

App opens straight into **Library**. Verdict: honestly, better than I expected.

- **Library (⌘2):** Big friendly "No photos yet — Bring in a folder or memory card to get
  started" with an orange "Import photos to get started" link AND an orange Import button
  top-right. Two obvious paths to the one thing I need to do. A sidebar says
  "All Photographs (0)". Search placeholder shows example syntax ("rating:3 camera:...")
  which quietly teaches me the search language before I ever need it. Grade: A-.
  (Evidence: dana-01-cold-open.png)
- **Cull (⌘1):** Same "No photos yet" + import link, sidebar says "Cull From — Nothing to
  cull". Fine. It doesn't dump me into a scary empty pro-tool cockpit; it repeats the one
  next step. Grade: A-. (dana-02-cull-empty.png)
- **People (⌘3):** First jargon sighting. Banner: "No faces found yet — *Run evaluation on
  catalog photos to populate local face review queues.*" Dana does not know what
  "evaluation", "catalog photos", or "local face review queues" are. Worse, the card below
  says "*Split person and face-box naming are deferred; automatic grouping suggestions,
  one-tap confirm, manual naming, and merge are available now.*" — that's a release-notes
  sentence from the dev team, shipped into an end-user empty state. Dana's read: "this
  screen is talking to itself." Grade: C. (dana-03-people-empty.png)
- One tiny wobble: the workspace switcher said Cull/Library/People but ⌘1 dropped me into
  something labeled "Loupe" under the title. Minor, moving on.

Score so far: the app explains itself. Dana has not deleted it. On to import.

## 0:08 — Import

Clicked "Import photos to get started" → tidy little menu: **Folder…** / **From Card…**.
Exactly the two things a camera-dump person needs. Picked Folder, navigated to
~/Pictures/roll-1 in the normal macOS picker. (dana-04-import-menu.png)

The confirmation sheet is the best thing I've seen so far: "Import Folder — Catalogs photos
in place without moving the originals. Source roll-1, 28 recognized photo files, 903.8 MB",
then a checklist of what it will and won't do. "No original files are moved, rewritten, or
copied" is EXACTLY the sentence a skeptic needs on day one. Some checklist lines drift into
vendor-speak ("Mirror portable metadata to XMP", "reads stay provisional until you act") —
Dana skims those, but the tone is trustworthy, not scary. Button says "Import 28 Photos",
not "OK". (dana-05-import-sheet.png)

Clicked it. Within ~5 seconds: green "28 photos imported" banner, real thumbnails already
on screen (RAW files!), sidebar now shows All Photographs (28), Recent Import, and my
roll-1 folder. A completion panel offers a big orange **Start culling** plus Review/Open/
Evaluate/Cull-stacks buttons, and it already detected "4 stacks · 8 photos in time-adjacent
bursts". That's genuinely impressive for 900MB of DNGs. (dana-06-during-import.png)

Small gripes on this screen:
- Suggestion chips appeared: "Apply adult — 1 photo at 95%". Out of context "Apply adult"
  reads... unfortunate. It means the keyword "adult". Needs a noun ("Add keyword: adult").
- Filter chips "Not analyzed yet", "Signal: Focus", "Signal: Face Count" — Dana doesn't
  know what a Signal is yet.
- The completion panel is a wall of eight buttons. The orange one wins, but it's a lot.

Ground truth check: 28 rows in `assets`, and **zero** .xmp files in my folder right after
import. The "we won't touch your files" promise held at import time.

## 0:15 — Learning to cull with no manual

Clicked the orange **Start culling**. Dropped into a loupe: big photo, filename, "Frame 1
of 28", a filmstrip, and — nice touch — "Stack 1 of 24 · Same folder, captured within 2s"
with an orange **Keep frame 1 · cut 1** button. The app is openly suggesting what to do
with the burst. (dana-07-cull-start.png)

Keys: Dana's first instinct, press `?`. **A real Keyboard Shortcuts overlay appeared.**
Navigation (arrows, stacks), Ratings 0-5, Color Labels, and more below the scroll. This is
the single best discoverability moment of the session — the thing narrative.so users brag
about, and it's just... there. (dana-08-keymap.png) Small gripe: Pick/Reject aren't visible
in the first screenful; you must scroll to find them, and nothing on the loupe itself says
"P = pick, X = reject". Dana guessed P and X from muscle memory of other apps.

Culled a few: P → toast + green tick, X → toast "R0012914.DNG rejected — ⌘Z undoes".
That toast is perfect: it names the file AND the undo. Header keeps a running "✓2 ×2 ·
24 left" score with a progress bar. Filmstrip edges go green/red. Culling feels great.
(dana-10-mid-cull.png)

Catalog agrees: `R0012901 pick, R0012903 reject, R0012911 pick, R0012914 reject`.

### DEFECT — browsing writes Rating=0 sidecars into my photo folder

After flagging only 4 photos, my roll-1 folder contained **8** .xmp sidecars. The extra
four (R0012902, R0012909, R0012913, R0012918) are photos Dana merely *looked at* while
arrowing through — catalog shows `flag NULL, rating 0` for them, and each got a sidecar
containing only `xmp:Rating="0"`:

    <rdf:Description ... xmp:Rating="0"></rdf:Description>   (no ts:Pick attribute)

The runbook's own promise is "Teststrip doesn't write a sidecar just from importing or
browsing" — a sidecar is supposed to appear only after a user sets rating/flag/keyword/etc.
Navigating the loupe apparently commits a zero rating. A skeptic who checks her folder
after five minutes (Dana did) sees the app spraying files next to her originals that she
never asked for. This is exactly the trust surface the app brags about. Severity: high for
the persona, easy to evidence, reproducible: import → arrow through photos → ls *.xmp.

## 0:25 — Scope, stacks, finishing the pass

Pressed Return on a "Keep frame N · cut M" recommendation — nothing observable happened
(catalog flags unchanged). Pressed S — the filmstrip silently changed from "frame 8/28" to
"frame 4/24" and an "Unrated" pill appeared by the filename. No toast, no explanation:
Dana has no idea she just cycled "scope" or what scope even is. She only figured it out in
hindsight because 4 flagged photos disappeared from the strip. (dana-11-scope.png)
Kept culling with P/X — auto-advance means P,P,X,X just works. Ended at 4 picks, 4 rejects,
confirmed in catalog.

## 0:32 — "Now what?" Export

In Library, clicked the **Pick** filter chip → grid shows exactly my 4 keepers with green
flags. Clicked the share icon in the toolbar → **Export Photos** popover: Selected/Visible/
All Matches, a "Web 2048px" preset, JPEG/PNG, quality slider, "Include EXIF/IPTC metadata",
"≈ 2.7 MB estimated", and a note about name collisions. Everything a normal person needs,
nothing they don't. Picked my Desktop in the save panel. Four JPEGs appeared:
R0012901/R0012911/R0012919/R0012920.jpg. Verified on disk. Dana's whole job — dump,
pick, hand off keepers — worked end to end in half an hour. (dana-13-export-sheet.png)

## 0:38 — Poking around

- **People, revisited:** without Dana doing anything, People now says "74 faces need a
  name — 8 new groups" with face crops and "Who is this?" cards. The face scan ran itself
  after import. Named the biggest group "Riley" via a clean Name Face Group dialog
  ("Groups this face group's 42 faces across 11 photos under a new named person").
  Ground truth: `people`/`person_assets` were **0 and 0 until the moment I clicked Create
  Person**, then Riley + 11 rows. Confirm-before-write demonstrably holds.
  (dana-15-people.png, dana-16-name-sheet.png)
- **Search:** ⌘F focuses the field (good). Typed "pacifier" → a chip reading "Search:
  pacifier — *Plain search fallback*" and a caption "read as plain text: pacifier"… and the
  visible results did not change. Dana can't tell whether it found nothing, or everything,
  or what a "plain search fallback" is falling back *from*. The placeholder taught her
  `rating:3 camera:...` syntax, but plain words go into a shrug. (dana-20-search.png)
- **Settings (⌘,):** a single "Default byline" pane — Creator/Copyright with "Nothing is
  written to a photo until you apply it." Minimal and on-message. Oddity: it came
  pre-filled with "Scenario Tester / © 2026 Scenario" — on a fresh install Dana would
  expect empty fields. (dana-18-prefs.png)
- **Filter-chip soup:** after a session the bar above the grid accumulates stacked chips
  ("Pick", "Imported 28 photos from roll-1 Cull Input", "Search: pacifier") plus suggestion
  chips plus signal chips. Individually fine, collectively noisy. And keyword-suggestion
  buttons still read as commands with no object: "Apply adult — 4 photos at 85%".

## 0:45 — Quit and relaunch

Quit, relaunched against the same catalog. Everything came back: 28 photos, 4 picks with
green badges, Riley in People, folders, previews — and even the Pick filter I'd left
active. Second launch feels exactly like home. (dana-19-relaunch.png)

---

# Verdict

## Top 5 frictions (ranked)

1. **Browsing writes Rating=0 XMP sidecars next to originals** — files Dana never rated or
   flagged (R0012902/09/13/18) got sidecars just from arrowing past them, contradicting the
   app's own "no sidecar from importing or browsing" promise. Evidence: sidecar diff +
   catalog rows above. Trust-breaking for exactly the user this app courts.
2. **People empty state speaks developer** — "Run evaluation on catalog photos to populate
   local face review queues" and "Split person and face-box naming are deferred…" is
   roadmap text in a first-run screen. (dana-03-people-empty.png)
3. **S/scope is a silent mode change** — filmstrip renumbers and an easily-missed "Unrated"
   pill appears; no toast names the new scope. Dana didn't know she'd changed anything.
   Also Return on the stack recommendation did nothing observable. (dana-11-scope.png)
4. **Plain-text search gives no comprehensible feedback** — "Plain search fallback" chip,
   result set visibly unchanged; no "0 matches for 'pacifier'" moment. (dana-20-search.png)
5. **Pick/Reject keys aren't taught where you need them** — the ? overlay is great but P/X
   are below the fold and the loupe itself never shows the two keys the whole workflow
   runs on; Dana guessed from other apps. (Minor kin: "Apply adult" chips, eight-button
   completion panel.)

## Top 3 delights

1. **The import confirmation sheet** — count, size, and a plain-English "we will not move,
   rewrite, or copy your originals" checklist before anything happens. Best-in-class first
   contact. (dana-05-import-sheet.png)
2. **Import speed with instant next steps** — 900MB of RAW visible in seconds, stacks
   auto-detected, one obvious orange "Start culling", and the reject toast that names the
   file and the undo key. (dana-06, dana-10)
3. **Perfect memory on relaunch + honest ground truth** — picks, person name, even the
   active filter all survive quit; and the confirm-before-write model provably does what
   the marketing says (0 rows until Create Person).

## Did Dana delete the app?

**No.** Closest call was minute ~3 in the People workspace (jargon wall) — but the Library
empty state had already banked enough goodwill, and by minute 32 she had exported keepers.
She keeps it. What would have lost her: discovering the Rating=0 sidecar spray in her
camera folder *before* the export win — if she'd Finder-checked at minute 16 and been less
patient, that's an uninstall plus a warning text to the friend who recommended it. Fix #1.

Harness notes (not Dana's experience): VM networking was down ~25 min (Tailscale exit node
without LAN access shadowing the vmnet subnet; fixed via `tailscale set
--exit-node-allow-lan-access=true`, plus an ssh alias workaround for a stale host route).
App driven entirely via vm_scenario_run.sh ax/key/shell; evidence screenshots
dana-01…dana-20 in this directory.



