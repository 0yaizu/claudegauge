#!/bin/bash
# release ビルドから build/ClaudeGauge.app を組み立てる (ad-hoc 署名)。
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/ClaudeGauge.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClaudeGauge" "$APP/Contents/MacOS/ClaudeGauge"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Hardened Runtime: 他プロセスからの DYLD_INSERT_LIBRARIES などによるコード注入を OS が拒否する。
# このアプリは JIT も未署名ライブラリも使わないので、entitlement は要らない。
codesign --force --sign - --options runtime "$APP"
plutil -lint "$APP/Contents/Info.plist"
echo "Built $APP"
