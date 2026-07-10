# Releasing Teststrip

Tagging `vX.Y.Z` and pushing the tag builds, Developer ID-signs, notarizes,
staples, and publishes `Teststrip.app` to a GitHub Release with a Sparkle
auto-update appcast, via `.github/workflows/release.yml`. For the manual
signing/notarization pipeline itself (`script/package_release.sh`), see
`docs/distribution.md` — this doc covers the release-automation layer on top:
the tag trigger, the Sparkle appcast, and the one-time secrets setup.

## One-time setup: repository secrets

The workflow needs these secrets on `prime-radiant-inc/teststrip` (Settings →
Secrets and variables → Actions). Verify what's set with:

```sh
gh secret list --repo prime-radiant-inc/teststrip
```

| Secret | What it is |
|--------|-----------|
| `DEVELOPER_ID_APPLICATION_SIGNING_IDENTITY` | `Developer ID Application: Jesse Vincent (87WJ58S66M)` |
| `APPLE_TEAM_ID` | `87WJ58S66M` |
| `DEVELOPER_ID_APPLICATION_CERT_BASE64` | base64 of the Developer ID Application `.p12` (single-identity) |
| `DEVELOPER_ID_APPLICATION_CERT_PASSWORD` | password for that `.p12` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | app-specific password for that Apple ID |
| `SPARKLE_PRIVATE_ED_KEY` | Sparkle EdDSA private key (matches `SUPublicEDKey` baked into `Info.plist` by `script/lib/app_bundle.sh`) |

Teststrip reuses the same Sparkle EdDSA keypair as clipfan/clearance
(`SUPublicEDKey = ZY/ZPlRrnPohsWVic4GcjZ8tJg8qScm9MRHj3EWO4mg=`), so
`SPARKLE_PRIVATE_ED_KEY` is the same private key value already used for those
repos' `SPARKLE_PRIVATE_ED_KEY` secret.

### Exporting the Developer ID `.p12`

The `.p12` export is interactive (Keychain Access) and can't be scripted:

1. Open Keychain Access → `login` keychain → `My Certificates`.
2. Find `Developer ID Application: Jesse Vincent (87WJ58S66M)`.
3. Right-click → Export → save as `developer-id-application.p12`, set an
   export password.
4. Set the two secrets from that file:

```sh
base64 -i developer-id-application.p12 | gh secret set DEVELOPER_ID_APPLICATION_CERT_BASE64 --repo prime-radiant-inc/teststrip
gh secret set DEVELOPER_ID_APPLICATION_CERT_PASSWORD --repo prime-radiant-inc/teststrip
rm developer-id-application.p12
```

### Apple app-specific password

`APPLE_APP_SPECIFIC_PASSWORD` cannot be recovered once created; generate a new
one at https://account.apple.com → Sign-In and Security → App-Specific
Passwords if it's ever lost, then:

```sh
gh secret set APPLE_APP_SPECIFIC_PASSWORD --repo prime-radiant-inc/teststrip
```

## Cutting a release

The tag drives the version (`vX.Y.Z` → `CFBundleShortVersionString X.Y.Z`); the
build number is the workflow run number.

```sh
git tag v0.2.0
git push origin v0.2.0
```

The workflow then:

1. builds + Developer ID-signs the app bundle (`script/package_release.sh
   --sign-only`), including the embedded, hardened-runtime-signed
   `Sparkle.framework`;
2. notarizes + staples;
3. builds Sparkle's `generate_appcast` tool from source and signs the release
   zip with `SPARKLE_PRIVATE_ED_KEY`;
4. publishes the `.zip`, `.dmg`, and `appcast.xml` to the GitHub Release.

Installed copies pick up the update from
`https://github.com/prime-radiant-inc/teststrip/releases/latest/download/appcast.xml`
(`SUFeedURL` in `Info.plist`).

## Local verification before tagging

```sh
swift test
script/package_release.sh --dry-run
```

`--dry-run` proves the build, bundle assembly, and Sparkle.framework embedding
with an ad-hoc signature (no real certs needed). To exercise real Developer ID
signing locally (skipping notarization):

```sh
script/package_release.sh --sign-only --identity "Developer ID Application: Jesse Vincent (87WJ58S66M)"
codesign -dv --verbose=4 dist/Teststrip.app/Contents/Frameworks/Sparkle.framework
```
