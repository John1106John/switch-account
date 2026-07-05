<#
.SYNOPSIS
  switch-account — 在共用同一個 ~/.claude 的前提下，只換 .credentials.json 來切換 Claude 帳號。

.DESCRIPTION
  對話、設定、skill 全部共用同一個 ~/.claude；切換帳號只覆蓋 .credentials.json（身份/額度）。
  倉庫集中在 <root>/.account-creds/，數字檔名（1.json、2.json…），current 檔記錄當前 active 編號。
  切換一律「離場存檔 → 進場覆蓋」以維持不變式：.credentials.json 永遠等於 current 所指那號的最新內容。

.USAGE
  switch-account.ps1            # 選單：列出帳號，選一個切換
  switch-account.ps1 2          # 直接切到 2 號
  switch-account.ps1 capture    # 把當前 .credentials.json 登記成下一個空編號
  switch-account.ps1 list       # 列出倉庫與當前 active
  switch-account.ps1 watch ...  # 包裝 claude，撞 rate limit 時自動輪替下一個帳號（CLI 專用）

  可用 $env:SA_CLAUDE_DIR 覆寫根目錄（預設 ~/.claude），供測試指向暫存目錄。
#>

param(
  [Parameter(Position = 0)]
  [string]$Command,

  [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
  [string[]]$Rest
)

$ErrorActionPreference = 'Stop'

# ── 路徑 ────────────────────────────────────────────────────────────────────
function Get-Root {
  if ($env:SA_CLAUDE_DIR) { return $env:SA_CLAUDE_DIR }
  return (Join-Path $HOME '.claude')
}
function Get-CredsDir   { return (Join-Path (Get-Root) '.account-creds') }
function Get-ActiveFile { return (Join-Path (Get-Root) '.credentials.json') }
function Get-CurrentFile { return (Join-Path (Get-CredsDir) 'current') }
function Get-AccountFile([int]$n) { return (Join-Path (Get-CredsDir) "$n.json") }
function Get-NamesFile { return (Join-Path (Get-CredsDir) 'names.json') }

# ── 狀態讀寫 ────────────────────────────────────────────────────────────────
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

# 回傳倉庫中所有帳號編號（升冪）
function Get-AccountNumbers {
  $dir = Get-CredsDir
  if (-not (Test-Path $dir)) { return @() }
  $nums = @()
  foreach ($f in Get-ChildItem $dir -Filter '*.json' -File) {
    if ($f.BaseName -match '^\d+$') { $nums += [int]$f.BaseName }
  }
  return ($nums | Sort-Object)
}

# ── 名稱（編號 → 名稱對應）─────────────────────────────────────────────────
# 存於 names.json，以 UTF-8 讀寫確保中文名稱正確（避免 PS 5.1 ANSI 雷）。
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

# ── 驗證 ────────────────────────────────────────────────────────────────────
# 合法 credentials = 能 parse JSON 且含 claudeAiOauth.accessToken
function Test-CredentialsFile([string]$path) {
  if (-not (Test-Path $path)) { return $false }
  try {
    $j = Get-Content $path -Raw | ConvertFrom-Json
    return [bool]$j.claudeAiOauth.accessToken
  } catch { return $false }
}

# ── 核心狀態機 ──────────────────────────────────────────────────────────────
# 離場存檔：把現役活檔存回 current 所指的號（保留被 claude 背景刷新過的最新 token）
function Save-ActiveBack {
  $cur = Get-Current
  if ($null -eq $cur) { return }              # current 未知 → 跳過（不知道存回哪號）
  $active = Get-ActiveFile
  if (-not (Test-CredentialsFile $active)) { return }  # 活檔不合法 → 不覆蓋倉庫
  Initialize-CredsDir
  Copy-Item $active (Get-AccountFile $cur) -Force
}

# 進場覆蓋：把 N.json 覆蓋活檔，並更新 current
function Set-ActiveAccount([int]$n) {
  Copy-Item (Get-AccountFile $n) (Get-ActiveFile) -Force
  Set-Current $n
}

# 完整切換：離場存檔 → 進場覆蓋
function Invoke-Switch([int]$n, [switch]$Quiet) {
  $src = Get-AccountFile $n
  if (-not (Test-Path $src)) {
    $avail = (Get-AccountNumbers) -join ', '
    Write-Host "❌ 帳號 ($n) 不存在。可用編號：$(if ($avail) { $avail } else { '（倉庫是空的，先 capture）' })"
    return $false
  }
  if (-not (Test-CredentialsFile $src)) {
    Write-Host "❌ $n.json 不是合法 credentials，已中止（不覆蓋活檔）。"
    return $false
  }
  if ($null -eq (Get-Current)) {
    Write-Host "⚠ current 未知，跳過離場存檔——前一帳號若剛被刷新過的 token 可能遺失，必要時重登。"
  }
  Save-ActiveBack
  Set-ActiveAccount $n
  if (-not $Quiet) {
    Write-Host "✅ 已切到帳號 ($n)。"
    Write-Host "   VSCode 插件請 Reload Window（或重開對話）才生效；CLI 下次啟動即生效。"
  }
  return $true
}

# 登記：把當前活檔存成下一個空編號（max+1；空倉庫為 1）。可選帶名稱。
function Invoke-Capture([string]$name = '') {
  $active = Get-ActiveFile
  if (-not (Test-Path $active)) {
    Write-Host "❌ 目前沒有登入（找不到 $active）。先用某帳號 /login 再 capture。"
    return
  }
  if (-not (Test-CredentialsFile $active)) {
    Write-Host "❌ 當前 .credentials.json 不是合法 credentials，已中止。"
    return
  }
  $nums = Get-AccountNumbers
  $next = if ($nums.Count -gt 0) { ($nums | Measure-Object -Maximum).Maximum + 1 } else { 1 }
  Initialize-CredsDir
  Copy-Item $active (Get-AccountFile $next) -Force
  Set-Current $next
  if ($name) { Set-Name $next $name }
  $suffix = if ($name) { " 「$name」" } else { '' }
  Write-Host "✅ 已把當前帳號登記為 ($next)$suffix，並設為 current。"
}

# 事後命名/改名：sa name <編號> <名稱>
function Invoke-SetName([string[]]$rest) {
  if (-not $rest -or $rest.Count -lt 2) { Write-Host "用法：sa name <編號> <名稱>"; return }
  if ($rest[0] -notmatch '^\d+$') { Write-Host "編號需為數字。"; return }
  $n = [int]$rest[0]
  if (-not (Test-Path (Get-AccountFile $n))) { Write-Host "❌ 帳號 ($n) 不存在。"; return }
  $name = ($rest[1..($rest.Count - 1)] -join ' ')
  Set-Name $n $name
  Write-Host "✅ 帳號 ($n) 命名為「$name」。"
}

# 列出倉庫
function Invoke-List {
  $nums = Get-AccountNumbers
  if ($nums.Count -eq 0) { Write-Host "（倉庫是空的，先用 capture 登記帳號）"; return }
  $cur = Get-Current
  $names = Get-Names
  Write-Host "帳號倉庫（$(Get-CredsDir)）："
  foreach ($n in $nums) {
    $nm = if ($names.ContainsKey("$n")) { " " + $names["$n"] } else { '' }
    $mark = if ($n -eq $cur) { '  ← current' } else { '' }
    Write-Host ("  [{0}]{1}{2}" -f $n, $nm, $mark)
  }
}

# 選單：列出 → 讀輸入 → 切換
function Invoke-Menu {
  $nums = Get-AccountNumbers
  if ($nums.Count -eq 0) { Write-Host "（倉庫是空的，先用 capture 登記帳號）"; return }
  Invoke-List
  $ans = (Read-Host "要切到哪一號？（Enter 取消）").Trim()
  if (-not $ans) { return }
  if ($ans -notmatch '^\d+$') { Write-Host "請輸入數字編號。"; return }
  [void](Invoke-Switch ([int]$ans))
}

# 下一號（wrap around）：current 之後的下一個存在編號，繞回開頭
function Get-NextNumber([int]$cur) {
  $nums = Get-AccountNumbers
  if ($nums.Count -eq 0) { return $null }
  $after = $nums | Where-Object { $_ -gt $cur }
  if ($after) { return ($after | Select-Object -First 1) }
  return $nums[0]
}

# ── Usage 儀表板 ─────────────────────────────────────────────────────────────
# 用每個帳號自己的 OAuth token 查 Anthropic 的 usage/profile。
# 注意：這是 Claude Code 內部用的非公開端點，Anthropic 若變更可能失效。
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
  if (-not $iso) { return '—' }
  try { return ([datetimeoffset]$iso).LocalDateTime.ToString('MM/dd HH:mm') } catch { return $iso }
}

# sa status：列出所有帳號的即時 usage
function Invoke-Status {
  $nums = Get-AccountNumbers
  if ($nums.Count -eq 0) { Write-Host "（倉庫是空的，先用 capture 登記帳號）"; return }
  $cur = Get-Current
  $names = Get-Names
  foreach ($n in $nums) {
    $tok = Get-AccountToken $n
    $nm = if ($names.ContainsKey("$n")) { $names["$n"] } else { '(未命名)' }
    $tag = if ($n -eq $cur) { ' ← current' } else { '' }
    Write-Host ""
    Write-Host "[$n] $nm$tag" -ForegroundColor Cyan
    if (-not $tok) { Write-Host "    (無法讀取 token)"; continue }
    try {
      $u = Invoke-OAuthApi $tok '/api/oauth/usage'
      $sess = [int]$u.five_hour.utilization
      $week = [int]$u.seven_day.utilization
      $email = ''
      try { $email = (Invoke-OAuthApi $tok '/api/oauth/profile').account.email } catch {}
      if ($email) { Write-Host "    $email" }
      Write-Host ("    Session {0}%（重置 {1}）   Weekly {2}%（重置 {3}）" -f `
        $sess, (Format-ResetTime $u.five_hour.resets_at), $week, (Format-ResetTime $u.seven_day.resets_at))
    } catch {
      $code = $null; try { $code = $_.Exception.Response.StatusCode.value__ } catch {}
      Write-Host "    ⚠ 查詢失敗（HTTP $code）——token 可能過期，用該帳號重登後 sa capture 更新。"
    }
  }
  Write-Host ""
}

# ── 自動輪替（CLI 專用）──────────────────────────────────────────────────────
$RateLimitPattern = 'rate.?limit|too many requests|429|usage.?limit|plan limit|over_capacity'

# 從 <root>/projects 下最近修改的 session jsonl 尾端偵測 rate limit
function Test-RateLimited {
  $projects = Join-Path (Get-Root) 'projects'
  if (-not (Test-Path $projects)) { return $false }
  $latest = Get-ChildItem $projects -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $latest) { return $false }
  $tail = Get-Content $latest.FullName -Tail 30 -ErrorAction SilentlyContinue
  return [bool]($tail -match $RateLimitPattern)
}

# 從所有帳號（排除 exclude）挑「最有額度」的：session/weekly 皆未達上限者中 session 用量最低。
# 回傳 @{ Best = 編號或 $null; AnyQueried = 是否至少成功查到一個帳號 }。
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
      if ($s -ge 100 -or $w -ge 100) { continue }   # 已爆，跳過
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
    if (-not $first) { $runArgs = @('--continue') + $runArgs }  # 切帳號後接續同一場對話

    & claude @runArgs
    $code = $LASTEXITCODE
    $first = $false

    if ($code -eq 0) { exit 0 }
    # PowerShell 沒有標準 130；Ctrl-C 通常讓子程序自行結束，這裡只對 rate limit 動作
    if (-not (Test-RateLimited)) { exit $code }

    $cur = Get-Current
    if ($null -eq $cur) { Write-Host "⚡ 撞到 rate limit，但 current 未知，無法自動輪替。用 list/switch 手動處理。"; exit $code }
    $tried[$cur] = $true

    # 優先挑「最有額度」的帳號；usage API 全查不到時退回順序輪替。
    $sel = Get-BestAccount $cur
    if ($sel.Best) {
      $next = $sel.Best
    } elseif ($sel.AnyQueried) {
      Write-Host ""
      Write-Host "⚡ 所有帳號額度都爆了，休息一下吧。"
      exit $code
    } else {
      $next = Get-NextNumber $cur
      if ($null -eq $next -or $tried.ContainsKey($next)) {
        Write-Host ""
        Write-Host "⚡ 找不到可用帳號（usage 查詢失敗且已輪過一圈）。"
        exit $code
      }
    }
    Write-Host ""
    Write-Host "⚡ 帳號 ($cur) 撞到 rate limit → 自動切到最有額度的 ($next) 接續…"
    if (-not (Invoke-Switch $next -Quiet)) { exit $code }
  }
}

# ── 分派 ────────────────────────────────────────────────────────────────────
# 被 dot-source（. switch-account.ps1）時 InvocationName 為 '.'，此時只定義函式供測試，不執行分派。
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
      Write-Host "未知指令：$Command"
      Write-Host "用法：switch-account [<編號> | capture [名稱] | name <編號> <名稱> | list | status | watch ...]（無參數=選單）"
    }
  }
}
