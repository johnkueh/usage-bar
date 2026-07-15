# Usage Bar

Usage Bar is a native macOS menu bar app for monitoring Claude Code, Codex, and Grok Build accounts. Pin one account to the system bar and open the menu for the full multi-provider dashboard.

```sh
git clone https://github.com/johnkueh/claude-usage-bar
cd claude-usage-bar && ./install.sh
```

Requires macOS 13+, `jq`, and the Xcode command line tools. Codex and Grok Build support requires their respective CLIs.

## What it shows

- **Claude Code:** 5-hour and weekly windows.
- **Codex:** every window returned by Codex. It currently returns a weekly window; a 5-hour window will appear automatically if OpenAI restores it.
- **Grok Build:** its weekly window.

The menu bar shows one pinned account, not every provider at once. Choose *Show in menu bar* from any account’s submenu to change the pin. The tooltip includes the provider and account name.

## Accounts

Open *Add account…* to:

- save the current Claude Code login;
- add the current Codex or Grok Build login; or
- sign in to another Codex or Grok Build account in an isolated CLI home.

Additional Codex and Grok accounts authenticate directly inside their own `CODEX_HOME` or `GROK_HOME`. Usage Bar stores only account names and home paths in `~/.usage-bar/accounts.json`; provider credentials stay in the provider-managed auth files with their existing permissions. It never copies rotating refresh tokens between accounts.

Claude keeps the existing snapshot model in `~/.claude`. Manual switching remains available from a Claude account’s submenu. Running Claude sessions keep their existing credential; new sessions use the selected account. There is no automatic switching.

Removing a Codex or Grok account detaches it from Usage Bar without deleting its CLI login files. Removing a Claude account deletes that account’s local credential snapshot.

## Refresh behavior

Usage refreshes every five minutes, when the menu opens, after wake, and with ⌘R. A failed refresh keeps the last good value and marks it with `~`.

- Claude uses Anthropic’s OAuth usage endpoint and retains the existing background refresh for expired inactive snapshots.
- Codex uses the official `codex app-server` `account/rateLimits/read` method, so Codex owns token refresh.
- Grok opens its built-in `/usage show` view in a private pseudo-terminal and parses the weekly meter. Grok owns token refresh.

## Build without installing

```sh
INSTALL=0 ./build.sh
```

The app is built at `build/Usage Bar.app`. The bundle identifier remains `com.johnkueh.claude-usage-bar`, preserving launch-at-login registration and preferences from Claude Usage.

## Debug hooks

| Environment variable | Behavior |
|---|---|
| `DEBUG_SHOOT=1` | Renders light and dark status/menu proof images to `/tmp/usage-bar-*.png`, then quits. |
| `DEBUG_SWITCH=<name>` | Exercises the real manual Claude switch path, then quits. |

MIT.
