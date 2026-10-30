# Blacklevel Home

A replacement home screen for Sony BRAVIA Google TV / Android TV. The time, one row of your apps, one row of your HDMI inputs, and Settings. Nothing else.

![Apps row focused](../docs/images/home-apps.png)
![Inputs row focused](../docs/images/home-inputs.png)

- **Apps** come from the TV itself (every app with a TV launcher entry), minus the bundled Sony and Google extras (Play Store, Sony Select, the Vewd browser and so on). YouTube stays. The app you opened last moves to the front.
- **Inputs** are the connected HDMI ports, named after the HDMI-CEC device on them ("SHIELD", "RX-V485") or the name you gave the port on the TV ("PC"). Device names come from the TV's own local Sony API, which needs no key. That API takes about a second to answer, so names are cached and the row updates when they change.
- **OLED care**: a dark, warm background; dims to ~30% after a minute idle; shifts everything a few pixels every minute.
- **Remote**: ◀ ▶ move along a row, ▲ ▼ switch rows, OK opens. Back does nothing (you're already home).

It's a single `WebView` page ([`app/assets/index.html`](app/assets/index.html)) with a small Kotlin bridge ([`HomeActivity.kt`](app/src/io/github/itsonlyjames/blacklevel/HomeActivity.kt)) that lists apps and inputs. The APK is about 136 KB. Fonts are bundled, so it works offline.

## Build

Requires `openjdk@17`, `kotlin`, and the Android SDK packages `platforms;android-34` and `build-tools;34.0.0` (in `~/Library/Android/sdk`, or set `ANDROID_HOME`).

```bash
brew install openjdk@17 kotlin
./build.sh
```

The script runs aapt2 → kotlinc → R8 → zipalign → apksigner directly, no Gradle. Output: `build/home.apk`. The first build creates a local `debug.keystore` to sign with; keep it, since reinstalling over an APK signed with a different key fails.

## Install

Set up network debugging first ([TV setup](../docs/tv-setup.md#3-network-debugging-for-blacklevel-home-optional-for-the-remote)).

```bash
adb connect <tv-ip>:5555
adb install -r build/home.apk
adb shell cmd package set-home-activity io.github.itsonlyjames.blacklevel/.HomeActivity
```

On a Sony A80J (Google TV, Android 12) that isn't enough by itself. `set-home-activity` and the HOME role (`cmd role add-role-holder android.app.role.HOME io.github.itsonlyjames.blacklevel`) both report success, but the Home button still opens Google TV's launcher. With that launcher disabled, Home goes to Google's setup app (`com.google.android.tungsten.setupwraith/.RecoveryActivity`), which shows nothing. Making it stick therefore needs both disabled. This has not been tested end to end:

```bash
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith/.RecoveryActivity
adb shell cmd package set-home-activity io.github.itsonlyjames.blacklevel/.HomeActivity
```

Reinstalling or updating the APK clears the `set-home-activity` choice, so run it again after every install. Until then, open Blacklevel Home from the apps row, or with `adb shell am start -n io.github.itsonlyjames.blacklevel/.HomeActivity`.

## Revert to the stock home screen

Verified on the A80J:

```bash
adb shell pm enable com.google.android.apps.tv.launcherx
adb shell pm enable com.google.android.tungsten.setupwraith/.RecoveryActivity   # only if you disabled it
adb shell cmd package set-home-activity com.google.android.apps.tv.launcherx/.home.HomeActivity
adb shell cmd role add-role-holder android.app.role.HOME com.google.android.apps.tv.launcherx
adb uninstall io.github.itsonlyjames.blacklevel
```

## Customise

- **Design**: open `app/assets/index.html` in a desktop browser. Without the Android bridge it uses mock data, so you can iterate without a TV. The page is laid out at 1920×1080.
- **Starting app order**: the `preferred` list in `HomeActivity.kt`. It only matters until you've opened a few apps; after that the most-recently-opened order takes over.
- **Hidden apps**: the `hidden()` function in `HomeActivity.kt`.

`design/` has the mockup iterations (v1–v4) and photos from the TV.
