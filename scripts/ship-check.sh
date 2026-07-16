#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/usage-bar-clang-cache"
export SWIFT_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/usage-bar-swift-cache"

sh -n build.sh install.sh release.sh scripts/generate-icon.sh bin/claude-account
xcrun swiftc -typecheck Sources/*.swift
xcrun swiftc Sources/Models.swift Sources/Usage.swift Tests/UsageParserTests.swift \
  -o "${TMPDIR:-/tmp}/usage-bar-parser-tests"
"${TMPDIR:-/tmp}/usage-bar-parser-tests"
BUILD_DIR="${TMPDIR:-/tmp}/usage-bar-build" INSTALL=0 ./build.sh
codesign --verify --deep --strict "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app"
file "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/MacOS/UsageBar" | grep -q arm64
file "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/MacOS/UsageBar" | grep -q x86_64
test -x "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/Resources/claude-account"
test -f "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app/Contents/Resources/AppIcon.icns"

echo "Usage Bar ship check passed"
