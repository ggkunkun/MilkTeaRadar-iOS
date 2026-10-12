#!/usr/bin/env bash
# ============================================================
#  奶茶优惠雷达 · iOS 一键构建脚本
#  适用：macOS + Xcode 15+
#
#  用法：
#    chmod +x build.sh
#    ./build.sh              # 构建并尝试导出 ipa
#    ./build.sh sim          # 只编译模拟器版本（不需要签名，最快验证）
#    ./build.sh run          # 编译并在已连接的设备/模拟器上运行
# ============================================================
set -euo pipefail

APP_NAME="MilkTeaRadar"
SCHEME="$APP_NAME"
PROJECT="$APP_NAME.xcodeproj"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/ipa"

MODE="${1:-ipa}"

# ---------- 环境检查 ----------
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "✗ 未找到 xcodebuild。请先安装 Xcode：https://apps.apple.com/app/xcode/id497799835"
  exit 1
fi

echo "==> Xcode 版本："
xcodebuild -version

if [ ! -d "$PROJECT" ]; then
  echo "✗ 找不到 $PROJECT"
  echo "  若只有 project.yml，请先执行：brew install xcodegen && xcodegen generate"
  exit 1
fi

# ---------- 模式 1：模拟器编译（不需签名） ----------
if [ "$MODE" = "sim" ]; then
  echo "==> 编译模拟器版本（跳过签名）"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO \
    -derivedDataPath "$BUILD_DIR/dd" \
    build
  echo "✓ 编译成功，产物在 $BUILD_DIR/dd/Build/Products/Debug-iphonesimulator/"
  exit 0
fi

# ---------- 模式 2：真机运行 ----------
if [ "$MODE" = "run" ]; then
  echo "==> 查找可用设备"
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations | head -30
  echo
  echo "请手动执行（把 <设备名> 换成上面列出的设备）："
  echo "  xcodebuild -project $PROJECT -scheme $SCHEME -destination 'platform=iOS,name=<设备名>' build"
  echo "或直接用 Xcode 打开工程按 ⌘R。"
  exit 0
fi

# ---------- 模式 3：Archive + 导出 ipa ----------
echo "==> 清理旧产物"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 归档（Release）"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  clean archive

echo "==> 生成 ExportOptions.plist"
# 优先读环境变量，其次自动探测本机签名身份
TEAM_ID="${MTR_TEAM_ID:-}"
METHOD="${MTR_EXPORT_METHOD:-development}"

if [ -z "$TEAM_ID" ]; then
  TEAM_ID=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -oE '\([A-Z0-9]{10}\)' | head -1 | tr -d '()' || true)
fi

if [ -z "$TEAM_ID" ]; then
  echo "⚠ 未检测到开发者证书 / Team ID。"
  echo "  归档已完成：$ARCHIVE_PATH"
  echo "  如需导出 ipa，请设置 MTR_TEAM_ID 后重跑，或用 Xcode："
  echo "    open $ARCHIVE_PATH  →  Distribute App"
  exit 0
fi

cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>${METHOD}</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>compileBitcode</key>
    <false/>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

echo "==> 导出 ipa（method=${METHOD}, team=${TEAM_ID}）"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

echo
echo "✓ 完成！ipa 位于："
ls -la "$EXPORT_DIR"/*.ipa 2>/dev/null || echo "  （未生成 ipa，请检查签名配置）"
