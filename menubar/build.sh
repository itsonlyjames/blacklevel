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
# Signed with a Developer ID when one is in the keychain, so macOS sees every rebuild as the same app
# (no Keychain prompts); ad hoc otherwise. SIGN_IDENTITY overrides; RELEASE=1 adds the timestamp notarising needs.
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}
if [[ -n $IDENTITY ]]; then
  [[ -n ${RELEASE:-} ]] && TIMESTAMP=--timestamp || TIMESTAMP=--timestamp=none
  codesign --force --options runtime $TIMESTAMP --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
