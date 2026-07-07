# export-presets-with-exif: Export copies with an optional EXIF/IPTC carry

**What this covers**: the export surface — the toolbar **Export** popover, its
Format/Quality/Long-edge settings, presets, and the **"Include EXIF/IPTC
metadata"** checkbox (`includeSourceMetadata`, Jesse's explicit ask: EXIF/IPTC
optional, checkbox at export). The load-bearing assertions are on the exported
files: a resized JPEG is actually written at the requested long edge, and the
EXIF/IPTC checkbox governs whether metadata rides along — checked carries it,
unchecked strips it.

## Pre-state
- Fresh build, isolated catalog:
  ```bash
  ./script/build_and_run.sh --isolated
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  ```
- Scratch export destination: `OUT=$(mktemp -d)/export` (let the app create it).
- At least one photo visible in the grid.

## Steps
1. **Open Export.** `script/activate_app.sh Teststrip`; AX-press the toolbar
   button labeled **"Export"**. `waitFor` an `AXStaticText` **"Export Photos"**.
2. **Set a resize + carry metadata ON.** In the popover: leave Format = JPEG,
   type `1024` into the **"Long edge"** field, and ensure the checkbox
   **"Include EXIF/IPTC metadata"** is CHECKED (read its AX value; toggle if
   needed).
3. **Run the export.** AX-press the export confirm button (the popover's
   primary action; its label is the presentation `exportTitle`, e.g.
   "Export N"). In the native destination panel, Cmd+Shift+G → `$OUT` → confirm.
   `waitFor` the export to report completion (progress clears / success text).
4. **Assert a resized JPEG landed with metadata**:
   ```bash
   F=$(ls "$OUT"/*.jpg "$OUT"/*.jpeg 2>/dev/null | head -1); echo "$F"
   sips -g pixelWidth -g pixelHeight "$F"          # long edge must be 1024
   sips -g hasAlpha "$F" >/dev/null && echo "readable jpeg"
   /usr/bin/mdls -name kMDItemExifApertureValue -name kMDItemISOSpeed "$F"   # metadata present
   ```
5. **Export again with metadata OFF.** Re-open Export, same 1024 long edge,
   UNCHECK "Include EXIF/IPTC metadata", export to `OUT2=$(mktemp -d)/export`.
6. **Assert the stripped copy dropped metadata**:
   ```bash
   G=$(ls "$OUT2"/*.jpg "$OUT2"/*.jpeg 2>/dev/null | head -1)
   /usr/bin/mdls -name kMDItemExifApertureValue "$G"   # should be (null)
   ```

## Expected
- Step 3: an export completion signal within 30s. **Fails if** none appears or
  an error alert shows.
- Step 4: exactly one dimension equals 1024 and the other ≤ 1024; `sips` reads
  the file (valid JPEG); at least one EXIF field is present. **Fails if** the
  file is full-size (resize ignored), unreadable, or carries no EXIF when the
  box was checked. Quote the actual `sips` dimensions.
- Step 6: the same EXIF field reads `(null)` / absent. **Fails if** metadata
  survived with the box unchecked — the checkbox is not governing the carry.
  Quote both `mdls` outputs (checked vs unchecked) side by side.

## Cleanup
```bash
rm -rf "$(dirname "$OUT")" "$(dirname "$OUT2")"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- The destination is a native `NSOpenPanel` (`exportDestinationParent`); drive
  it via Cmd+Shift+G as in the reject card. No typed-path hook exists — if AX
  can't reach the panel, report the driveability gap.
- Synthetic `--isolated` fixtures may carry little/no EXIF, which would make the
  step-4 "metadata present" assertion vacuous. Confirm the seeded originals
  actually have EXIF (`mdls` a source original first); if they don't, run this
  card against `--sample-photos` or a real-EXIF fixture instead, and say which
  corpus you used. A vacuous "present" check is a failed check.
- `sips` reports the *stored* pixel dimensions; `includeSourceMetadata` resets
  orientation to 1 and drops pixel-dimension tags on export, so trust `sips`
  geometry over any EXIF dimension tag.
