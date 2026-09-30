# NOTE

## 進行中：分批 merge upstream 到 fork main（2026-09-22 起）

- 目標：`main`（fork，含 MyCoder provider + 相關修正）合併 upstream `steipete/CodexBar`，採用
  **merge**（非 rebase），逐個 minor release tag 當錨點分批合併：
  `v0.56.0 → v0.57.0 → v0.58.0 → v0.59.0 → v0.60.0 → v0.61.0 → v0.62.0 → v0.63.0 → v0.64.1`。
- **已完成並 push 到 origin**（2026-09-23）：
  - `v0.56.0` merge commit `8046b24ec`。衝突：`KeychainAccessGate.swift`、
    `StatusItemController+CountdownRefresh.swift`，採用 upstream 邏輯。
    - 驗證：單獨跑 `StatusMenuTests`（176 個測試，81.982s 全過）、`ClaudeCLISessionTests`
      （7 個測試全過）。先前全量 `swift test` 中途看到的失敗是既有 flaky/timing 問題，非合併
      造成的 regression（誤以為卡死，其實只是套件本身跑很久）。
  - `v0.57.0` merge commit `337b5fce5`。衝突：
    - `Tests/CodexBarTests/OpenAISubscriptionMetadataTests.swift`：upstream 重寫了 WebKit fixture
      機制（`fetchFixtureHTML`/`Task.sleep` 輪詢 → `withProductionWebView`/`window.fixtureRequests[]`
      陣列式 mock）。HEAD 舊測試的等價邏輯已被 upstream 新測試涵蓋，故整個捨棄舊函式。
    - `Sources/CodexBar/StatusItemController+SwitcherViews.swift`：`buildButtons` 函式簽名衝突
      （HEAD 的 `useTwoRows: Bool` vs upstream 的 `columns: Int`），採用 upstream 版本（第一次合併
      時漏改，遺留 `<<<<<<< HEAD` 標記讓後續 `swift build` 直接編譯失敗，第二輪才補上並 amend
      進同一個 merge commit）。
    - 驗證：`OpenAISubscriptionMetadataTests`（7/7 全過）、`StatusMenuCodexSwitcherTests`（22/22
      全過），`swift build` 乾淨。
  - `git push origin main`：`cf40813be..337b5fce5`。
- **已完成並 push 到 origin**（2026-09-29）：
  - `v0.58.0` merge commit `65d4f3cc2`。無衝突。`swift build` 乾淨（487.76s），焦點測試
    155 個全過（`MenuBarPercentWindowPreferenceTests`、`MenuBarResetWindowRendererTests`、
    `ProviderUsageItemVisibilityTests`、`StatusMenuTests` 等 v0.58.0 新增區域）。
  - `v0.59.0` merge commit `369dd8bc0`。衝突：`StatusItemController+PersistentMenuActions.swift`
    的 `isMergedOverviewSelected`——HEAD 直接呼叫 `resolvedMergedOverviewProviders`，upstream
    改用 `includesOverviewTab(enabledProviders:)` 封裝（內部同樣呼叫
    `resolvedMergedOverviewProviders`，語意等價），採用 upstream 版本。
    `swift build` 乾淨（245.19s），焦點測試 209 個全過。
  - `v0.60.0` merge commit `5aa5e6286`。無衝突。`swift build` 乾淨（458.50s）。
    - 測試發現 10 個失敗，重跑確認**全是 flaky 非 regression**：DeepSeek 5 個時間斷言測試
      （上限 0.2s~1s，實際 0.99~2.05s，每次數值不同，Intel iMac 負載造成）+
      `OpenAIDashboardSessionAuthorizationTests` 的 webview 環境偶發（重跑即過）。
      這些測試檔與 DeepSeek source 在 v0.59.0..v0.60.0 完全沒被修改。
  - `v0.61.0` merge commit `86b9ba3c6`。**23 個衝突檔案**（merge 輸出被 `tail -15` 截斷，
    第一次誤判只有 3 個、把帶標記的檔案 commit 進去，已 `git reset --hard` 重做）。
    衝突根源：fork 全域 swiftformat commit `6824aa292` 撞上 upstream 的功能重構
    （`SettingsValue.cleaned` 共用化、`TestProcessSafety` 抽取、private helper 移除、
    `ProviderSettingsFieldDescriptor` 移除 `onActivate`/`stringBinding`）。
    解法：21 檔 `git checkout --theirs`，`ProviderImplementationManifest.swift` 與
    `docs/provider-ids.md` 採 upstream 後手動補回 MyCoder；
    `MyCoderProviderImplementation.swift` 修正新 API（`context.binding`、移除 `onActivate`）。
    - 驗證：`swift build` 乾淨；焦點測試中 Kimi 時間斷言與 OpenCodeGo zenBalance 為 flaky
      （重跑即過）；`AlibabaTokenPlanProviderTests` 的 Cookie/`X-Anonymous-Id` 斷言穩定失敗，
      但 HEAD 與 `v0.61.0` 在該測試與 source 的 diff 為 0——**upstream 既有問題**
      （e1d208b02 "preserve Alibaba and Qwen form values" 改完後測試仍失敗），非 merge 造成。
  - `git push origin main`：`5aa5e6286..86b9ba3c6`。
- **下一步**：繼續 `v0.62.0 → v0.63.0 → v0.64.1`。
  - 提醒：每次 merge 後務必用 `grep -rl '^<<<<<<<' --include='*.swift' Sources Tests` 全域確認
    沒有殘留衝突標記，再進 build，避免像 `v0.57.0` 那次漏掉一個檔案。
    **merge 輸出不要用 `tail` 截斷**——v0.61.0 那次因此漏看 20 個衝突檔案。
  - 提醒：DeepSeek 時間斷言測試、Kimi 時間斷言、`OpenAIDashboardSessionAuthorizationTests`、
    `OpenCodeGoUsageFetcherCLIWaitTests` 在本機是已知 flaky，失敗時先重跑單獨 filter 確認，
    不要直接當 regression。

## 已修：OpenCodeGoUsageFetcherCLIWaitTests.swift 的 data race warning（2026-09-22）

`Tests/CodexBarTests/OpenCodeGoUsageFetcherCLIWaitTests.swift` 的 `deliver` closure改用
`@Sendable` + 既有的 `LockIsolated` box 裝 `self`（`URLProtocol` 本身非 `Sendable`），
`swift build --build-tests` 確認 warning 消失，`OpenCodeGoUsageFetcherCLIWaitTests` 4/4 測試通過。

## 2026-09-16：Xcode 26.3 toolchain 已可用，Swiftly 已退役

- Xcode 26.3（Build 17C529）自帶 Swift 6.2.4，`swift build` / `swift test` / 打包執行都正常，
  之前「Swiftly 6.3.3 編譯成功但執行檔 dyld crash」的問題隨 Xcode 升級一併解決。
- Swiftly 已移除：`~/.bashrc.d/swiftly.sh` 已刪（trash），repo 的 `.swift-version` 已刪，
  `~/.swiftly/` 與 brew 的 swiftly 本體還在但不再注入 PATH（要徹底清：`brew uninstall swiftly` + `trash ~/.swiftly`）。
- `Scripts/compile_and_run.sh` 的 `ensure_swift_version` 已加 fallback：PATH swift 解析失敗時
  自動切到 Xcode toolchain（`xcrun --find swift`），兩邊都失敗才退出。

## 本機（Intel x86_64）跑測試的已知差異

- 2026-09-16 已修：`TestTimingBudget.slowdownFactor` 加入 `arch(x86_64)` 2x factor，
  所有 wall-clock budget 統一放大，`CostUsagePerformanceGateTests` 本機 30/30 全過。
  CPU 時間 gate 維持嚴格（那才是抓 O(files) regression 的關鍵指標）。

## swiftlint --strict 的 4 個既有 violations（與本次改動無關）

- `CodexCLISession.swift:102` function_body_length（152 > 150）
- `AntigravityStatusProbe.swift` file_length（1506 > 1500）
- `MiniMaxUsageFetcher.swift` file_length（1520 > 1500）
- `FactoryStatusProbe.swift:594` type_body_length（804 > 800）
- 推測是 swiftlint 版本更新後規則收緊，之後找時間拆檔或調整。

## MenuSwitchFlickerProbe 的 CGWindowListCreateImage deprecation

`Sources/CodexBar/MenuSwitchFlickerProbe.swift:144` 用了 macOS 14 已 deprecated 的
`CGWindowListCreateImage`（3ms 循環抓 frame 的 flicker probe）。官方建議改 ScreenCaptureKit，
但那是非同步 API + 需要錄影權限，遷移是大工程，暫不處理。

## PATH 上 pyenv 的 xattr shim 劫持系統 xattr

本機 `which xattr` 解析到 `~/.pyenv/shims/xattr`（Python 套件版），不支援 `-r`（遞迴）選項。
`Scripts/package_app.sh` 的 `verify_no_quarantine_attribute` 原本呼叫裸 `xattr -r -p ...`，
在此環境下必定印出 usage 說明文字而被誤判為「still quarantined」，導致 `make release` 每次必炸。
已修正為明確呼叫 `/usr/bin/xattr`（僅此一處）。

可能影響：其他依賴系統 `xattr`/其他常見 CLI 工具（未來若又踩到類似問題）的腳本，
建議日後新腳本統一用絕對路徑或先 `command -v` 確認解析到系統版本，避免 PATH 污染。

## Keychain 每次重建後都要求存取權限

重新編譯 CodexBar.app 後，Keychain ACL 不認新 binary 簽名，導致：
- 讀取 Chrome Safe Storage（cookie 解密）時跳提示
- 讀取 CookieHeaderCache keychain items 時跳提示

允許一次後應該會記住。如果每次 refresh 都反覆要求，需排查：
1. `CookieHeaderCache.store()` 是否成功寫入（keychain write 可能因 ACL 失敗）
2. `KeychainCacheStore.trustedApplicationPathsForCacheAccess()` 是否涵蓋新 binary 路徑
3. Ad-hoc signing vs Developer ID signing 的 keychain 行為差異

## Build 工具鏈

- 編譯與打包 CodexBar 時要使用 Swiftly 提供的 `swift`
- 載入：`source ~/.bashrc.d/swiftly.sh`
- 預期路徑：`/Users/louis/.swiftly/bin/swift`
- 原因：系統或其他 `swift` 版本可能無法解析目前相依套件的 `swift-tools-version`
  （2026-08-20 merge upstream 後確認：SweetCookieKit 0.5.2 要求 swift-tools-version 6.2，
  系統 Xcode 內建的 swift 只到 6.1.2，用 Swiftly 的 6.3.3 才能 resolve/build 成功）

## `swift test` / 打包後的執行檔在此環境下都無法「執行」（不只是 swift test）

`swift build`（含 `-c release`）用 Swiftly 的 swift 6.3.3 可以完整建置與連結成功，
但**任何**用這顆編譯器產出的執行檔，在這台機器上實際執行都會 crash：

```
dyld[...]: Symbol not found: _$sScf25isIsolatingCurrentContextSbSgyFTq
Referenced from: <...>/CodexBarCLI (或 CodexBarPackageTests.xctest、CodexBar.app 內的 Helpers 等)
Expected in:     /usr/lib/swift/libswift_Concurrency.dylib
```

已確認範圍：
- `swift test`（呼叫系統 Xcode 的 `swiftpm-xctest-helper`）失敗
- 直接執行 `.build/release/CodexBarCLI` 也失敗（跟 xctest 無關，純粹是 dyld 找不到 symbol）
- `Scripts/package_app.sh` 打包出的 `CodexBar.app` 在 `verify_packaged_app_launch.sh`
  的 launch smoke check 階段，用同一個 `CodexBarCLI` 也是同樣 crash 而讓打包失敗

目前判斷最可能的根本原因：編譯用的 SDK 是 `MacOSX15.5.sdk`（隨 Swiftly 6.3.3 toolchain
附帶），但這台機器目前跑的是 **macOS 15.4**（`sw_vers` 確認）。`isIsolatingCurrentContext`
這個 concurrency runtime symbol很可能是隨 macOS 15.5 點更新才進到系統的
`libswift_Concurrency.dylib`，而不是 6.1.2/6.3.3 編譯器本身的差異。

**下次要驗證 build 出的執行檔能不能跑，請先確認/更新 macOS 到 15.5 以上再重試**
（`softwareupdate --list` 或系統設定裡的軟體更新）。如果更新 macOS 後 dyld symbol
仍找不到，才需要考慮改用其他 Swift 版本或改變連結方式（例如檢查
`MACOSX_DEPLOYMENT_TARGET` / SDK 版本是否一致）。

2026-08-20：這次 merge upstream 之後嘗試 `./Scripts/package_app.sh`，
建置、連結、程式碼簽章都成功（`CodexBar.app: valid on disk` /
`satisfies its Designated Requirement`），只有最後一步 launch smoke check 因為上述
dyld 版本問題而失敗，導致腳本回傳非 0。也就是說 merge 本身沒有問題，
純粹卡在這台機器的 OS / Swift runtime 版本沒對齊。

## WidgetExtension.xcodeproj 需要手動補上 CQuickJS 的連結設定

Upstream 在 Package.swift 新增了 `CQuickJS`（QuickJS JS 引擎，給新的 provider plugin
系統用）並讓 `CodexBarCore` 依賴它，但 `WidgetExtension/CodexBarWidgetExtension.xcodeproj`
的 Debug/Release build settings 一直沒有同步更新，導致用 Xcode 建置
`CodexBarWidgetExtension` target 時報錯：

```
error: missing required module 'CQuickJS'
```

已在 2026-08-20 merge upstream 時於 `project.pbxproj` 補上（Debug 和 Release 都要改）：
- `OTHER_LDFLAGS` 追加 `-lCQuickJS`
- `SWIFT_INCLUDE_PATHS` 追加 `$(CODEXBAR_BUILD_DIR)/<config>/CQuickJS.build`
  （CQuickJS 的 `module.modulemap` 產生在這裡，不在 `.../Modules` 底下）

之後如果 upstream 又新增其他 C target 依賴（同樣模式：`.target(name: "C...", ...)`
且 `CodexBarCore` 依賴它、且不是 Linux-only），要記得同步檢查這個 xcodeproj 有沒有補齊
`-l<TargetName>` 跟對應的 `<TargetName>.build` module map 路徑。

## 2026-09-18：MyCoder SSL 錯誤排查（未完，下週續）

**症狀**：選單顯示「MyCoder network error: 發生SSL錯誤，無法建立與伺服器的安全連線。」

**已確認的事實**：
- `afs-mycoder-api.asus.com` / `afs-mycoder.asus.com` 用華碩內部 CA（`ASUSTEK 2016 Service CA1` ← `ASUSTEK 2016 Root CA`），不是公開 CA，所以系統預設驗證必失敗（curl 顯示 self signed certificate in certificate chain）。
- App log（`log show`）顯示每 5 分鐘 refresh 固定失敗 `URLError -1200`（底層 `-9802`），且 auth challenge 處置是 `disp=1`（performDefaultHandling）——**失敗的請求沒走到 trust bypass delegate**；同時又有 119 次 TLS 連線成功，代表失敗的可能走別條路徑（尚未確認是哪條）。
- 獨立 Swift 腳本重現同樣 bypass 邏輯 → TLS 握手成功（HTTP 400 = 伺服器有回應，dummy token 被拒是正常的）。
- **PEM 陷阱**：`/etc/ssl/certs/mycoder-prod-rootCA.crt` 是 PEM 格式，`SecCertificateCreateWithData` 只吃 DER → raw parse FAIL，需先 PEM→DER 轉換（已實作並驗證 OK）。

**已 commit（cf40813be）**：`MyCoderUsageFetcher.swift` 的 TLS 處理改為三層策略：
1. 讀 `/etc/ssl/certs/mycoder-prod-rootCA.crt`（PEM→DER 支援）
2. 讀環境變數 `NODE_EXTRA_CA_CERTS`
3. 都沒有 → 無條件 trust（僅限這兩個 host）
找到 CA 時用 `SecTrustSetAnchorCertificatesOnly(trust, true)` 只信任該 CA。另加 TLS challenge 診斷 log。

**下週待辦**：
1. `./Scripts/package_app.sh` 重新打包 + 重啟 app，看選單是否正常顯示 quota（~$12.69/$100.00）。
2. 若仍失敗：用新加的 log（`MyCoder TLS challenge:` / `MyCoder trusting transport request host:`）確認失敗請求到底有沒有經過 trusting transport——之前 disp=1 的現象還沒解釋。
3. MyCoder E2E 驗證仍卡 Keychain 6 小時 cooldown（cookie refresh 需要 Chrome Safe Storage 授權）。
4. NOTE.md 先前未 commit 的更新（Xcode toolchain / Intel timing）也還沒 commit。

## 2026-09-21：MyCoder SSL 排查續——disp=1 之謎已解，卡在 QUIC 路徑（未完）

**今天完成的驗證**：
1. `package_app.sh` 重新打包成功（build 1120s），app 重啟正常（PID 45727）。
2. Keychain cooldown 已過：`cookie refresh --allow-keychain-prompt` 拿到 Chrome Safe Storage 授權，
   cookie 有 staged（`Cookie cache refresh staged`），Chrome 裡確實有
   `afs-mycoder.asus.com | PUBLIC_USER_SSO_TOKEN`（到期 2026-09-24）。
3. **host 沒錯**：用整合瀏覽器登入 afs-mycoder.asus.com 後攔截網路請求，網頁版就是打
   `https://afs-mycoder-api.asus.com/mycoder-quota/api/v1/user/{userId}/quota`（Bearer token），
   與 CodexBar 實作一致。`portalConfig.json` 的 `QUOTA_SVC_API_URL` 也是 asus.com
   （bundle 裡的 twcc.ai 只是 fallback 預設值，不是實際使用的 host）。
   userId 來源：`/iam/api/v1/user`（JWT aud claim，CodexBar 已實作）。
4. **disp=1 之謎解開一半**：CLI 的 `log stream` 抓到完整序列——
   `asked to evaluate TLS Trust` → `[TLSCBQ] Need to invoke to satisfy trust callback` →
   `auth completion disp=1 cred=0x0` → `-9807` → `-1202`。
   也就是 delegate 有被叫到，但 CFNetwork 在 **QUIC（HTTP/3）路徑**上自己以
   performDefaultHandling 回掉，pinned-CA 邏輯根本沒機會執行。
   CLI log 明確顯示 `quic-connection`；獨立 repro 腳本（TCP+TLS、h2）則正常走 delegate。
5. 獨立變體矩陣（extension 內 delegate / inline delegate / Origin+Referer headers）全部通過，
   排除這些變因。

**已改（未 commit）**：`MyCoderUsageFetcher.swift` 的 `MyCoderTrustingTransport.init()` 加了
`CFPreferencesSetValue("CFNetworkHTTP3Override", false, ...)` 停用 HTTP/3。
（`assumesHTTP3Capable` 在此 SDK 不存在，已試過會 compile error。）
**但驗證結果：CFNetwork 還是走 quic-connection**（stream3 log：`found no value for key
CFNetworkHTTP3Override`——runtime 寫的 preference 沒被讀到，可能要在 process 啟動前就存在，
或 key/domain 不對）。仍 disp=1、仍 -9807。

**下次待辦**：
1. 停用 QUIC 的正確做法待查：試 `URLSessionConfiguration` 的
   `connectionProxyDictionary`？或 `CFNetworkHTTP3Override` 寫進
   `~/Library/Preferences/.GlobalPreferences.plist` 後再啟動？或改用
   `URLSessionConfiguration.ephemeral` + `URLProtocol`？也可以考慮
   `nw_listener`/Network.framework 直接實作，或乾脆改用 curl 子行程。
2. 另一個更乾淨的方向：**把 ASUS root CA 裝進系統 Keychain 並標記信任**
   （`security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain
   /etc/ssl/certs/mycoder-prod-rootCA.crt`），這樣連 QUIC 路徑的 default trust
   evaluation 都會過，完全不需要 delegate bypass。需要 admin 權限 + 用戶同意。
3. 驗證工具都在 /tmp：`tls_repro.swift`（基本重現）、`tls_variants.swift`（變體矩陣）、
   `cli_stream*.log`（CLI log stream）。CLI build：`swift build -c release --product CodexBarCLI`。
4. Chrome Safe Storage 授權今天已給過（新 CLI binary 也授權了），cookie cache 應該可用。
5. 未 commit 的變更：`MyCoderUsageFetcher.swift`（CFPreferences 停 QUIC，無效待改）+
   sendRequest 的 401/403 與 network error 診斷 log（這部分有效，保留）。
