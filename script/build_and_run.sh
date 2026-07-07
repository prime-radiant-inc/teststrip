#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="TeststripApp"
WORKER_PRODUCT_NAME="TeststripWorker"
BENCH_PRODUCT_NAME="TeststripBench"
APP_NAME="Teststrip"
BUNDLE_ID="com.teststrip.app"
MIN_SYSTEM_VERSION="14.0"
APPLICATION_SUPPORT_ENV_KEY="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY"
REQUIRED_SECURITY_SCOPE_ENV_KEY="TESTSTRIP_REQUIRE_SECURITY_SCOPED_IMPORTS"
CARD_IMPORT_ROUTE_ENV_KEY="TESTSTRIP_CARD_IMPORT_ROUTE"
REJECT_DESTINATION_ENV_KEY="TESTSTRIP_REJECT_DESTINATION_DIR"
EXPORT_DESTINATION_ENV_KEY="TESTSTRIP_EXPORT_DESTINATION_DIR"
ISOLATED=0
ISOLATED_APPLICATION_SUPPORT=""
SANDBOXED=0
SMOKE=0
SMOKE_ASSET_COUNT="${TESTSTRIP_SMOKE_ASSET_COUNT:-24}"
SAMPLE_PHOTOS=0
SAMPLE_PHOTOS_DIR="${TESTSTRIP_SAMPLE_PHOTOS_DIR:-}"
SAMPLE_PHOTOS_MANIFEST="${TESTSTRIP_SAMPLE_PHOTOS_MANIFEST:-}"
REAL_CORPUS=0
REAL_CORPUS_DIR="${TESTSTRIP_REAL_CORPUS_DIR:-}"
BACKGROUND_OPEN=0

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_HELPERS="$APP_CONTENTS/Helpers"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
WORKER_BINARY="$APP_HELPERS/$WORKER_PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_ICNS="$ROOT_DIR/config/macos/AppIcon.icns"
APP_ENTITLEMENTS="$ROOT_DIR/config/macos/Teststrip.entitlements"
WORKER_ENTITLEMENTS="$ROOT_DIR/config/macos/TeststripWorker.entitlements"

usage() {
  echo "usage: $0 [run|--build|--build-sandboxed|--sandboxed|--verify|--verify-sandboxed|--isolated|--verify-isolated|--smoke|--verify-smoke|--sample-photos|--verify-sample-photos|--faces|--verify-faces|--real-corpus|--verify-real-corpus|--debug|--logs|--telemetry]" >&2
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
  mkdir -p "$APP_MACOS" "$APP_HELPERS" "$APP_RESOURCES"
  cp "$build_binary" "$APP_BINARY"
  cp "$build_worker_binary" "$WORKER_BINARY"
  chmod +x "$APP_BINARY"
  chmod +x "$WORKER_BINARY"

  if [[ -f "$APP_ICON_ICNS" ]]; then
    cp "$APP_ICON_ICNS" "$APP_RESOURCES/AppIcon.icns"
  else
    echo "warning: $APP_ICON_ICNS is missing; building without an app icon (run script/generate_app_icon.sh)" >&2
  fi

  FACE_MODEL="$ROOT_DIR/sample-data/models/arcface-w600k-r50.mlpackage"
  if [[ -d "$FACE_MODEL" ]]; then
    /usr/bin/ditto "$FACE_MODEL" "$APP_RESOURCES/arcface-w600k-r50.mlpackage"
  fi

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
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

  local worker_codesign=(codesign --force --sign -)
  local app_codesign=(codesign --force --sign -)
  if [[ "$SANDBOXED" == "1" ]]; then
    worker_codesign+=(--entitlements "$WORKER_ENTITLEMENTS")
    app_codesign+=(--entitlements "$APP_ENTITLEMENTS")
  fi
  "${worker_codesign[@]}" "$WORKER_BINARY" >/dev/null
  "${app_codesign[@]}" "$APP_BUNDLE" >/dev/null
}

open_app() {
  local open_args=(-n "$APP_BUNDLE")
  if [[ "$BACKGROUND_OPEN" == "1" ]]; then
    open_args=(-g "${open_args[@]}")
  fi
  if [[ "$SANDBOXED" == "1" ]]; then
    open_args=(--env "$REQUIRED_SECURITY_SCOPE_ENV_KEY=1" "${open_args[@]}")
  fi
  if [[ "$ISOLATED" == "1" ]]; then
    prepare_isolated_catalog
    if [[ "$SMOKE" == "1" ]]; then
      seed_smoke_catalog
    fi
    if [[ "$SAMPLE_PHOTOS" == "1" ]]; then
      seed_sample_catalog
    fi
    if [[ "$REAL_CORPUS" == "1" ]]; then
      seed_real_corpus_catalog
    fi
    open_args=(--env "$APPLICATION_SUPPORT_ENV_KEY=$ISOLATED_APPLICATION_SUPPORT" "${open_args[@]}")
  fi
  if [[ -n "${TESTSTRIP_CARD_IMPORT_ROUTE:-}" ]]; then
    open_args=(--env "$CARD_IMPORT_ROUTE_ENV_KEY=$TESTSTRIP_CARD_IMPORT_ROUTE" "${open_args[@]}")
  fi
  if [[ -n "${TESTSTRIP_REJECT_DESTINATION_DIR:-}" ]]; then
    open_args=(--env "$REJECT_DESTINATION_ENV_KEY=$TESTSTRIP_REJECT_DESTINATION_DIR" "${open_args[@]}")
  fi
  if [[ -n "${TESTSTRIP_EXPORT_DESTINATION_DIR:-}" ]]; then
    open_args=(--env "$EXPORT_DESTINATION_ENV_KEY=$TESTSTRIP_EXPORT_DESTINATION_DIR" "${open_args[@]}")
  fi
  /usr/bin/open "${open_args[@]}"
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
      if [[ "$ISOLATED" == "1" ]]; then
        echo "$APP_NAME is using isolated application support at $ISOLATED_APPLICATION_SUPPORT"
      fi
      if [[ "$SANDBOXED" == "1" ]]; then
        echo "$APP_NAME is signed with sandbox entitlements"
      fi
      return 0
    fi
    sleep 0.25
  done
  echo "$APP_NAME did not start" >&2
  return 1
}

prepare_isolated_catalog() {
  if [[ -z "$ISOLATED_APPLICATION_SUPPORT" ]]; then
    ISOLATED_APPLICATION_SUPPORT="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-app-support.XXXXXX")"
  fi
}

seed_smoke_catalog() {
  cd "$ROOT_DIR"
  swift run "$BENCH_PRODUCT_NAME" seed-app-catalog "$ISOLATED_APPLICATION_SUPPORT" "$SMOKE_ASSET_COUNT"
}

seed_sample_catalog() {
  cd "$ROOT_DIR"
  if [[ -z "$SAMPLE_PHOTOS_DIR" ]]; then
    SAMPLE_PHOTOS_DIR="$ROOT_DIR/sample-data/photos/wordpress-photo-directory"
  fi
  if [[ -z "$SAMPLE_PHOTOS_MANIFEST" ]]; then
    SAMPLE_PHOTOS_MANIFEST="$ROOT_DIR/sample-data/wordpress-photo-directory.tsv"
  fi
  if [[ ! -d "$SAMPLE_PHOTOS_DIR" ]] || [[ -z "$(find "$SAMPLE_PHOTOS_DIR" -maxdepth 1 -type f -print -quit)" ]]; then
    "$ROOT_DIR/script/download_sample_photos.sh" --manifest "$SAMPLE_PHOTOS_MANIFEST" --destination "$SAMPLE_PHOTOS_DIR"
  fi
  swift run "$BENCH_PRODUCT_NAME" seed-sample-catalog "$ISOLATED_APPLICATION_SUPPORT" "$SAMPLE_PHOTOS_DIR"
}

seed_real_corpus_catalog() {
  cd "$ROOT_DIR"
  if [[ -z "$REAL_CORPUS_DIR" ]]; then
    REAL_CORPUS_DIR="$ROOT_DIR/sample-data/photos/jesse-pictures"
  fi
  if [[ ! -d "$REAL_CORPUS_DIR" ]]; then
    echo "real corpus directory does not exist: $REAL_CORPUS_DIR" >&2
    echo "set TESTSTRIP_REAL_CORPUS_DIR to an ignored local photo corpus" >&2
    return 1
  fi
  swift run "$BENCH_PRODUCT_NAME" seed-real-corpus-catalog "$ISOLATED_APPLICATION_SUPPORT" "$REAL_CORPUS_DIR"
}

case "$MODE" in
  run|--build|build|--verify|verify|--debug|debug|--logs|logs|--telemetry|telemetry)
    ;;
  --build-sandboxed|build-sandboxed)
    MODE="--build"
    SANDBOXED=1
    ;;
  --sandboxed|sandboxed)
    MODE="run"
    SANDBOXED=1
    ;;
  --verify-sandboxed|verify-sandboxed)
    MODE="--verify"
    SANDBOXED=1
    ;;
  --isolated|isolated)
    MODE="run"
    ISOLATED=1
    ;;
  --verify-isolated|verify-isolated)
    MODE="--verify"
    ISOLATED=1
    ;;
  --smoke|smoke)
    MODE="run"
    ISOLATED=1
    SMOKE=1
    ;;
  --verify-smoke|verify-smoke)
    MODE="--verify"
    ISOLATED=1
    SMOKE=1
    ;;
  --sample-photos|sample-photos)
    MODE="run"
    ISOLATED=1
    SAMPLE_PHOTOS=1
    ;;
  --verify-sample-photos|verify-sample-photos)
    MODE="--verify"
    ISOLATED=1
    SAMPLE_PHOTOS=1
    ;;
  --faces|faces)
    MODE="run"
    ISOLATED=1
    SAMPLE_PHOTOS=1
    SAMPLE_PHOTOS_MANIFEST="$ROOT_DIR/sample-data/faces.tsv"
    SAMPLE_PHOTOS_DIR="$ROOT_DIR/sample-data/photos/faces"
    ;;
  --verify-faces|verify-faces)
    MODE="--verify"
    ISOLATED=1
    SAMPLE_PHOTOS=1
    SAMPLE_PHOTOS_MANIFEST="$ROOT_DIR/sample-data/faces.tsv"
    SAMPLE_PHOTOS_DIR="$ROOT_DIR/sample-data/photos/faces"
    ;;
  --real-corpus|real-corpus)
    MODE="run"
    ISOLATED=1
    REAL_CORPUS=1
    BACKGROUND_OPEN=1
    ;;
  --verify-real-corpus|verify-real-corpus)
    MODE="--verify"
    ISOLATED=1
    REAL_CORPUS=1
    BACKGROUND_OPEN=1
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

if [[ "$MODE" != "--build" && "$MODE" != "build" ]]; then
  stop_running_app
fi
build_app_bundle

case "$MODE" in
  --build|build)
    echo "Built $APP_BUNDLE"
    ;;
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
