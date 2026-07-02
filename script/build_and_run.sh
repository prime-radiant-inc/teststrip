#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="TeststripApp"
WORKER_PRODUCT_NAME="TeststripWorker"
APP_NAME="Teststrip"
BUNDLE_ID="com.teststrip.app"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_BINARY="$APP_MACOS/$APP_NAME"
WORKER_BINARY="$APP_HELPERS/$WORKER_PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

usage() {
  echo "usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2
}

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x "$PRODUCT_NAME" >/dev/null 2>&1 || true
  pkill -x "$WORKER_PRODUCT_NAME" >/dev/null 2>&1 || true
}

build_app_bundle() {
  cd "$ROOT_DIR"
  swift build --product "$PRODUCT_NAME"
  swift build --product "$WORKER_PRODUCT_NAME"

  local build_dir
  build_dir="$(swift build --show-bin-path)"
  local build_binary="$build_dir/$PRODUCT_NAME"
  local build_worker_binary="$build_dir/$WORKER_PRODUCT_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_HELPERS"
  cp "$build_binary" "$APP_BINARY"
  cp "$build_worker_binary" "$WORKER_BINARY"
  chmod +x "$APP_BINARY"
  chmod +x "$WORKER_BINARY"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

  codesign --force --sign - "$WORKER_BINARY" >/dev/null
  codesign --force --sign - "$APP_BUNDLE" >/dev/null
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

verify_app() {
  if [[ ! -x "$WORKER_BINARY" ]]; then
    echo "$WORKER_PRODUCT_NAME helper is missing from $APP_HELPERS" >&2
    return 1
  fi

  open_app
  for _ in {1..40}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      echo "$APP_NAME is running from $APP_BUNDLE"
      return 0
    fi
    sleep 0.25
  done
  echo "$APP_NAME did not start" >&2
  return 1
}

case "$MODE" in
  run|--verify|verify|--debug|debug|--logs|logs|--telemetry|telemetry)
    ;;
  --help|help|-h)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

stop_running_app
build_app_bundle

case "$MODE" in
  run)
    open_app
    ;;
  --verify|verify)
    verify_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
esac
