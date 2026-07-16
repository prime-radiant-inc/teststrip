# Simulated User Panel — Keyboard-Driven Culling Mode

2026-07-16. **This is a simulated panel**: six synthetic personas, inhabited and
moderated by an LLM to pressure-test the culling-mode design before UX work
begins. It is not real user research and must not be cited as such. Inputs:
`narrative-research.md` (Narrative Select teardown) and
`teststrip-signals-inventory.md` (what Teststrip has built today). The panel was
held to the product constraints: keyboard-first batch culling over a search
result, burst stacking with AI assistance, graceful no-burst degradation, and
the provenance invariants (tentative ✨ AI labels, explicit confirm/remove,
tentative flags never drive destructive operations, original bytes never
modified).

Panelists:

- **Marisol** — high-volume wedding/event pro. 6–8k frames per wedding, culls to ~700 in one sitting. Photo Mechanic daily; trialed Narrative Select and AfterShoot.
- **Dev** — documentary/street. Distrusts AI aesthetic judgment. Culls slowly, revisits.
- **Ruth** — retired teacher, 40 years of family photos, ~120k images (scans, point-and-shoot, phone). Almost no bursts; many near-duplicates. Wants keepers plus a "print these" shortlist.
- **Kenji** — sports/wildlife. 20–60 frame bursts, 4k+ frame days. Wants sharpness ranking he can trust and one-key burst resolution.
- **Priya** — accessibility/keyboard power user with RSI. Vim brain. One hand, home row, no chords, no pointer, predictable focus.
- **Saul** — studio owner/retoucher. Supervises juniors who mis-trust culling AI both ways. Cares about audit, undo, and two-pass workflow.

---

## Round 1 — Individual interviews

### Marisol (wedding pro)

**How I cull today.** Photo Mechanic, embedded JPEGs, one hand on the keyboard,
one on a coffee. Wedding lands around 7,000 frames. First pass is binary at
speed: tag or skip, arrow-tag-arrow-tag, roughly 3–4 seconds a frame when the
render keeps up, which in PM it always does. That's the whole religion: PM has
never once made me wait for pixels. Where the time actually goes is bursts —
the processional is 14 near-identical frames and I eyeball all 14 for the one
where her eyes are open and her father isn't mid-word. That comparison loop is
70% of my night. Second pass over the tagged set to cut 1,100 to 700, then
ship. If the cull isn't done in one sitting the sneak-peek gallery is late and
the couple posts a phone photo instead of mine.

**Narrative's model.** I trialed it. The within-scene ranking is the real
product — landing on the probable best frame of a burst instead of frame 1
saved me genuine hours. Steal that. The face dots and Close-Ups panel: steal
those, that's the eyes-open check without zooming 14 times. What's wrong:
sorting *scenes* by rank order is madness — I cull a wedding in story order,
ceremony before dancing, and their rank-first scene sort scrambled the
narrative so I turned it off day one. Also their Space-to-zoom fights my
PM muscle memory where Space means "next."

**Six keys.** Pick, reject, next-burst, prev-burst, next-frame-in-burst, zoom.
ENTER should be "this frame wins the burst, reject the rest, next burst" —
that's the money key; if I press it 300 times a night it pays for the app.
SPACE advances without deciding. "Done with this burst" = every frame has a
decision and I never see the burst again in my working scope.

**No bursts (Ruth's case).** Then it's just PM: one frame, one decision, next.
The mode should collapse to that with zero burst chrome. If it shows me an
empty "stack rail" on singletons I will notice and I will sneer.

**AI pre-applied vs on-demand.** Pre-applied, all of it, before I sit down.
The ✨-tentative model is fine — better than fine, AfterShoot's auto-cull
committed opinions I then had to un-commit. Compute overnight, show me
tentative picks, let me confirm in bulk at the end.

**Done with this batch.** A tally: picked / rejected / undecided, undecided
list one key away, then "confirm all tentative" as a single deliberate gesture,
then I export picks. If undecided isn't zero I'm not done.

### Dev (documentary/street)

**How I cull today.** Slowly, on purpose, and I resent that this panel treats
that as a defect. Contact-sheet ethic: everything from a walk goes into one
grid, I live with it for a few days, mark maybes, come back. The cull *is* the
edit — the thinking happens in the second and third look. Time goes into
looking, which is the job. What wastes my time is tools that fight revisiting:
anything that treats a decision as final, buries the unchosen, or resorts my
frames by its own opinion of them.

**Narrative's model.** I'll grant them one honest sentence, and it's in their
own help docs: undesirable-flagged images "may not be objectively bad if viewed
on their own." Correct — and then the whole UI works against that sentence.
Pre-ranked best-first, a filter that hides half the take. The technically worst
frame is often the picture. Winogrand's whole archive would score "undesirable"
on eye dots. The one thing I'd steal: nothing is auto-rejected and rejected
frames stay browsable. That restraint is the only part I trust. Face
assessments — for street work half my subjects aren't facing the camera and
that's the point.

**Six keys.** Next, previous, pick, reject, *unmark*, and a key that toggles
every AI opinion off-screen. ENTER should do nothing grand — grand ENTERs are
how mistakes happen at speed. SPACE = advance, no decision. "Done with this
burst" is my call, not a checkmark's: it means I've *seen* every frame, not
that every frame is labeled.

**No bursts.** That's my life too — street work is single frames. The mode
must be a first-class single-frame reviewer, not a burst tool with the burst
removed.

**AI pre-applied vs on-demand.** On-demand only, for me. The ✨ provenance is
honestly designed — tentative, never committing, removable with a memory so it
doesn't come back. I respect the plumbing. I still want a plain view where no
verdict pill tells me what to think while I'm looking. Show me the read when I
ask (a key), not as ambient pressure.

**Done culling.** Never, really. Practically: I want to close the session with
maybes intact and reopen it in three days to the exact same state. A tool that
demands closure at the end of a sitting has misunderstood the work.

### Ruth (family archive)

**How I cull today.** Badly, if I'm honest. 120,000 images: scanned prints,
point-and-shoots, every phone we've owned. I open a folder in the Mac photo
viewer, get through 1968–1971 in an evening, lose heart. Time goes to three
things: near-duplicates that aren't bursts — I scanned the same print twice at
different settings, or took the same porch photo every Thanksgiving for a
decade; deciding whether a blurry photo is worthless or the only picture of my
sister-in-law who passed; and losing my place between sessions. My goal isn't
a client gallery. It's keepers, plus a short list to actually print for the
grandchildren.

**Narrative's model.** Best-frame-first in a burst is lovely and mostly
useless to me — I don't have bursts, I have *reshoots* years apart and
scan-duplicates minutes apart. If your grouping catches those, that's worth
more to me than any wedding feature. The face assessments frighten me a
little: a machine calling a photo of my late husband "undesirable" because his
eyes were closed — the label is wrong even when it's accurate. The
potential-picks filter that hides half? Absolutely not. The hidden half is
where the only photo of somebody lives.

**Six keys.** Keep, set aside (I won't say reject), *print this one*, next,
back, and undo. I can learn six; I can't learn forty, and I'd like the little
cheat-sheet overlay on screen until I dismiss it. ENTER = keep and go on —
the reassuring key. SPACE = go on without deciding. A burst is "done" when
I've looked at each one; please don't make the computer's guess count as my
looking.

**No bursts.** This isn't degradation for me, it's the whole product. One
photo, one decision, my place always saved.

**AI help.** Pre-applied but gentle. The ✨ is right — I want to see "the
computer thinks this one" and decide. For faces and names, prominent and
review-first, as your rules already say — if it labels the wrong sister I need
to catch it, not discover it in a printed album.

**Done with a batch.** A summary I can read like a teacher grades: how many
kept, set aside, undecided, *and how many I never actually looked at* — plus
my print list somewhere I can find again next week.

### Kenji (sports/wildlife)

**How I cull today.** 45fps bodies. A goshawk strike is a 60-frame burst; a
match day is 4,000+ frames in maybe 90 bursts plus stragglers. My cull is
burst-shaped: within a burst exactly one question matters — which frame is
critically sharp on the eye — and it cannot be answered below 100% zoom.
Current loop: open burst, zoom to the eye, arrow through with zoom locked,
pick one (rarely two), kill the rest, next burst. Time sink is the zoomed
flip-through, times ninety.

**Narrative's model.** Their focus scoring is face-anchored — no score at all
without a detected human face. My subjects have feathers. Their whole
assessment stack goes inert on my work. The *structure* is right though:
rank the burst, land me on the winner, let me verify. And their claim of
instant rendering is the actual product; if frame-to-frame at 100% zoom ever
hitches, the tool is dead to me.

**Your signals inventory — I read it.** Focus is an edge heuristic on a 16×16
preview sample. That cannot separate frame 31 from frame 32 of a 45MP bird at
1/3200. It can find garbage — wing-flap blur, empty frames — and that's
worth something. But a ✦ that pretends to know the sharpest of thirty frames
off a thumbnail is a lie, and the first time I catch it lying I stop pressing
the trust key. Better an honest "top 5, can't split them" than a fake #1.

**Six keys.** Keep-this-kill-burst (one key, the whole job), next burst, prev
frame, next frame, zoom-100 *that holds position across frames*, reject-burst
entirely (bird never in frame — happens constantly). ENTER =
keep-this-kill-burst. SPACE = advance. Burst done = one keeper flagged, rest
rejected, gone from scope.

**No bursts.** Don't care personally, but don't gate my burst keys behind
burst detection — a straggler frame gets ENTER = pick-and-advance, fine.

**AI pre-applied vs on-demand.** Pre-applied triage (empty-frame, gross blur),
on-demand ranking. Tentative-✨ is correct: never let its guess reject a frame
on its own. My rejects feed a trash run of thousands of files; only my
keypress gets to put a frame in that queue.

**Done.** Keepers count vs. burst count (should be ~1:1), then one audited
move-rejects-to-trash ceremony. Separate ceremony. Never a side effect.

### Priya (keyboard/RSI)

**How I cull today.** Whatever tool costs my hands least, which is a low bar
because every "keyboard-driven" photo app is lying somewhere. The lie shows up
as: a hover-only tooltip, a click-only menu, a modal that eats keys, or focus
silently moving so my keystrokes go nowhere. I read your current bindings.
Good bones — bare keys, local capture, a `?` overlay. Now the failures: all
four navigation actions are on *arrow keys*, which means leaving home row or
they don't exist; the verdict pill's detail is *on hover*; the Culling menu is
documented as click-only; and key capture is gated to specific sub-views, so
if focus wanders to the sidebar my P does nothing and — worse — I don't know
whether it did nothing.

**Narrative's model.** Customizable shortcuts, good. Toast confirmations,
good — feedback without looking away. `⌘+Shift+click` to select a scene is
disqualifying as the *only* path to a whole-burst operation. Any action that
exists only as a pointer gesture doesn't exist.

**Six keys.** J/K next/prev frame, H/L prev/next burst, F pick, D reject —
all home row, one hand, zero modifiers. (Arrows can stay as synonyms; they
must never be the only path.) ENTER = the burst-commit; SPACE = advance. Both
are fat keys, both reachable, that's correct. "Done with this burst" must be
mechanical and predictable: last undecided frame decided → advance. I need to
know where the cursor will be after every keypress without looking.

**No bursts.** Identical grammar, fewer states. H/L and J/K may merge; F/D/
ENTER/SPACE must not change meaning. A mode that re-binds keys based on
content I can't predict is a mode I can't operate.

**AI help.** Don't care about the opinions; care about the plumbing. Every AI
affordance needs a key: show/hide the read (your I-overlay pattern is right),
jump to ✦, confirm, remove. If rationale lives only under a mouse pointer,
you've built a mouse app with keyboard garnish.

**Done.** Summary readable without pointer, actions on keys, and the whole
session drivable start to finish with the trackpad physically unplugged. Test
it that way. Literally.

### Saul (studio owner/retoucher)

**How we cull today.** Two-pass discipline, enforced. Pass one is binary and
fast — in or out, no ratings, ratings in pass one are procrastination with
extra steps. Pass two works the ins: stars for tiers, client-facing set
picked deliberately. I supervise juniors, and I've watched AI culling fail
both directions in the same week: one kid rubber-stamped 900 machine picks
without rendering half of them; another ignored a correct blink-detector and
shipped a blinker as the hero frame. The tool's job is to make both failures
visible, not just possible to avoid.

**Narrative's model.** The relative-not-absolute framing — "worse than its
neighbors," never "bad photo" — is the most honest sentence in that product
and it should be tattooed on this one. Close-Ups panel: genuinely good review
affordance, faces audited without leaving the frame. What's missing for me is
the *audit layer*: show me, after the fact, everything the machine flagged,
everything a human confirmed, and everything a human overrode. Your
provenance model — origin=ai vs user, `removed_ai_labels` so a deleted
suggestion can't resurrect — is exactly the substrate. Now put a face on it.

**Six keys.** Pick, reject, next, prev, "why?" (show the machine's reasoning
for this frame's rank — the score-gated phrases, 'sharpest,' '23% sharper,'
are the right idea), and undo. ENTER as burst-commit is fine *only if* it's
undoable as a single unit and tells you what it just did: "kept 1, rejected
7 — undo." SPACE advances, decision-free. A burst is done when every frame
carries a *human* decision. A ✨ is not a decision.

**No bursts.** Pass one over singletons is just flag/skip; the two-pass
structure survives untouched. It's a workflow, not a burst feature.

**AI pre-applied vs on-demand.** Pre-applied and *tentative*, exactly your
model — pre-applied is auditable in bulk, on-demand judgments vanish into the
air. The end-of-session review queue of everything ✨ is the feature.

**Done.** The reconciliation: human-decided vs machine-tentative vs undecided
vs — critically — *never viewed*. If a filter hid 400 frames from a junior, I
need that number in red before anyone says "done."

---

## Round 2 — Moderated debate

### 2.1 Auto-advance after a decision

**Marisol:** On, always, no discussion. Decision without advance is a wasted
keystroke, times seven thousand.

**Dev:** Off. Advance-on-decision trains you to decide in order to move — the
tool starts farming decisions out of you. I want to mark a frame and keep
sitting with it.

**Priya:** You're both asking for determinism, not a direction. I'll take
either default, but the rule must be one sentence long and never vary by
context. And Dev — SPACE already advances without deciding; your "sit with it"
is: decide, don't move, because deciding didn't move you… no wait, that's my
point inverted. Fine: this is genuinely a mode toggle, not a resolvable
default.

**Kenji:** Within a burst, decision must advance to the next *undecided* frame
— not next sequential, I've already rejected those. Across bursts: deciding
the last frame must jump me to the next burst without a separate keypress.

**Ruth:** I want Marisol's default, honestly. My problem is volume; sitting
with frames is what I do *too much* of.

**Saul:** Default on, toggle off, and the toggle is a visible mode indicator —
juniors forget which mode they're in and press X twice.

**Moderator's read:** Consensus on configurable with default ON, and on
Kenji's two-level rule (advance to next undecided in burst; last decision
exits to next burst). Dev retains a supported "stay" mode. Dev, notably, moved
from "off" to "off *for me*, fine as a toggle" once SPACE-as-free-advance was
on the table.

### 2.2 Pick-first vs reject-first; ratings in the first pass

**Saul:** Pass one is binary. Anyone reaching for stars at 4,000 frames is
avoiding the question. Stars are pass-two vocabulary.

**Marisol:** Agree — PM taught everyone this. But I'm pick-first: I hunt
keepers; the unpicked default to gone. Kenji's the opposite.

**Kenji:** Reject-first by volume — 59 of 60 frames die — but mechanically I
express it as ONE pick that implies the rejects. Which is why ENTER matters
more than either P or X for me.

**Ruth:** I need a third thing and nobody's naming it: "keep" versus "keep
*and print*." If that means stars, I'll learn one star gesture. If it can be
one key on the second look-through, better.

**Dev:** Binary only, and I want "unmark" to be as cheap as marking. My picks
are provisional for days.

**Priya:** The number row for ratings is fine because it's *optional*. The
moment any workflow requires the number row at speed, one-handed operation
dies.

**Moderator's read:** Full consensus that the core loop is binary
(pick/reject/skip) and ratings are never required in a first pass. Ruth's
print list is a second-pass gesture over Picks (a color label or star bound to
one key), which Saul folded into his pass-two naturally. No consensus on
pick-first vs reject-first as a philosophy — but no design conflict either:
P, X, and ENTER coexist; users choose their own center of gravity.

### 2.3 Cursor lands on the recommended frame?

**Kenji:** Land me on the ✦. That's the entire time savings — I verify at
100% and commit. Landing on frame 1 of 60 is 59 wasted keypresses.

**Dev:** That's the machine curating what I see first, which is the machine
editing. Anchoring is real — you show me a frame as "best" and every other
frame is now viewed as a deviation from it. Land me on frame 1, capture
order; the burst is a sequence, the sequence has meaning.

**Marisol:** Dev, in a 14-frame processional burst the "sequence" is her
father's mouth in fourteen positions. There's no narrative *inside* a burst —
that's what makes it a burst. Across bursts, story order, I'm with you — I
said the same about Narrative's rank-order scene sort. Within? Land on the ✦.

**Dev:** …Distinguishing within-burst from across-burst ordering, that's
fair. I'll retreat to: capture-order across bursts is non-negotiable, and
within a burst I want a *mode* where entry is chronological, because for my
work the burst sometimes is a sequence — four frames of a gesture unfolding.

**Saul:** The trap isn't where the cursor lands, it's landing *silently*. If
it lands on ✦ it must say why — the score-gated phrases, "sharpest, eyes
open" — and show what it's ranked against. An unexplained landing is an
instruction; an explained one is a suggestion.

**Priya:** Either landing rule is fine; a landing rule that *varies* — ✦ when
signals exist, frame 1 when they don't — is two rules, and I hold two rules
in muscle memory badly. Whatever you pick, the no-signals fallback must be
visually loud so I know which rule fired.

**Moderator's read:** Consensus (Dev conceding, with conditions): default =
land on recommended frame *within* a burst, always with visible ✦ +
rationale; batch traversal *across* bursts stays capture-order, period —
Narrative's rank-order scene sort is explicitly rejected, with Marisol the
pro leading that rejection. Setting for chronological within-burst entry
(Dev). When no recommendation exists, land on first frame with an explicit
"no read" state (Priya's legibility demand, Kenji's honesty demand).

### 2.4 Whole-burst "accept recommendation and next" — safe or rubber-stamp trap?

**Kenji:** It's my most important key and I'm tired of pretending it's
dangerous. Reject is a *flag* in this app. Nothing moves, nothing deletes.
The blast radius of a wrong ENTER is one undo.

**Saul:** The blast radius of one wrong ENTER is one undo. The blast radius of
ENTER held down by a bored junior is a delivered gallery chosen by a
thumbnail heuristic. I watched it happen. I want friction.

**Marisol:** Friction is a tax on the 295 times I use it correctly to pay for
the 5 times someone else doesn't. Charge the 5, not the 295.

**Saul:** Then charge them precisely: ENTER only fires if the frame it's
keeping has actually *rendered on screen at full quality* in front of you.
You can't accept what you never saw. That costs the diligent user nothing —
the frame renders faster than their eyes move — and it breaks the
hold-down-ENTER conveyor belt completely.

**Kenji:** …I'd take that deal. It's the same guarantee I want from the
renderer anyway — if the frame isn't up yet, I don't want my keypress landing
on faith.

**Priya:** With a toast — "kept 1, rejected 7" — and single-key whole-unit
undo. Feedback and reversal are what make a fat key safe, not friction.

**Ruth:** And it never touches files. Say it again in the spec, in bold.

**Moderator's read:** Consensus, and a genuinely good synthesis: ENTER
(burst-commit) stays one keystroke, but is inert until the kept frame has
rendered at decision quality; every fire produces a count toast and is
undoable as one unit. Non-destructive invariant restated as load-bearing.

### 2.5 The Potential Picks filter (machine hides ~50% of frames)

**Marisol:** For a same-night sneak peek it's the difference between done and
not done. I want it one key away.

**Ruth:** And the half it hides is where the only photo of someone lives. In
my archive that's not a quality tradeoff, it's an irreplaceable-loss
tradeoff.

**Dev:** It's the single worst idea in Narrative's product. The machine
deciding what I don't see is the machine doing the edit. Never a default.

**Marisol:** Nobody said default. Narrative doesn't default it either — their
framing is "fast first pass, not a replacement for full review," and that's
how I used it. Opt-in, loud, per-session.

**Saul:** Opt-in and *accounted for*. Narrative has a documented trap where a
focus-range filter silently excludes unscored images — the inventory doc
flags it. The requirement is arithmetic: the screen says "showing 812 of
1,604" the entire time, and the end-of-batch summary says "792 frames never
displayed" in a color you can't ignore. A junior can use the filter; a junior
cannot *hide having used it*.

**Kenji:** Also the flip side works for Ruth — instead of hiding the bad half,
*surface* the likely-issues as a queue to sweep first. Additive, not
subtractive. Your app already has that queue built.

**Ruth:** Yes — show me the pile of probably-blurry ones to set aside myself.
I'll go through a pile. I won't accept an oubliette.

**Moderator's read:** Consensus: never default-on; opt-in per batch; a
persistent shown/total counter while active; never-viewed count in the
completion summary. Dev's "never" softened to "never *silent*" — he remains
personally a non-user. Kenji's additive reframing (likely-issue triage queue
as the archive-side equivalent) adopted for the Ruth use case.

### 2.6 One-pass vs two-pass

**Saul:** Build the mode around two passes: rough binary cull, then a refine
pass over Picks. Name them in the UI. Structure is what juniors and amateurs
both lack.

**Marisol:** Don't name them, don't gate them. My "two passes" are one
sitting; a wizard with steps would slow me down. Give me the scope cycle —
unrated, picks, rejects, all — and the passes emerge.

**Dev:** My cull is N passes over days. Any pass structure baked into the UI
is wrong for me by construction. What I need is state that survives closing
the app: my maybes, my position, untouched.

**Ruth:** I need what Dev needs, for humbler reasons — I do twenty minutes an
evening. Resume-exactly-where-I-was is the difference between an archive
that gets culled and one that doesn't.

**Priya:** The scope cycle *is* the two-pass feature: cull scope=unrated is
pass one; scope=picks is pass two. It already exists on S. Don't build a
second thing.

**Saul:** …If the completion summary makes "you have 214 picks — refine
them?" a one-key transition into scope=picks, I get my structure without a
wizard. Withdrawn.

**Moderator's read:** Consensus: no enforced pass structure; scope cycling +
exact session resume are the substrate; the completion summary offers the
refine pass as a one-key suggestion (Saul's structure as an affordance, not a
gate). Session resume is promoted to a hard requirement — Dev and Ruth, the
two slowest cullers, were immovable and correct.

### 2.7 What's on screen during blaze-through

**Marisol:** Close-Ups panel always, for a wedding. Faces are the job. It's
the difference between zooming 14 times and zooming zero.

**Kenji:** "When faces exist" means "never," for me, and then the panel space
is dead weight. Narrative solved this — Pan Mode, a subject crop when there
are no faces. Your inventory says Teststrip has no saliency detection at all.
Until it does, give me a center-crop pan panel or give me the pixels back.

**Dev:** Give me the pixels back regardless. Blaze-through for me is the
photograph, full stop. Every panel, pill, and badge on a toggle, and my
toggles remembered.

**Ruth:** Contextual by default sounds right — faces when there are faces. But
the panel switching itself on and off as I move is exactly the kind of
motion that makes me feel the software is fidgeting.

**Priya:** Ruth just said something important. Contextual *appearance* is
layout shift, and layout shift during rapid keying means the thing I'm
tracking moved. Reserve the space or don't; never reflow per frame. And the
panel toggle is a key, current binding `/` or whatever — fine — but its
*state* must persist per session, not per frame.

**Saul:** Verdict pill and ✦ visible by default — Dev can hide them, but
default-hidden re-creates my junior who ignored the correct blink warning.
Rationale detail on a key, not hover.

**Moderator's read:** Partial consensus: Close-Ups defaults on when the batch
is face-heavy, toggleable with per-session persistence, reserved-space so no
per-frame reflow (Priya/Ruth). Verdict/✦ visible by default, all AI chrome
hideable as a remembered "plain view" (Dev). Genuine gap flagged: no saliency
fallback exists for the no-face case (Kenji) — panel should show a pannable
center crop or collapse *for the session*, and a real Key-Element/saliency
signal is future work. No consensus between "always" (Marisol) and "never"
(Dev) — resolved as defaults-by-content plus persistent user override, which
both accepted grudgingly.

---

## Round 3 — Moderator's synthesis

### Design demands (consensus — numbered, testable)

1. **Uniform decision grammar.** P (pick), X (reject), U (clear) act on the
   current frame identically whether or not it's in a burst. In a batch with
   zero detected stacks, no burst chrome renders, no key is dead, and no key
   changes meaning. Test: an identical keystroke script yields identical
   catalog flags on a burst batch and a singleton batch.
2. **Capture-order spine.** The batch is traversed in capture order. Ranking
   never reorders traversal — it only marks ✦ and orders the within-burst
   candidate rail. Narrative's rank-order scene sort is explicitly rejected.
3. **Auto-advance: default on, one toggle, two-level rule.** A decision
   advances to the next *undecided* frame in the current burst; deciding the
   burst's last undecided frame advances to the next burst's landing frame.
   The toggle's state is visibly indicated. SPACE always advances without
   deciding, in every mode.
4. **ENTER = burst-commit.** Keep the current frame, reject the burst's other
   undecided frames, advance to the next burst. On a singleton, ENTER = pick
   and advance. Every fire shows a count toast ("Kept 1, rejected 7") and is
   undoable as a single unit with one keystroke. ENTER is inert until the
   frame it would keep has rendered at decision quality on screen.
5. **Landing frame = recommended, truthfully.** Entering a burst lands the
   cursor on the ✦ frame when a recommendation exists, with the score-gated
   rationale visible. When no frame has rankable signals, land on the first
   frame by capture time and show an explicit "no read yet" state — never a
   fabricated ✦. A setting flips within-burst entry to capture order.
6. **Zero pointer dependency.** Every hover affordance (verdict detail,
   rationale, badge meanings) has a keyboard path; every menu action in the
   mode has a key. Test: a full cull session — including confirm-all and the
   completion summary — completes via AX script with no pointer events.
7. **Home-row alternates; no chords in the core loop.** Every core action is
   on a bare key; all four arrow functions get letter synonyms (e.g. H/L
   prev/next burst, J/K prev/next frame). No ⌘/⌃ chord is required for
   pick/reject/advance/commit/zoom/undo. Culling keys work regardless of
   which pane has app focus while the mode is active.
8. **Hiding is loud.** Any filter that removes frames from traversal
   (Potential Picks, scope narrowing) is opt-in per batch, displays a
   persistent "showing N of M" counter while active, and the completion
   summary reports the count of frames never displayed on screen.
9. **Tentative ≠ decided.** ✨ (origin=ai) flags never mark a frame, burst, or
   batch as done. Done = every frame carries a user-origin decision or an
   explicit skip. The per-stack "complete" checkmark and all progress counts
   reflect user-origin decisions only. Test: a batch fully covered by
   tentative autopilot flags reports 0% decided.
10. **Batch confirm is deliberate and auditable.** One gesture confirms all
    tentative AI flags in scope, reachable only from an explicit review
    surface that lists exactly what will be confirmed (with one-key jump into
    that queue). No navigation or decision key ever implicitly confirms a ✨.
11. **Decision-quality rendering inside a burst.** Stepping to any frame in
    the current burst shows a sharpness-judgeable image immediately: the
    whole current burst plus the next burst's landing frame are prefetched at
    large size. If a frame isn't ready, show an explicit loading state —
    never a silently substituted low-res proxy while the user is judging
    focus. Test: arrow through a 20-frame burst at 5 keys/sec.
12. **Pixel-locked comparison zoom.** Z toggles 100% zoom; zoom level and
    center persist across within-burst navigation so successive frames are
    compared at the same region. Shift+Z centers the nearest face.
13. **Honest ranking or none.** Rationale claims remain score-gated (current
    behavior — keep it). When the signal can't distinguish frames — score
    deltas below the signal's noise floor, e.g. the 16×16-preview focus
    heuristic across a 30-frame telephoto burst — the UI says "too close to
    call" (top-N, unranked) rather than presenting a fake #1.
14. **Rejects are flags; disposal is a ceremony.** No key in the mode moves or
    deletes files. Move-rejects-to-trash/folder is a separate post-cull
    action that excludes tentative-only rejects (existing invariant),
    presents a manifest, and warns when a rejected frame contains a person
    with no other photos in the library.
15. **Exact resume.** Quitting mid-batch and relaunching restores scope,
    position, panel-visibility state, and all decisions. The completion
    summary shows: picked / rejected / undecided / never-viewed / tentative-✨
    counts, with one-key jumps to the undecided set, the ✨ review queue, and
    a "refine picks" scope switch.
16. **Dismissible on-screen reference.** The `?` key overlay and the on-screen
    command rail are both dismissible and their state remembered; core keys
    are user-remappable.

### Divergences (with recommended resolutions)

1. **Cursor lands on the recommended frame.** Marisol/Kenji/Saul: yes, it's
   the time savings. Dev: anchoring bias, machine overreach. Priya: neutral,
   demands one predictable rule. **Resolution:** default ON for both anchor
   use cases — the wedding pro's burst-comparison loop and the archive's
   scan-duplicate clusters both benefit, and demand 5's "no fake ✦" honesty
   plus visible rationale answers the overreach charge. Ship the
   capture-order-entry setting for Dev's constituency; don't make it a per-
   burst heuristic (Priya's two-rules objection).
2. **Machine-hides-frames filtering (Potential Picks).** Marisol: one key
   away, deadline-critical. Dev/Ruth: never — the hidden half holds the only
   photo of someone. **Resolution:** ship it opt-in per batch under demand 8's
   loud accounting (persistent N-of-M counter, never-viewed count at
   completion), never default. For the archive anchor, invert it: surface
   likely-issues as an additive triage queue (already built) instead of
   subtracting frames from review.
3. **On-screen density during blaze-through (Close-Ups panel, verdict
   chrome).** Marisol: panel always. Dev: nothing, ever, by default. Kenji:
   panel is dead weight without a saliency fallback. **Resolution:** content-
   aware *defaults* (panel on for face-heavy batches), per-session persistent
   user override, reserved layout space so nothing reflows per frame. Verdict
   pill and ✦ on by default with a remembered "plain view" toggle. Log the
   saliency/Key-Element gap as real future work; until then the no-face panel
   state is a pannable center crop or a session-level collapse, never a
   per-frame appearance/disappearance.

Secondary splits, noted without alarm: pick-first vs reject-first (both fully
supported by the same three keys; no design conflict) and one-pass vs
two-pass (resolved structurally — scope cycle + resume + a one-key "refine
picks" offer at completion).

### Traps (anti-requirements — the five biggest ways this mode fails)

1. **The wedding-shaped default.** If the mode's value collapses without
   bursts — empty stack rails on singletons, dead burst keys, ranking chrome
   with nothing to rank — the archive anchor (Ruth, and Jesse's own library)
   gets a degraded wedding tool instead of a first-class single-frame
   reviewer. The no-burst path is a primary path, not a fallback.
2. **The silent oubliette.** Any default or un-countered filter that removes
   frames from review without a visible tally — potential-picks on by
   default, a score-range filter that silently drops unscored frames
   (Narrative's own documented trap) — will eventually hide the only photo
   of someone, and the user will not know until it's unrecoverable in
   practice even though it's recoverable in the catalog.
3. **The ENTER conveyor belt.** If burst-commit can outrun rendering, the mode
   becomes a machine for laundering thumbnail heuristics into user-origin
   decisions at 4,000 frames an hour. Speed keys must never commit to a frame
   the user hasn't been shown.
4. **The pointer leak.** One hover-only rationale, one click-only menu, one
   focus-dependent dead key, and the "keyboard-driven" promise is void for
   the users who needed it most — while everyone else discovers it only as a
   vague sense that the mode fights them.
5. **The overconfident signal.** Presenting a low-resolution focus heuristic
   as a burst-discriminating sharpness ranking will get caught by exactly the
   users (Kenji) whose trust the ✦ needs to earn — and once caught lying, the
   recommendation system is dead weight forever. Rank only what the signal
   can actually resolve; otherwise say "too close to call."
