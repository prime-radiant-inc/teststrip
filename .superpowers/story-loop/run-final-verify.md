# Final post-fix verification batch — 2026-07-11

Scope: the 21 ledger rows at status Fixed, re-driven live in the Tart VM
against current main (720fb5f5). Cards are authoritative; assertions are
against catalog SQL / files, not pixels. One flake retry per leg.

Seed order: smoke → smokebig → burst → faces → (geo for worker-006) → empty.

## Setup

- VM `teststrip-e2e` found running but SSH wedged (connect timeout on
  192.168.65.5:22). `tart stop` + fresh `tart run --no-graphics`, polled
  until shell answered.
- Host build: `./script/build_and_run.sh --build` on main @ 720fb5f5.

- Dup fixtures for import-004 generated on host via
  `swift run TeststripBench seed-dup-fixtures` (card1 N=4, card2 4 dup + 2 new).

- VM network trap: after the wedge, two full headless reboots renewed DHCP
  (lease for MAC f6:4d:a1:75:fd:d5 at 192.168.65.5) but all unicast to the
  guest (ICMP, TCP 22) was dropped — host-side vmnet NAT broken. Worked
  around by relaunching with `--net-bridged=en0`; VM now at a LAN IP
  (192.168.20.149 this session), resolved via a PATH shim that makes
  `tart ip` use `--resolver=arp` so `vm_scenario_run.sh` keeps working
  unmodified.

## Legs

### smoke run 2 (`run/smoke2-1783823147`, env: REJECT_DESTINATION_DIR, EXPORT_DESTINATION_DIR, CARD_IMPORT_ROUTE=typed-path)

**app-010 move rejects (folder flavor) — PASS**
- Culling ▸ Move Rejects…: primary "Move 5 reject photos to rejects-dest",
  standing hint "Check the box above to enable …" present; sheet buttons via
  System Events: one enabled (Cancel), one disabled (primary) while
  unchecked. Checked → hint gone, both enabled. Gate identical to app-017's
  trash flavor.
- Move: smoke-0 left source, 5 jpgs in /Users/admin/rejects-dest, manifest 5.
- Move back: smoke-0 restored at exact path, dest emptied (only an empty
  stale `rejects/` subdir remains), manifest 0.

**app-009 export — PASS**
- Export popover: Long edge 1024, "Include EXIF/IPTC metadata" ON (default),
  Export Visible Batch → 24 JPEGs; smoke-2.jpg = 1024×683 (long edge exact).
- Catalog-authored metadata embedded (byte-scan of the JPEG; Spotlight
  indexing is disabled in the VM so mdls reads null for everything):
  "NASA Photo Office" (creator), "Public Domain" (copyright),
  "Smoke frame 3" (caption), "smoke"/"batch-0" (keywords) all present.
- Metadata OFF leg: re-export after toggling checkbox → all four values
  absent from the bytes (creator/copyright/caption/keywords stripped);
  a bare "Exif" TIFF container marker remains (no authored values).
- Collision-prompt step 7 not driven (destination env pins one folder;
  files were moved aside between runs) — matches card's PENDING-VM note.

**import-004 new-only dedupe — PASS steps 1-4/3b, FAIL step 5**
- card1 (4 new): preflight "4 new"; imported; A1 24→28.
- card2 dedupe ON: preflight "2 new · 4 already in catalog" (the ae565378
  truth fix, verified verbatim); completion "Imported 2 photos (4 photos
  already in catalog) from card2"; A2 = 30 = A1 + M. No silent drops.
- 3b: re-review of fully-imported card2 → "0 new · 6 already in catalog",
  primary "Import 0 Photos". Cancelled clean.
- Step 5 FAIL: with "Import new photos only" UNCHECKED (verified value 0 via
  System Events after clicking it), the primary still reads "Import 0
  Photos" and pressing it imports nothing — A3 stayed 30, expected 36
  (A2 + all 6 card2 files as intentional copies). Two attempts (ax press
  toggle, then coordinate click with value readback) — deterministic.
  The dedupe-off escape hatch does not re-import already-cataloged files.
- Driving trap for the record: AXSetValue into a *focused* SwiftUI sheet
  field updates the pixels but not the binding — "Review Card Import"
  looked inert for 6 presses because the draft paths were empty. Real
  keyboard keystrokes (click field, ⌘A, type) commit properly.

### smoke run 1 continued (order note: these legs ran after the ones below)

**activity-006 xmp lifecycle (post-aed1dbbe rescan+report) — PASS**
- With active filter `rating:4` (9 photos), edited smoke-1's sidecar
  out-of-band (Rating 1→3): Metadata ▸ Check Sidecars for Changes detected
  it — catalog rating followed 1→3, metadata_sync_state all 'synced'.
- Repeat with smoke-3 (3→4): completion toast captured verbatim:
  "Checked 24 sidecars — 1 changed on disk, queued to re-sync"; catalog
  followed 3→4. Change detection for assets OUTSIDE the active filter works.

**app-017 move rejects to Trash — PASS (all legs incl. the truth leg)**
- Culling ▸ Move Rejects to Trash…: primary "Move 5 to Trash" + warning
  "Files go to the macOS Trash and the catalog forgets them." present.
- Gate: with checkbox unchecked, sheet has exactly one disabled button
  (System Events `enabled=false` on the primary; Cancel enabled) and the
  standing hint "Check the box above to enable “Move 5 to Trash”." After
  checking: hint gone (find rc=1), both buttons enabled.
- Move: smoke-0 left source, 2 smoke-0 entries in ~/.Trash, preview dir
  gone, assets 24→19, smoke-0 row gone, manifest = 5 rows.
- Count surfaces agree post-trash: sidebar "Picks, 6" / "Not analyzed yet,
  19", Rejects row absent (0 omitted), filmstrip "frame 2 / 19" — catalog:
  rejects 0, picks 6, total 19. (Also serves as cull-015 count-agreement
  evidence on smoke.)
- Truth leg: deleted the 5 trashed copies via manifest paths, pressed Move
  back → banner "5 files are no longer in the Trash and can't be restored",
  Move back button retired (find rc=1), assets still 19, manifest cleared 0.

**app-006 session restore — PASS (steps 4-10)**
- Blob (defaults key `SessionRestoreState./…/run/smoke-1783819919/Teststrip`):
  `{"version":1,"selectedView":"timeline","sortOption":"filename",
  "minimumRatingFilter":3,"selectedAssetID":"smoke-3",…}` — per-catalog-root
  key, version 1, exact values set in the UI.
- Relaunch restored all facets: window "Teststrip – Timeline", Rating >= 3
  chip, "Sort: Filename — A to Z".
- Quit from Cull → relaunch lands "Teststrip – Grid" (never a cull view).
- Legacy "search" rawValue → Grid with the rest (rating chip) restored.
- "nonsense-mode" → whole state discarded (Grid, NO chip), no crash.
- version 2 → discarded (Grid, no chip), no crash.
- Zombie panel: imported 4 photos (Import Path typed route), completion
  surface up, quit without dismissing → relaunch has 1 standard window,
  0 sheets; "Imported 4 photos from card1" remains only as the Recent
  Import sidebar row.
- Tooling note: `defaults export`/`import` on the VM is stale/cache-racy —
  early false alarm about a missing key was my own `defaults import`
  clobber; plistlib edits + `killall cfprefsd` are reliable.

### smoke run 1 (`launch smoke` → run/smoke-1783819919)

**cull-009 keymap overlay — FAIL (one leg), rest PASS**
- First entry to Cull: toast "Press ? for keyboard shortcuts" found via AX. PASS.
- Leave (⌘2) / return (⌘1): hint REAPPEARED — driven 3 separate times, toast
  absent after its 2s window (find rc=1), then present again immediately on
  every re-entry (find rc=0 with the exact text). Source reads once-per-session
  (`hasShownCullKeyboardHint`, AppModel.swift:1958-1967) but the *stale*
  `lastCullingMetadataDecision` is re-rendered on workspace re-entry. FAIL
  against the card's "does NOT reappear" assertion.
- Overlay: `?` opens; NAVIGATION/FLAGS/LOUPE headings, "Promote Frame & Reject
  Siblings", "Cycle EXIF Overlay", "Previous Stack (Option)", "Next Stack
  (Option)", "⌥←" all present verbatim. Esc dismisses (find rc=1 after);
  focus recovered — `p` picked (SQL picks 6→7), ⌘Z reverted (7→6). Second `?`
  press also dismisses. All PASS.

**cull-005 scope cycle — PASS**
- Ground truth: unrated/picks/rejects/all = 13/6/5/24.
- Each S press toasted: "Scope: Unrated only" / "Scope: Picks only" /
  "Scope: Rejects only" / "Scope: All frames", then "Scope: Unrated only"
  again on the 5th press (clean loop). Filmstrip totals tracked exactly:
  13 → 6 → 5 → 24 → 13. No blank loupe at any step (frame text present
  every time).

**cull-002 loupe navigation — PASS (nav legs); zero-xmp negative moved to burst**
- In All scope from frame 6/24: Right→7, Left→6, Space→7 (exact single steps).
- Up/Down/⌥→/⌥← all left selection at frame 7/24 (designed no-op on the
  all-singleton smoke catalog).
- End-of-set: at 24/24 an extra Right held at 24/24, no error, no wrap.
- Zero-new-sidecar negative is NOT probative on this seed: every smoke asset
  ships seeded ratings/flags/keywords, and the launch catalog→sidecar sync
  legitimately wrote 23-24 sidecars (metadata_sync_state all 'synced';
  smoke-0 sidecar carries its seeded Rating="0"→ later checked smoke-2
  carried Rating="2"). Negative re-asserted on the burst seed below, whose
  assets carry no seeded metadata.

**lib-006 query field — PASS (Esc staging leg, the owed one)**
- Submitted `pick` → "6 photos" + Pick chip (SQL picks=6). Typed draft
  "draftxyz" (unsubmitted): Esc #1 cleared the text only (field no longer
  contains draftxyz, rc=1) while "Remove filter Pick" chip stayed; Esc #2
  cleared the chip (rc=1) and count restored to "24 photos".

**lib-008 chips — PASS (all legs)**
- Clean launch: no chips, no Clear-filters button (find rc=1).
- rating:3 + Add filter ▸ Flag ▸ Pick → exactly chips "Rating >= 3" and
  "Pick"; Clear filters appeared; count 3 == SQL AND(rating>=3 ∧ pick).
- Removing the Rating chip left Pick chip + its filter (count 6 = picks).
- `rating:4 sunset` → "Search: sunset" chip carries subtitle "Not a filter —
  matching file names and photo text"; the Rating >= 4 chip has none.
- Clear filters: all chips gone, button gone, count 24.

**lib-010 result header + save — PASS (all reachable legs)**
- Empty query: no interpretation line. `sunset` → exact header "No filter
  matched — searching file names and photo text for “sunset”". `rating:4`
  alone → no interpretation, "9 photos" == SQL (9 after smoke-2 got rated 5).
- Suggested chips (help "Add X filter"): Rating >= 4 / Pick / Reject all
  present; applying Rating >= 4 suppressed its suggestion while the active
  chip appeared; Pick/Reject suggestions remained.
- Save ▾ gating: with selection only → Snapshot + Save Selection (no Save
  Search); adding rating:4 → all 3 actions. No action ever appeared before
  its gate; the 1-action (no-selection) state was unreachable because a grid
  selection persisted and no clear-selection affordance was findable — noted,
  not a failure of the gating contract.

**app-008 batch metadata — PASS (all legs drivable on smoke)**
- ⌥⌘M opens the Batch Metadata popover from the keyboard; scope segments
  Selected / Visible / All Matches render with a count line (screenshots).
- Creator/Copyright fields start EMPTY with the preference defaults visible
  only as gray placeholders ("Scenario Tester", "© 2026 Scenario") —
  screenshot evidence; typed values land as values, placeholders persist
  after clearing.
- Keyword-only apply to a 2-photo Selected batch: exactly 2 catalog rows
  gained `scenario-kw`; smoke-0's inspector-set creator "Real Provenance"
  survived untouched; sidecars: exactly smoke-0/smoke-1 xmp carry
  scenario-kw, "Scenario Tester"/"2026 Scenario" appear in NO sidecar.
- All-catalog gate: "All Matches" scope shows "Confirm applying metadata to
  all 24 catalog photos."; pressing Apply with the box unchecked wrote
  nothing (popover stayed open, gate-kw rows = 0); Cancel → still 0.
- Menu-disabled-on-empty leg deferred to the empty seed.

**inspect-008 sidecar write semantics — PASS (write legs)**
- smoke-2 rated 5 (grid keyboard `5`): catalog rating=5; sidecar
  `smoke-2.jpg.xmp` now reads Rating="5"; original SHA-256 unchanged
  (660ca269bcc70b0d… before and after). Non-destructive invariant held.
- The "no sidecar from selection alone" negative is vacuous on smoke (seeded
  metadata syncs sidecars at launch — smoke-2's pre-gesture sidecar carried
  its seeded Rating="2", not a browsing Rating="0" spray). Negative driven
  on burst below.

### smokebig (`run/smokebig-1783824558`)

**cull-013 filmstrip — PASS**
- All scope: caption "frame 1 / 130" agrees with header "Frame 1 of 130"
  and `SELECT count(*)` = 130 — not the 120 page size (the persona-7 drift
  is gone). Stack denominator stays page-local (120) — the card scopes the
  fix to frame totals; scoped views stay scope-local by design.
- Scoped counts track the loaded window (Unrated 64 / Picks 32 / Rejects 24
  of the 120-asset page) per the card's "scope-local by design" note.
- Tile click (smoke-3.jpg) moved loupe focus → "Frame 3 of 104" (post-trash).
- Decision propagation: after P, exactly the picked tiles (smoke-3, -6, -9,
  -12 …) match --contains "Picked" via tile AXValue; undecided neighbors
  don't.

**cull-015 sidebar sources — PASS**
- Pre-op: sidebar "Picks, 35" / "Rejects, 26" / "Not analyzed yet, 130"
  == SQL 35/26/130 exactly.
- Bulk op (Move 26 Rejects to Trash, gate confirmed again): catalog
  104/0 rejects/35 picks; sidebar refreshed to "Picks, 35" /
  "Not analyzed yet, 104", Rejects row absent (zero-count omitted, not
  disabled); filmstrip "frame 1 / 104". All three surfaces agree —
  Marcus's stale-count defect (fa2c112c fix) verified closed.

### burst (`run/burst-1783824771`)

**cull-004 open question — Return DOES fire on a multi-frame stack: PASS,
plus one FAIL finding on the rail button**
- Loupe on frame 1 of a 3-frame auto-stack (smoke-0/1/2, flags
  reject/NULL/NULL). Return → one atomic gesture: smoke-0 → pick,
  smoke-1/2 → reject (SQL). Single ⌘Z reverted all three to
  reject/NULL/NULL. Dana's "Return did nothing" does not reproduce on the
  burst seed — promote-frame fires and is atomic.
- FAIL finding (card's rail-Keep-equals-Return spot-check): clicking the
  rail's "Keep frame 1 · cut 2" button wrote NOTHING — flags unchanged
  after both AXPress and a real CGEvent click, from the same state where
  Return worked. Inverse flavor of cull-018's noted Return/Keep-primary
  inconsistency; the rail primary is a silent no-op in the loupe on this
  seed.

**cull-002/inspect-008 zero-sidecar-from-browsing negative — PASS (via
unrated imports)**
- Every seeded catalog (smoke, burst) bakes ratings/flags, so launch-sync
  legitimately mirrors sidecars there — not probative. The probative set:
  the 6 card-dest copies and 4 dupfix in-place originals imported with NO
  metadata during these sessions, heavily browsed (arrows/Space/loupe,
  relaunches): `find` shows 0 .xmp beside any of them, and
  metadata_sync_state pending = 0. No Rating=0 spray.

### faces (`run/faces-1783824917`)

**people-009 scan — PASS (both status legs + scan)**
- Seed's source_roots pointed at the host path (nonexistent in VM):
  People showed "Photo sources offline — reconnect to scan", "Scan ready"
  absent — the aed1dbbe offline-status fix, verbatim.
- After fixing source_roots to the VM path + relaunch: "Scan ready"
  present, offline text gone. No clickable Scan button in the canvas
  (only the review-card caption text); People ▸ Scan for Faces menu item
  enabled (previews pre-cached; the disabled-window leg was unreachable —
  previews existed at first check).
- Scan: evaluation_signals faceCount 0→11, face_observations 0→11,
  provider breakdown exclusively apple-vision (46 signals total, all
  apple-vision — no other provider grew).

**people-001 canvas header — PASS**
- Header exactly "0 people · 11 photos with face signals" == P=0,
  max(FC,FQ)=max(11,11). Panels present: review strip ("Unnamed faces",
  "Face quality checks" cards), "ALL PEOPLE" grid.

**people-007 name selection — PASS core; batch leg blocked by a real
selection-lifetime finding**
- Baselines 0/0/0. Selection alone: no writes. "Name selection" sheet:
  subtitle "Groups the 1 selected photo under a new named person."
  (count present — the aed1dbbe fix), Create Person disabled on empty
  name (SE enabled=false), sheet-open wrote nothing.
- Create with "Test Person" → people +1, person_assets = 1 (selection
  size). Dismiss face review → dismissed_face_assets 0→1,
  people/person_assets untouched.
- Batch leg: a 2-photo ⌘-click batch in Library does NOT survive ⌘3 into
  People ("2 selected" note gone; subtitle truthfully reads 1). The
  subtitle is honest about what will be written (the fix's point), but
  the card's step-9 batch path can't produce a >1 link count via this
  route — finding, not a subtitle regression.

### geo (`run/geo-1783825469`) — offline VM (intended)

**worker-006 geocode backfill — PASS (retry-accounting legs)**
- geocode_queue row (48.86,2.29): attempt_count advanced 0→1→2→3 across
  ~30s-spaced passes, last_error non-null, last_attempted_at updating,
  row retained (not dropped), app never wedged (AX vended every poll).
  Bounded-retry ceiling (5) not waited out; the fixed claim (rows advance
  attempt_count/last_attempted_at on failing lookups) holds.

### empty (`run/empty-1783825621`)

**people-001 empty-state copy — PASS**
- Exact copy present: "These photos haven’t been scanned for faces yet.
  Scan for faces to see who’s in your photos." and "Confirm a suggested
  group, name faces yourself, or merge people. Nothing is saved until you
  confirm."
- Jargon negatives all clean: "evaluation", "review queues", "deferred",
  "face-box" match nothing in the AX tree.

**app-008 gating leg — PASS**
- Metadata ▸ Batch Metadata… reports enabled=false on the empty catalog.

## Verdict summary

| Row | Verdict |
|---|---|
| app-017 | PASS (gate, truth-banner, retire, counts) |
| app-010 | PASS (identical folder-flavor gate, move/restore) |
| cull-015 | PASS (counts agree pre/post bulk op) |
| cull-013 | PASS (catalog-wide frame numbers, badges, click) |
| import-004 | PASS preflight-truth legs; FAIL step 5 (dedupe-off re-import skips everything, A3==A2) |
| app-006 | PASS (all 7 legs) |
| app-008 | PASS (placeholders, keyword-only isolation, gate, empty-disable) |
| app-009 | PASS (resize, carry-on, carry-off) |
| activity-006 | PASS (filtered-out asset detected; toast verbatim) |
| lib-008 | PASS |
| lib-010 | PASS (1-action save state unreachable, noted) |
| lib-006 | PASS (Esc staging live) |
| cull-005 | PASS (toast every press, exact counts) |
| cull-009 | FAIL hint leg (reappears every Cull re-entry); overlay legs PASS |
| cull-002 | PASS (nav, no-ops, end-of-set, negative via unrated imports) |
| inspect-008 | PASS (rating→sidecar, original untouched, negative) |
| people-001 | PASS (header + empty-state copy) |
| people-007 | PASS core; batch-selection dies on workspace switch (finding) |
| people-009 | PASS (offline status + healthy scan) |
| worker-006 | PASS (attempt accounting offline) |
| cull-004 | Return fires on real stack: PASS; rail Keep button silent no-op: FAIL finding |

App quit; VM left running (bridged networking; see setup note).
