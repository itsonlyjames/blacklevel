#!/bin/zsh
# Builds BlacklevelRemote.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
# Universal, so the same build runs on Apple silicon and Intel Macs
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BIN=$(swift build -c release $ARCHS --show-bin-path)
APP=build/BlacklevelRemote.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN/BlacklevelRemote" "$APP/Contents/MacOS/BlacklevelRemote"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
