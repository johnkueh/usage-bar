#!/bin/bash
# Build, sign, notarize, and package a public Usage Bar release.
set -euo pipefail
cd "$(dirname "$0")"
[ -f release.env ] && source release.env

DRY_RUN=0
SET_VERSION=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --set-version)
      [ "$#" -gt 1 ] || { echo "--set-version needs a version" >&2; exit 2; }
      SET_VERSION="$2"
      shift
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ -n "$SET_VERSION" ]; then
  CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SET_VERSION" Info.plist
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((CURRENT_BUILD + 1))" Info.plist
fi

APP="Usage Bar.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
DMG_VERSIONED="Usage-Bar-$VERSION.dmg"
DMG_STABLE="Usage-Bar.dmg"
APPCAST="appcast.xml"
DOWNLOAD_PREFIX="https://github.com/johnkueh/usage-bar/releases/latest/download/"
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

FEED_STAGE="$(mktemp -d)"
cp "dist/$DMG_STABLE" "$FEED_STAGE/"
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  [ -f "$SPARKLE_ED_KEY_FILE" ] || { echo "SPARKLE_ED_KEY_FILE does not exist" >&2; exit 1; }
  vendor/bin/generate_appcast --ed-key-file "$SPARKLE_ED_KEY_FILE" \
    --download-url-prefix "$DOWNLOAD_PREFIX" "$FEED_STAGE"
else
  vendor/bin/generate_appcast --download-url-prefix "$DOWNLOAD_PREFIX" "$FEED_STAGE"
fi
cp "$FEED_STAGE/$APPCAST" "dist/$APPCAST"
rm -rf "$FEED_STAGE"
codesign --verify --deep --strict "$APP_PATH"
xmllint --noout "dist/$APPCAST"

echo "Release artifacts: dist/$DMG_VERSIONED, dist/$DMG_STABLE, and dist/$APPCAST"
echo "Upload all three to GitHub release v$VERSION."
