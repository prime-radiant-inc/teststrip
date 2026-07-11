# Persona 7 — Marcus, the ruthless cleaner

Build: current main (1dc6d1d5). VM: teststrip-e2e (had to restart it — network was
dead on first contact; not the app's fault). Seed: smokebig, 130 synthetic photos.

I shoot volume. I delete volume. Today I find out if this app lets me.

## 1. Keyboard blast

Launched into Cull loupe. Frame 1 of 130, HUD "35 picks, 26 rejects, 69 left".
First itch: filmstrip caption says "frame 1 / 120 · stack 1 / 120" while the
header says 130. Which is it? (Suspect a 120-item page under the hood. A user
just sees two numbers that disagree.)

`x` rejects AND advances — good, that's the muscle memory from every other
culler. Toast says "✕ smoke-0.jpg rejected — ⌘Z undoes". Reassuring.

Speed run: 30 keystrokes (x,x,p repeating) at 80ms spacing. Landed on Frame 32
— exactly 30 advances. Zero eaten keys, zero double-fires. HUD said 37/40/53
and the catalog agreed byte-for-byte:
  SELECT flag, count(*) → pick 37, reject 40, null 53. 
This is the fastest part of the app. No complaints. Keys feel instant even
through an SSH-driven VM.
## 2. Move Rejects to Trash — GHOST CORNERED

Culling > Move Rejects to Trash… with 40 rejects. The preflight sheet is honest:
"40 files · 19 sidecars · 896 KB", "Files go to the macOS Trash and the catalog
forgets them", and it lists the real absolute paths. Good wording.

Then I pressed "Move 40 to Trash". ax reported pressed. NOTHING HAPPENED.
Sheet still open, ~/.Trash still empty (0 files), catalog still 130 rows,
originals dir still 154 entries. The known inert-confirm ghost, live.

Root cause, from the screenshot (scratchpad/ghost.png, VM 8:19PM Jul 11):
the sheet contains an UNCHECKED checkbox "Move 40 reject photos to Trash" and
orange hint text "Check the box above to confirm the move." — but the primary
button is painted full-blue, prominent, enabled-looking. AXPress on it
"succeeds" and is silently ignored. It is not a dead button; it is a
checkbox-gated button that LOOKS armed.

As Marcus: this is the worst kind of safety UX. Either grey the button out
until the box is checked, or drop the checkbox (the sheet already IS the
confirmation). A blue button that eats clicks reads as "app is broken" and in
a real session I'd have clicked it five times and then force-quit. Also the
hint text appears to be visible before any click, meaning the sheet opens
with a lecture instead of arming itself.

Also spotted in the screenshot: an OS "See what's new in macOS Tahoe"
notification — not the app's fault, ignore.
Once I checked the box, the button worked instantly: toast "Moved 40 reject
photos to Trash", HUD → "37 picks, 0 rejects, 53 left", Frame count 130→90,
~/.Trash gained exactly 59 items (40 jpg + 19 xmp sidecars), catalog 130→90
rows, originals dir 154→95. Every number cross-checked. The operation itself
is *fast* and the accounting is airtight.

## 3. Instant regret — Move back

The toast row carries a "Move back" button. Before pressing it I took an
aggregate SHA-256 of all 59 trashed files: 65f35730a60c...392.

Pressed Move back: ~/.Trash → 0, catalog → 130 rows, flags restored exactly
(pick 37 / reject 40 / null 53), originals dir back to 154 entries, and the
aggregate SHA-256 over the same 59 files (restored in place) is IDENTICAL:
65f35730a60c...392. Byte-perfect round trip, sidecars included. This is
exactly the safety net I want. Delight.
## 4. Trash, then empty the Trash, then Move back — THE APP LIES

Trashed the 40 rejects again (checkbox dance again — second time it's already
muscle-memory-hostile). Then `rm -rf ~/.Trash/smoke-*` (user emptied Trash in
Finder). Then pressed the banner's "Move back".

Result: NOTHING. No error dialog, no failure toast, no banner change. Catalog
stays at 90 rows, Trash stays empty, and the banner STILL reads "Moved 40
reject photos to Trash" with a live "Move back" button — inviting me to click
it again. I did. Same silence. (Screenshot moveback-fail.png also caught the
banner's progress bar frozen mid-fill.)

For a deletion-happy user this is the cardinal sin: the app cannot restore the
files (fine, they're gone, that's my fault) but it REFUSES TO SAY SO. I would
sit there clicking Move back, assuming the app is broken, not that the files
are unrecoverable. It must say "40 files are no longer in the Trash and can't
be restored" and retire the button.

Bonus stale-count bug caught in the same screenshot: sidebar still shows
"Rejects 40" and "Not analyzed yet 130" while the HUD says "✕ 0" and the
catalog holds 90 rows. Three surfaces, three different stories.
## 5. Re-import the same folder

File > Import Path… on the same SmokeOriginals dir (90 survivors). The
REVIEW sheet says "Duplicates: 90 new" — flatly wrong, all 90 are already
cataloged. I braced for 180 rows of chaos. Confirmed anyway: the importer
itself did the right thing — "No new photos imported / 90 photos already in
catalog / Matched set", catalog stays 90 rows, 0 duplicate paths. So dedup
works, but the preflight's "Duplicates" line is lying about what's about to
happen. If I trusted it I'd have cancelled.
## 6. Move Rejects… (folder flavor)

Culling > Move Rejects… opens a native folder picker first ("Select where
reject photos should be moved."), THEN the preflight sheet: "Move rejects to
marcus-rejects / 5 files · 5 sidecars · 116 KB" + file list. Same checkbox
gate — and here the checkbox and the primary button carry the IDENTICAL
label "Move 5 reject photos to marcus-rejects". Two controls, same words,
only one of them does anything until the other is toggled. Coherence with
the Trash flow: good (same shape). Clarity: poor (same words twice).

The move itself: 5 jpg + 5 xmp landed in ~/marcus-rejects, catalog kept all
90 rows with 5 original_path repointed to the new folder. Sensible contrast:
folder move keeps tracking, Trash forgets. Move back from the banner was
flawless — folder emptied, paths repointed home, file physically back in
SmokeOriginals.

## 7. Undo, scopes, completion stage

- ⌘Z after all of that undid the most recent FLAG change (5→4 rejects, HUD +
  catalog agree), reaching past the intervening move ops. Reasonable.
- Scope cycle (s): All → Unrated → Picks → Rejects. Two gripes: "Unrated"
  actually means "undecided flag" (it happily showed me a 5-star photo), and
  an empty scope renders a blank loupe with NO scope label at all — you
  can't tell where you are or how to get out.
- Bulk blast: 49 x's at 90ms — 48 landed, ONE eaten (the only key loss all
  session; earlier 30 keys at 80ms were perfect).
- Completion stage: "Nothing left to decide / 37 picks · 53 rejects" — sums
  exactly to 90 — with View Picks / Export / Move Rejects… / Move Rejects to
  Trash… right there. That's Marcus's dream placement. One wart: the subtitle
  reads "37 picks · 53 rejects — No new photos found in SmokeOriginals Cull",
  old import status concatenated into the completion line.
- Final purge from the completion stage: 53 files + 53 sidecars → Trash
  (106 items verified in ~/.Trash), catalog 90→37 rows. Exact.

## Environment notes (not the app's fault)

The Tart VM's network died three times mid-session; each time the app took a
hard kill. Silver lining: the catalog survived every power-cut with zero
corruption (flags 37/52/1 intact mid-cull). Rock-solid durability. One real
app finding from the crashes: on relaunch the app resurrected the
pre-crash import-completion panel as a zombie sheet I had to Close again.

## Top 5 frictions (ranked)

1. **Move back lies after Trash is emptied.** Files permanently gone → the
   banner keeps a live "Move back" button; pressing it does NOTHING. No
   dialog, no toast, banner still says "Moved 40 reject photos to Trash".
   Evidence: catalog stayed 90 rows, Trash 0, across two presses;
   moveback-fail.png. This is a lie about data loss — the one thing a
   deletion tool must never do.
2. **The armed-looking dead confirm button (the ghost).** "Move N to Trash"
   renders full-blue and enabled while an unchecked "Move N reject photos to
   Trash" checkbox silently gates it; the hint "Check the box above to
   confirm the move." is easy to miss. AXPress reports success, nothing
   happens (ghost.png). Grey the button until armed, or drop the checkbox.
3. **Counts disagree across surfaces.** Sidebar said "Rejects 40 / Not
   analyzed yet 130" while the HUD said "✕ 0" and the catalog held 90 rows.
   Header "Frame 32 of 130" vs filmstrip "frame 32 / 120". For a bulk
   deleter, numbers ARE the UI; three surfaces telling three stories burns
   trust fast.
4. **Re-import preflight claims "Duplicates: 90 new" for 90 already-cataloged
   files.** The importer then correctly adds nothing ("90 photos already in
   catalog") — but the preflight would have scared me into cancelling.
5. **Empty scope = blank void.** Cycling s into an empty filter shows "No
   photo selected / 0 frames" with no scope label; plus stale banners linger
   ("Moved 40 reject photos to Trash" was still on screen 25 minutes and two
   operations later, still clickable).

## Top 3 delights

1. **Byte-perfect Move back.** Aggregate SHA-256 of 59 trashed files
   (65f35730a60c...) identical after restore; rows, flags, sidecars, counts
   all restored exactly. When it can work, it's perfect.
2. **Keyboard culling is instant and lossless** (30/30 keys at 80ms, exact
   catalog agreement), x-advances, toast says "⌘Z undoes", and the completion
   stage puts Move Rejects to Trash exactly where my thumb wants it.
3. **Crash-proof catalog.** Three hard VM kills mid-cull; zero lost
   decisions, zero corruption. Trash preflights are honest (real counts,
   real paths, sidecars itemized) and the folder-move flow tracks relocated
   files instead of forgetting them.

## Would Marcus have quit? Where and why?

Twice, nearly. First at the ghost button: a blue "Move 40 to Trash" that
eats clicks reads as "app is broken at the exact moment I asked it to do its
one dangerous job." A real Marcus clicks 3-4 times, mutters, and only luck
makes him spot the checkbox. Survivable — once.

The uninstall moment is friction #1. Marcus empties the Trash reflexively.
The day he clicks "Move back" and the app silently pretends the button
works — no "those files are gone" — is the day he stops believing anything
the app says about his files, and belief is the entire product here. Fix #1
and #2 and Marcus is a genuine convert: the core loop (blast keys → honest
preflight → verified Trash → byte-perfect regret button) is already the best
version of this workflow I've used.
