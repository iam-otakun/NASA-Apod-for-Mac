#!/bin/bash
# NASA APOD — 本地构建脚本（Dash 备，Fred 在 Mac 上运行）
# 用 DEVELOPER_DIR 直指 Xcode，不改系统 xcode-select，不需要 sudo。
set -e
cd "$(dirname "$0")"

if [ ! -d /Applications/Xcode.app ]; then
  echo "没找到 /Applications/Xcode.app，Xcode 还没装好。"
  exit 1
fi
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

echo "== Xcode 版本 =="
xcodebuild -version

echo "== 开始构建（Release，自签名 adhoc） =="
xcodebuild -project NASA-Apod-for-Mac.xcodeproj -scheme "NASA APOD" \
  -configuration Release -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  build

echo "== 完成 =="
echo "产物：build/Build/Products/Release/NASA APOD.app"
