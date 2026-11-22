# 没有 Xcode 怎么把「译幕」装到 iPhone

> **ipa 已经编译好了**（2026-11-22 云端构建通过，501 KB）。如果你手上已经有 `SubLens-unsigned.ipa`，**跳过第一、二节**，直接从下面的「三、用 Sideloadly 签名安装」开始。
> 想自己重新编译：仓库 <https://github.com/ltmsbase/Sublens> 的 Actions 页点 `Run workflow`。

结论先说：**可以。** 思路是把"编译"和"签名安装"拆成两件事——

- 编译：丢给 GitHub 免费的 macOS 机器（云端已经装好 Xcode，不占你硬盘）；
- 签名 + 安装：用 **Sideloadly**（Mac / Windows 都有，几十 MB，不需要 Xcode）拿你的免费 Apple ID 签，再通过数据线推进手机。

整条链路不花一分钱，装出来的效果和你自己 `Cmd+R` 完全一样（免费账号都是 7 天有效期）。

---

## 一、准备

| 需要 | 说明 |
| --- | --- |
| GitHub 账号 | 免费注册。公开仓库的 Actions 分钟数不限 |
| 一台电脑 | 你的 MacBook 或任意 Windows 都行，只要能装 Sideloadly |
| iPhone 数据线 | 首次安装建议用线，装完可以拔 |
| 免费 Apple ID | 就是你平时登录 App Store 的那个 |

---

## 二、传到 GitHub（5 分钟）

1. 打开 <https://github.com/new>，新建一个仓库，名字随便（例如 `sublens`），**选 Public**（私有仓库每月只有 2000 分钟额度，public 不限制），不要勾 README。
2. 在本地把工程解压出来，进目录执行：

```bash
cd LiveSubtitle
git init
git add .
git commit -m "init"
git branch -M main
git remote add origin https://github.com/<你的用户名>/sublens.git
git push -u origin main
```

> 工程里已经放好 `.github/workflows/build-ipa.yml`，push 上去会自动开始编译。
> `.gitignore` 已排除 `build/`、`DerivedData/`、`.DS_Store`，不用担心把几百 MB 的中间产物传上去。

3. 打开仓库的 **Actions** 页 → 左侧 `Build unsigned IPA` → 右边 `Run workflow` → 绿色按钮。
   大约 3～6 分钟跑完（第一次会慢一点，要装依赖）。

4. 跑完后点进那次运行，页面底部 **Artifacts** → `SubLens-unsigned-ipa` → 下载，得到一个 zip，解压出 `SubLens-unsigned.ipa`。

编译失败的话，同一次运行的日志里有一段 `===== 编译错误摘要 =====`，把那段（或整个 `build.log`）发给我，我直接改代码。

---

## 三、用 Sideloadly 签名安装（10 分钟）

1. 下载：<https://sideloadly.io/>（认准这个域名）。macOS 直接拖进 Applications，Windows 直接装。
2. 手机用数据线连电脑，第一次连接手机上点「信任这台电脑」。
3. 打开 Sideloadly：
   - **IPA 文件**：选刚才解压出来的 `SubLens-unsigned.ipa`
   - **Apple 账号**：填你的 Apple ID（`iDevice` 那一栏会自动认出你的手机）
   - 如果是 Apple ID 登录，勾上 `Use Anisette Auth`（新版默认就勾好了）
4. 点 **Start**。中途可能弹：
   - `Apple ID 二次验证`：手机上会收到 6 位验证码，填进去；
   - `是否要注册新设备`：选是（免费账号每年能注册的设备数量有限，一台手机一般没问题）。
5. 安装完成后，手机上首次打开会提示"不受信任的开发者"：
   **设置 → 通用 → VPN与设备管理 → 开发者 App → 你的 Apple ID → 信任**。
6. 打开「译幕」，去「设置 → 检查系统权限」把麦克风、语音识别、相册、相机都点一遍授权。

装好后桌面上会有两个东西：`译幕`（主 App）和它在录屏列表里的项 `译幕 · 屏幕字幕`。第一次要先在 App 里点一次「开始屏幕字幕」，控制中心的录屏列表里才会出现它。

---

## 四、几个必须知道的点

**1. 7 天过期**
免费 Apple ID 签出来的 App 有效期 7 天，到期打不开。重新用 Sideloadly 点一次 Start 就能续上，数据不会丢。想彻底不过期只有付费开发者账号（$99/年）。

**2. 扩展能不能一起装上？**
能。IPA 里的 `Payload/SubLens.app/PlugIns/ScreenBroadcastExtension.appex` 会一起被签名。Sideloadly 对带扩展的 App 支持是完整的——装好后去控制中心看录屏列表里有没有「译幕 · 屏幕字幕」，有就说明扩展签名成功。

**3. 每次重新签名会重置 Bundle ID 吗？**
不会。Sideloadly 用工程里写死的 Bundle ID（默认 `com.sublens.livetranslate`）去申请描述文件。如果提示 **"This app ID is not available"**（被别人占了），把 `SubLens.xcodeproj` 里两个 target 的 Bundle ID 改成 `com.你的拼音.sublens` 和 `...sublens.ScreenBroadcast` 再重新 push，重新跑一次 Actions。

**4. 不想用 GitHub 的话还有两条路**
- 找一台装了 Xcode 的 Mac（同学/公司/网吧式共享 Mac），`open SubLens.xcodeproj` 直接 `Cmd+R`，或用 `./scripts/build_unsigned_ipa.sh` 出 ipa 再交给 Sideloadly；
- 租云 Mac（MacinCloud、Scaleway Mac mini 之类，约 ¥150～250/月），在上面装 Xcode 构建，手机通过 Sideloadly 或 Xcode 无线调试安装。

**5. 为什么不能再省一步，直接给我个 ipa？**
因为签名必须用**你自己的 Apple ID** 在**你自己的设备**上完成——苹果的描述文件和设备 UDID 是绑定的。任何"别人签好的 ipa"你手机都装不上，这是系统设计，不是流程偷懒。

---

## 五、常见报错对照

| 报错 | 原因 | 处理 |
| --- | --- | --- |
| `No signing certificate found` | 用了带签名的构建参数 | 这份 workflow 已经关掉签名，确认你下的是 `SubLens-unsigned.ipa` |
| `Failed to create provisioning profile` | Bundle ID 冲突 | 改 Bundle ID 后重新跑 Actions |
| `Unable to install "译幕"` | 手机没信任电脑 / 描述文件过期 | 重新连、重新点 Start |
| 装好后点开闪退 | 描述文件没生效 | 设置里删掉旧描述文件，重装一次 |
| 控制中心没有「译幕 · 屏幕字幕」 | 扩展没签名成功或没启动过一次 | 先打开主 App 点一次「开始屏幕字幕」，再重启手机 |
| `Maximum App IDs reached` | 免费账号一周内申请 App ID 太多 | 等一周，或在 App Store Connect 里删掉不用的 |
