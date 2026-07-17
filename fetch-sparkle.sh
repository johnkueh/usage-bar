#!/bin/sh
# Vendor the pinned Sparkle framework and release tools into vendor/ (gitignored).
set -eu
cd "$(dirname "$0")"

SPARKLE_VERSION="2.9.3"
if [ -d vendor/Sparkle.framework ] && [ -x vendor/bin/generate_appcast ]; then
  echo "Sparkle $SPARKLE_VERSION already vendored."
  exit 0
fi

mkdir -p vendor
URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
echo "Fetching $URL"
curl -fsSL "$URL" -o vendor/sparkle.tar.xz
tar xf vendor/sparkle.tar.xz -C vendor
rm -f vendor/sparkle.tar.xz
echo "Vendored Sparkle $SPARKLE_VERSION -> vendor/"
