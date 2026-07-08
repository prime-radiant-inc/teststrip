#!/usr/bin/env bash
set -euo pipefail

# Release packaging pipeline for Teststrip.
#
# Produces a distributable, Developer ID-signed, notarized, stapled .app
# packaged as a zip (default) or .dmg in dist/. This is the distribution
# counterpart to script/build_and_run.sh (which ad-hoc signs an unsigned dev
# bundle). Both share the assembly logic in script/lib/app_bundle.sh.
#
# Pipeline steps (full run):
#   1. Release build of TeststripApp + TeststripWorker (swift build -c release).
#   2. Assemble the .app bundle, incl. the bundled Core ML face model.
#   3. Sign inside-out with Developer ID Application + hardened runtime:
#        worker helper -> Core ML model -> outer .app  (inner binaries first).
#   4. Notarize with `xcrun notarytool submit --wait`, then staple the ticket.
#   5. Package the .app into dist/Teststrip-<version>.zip (or .dmg).
#   6. Verify: codesign --verify --deep --strict, spctl (Gatekeeper),
#      and xcrun stapler validate.
#
# Credentials (never hardcoded):
#   TESTSTRIP_SIGNING_IDENTITY  Developer ID Application identity string or hash,
#                               matching a cert in your login keychain. May also
#                               be passed as the first positional argument.
#   TESTSTRIP_NOTARY_PROFILE    Name of a notarytool keychain profile created
#                               with `xcrun notarytool store-credentials`.
#
# When credentials are absent the script prints exactly what to provide and how
# (see print_credential_guidance). Pass --dry-run to prove steps 1-2 and the
# verify wiring with an ad-hoc signature, no real certs required.
#
# Options:
#   --dry-run          Build + assemble + ad-hoc sign + codesign verify only.
#                      Skips Developer ID signing, notarization, and Gatekeeper
#                      assessment (which cannot pass for an ad-hoc signature).
#   --dmg              Package as a .dmg instead of a .zip.
#   --identity <id>    Signing identity (overrides TESTSTRIP_SIGNING_IDENTITY).
#   --profile <name>   Notary keychain profile (overrides TESTSTRIP_NOTARY_PROFILE).
#   -h, --help         Show this help.
#
# Exit codes: 0 success, 2 usage error, 3 missing credentials,
#             4 signing identity not found in keychain.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/app_bundle.sh
source "$ROOT_DIR/script/lib/app_bundle.sh"

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$TESTSTRIP_APP_NAME.app"
APP_ENTITLEMENTS="$ROOT_DIR/config/macos/Teststrip.entitlements"
WORKER_ENTITLEMENTS="$ROOT_DIR/config/macos/TeststripWorker.entitlements"
WORKER_BINARY="$APP_BUNDLE/Contents/Helpers/$TESTSTRIP_WORKER_PRODUCT_NAME"
FACE_MODEL_BUNDLED="$APP_BUNDLE/Contents/Resources/arcface-w600k-r50.mlpackage"

SIGNING_IDENTITY="${TESTSTRIP_SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${TESTSTRIP_NOTARY_PROFILE:-}"
DRY_RUN=0
ARTIFACT_FORMAT="zip"

usage() {
  echo "usage: $0 [--dry-run] [--dmg] [--identity <id>] [--profile <name>] [<signing-identity>]" >&2
}

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit "${2:-1}"; }

print_credential_guidance() {
  cat >&2 <<'GUIDANCE'
Release packaging needs Developer ID signing + notarization credentials.

You must provide, one time:

  1. A "Developer ID Application" certificate in your login keychain.
     Verify it is present with:
         security find-identity -v -p codesigning
     It appears as: "Developer ID Application: Your Name (TEAMID)".
     If absent, create/download it from the Apple Developer portal
     (Certificates > Developer ID Application) and import into the login
     keychain. Then export its identity string to:
         export TESTSTRIP_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"

  2. A notarytool keychain profile holding your notarization credentials —
     either an App Store Connect API key (recommended) or an Apple ID plus an
     app-specific password. Create it once with:
         xcrun notarytool store-credentials "TeststripNotary" \
             --apple-id "you@example.com" --team-id "TEAMID" \
             --password "app-specific-password"
       (or, with an API key:)
         xcrun notarytool store-credentials "TeststripNotary" \
             --key "/path/AuthKey_XXXX.p8" --key-id "KEYID" --issuer "ISSUER-UUID"
     Then point the pipeline at that profile:
         export TESTSTRIP_NOTARY_PROFILE="TeststripNotary"

Then re-run: script/package_release.sh

To prove the build + bundle assembly and verify wiring without real certs,
run an ad-hoc dry run:
         script/package_release.sh --dry-run
GUIDANCE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --dmg) ARTIFACT_FORMAT="dmg"; shift ;;
    --zip) ARTIFACT_FORMAT="zip"; shift ;;
    --identity) SIGNING_IDENTITY="${2:-}"; shift 2 ;;
    --profile) NOTARY_PROFILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; exit 2 ;;
    *) SIGNING_IDENTITY="$1"; shift ;;
  esac
done

# --- Step 1 + 2: build and assemble (shared with build_and_run.sh) -----------
build_and_assemble() {
  log "Release build of $TESTSTRIP_PRODUCT_NAME + $TESTSTRIP_WORKER_PRODUCT_NAME"
  teststrip_build_products "$ROOT_DIR" -c release
  local build_dir
  build_dir="$(teststrip_build_bin_path "$ROOT_DIR" -c release)"
  log "Assembling $APP_BUNDLE"
  teststrip_assemble_bundle "$ROOT_DIR" "$build_dir" "$APP_BUNDLE"
}

# --- Step 3: sign inside-out --------------------------------------------------
# Inner binaries/helpers and the Core ML model are signed before the outer .app
# so the outer seal covers already-signed contents.
sign_developer_id() {
  local identity="$1"
  local common=(codesign --force --timestamp --options runtime --sign "$identity")

  log "Signing worker helper"
  "${common[@]}" --entitlements "$WORKER_ENTITLEMENTS" "$WORKER_BINARY"

  if [[ -d "$FACE_MODEL_BUNDLED" ]]; then
    log "Signing bundled Core ML model"
    "${common[@]}" "$FACE_MODEL_BUNDLED"
  fi

  log "Signing outer app bundle"
  "${common[@]}" --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE"
}

sign_ad_hoc() {
  log "Ad-hoc signing worker helper (dry run)"
  codesign --force --sign - --entitlements "$WORKER_ENTITLEMENTS" "$WORKER_BINARY"
  if [[ -d "$FACE_MODEL_BUNDLED" ]]; then
    log "Ad-hoc signing bundled Core ML model (dry run)"
    codesign --force --sign - "$FACE_MODEL_BUNDLED"
  fi
  log "Ad-hoc signing outer app bundle (dry run)"
  codesign --force --sign - --entitlements "$APP_ENTITLEMENTS" "$APP_BUNDLE"
}

# --- Step 5: package ----------------------------------------------------------
package_artifact() {
  local version="$TESTSTRIP_SHORT_VERSION"
  ARTIFACT_PATH="$DIST_DIR/$TESTSTRIP_APP_NAME-$version.$ARTIFACT_FORMAT"
  rm -f "$ARTIFACT_PATH"
  if [[ "$ARTIFACT_FORMAT" == "dmg" ]]; then
    log "Packaging .dmg -> $ARTIFACT_PATH"
    hdiutil create -volname "$TESTSTRIP_APP_NAME" -srcfolder "$APP_BUNDLE" \
      -ov -format UDZO "$ARTIFACT_PATH" >/dev/null
  else
    log "Packaging .zip -> $ARTIFACT_PATH"
    # ditto -c -k --keepParent produces the notarization-friendly zip layout.
    /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ARTIFACT_PATH"
  fi
}

# --- Step 4: notarize + staple ------------------------------------------------
notarize_and_staple() {
  local profile="$1"
  log "Submitting $ARTIFACT_PATH to notarytool (this waits for Apple)"
  xcrun notarytool submit "$ARTIFACT_PATH" --keychain-profile "$profile" --wait
  log "Stapling ticket to $APP_BUNDLE"
  xcrun stapler staple "$APP_BUNDLE"
  # Re-package so the distributed artifact carries the stapled ticket.
  package_artifact
}

# --- Step 6: verify -----------------------------------------------------------
verify_signature() {
  log "Verifying signature: codesign --verify --deep --strict"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

verify_distribution() {
  log "Gatekeeper assessment: spctl -a -vvv"
  spctl -a -vvv -t execute "$APP_BUNDLE"
  log "Validating stapled ticket: stapler validate"
  xcrun stapler validate "$APP_BUNDLE"
}

# --- Credential resolution ----------------------------------------------------
require_signing_identity_present() {
  local identity="$1"
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$identity"; then
    die "signing identity not found in keychain: $identity (run: security find-identity -v -p codesigning)" 4
  fi
}

main() {
  mkdir -p "$DIST_DIR"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY RUN: ad-hoc signature, no notarization or Gatekeeper assessment"
    build_and_assemble
    sign_ad_hoc
    verify_signature
    package_artifact
    log "Dry run complete. Assembled + ad-hoc-signed + verified: $APP_BUNDLE"
    log "Artifact: $ARTIFACT_PATH (NOT distributable — ad-hoc signed, unnotarized)"
    return 0
  fi

  if [[ -z "$SIGNING_IDENTITY" || -z "$NOTARY_PROFILE" ]]; then
    print_credential_guidance
    die "missing signing identity and/or notary profile; see guidance above" 3
  fi

  require_signing_identity_present "$SIGNING_IDENTITY"

  build_and_assemble
  sign_developer_id "$SIGNING_IDENTITY"
  verify_signature
  package_artifact
  notarize_and_staple "$NOTARY_PROFILE"
  verify_signature
  verify_distribution
  log "Release complete: $ARTIFACT_PATH"
}

main
