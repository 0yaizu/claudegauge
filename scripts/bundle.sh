#!/bin/bash
#   VERSION=1.2.3 ./scripts/bundle.sh   Info.plist のバージョンを上書きする (リリースのビルド用)。省略すると plist の値のまま。
set -euo pipefail

cd "$(dirname "$0")/.."

# PlistBuddy のコマンド文字列に入れるので、形を先に検査する (ビルドの前に止める)。
if [[ -n "${VERSION:-}" && ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION は x.y.z の形で指定してください: $VERSION" >&2
    exit 1
fi

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/ClaudeGauge.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClaudeGauge" "$APP/Contents/MacOS/ClaudeGauge"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# 署名の前に書き換える。
if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

# Hardened Runtime: 他プロセスからの DYLD_INSERT_LIBRARIES などによるコード注入を OS が拒否する。
# このアプリは JIT も未署名ライブラリも使わないので、entitlement は要らない。
codesign --force --sign - --options runtime "$APP"
codesign --verify --strict --deep "$APP"
plutil -lint "$APP/Contents/Info.plist"
echo "Built $APP"
