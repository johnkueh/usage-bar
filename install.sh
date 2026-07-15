#!/bin/sh
# Install Usage Bar and the Claude account helper into ~/Applications.
set -eu
cd "$(dirname "$0")"

command -v jq >/dev/null || { echo "jq is required (brew install jq)"; exit 1; }
command -v swiftc >/dev/null || { echo "swiftc is required (xcode-select --install)"; exit 1; }

# claude-account does the credential snapshots + switching; the app drives it.
if [ ! -e "$HOME/.local/bin/claude-account" ]; then
  mkdir -p "$HOME/.local/bin"
  cp bin/claude-account "$HOME/.local/bin/claude-account"
  chmod +x "$HOME/.local/bin/claude-account"
  echo "Installed claude-account to ~/.local/bin"
else
  echo "claude-account already present — leaving yours in place"
fi

./build.sh

echo
echo "Done. Next:"
echo "  1. open ~/Applications/'Usage Bar.app'"
echo "  2. Choose Add account… from the menu"
