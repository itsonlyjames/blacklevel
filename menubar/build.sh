#!/bin/zsh
# Builds BlacklevelRemote.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/BlacklevelRemote.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BlacklevelRemote "$APP/Contents/MacOS/BlacklevelRemote"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
