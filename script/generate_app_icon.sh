#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG_SOURCE="$ROOT_DIR/config/macos/AppIcon.svg"
RENDER_SCRIPT="$ROOT_DIR/script/render_app_icon.swift"
OUTPUT_ICNS="$ROOT_DIR/config/macos/AppIcon.icns"
PREVIEW_PATH=""
KEEP_ICONSET=0

usage() {
  cat <<EOF
Usage: $0 [--output PATH] [--preview PATH] [--keep-iconset] [--help]

Renders config/macos/AppIcon.icns from the Teststrip icon design.

The design's canonical vector source is config/macos/AppIcon.svg, but this
machine's stock toolchain has no SVG rasterizer (no rsvg-convert, no
Inkscape, no pyobjc for Python's CoreGraphics bindings). Instead
script/render_app_icon.swift redraws the same design with CoreGraphics, and
this script calls it once per size an .iconset needs -- 16 through 1024px --
then packs the result with iconutil. Rendering each size natively (rather
than downsampling a single 1024px master with sips) keeps the small sizes
legible; see render_app_icon.swift for why.

  --output PATH    write the .icns here instead of config/macos/AppIcon.icns
  --preview PATH   also render a plain 512x512 PNG preview to PATH
  --keep-iconset   leave the intermediate .iconset directory in place and
                   print its path, instead of deleting it
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_ICNS="$2"
      shift 2
      ;;
    --preview)
      PREVIEW_PATH="$2"
      shift 2
      ;;
    --keep-iconset)
      KEEP_ICONSET=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for tool in swift sips iconutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "generate_app_icon error=missing_tool tool=$tool" >&2
    exit 1
  fi
done

if [[ ! -f "$SVG_SOURCE" ]]; then
  echo "generate_app_icon error=missing_svg_source path=$SVG_SOURCE" >&2
  exit 1
fi

if [[ ! -f "$RENDER_SCRIPT" ]]; then
  echo "generate_app_icon error=missing_render_script path=$RENDER_SCRIPT" >&2
  exit 1
fi

ICONSET_DIR="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-app-icon.XXXXXX")/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

cleanup() {
  if [[ "$KEEP_ICONSET" == "1" ]]; then
    echo "generate_app_icon iconset_kept=$ICONSET_DIR"
  else
    rm -rf "$(dirname "$ICONSET_DIR")"
  fi
}
trap cleanup EXIT

# name -> actual pixel dimensions iconutil expects for that iconset entry.
ICONSET_ENTRIES=(
  "icon_16x16.png:16"
  "icon_16x16@2x.png:32"
  "icon_32x32.png:32"
  "icon_32x32@2x.png:64"
  "icon_128x128.png:128"
  "icon_128x128@2x.png:256"
  "icon_256x256.png:256"
  "icon_256x256@2x.png:512"
  "icon_512x512.png:512"
  "icon_512x512@2x.png:1024"
)

for entry in "${ICONSET_ENTRIES[@]}"; do
  name="${entry%%:*}"
  pixels="${entry##*:}"
  out_path="$ICONSET_DIR/$name"
  swift "$RENDER_SCRIPT" "$out_path" "$pixels" >/dev/null

  actual_width="$(sips -g pixelWidth "$out_path" | awk '/pixelWidth/{print $2}')"
  if [[ "$actual_width" != "$pixels" ]]; then
    echo "generate_app_icon error=size_mismatch file=$name expected=$pixels actual=$actual_width" >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$OUTPUT_ICNS")"
iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
echo "generate_app_icon wrote=$OUTPUT_ICNS"

if [[ -n "$PREVIEW_PATH" ]]; then
  mkdir -p "$(dirname "$PREVIEW_PATH")"
  swift "$RENDER_SCRIPT" "$PREVIEW_PATH" 512 >/dev/null
  echo "generate_app_icon wrote_preview=$PREVIEW_PATH"
fi
