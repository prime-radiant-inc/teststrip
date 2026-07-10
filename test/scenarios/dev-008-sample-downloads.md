# dev-008-sample-downloads: Sample photo and face-model download scripts

**What this covers**
As a developer setting up a machine for real-photo/face-recognition work, I
want `script/download_sample_photos.sh` (checksum-verified, idempotent
manifest downloader) and `script/download_face_model.sh` (its AuraFace-model
wrapper) to report their config safely without downloading, honor `--limit`,
and skip re-downloading files that already verify. Covers
`script/download_sample_photos.sh` and `script/download_face_model.sh`; no
capability-inventory entry names these directly but they gate every
sample-photo/face-recognition card's Pre-state.

**Network required — SKIP-offline convention applies.** Steps 1–2
(`--print-config`) are safe and always run. Steps 3+ (an actual small
download) require network reachability; if the preflight connectivity check
fails, this card's outcome is **"SKIP (offline)"**, which is an acceptable,
non-failing result — do not treat SKIP as a card failure.

## Pre-state
- Repo checkout. No build required — both are `#!/bin/zsh` scripts run
  directly.
- Manifests already in the repo:
  `sample-data/wordpress-photo-directory.tsv` (photos),
  `sample-data/face-recognition-model.tsv` (face model, read by
  `download_face_model.sh` via its own `--manifest` call into
  `download_sample_photos.sh`).
- Preflight connectivity check (same convention as
  `script/verify_reverse_geocode_smoke.sh`, which prints `SKIP no network`
  and exits 0 when offline):
  ```bash
  if ! /usr/bin/curl --silent --head --max-time 5 https://www.apple.com >/dev/null 2>&1; then
    echo "SKIP (offline)"
    exit 0
  fi
  ```

## Steps
1. **`--print-config`, sample photos (safe, no download).**
   ```bash
   ./script/download_sample_photos.sh --print-config
   ```
2. **`--print-config` with `--limit`.**
   ```bash
   ./script/download_sample_photos.sh --print-config --limit 5
   ```
3. **Run the offline preflight check** shown in Pre-state. If it prints
   `SKIP (offline)`, stop here — the card's outcome is SKIP and steps 4–6 are
   not run.
4. **Small live download with `--limit`**, into a throwaway destination (not
   the repo's `sample-data/photos/wordpress-photo-directory`, to avoid
   touching committed-adjacent working state):
   ```bash
   DEST=$(mktemp -d)/sample-photos-dev008
   ./script/download_sample_photos.sh --destination "$DEST" --limit 2
   ```
5. **Idempotence: second run against the same destination verifies via
   md5+size and re-uses existing files** (per `verify_file()`, lines 82–92,
   which checks `md5_value` then `byte_count` against the manifest's
   recorded `expected_md5`/`expected_size` columns before deciding a file is
   already "kept"):
   ```bash
   ./script/download_sample_photos.sh --destination "$DEST" --limit 2
   ```
6. **Face-model wrapper** (only if network is up; downloads+unzips into
   `sample-data/models/`, which is gitignored — this is the one step that
   writes into the repo tree, but only a gitignored path):
   ```bash
   ./script/download_face_model.sh
   ```

## Expected
- Step 1: exit `0`, stdout exactly:
  ```
  manifest=/Users/jesse/git/projects/teststrip/sample-data/wordpress-photo-directory.tsv
  destination=/Users/jesse/git/projects/teststrip/sample-data/photos/wordpress-photo-directory
  limit=0
  ```
  (captured live on this checkout; `manifest`/`destination` are absolute
  paths derived from `$ROOT_DIR`, so they'll match any checkout at this
  layout). **Fails if** anything downloads or `sample-data/photos/` changes.
- Step 2: same as step 1 but `limit=5`. **Fails if** `--limit` changes
  `manifest`/`destination`, or `--print-config` still respects `--limit`
  incorrectly (e.g. prints `limit=0`).
- Step 3: either no output (network up, continue) or `SKIP (offline)` (exit
  0) — in the SKIP case, the card ends here and that is a pass, not a
  failure.
- Step 4: exit `0`. Stdout has one `downloaded <filename>` line per new file
  (exactly 2, since `--limit 2`) and a final summary line:
  `sample photos ready: destination=$DEST total=2 downloaded=2 kept=0`.
  **Fails if** `downloaded` count != 2, or if checksum verification is
  silently skipped (the script's `verify_file()` always checks md5 first,
  size only when the manifest's `expected_size` column is non-empty/non-zero
  — a `checksum or size mismatch` message on stderr with exit 1 would be a
  genuine failure here, not expected).
- Step 5: exit `0`. Stdout has `kept <filename>` for both files (no
  `downloaded` lines), final summary
  `sample photos ready: destination=$DEST total=2 downloaded=0 kept=2`.
  **Fails if** `downloaded` is nonzero on the second run — that means
  `verify_file()`'s md5/size check isn't actually gating re-download.
- Step 6: exit `0`, final line `face model ready: /Users/jesse/git/projects/teststrip/sample-data/models/auraface-v1.mlpackage`,
  and `sample-data/models/auraface-v1.mlpackage` exists as a directory
  (`.mlpackage` bundles are directories, not files — `ditto -x -k` unzips
  the `.zip` in place per the wrapper's lines 42–48).

## Cleanup
```bash
rm -rf "$DEST"   # only if step 4/5 ran; $DEST is a throwaway mktemp dir this card created
```
`sample-data/models/auraface-v1.mlpackage` (step 6) is intentionally left in
place — it's gitignored, machine-local cached state that other
face-recognition cards and dogfood sessions expect to already be present;
do not delete it as part of this card's cleanup.

## Sharp edges
- `download_sample_photos.sh --limit` counts *manifest rows processed*, not
  just newly downloaded files — a `--limit 2` run against a destination that
  already has the first file kept will still only process 2 total rows (1
  kept + 1 downloaded), not download 2 new files. Don't misread `total=` as
  "downloaded count."
- The safety check on `filename` (`unsafe manifest filename` on `/` or `..`,
  lines 103–106) only guards the manifest-supplied filename column, not the
  `--destination` argument itself — a malicious/typo'd `--destination` isn't
  validated at all.
- `download_face_model.sh` has no `--print-config`/dry-run mode of its own;
  it always shells out straight to `download_sample_photos.sh` (no
  `--print-config` flag passed), so there is no safe way to preview its
  effective manifest/destination without either reading the script or
  letting it actually attempt the download. This card's step 6 is the only
  fully safe way to know the wrapper works, and it's gated on network.
- Both scripts use `curl -fsSL --retry 3 --retry-all-errors`, so a flaky-but-
  not-fully-offline network could retry for a while before failing loudly
  rather than cleanly SKIPping — the offline preflight in this card's Steps
  3 only prevents the *fully offline* case, not partial connectivity.
