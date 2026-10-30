#!/bin/bash
# Builds app/ into build/home.apk without Gradle: aapt2 -> kotlinc -> d8 -> zipalign -> apksigner.
set -euo pipefail
cd "$(dirname "$0")"
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
BT=$SDK/build-tools/34.0.0
JAR=$SDK/platforms/android-34/android.jar
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}
KHOME=$(dirname "$(readlink -f "$(command -v kotlinc)")")/..
KSTD=$(ls "$KHOME"/libexec/lib/kotlin-stdlib.jar "$KHOME"/lib/kotlin-stdlib.jar 2>/dev/null | head -1 || true)

rm -rf build && mkdir -p build/res build/classes build/dex
"$BT/aapt2" compile --dir app/res -o build/res.zip
"$BT/aapt2" link -I "$JAR" --manifest app/AndroidManifest.xml -A app/assets build/res.zip \
  --min-sdk-version 28 --target-sdk-version 31 -o build/unsigned.apk
kotlinc app/src -cp "$JAR" -d build/classes -jvm-target 1.8 -nowarn 2>&1 | grep -v "^warning" || true
# r8 strips the unused parts of the Kotlin stdlib (~2.5 MB of dex -> a few KB)
(cd build/classes && jar cf ../classes.jar .)
java -cp "$BT/lib/d8.jar" com.android.tools.r8.R8 --release --min-api 28 --lib "$JAR" \
  --pg-conf rules.pro --output build/dex build/classes.jar "$KSTD" 2>&1 | grep -E "^Error" || true
(cd build/dex && zip -q ../unsigned.apk classes*.dex)
"$BT/zipalign" -f -p 4 build/unsigned.apk build/aligned.apk

KS=debug.keystore
[ -f "$KS" ] || keytool -genkeypair -keystore "$KS" -storepass android -keypass android \
  -alias home -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Home" >/dev/null 2>&1
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:android --key-pass pass:android \
  --out build/home.apk build/aligned.apk
ls -la build/home.apk
