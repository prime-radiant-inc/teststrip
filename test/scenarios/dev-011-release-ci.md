# dev-011-release-ci: Release workflow vs RELEASING.md static consistency

**What this covers**
As a developer I want confidence that `.github/workflows/release.yml` still
matches what `docs/RELEASING.md` documents as the release flow, and that its
secret references and pinned tool revision haven't silently drifted, without
ever pushing a real tag. This covers the "release automation stays
documentation-accurate" leg of the capability inventory. **STATIC-ONLY: no
execution of the workflow.** The workflow can only truly be exercised by
pushing a `v*` tag with all repo secrets configured — that is explicitly out
of scope for this card.

## Pre-state
None — read-only inspection of two files plus one live, read-only
`gh secret list` call (lists secret *names* only, never values).

## Steps
1. Read the workflow in full:
   ```bash
   cat .github/workflows/release.yml
   ```
2. Read the docs in full:
   ```bash
   cat docs/RELEASING.md
   ```
3. Cross-check secret names referenced in the workflow (`secrets.X`) against
   what's actually set on the repo (read-only, names only):
   ```bash
   gh secret list --repo prime-radiant-inc/teststrip
   ```
4. Confirm the Sparkle appcast generator step is pinned to a commit SHA, not
   a floating tag/branch:
   ```bash
   grep -A1 "SPARKLE_REVISION" .github/workflows/release.yml
   ```

## Expected

**Structural match, workflow vs. RELEASING.md — no drift found:**

- Trigger: `on: push: tags: ["v*"]` (workflow line 3-6) matches
  RELEASING.md's "Tagging `vX.Y.Z` and pushing the tag" (line 3) and the
  `git tag v0.2.0 && git push origin v0.2.0` cutting-a-release example.
- Version derivation: workflow does
  `VERSION="${TESTSTRIP_SHORT_VERSION_TAG#v}"` from `github.ref_name`
  (line 53) and sets `TESTSTRIP_BUNDLE_VERSION="${GITHUB_RUN_NUMBER}"`
  (line 55) — matches RELEASING.md's "The tag drives the version (`vX.Y.Z` →
  `CFBundleShortVersionString X.Y.Z`); the build number is the workflow run
  number" (lines 62-63).
- Keychain setup (lines 22-42): imports `DEVELOPER_ID_APPLICATION_CERT_BASE64`
  and unlocks with `DEVELOPER_ID_APPLICATION_CERT_PASSWORD` — matches the
  one-time-setup secrets table in RELEASING.md (lines 19-27).
- `package --sign-only` step (line 60): runs
  `bash script/package_release.sh --sign-only --identity "$TESTSTRIP_SIGNING_IDENTITY"`
  — matches RELEASING.md step 1 of "The workflow then:" (lines 72-74),
  including the parenthetical about the embedded, hardened-runtime-signed
  Sparkle.framework.
- Notarize/staple (lines 66-111): `xcrun notarytool submit ... --wait`, then
  `xcrun stapler staple`, then zip+dmg via `ditto`/`hdiutil` — matches
  RELEASING.md step 2 (line 75) and the "publishes the `.zip`, `.dmg`, and
  `appcast.xml`" line (78).
- Appcast: builds Sparkle's `generate_appcast` from source (lines 113-130),
  then runs it with `--ed-key-file` sourced from `SPARKLE_PRIVATE_ED_KEY`
  (lines 132-150) — matches RELEASING.md step 3 (lines 76-77) and the Sparkle
  EdDSA key note (lines 29-32).
- GitHub Release (lines 152-166): `gh release create ... --generate-notes` or
  `gh release upload ... --clobber` if the tag's release already exists,
  uploading zip/dmg/appcast.xml — matches "publishes ... to a GitHub Release"
  (RELEASING.md line 4) and step 4 (line 78).
- No drift found between the workflow's job/step structure and what
  RELEASING.md documents as the flow.

**Secret name cross-check (live `gh secret list` result at time of this
card's authoring):**
```
APPLE_ID                                     2026-07-10T16:53:35Z
APPLE_TEAM_ID                                2026-07-10T16:53:28Z
DEVELOPER_ID_APPLICATION_SIGNING_IDENTITY    2026-07-10T16:53:31Z
SPARKLE_PRIVATE_ED_KEY                       2026-07-10T16:53:25Z
```
Workflow references (`secrets.X`) found in `release.yml`:
`DEVELOPER_ID_APPLICATION_CERT_BASE64`, `DEVELOPER_ID_APPLICATION_CERT_PASSWORD`,
`DEVELOPER_ID_APPLICATION_SIGNING_IDENTITY`, `APPLE_ID`,
`APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`, `SPARKLE_PRIVATE_ED_KEY`.

**Drift found (informational — secrets can be org-level, so this is not a
hard failure, but flag it):** three of the seven workflow-referenced secrets
are **not present** in this repo's secret list —
`DEVELOPER_ID_APPLICATION_CERT_BASE64`, `DEVELOPER_ID_APPLICATION_CERT_PASSWORD`,
and `APPLE_APP_SPECIFIC_PASSWORD`. If these are not set at the org level
either, the "Setup Signing Keychain" step and the "Notarize, Staple, Package"
step will fail on the next tag push with an empty/unset secret. Worth
confirming with `gh secret list --repo prime-radiant-inc/teststrip --org`
equivalent or checking org-level secrets before the next release, since
RELEASING.md's setup instructions (lines 44-47, 56-57) assume these are
repo-level `gh secret set` targets.

**Sparkle pin:** the appcast generator step pins to a commit SHA, not a
floating tag —
```yaml
SPARKLE_REVISION: 6276ba2b404829d139c45ff98427cf90e2efc59b
```
(`.github/workflows/release.yml` line 115), and the step asserts the checkout
actually landed on that SHA (`test "$(git -C "$SPARKLE_SOURCE" rev-parse HEAD)" = "$SPARKLE_REVISION"`,
line 124) — this is a real commit pin, not a branch/tag reference.

**Out of scope, stated explicitly:** this card does not push a `v*` tag and
does not exercise notarization, stapling, appcast generation, or GitHub
Release creation — those require all workflow secrets to be genuinely
configured (including the three found missing above) and burn a real Apple
notarization submission. Only static structural/doc consistency and the
Sparkle pin are verified here.

## Cleanup
None — no state was created.

## Sharp edges
- The missing `DEVELOPER_ID_APPLICATION_CERT_BASE64` /
  `DEVELOPER_ID_APPLICATION_CERT_PASSWORD` / `APPLE_APP_SPECIFIC_PASSWORD`
  secrets are the most actionable finding here: if they're truly absent (not
  just invisible to this token/scope), the release workflow will fail at the
  keychain-import step on the very first tag push. This card does not attempt
  to set them — RELEASING.md documents the (interactive, unscriptable) `.p12`
  export process for the cert secrets and the app-specific-password
  generation URL.
- `gh secret list` only shows names/update timestamps, never values, so this
  check cannot confirm a present secret still holds a *correct* value (e.g.
  an expired app-specific password would still show up as present).
