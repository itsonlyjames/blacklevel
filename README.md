# Blacklevel

**Take your Sony TV back. It's just a TV.**

Blacklevel replaces the busy parts of a Sony BRAVIA Google TV with quiet ones: a dark, typographic home screen with no ads or recommendation rows, and a native macOS menu bar remote. No accounts, no cloud, no third-party code. Everything talks to the TV over your local network.

<p align="center">
  <img src="docs/images/home-apps.png" alt="Blacklevel Home: the time, one row of apps, one row of HDMI inputs" width="720">
</p>

## What's in the box

| | Runs on | What it is |
|---|---|---|
| **[Blacklevel Home](launcher/)** | The TV (Android TV / Google TV) | A replacement home screen. The time, one row of your apps, one row of your HDMI inputs, and Settings. Nothing else. Built for OLED: dark, dims when idle, drifts to avoid burn-in. ~128 KB. |
| **[Blacklevel Remote](menubar/)** | macOS 14+ | A SwiftUI menu bar remote: power, volume, inputs, apps, D-pad, playback, picture and sound settings, text entry, screenshots. Uses Sony's BRAVIA REST API and IRCC codes. |

<p align="center">
  <img src="docs/images/remote-menu.png" alt="Blacklevel Remote menu bar window" width="340">
</p>

## Quick start

1. **Prepare the TV**: turn on IP control with a pre-shared key, and (for Home) network debugging. See [TV setup](docs/tv-setup.md).
2. **Remote**: `cd menubar && ./build.sh && open build/BlacklevelRemote.app`, then enter the TV's address and key in **Settings…**. [More](menubar/README.md)
3. **Home**: `cd launcher && ./build.sh`, then install and set it as the home screen with `adb`. [More](launcher/README.md)

Both parts are independent. Use either, or both.

## Compatibility

Developed and tested on a **Sony XR-65A80J** (2021, Google TV). It should work on other BRAVIA TVs that expose the BRAVIA REST API ("IP control"), which covers most Sony Android TV and Google TV models from 2015 onward. The remote reads the TV's supported methods, inputs, apps and remote keys at runtime, so it only shows what your TV can do.

If you try it on another model, please open an issue with what worked and what didn't.

## Documentation

- [TV setup](docs/tv-setup.md): IP control, pre-shared key, remote start, network debugging
- [Blacklevel Home](launcher/README.md): build, install, customise, revert
- [Blacklevel Remote](menubar/README.md): build, run, feature list
- [Troubleshooting](docs/troubleshooting.md)

## Building from source

No Gradle, no Xcode project, no dependencies to fetch.

- **Home** needs `openjdk@17`, `kotlin`, and Android SDK `platforms;android-34` + `build-tools;34.0.0`.
- **Remote** needs Swift 5.9+ (Xcode Command Line Tools) on macOS 14 or later.

## License

[MIT](LICENSE). The bundled fonts (Hanken Grotesk, Instrument Serif) are under the [SIL Open Font License](launcher/app/assets/fonts/OFL.txt).

Blacklevel is an independent project and is not affiliated with, endorsed by, or sponsored by Sony Group Corporation or Google LLC. Sony and BRAVIA are trademarks of Sony Group Corporation. Google TV and Android TV are trademarks of Google LLC.
