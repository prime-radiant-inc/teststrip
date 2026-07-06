#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/Teststrip.app"

assert_exists() {
  local path="$1"
  local message="$2"
  if [[ ! -e "$path" ]]; then
    echo "$message: expected '$path' to exist" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "$message: expected content to contain '$needle'" >&2
    exit 1
  fi
}

test_icon_sources_are_checked_in() {
  assert_exists "$ROOT_DIR/config/macos/AppIcon.svg" "icon vector source"
  assert_exists "$ROOT_DIR/config/macos/AppIcon.icns" "generated icon"
  assert_exists "$ROOT_DIR/script/render_app_icon.swift" "icon renderer"
  assert_exists "$ROOT_DIR/script/generate_app_icon.sh" "icon generator"

  local icns_type
  icns_type="$(file "$ROOT_DIR/config/macos/AppIcon.icns")"
  assert_contains "$icns_type" "Mac OS X icon" "generated icon file type"
}

test_built_bundle_includes_icon() {
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "skip: $APP_BUNDLE not built (run script/build_and_run.sh --build first)"
    return 0
  fi

  assert_exists "$APP_BUNDLE/Contents/Resources/AppIcon.icns" "bundled icon"

  local plist_contents
  plist_contents="$(cat "$APP_BUNDLE/Contents/Info.plist")"
  assert_contains "$plist_contents" "<key>CFBundleIconFile</key>" "Info.plist icon key"
  assert_contains "$plist_contents" "<string>AppIcon</string>" "Info.plist icon value"
}

test_icon_sources_are_checked_in
test_built_bundle_includes_icon

echo "app icon bundle tests passed"
