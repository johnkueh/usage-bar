#!/bin/bash
# Build, sign, notarize, and package a public Usage Bar release.
set -euo pipefail
cd "$(dirname "$0")"
[ -f release.env ] && source release.env

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1
APP="Usage Bar.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DMG_VERSIONED="Usage-Bar-$VERSION.dmg"
DMG_STABLE="Usage-Bar.dmg"
RELEASE_BUILD="${TMPDIR:-/tmp}/usage-bar-release-build"
APP_PATH="$RELEASE_BUILD/$APP"

if [ "$DRY_RUN" = 1 ]; then
  IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
  [ -n "$IDENTITY" ] || IDENTITY="-"
else
  : "${ASC_KEY_ID:?Set ASC_KEY_ID in release.env}"
  : "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID in release.env}"
  : "${ASC_KEY_FILEPATH:?Set ASC_KEY_FILEPATH in release.env}"
  IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
[ -n "$IDENTITY" ] || { echo "No matching code-signing identity found" >&2; exit 1; }

BUILD_DIR="$RELEASE_BUILD" INSTALL=0 SIGN_IDENTITY="$IDENTITY" ./build.sh
codesign --verify --deep --strict "$APP_PATH"
file "$APP_PATH/Contents/MacOS/UsageBar" | grep -q 'arm64'
file "$APP_PATH/Contents/MacOS/UsageBar" | grep -q 'x86_64'

rm -rf dist
mkdir -p dist
if [ "$DRY_RUN" = 0 ]; then
  ditto -c -k --keepParent "$APP_PATH" "dist/Usage-Bar-app-$VERSION.zip"
  xcrun notarytool submit "dist/Usage-Bar-app-$VERSION.zip" \
    --key "$ASC_KEY_FILEPATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
  xcrun stapler staple "$APP_PATH"
  rm "dist/Usage-Bar-app-$VERSION.zip"
fi

STAGE="$(mktemp -d)"
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Usage Bar" -srcfolder "$STAGE" -ov -format UDZO "dist/$DMG_VERSIONED" >/dev/null
rm -rf "$STAGE"

if [ "$DRY_RUN" = 0 ]; then
  xcrun notarytool submit "dist/$DMG_VERSIONED" \
    --key "$ASC_KEY_FILEPATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
  xcrun stapler staple "dist/$DMG_VERSIONED"
  xcrun stapler validate "dist/$DMG_VERSIONED"
fi
cp "dist/$DMG_VERSIONED" "dist/$DMG_STABLE"
echo "Release artifacts: dist/$DMG_VERSIONED and dist/$DMG_STABLE"
