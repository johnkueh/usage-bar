#!/bin/sh
# Build and install Usage Bar into ~/Applications.
set -eu
cd "$(dirname "$0")"

command -v swiftc >/dev/null || { echo "swiftc is required (xcode-select --install)"; exit 1; }

./build.sh

echo
echo "Done. Next:"
echo "  1. open ~/Applications/'Usage Bar.app'"
echo "  2. Choose Add account… from the menu"
