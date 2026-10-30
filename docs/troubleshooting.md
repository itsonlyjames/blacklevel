# Troubleshooting

## adb says "offline", "unauthorized" or "no route to host"

```bash
adb kill-server
adb start-server
adb connect <tv-ip>:5555
```

If it says `unauthorized`, look at the TV: there's an **Allow USB debugging?** prompt waiting. If the TV was in standby, wake it first; network ADB doesn't answer while it's asleep.

## The Home button still opens Google TV's home screen

Google TV's launcher takes priority over other home apps. Disable it (reversible, see [Reverting](../launcher/README.md#revert-to-the-stock-home-screen)):

```bash
adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
```

## The remote shows the TV but buttons do nothing

- Check that **Settings…** in the remote has the same pre-shared key as the TV, then click **Test Connection**.
- On the TV, check **IP control → Authentication** is **Normal and Pre-Shared Key**, not **Normal**.
- macOS may have blocked local network access. **System Settings → Privacy & Security → Local Network**, and turn on Blacklevel Remote.

## The remote can't turn the TV on

Turn on **Remote start** in the TV's IP control menu. For Wake-on-LAN, the remote needs the TV's MAC address: click **Detect** in **Settings…** while the TV is on, or type it in.

## Screenshots fail

Some models list `system.getScreenshot` but answer "Unsupported Operation" (the A80J does). The remote then falls back to `adb exec-out screencap`, which needs `adb` installed and network debugging on.

## Self-test

The remote has a built-in check that runs every API call against your TV and prints what passed:

```bash
menubar/build/BlacklevelRemote.app/Contents/MacOS/BlacklevelRemote --selftest
```
