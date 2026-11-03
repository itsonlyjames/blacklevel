# Compatibility

Blacklevel is developed and tested on one TV. It should work on other BRAVIA TVs that expose the BRAVIA REST API ("IP control"), which covers most Sony Android TV and Google TV models from 2015 onward. The remote reads the TV's supported methods, inputs, apps and remote keys at runtime, so it only shows what your TV can do.

## Will it work on my TV?

Two things decide it. The Remote speaks Sony's own API, so it needs a BRAVIA. Home is an Android app that needs Android 9 or newer, Android TV's `leanback` feature and `adb` to set it up, so it needs Android TV or Google TV.

| Your TV | Remote | Home |
|---|---|---|
| Sony BRAVIA on Android 9 or newer | Yes | Yes, but only the A80J is tested |
| Sony BRAVIA on Android 7 or 8 (mostly 2015 to 2016) | Should work | No: it won't install below Android 9 |
| Another brand on Android TV or Google TV (TCL, Xiaomi, Philips, Hisense and others) | No | Untested, see [Other Android TV brands](#other-android-tv-and-google-tv-brands) |
| Samsung (Tizen) or LG (webOS) | No | No, see [Samsung and LG](#samsung-and-lg) |
| Roku, Vizio, Hisense VIDAA | No | No: they aren't Android |
| Amazon Fire TV | No | No: Fire OS [keeps its own home screen](https://cleanyour.tv/tvs) |

[cleanyour.tv](https://cleanyour.tv/tvs) is a good way to look up what your model runs: it lists 427 community-tested Android TV and Google TV models with their Android versions. Being on that list means another project's cleanup works there, not that Blacklevel has been tried. Hisense sells TVs on Google TV, VIDAA and Roku, so check yours.

### Checks that change nothing

Check the software first: **Settings → System → About** on Android TV and Google TV. If that settles it, stop there. Otherwise, these only read from the TV.

Does it have the BRAVIA API? This call needs no key, and answers with the model name:

```bash
curl -s -m 5 http://<tv-ip>/sony/system -d '{"method":"getInterfaceInformation","id":1,"params":[],"version":"1.0"}'
```

Could it run Home? This needs network debugging on ([TV setup](tv-setup.md#3-network-debugging-for-blacklevel-home-optional-for-the-remote)), which is a change to the TV, so that's your call. Then:

```bash
adb connect <tv-ip>:5555
adb shell getprop ro.build.version.sdk
adb shell pm list features | grep leanback
adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME
```

The first number needs to be 28 or higher, `android.software.leanback` needs to be listed, and the last line names the launcher that holds the Home button now.

### Samsung and LG

Neither can run Blacklevel today, and there's no setting that changes that. They aren't Android: there's no `adb`, no APK install and no BRAVIA API, so neither app has anything to connect to. Bringing them in would mean new clients, not fixes:

| | LG (webOS) | Samsung (Tizen) |
|---|---|---|
| Remote | Possible on the LAN. webOS has a local API on port 3001 ([`lgtv2`](https://github.com/hobbyquaker/lgtv2) documents it) covering volume, inputs, apps, text entry and media keys, after you accept a prompt on the TV | Partly. The local socket on port 8002 ([`samsung-tv-ws-api`](https://github.com/xchwarze/samsung-tv-ws-api)) sends keys and lists and opens apps. [Community integrations](https://github.com/ollo69/ha-samsungtv-smart) use Samsung's SmartThings cloud to read the current source, which Blacklevel's local-only rule doesn't allow |
| Home | Needs a rooted TV. Without root an app can't take the Home button | Possible but fragile. It needs Developer Mode, and on 2024 and later TVs a certificate from a Samsung account. Taking the Home button relies on an undocumented setting |

Other people have built home screens for these. Blacklevel hasn't tested or reviewed them, and they go further into the TV than Blacklevel does, so read what each one changes first: [AeroTizen](https://github.com/helalaou/AeroTizen/wiki) for Samsung (2020 and later, no root; its native Home mode is experimental), and [CleanYourTV for webOS](https://github.com/lasharor/cleanyourtv-WebOS/wiki) or [TheBoringTV](https://github.com/theboringhumane/theboringtv-lgwebos/wiki) for LG (rooted TVs, see [webosbrew](https://www.webosbrew.org/rooting/)). If you only want less tracking, cleanyour.tv's [non-Android guide](https://cleanyour.tv/not-android) goes through the settings for each brand.

Checked in November 2026. These change with firmware, and none of it has been tried on a real Samsung or LG TV for this page. If you've found otherwise, please [send a report](#reporting).

### Other Android TV and Google TV brands

The Remote won't connect: it's the BRAVIA API or nothing. Home is plain Android apart from one thing, so it may well run, but nobody has tried it. What to expect:

- **App row**: other brands' bundled apps will show up, because Home only hides Sony's and Google's.
- **HDMI row**: inputs have to be labelled "HDMI 1" and so on, or they're left out. Device names come from Sony's API where there is one, and fall back to Android's own.
- **Home button**: the [install steps](../launcher/README.md#install) disable two Google packages, found on the A80J. Other launchers will have other names, and vendors can add their own, so don't copy those commands onto another brand's TV.

Home can be tried without touching the Home button, since it also opens like any other app:

```bash
adb install -r BlacklevelHome-<version>.apk
```

Open **Blacklevel** from the TV's app list and check the app and HDMI rows. Press Home to leave. If the TV asks which home screen to use, pick the usual one. Remove it again with:

```bash
adb uninstall io.github.itsonlyjames.blacklevel
```

## Tested

| Model | Year | Software | Remote | Home |
|---|---|---|---|---|
| Sony XR-65A80J | 2021 | Google TV (Android 12) | Everything | Everything, with the extra launcher steps in [Install](../launcher/README.md#install) |

## Testing on another TV

If you have a different BRAVIA, a report of what worked and what didn't is the most useful thing you can send. Start with the Remote: it changes nothing on the TV beyond turning on IP control.

1. **Set up the TV and the Remote** as in [TV setup](tv-setup.md) and the [Quick start](../README.md#quick-start), and check the Remote finds the TV.
2. **Run the self-test.** It calls each API the menu uses with the address and key from the Remote's Settings, and prints one line per check. Nothing disruptive runs: no power, no switching to other inputs, no app launches or navigation keys; volume and settings it touches are put straight back.

   ```bash
   /Applications/BlacklevelRemote.app/Contents/MacOS/BlacklevelRemote --selftest
   ```

3. **Try the menu**: power, volume, inputs, apps, the D-pad and playback keys, picture and sound settings, text entry and screenshots. Note anything missing, greyed out or doing the wrong thing.
4. **Home (optional).** Installing it means disabling Google TV's own launcher, so read [Install](../launcher/README.md#install) and [Revert to the stock home screen](../launcher/README.md#revert-to-the-stock-home-screen) first. Then check the app and input rows, Customise, the Home button from other apps and inputs, and that it survives a reboot.

## Reporting

[Open a TV report](https://github.com/itsonlyjames/blacklevel/issues/new?template=tv-report.yml), whether or not it worked. It asks for:

- The model number (on the TV: **Settings → System → About**) and its software version
- What worked, what didn't, and anything that behaved differently from the README
- The self-test output and the results of any checks above, with the TV's MAC address and IP address removed

Reports are public, so leave out serial numbers, keys, and network or account names too. An agent can write one with the same headings and, once you've read it and said yes, post it:

```bash
gh issue create --repo itsonlyjames/blacklevel --title "TV report: <brand> <model>" --body-file report.md
```

Differences that turn up get written into this page, so the next person with that model knows what to expect.
