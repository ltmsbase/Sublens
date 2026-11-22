# 用免费 Apple ID 装到自己的 iPhone

不需要付费开发者账号。代价是签名 7 天过期，到期重新编译一次就行。

## 准备

- macOS + Xcode 15 或更新（App Store 直接装）
- iPhone，系统 iOS 18.0 以上
- 一根能传数据的线（或同一局域网下用无线调试）
- 任意 Apple ID（没开发者账号也行）

## 一、Xcode 里登录账号

`Xcode → Settings → Accounts → +` 加你的 Apple ID。
登录后 `Manage Certificates` 里会看到 Xcode 自动生成的 **Apple Development** 证书（免费账号也有一张）。

## 二、打开工程

```bash
cd LiveSubtitle
open SubLens.xcodeproj
```

## 三、改 Bundle ID（重要）

免费账号的 Bundle ID 必须是全球唯一的，用默认的 `com.sublens.livetranslate` 大概率会冲突。

1. 选中 **SubLens** target → `General` → Bundle Identifier 改成 `com.你的名字拼音.sublens`
2. 选中 **ScreenBroadcastExtension** target → 改成 `com.你的名字拼音.sublens.ScreenBroadcast`

扩展的 ID **必须**是主 App ID 加 `.ScreenBroadcast` 后缀，否则装不上。

命令行一次性改完：

```bash
python3 - <<'PY'
import re
p="SubLens.xcodeproj/project.pbxproj"
s=open(p,encoding="utf-8").read()
s=s.replace("PRODUCT_BUNDLE_IDENTIFIER = com.sublens.livetranslate.ScreenBroadcast;","PRODUCT_BUNDLE_IDENTIFIER = com.你的名字.sublens.ScreenBroadcast;")
s=s.replace("PRODUCT_BUNDLE_IDENTIFIER = com.sublens.livetranslate;","PRODUCT_BUNDLE_IDENTIFIER = com.你的名字.sublens;")
open(p,"w",encoding="utf-8").write(s)
PY
```

## 四、选团队

两个 target 的 `Signing & Capabilities` 里：

- 勾选 `Automatically manage signing`
- Team 选 `你的名字 (Personal Team)`

不需要任何 Capability。工程里的 entitlements 是空的——这是故意的，因为免费个人团队**不支持 App Groups**，所以屏幕字幕走的是回环 TCP 通道（详见 README）。

## 五、运行

插上 iPhone → 顶部设备选你的手机 → `Cmd+R`。

首次会报 "Untrusted Developer"：
**设置 → 通用 → VPN与设备管理 → 开发者 App → 信任**。

## 六、验证

1. App 能打开，四个 Tab 都在。
2. 「同传」页点麦克风，说话，出字幕。
3. 「屏幕」页点开始，下拉控制中心长按录屏 → 列表里应出现「译幕 · 屏幕字幕」。

## 常见报错

| 报错 | 原因 | 处理 |
| --- | --- | --- |
| `Personal development teams do not support the App Groups capability` | 有人手动加了 App Group | 删掉 entitlements 里的 app groups 键，或改用付费账号 |
| `The app ID cannot be registered` | Bundle ID 被别人占了 | 换成更独特的，比如 `com.yourname.sublens2026` |
| `No profiles for ... were found` | 设备没注册 | 用 Xcode 直接 Run（会自动注册），不要用命令行首次构建 |
| `Unable to install ... not have the required entitlements` | 签名里带了不支持的能力 | 确认 entitlements 是空 dict |
| 装完闪退 | 免费签名过期 | 重新 `Cmd+R` |

## 免费账号的限制

- 签名 **7 天**有效，过期要重签。
- 7 天内最多创建 **10 个 App ID**。
- 同一时间最多 **3 个** 免费签名的 App 在设备上。
- 不能用 TestFlight、推送、App Groups、iCloud 等能力。

想彻底摆脱这些限制，只能上付费开发者计划。
