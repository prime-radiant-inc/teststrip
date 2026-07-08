# Distribution: signing, notarization, packaging

`script/package_release.sh` turns a Teststrip source tree into a distributable,
Developer ID-signed, Apple-notarized, stapled `.app` packaged as a `.zip`
(default) or `.dmg` in `dist/`. It is the release counterpart to
`script/build_and_run.sh`, which only ad-hoc signs an unsigned dev bundle. Both
share the bundle-assembly logic in `script/lib/app_bundle.sh`, so the shipped
layout matches what you dogfood.

## One-time setup

Distribution needs two credentials. Neither is hardcoded; both come from your
environment / login keychain.

### 1. Developer ID Application certificate

You need a **Developer ID Application** certificate in your login keychain
(this is the cert type Gatekeeper accepts for apps distributed outside the App
Store). Check whether you already have one:

```sh
security find-identity -v -p codesigning
```

Look for a line like `Developer ID Application: Your Name (TEAMID)`. If it is
missing, create/download it from the Apple Developer portal
(Certificates → Developer ID Application) and import it into the login keychain.
Then expose it to the pipeline:

```sh
export TESTSTRIP_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
```

### 2. notarytool keychain profile

Notarization credentials are stored once as a `notarytool` keychain profile —
either an App Store Connect API key (recommended) or your Apple ID plus an
app-specific password.

```sh
# App Store Connect API key (recommended):
xcrun notarytool store-credentials "TeststripNotary" \
    --key "/path/AuthKey_XXXX.p8" --key-id "KEYID" --issuer "ISSUER-UUID"

# or Apple ID + app-specific password:
xcrun notarytool store-credentials "TeststripNotary" \
    --apple-id "you@example.com" --team-id "TEAMID" \
    --password "app-specific-password"
```

Then point the pipeline at that profile:

```sh
export TESTSTRIP_NOTARY_PROFILE="TeststripNotary"
```

## Running the pipeline

```sh
script/package_release.sh
```

Full run steps:

1. Release build of `TeststripApp` + `TeststripWorker` (`swift build -c release`).
2. Assemble the `.app`, including the bundled Core ML face model.
3. Sign **inside-out** with Developer ID Application + hardened runtime:
   worker helper → Core ML model → outer `.app`. Inner code is signed before the
   outer seal that covers it.
4. Notarize with `xcrun notarytool submit --wait`, then `xcrun stapler staple`
   the ticket onto the `.app`.
5. Package into `dist/Teststrip-<version>.<zip|dmg>`.
6. Verify: `codesign --verify --deep --strict`, `spctl -a -vvv` (Gatekeeper
   assessment), and `xcrun stapler validate`.

Useful flags:

- `--dmg` — package a `.dmg` instead of the default `.zip`.
- `--identity <id>` / `--profile <name>` — override the env vars per run.
- `--dry-run` — build + assemble + **ad-hoc** sign + `codesign --verify` only.
  No real certs needed; proves the build and bundle assembly. The resulting
  artifact is **not** distributable (ad-hoc signed, unnotarized), and Gatekeeper
  assessment / stapler validation are skipped because they cannot pass for an
  ad-hoc signature.
- `-h` / `--help` — usage.

Version strings default to `0.1.0` / `1` and can be overridden with the
`TESTSTRIP_SHORT_VERSION` / `TESTSTRIP_BUNDLE_VERSION` env vars (they set both
the `Info.plist` and the artifact filename).

If either credential is missing on a full run, the script prints exactly what to
provide and exits (code 3). Exit codes: `0` success, `2` usage error,
`3` missing credentials, `4` signing identity not found in keychain.

## What distribution does NOT change (out of scope)

Building a signed, notarized bundle is purely a packaging concern. It does not
expand the product's feature scope. The following remain out of scope and are
untouched by this pipeline:

- **Lightroom catalog migration** — importing existing Lightroom catalogs.
- **Editing** — Teststrip stays a culling app; it is not an image editor.
- **Watched folders** — automatic ingest of folders as they change.
- **iOS** — this is a macOS-only pipeline; there is no iOS build or companion.
