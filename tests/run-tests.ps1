<#
  Zero-dependency test runner (no Pester): verifies the switch-account core state machine.
  Uses $env:SA_CLAUDE_DIR pointed at a temp dir throughout; never touches the real ~/.claude.
  Interactive commands (Invoke-Capture / Invoke-Remove) are exercised via their non-interactive
  cores (Add-Account / Save-ToSlot / Remove-Account); the Read-Host prompts are verified by hand.
  Run: powershell -File .\tests\run-tests.ps1
#>
$ErrorActionPreference = 'Stop'

# dot-source the main script -> defines functions only, does not dispatch
. (Join-Path $PSScriptRoot '..\scripts\switch-account.ps1')

$script:Pass = 0
$script:Fail = 0

function Assert-Equal($actual, $expected, $msg) {
  if ($actual -eq $expected) { $script:Pass++; Write-Host "  PASS  $msg" -ForegroundColor Green }
  else { $script:Fail++; Write-Host "  FAIL  $msg`n        expected [$expected] got [$actual]" -ForegroundColor Red }
}
function Assert-True($cond, $msg)  { Assert-Equal ([bool]$cond) $true  $msg }
function Assert-False($cond, $msg) { Assert-Equal ([bool]$cond) $false $msg }

# Test helpers
function Set-ActiveCreds([string]$accessToken, [string]$refreshToken = 'r') {
  $obj = @{ claudeAiOauth = @{ accessToken = $accessToken; refreshToken = $refreshToken } }
  $obj | ConvertTo-Json -Depth 5 | Set-Content (Get-ActiveFile)
}
function Read-AT([string]$path) {
  (Get-Content $path -Raw | ConvertFrom-Json).claudeAiOauth.accessToken
}

# Each test runs in a clean temp dir
function Run-Case([string]$name, [scriptblock]$body) {
  $root = Join-Path ([IO.Path]::GetTempPath()) ("sa-test-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Force $root | Out-Null
  $env:SA_CLAUDE_DIR = $root
  Write-Host "* $name"
  try { Set-ActiveCreds 'sk-ant-AAA'; & $body }
  catch { $script:Fail++; Write-Host "  ERROR $($_.Exception.Message)" -ForegroundColor Red }
  finally {
    Remove-Item Env:\SA_CLAUDE_DIR -ErrorAction SilentlyContinue
    if (Test-Path $root) { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

Run-Case 'Add-Account into empty vault -> 1.json and current=1' {
  Add-Account | Out-Null
  Assert-True (Test-Path (Get-AccountFile 1)) '1.json created'
  Assert-Equal (Get-Current) 1 'current=1'
  Assert-Equal (Read-AT (Get-AccountFile 1)) 'sk-ant-AAA' '1.json content = live file'
}

Run-Case 'Add-Account again -> increments to 2 without overwriting 1.json' {
  Add-Account | Out-Null
  Set-ActiveCreds 'sk-ant-BBB'
  Add-Account | Out-Null
  Assert-Equal (Get-Current) 2 'current=2'
  Assert-Equal (Read-AT (Get-AccountFile 1)) 'sk-ant-AAA' '1.json not overwritten'
  Assert-Equal (Read-AT (Get-AccountFile 2)) 'sk-ant-BBB' '2.json = new live file'
}

Run-Case 'Add-Account returns the assigned number' {
  Assert-Equal (Add-Account) 1 'first = 1'
  Set-ActiveCreds 'sk-ant-BBB'
  Assert-Equal (Add-Account) 2 'second = 2'
}

Run-Case 'switch to N -> live file = N.json and current=N' {
  Add-Account | Out-Null
  Set-ActiveCreds 'sk-ant-BBB'
  Add-Account | Out-Null
  Invoke-Switch 1 | Out-Null
  Assert-Equal (Read-AT (Get-ActiveFile)) 'sk-ant-AAA' 'live file swapped to 1.json'
  Assert-Equal (Get-Current) 1 'current=1'
}

Run-Case 'two-way sync -> save refreshed live file back before leaving' {
  Add-Account | Out-Null                        # 1=AAA
  Set-ActiveCreds 'sk-ant-BBB'
  Add-Account | Out-Null                        # 2=BBB
  Invoke-Switch 1 | Out-Null                    # current=1, live=AAA
  Set-ActiveCreds 'sk-ant-AAA-refreshed'        # simulate background refresh
  Invoke-Switch 2 | Out-Null                    # save-out should update 1.json
  Assert-Equal (Read-AT (Get-AccountFile 1)) 'sk-ant-AAA-refreshed' '1.json keeps refreshed token'
  Assert-Equal (Read-AT (Get-ActiveFile)) 'sk-ant-BBB' 'live file swapped to 2.json'
}

Run-Case 'Save-ToSlot overwrites an existing slot, keeps name when none given' {
  Add-Account 'work' | Out-Null                 # 1 = AAA 'work'
  Set-ActiveCreds 'sk-ant-NEW'
  Save-ToSlot 1 | Out-Null                      # overwrite 1, no name arg
  Assert-Equal (Read-AT (Get-AccountFile 1)) 'sk-ant-NEW' '1.json credentials overwritten'
  Assert-Equal (Get-Name 1) 'work' 'name kept when none given'
  Assert-Equal (Get-Current) 1 'current=1'
}

Run-Case 'Save-ToSlot with a new name updates the name' {
  Add-Account 'work' | Out-Null
  Set-ActiveCreds 'sk-ant-NEW'
  Save-ToSlot 1 'backup' | Out-Null
  Assert-Equal (Get-Name 1) 'backup' 'name updated'
}

Run-Case 'switch to nonexistent number -> false and live file unchanged' {
  Add-Account | Out-Null
  Assert-False (Invoke-Switch 9) 'Invoke-Switch 9 returns false'
  Assert-Equal (Read-AT (Get-ActiveFile)) 'sk-ant-AAA' 'live file unchanged'
}

Run-Case 'switch with invalid source credentials -> rejected and live file unchanged' {
  Add-Account | Out-Null
  'not valid json' | Set-Content (Get-AccountFile 2)
  Assert-False (Invoke-Switch 2) 'Invoke-Switch 2 returns false'
  Assert-Equal (Read-AT (Get-ActiveFile)) 'sk-ant-AAA' 'live file unchanged'
}

Run-Case 'Add-Account with name -> records the name' {
  Add-Account 'work' | Out-Null
  Assert-Equal (Get-Name 1) 'work' 'account 1 name = work'
}

Run-Case 'name / rename after the fact (incl. non-ASCII, tests UTF-8)' {
  Add-Account | Out-Null                    # 1, no name
  Assert-Equal (Get-Name 1) '' 'no name initially'
  Invoke-SetName @('1', 'personal') | Out-Null
  Assert-Equal (Get-Name 1) 'personal' 'named personal'
  Invoke-SetName @('1', '工作', '機') | Out-Null   # non-ASCII with a space, verifies UTF-8 round-trip
  Assert-Equal (Get-Name 1) '工作 機' 'renamed with non-ASCII + space'
}

Run-Case 'name nonexistent number -> not written' {
  Add-Account | Out-Null
  Invoke-SetName @('9', 'X') | Out-Null
  Assert-Equal (Get-Name 9) '' 'no name written for nonexistent number'
}

Run-Case 'remove account -> file gone, name dropped, current cleared' {
  Add-Account 'work' | Out-Null               # 1, current=1
  Assert-True (Remove-Account 1) 'Remove-Account 1 returns true'
  Assert-False (Test-Path (Get-AccountFile 1)) '1.json deleted'
  Assert-Equal (Get-Name 1) '' 'name dropped'
  Assert-Equal (Get-Current) $null 'current cleared (was 1)'
}

Run-Case 'remove keeps other accounts and their current' {
  Add-Account | Out-Null                      # 1
  Set-ActiveCreds 'sk-ant-BBB'
  Add-Account | Out-Null                      # 2, current=2
  Assert-True (Remove-Account 1) 'Remove-Account 1 returns true'
  Assert-False (Test-Path (Get-AccountFile 1)) '1.json deleted'
  Assert-True (Test-Path (Get-AccountFile 2)) '2.json kept'
  Assert-Equal (Get-Current) 2 'current still 2 (not removed)'
}

Run-Case 'remove nonexistent -> false' {
  Add-Account | Out-Null
  Assert-False (Remove-Account 9) 'Remove-Account 9 returns false'
}

Write-Host ""
Write-Host ("Result: {0} passed, {1} failed" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
exit $(if ($script:Fail) { 1 } else { 0 })
