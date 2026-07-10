#!/usr/bin/env bash
# Shared Teststrip .app assembly logic.
#
# Sourced by both script/build_and_run.sh (dev: debug build, ad-hoc signed)
# and script/package_release.sh (release: Developer ID signed + notarized).
# This file owns everything the two flows have in common: building the
# products, laying out the .app bundle (binaries, icon, bundled Core ML face
# model), and writing Info.plist. It deliberately does NOT sign the bundle:
# dev uses ad-hoc `codesign -s -`, release uses a Developer ID identity with a
# hardened runtime, so signing stays with each caller.
#
# Bundle identity constants live here so the two flows can never drift.
# CFBundleShortVersionString / CFBundleVersion can be overridden with the
# TESTSTRIP_SHORT_VERSION / TESTSTRIP_BUNDLE_VERSION env vars.

TESTSTRIP_PRODUCT_NAME="TeststripApp"
TESTSTRIP_WORKER_PRODUCT_NAME="TeststripWorker"
TESTSTRIP_APP_NAME="Teststrip"
TESTSTRIP_BUNDLE_ID="com.teststrip.app"
TESTSTRIP_MIN_SYSTEM_VERSION="14.0"
TESTSTRIP_SHORT_VERSION="${TESTSTRIP_SHORT_VERSION:-0.1.0}"
TESTSTRIP_BUNDLE_VERSION="${TESTSTRIP_BUNDLE_VERSION:-1}"

# Relative path of the bundled ArcFace Core ML model within the repo. Absent in
# a fresh checkout; script/download_face_model.sh fetches it. Assembly skips it
# (with a warning) when missing so the bundle can still be built and signed.
TESTSTRIP_FACE_MODEL_REL="sample-data/models/auraface-v1.mlpackage"

# Build the app + worker products.
# Usage: teststrip_build_products <root_dir> [extra swift build args...]
teststrip_build_products() {
  local root_dir="$1"; shift
  ( cd "$root_dir" && swift build "$@" --product "$TESTSTRIP_PRODUCT_NAME" )
  ( cd "$root_dir" && swift build "$@" --product "$TESTSTRIP_WORKER_PRODUCT_NAME" )
}

# Echo the SwiftPM bin path for the given build configuration.
# Usage: teststrip_build_bin_path <root_dir> [extra swift build args...]
teststrip_build_bin_path() {
  local root_dir="$1"; shift
  ( cd "$root_dir" && swift build "$@" --show-bin-path )
}

# Lay out the .app bundle contents from an already-built bin path. Wipes and
# recreates <app_bundle>. Does not sign.
# Usage: teststrip_assemble_bundle <root_dir> <build_dir> <app_bundle>
teststrip_assemble_bundle() {
  local root_dir="$1" build_dir="$2" app_bundle="$3"

  local app_contents="$app_bundle/Contents"
  local app_macos="$app_contents/MacOS"
  local app_helpers="$app_contents/Helpers"
  local app_resources="$app_contents/Resources"
  local app_frameworks="$app_contents/Frameworks"
  local app_binary="$app_macos/$TESTSTRIP_APP_NAME"
  local worker_binary="$app_helpers/$TESTSTRIP_WORKER_PRODUCT_NAME"
  local info_plist="$app_contents/Info.plist"
  local app_icon_icns="$root_dir/config/macos/AppIcon.icns"
  local face_model="$root_dir/$TESTSTRIP_FACE_MODEL_REL"
  local sparkle_framework="$build_dir/Sparkle.framework"

  rm -rf "$app_bundle"
  mkdir -p "$app_macos" "$app_helpers" "$app_resources" "$app_frameworks"
  cp "$build_dir/$TESTSTRIP_PRODUCT_NAME" "$app_binary"
  cp "$build_dir/$TESTSTRIP_WORKER_PRODUCT_NAME" "$worker_binary"
  chmod +x "$app_binary" "$worker_binary"

  # SwiftPM's dev build resolves @rpath/Sparkle.framework via the `@loader_path`
  # rpath (the framework sits next to the executable in .build/); once
  # relocated into Contents/MacOS the framework instead lives in
  # ../Frameworks, so add that rpath for the bundled binary to resolve it.
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$app_binary"

  if [[ -d "$sparkle_framework" ]]; then
    # Sparkle.framework bundles its own Autoupdate helper and (for sandboxed
    # hosts like Teststrip) the Installer/Downloader XPC services under
    # Versions/B/XPCServices; copying the whole framework carries those along.
    /usr/bin/ditto "$sparkle_framework" "$app_frameworks/Sparkle.framework"
  else
    echo "error: Sparkle.framework not found at $sparkle_framework (swift build did not resolve the Sparkle SPM dependency)" >&2
    return 1
  fi

  if [[ -f "$app_icon_icns" ]]; then
    cp "$app_icon_icns" "$app_resources/AppIcon.icns"
  else
    echo "warning: $app_icon_icns is missing; building without an app icon (run script/generate_app_icon.sh)" >&2
  fi

  if [[ -d "$face_model" ]]; then
    /usr/bin/ditto "$face_model" "$app_resources/auraface-v1.mlpackage"
  else
    echo "warning: face model $face_model is missing; bundle will ship without on-device face embedding (run script/download_face_model.sh)" >&2
  fi

  teststrip_write_info_plist "$app_contents"
}

# Sign every nested Mach-O and bundle under Contents/Frameworks, deepest first
# (Sparkle.framework's own binary, its bundled Autoupdate helper, Updater.app,
# and the Installer/Downloader XPC services used by sandboxed hosts). Shared
# by build_and_run.sh (ad-hoc dev signing) and package_release.sh (Developer
# ID signing) so both keep the app launchable with an embedded Sparkle.
# macOS ships bash 3.2 (no nameref support), so the codesign invocation is
# passed as trailing positional args rather than by array-variable name.
# Usage: teststrip_sign_frameworks <app_bundle> <codesign-arg>...
teststrip_sign_frameworks() {
  local app_bundle="$1"; shift
  local frameworks_dir="$app_bundle/Contents/Frameworks"
  [[ -d "$frameworks_dir" ]] || return 0

  while IFS= read -r executable; do
    "$@" "$executable"
  done < <(find "$frameworks_dir" -type f -perm -111 -print \
    | awk '{ print length($0) " " $0 }' | sort -rn | cut -d' ' -f2-)

  while IFS= read -r component; do
    "$@" "$component"
  done < <(find "$frameworks_dir" \
    \( -name "*.framework" -o -name "*.dylib" -o -name "*.xpc" -o -name "*.bundle" -o -name "*.app" \) -print \
    | awk '{ print length($0) " " $0 }' | sort -rn | cut -d' ' -f2-)
}

# Usage: teststrip_write_info_plist <app_contents_dir>
teststrip_write_info_plist() {
  local app_contents="$1"
  local info_plist="$app_contents/Info.plist"
  cat >"$info_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$TESTSTRIP_APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$TESTSTRIP_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$TESTSTRIP_APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$TESTSTRIP_SHORT_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$TESTSTRIP_BUNDLE_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$TESTSTRIP_MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>https://github.com/prime-radiant-inc/teststrip/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>ZY/ZPlRrnPohsWVic4GcjZ8tJg8qScm9MRHj3EWO4mg=</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
</dict>
</plist>
PLIST
}
