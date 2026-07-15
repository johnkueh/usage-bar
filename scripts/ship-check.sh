#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/usage-bar-clang-cache"
export SWIFT_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/usage-bar-swift-cache"

sh -n build.sh install.sh bin/claude-account
xcrun swiftc -typecheck Sources/*.swift
xcrun swiftc Sources/Models.swift Sources/Usage.swift Tests/UsageParserTests.swift \
  -o "${TMPDIR:-/tmp}/usage-bar-parser-tests"
"${TMPDIR:-/tmp}/usage-bar-parser-tests"
BUILD_DIR="${TMPDIR:-/tmp}/usage-bar-build" INSTALL=0 ./build.sh
codesign --verify --deep --strict "${TMPDIR:-/tmp}/usage-bar-build/Usage Bar.app"

echo "Usage Bar ship check passed"
