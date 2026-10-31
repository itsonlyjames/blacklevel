# Blacklevel Home

A replacement home screen for Sony BRAVIA Google TV / Android TV. The time, one row of your apps, one row of your HDMI inputs, and Settings. Nothing else.

![Apps row focused](../docs/images/home-apps.png)
![Inputs row focused](../docs/images/home-inputs.png)

- **Apps** come from the TV itself (every app with a TV launcher entry), minus the bundled Sony and Google extras (Play Store, Sony Select, the Vewd browser and so on). YouTube stays. By default the app you opened last moves to the front; hold OK on an app to pick it up, ◀ ▶ to move it, OK to place it (Back cancels). Placing one switches **App order** in Customise to *Your order*; switch it back to *Recently opened* any time.
- **Inputs** are the connected HDMI ports, named after the HDMI-CEC device on them ("SHIELD", "RX-V485") or the name you gave the port on the TV ("PC"). Device names come from the TV's own local Sony API, which needs no key. That API takes about a second to answer, so names are cached and the row updates when they change.
- **OLED care**: a dark, warm background; dims to ~30% after a minute idle; shifts everything a few pixels every minute.
- **Remote**: ◀ ▶ move along a row, ▲ ▼ switch rows, OK opens, hold OK moves an app. Back closes Customise or cancels a move, and otherwise does nothing (you're already home).

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

On a Sony A80J (Google TV, Android 12) that isn't enough by itself. `set-home-activity` and the HOME role both report success, but the Home button still opens Google TV's launcher. With that launcher disabled, Home goes to Google's setup app (`com.google.android.tungsten.setupwraith/.RecoveryActivity`), which shows nothing. adb isn't allowed to disable that one activity (`Shell cannot change component state`), so the whole setup app has to be disabled:

```bash
adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
adb shell cmd package set-home-activity --user 0 io.github.itsonlyjames.blacklevel/.HomeActivity
adb shell cmd role add-role-holder --user 0 android.app.role.HOME io.github.itsonlyjames.blacklevel
```

Verified on the A80J on 30 October 2026 with the earlier build (package `tv.hijacking.home`). Home opened Blacklevel Home from YouTube, Plex, Netflix, TV Settings and the SHIELD input. It still did after a minute and after a reboot (the TV boots to its last input, as normal; Home then opens Blacklevel Home). Back on the home screen stays put. Opening apps, inputs and Settings from it all worked. Screenshots: `design/tv/home-from-*.png`, `design/tv/home-after-reboot.png`.

### Current state of the TV

| Package | State |
|---|---|
| `com.google.android.apps.tv.launcherx` (Google TV home) | disabled |
| `com.google.android.tungsten.setupwraith` (Google TV setup and recovery) | disabled |
| `tv.samba.ssm` (Samba TV) | disabled (separately, for privacy) |
| `com.sony.dtv.homekit`, `com.sonypicturescore`, `com.apple.atve.sony.appletv`, `com.sony.dtv.kenhchonloc`, `com.sony.dtv.b2b.softap` | disabled from the factory; leave them |
| `io.github.itsonlyjames.blacklevel` (Blacklevel Home) | installed 31 October 2026; home screen and HOME role holder |
| `tv.hijacking.home` (Blacklevel Home, earlier package name) | removed |

### After every Blacklevel Home install or update

Reinstalling can clear the home choice, so run this again after each install. With Google's launcher and setup app disabled, Blacklevel Home is also the only real home left, so Android should pick it anyway:

```bash
adb shell cmd package set-home-activity --user 0 io.github.itsonlyjames.blacklevel/.HomeActivity
adb shell cmd role add-role-holder --user 0 android.app.role.HOME io.github.itsonlyjames.blacklevel
```

Builds before 31 October 2026 used the package `tv.hijacking.home`, which Android treats as a different app. If you have it, install the new build, run the two commands above, press Home to check it opens, then remove the old one with `adb uninstall tv.hijacking.home`. The new build starts with an empty recent-apps order.

## Before a factory reset or a major Google TV update

Switch Google's apps back on first. The setup app runs first-time setup and recovery, so a reset or big update may misbehave without it:

```bash
adb shell pm enable com.google.android.tungsten.setupwraith
adb shell pm enable com.google.android.apps.tv.launcherx
```

Afterwards, disable them again with the install commands above if you still want Blacklevel Home.

## Revert to the stock home screen

The launcher lines were verified on the A80J: they restored Google TV after an earlier attempt that disabled only the launcher. Re-enabling the whole setup app hasn't been run yet, but it's the same `pm enable` that undoes `disable-user`.

```bash
adb shell pm enable com.google.android.tungsten.setupwraith
adb shell pm enable com.google.android.apps.tv.launcherx
adb shell cmd package set-home-activity --user 0 com.google.android.apps.tv.launcherx/.home.HomeActivity
adb shell cmd role add-role-holder --user 0 android.app.role.HOME com.google.android.apps.tv.launcherx
adb uninstall io.github.itsonlyjames.blacklevel
adb uninstall tv.hijacking.home                      # only if a pre-rename build is still installed
```

Then press Home to check it opens Google TV.

## Customise

- **Design**: open `app/assets/index.html` in a desktop browser. Without the Android bridge it uses mock data, so you can iterate without a TV. The page is laid out at 1920×1080.
- **Starting app order**: the `preferred` list in `HomeActivity.kt`. It only matters until you've opened a few apps; after that the most-recently-opened order takes over.
- **Hidden apps**: the `hidden()` function in `HomeActivity.kt`.

`design/` has the mockup iterations (v1–v4) and photos from the TV.
