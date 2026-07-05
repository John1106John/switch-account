---
name: switch-account
description: 在共用同一個 ~/.claude（對話、設定、skill 全共用）的前提下，只覆蓋 .credentials.json 來循序切換多個 Claude 帳號。撞到 rate limit 時自動切到「最有額度」的帳號、同一場對話用 --continue 接續；可用 sa status 查所有帳號的即時 usage。Windows PowerShell 專用。觸發詞：switch-account、sa、切換帳號、換帳號、帳號輪替、額度爆了切帳號、credentials 切換、多帳號 credentials、claude 換帳號繼續、usage 儀表板。
---

# switch-account

只換 `~/.claude/.credentials.json` 來切換 Claude 帳號；對話、設定、skill 因共用同一個 `~/.claude` 而天生延續。適合「一個帳號額度爆了，換下一個帳號繼續同一場對話」的**循序**切換（非同時雙開）。

## 核心不變式

`~/.claude/.credentials.json` 永遠等於 `current` 所指那號的最新內容。切換一律「**離場存檔 → 進場覆蓋**」：先把現役活檔存回原號（保住被 claude 背景刷新過的 token，避免倉庫過期），再覆蓋成目標帳號。

倉庫：`~/.claude/.account-creds/`，數字檔名 `1.json`、`2.json`…，外加 `current` 記錄當前 active 編號。

## 安裝

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install.ps1   # 在 $PROFILE 註冊 sa 指令
. $PROFILE                                                      # 重新載入
```

## 登記帳號（首次）

因為所有帳號共用 `~/.claude`，用某帳號 `/login` 會把它的 token 寫進 `.credentials.json`，再 `capture` 收進倉庫：

```powershell
# 用第一個 email /login 後：
sa capture 工作    # → 1.json，並命名「工作」（名稱可省略）
# 用第二個 email /login 後：
sa capture 個人    # → 2.json
```

## 用法

```powershell
sa                # 選單：列出帳號（含名稱），選一個切換
sa 2              # 直接切到 2 號
sa list           # 列出倉庫、名稱與當前 active
sa status         # 儀表板：查所有帳號的即時 usage（session% / weekly% / 重置時間 / email）
sa capture [名稱] # 把當前 .credentials.json 登記成下一個空編號，可選命名
sa name 1 工作    # 事後為某編號命名/改名
sa watch [args]   # CLI 專用：包裝 claude，撞 rate limit 自動切「最有額度」的帳號並 --continue 接續
```

名稱存於 `~/.claude/.account-creds/names.json`（UTF-8）。`list` 與選單會顯示 `[1] 工作` 這種標籤，方便辨認哪個帳號。

切換後 **VSCode 插件需 Reload Window**（或重開對話）才生效；CLI 下次啟動即生效。只有 `sa watch` 在 CLI 能做到零操作無縫輪替。

## 重要限制

- **循序切換，非同時雙開**：`.credentials.json` 是全機共用的單一檔，切換會讓**所有正在跑的 claude 對話**下次刷新一起變成新帳號。要並行多帳號請改用獨立 `CLAUDE_CONFIG_DIR`（見 ccc）。
- **`sa watch` 為 CLI 專用**：VSCode 插件不是被腳本包裝啟動的，攔不到退出，無法自動輪替。
- 額度監控：`sa status` 可隨時查所有帳號的即時 usage（透過 Claude Code 內部的 OAuth 端點 `/api/oauth/usage`，非公開，Anthropic 若變更可能失效）。`sa watch` 的自動輪替仍是「撞牆退出後」才切，非事前預防。

## 測試

```powershell
powershell -File tests/run-tests.ps1   # 零依賴，全程用暫存目錄，不碰真實帳號
```

## 注意

`scripts/*.ps1` 以 UTF-8 with BOM 儲存，Windows PowerShell 5.1 才能正確解析中文/符號。編輯後若中文變亂碼導致解析錯誤，重新以 BOM 儲存即可。
