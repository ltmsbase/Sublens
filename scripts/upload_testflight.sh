#!/usr/bin/env bash
# 归档并上传到 TestFlight。需要：
#   1. 付费 Apple Developer Program（个人 99 美元/年）
#   2. App Store Connect 里已创建与本工程 Bundle ID 一致的 App 记录
#   3. App Store Connect API Key（.p8）放到 ~/.appstoreconnect/private_keys/
#      https://appstoreconnect.apple.com/access/integrations/api
#
# 用法：
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxx-xxxx-xxxx ./scripts/upload_testflight.sh

set -euo pipefail
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?请设置 ASC_KEY_ID（API Key 的 Key ID）}"
: "${ASC_ISSUER_ID:?请设置 ASC_ISSUER_ID（App Store Connect 的 Issuer ID）}"

BUNDLE_ID="${BUNDLE_ID:-com.sublens.livetranslate}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

[ -f "$KEY_PATH" ] || {
    echo "找不到 API Key 文件：$KEY_PATH"
    echo "请从 App Store Connect -> 用户和访问 -> 集成 -> App Store Connect API 下载 .p8，"
    echo "放到 ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"
    exit 1
}

echo "1/4 归档…"
xcodebuild \
    -project SubLens.xcodeproj \
    -scheme SubLens \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath build/SubLens.xcarchive \
    -allowProvisioningUpdates \
    archive

echo "2/4 导出 ipa…"
rm -rf build/export
xcodebuild \
    -archivePath build/SubLens.xcarchive \
    -exportPath build/export \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -allowProvisioningUpdates \
    -exportArchive

IPA=$(find build/export -name "*.ipa" | head -n 1)
[ -n "$IPA" ] || { echo "没有导出 ipa"; exit 1; }
echo "ipa: $IPA"

echo "3/4 校验…"
xcrun altool --validate-app --type ios -f "$IPA" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo "4/4 上传…"
xcrun altool --upload-app --type ios -f "$IPA" \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo ""
echo "上传完成。等 10~30 分钟构建处理完成后，去 App Store Connect -> TestFlight 添加内部测试员即可。"
echo "注意：Bundle ID 必须和 App Store Connect 里的 App 记录一致：$BUNDLE_ID"
