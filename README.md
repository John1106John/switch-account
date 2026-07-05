# switch-account

Switch between multiple Claude Code accounts by swapping only `.credentials.json`, while **sharing a single `~/.claude`**. Conversations, settings, and skills all carry over — switching an account only changes *identity and quota*. When you hit a rate limit it can auto-switch to the account with the **most quota left**, and `sa status` shows live usage for every account.

> Windows PowerShell only. This is a Claude Code Skill whose essence is a set of CLI commands (`sa`).

## Core idea

Claude Code stores its login token in `~/.claude/.credentials.json` (a plain file on Windows, not the Keychain). Every account shares the same `~/.claude`, so:

- **Conversations, settings, and skills are shared by nature** — they all live in the same directory; switching accounts doesn't touch them.
- **Only `.credentials.json` needs to change** to switch identity and quota.

Credential copies live in `~/.claude/.account-creds/` (`1.json`, `2.json`, …), and a `current` file records the active number.

**Core invariant**: `.credentials.json` always equals the latest content of whatever `current` points to. Every switch does **save-out → apply-in** — first copy the live file back to its own number (preserving any token Claude refreshed in the background), then overwrite with the target account. This keeps the vault from going stale.

## Install

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1   # register the `sa` command in $PROFILE
. $PROFILE                                                      # reload
```

## Registering accounts

Because everything shares `~/.claude`, running `/login` with an account writes its token into `.credentials.json`; then `capture` files it into the vault:

```powershell
# after /login with the first email:
sa capture work
# after /login with the second email:
sa capture personal
```

## Usage

| Command | What it does |
|---|---|
| `sa` | Menu: list accounts (with names), pick one to switch |
| `sa 2` | Switch straight to account 2 |
| `sa list` | List the vault, names, and the current active account |
| `sa status` | Dashboard: live usage per account (session% / weekly% / reset time / email) |
| `sa capture [name]` | File the current `.credentials.json` as the next free number, optionally named |
| `sa name 1 work` | Name / rename an account after the fact |
| `sa watch [args]` | CLI only: wraps `claude`; on rate limit, auto-switch to the account with the most quota and resume with `--continue` |

After switching, the **VS Code extension needs a Reload Window** (or reopen the conversation) to take effect; the CLI picks it up on next launch.

## Limitations

- **Sequential switching, not concurrent**: `.credentials.json` is a single machine-wide file, so switching makes every running Claude conversation become the new account on its next refresh. For true parallel multi-account use, use separate `CLAUDE_CONFIG_DIR` values instead.
- **`sa watch` is CLI-only**: the VS Code extension isn't launched by the wrapper, so its exit can't be intercepted for auto-rotation.
- **Non-public usage endpoint**: `sa status` and auto-rotation rely on Claude Code's internal OAuth endpoint (`/api/oauth/usage`), which may break if Anthropic changes it.

## Security

This skill contains **no tokens**: scripts always use the relative path `$HOME\.claude\.credentials.json`, and tokens are read from your machine at runtime — never hardcoded or moved. Real credentials only ever live in `~/.claude/.account-creds/` (**outside this repo**) and are additionally guarded by `.gitignore`. Safe to publish.

## Tests

```powershell
powershell -File tests/run-tests.ps1   # zero-dependency (no Pester), runs entirely in a temp dir, never touches real accounts
```

## Credits

The concept comes from `ccc` (a pair of bash skills for seamless cross-account switching). This project rewrites it for **Windows PowerShell + shared credentials**, adding a usage dashboard and "switch to the account with the most quota" auto-rotation.
