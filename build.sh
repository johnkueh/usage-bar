#!/bin/sh
# Build a universal Usage Bar.app. Set INSTALL=0 to leave it in build/ only.
set -eu
cd "$(dirname "$0")"

APP="Usage Bar.app"
EXECUTABLE="UsageBar"
BUILD="${BUILD_DIR:-build}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/usage-bar-clang-cache}"
export SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/usage-bar-swift-cache}"

[ -d vendor/Sparkle.framework ] || ./fetch-sparkle.sh

rm -rf "$BUILD"
mkdir -p "$BUILD/$APP/Contents/MacOS"
mkdir -p "$BUILD/$APP/Contents/Resources"
mkdir -p "$BUILD/$APP/Contents/Frameworks"
cp Info.plist "$BUILD/$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$BUILD/$APP/Contents/Resources/AppIcon.icns"
cp bin/claude-account "$BUILD/$APP/Contents/Resources/claude-account"
cp -R vendor/Sparkle.framework "$BUILD/$APP/Contents/Frameworks/"
chmod +x "$BUILD/$APP/Contents/Resources/claude-account"

for arch in arm64 x86_64; do
  xcrun swiftc -O -target "$arch-apple-macos13.0" Sources/*.swift \
    -F vendor -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "$BUILD/$EXECUTABLE-$arch"
done
lipo -create "$BUILD/$EXECUTABLE-arm64" "$BUILD/$EXECUTABLE-x86_64" \
  -output "$BUILD/$APP/Contents/MacOS/$EXECUTABLE"
rm "$BUILD/$EXECUTABLE-arm64" "$BUILD/$EXECUTABLE-x86_64"
xattr -cr "$BUILD/$APP"

FRAMEWORK="$BUILD/$APP/Contents/Frameworks/Sparkle.framework"
FRAMEWORK_VERSION="$FRAMEWORK/Versions/B"
if [ "$SIGN_IDENTITY" = "-" ]; then
  sign() { codesign --force --sign - "$1"; }
else
  sign() { codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$1"; }
fi
for item in \
  "$FRAMEWORK_VERSION/XPCServices/Installer.xpc" \
  "$FRAMEWORK_VERSION/XPCServices/Downloader.xpc" \
  "$FRAMEWORK_VERSION/Autoupdate" \
  "$FRAMEWORK_VERSION/Updater.app"; do
  [ ! -e "$item" ] || sign "$item"
done
sign "$FRAMEWORK"
sign "$BUILD/$APP"

if [ "${INSTALL:-1}" = "1" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$APP"
  rm -rf "$HOME/Applications/Claude Usage.app"
  cp -R "$BUILD/$APP" "$HOME/Applications/$APP"
  echo "Installed: ~/Applications/$APP"
else
  echo "Built: $BUILD/$APP"
fi
