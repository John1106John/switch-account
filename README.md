# switch-account

Switch between multiple Claude Code accounts by swapping only `.credentials.json`, while **sharing a single `~/.claude`**. Conversations, settings, and skills all carry over — switching an account only changes *identity and quota*. `sa status` shows live usage for every account. Switching is **manual** — for fully automatic rate-limit rotation, see [teamclaude](https://github.com/KarpelesLab/teamclaude).

> Windows PowerShell only.
>
> **Not just a skill.** Although it ships as a Claude Code skill (so Claude can point you to it), it's really a standalone PowerShell CLI. Run `scripts/install.ps1` once and use `sa` directly in any terminal — Claude Code isn't required at runtime.

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

Because everything shares `~/.claude`, running `/login` with an account writes its token into `.credentials.json`; then `capture` files it into the vault. `capture` opens a menu to pick a slot — open a new one, or overwrite an existing account (handy for refreshing a re-logged-in token, or fixing a duplicate):

```powershell
# after /login with an account:
sa capture        # menu: pick [N] (new) to add, or an existing number to overwrite (confirms first)
```

## Usage

| Command | What it does |
|---|---|
| `sa` | Menu: list accounts (with names), pick one to switch |
| `sa 2` | Switch straight to account 2 |
| `sa list` | List the vault, names, and the current active account |
| `sa status` | Dashboard: live usage per account (session% / weekly% / reset time / email) |
| `sa capture` | Interactive menu: pick a slot to save the current account into (new, or overwrite an existing number) |
| `sa name 1 work` | Name / rename an account after the fact |
| `sa remove 2` | Remove account 2 from the vault (asks to confirm) |

After switching, the **VS Code extension needs a Reload Window** (or reopen the conversation) to take effect; the CLI picks it up on next launch.

## Limitations

- **Sequential switching, not concurrent**: `.credentials.json` is a single machine-wide file, so switching makes every running Claude conversation become the new account on its next refresh. For true parallel multi-account use, use separate `CLAUDE_CONFIG_DIR` values instead.
- **Manual switching only — no auto-rotation**: interactive Claude does *not* exit when rate-limited (it stays in the TUI), so a CLI wrapper has no reliable trigger to hook. For **automatic** quota-based rotation with zero interruption, use a proxy-based tool like [teamclaude](https://github.com/KarpelesLab/teamclaude) (it injects each account's token at the proxy, so Claude never has to restart).
- **Non-public usage endpoint**: `sa status` relies on Claude Code's internal OAuth endpoint (`/api/oauth/usage`), which may break if Anthropic changes it.

## Security

This skill contains **no tokens**: scripts always use the relative path `$HOME\.claude\.credentials.json`, and tokens are read from your machine at runtime — never hardcoded or moved. Real credentials only ever live in `~/.claude/.account-creds/` (**outside this repo**) and are additionally guarded by `.gitignore`. Safe to publish.

## Tests

```powershell
powershell -File tests/run-tests.ps1   # zero-dependency (no Pester), runs entirely in a temp dir, never touches real accounts
```

## Credits

The concept comes from `ccc` (a pair of bash skills for seamless cross-account switching). This project rewrites it for **Windows PowerShell + shared credentials**, adding a live usage dashboard and named account slots. For fully automatic proxy-based rotation, see [teamclaude](https://github.com/KarpelesLab/teamclaude).
