# NOTE

## 進行中：分批 merge upstream 到 fork main

上游持續有新 tag，fork 需定期分批 merge（非 rebase，逐 tag 當錨點）。上次已完成
`v0.56.0 → v0.64.1`（2026-09-29 push 到 origin/main），fork 與 upstream 同步至 v0.64.1，
MyCoder provider 保留完好（manifest + provider-ids.md + MyCoder 目錄）。

**下次 merge 的教訓**：
- merge 後務必 `grep -rl '^<<<<<<<' --include='*.swift' Sources Tests` 全域確認無殘留標記再 build。
- **merge 輸出不要用 `tail` 截斷**——v0.61.0 那次因此漏看 20 個衝突檔案。
- 衝突常見模式：fork 全域 swiftformat 格式 vs upstream 功能變更 → 採 upstream 後手動補回 MyCoder（manifest、provider-ids.md）。
- upstream 新增 C target 依賴時，記得同步 `WidgetExtension/CodexBarWidgetExtension.xcodeproj`（`OTHER_LDFLAGS` 加 `-l<Target>`、`SWIFT_INCLUDE_PATHS` 加 `<Target>.build` module map 路徑；CQuickJS 已於 2026-08-20 補過）。
- 本機已知 flaky 測試失敗先單獨 filter 重跑，不要直接當 regression（見下方備忘）。

## 已解決：MyCoder SSL / QUIC 排查（2026-09-21 ~ 10-06）

**症狀**：選單顯示「MyCoder network error: 發生SSL錯誤」。

**根因**：`afs-mycoder-api.asus.com` / `afs-mycoder.asus.com` 用華碩內部 CA（`ASUSTEK 2016 Service CA1` ← `ASUSTEK 2016 Root CA`），非公開 CA，系統預設驗證必失敗。CFNetwork 在 QUIC（HTTP/3）路徑上自己以 performDefaultHandling 回掉（disp=1），pinned-CA delegate 邏輯沒機會執行。

**解法（commit cf40813be）**：`MyCoderUsageFetcher.swift` 三層 TLS 策略：
1. 讀 `/etc/ssl/certs/mycoder-prod-rootCA.crt`（PEM→DER；`SecCertificateCreateWithData` 只吃 DER）
2. 讀環境變數 `NODE_EXTRA_CA_CERTS`
3. 都沒有 → 無條件 trust（僅限這兩個 host）
找到 CA 時 `SecTrustSetAnchorCertificatesOnly(trust, true)` 只信任該 CA。

**結果**：app 內 MyCoder 顯示正常（quota API 呼叫成功）。

## 已解決：Keychain 每次重建後都要求存取權限（2026-10-06）

**根因**：ad-hoc 簽章每次重建都變（機器上無 codesigning 身分），Keychain ACL 不認新 binary；加上 Codex 的瀏覽器掃描順序包含所有 Chromium 變體，每個都會先讀 Safe Storage（→ 提示）才查 cookie DB，即使沒有相關 cookie 也跳提示。

**解法**：Codex 的 `browserCookieOrder` 限縮為 Chrome → Edge → Safari → Firefox（commit `83695bcd3`），提示次數大幅減少；app 內 MyCoder cookie 流程已可正常運作。

**已知限制**：CLI（`codexbar usage --provider mycoder`）在背景上下文執行、從不提示，ad-hoc ACL 失效時仍會失敗；要徹底解決需 Developer ID 憑證。

## 已完成：分批 merge upstream 到 fork main（2026-09-22 ~ 09-29）

`v0.56.0 → v0.57.0 → v0.58.0 → v0.59.0 → v0.60.0 → v0.61.0 → v0.62.0 → v0.63.0 → v0.64.1`
已全部 merge（非 rebase，逐 tag 分批）並 push 到 origin/main。fork 與 upstream 同步，
MyCoder provider 保留完好（manifest + provider-ids.md + MyCoder 目錄）。

各輪摘要（merge commit）：
- `v0.56.0`（`8046b24ec`）：衝突 `KeychainAccessGate.swift`、`StatusItemController+CountdownRefresh.swift`，採 upstream。
- `v0.57.0`（`337b5fce5`）：`OpenAISubscriptionMetadataTests` upstream 重寫 WebKit fixture 機制，捨棄舊測試；`buildButtons` 簽名衝突採 upstream（曾漏改遺留 `<<<<<<< HEAD`，第二輪 amend）。
- `v0.58.0`（`65d4f3cc2`）：無衝突。
- `v0.59.0`（`369dd8bc0`）：`isMergedOverviewSelected` 改用 upstream 的 `includesOverviewTab(enabledProviders:)` 封裝。
- `v0.60.0`（`5aa5e6286`）：無衝突。
- `v0.61.0`（`86b9ba3c6`）：**23 個衝突**（fork 全域 swiftformat `6824aa292` 撞 upstream 重構）。21 檔 `--theirs`；manifest 與 provider-ids.md 採 upstream 後補回 MyCoder；`MyCoderProviderImplementation.swift` 修新 API（`context.binding`、移除 `onActivate`）。
- `v0.62.0`（`676690967`）：`HookEvent.swift` 採 upstream。`TestsLinux/CostUsageQuotaWeekLinuxTests.swift` 在 Intel 型別檢查逾時，拆開 `#expect` 修復（commit `446284198`）。
- `v0.63.0`（`2d9c43d7a`）：6 個衝突全為 swiftformat 格式 vs upstream 功能變更，5 檔採 upstream，provider-ids.md 補回 `mycoder`。
- `v0.64.1`（`2043fed99`）：`LLMProxy`/`NeuralWatt` 改 bundled plugin，接受刪除；`KimiCookieHeader.swift` 採 upstream；provider-ids.md 補回 `mycoder`。

**下次 merge 的教訓**：
- merge 後務必 `grep -rl '^<<<<<<<' --include='*.swift' Sources Tests` 全域確認無殘留標記再 build。
- **merge 輸出不要用 `tail` 截斷**——v0.61.0 那次因此漏看 20 個衝突檔案。
- upstream 新增 C target 依賴時，記得同步 `WidgetExtension/CodexBarWidgetExtension.xcodeproj`（`OTHER_LDFLAGS` 加 `-l<Target>`、`SWIFT_INCLUDE_PATHS` 加 `<Target>.build` module map 路徑；CQuickJS 已於 2026-08-20 補過）。

## 本機環境備忘（Intel x86_64）

- **已知 flaky 測試**（失敗先單獨 filter 重跑，不要直接當 regression）：DeepSeek 時間斷言、Kimi 時間斷言、`OpenAIDashboardSessionAuthorizationTests`（webview 偶發）、`OpenCodeGoUsageFetcherCLIWaitTests`、`SpendDashboardSourceConcurrencyTests`（並行負載時 timedOut）。`AlibabaTokenPlanProviderTests` 的 Cookie/`X-Anonymous-Id` 斷言穩定失敗是 **upstream 既有問題**（e1d208b02），非 fork 造成。
- **swiftlint --strict 既有 violations**（與改動無關）：`CodexCLISession.swift:102` function_body_length、`AntigravityStatusProbe.swift` file_length、`MiniMaxUsageFetcher.swift` file_length、`FactoryStatusProbe.swift:594` type_body_length。之後找時間拆檔。
- **timing budget**：`TestTimingBudget.slowdownFactor` 已加 `arch(x86_64)` 2x factor，wall-clock budget 統一放大；CPU 時間 gate 維持嚴格。
- **pyenv xattr shim**：`which xattr` 解析到 `~/.pyenv/shims/xattr`（不支援 `-r`），會讓 `package_app.sh` 的 quarantine 檢查誤判。已改用 `/usr/bin/xattr`。日後新腳本統一用絕對路徑或先 `command -v` 確認。
- **toolchain**：Xcode 26.3（Swift 6.2.4）已可用，Swiftly 已退役（`.swift-version` 已刪；`compile_and_run.sh` 有 fallback 自動切 Xcode toolchain）。先前「Swiftly 6.3.3 編譯成功但執行檔 dyld crash」隨 Xcode 升級一併解決。
- **MenuSwitchFlickerProbe**：`CGWindowListCreateImage` 已 deprecated（macOS 14），官方建議 ScreenCaptureKit 但需錄影權限 + 非同步遷移，暫不處理。
