#!/bin/sh
# Build Usage Bar.app. Set INSTALL=0 to leave the app in build/ only.
set -eu
cd "$(dirname "$0")"

APP="Usage Bar.app"
EXECUTABLE="UsageBar"
BUILD="${BUILD_DIR:-build}"

rm -rf "$BUILD"
mkdir -p "$BUILD/$APP/Contents/MacOS"
cp Info.plist "$BUILD/$APP/Contents/Info.plist"
swiftc -O Sources/*.swift -o "$BUILD/$APP/Contents/MacOS/$EXECUTABLE"
xattr -cr "$BUILD/$APP"
codesign --force --sign - "$BUILD/$APP"

if [ "${INSTALL:-1}" = "1" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/$APP"
  rm -rf "$HOME/Applications/Claude Usage.app"
  cp -R "$BUILD/$APP" "$HOME/Applications/$APP"
  echo "Installed: ~/Applications/$APP"
else
  echo "Built: $BUILD/$APP"
fi
