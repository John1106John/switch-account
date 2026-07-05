<#
.SYNOPSIS
  在 PowerShell $PROFILE 註冊 `sa` 短指令，指向 switch-account.ps1。
.DESCRIPTION
  冪等：已註冊就不重複加。之後 `sa` / `sa 2` / `sa capture` / `sa list` / `sa watch` 即可用。
#>

$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'switch-account.ps1'
$marker = '# switch-account skill: sa 指令'
$funcLine = "function sa { & `"$scriptPath`" @args }"

if (-not (Test-Path $PROFILE)) {
  New-Item -ItemType File -Force $PROFILE | Out-Null
  Write-Host "已建立 profile：$PROFILE"
}

$content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($content -and $content.Contains($marker)) {
  Write-Host "✓ sa 指令已註冊（$PROFILE），略過。"
} else {
  Add-Content $PROFILE "`r`n$marker`r`n$funcLine`r`n"
  Write-Host "✅ 已在 $PROFILE 註冊 sa 指令。"
}

Write-Host ""
Write-Host "重新載入 profile 讓 sa 生效：  . `$PROFILE"
Write-Host "接著："
Write-Host "  1) 用第一個帳號 /login，然後：sa capture"
Write-Host "  2) 用第二個帳號 /login，然後：sa capture"
Write-Host "  3) 之後 sa 選單切換、或 sa watch 在 CLI 撞牆自動輪替。"
