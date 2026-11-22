# 译幕 SubLens

iOS 上的实时翻译字幕工具，四个能力：

| 能力 | 状态 | 实现方式 |
| --- | --- | --- |
| 屏幕内容 → 双语字幕 | 可用 | ReplayKit 广播扩展取屏幕帧 → Vision OCR → 端上翻译 |
| 播放声音 → 双语字幕 | 受系统限制，见下文 | iOS 不允许第三方读取其他 App 音频流；用「同传」模式采集外放声音实现 |
| 识图翻译 | 可用 | 相册/拍照 → Vision OCR → 译文直接盖在原文位置 |
| 麦克风同声传译 | 可用 | SFSpeechRecognizer 流式识别 → 端上翻译 → 字幕 + 语音播报 |

要求 iOS 18.0 及以上（端上翻译依赖 Apple Translation 框架）。

---

## 一、先说清楚四个系统限制

这几条不是偷懒，是 iOS 的硬约束，评估时最好先看：

1. **第三方 App 不能直接读取别的 App 的屏幕**。唯一的合法入口是 ReplayKit「广播上传扩展」，也就是录屏。所以每次都要去控制中心手动开始录屏并选「译幕」，这是所有同类 App 的共同处境。
2. **第三方 App 不能盖在别的 App 上面**。想一边刷别的 App 一边看字幕，只能用系统唯一允许浮在最上层的**画中画（PiP）**。本工程就是这么做的：把字幕渲染成视频帧喂给画中画，得到一个悬浮字幕条。
3. **第三方 App 拿不到其他 App 的音频流**。ReplayKit 的广播扩展理论上能拿到 `audioApp` 采样，但扩展内存配额只有约 50MB，同时跑 OCR 和语音识别基本会被系统杀掉。所以「播放声音」这条走**麦克风采集**：手机外放着看视频/听播客，同传模式就能把声音转成字幕。戴耳机时麦克风听不到，这是物理限制。
4. **DRM 内容录不到**。Netflix、部分视频 App 的画面受保护，录屏出来是黑的，自然也没法识别。

除此之外都是真能跑的。

---

## 二、快速开始（5 分钟）

```bash
cd LiveSubtitle
open SubLens.xcodeproj
```

1. Xcode 选中 `SubLens` target → `Signing & Capabilities` → **Team** 选你自己的 Apple ID（免费的 "Personal Team" 也行）。
2. 如果提示 Bundle ID 冲突，把 `SubLens` 和 `ScreenBroadcastExtension` 两个 target 的 Bundle ID 改成 `com.你的名字.sublens` 和 `com.你的名字.sublens.ScreenBroadcast`（扩展必须以后缀形式挂在主 App 下面）。
3. 插上 iPhone，选设备，`Cmd+R`。
4. 首次启动后到「设置 → 通用 → VPN与设备管理」信任你的开发者证书。

命令行方式：

```bash
TEAM_ID=你的团队ID BUNDLE_ID=com.你的名字.sublens ./scripts/build_device.sh
```

> 没有 `SubLens.xcodeproj` 或者想从配置重建工程？`python3 scripts/gen_xcodeproj.py`；装了 XcodeGen 的话 `xcodegen generate` 也行（`project.yml` 是等价配置）。

### 电脑上装不了 Xcode？

不用装。`.github/workflows/build-ipa.yml` 会把工程丢给 GitHub 免费的 macOS 机器编译成未签名 `.ipa`，再用 **Sideloadly**（Mac/Windows，几十 MB）拿免费 Apple ID 签一下推到手机，全程不需要 Xcode。完整步骤见 `docs/BUILD_WITHOUT_XCODE.md`。

> 借到一台装了 Xcode 的 Mac 也可以：`./scripts/build_unsigned_ipa.sh` 直接出 ipa 交给 Sideloadly。

---

## 三、四个功能怎么用

### 1. 屏幕字幕

1. 进「屏幕」页 → 点「开始屏幕字幕」（会让 App 保持后台运行并准备好画中画）。
2. 下拉控制中心 → **长按**录屏按钮 → 在 App 列表里选「译幕 · 屏幕字幕」→ 开始直播。
3. 回到你要翻译的页面。字幕会出现在：
   - 本 App 的「最近字幕」列表（全屏阅读用）；
   - 画中画浮窗（点「开启浮窗」，切到别的 App 也能看到）。

识别节奏约 0.7 秒一轮，只翻译新增的行，避免重复刷屏。

### 2. 声音 → 字幕

进「同传」页点麦克风按钮。把手机放在声源附近（外放视频、面对面说话都行）。
- 识别优先走**设备本地**（`requiresOnDeviceRecognition`），不联网。
- 一句话说完（标点或停顿）就送去翻译，然后追加一条字幕。
- 打开「译文播报」会用系统语音念译文。

### 3. 识图翻译

「识图」页 → 选图或拍照 → 识别出的每段文字都会被翻译并**按原位置盖在图上**；下面还有原文/译文对照列表。适合菜单、说明书、路牌、截图。

### 4. 翻译引擎

- 默认：Apple 端上翻译（免费、离线、内容不上传）。首次用某个语种会提示下载语言包，之后可离线。
- 兜底：端上失败时，如果「设置」里填了 OpenAI 兼容接口的 Base URL + API Key，就走它；留空则用 MyMemory 公共接口（免 Key、质量一般、有频率限制）。

---

## 四、上 TestFlight

TestFlight **必须**有付费 Apple Developer Program（99 美元/年），免费 Apple ID 无法使用。步骤：

1. 加入开发者计划，拿到 Team ID。
2. 在 [App Store Connect](https://appstoreconnect.apple.com) 新建 App，Bundle ID 必须和工程一致。
3. 生成 App Store Connect API Key（用户和访问 → 集成 → App Store Connect API），下载 `.p8` 放到 `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`。
4. 运行：

```bash
ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxx-xxxx-xxxx ./scripts/upload_testflight.sh
```

5. 构建处理完（10~30 分钟）→ TestFlight → 添加内部测试员（最多 100 人，无需审核）或外部测试员（需要 Beta 审核）。

细节和排错见 [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md)，免费账号装机的完整流程见 [`docs/BUILD_FREE_ACCOUNT.md`](docs/BUILD_FREE_ACCOUNT.md)。

---

## 五、工程结构

```
LiveSubtitle/
├── SubLens.xcodeproj/            # 已生成，可直接打开
├── project.yml                   # XcodeGen 等价配置
├── SubLens/
│   ├── App/                      # 入口与全局状态装配
│   ├── Core/                     # 模型、跨进程总线、回环 TCP 传输
│   ├── Translation/              # 端上翻译 + 云端兜底
│   ├── Speech/                   # 流式识别、语音播报
│   ├── Screen/                   # 字幕服务、画中画浮窗、后台保活
│   ├── Image/                    # Vision OCR
│   ├── UI/                       # 四个页面 + 组件
│   └── Resources/                # Info.plist、entitlements、图标
├── ScreenBroadcastExtension/     # 录屏扩展：取帧 + OCR + 上报
├── scripts/                      # 工程生成、真机安装、TestFlight 上传
└── docs/                         # 上手与排错文档
```

### 数据流

```
[控制中心开始录屏]
        ↓
ScreenBroadcastExtension
  processSampleBuffer(.video)
        ↓ 缩放到 720px，0.7s 一轮
  Vision VNRecognizeTextRequest
        ↓ 文本行
  SharedScreenBus.write()
        ├─ 有 App Group → 写共享 JSON 文件（主 App 每 0.6s 轮询）
        └─ 没有 App Group → 回环 TCP 127.0.0.1:47821（写入即推送）
        ↓
主 App ScreenSubtitleService（去重）
        ↓
Translator（Apple 端上，失败走云端）
        ↓
字幕列表 + 画中画浮窗 +（可选）语音播报
```

**为什么有回环 TCP？** App Group 需要付费开发者账号。为了让免费账号也能跑通屏幕字幕，扩展会连到主 App 监听的本地端口发 JSON。主 App 用「静音音频保活」保持后台运行（`UIBackgroundModes: audio`），所以切到别的 App 也能收。付费账号想更稳，可以在两个 entitlements 文件里打开 App Group（见下）。

### 改成自己的 App Group（可选，付费账号）

1. `SubLens/Resources/SubLens.entitlements` 和 `ScreenBroadcastExtension/ScreenBroadcastExtension.entitlements` 都加：

```xml
<key>com.apple.security.application-groups</key>
<array><string>group.com.你的名字.sublens</string></array>
```

2. 同步改 `SubLens/Core/SharedBus.swift` 里的 `SharedConfig.appGroupID`。
3. 到 developer 后台给两个 Bundle ID 勾上 App Groups。

改完会自动走文件通道，不再依赖 TCP。

---

## 六、常见问题

**录屏列表里没有「译幕」**
先在本 App 里点一次「开始屏幕字幕」，扩展才会被系统注册；仍不出现就重启一次手机。

**屏幕字幕一直显示"还没有收到画面文字"**
- 检查是不是在控制中心选的「译幕 · 屏幕字幕」，而不是系统自带的录屏；
- 确认 App 没被手动划掉（后台保活依赖音频会话，划掉就断了）；
- 有些页面本身没文字（纯图片、视频），属正常。

**浮窗字幕起不来**
画中画需要 App 在前台时调用一次启动。回到 App 点「开启浮窗」，再切走；模拟器不支持画中画，必须真机。

**端上翻译报错 / 一直走云端**
iOS 18 的端上翻译必须先把语言包装到手机里，否则 `TranslationSession` 初始化会直接抛错，程序会自动退回云端（没填 Key 时用免费的 MyMemory，速度慢一些）。装语言包的两种办法：
1. 系统「翻译」App 里手动翻一次「中文 ↔ 英文」，系统会提示下载；
2. 设置 → App → 译幕 → 语言 里下载（部分版本在 设置 → 通用 → 语言与地区 → 翻译语言 里）。

点「设置 → 引擎 → 重新检测端上翻译语言包」可以立刻重新探测，不用重启 App。

**识图翻译有些字翻不出来**
竖排、艺术字、超小字号容易漏。拍照时尽量正对、光线均匀。

**真机提示"不受信任的开发者"**
设置 → 通用 → VPN与设备管理 → 信任你的开发者证书。免费账号的签名 7 天后过期，重新 `Cmd+R` 即可。

---

## 七、还没做的

- 屏幕音频（`audioApp`）转写：受扩展内存限制，代码里保留分支但默认不启用。
- Live Activity 字幕条：比画中画更省地方，但更新频率会被系统限流，暂时没接。
- 双语字幕导出（SRT）：数据模型已经支持，加个导出很简单。

需要哪一项可以接着加。
