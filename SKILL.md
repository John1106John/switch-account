---
name: switch-account
description: Switch between multiple Claude Code accounts by swapping only .credentials.json while sharing one ~/.claude (conversations, settings, and skills all carry over). On rate limit, auto-switch to the account with the most quota left and resume the same conversation with --continue; use `sa status` for a live usage dashboard. Windows PowerShell only. Triggers: switch-account, sa, switch account, change account, account rotation, rate limit switch account, credentials switch, multi-account credentials, resume claude on another account, usage dashboard.
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

Because every account shares `~/.claude`, `/login` writes a token into `.credentials.json`; then `capture` files it into the vault:

```powershell
# after /login with the first email:
sa capture work
# after /login with the second email:
sa capture personal
```

## Usage

```powershell
sa                # menu: list accounts (with names), pick one to switch
sa 2              # switch straight to account 2
sa list           # list the vault, names, and the current active account
sa status         # dashboard: live usage per account (session% / weekly% / reset time / email)
sa capture [name] # file the current .credentials.json as the next free number, optionally named
sa name 1 work    # name/rename an account after the fact
sa remove 2       # remove account 2 from the vault (asks to confirm)
sa watch [args]   # CLI only: wrap claude; on rate limit auto-switch to the account with the most quota and --continue
```

Names are stored in `~/.claude/.account-creds/names.json` (UTF-8). `list` and the menu show labels like `[1] work` to tell accounts apart.

After switching, the **VS Code extension needs a Reload Window** (or reopen the chat) to take effect; the CLI picks it up on next launch. Only `sa watch` achieves zero-touch rotation in the CLI.

## Limitations

- **Sequential switching, not concurrent**: `.credentials.json` is a single machine-wide file, so switching makes every running Claude conversation become the new account on its next refresh. For true parallel multi-account use, use separate `CLAUDE_CONFIG_DIR` values instead.
- **`sa watch` is CLI-only**: the VS Code extension isn't launched by the wrapper, so its exit can't be intercepted for auto-rotation.
- **Non-public usage endpoint**: `sa status` and auto-rotation use Claude Code's internal OAuth endpoint (`/api/oauth/usage`), which may break if Anthropic changes it. `sa watch` still switches only *after* hitting the limit, not preemptively.

## Tests

```powershell
powershell -File tests/run-tests.ps1   # zero-dependency, runs entirely in a temp dir, never touches real accounts
```

## Note

`scripts/*.ps1` are saved as UTF-8 with BOM so Windows PowerShell 5.1 parses non-ASCII characters correctly. If editing turns characters into mojibake and causes parse errors, re-save with a BOM.
