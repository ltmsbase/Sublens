# 上 TestFlight 完整流程

TestFlight 分成两种测试员，流程不一样：

- **内部测试员**（Internal）：最多 100 人，必须是你 App Store Connect 团队的成员，**不需要 Beta 审核**，构建传上去十几分钟就能装。给同事/自己用选这个。
- **外部测试员**（External）：最多 10000 人，通过公开链接邀请，**需要 Beta App Review**（通常 1 天内）。

## 0. 前置条件

- [ ] 已加入 Apple Developer Program（个人 99 美元/年，公司 299）
- [ ] 拿到 Team ID（developer.apple.com → Membership）
- [ ] Xcode 15+，已登录该开发者账号

## 1. 注册 App ID

developer.apple.com → Certificates, Identifiers & Profiles → Identifiers：

- 主 App：`com.sublens.livetranslate`（或你改过的 ID）
- 扩展：`com.sublens.livetranslate.ScreenBroadcast`

扩展类型选 **App Extension**，不需要额外勾任何 Capability。如果用 App Group（可选项），两个 ID 都要勾 App Groups。

## 2. 创建 App 记录

App Store Connect → My Apps → `+` → New App：

- Platform: iOS
- Name: 译幕（或你的名字，全球唯一，被占用就加后缀）
- Primary Language: 简体中文
- Bundle ID: 选上一步的 **主 App ID**（下拉里必须能选到，选不到说明 ID 还没生效，等几分钟）
- SKU: 随便，比如 `sublens001`

## 3. 生成 API Key

App Store Connect → Users and Access → Integrations → App Store Connect API → `+`

- 权限选 **App Manager** 就够
- 下载 `.p8`（**只能下载一次**）

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
```

记下 Key ID（10 位）和页面顶部的 Issuer ID（UUID 格式）。

## 4. 归档并上传

```bash
cd LiveSubtitle
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  ./scripts/upload_testflight.sh
```

脚本做四件事：`archive` → `exportArchive` → `validate-app` → `upload-app`。

不想用脚本，等价的手动流程：

```bash
xcodebuild -project SubLens.xcodeproj -scheme SubLens -configuration Release \
  -destination "generic/platform=iOS" -archivePath build/SubLens.xcarchive \
  -allowProvisioningUpdates archive

xcodebuild -exportArchive -archivePath build/SubLens.xcarchive \
  -exportPath build/export -exportOptionsPlist scripts/ExportOptions.plist \
  -allowProvisioningUpdates

xcrun altool --upload-app --type ios -f build/export/SubLens.ipa \
  --apiKey $ASC_KEY_ID --apiIssuer $ASC_ISSUER_ID
```

## 5. 等构建处理

App Store Connect → 你的 App → TestFlight → iOS Builds。
状态从 `Processing` 变成 `Ready to Submit` 通常 10~30 分钟。收到 "Missing Compliance" 邮件的话点一下加密合规（本工程 Info.plist 已声明 `ITSAppUsesNonExemptEncryption = false`，选"不使用加密"即可）。

## 6. 邀请测试员

**内部**：TestFlight → Internal Testing → `+` → 选个组 → 添加成员（必须是 App Store Connect 用户）。

**外部**：TestFlight → External Testing → 建组 → 添加构建 → **Submit for Beta Review** → 通过后把公开链接发出去。

## 7. 测试员怎么装

App Store 里装 **TestFlight** → 打开邀请链接或邮箱邀请 → 点 Install。构建有效期 90 天。

---

## 可能被卡住的点

**1. 上传报 `No suitable application records were found`**
App Store Connect 里还没有对应 Bundle ID 的 App 记录，或者 ID 不一致。注意扩展的 ID 不能单独建 App 记录。

**2. 上传报 `Authentication failed`**
`.p8` 文件名必须严格是 `AuthKey_<KEY_ID>.p8`，Issuer ID 别和 Key ID 搞混。

**3. Beta 审核可能挑刺的地方（提前知道）**
- **后台静音保活**：为了让屏幕字幕在后台继续工作，App 声明了 `audio` 后台模式并播放静音音频。这属于灰色用法，App Store 正式上架审核较严时可能被质疑"滥用后台音频"。内部测试一般没问题；要走外部 Beta 审核，建议在审核备注里说明"实时字幕需要持续处理录屏扩展的数据"，或者干脆只在 App 前台演示屏幕字幕功能。
- **录屏用途说明**：审核员可能会问为什么要录屏。备注里写清楚"用户主动开启录屏，文字仅在本机识别和翻译"。
- **隐私**：工程默认端上识别与端上翻译，不上传内容；只有端上失败且用户填了 API Key 才会把文本发到云端。这些在 App 隐私声明里要如实填写（"用户内容 - 其他"）。

**4. 装上去但没有「译幕 · 屏幕字幕」**
TestFlight 装的包和 Xcode 直接跑的包行为一致。先启动一次 App，再长按控制中心录屏按钮；仍不出现就重启手机。

**5. 90 天后失效**
TestFlight 构建 90 天过期，重新上传即可（版本号 `CURRENT_PROJECT_VERSION` 要加一）。
