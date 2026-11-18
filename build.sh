#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Clocky -> WatchBridge 未签名 IPA 打包脚本
# 运行环境: macOS + Xcode 26 (含 watchOS 26 SDK)
# 产物: build/ipa/Clocky-WatchBridge.ipa
# ============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/build"

WATCH_BUNDLE_ID="com.custom.Clocky.watchkitapp"
COMPANION_BUNDLE_ID="com.custom.Clocky"
COMPANION_NAME="ClockyCompanion"
WATCH_APP_NAME="Clocky"

REPO_URL="https://github.com/pookjw/Clocky.git"

echo "==> 1/5 拉取 Clocky 源码"
rm -rf "$BUILD/Clocky"
git clone -b main --depth 1 "$REPO_URL" "$BUILD/Clocky"

# 兼容性：仓库用 objectVersion 110（Xcode 27.3），macos-26 runner 的 Xcode 26.6 打不开，
# 把工程格式降到 77（Xcode 16.3+，仍支持 PBXFileSystemSynchronizedRootGroup）。
PBPROJ="$BUILD/Clocky/Clocky.xcodeproj/project.pbxproj"
sed -e 's/objectVersion = 110;/objectVersion = 77;/' \
    -e 's/preferredProjectObjectVersion = 110;/preferredProjectObjectVersion = 77;/' \
    "$PBPROJ" > "$PBPROJ.tmp" && mv "$PBPROJ.tmp" "$PBPROJ"
echo "    已把 project.pbxproj 工程格式从 110 降到 77"

# ------------------------------------------------------------
# 2. 编译 watchOS 端 Clocky.app (无签名)
# ------------------------------------------------------------
echo "==> 2/5 编译 watchOS 端 Clocky.app"

if ! xcodebuild \
      -project "$BUILD/Clocky/Clocky.xcodeproj" \
      -scheme Clocky \
      -configuration Release \
      -destination 'generic/platform=watchOS' \
      -derivedDataPath "$BUILD/DerivedDataWatch" \
      PRODUCT_BUNDLE_IDENTIFIER="$WATCH_BUNDLE_ID" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY="" \
      build; then
  echo "!! 首次编译失败，改用 ARCHS=arm64 arm64e 重试"
  rm -rf "$BUILD/DerivedDataWatch"
  xcodebuild \
      -project "$BUILD/Clocky/Clocky.xcodeproj" \
      -scheme Clocky \
      -configuration Release \
      -destination 'generic/platform=watchOS' \
      -derivedDataPath "$BUILD/DerivedDataWatch" \
      PRODUCT_BUNDLE_IDENTIFIER="$WATCH_BUNDLE_ID" \
      ARCHS="arm64 arm64e" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      CODE_SIGN_IDENTITY="" \
      build
fi

WATCH_APP="$BUILD/DerivedDataWatch/Build/Products/Release-watchos/$WATCH_APP_NAME.app"
if [ ! -d "$WATCH_APP" ]; then
  echo "!! 未找到 watch app: $WATCH_APP" >&2
  exit 1
fi
echo "    watch app: $WATCH_APP"

# ------------------------------------------------------------
# 3. 编译极简 iOS Companion 宿主 App (无签名)
# ------------------------------------------------------------
echo "==> 3/5 编译 iOS Companion 宿主 App"

COMPANION_APP="$BUILD/Companion/$COMPANION_NAME.app"
rm -rf "$COMPANION_APP"
mkdir -p "$COMPANION_APP"

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun swiftc \
  -sdk "$SDK_PATH" \
  -target arm64-apple-ios17.0 \
  -emit-executable \
  -parse-as-library \
  -o "$COMPANION_APP/$COMPANION_NAME" \
  "$ROOT/Companion/CompanionApp.swift"

cp "$ROOT/Companion/Info.plist" "$COMPANION_APP/Info.plist"
echo "    companion app: $COMPANION_APP"

# ------------------------------------------------------------
# 4. 组装嵌套结构 + 修正 Info.plist
# ------------------------------------------------------------
echo "==> 4/5 组装 Payload 并修正 Info.plist"

STAGING="$BUILD/staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/Payload"

ditto "$COMPANION_APP" "$STAGING/Payload/$COMPANION_NAME.app"
mkdir -p "$STAGING/Payload/$COMPANION_NAME.app/Watch"
ditto "$WATCH_APP" "$STAGING/Payload/$COMPANION_NAME.app/Watch/$WATCH_APP_NAME.app"

WATCH_PLIST="$STAGING/Payload/$COMPANION_NAME.app/Watch/$WATCH_APP_NAME.app/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $WATCH_BUNDLE_ID" "$WATCH_PLIST"
/usr/libexec/PlistBuddy -c "Delete :WKWatchOnly" "$WATCH_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :WKCompanionAppBundleIdentifier" "$WATCH_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :WKCompanionAppBundleIdentifier string $COMPANION_BUNDLE_ID" "$WATCH_PLIST"

# 清除残留描述文件
find "$STAGING/Payload" -name "embedded.mobileprovision" -delete

# ------------------------------------------------------------
# 5. 打包 IPA 并校验
# ------------------------------------------------------------
echo "==> 5/5 打包 IPA"

IPA_DIR="$BUILD/ipa"
rm -rf "$IPA_DIR"
mkdir -p "$IPA_DIR"

ditto -c -k --sequesterRsrc --keepParent "$STAGING/Payload" "$IPA_DIR/Clocky-WatchBridge.ipa"

echo "    IPA 内容:"
unzip -l "$IPA_DIR/Clocky-WatchBridge.ipa" | grep -E "Payload/.*\.app/"

echo ""
echo "完成: $IPA_DIR/Clocky-WatchBridge.ipa"
