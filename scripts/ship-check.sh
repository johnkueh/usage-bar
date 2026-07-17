#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/usage-bar-clang-cache"
export SWIFT_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/usage-bar-swift-cache"

sh -n build.sh install.sh release.sh fetch-sparkle.sh scripts/generate-icon.sh bin/claude-account
[ -d vendor/Sparkle.framework ] || ./fetch-sparkle.sh
xcrun swiftc -typecheck -F vendor Sources/*.swift
xcrun swiftc Sources/Models.swift Sources/Usage.swift Tests/UsageParserTests.swift \
  -o "${TMPDIR:-/tmp}/usage-bar-parser-tests"
"${TMPDIR:-/tmp}/usage-bar-parser-tests"
BUILD_DIR="${TMPDIR:-/tmp}/usage-bar-build" INSTALL=0 ./build.sh
codesign --verify --deep --strict "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app"
file "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/MacOS/UsageBar" | grep -q arm64
file "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/MacOS/UsageBar" | grep -q x86_64
test -x "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/Resources/claude-account"
test -f "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/Resources/AppIcon.icns"
test -d "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/Frameworks/Sparkle.framework"
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/Info.plist" | grep -q appcast.xml
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/Info.plist" | grep -qv '^$'

echo "Usage Bar ship check passed"
