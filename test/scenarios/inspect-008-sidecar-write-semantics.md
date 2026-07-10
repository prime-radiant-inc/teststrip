# inspect-008-sidecar-write-semantics: every edit writes catalog first, then sidecar; worker presence changes sync timing

**What this covers**: inventory items 53-55 plus the original rate-writes
happy path. Every metadata edit writes the catalog first and then syncs to
the `.xmp` sidecar; original image bytes are never touched. When the worker
process is present, the sidecar write is queued and the asset shows
"pending" until the worker drains it; when the worker is absent, the sidecar
write happens synchronously inline. This applies uniformly to every edit
surface — field changes, suggested-keyword accepts, OCR caption accepts, and
conflict-resolution actions (Retry/Use XMP/Merge Missing) all go through the
same catalog-then-sidecar path. This card proves the core non-destructive
promise on its positive path — setting a star rating in the inspector writes
a portable `.xmp` sidecar mirroring the rating while the original is
untouched; `script/verify_metadata_write.sh` checks it at the metric level,
this card proves it through the assembled inspector UI.

## Pre-state
- Fresh build, isolated catalog:
  ```bash
  ./script/build_and_run.sh --smoke
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  DB="$ISOLATED/Teststrip/catalog.sqlite"
  ```
- Pick a target original and record its pre-state (ground truth):
  ```bash
  SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
  ORIG_SUM=$(shasum "$SRC" | awk '{print $1}')
  test ! -e "$SRC.xmp" && echo "no sidecar yet"    # rating hasn't been set, so none should exist
  ```

## Steps
1. **Select the photo.** `script/activate_app.sh Teststrip`; AX-press the grid
   thumbnail whose accessible label is `$SRC`'s basename so the inspector binds
   to it.
2. **Assert nothing is written before the gesture** (confirm-before-write):
   ```bash
   test ! -e "$SRC.xmp" && echo "still no sidecar: OK"
   ```
   Merely selecting/browsing must not create a sidecar.
3. **Set a 5-star rating.** AX-press the inspector rating button whose
   accessible label (help text) is **"Rate 5"**. Re-dump; confirm the selected
   asset now renders **"5 STAR"** (the decision badge).
4. **Assert the sidecar was written with the rating**:
   ```bash
   test -f "$SRC.xmp" && echo "sidecar written"
   grep -qiE 'Rating>?5|xmp:Rating="5"' "$SRC.xmp" && echo "rating 5 in xmp"
   ```
   (The exact XMP serialization may be attribute or element form — match either.)
5. **Assert the original is byte-for-byte unchanged**:
   ```bash
   NOW_SUM=$(shasum "$SRC" | awk '{print $1}')
   [ "$NOW_SUM" = "$ORIG_SUM" ] && echo "original untouched"
   ```

## Expected
- Step 2: no `$SRC.xmp` exists. **Fails if** a sidecar appears from selection
  alone — that violates confirm-before-write; report it, don't excuse it.
- Step 3: badge reads `5 STAR`. **Fails if** the rating didn't take in the UI.
- Step 4: `$SRC.xmp` now exists and encodes rating 5. **Fails if** no sidecar
  was written, or it doesn't carry the rating. Quote the relevant XMP line.
- Step 5: the original's checksum equals `ORIG_SUM`. **Fails if** the hash
  changed — the original was rewritten, the cardinal sin. Quote both hashes.

## Cleanup
```bash
rm -f "$SRC.xmp"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- Sidecar naming: default is `<original-filename>.xmp` (e.g. `IMG_1.jpg.xmp`).
  If an existing Adobe-style `<basename>.xmp` (no original extension) is bound
  to this original, the rating updates *that* file instead — check for both
  `$SRC.xmp` and the basename form before concluding nothing was written.
- The rating buttons are five separate star buttons each helped "Rate \<n\>";
  press "Rate 5", not the first star. There is also a "Clear rating" / "0"
  button — don't confuse it for a star.
- `grep` on the XMP is a coarse check; if it fails, dump the file and inspect
  the actual `xmp:Rating` serialization before declaring a miss — the write may
  be present in a form the regex didn't anticipate (fix the card, per
  "executing the card tests the card").
