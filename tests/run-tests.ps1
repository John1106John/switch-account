<#
  零依賴測試 runner（不需 Pester）：驗證 switch-account 核心狀態機。
  全程用 $env:SA_CLAUDE_DIR 指向暫存目錄，不碰真實 ~/.claude。
  執行：powershell -File .\tests\run-tests.ps1
#>
$ErrorActionPreference = 'Stop'

# dot-source 主腳本 → 只定義函式、不執行分派
. (Join-Path $PSScriptRoot '..\scripts\switch-account.ps1')

$script:Pass = 0
$script:Fail = 0

function Assert-Equal($actual, $expected, $msg) {
  if ($actual -eq $expected) { $script:Pass++; Write-Host "  PASS  $msg" -ForegroundColor Green }
  else { $script:Fail++; Write-Host "  FAIL  $msg`n        期望 [$expected] 實得 [$actual]" -ForegroundColor Red }
}
function Assert-True($cond, $msg)  { Assert-Equal ([bool]$cond) $true  $msg }
function Assert-False($cond, $msg) { Assert-Equal ([bool]$cond) $false $msg }

# 測試輔助
function Set-ActiveCreds([string]$accessToken, [string]$refreshToken = 'r') {
  $obj = @{ claudeAiOauth = @{ accessToken = $accessToken; refreshToken = $refreshToken } }
  $obj | ConvertTo-Json -Depth 5 | Set-Content (Get-ActiveFile)
}
function Read-AT([string]$path) {
  (Get-Content $path -Raw | ConvertFrom-Json).claudeAiOauth.accessToken
}

# 每個測試在乾淨暫存目錄中執行
function Run-Case([string]$name, [scriptblock]$body) {
  $root = Join-Path ([IO.Path]::GetTempPath()) ("sa-test-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Force $root | Out-Null
  $env:SA_CLAUDE_DIR = $root
  Write-Host "• $name"
  try { Set-ActiveCreds 'sk-ant-AAA'; & $body }
  catch { $script:Fail++; Write-Host "  ERROR $($_.Exception.Message)" -ForegroundColor Red }
  finally {
    Remove-Item Env:\SA_CLAUDE_DIR -ErrorAction SilentlyContinue
    if (Test-Path $root) { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
  }
}

Run-Case 'capture 空倉庫 → 1.json 且 current=1' {
  Invoke-Capture | Out-Null
  Assert-True (Test-Path (Get-AccountFile 1)) '1.json 已建立'
  Assert-Equal (Get-Current) 1 'current=1'
  Assert-Equal (Read-AT (Get-AccountFile 1)) 'sk-ant-AAA' '1.json 內容 = 活檔'
}

Run-Case 'capture 第二次 → 遞增為 2 不覆蓋 1.json' {
  Invoke-Capture | Out-Null
  Set-ActiveCreds 'sk-ant-BBB'
  Invoke-Capture | Out-Null
  Assert-Equal (Get-Current) 2 'current=2'
  Assert-Equal (Read-AT (Get-AccountFile 1)) 'sk-ant-AAA' '1.json 未被覆蓋'
  Assert-Equal (Read-AT (Get-AccountFile 2)) 'sk-ant-BBB' '2.json = 新活檔'
}

Run-Case 'switch 到 N → 活檔=N.json 且 current=N' {
  Invoke-Capture | Out-Null
  Set-ActiveCreds 'sk-ant-BBB'
  Invoke-Capture | Out-Null
  Invoke-Switch 1 | Out-Null
  Assert-Equal (Read-AT (Get-ActiveFile)) 'sk-ant-AAA' '活檔換成 1.json'
  Assert-Equal (Get-Current) 1 'current=1'
}

Run-Case '雙向同步 → 切走前把刷新過的活檔存回原號' {
  Invoke-Capture | Out-Null                     # 1=AAA
  Set-ActiveCreds 'sk-ant-BBB'
  Invoke-Capture | Out-Null                     # 2=BBB
  Invoke-Switch 1 | Out-Null                    # current=1, 活檔=AAA
  Set-ActiveCreds 'sk-ant-AAA-refreshed'        # 模擬背景刷新
  Invoke-Switch 2 | Out-Null                    # 離場存檔應更新 1.json
  Assert-Equal (Read-AT (Get-AccountFile 1)) 'sk-ant-AAA-refreshed' '1.json 保住刷新後 token'
  Assert-Equal (Read-AT (Get-ActiveFile)) 'sk-ant-BBB' '活檔換成 2.json'
}

Run-Case '下一號 wrap around → 最大號繞回開頭' {
  Initialize-CredsDir
  1..3 | ForEach-Object { Set-ActiveCreds "sk-ant-$_"; Copy-Item (Get-ActiveFile) (Get-AccountFile $_) -Force }
  Assert-Equal (Get-NextNumber 3) 1 '3 的下一號 = 1'
  Assert-Equal (Get-NextNumber 1) 2 '1 的下一號 = 2'
}

Run-Case 'switch 不存在的號 → false 且活檔不變' {
  Invoke-Capture | Out-Null
  Assert-False (Invoke-Switch 9) 'Invoke-Switch 9 回傳 false'
  Assert-Equal (Read-AT (Get-ActiveFile)) 'sk-ant-AAA' '活檔不變'
}

Run-Case 'switch 來源非合法 credentials → 拒絕且活檔不變' {
  Invoke-Capture | Out-Null
  'not valid json' | Set-Content (Get-AccountFile 2)
  Assert-False (Invoke-Switch 2) 'Invoke-Switch 2 回傳 false'
  Assert-Equal (Read-AT (Get-ActiveFile)) 'sk-ant-AAA' '活檔不變'
}

Run-Case 'capture 帶名稱 → 記錄名稱' {
  Invoke-Capture '工作' | Out-Null
  Assert-Equal (Get-Name 1) '工作' '1 號名稱 = 工作'
}

Run-Case 'name 事後命名/改名' {
  Invoke-Capture | Out-Null                 # 1，無名稱
  Assert-Equal (Get-Name 1) '' '初始無名稱'
  Invoke-SetName @('1', '個人') | Out-Null
  Assert-Equal (Get-Name 1) '個人' '命名為個人'
  Invoke-SetName @('1', '工作', '機') | Out-Null   # 名稱含空格
  Assert-Equal (Get-Name 1) '工作 機' '改名含空格'
}

Run-Case 'name 不存在的號 → 不寫入' {
  Invoke-Capture | Out-Null
  Invoke-SetName @('9', 'X') | Out-Null
  Assert-Equal (Get-Name 9) '' '不存在的號不寫名稱'
}

Write-Host ""
Write-Host ("結果：{0} passed, {1} failed" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
exit $(if ($script:Fail) { 1 } else { 0 })
