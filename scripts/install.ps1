<#
.SYNOPSIS
  Register the `sa` shortcut in the PowerShell $PROFILE, pointing at switch-account.ps1.
.DESCRIPTION
  Idempotent: won't add twice. Afterwards `sa` / `sa 2` / `sa capture` / `sa list` / `sa watch` are available.
#>

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'switch-account.ps1'
$marker = '# switch-account skill: sa command'
$funcLine = "function sa { & `"$scriptPath`" @args }"

if (-not (Test-Path $PROFILE)) {
  New-Item -ItemType File -Force $PROFILE | Out-Null
  Write-Host "Created profile: $PROFILE"
}

$content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($content -and $content.Contains($marker)) {
  Write-Host "sa command already registered ($PROFILE); skipping."
} else {
  Add-Content $PROFILE "`r`n$marker`r`n$funcLine`r`n"
  Write-Host "Registered sa command in $PROFILE."
}

Write-Host ""
Write-Host "Reload the profile to activate sa:  . `$PROFILE"
Write-Host "Then:"
Write-Host "  1) /login with the first account, then: sa capture"
Write-Host "  2) /login with the second account, then: sa capture"
Write-Host "  3) Afterwards use the sa menu to switch, or sa watch to auto-rotate on rate limit in the CLI."
