#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

SOURCE="assets/AppIcon.svg"
ICONSET="${TMPDIR:-/tmp}/UsageBar.iconset"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/usage-bar-icon-clang-cache"
export SWIFT_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/usage-bar-icon-swift-cache"
rm -rf "$ICONSET"
rm -f assets/AppIcon.icns
mkdir -p "$ICONSET"

magick -background none -depth 8 "$SOURCE" "PNG32:$ICONSET/icon_512x512@2x.png"
for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png"; do
  set -- $spec
  sips -z "$1" "$1" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/$2" >/dev/null
done
xcrun swift scripts/make-icns.swift assets/AppIcon.icns \
  icp4 "$ICONSET/icon_16x16.png" \
  icp5 "$ICONSET/icon_32x32.png" \
  icp6 "$ICONSET/icon_32x32@2x.png" \
  ic07 "$ICONSET/icon_128x128.png" \
  ic08 "$ICONSET/icon_256x256.png" \
  ic09 "$ICONSET/icon_512x512.png" \
  ic10 "$ICONSET/icon_512x512@2x.png"
rm -rf "$ICONSET"
echo "Generated assets/AppIcon.icns"
