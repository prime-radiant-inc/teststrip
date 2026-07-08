#!/usr/bin/env bash
set -euo pipefail

# Covers package_release.sh's argument and credential-absent branches without
# requiring real Developer ID certs or notarization. Heavy branches (the actual
# release build/sign/notarize) are out of scope for this unit test; those need
# real credentials and a full swift build and are exercised via --dry-run and a
# real run by hand. We stub `security` so the identity-lookup branch is
# deterministic (mirrors test_activate_app.sh's osascript stub).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STUB_DIR="$(mktemp -d /tmp/teststrip-package-release-test.XXXXXX)"
trap 'rm -rf "$STUB_DIR"' EXIT

# Stub `security`: report exactly the identity named in TEST_STUB_IDENTITY so
# the keychain-presence check is deterministic and cert-free.
cat > "$STUB_DIR/security" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *"find-identity"* ]]; then
  printf '  1) DEADBEEF "%s"\n' "${TEST_STUB_IDENTITY:-}"
  exit 0
fi
exit 1
STUB
chmod +x "$STUB_DIR/security"

run_package() {
  # Runs package_release.sh with the security stub on PATH. Echoes nothing; the
  # caller captures output/status.
  PATH="$STUB_DIR:$PATH" "$SCRIPT_DIR/package_release.sh" "$@"
}

assert_equal() {
  local expected="$1" actual="$2" message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  case "$haystack" in
    *"$needle"*) ;;
    *) echo "$message: '$needle' not found in output" >&2; exit 1 ;;
  esac
}

test_help_exits_zero() {
  local status=0
  run_package --help >/dev/null 2>&1 || status=$?
  assert_equal "0" "$status" "--help exit status"
}

test_unknown_flag_is_usage_error() {
  local status=0
  run_package --bogus >/dev/null 2>&1 || status=$?
  assert_equal "2" "$status" "unknown flag exit status"
}

test_missing_credentials_prints_guidance() {
  local status=0 output
  output="$(
    env -u TESTSTRIP_SIGNING_IDENTITY -u TESTSTRIP_NOTARY_PROFILE \
      "$SCRIPT_DIR/package_release.sh" 2>&1
  )" || status=$?
  assert_equal "3" "$status" "missing-credentials exit status"
  assert_contains "$output" "Developer ID Application" "guidance names the cert"
  assert_contains "$output" "store-credentials" "guidance names notarytool store-credentials"
}

test_identity_present_but_profile_missing_prints_guidance() {
  local status=0 output
  output="$(
    env -u TESTSTRIP_NOTARY_PROFILE TESTSTRIP_SIGNING_IDENTITY="Developer ID Application: Someone (TEAMID)" \
      "$SCRIPT_DIR/package_release.sh" 2>&1
  )" || status=$?
  assert_equal "3" "$status" "profile-missing exit status"
  assert_contains "$output" "store-credentials" "guidance names notarytool store-credentials"
}

test_identity_not_in_keychain_exits_4() {
  # Identity + profile both supplied, but the stubbed keychain reports a
  # different identity, so the presence check must fail before any build.
  local status=0 output
  output="$(
    TEST_STUB_IDENTITY="Developer ID Application: Real Cert (TEAMID)" \
    run_package --identity "Developer ID Application: Missing Cert (TEAMID)" --profile "SomeProfile" 2>&1
  )" || status=$?
  assert_equal "4" "$status" "identity-not-found exit status"
  assert_contains "$output" "not found in keychain" "error explains the missing identity"
}

test_help_exits_zero
test_unknown_flag_is_usage_error
test_missing_credentials_prints_guidance
test_identity_present_but_profile_missing_prints_guidance
test_identity_not_in_keychain_exits_4

echo "test_package_release.sh passed"
