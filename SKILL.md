---
name: switch-account
description: Switch between multiple Claude Code accounts by swapping only .credentials.json while sharing one ~/.claude (conversations, settings, and skills all carry over). Manual menu/number switching, account naming, and a live usage dashboard (`sa status`). Windows PowerShell only. For automatic rate-limit rotation, use a proxy-based tool like teamclaude instead. Triggers: switch-account, sa, switch account, change account, credentials switch, multi-account credentials, claude usage dashboard.
---

# switch-account

Switch Claude accounts by swapping only `~/.claude/.credentials.json`; conversations, settings, and skills carry over because everything shares one `~/.claude`. Built for *sequential* switching ("one account is rate-limited, continue the same conversation on the next account"), not concurrent dual use.

## Core invariant

`~/.claude/.credentials.json` always equals the latest content of whatever `current` points to. Every switch does **save-out -> apply-in**: first copy the live file back to its own number (preserving any token Claude refreshed in the background, so the vault never goes stale), then overwrite with the target account.

Vault: `~/.claude/.account-creds/`, numbered files `1.json`, `2.json`, plus a `current` file recording the active number.

## Install

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1   # register the `sa` command in $PROFILE
. $PROFILE                                                      # reload
```

## Registering accounts

Because every account shares `~/.claude`, `/login` writes a token into `.credentials.json`; then `capture` files it into the vault. `capture` opens a menu to pick a slot — open a new one, or overwrite an existing account (handy for refreshing a re-logged-in token, or fixing a duplicate):

```powershell
# after /login with an account:
sa capture        # menu: pick [N] (new) to add, or an existing number to overwrite (confirms first)
```

## Usage

```powershell
sa                # menu: list accounts (with names), pick one to switch
sa 2              # switch straight to account 2
sa list           # list the vault, names, and the current active account
sa status         # dashboard: live usage per account (session% / weekly% / reset time / email)
sa capture        # interactive menu: pick a slot to save the current account into (new, or overwrite an existing number)
sa name 1 work    # name/rename an account after the fact
sa remove 2       # remove account 2 from the vault (asks to confirm)
```

Names are stored in `~/.claude/.account-creds/names.json` (UTF-8). `list` and the menu show labels like `[1] work` to tell accounts apart.

After switching, **no restart is needed on Windows**: Claude Code re-reads `.credentials.json` whenever it changes, so the new account takes effect on your **next message** — in both the CLI and the VS Code extension. (This is a Windows behavior; on macOS the Keychain is cached, which is why this tool targets Windows.)

## Limitations

- **Sequential switching, not concurrent**: `.credentials.json` is a single machine-wide file, so switching makes every running Claude conversation become the new account on its next refresh. For true parallel multi-account use, use separate `CLAUDE_CONFIG_DIR` values instead.
- **Manual switching only — no auto-rotation**: interactive Claude does *not* exit when rate-limited (it stays in the TUI), so a CLI wrapper has no reliable trigger to hook. For **automatic** quota-based rotation with zero interruption, use a proxy-based tool like [teamclaude](https://github.com/KarpelesLab/teamclaude) instead (it injects each account's token at the proxy, so Claude never has to restart).
- **Non-public usage endpoint**: `sa status` uses Claude Code's internal OAuth endpoint (`/api/oauth/usage`), which may break if Anthropic changes it.

## Tests

```powershell
powershell -File tests/run-tests.ps1   # zero-dependency, runs entirely in a temp dir, never touches real accounts
```

## Note

`scripts/*.ps1` are saved as UTF-8 with BOM so Windows PowerShell 5.1 parses non-ASCII characters correctly. If editing turns characters into mojibake and causes parse errors, re-save with a BOM.
