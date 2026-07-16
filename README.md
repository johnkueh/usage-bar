<p align="center">
  <img src="assets/hero.png" alt="Usage Bar — Claude Code, Codex, and Grok usage in one native Mac menu" width="1100" />
</p>

**Usage Bar** keeps Claude Code, Codex, and Grok Build limits in one native macOS menu. The system bar stays compact; open the menu for every account and provider.

<p align="center">
  <a href="https://github.com/johnkueh/usage-bar/releases/latest/download/Usage-Bar.dmg"><strong>Download for Mac</strong></a>
  · macOS 13+ · Apple Silicon and Intel · MIT
</p>

## Capabilities

- **Three providers, one menu.** Claude Code shows its 5-hour and weekly windows, Codex shows every window its CLI returns, and Grok Build shows its weekly limit.
- **Claude account switching.** Save multiple Anthropic logins and click a Claude row to switch. Only the active Claude account gets a checkmark.
- **Usage-only Codex and Grok accounts.** Add the current CLI login or sign in to another isolated account. Usage Bar reads their limits without changing which account either CLI uses.
- **Native and quiet.** AppKit menu, automatic light and dark mode, five-minute refreshes, wake refreshes, and no Dock icon.
- **No autopilot.** Usage Bar never switches accounts on its own.
- **Local by default.** Account names and CLI-home paths stay on your Mac. Provider credentials remain in the files and Keychain entries their CLIs already manage.

<p align="center">
  <img src="assets/menu-dark.png" alt="Usage Bar menu showing Claude Code, Codex, and Grok Build usage" width="420" />
</p>

## Install

1. [Download the latest DMG](https://github.com/johnkueh/usage-bar/releases/latest/download/Usage-Bar.dmg).
2. Drag **Usage Bar** to **Applications**.
3. Open it, then choose **Add account…** from the menu bar.

The downloaded app is Developer ID signed and notarized by Apple. Usage Bar itself has no package-manager dependencies. Install the Claude Code, Codex, or Grok CLI only for the providers you want to monitor.

## Accounts

Claude accounts use credential snapshots in `~/.claude`. Running Claude sessions keep their existing credential when you switch; new sessions and agents use the selected account.

Codex and Grok accounts authenticate inside their existing `CODEX_HOME` or `GROK_HOME`. Usage Bar stores only account names and home paths in `~/.usage-bar/accounts.json`; it never copies rotating refresh tokens between accounts.

Removing Codex or Grok from Usage Bar leaves the CLI login files alone. Removing a Claude account deletes that account's local credential snapshot.

## Refresh behavior

Usage refreshes every five minutes, when the menu opens, after wake, and with ⌘R. If a provider cannot refresh, Usage Bar keeps the last good value and marks it as stale.

- Claude reads Anthropic's OAuth usage endpoint and refreshes expired inactive snapshots in the background.
- Codex uses the official `codex app-server` `account/rateLimits/read` method.
- Grok opens its built-in `/usage show` view in a private pseudo-terminal and reads the weekly meter.

## Build from source

```sh
git clone https://github.com/johnkueh/usage-bar
cd usage-bar
./install.sh
```

Building requires macOS 13+ and the Xcode command line tools. `./build.sh` creates a universal app; set `INSTALL=0` to leave it in `build/` without replacing the installed copy.

## Release

`./release.sh --dry-run` exercises the universal build, signing, and DMG chain locally. A real release reads Apple notarization credentials from an untracked `release.env`, signs with Developer ID, notarizes and staples both app and DMG, and writes stable and versioned artifacts to `dist/`.

## Privacy

Usage Bar has no server, analytics, or account database. It calls provider-owned endpoints or CLIs from your Mac and caches the last successful usage response in macOS preferences. Credentials are never sent anywhere except their provider.

MIT.
