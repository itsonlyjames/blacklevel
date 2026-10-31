# Blacklevel Remote

A native SwiftUI menu bar remote for Sony BRAVIA TVs. It uses Sony's BRAVIA REST API and IRCC remote codes, with no third-party code.

<img src="../docs/images/remote-menu.png" alt="Blacklevel Remote" width="340">

## Install

Download `BlacklevelRemote-<version>-macOS.zip` from [Releases](https://github.com/itsonlyjames/blacklevel/releases/latest), unzip it and move **BlacklevelRemote.app** to Applications. It's signed and notarised, so it opens like any other app. Needs macOS 14 or later; runs on Apple silicon and Intel.

## Build and run

To build it yourself instead, you need macOS 14+ and Swift 5.9+ (`xcode-select --install`). `build.sh` signs with your Developer ID if one is in your keychain, and ad hoc otherwise.

```bash
./build.sh
open build/BlacklevelRemote.app
```

A TV icon appears in the menu bar (filled when the TV is on). The first time it talks to the TV, macOS asks for Local Network access. Allow it.

Then open **Settings…**:

1. On first launch the remote searches the network and picks the first TV it finds. To choose another, enter its address or click **Find**.
2. Enter the TV's pre-shared key ([how to set one](../docs/tv-setup.md#2-ip-control-and-pre-shared-key-for-blacklevel-remote)), then **Save Key** and **Test Connection**.
3. Click **Detect** next to the MAC address so the remote can wake the TV from standby.

To start it at login, add the app under **System Settings → General → Login Items**.

The key is stored in your login keychain. The TV's address and MAC address are kept in the app's preferences.

## What it does

| Feature | API | Needs key |
|---|---|---|
| Power status, model | `system.getPowerStatus`, `getInterfaceInformation` | No |
| Volume level and mute state | `audio.getVolumeInformation` | No |
| Input list (HDMI, CEC devices) | `avContent.getCurrentExternalInputsStatus` | No |
| Picture settings (read) | `video.getPictureQualitySettings` | No |
| Remote key list | `system.getRemoteControllerInfo` | No |
| Find the TV | SSDP search for `ScalarWebAPI` | No |
| Power on/off | `system.setPowerStatus` and Wake-on-LAN | Yes (WoL doesn't) |
| Set volume, mute | `audio.setAudioVolume`, `setAudioMute` | Yes |
| Switch input | `avContent.setPlayContent` | Yes |
| Launch an app | `appControl.getApplicationList`, `setActiveApp` | Yes |
| Change picture and sound settings | `video.setPictureQualitySettings`, `audio.setSpeakerSettings` | Yes |
| Now playing | `avContent.getPlayingContentInfo` | Yes |
| D-pad, Home, Back, playback, every other remote key | IRCC SOAP at `/sony/IRCC` | Yes |
| Type into the TV's text box | `appControl.setTextForm` | Yes |
| Screenshot to Pictures | `system.getScreenshot`, or ADB | Yes (ADB doesn't) |

The remote reads the method list, inputs, apps, picture settings and remote keys from the TV at runtime, so it only shows what your TV supports.

**No key yet?** If `adb` is installed and network debugging is on, the D-pad sends keys with `adb shell input keyevent` instead. You can turn this off in Settings.

## Testing

```bash
build/BlacklevelRemote.app/Contents/MacOS/BlacklevelRemote --selftest           # run every API call against the TV, print results
build/BlacklevelRemote.app/Contents/MacOS/BlacklevelRemote --snapshot menu.png  # render the live menu to a PNG and quit
```

## Source

| File | What |
|---|---|
| `BraviaClient.swift` | JSON-RPC, IRCC and Wake-on-LAN transport |
| `TVStore.swift` | State, polling and every TV action |
| `Views.swift` | The menu and Settings window |
| `Support.swift` | Keychain, SSDP discovery, MAC lookup, ADB fallback |
| `SelfTest.swift` | `--selftest` |
