#!/usr/bin/env bash
# 在装了 Xcode 的 Mac 上编出「未签名 ipa」，交给 Sideloadly / AltStore 用免费 Apple ID 签。
# 和 GitHub Actions 里那条 workflow 等价，适合借用别人的 Mac 时用（不用碰签名证书）。
#
# 用法：./scripts/build_unsigned_ipa.sh

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT="SubLens.xcodeproj"
SCHEME="SubLens"
OUT="SubLens-unsigned.ipa"

command -v xcodebuild >/dev/null || { echo "这台机器没有 xcodebuild，只能走 GitHub Actions（见 docs/BUILD_WITHOUT_XCODE.md）"; exit 1; }

echo "==> 清理旧产物"
rm -rf build Payload "$OUT"

echo "==> 编译（不签名）"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  ONLY_ACTIVE_ARCH=NO \
  build

APP="build/Build/Products/Release-iphoneos/SubLens.app"
[ -d "$APP" ] || { echo "找不到 $APP"; exit 1; }

echo "==> 打包"
mkdir -p Payload
cp -R "$APP" Payload/
[ -d "Payload/SubLens.app/PlugIns/ScreenBroadcastExtension.appex" ] \
  || echo "警告：扩展没有嵌进主 App，装好后录屏列表里会没有「译幕」"

zip -qry "$OUT" Payload
rm -rf Payload

echo "==> 完成：$(pwd)/$OUT"
echo "    下一步：用 Sideloadly 打开它，填你的 Apple ID，点 Start。"
