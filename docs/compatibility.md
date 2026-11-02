# Compatibility

Blacklevel is developed and tested on one TV. It should work on other BRAVIA TVs that expose the BRAVIA REST API ("IP control"), which covers most Sony Android TV and Google TV models from 2015 onward. The remote reads the TV's supported methods, inputs, apps and remote keys at runtime, so it only shows what your TV can do.

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

[Open an issue](https://github.com/itsonlyjames/blacklevel/issues/new) with:

- The model number (on the TV: **Settings → System → About**) and its Android or Google TV version
- The self-test output, with the TV's MAC address and IP address removed
- What worked, what didn't, and anything that behaved differently from the README

Differences that turn up get written into this page, so the next person with that model knows what to expect.
