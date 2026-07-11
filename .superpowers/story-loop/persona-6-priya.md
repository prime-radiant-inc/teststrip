# Persona 6 — Priya, the metadata perfectionist

*Session log, 2026-07-11. Teststrip in a Tart VM, faces seed (real photos).*

I catalog things for a living. If a tool loses a caption, misspells a keyword
without telling me, or writes sidecars it can't round-trip, I'm out. Today I'm
giving Teststrip the full archivist workout: ratings, flags, captions, batch
keywords/creator/copyright, sidecar verification field-by-field, an
out-of-band sidecar edit, people naming, and an export check.

## Setup

Built current main on the host and synced the `faces` seed into the VM.
Waiting on the build now — first impressions to follow.

## First look

Launch was quick; I land in the Library grid: 11 NASA astronaut portraits
(Aldrin, Armstrong, three eras of John Glenn, four Sally Rides). Immediately
two things an archivist likes: a **"Needs Keywords"** chip and a **"Not
analyzed yet"** chip sitting right under the search field, and the search
placeholder itself advertises `rating:3 camera:...` token syntax. The catalog
confirms a blank slate: every asset has `{"keywords":[],"rating":0}`. Good —
no phantom metadata.

## Task 1 — Ratings and flags, first pass

My plan: 5 stars for the formal portraits I'd lead an exhibit with, 3 for the
workaday shots, flag the keepers. I'll do it with the keyboard from the grid
and then go straight to the catalog and the sidecar directory to see if the
app is telling the truth.

Pressed `5` on the selected Aldrin portrait. Catalog: `"rating":5` instantly.
Sidecar `commons-aldrin-portrait.jpg.xmp` appeared with `xmp:Rating="5"`.
Exactly what the manual promised. Delight #1: no "save" button, no delay —
the sidecar is just *there* when I go look.

**Surprise #1 (big one for me):** four sidecars already existed in the folder
before I rated anything — clearly written by an earlier tool/session. One
(`commons-glenn-1962.jpg.xmp`) carries `xmp:Rating="5" ts:Pick="pick"` and a
`dc:description` ("Grandpa Joe at his happiest, 1962"). But the catalog row
for that photo says `{"keywords":[],"rating":0}` — **import ignored the
pre-existing sidecar values.** If I migrate an annotated archive into
Teststrip, my existing ratings and captions apparently don't come along. I'll
test whether "Check Sidecars for Changes" rescues this later (task 4 material).

Rated the full set from the grid with arrow keys + number keys (5/3/3/4/5/3/
2/5/3/4/3) and `P`-flagged the five keepers. Ground truth after the pass:
all 11 catalog rows carry exactly the ratings I typed, all 11 sidecars exist,
and `grep xmp:Rating *.xmp` matches the catalog **row for row**. `ts:Pick`
appears in exactly the five flagged files. This is the cleanest
rating-to-sidecar round trip I've seen in an alpha. (One self-inflicted
wound: a stray `P` while the last photo was selected flagged ride-sts7; I
decided to keep it — it is a nice frame.)

**Surprise #2:** when I rated glenn-1962 (the photo with the pre-existing
foreign sidecar), its old caption "Grandpa Joe at his happiest, 1962" and
`ts:Pick` suddenly appeared in the catalog. So the app *does* read an
existing sidecar — but only when I first touch the photo, not at import.
Lazy adoption. I'd rather be told at import: "4 of these photos have
sidecar metadata; import it?" Silent deferred adoption means my library
search results change depending on which photos I've happened to touch.

## Task 2 — Captions and Batch Metadata

Captions first, in the inspector (⌘I → Describe). Fields for Keywords /
Caption / Creator / Copyright, right where I want them. Captioned three
photos ("Sally Ride, official NASA portrait, 1984", etc.); each landed in the
catalog on Return and in the sidecar as a proper `dc:description` rdf:Alt.
The Info tab even shows a green "Saved to sidecar · <filename>" line —
that one line buys the app a lot of trust from me.

Then **Batch Metadata** (Metadata menu) over the 4 Sally Ride shots, scoped
"Visible" after a `ride` search. Keywords, creator, copyright applied to all
four; my per-photo caption was left alone because I left the batch Caption
field blank. Sidecars: `dc:subject` Bag with all four keywords, `dc:creator`
Seq, `dc:rights` Alt. Structurally immaculate XMP.

**But — the worst moment of the session.** The Batch Metadata form opens
*prefilled* with a default Creator ("Scenario Tester") and Copyright
("© 2026 Scenario"), styled so they read as gray placeholder text. I made a
second batch pass to add keywords, left those fields "as-is", hit Apply — and
it silently overwrote my real Creator/Copyright on all four photos, catalog
AND sidecars:

    catalog:  creator = "Scenario Tester", copyright = "© 2026 Scenario"
    sidecar:  <dc:creator><rdf:Seq><rdf:li>Scenario Tester</rdf:li>...
              <dc:rights>...<rdf:li>© 2026 Scenario</rdf:li>

Meanwhile an *empty* Keywords field on a later pass did NOT clear keywords —
so the rule is "blank = leave alone, filled = overwrite", and the form
sabotages that rule by pre-filling two fields for you. An archivist who
batch-adds a keyword to 2,000 images would stamp "Scenario Tester" over
2,000 provenance records without a single warning. I caught it only because
I diff the sidecars after every operation. This needs: no silent prefill, or
per-field "apply" checkboxes, or a change-summary confirmation.

I re-entered the correct values and re-applied; catalog and sidecars now
agree on all four fields.

## Task 3 — Keyword consistency and the audit pass

I keyworded glenn-1962 as "Mercury Program", then deliberately typed
"mercury program" (lowercase) on glenn-official. **Nothing helped me
notice** — no autocomplete, no suggestion of the existing spelling while
typing, no keyword list/tag manager anywhere in the sidebar to browse the
vocabulary. Catalog now honestly contains both spellings
(`["Mercury Program"]` vs `["mercury program"]`).

Searching `keyword:"mercury program"` returns BOTH photos — matching is
case-insensitive, so retrieval forgives me, but that also means the
inconsistency is *invisible* unless I dump the catalog myself. For a
controlled vocabulary person this is friction: the app neither prevents nor
reveals near-duplicate keywords. (If matching were exact instead, it'd be
worse — silent recall loss. Case-insensitive is the right call; a vocabulary
browser is the missing piece.)

Search/filter audit generally: `rating:4` parses into a proper "Rating >= 4"
chip; `flag:pick` is NOT a token — it honestly banner-warned "No matches for
'flag:pick', read as plain text" (there's a dedicated Pick quick-chip
instead, which found exactly the 5 flagged photos, matching
`SELECT count(*) ... flag='pick'` → 5). Two smaller notes: filters *stack*
(my old keyword chip stayed active when I typed a new query, quietly giving
me 0 results — though the empty state listing "Active filters: ..." with a
Clear Filters button is genuinely well done), and typed queries need Return
before anything happens, which fooled me once.

## Task 4 — Out-of-band sidecar edit + "Check Sidecars for Changes"

I simulated another tool touching a sidecar: edited
`commons-armstrong-eva-training.jpg.xmp` on disk, changing `xmp:Rating="3"`
to `"2"` and adding a `dc:description` ("EVA training at Ellington AFB, 1969
— edited by exiftool-sim"). Then Metadata ▸ Check Sidecars for Changes.
Twice. Waited 30+ seconds between checks.

**Result: nothing.** Catalog still `{"keywords":[],"rating":3}`. The
`metadata_sync_state` row for that asset still says `synced` with its
`updated_at` frozen at 19:28:37 (pre-edit). No banner, no Activity badge, no
toast — the menu item gives zero feedback whether it found changes, found
none, or even ran. Support ▸ Copy Diagnostics confirms the app's view:
`XMP pending/conflicts: 0/0`, while the file on disk provably says
`xmp:Rating="2"` (I re-read it).

For me this is the scariest failure of the day, worse than the batch
clobber, because it's the feature whose entire job is to notice exactly
this. If Teststrip and any other XMP-aware tool coexist on the same tree,
edits from the other tool are silently invisible — and Teststrip's next
write of that sidecar would presumably stomp them. Even if detection worked,
the command needs a completion report ("Checked 11 sidecars, N changed").
Silence is indistinguishable from broken — and here it *was* broken.

## Task 5 — People workspace

Rough ride. The People workspace (⌘3) showed "No faces found yet / Scan
ready" with a "Scan to find faces in these photos" control. I clicked it —
repeatedly, via two different AX paths — and **the face scan never ran**:
`face_observations` stayed 0 through ~4 minutes of polling with the app
frontmost, diagnostics show the worker running but *zero* face/evaluation
jobs ever enqueued (`Background by kind: xmpSync: 53` and nothing else,
`Recent failures: none`). The banner never left "Scan ready". No error, no
progress, no queue entry. It just doesn't start in this session. (Possible
smoking gun for the developers: `source_roots` in the seed catalog points at
a path from the machine that built the seed — `/Users/jesse/git/...` — which
doesn't exist here; assets themselves have correct local paths.)

Two side-observations while stuck:
- The Library's Pick filter silently scoped the *whole app* — People showed
  "0 people · 5 photos" and diagnostics said "Assets loaded/total: 5/5"
  until I cleared the filter back in Library. A global filter that follows
  you across workspaces without a visible indicator in People is disorienting.
- **Confirm-before-write held perfectly.** With the "Name Selection" dialog
  open and "Sally K. Ride" fully typed, `people` and `person_assets` were
  both still 0 rows. Only after Create Person did the row appear. That
  invariant is real, and I checked it at the SQL level mid-gesture.

But the naming dialog burned me: "Groups the selected photos under a new
named person" — with no count and no thumbnails of what's selected. My
actual selection was a leftover from Library (the Aldrin portrait), so I
created person "Sally K. Ride" attached to... Buzz Aldrin. The
`person:"Sally K. Ride"` search token works beautifully and returned exactly
that one wrong photo. A one-line "1 photo selected" in the dialog would have
prevented the misfile. Also: the person name does NOT flow to the photo's
XMP sidecar (no dc:subject/person entry) — people exist only inside the
catalog, which an archivist needs to know before relying on them.

## Task 6 — Export with metadata

File ▸ Export… gives a tidy popover: Selected/Visible/All Matches scope,
preset "Web 2048px", JPEG quality, long edge, an **"Include EXIF/IPTC
metadata"** checkbox (on by default), size estimate, and even a note about
collision handling. I exported the 4 Sally Ride photos, checkbox on.

All 4 JPEGs landed in `~/priya-export/`. Then I opened them up:

    strings *.jpg | grep "NASA Photo Office|Public Domain|Sally Ride|STS-7|astronaut"
    → nothing, in any file
    mdls: kMDItemAuthors = (null), kMDItemCopyright = (null), kMDItemKeywords = (null)

The files contain a minimal Exif block (resolution) and an empty Photoshop
marker — and **none of my catalog metadata**. No keywords, no caption, no
creator, no copyright. No .xmp sidecars written beside the exports either.
"Include EXIF/IPTC metadata" evidently means "carry the source file's
existing EXIF through", not "write the catalog's metadata into the export".
For an archivist this halves the product: everything I typed today lives in
the catalog and the originals' sidecars, but the deliverables I hand to a
client are stripped blank. If I hadn't checked, I'd have shipped four
uncredited, uncaptioned files under my own name.

## Wrap-up

State at quit: 11/11 rated, 5 picks, 4 captioned, 4 fully batch-tagged
photos; catalog and originals' sidecars in perfect field-for-field agreement
(I verified every field with sqlite3 + grep); one person record
(misfiled, my "fault", abetted by a blind naming dialog); face scan never ran;
one out-of-band sidecar edit permanently unnoticed.

## Top 5 frictions (ranked)

1. **Exports drop all catalog metadata despite "Include EXIF/IPTC
   metadata".** Evidence: exported JPEGs contain no keywords/caption/
   creator/copyright (strings + mdls all null) while catalog and source
   sidecars carry all of them. The deliverable is stripped of the work.
2. **"Check Sidecars for Changes" did not detect a real out-of-band sidecar
   edit — and gives zero feedback.** Evidence: sidecar on disk
   xmp:Rating="2" + new dc:description; ran the command twice; catalog still
   rating 3, metadata_sync_state row frozen at pre-edit timestamp, diagnostics
   "XMP pending/conflicts: 0/0". Silent and wrong.
3. **Batch Metadata pre-fills Creator/Copyright with defaults that look like
   placeholders, and Apply silently overwrites those fields on every photo
   in scope.** Evidence: a keyword-only second pass rewrote creator to
   "Scenario Tester" and rights to "© 2026 Scenario" in catalog + all four
   sidecars. Blank-means-skip exists (empty Keywords didn't clear), but the
   prefill defeats it.
4. **Face scan never starts (this session), silently.** Evidence: 4+ min of
   polling, face_observations = 0, no queued face jobs, no error, banner
   stuck at "Scan ready". People workspace is a dead end without it.
5. **No keyword vocabulary support**: no autocomplete against existing
   keywords, no keyword browser, so "Mercury Program" vs "mercury program"
   both entered without a whisper (case-insensitive search then hides the
   drift). Honorable mentions: naming dialog doesn't show what's selected
   (my Sally-Ride-on-Aldrin misfile); Library filters silently scope other
   workspaces; import ignores pre-existing sidecar metadata until first touch.

## Top 3 delights

1. **Rating→sidecar immediacy and fidelity.** Every rating/flag/caption/
   keyword landed in a clean, well-formed XMP sidecar instantly; 11/11
   sidecars matched the catalog row-for-row, and the inspector shows a green
   "Saved to sidecar · <file>" receipt. Trust-building stuff.
2. **Search tokens + honest fallbacks.** rating:4 → "Rating >= 4" chip,
   person:"…" works, keyword:"…" works, and unknown tokens are explicitly
   labeled "read as plain text" with an exemplary "Active filters / Clear
   Filters" empty state. The Pick chip matched SQL ground truth exactly.
3. **Confirm-before-write is real.** I checked the database with the naming
   dialog mid-flight: zero rows until the confirming click. That's the
   discipline the manual promises, verified.

## Verdict

**Would Priya have quit? Yes — at the export check (friction #1), late in
day one.** Everything before it was survivable: she'd have caught the batch
clobber (she audits), grumbled at the keyword field, filed the sidecar-watch
bug as "alpha". But when the exported deliverables came out with her
captions, credits, and rights stripped — after checking the box that
promised otherwise — the tool stopped being an archive and became a place
metadata goes to stay. She'd keep the sidecars (they're excellent) and go
back to exiftool until export carries metadata and sidecar changes are
actually detected.
