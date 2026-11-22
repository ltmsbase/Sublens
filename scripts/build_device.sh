#!/usr/bin/env bash
# 用自己的 Apple ID（免费个人团队也行）把 App 装到已连接的真机上。
#
# 用法：
#   ./scripts/build_device.sh                 # 用默认 Bundle ID 和已登录的团队
#   TEAM_ID=ABCDE12345 BUNDLE_ID=com.我的名字.sublens ./scripts/build_device.sh
#
# 前置条件：Xcode 已登录 Apple ID，设备已信任并出现在 Xcode 的设备列表里。

set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="${BUNDLE_ID:-com.sublens.livetranslate}"
TEAM_ID="${TEAM_ID:-}"
UDID="${UDID:-}"

command -v xcodebuild >/dev/null 2>&1 || {
    echo "没有找到 xcodebuild，请先在 App Store 安装 Xcode（需要 macOS）。"
    exit 1
}

# 1. 如果改了 Bundle ID / 团队，先写回工程（扩展会自动加 .ScreenBroadcast 后缀）
python3 - "$BUNDLE_ID" "$TEAM_ID" <<'PY'
import re, sys
bundle, team = sys.argv[1], sys.argv[2]
path = "SubLens.xcodeproj/project.pbxproj"
text = open(path, encoding="utf-8").read()
text = text.replace("PRODUCT_BUNDLE_IDENTIFIER = com.sublens.livetranslate.ScreenBroadcast;",
                    "PRODUCT_BUNDLE_IDENTIFIER = %s.ScreenBroadcast;" % bundle)
text = text.replace("PRODUCT_BUNDLE_IDENTIFIER = com.sublens.livetranslate;",
                    "PRODUCT_BUNDLE_IDENTIFIER = %s;" % bundle)
if team:
    text = re.sub(r'DEVELOPMENT_TEAM = "[^"]*";', 'DEVELOPMENT_TEAM = "%s";' % team, text)
open(path, "w", encoding="utf-8").write(text)
print("bundle id ->", bundle, "| team ->", team or "(Xcode 默认)")
PY

# 2. 编译
echo "开始编译…"
xcodebuild \
    -project SubLens.xcodeproj \
    -scheme SubLens \
    -configuration Debug \
    -destination "generic/platform=iOS" \
    -derivedDataPath build \
    -allowProvisioningUpdates \
    build

APP_PATH="build/Build/Products/Debug-iphoneos/SubLens.app"
[ -d "$APP_PATH" ] || { echo "编译产物没找到：$APP_PATH"; exit 1; }

# 3. 安装到设备
UDID="${UDID:-$(xcrun devicectl list devices 2>/dev/null | awk 'NR>1 && $0 ~ /connected|available/ {print $3; exit}')}"
if [ -n "$UDID" ]; then
    echo "安装到设备 $UDID …"
    xcrun devicectl device install app --device "$UDID" "$APP_PATH"
    echo "完成。首次启动前，请在「设置 - 通用 - VPN与设备管理」里信任你的开发者证书。"
else
    echo "已编译完成：$APP_PATH"
    echo "没有检测到设备，用 Xcode 打开工程选设备后按 Cmd+R 即可。"
fi
