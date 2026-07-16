#!/bin/sh
# Build a universal Usage Bar.app. Set INSTALL=0 to leave it in build/ only.
set -eu
cd "$(dirname "$0")"

APP="Usage Bar.app"
EXECUTABLE="UsageBar"
BUILD="${BUILD_DIR:-build}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

rm -rf "$BUILD"
mkdir -p "$BUILD/$APP/Contents/MacOS"
mkdir -p "$BUILD/$APP/Contents/Resources"
cp Info.plist "$BUILD/$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$BUILD/$APP/Contents/Resources/AppIcon.icns"
cp bin/claude-account "$BUILD/$APP/Contents/Resources/claude-account"
chmod +x "$BUILD/$APP/Contents/Resources/claude-account"

for arch in arm64 x86_64; do
  xcrun swiftc -O -target "$arch-apple-macos13.0" Sources/*.swift \
    -o "$BUILD/$EXECUTABLE-$arch"
done
lipo -create "$BUILD/$EXECUTABLE-arm64" "$BUILD/$EXECUTABLE-x86_64" \
  -output "$BUILD/$APP/Contents/MacOS/$EXECUTABLE"
rm "$BUILD/$EXECUTABLE-arm64" "$BUILD/$EXECUTABLE-x86_64"
xattr -cr "$BUILD/$APP"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --sign - "$BUILD/$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$BUILD/$APP"
fi

if [ "${INSTALL:-1}" = "1" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$APP"
  rm -rf "$HOME/Applications/Claude Usage.app"
  cp -R "$BUILD/$APP" "$HOME/Applications/$APP"
  echo "Installed: ~/Applications/$APP"
else
  echo "Built: $BUILD/$APP"
fi
