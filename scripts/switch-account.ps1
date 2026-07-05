<#
.SYNOPSIS
  switch-account — switch Claude accounts by swapping only .credentials.json, while sharing one ~/.claude.

.DESCRIPTION
  Conversations, settings, and skills all share one ~/.claude; switching an account only overwrites
  .credentials.json (identity/quota). Credential copies live in <root>/.account-creds/ as numbered
  files (1.json, 2.json...); a `current` file records the active number.
  Every switch does "save-out -> apply-in" to keep the invariant: .credentials.json always equals the
  latest content of the number that `current` points to.

.USAGE
  switch-account.ps1            # menu: list accounts, pick one to switch
  switch-account.ps1 2          # switch straight to account 2
  switch-account.ps1 capture    # file the current .credentials.json as the next free number
  switch-account.ps1 list       # list the vault and the current active account
  switch-account.ps1 watch ...  # wrap claude; on rate limit, auto-rotate to another account (CLI only)

  Override the root dir with $env:SA_CLAUDE_DIR (default ~/.claude); tests point it at a temp dir.
#>

param(
  [Parameter(Position = 0)]
  [string]$Command,

  [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
  [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# ── Paths ────────────────────────────────────────────────────────────────────
function Get-Root {
  if ($env:SA_CLAUDE_DIR) { return $env:SA_CLAUDE_DIR }
  return (Join-Path $HOME '.claude')
}
function Get-CredsDir   { return (Join-Path (Get-Root) '.account-creds') }
function Get-ActiveFile { return (Join-Path (Get-Root) '.credentials.json') }
function Get-CurrentFile { return (Join-Path (Get-CredsDir) 'current') }
function Get-AccountFile([int]$n) { return (Join-Path (Get-CredsDir) "$n.json") }
function Get-NamesFile { return (Join-Path (Get-CredsDir) 'names.json') }

# ── State I/O ────────────────────────────────────────────────────────────────
function Get-Current {
  $f = Get-CurrentFile
  if (-not (Test-Path $f)) { return $null }
  $raw = (Get-Content $f -Raw).Trim()
  if ($raw -match '^\d+$') { return [int]$raw }
  return $null
}

function Initialize-CredsDir {
  $dir = Get-CredsDir
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
}

function Set-Current([int]$n) {
  Initialize-CredsDir
  [IO.File]::WriteAllText((Get-CurrentFile), "$n")
}

# Return all account numbers in the vault (ascending)
function Get-AccountNumbers {
  $dir = Get-CredsDir
  if (-not (Test-Path $dir)) { return @() }
  $nums = @()
  foreach ($f in Get-ChildItem $dir -Filter '*.json' -File) {
    if ($f.BaseName -match '^\d+$') { $nums += [int]$f.BaseName }
  }
  return ($nums | Sort-Object)
}

# ── Names (number -> label mapping) ──────────────────────────────────────────
# Stored in names.json, read/written as UTF-8 so non-ASCII names survive (avoids the PS 5.1 ANSI pitfall).
function Get-Names {
  $f = Get-NamesFile
  $h = @{}
  if (Test-Path $f) {
    try {
      $obj = Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
    } catch {}
  }
  return $h
}

function Set-Name([int]$n, [string]$name) {
  Initialize-CredsDir
  $h = Get-Names
  $h["$n"] = $name
  ($h | ConvertTo-Json) | Set-Content (Get-NamesFile) -Encoding UTF8
}

function Get-Name([int]$n) {
  $h = Get-Names
  if ($h.ContainsKey("$n")) { return $h["$n"] }
  return ''
}

# ── Validation ───────────────────────────────────────────────────────────────
# Valid credentials = parses as JSON and has claudeAiOauth.accessToken
function Test-CredentialsFile([string]$path) {
  if (-not (Test-Path $path)) { return $false }
  try {
    $j = Get-Content $path -Raw | ConvertFrom-Json
    return [bool]$j.claudeAiOauth.accessToken
  } catch { return $false }
}

# ── Core state machine ───────────────────────────────────────────────────────
# Save-out: copy the live file back to the number `current` points to (preserves tokens Claude refreshed in the background)
function Save-ActiveBack {
  $cur = Get-Current
  if ($null -eq $cur) { return }              # current unknown -> skip (don't know which number to save back to)
  $active = Get-ActiveFile
  if (-not (Test-CredentialsFile $active)) { return }  # live file invalid -> don't overwrite the vault
  Initialize-CredsDir
  Copy-Item $active (Get-AccountFile $cur) -Force
}

# Apply-in: overwrite the live file with N.json and update current
function Set-ActiveAccount([int]$n) {
  Copy-Item (Get-AccountFile $n) (Get-ActiveFile) -Force
  Set-Current $n
}

# Full switch: save-out -> apply-in
function Invoke-Switch([int]$n, [switch]$Quiet) {
  $src = Get-AccountFile $n
  if (-not (Test-Path $src)) {
    $avail = (Get-AccountNumbers) -join ', '
    Write-Host "X Account ($n) not found. Available: $(if ($avail) { $avail } else { '(vault is empty; run capture first)' })"
    return $false
  }
  if (-not (Test-CredentialsFile $src)) {
    Write-Host "X $n.json is not valid credentials; aborted (live file untouched)."
    return $false
  }
  if ($null -eq (Get-Current)) {
    Write-Host "! current unknown; skipping save-out - the previous account's freshly refreshed token may be lost, re-login if needed."
  }
  Save-ActiveBack
  Set-ActiveAccount $n
  if (-not $Quiet) {
    Write-Host "OK Switched to account ($n)."
    Write-Host "   VS Code extension: Reload Window (or reopen the chat) to take effect; CLI picks it up on next launch."
  }
  return $true
}

# Capture: file the live file as the next free number (max+1; 1 for an empty vault). Optional name.
function Invoke-Capture([string]$name = '') {
  $active = Get-ActiveFile
  if (-not (Test-Path $active)) {
    Write-Host "X Not logged in (no $active). /login with an account first, then capture."
    return
  }
  if (-not (Test-CredentialsFile $active)) {
    Write-Host "X Current .credentials.json is not valid credentials; aborted."
    return
  }
  $nums = Get-AccountNumbers
  $next = if ($nums.Count -gt 0) { ($nums | Measure-Object -Maximum).Maximum + 1 } else { 1 }
  Initialize-CredsDir
  Copy-Item $active (Get-AccountFile $next) -Force
  Set-Current $next
  if ($name) { Set-Name $next $name }
  $suffix = if ($name) { " '$name'" } else { '' }
  Write-Host "OK Registered current account as ($next)$suffix and set as current."
}

# Name/rename after the fact: sa name <number> <name>
function Invoke-SetName([string[]]$rest) {
  if (-not $rest -or $rest.Count -lt 2) { Write-Host "Usage: sa name <number> <name>"; return }
  if ($rest[0] -notmatch '^\d+$') { Write-Host "Number must be numeric."; return }
  $n = [int]$rest[0]
  if (-not (Test-Path (Get-AccountFile $n))) { Write-Host "X Account ($n) not found."; return }
  $name = ($rest[1..($rest.Count - 1)] -join ' ')
  Set-Name $n $name
  Write-Host "OK Account ($n) named '$name'."
}

# List the vault
function Invoke-List {
  $nums = Get-AccountNumbers
  if ($nums.Count -eq 0) { Write-Host "(vault is empty; register an account with capture first)"; return }
  $cur = Get-Current
  $names = Get-Names
  Write-Host "Account vault ($(Get-CredsDir)):"
  foreach ($n in $nums) {
    $nm = if ($names.ContainsKey("$n")) { " " + $names["$n"] } else { '' }
    $mark = if ($n -eq $cur) { '  <- current' } else { '' }
    Write-Host ("  [{0}]{1}{2}" -f $n, $nm, $mark)
  }
}

# Menu: list -> read input -> switch
function Invoke-Menu {
  $nums = Get-AccountNumbers
  if ($nums.Count -eq 0) { Write-Host "(vault is empty; register an account with capture first)"; return }
  Invoke-List
  $ans = (Read-Host "Switch to which number? (Enter to cancel)").Trim()
  if (-not $ans) { return }
  if ($ans -notmatch '^\d+$') { Write-Host "Please enter a numeric account number."; return }
  [void](Invoke-Switch ([int]$ans))
}

# Next number (wrap around): the next existing number after current, wrapping to the start
function Get-NextNumber([int]$cur) {
  $nums = Get-AccountNumbers
  if ($nums.Count -eq 0) { return $null }
  $after = $nums | Where-Object { $_ -gt $cur }
  if ($after) { return ($after | Select-Object -First 1) }
  return $nums[0]
}

# ── Usage dashboard ──────────────────────────────────────────────────────────
# Query Anthropic usage/profile with each account's own OAuth token.
# Note: this is Claude Code's internal non-public endpoint; may break if Anthropic changes it.
$ApiBase = 'https://api.anthropic.com'

function Get-AccountToken([int]$n) {
  $f = Get-AccountFile $n
  if (-not (Test-Path $f)) { return $null }
  try { return (Get-Content $f -Raw | ConvertFrom-Json).claudeAiOauth.accessToken } catch { return $null }
}

function Invoke-OAuthApi([string]$token, [string]$path) {
  $headers = @{
    "Authorization"     = "Bearer $token"
    "anthropic-beta"    = "oauth-2025-04-20"
    "anthropic-version" = "2023-06-01"
  }
  return Invoke-RestMethod -Uri "$ApiBase$path" -Headers $headers -Method GET -TimeoutSec 20
}

function Format-ResetTime([string]$iso) {
  if (-not $iso) { return '-' }
  try { return ([datetimeoffset]$iso).LocalDateTime.ToString('MM/dd HH:mm') } catch { return $iso }
}

# sa status: list live usage for every account
function Invoke-Status {
  $nums = Get-AccountNumbers
  if ($nums.Count -eq 0) { Write-Host "(vault is empty; register an account with capture first)"; return }
  $cur = Get-Current
  $names = Get-Names
  foreach ($n in $nums) {
    $tok = Get-AccountToken $n
    $nm = if ($names.ContainsKey("$n")) { $names["$n"] } else { '(unnamed)' }
    $tag = if ($n -eq $cur) { ' <- current' } else { '' }
    Write-Host ""
    Write-Host "[$n] $nm$tag" -ForegroundColor Cyan
    if (-not $tok) { Write-Host "    (cannot read token)"; continue }
    try {
      $u = Invoke-OAuthApi $tok '/api/oauth/usage'
      $sess = [int]$u.five_hour.utilization
      $week = [int]$u.seven_day.utilization
      $email = ''
      try { $email = (Invoke-OAuthApi $tok '/api/oauth/profile').account.email } catch {}
      if ($email) { Write-Host "    $email" }
      Write-Host ("    Session {0}% (resets {1})   Weekly {2}% (resets {3})" -f `
        $sess, (Format-ResetTime $u.five_hour.resets_at), $week, (Format-ResetTime $u.seven_day.resets_at))
    } catch {
      $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
      Write-Host "    ! Query failed (HTTP $code) - token may be expired; re-login with that account and sa capture to refresh."
    }
  }
  Write-Host ""
}

# ── Auto-rotation (CLI only) ─────────────────────────────────────────────────
$RateLimitPattern = 'rate.?limit|too many requests|429|usage.?limit|plan limit|over_capacity'

# Detect rate limit from the tail of the most recently modified session jsonl under <root>/projects
function Test-RateLimited {
  $projects = Join-Path (Get-Root) 'projects'
  if (-not (Test-Path $projects)) { return $false }
  $latest = Get-ChildItem $projects -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $latest) { return $false }
  $tail = Get-Content $latest.FullName -Tail 30 -ErrorAction SilentlyContinue
  return [bool]($tail -match $RateLimitPattern)
}

# Pick the account with the most quota (excluding `exclude`): among those below both session/weekly
# limits, the one with the lowest session usage.
# Returns @{ Best = number or $null; AnyQueried = whether at least one account was queried successfully }.
function Get-BestAccount([int]$exclude) {
  $best = $null; $bestUtil = [double]999; $anyQueried = $false
  foreach ($n in Get-AccountNumbers) {
    if ($n -eq $exclude) { continue }
    $tok = Get-AccountToken $n
    if (-not $tok) { continue }
    try {
      $u = Invoke-OAuthApi $tok '/api/oauth/usage'
      $anyQueried = $true
      $s = [double]$u.five_hour.utilization
      $w = [double]$u.seven_day.utilization
      if ($s -ge 100 -or $w -ge 100) { continue }   # maxed out, skip
      if ($s -lt $bestUtil) { $bestUtil = $s; $best = $n }
    } catch { continue }
  }
  return @{ Best = $best; AnyQueried = $anyQueried }
}

function Invoke-Watch([string[]]$claudeArgs) {
  $tried = @{}
  $first = $true
  while ($true) {
    $runArgs = @()
    if ($claudeArgs) { $runArgs += $claudeArgs }
    if (-not $first) { $runArgs = @('--continue') + $runArgs }  # resume the same conversation after switching

    & claude @runArgs
    $code = $LASTEXITCODE
    $first = $false

    if ($code -eq 0) { exit 0 }
    # PowerShell has no standard 130; Ctrl-C usually lets the child exit on its own - only act on rate limit here
    if (-not (Test-RateLimited)) { exit $code }

    $cur = Get-Current
    if ($null -eq $cur) { Write-Host "! Hit rate limit, but current is unknown; cannot auto-rotate. Use list/switch manually."; exit $code }
    $tried[$cur] = $true

    # Prefer the account with the most quota; fall back to sequential rotation if the usage API is unreachable.
    $sel = Get-BestAccount $cur
    if ($sel.Best) {
      $next = $sel.Best
    } elseif ($sel.AnyQueried) {
      Write-Host ""
      Write-Host "! All accounts are maxed out. Time for a break."
      exit $code
    } else {
      $next = Get-NextNumber $cur
      if ($null -eq $next -or $tried.ContainsKey($next)) {
        Write-Host ""
        Write-Host "! No usable account (usage query failed and rotated a full loop)."
        exit $code
      }
    }
    Write-Host ""
    Write-Host "! Account ($cur) hit rate limit -> auto-switching to ($next) with the most quota..."
    if (-not (Invoke-Switch $next -Quiet)) { exit $code }
  }
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
# When dot-sourced (. switch-account.ps1) InvocationName is '.'; only define functions for tests, don't dispatch.
if ($MyInvocation.InvocationName -ne '.') {
  switch -Regex ($Command) {
    '^\d+$'      { [void](Invoke-Switch ([int]$Command)); break }
    '^capture$'  { Invoke-Capture ($Rest -join ' '); break }
    '^name$'     { Invoke-SetName $Rest; break }
    '^list$'     { Invoke-List; break }
    '^status$'   { Invoke-Status; break }
    '^watch$'    { Invoke-Watch $Rest; break }
    '^$'         { Invoke-Menu; break }
    default {
      Write-Host "Unknown command: $Command"
      Write-Host "Usage: switch-account [<number> | capture [name] | name <number> <name> | list | status | watch ...] (no args = menu)"
    }
  }
}
