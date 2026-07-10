# dev-005: package_release.sh --sign-only (Developer ID sign, no notarization)

**What this covers**
As a developer I want `script/package_release.sh --sign-only` to build,
assemble, and sign the release `.app` with a real Developer ID Application
certificate (inside-out: worker helper → Sparkle framework → outer app),
verify the signature, and package it — stopping *before* notarization so CI
can run notarization as its own separate, retriable step. Covers the
`--sign-only` capability-inventory entry for `script/package_release.sh`.
Notarization/stapling (`xcrun notarytool` / `xcrun stapler`) is explicitly
**out of scope** for this card — see `dev-004` for the credential-free
`--dry-run` path, which is the only path this card actually exercises live.

## Pre-state
- Checked this Mac's signing identities:
  ```bash
  security find-identity -v -p codesigning
  ```
  Result on this machine (2026-07-09/10):
  ```
    1) 6F56D754CF230FABBC19D8739BEDC5477DF6A3D0 "Developer ID Application: Jesse Vincent (87WJ58S66M)"
    2) B54A6B34D0E52FD2D7EB5F6EA16D094BF55F3365 "Apple Development: Jesse Vincent (P82MJJHK76)"
       2 valid identities found
  ```
  A real **Developer ID Application** identity (`87WJ58S66M`) is present in
  the login keychain on this Mac, so the **success path** below applies here.
  Per the task brief, this card documents both the success path and the
  failure path, but does **not** execute `--sign-only` live even though a
  valid identity exists — `--sign-only` signs with a real cert and, unlike
  `--dry-run`, its Developer ID signature could plausibly get exercised
  against Gatekeeper/notarization infra later by whoever runs this card; treat
  invocation as documentation/inspection-only unless Jesse explicitly opts in
  to a live signing run.

## Steps (documented, not executed live — see Pre-state)
```bash
cd /Users/jesse/git/projects/teststrip

# Success path (identity present, as on this Mac):
./script/package_release.sh --sign-only \
  --identity "Developer ID Application: Jesse Vincent (87WJ58S66M)"
echo "exit: $?"

# Equivalent via env var + positional arg forms the script also accepts:
TESTSTRIP_SIGNING_IDENTITY="Developer ID Application: Jesse Vincent (87WJ58S66M)" \
  ./script/package_release.sh --sign-only

# Failure path A — no identity supplied at all (missing credentials):
./script/package_release.sh --sign-only
echo "exit: $?"   # expect 3

# Failure path B — identity string supplied but not present in keychain:
./script/package_release.sh --sign-only --identity "Developer ID Application: Nobody (0000000000)"
echo "exit: $?"   # expect 4
```

## Expected
- **Success path** (`SIGN_ONLY=1`, `SIGNING_IDENTITY` set and present in
  keychain; `script/package_release.sh:226-238`):
  - Runs `build_and_assemble` (real `swift build -c release`), then
    `sign_developer_id` which signs, inside-out: Sparkle.framework's nested
    XPC services/Autoupdate/Updater.app, then the worker binary
    (`--entitlements config/macos/TeststripWorker.entitlements`), then the
    outer `.app` (`--entitlements config/macos/Teststrip.entitlements`) —
    each via `codesign --force --timestamp --options runtime --sign
    "$identity"`.
  - `verify_signature` (`codesign --verify --deep --strict --verbose=2`)
    passes.
  - `package_artifact` writes `dist/Teststrip-<version>.zip` (or `.dmg` with
    `--dmg`).
  - Log ends with: `==> Sign-only complete: <path> (Developer ID signed, NOT
    notarized)` and exit code `0`.
  - Notarization (`notarize_and_staple`) and Gatekeeper verification
    (`verify_distribution`) are **not** called — confirmed by their absence
    from the `SIGN_ONLY` branch in `main()` (script lines 226-238), which
    `return 0`s right after `package_artifact`.
- **Failure path A — missing identity** (`script/package_release.sh:227-229`):
  stdout/stderr prints `print_credential_guidance` (the full "Release
  packaging needs Developer ID signing + notarization credentials..." block,
  including the `security find-identity -v -p codesigning` hint and the
  `xcrun notarytool store-credentials` example), followed by
  `error: missing signing identity; see guidance above` on stderr, and
  **exit code 3** (`die "..." 3` at line 229 — the `3` is the "missing
  credentials" exit code documented in the script's header comment, line 46).
- **Failure path B — identity not in keychain**
  (`require_signing_identity_present`, `script/package_release.sh:205-210`):
  stderr prints `error: signing identity not found in keychain: <identity>
  (run: security find-identity -v -p codesigning)`, and **exit code 4** (`die
  "..." 4` at line 208 — "signing identity not found in keychain" per the
  header comment, line 46). This path is reached *after* the identity-present
  check (`-z "$SIGNING_IDENTITY"`) passes but *before* any build work starts,
  so it fails fast without a wasted `swift build -c release`.

## Cleanup
Not applicable — no live run was executed by this card (see Pre-state). If a
future run of this card does execute `--sign-only` live:
```bash
rm -rf /Users/jesse/git/projects/teststrip/dist
```

## Sharp edges
- Exit codes 3 and 4 are easy to conflate: **3** = no identity string was
  ever supplied (env var, `--identity`, and positional arg all empty); **4**
  = an identity string *was* supplied but doesn't match anything
  `security find-identity -v -p codesigning` returns. The `require_signing_identity_present`
  check does a `grep -qF` substring match against the full identity listing,
  so a partial/malformed identity string can still hit exit 4 even if the
  real cert is present, if the string doesn't substring-match exactly.
- `--sign-only` and plain positional-arg invocation
  (`./script/package_release.sh "Developer ID Application: ..."`) are
  equivalent per the arg parser's fallthrough `*) SIGNING_IDENTITY="$1"`
  case — the identity can be passed three ways (env var, `--identity`,
  bare positional) and the card's Steps show two of them; worth knowing if a
  human runs it from muscle memory with the older bare-arg calling
  convention.
- This card documents but does not execute `--sign-only`'s success path live,
  per the task brief's caution about local-signing side effects; if Jesse
  wants a live-verified success-path run captured in this repo's card
  history, that requires explicit opt-in and should get its own follow-up
  card run, not a silent addition here.
