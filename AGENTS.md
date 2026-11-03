# Working on Blacklevel

Instructions for coding agents (Claude Code, Codex, Cursor and the like) and for anyone else changing the code. This repo is small and dependency-free on purpose, which makes it easy to hand to an agent. Read this first, then the README for the part you're changing.

## Orientation

- `launcher/`: Blacklevel Home. Kotlin `HomeActivity.kt` hosts a WebView; the whole UI is `app/assets/index.html`. Built by `build.sh` with `kotlinc`, `d8` and `aapt2`; no Gradle. Design intent lives in `launcher/.impeccable.md`; read it before touching the UI.
- `menubar/`: Blacklevel Remote. A Swift package: `BraviaClient.swift` (REST + IRCC), `TVStore.swift` (state), `Views.swift` (SwiftUI), `Support.swift` (keychain, helpers), `SelfTest.swift`. Built by `build.sh`; no Xcode project.
- `icons/`: `make-icons.swift` draws the Remote's `AppIcon.icns` and Home's TV banner from one source; run it with `swift icons/make-icons.swift` and commit what it writes. The menu bar icon is drawn in code (`MenuBarIcon` in `Views.swift`) to match.
- `docs/`: user-facing setup, troubleshooting and compatibility. `docs/images/` holds the screenshots used in READMEs.

## Ground rules

- No new dependencies, package managers, build systems or network services. Everything talks to the TV on the LAN. The one exception is the update check against GitHub Releases (`Updater.swift`, and `checkUpdate`/`installUpdate` in `HomeActivity.kt`); keep it the only one, and keep it switchable. If you change what either app talks to, update [What talks to what](README.md#what-talks-to-what).
- Keep the launcher OLED-safe: dark backgrounds, no large static bright areas, keep the idle dimming and drift. D-pad navigation must keep working.
- Don't hard-code a model's capabilities. Ask the TV (supported methods, inputs, apps, remote keys) and hide what it doesn't support. Model-specific quirks go in [docs/compatibility.md](docs/compatibility.md).
- Never commit secrets: the pre-shared key lives in the macOS keychain, `*.keystore` is ignored, and TV IPs belong in settings, not source.
- Match the surrounding code's style and comment density. Small, focused changes.
- Commit messages use conventional prefixes (`feat:`, `fix:`, `docs:`, `chore:`), as in the existing history.

## Checking your work

- Remote: `cd menubar && ./build.sh`, then `build/BlacklevelRemote.app/Contents/MacOS/BlacklevelRemote --selftest` to run every API call against a real TV (non-disruptive), and `--snapshot menu.png` to render the menu to an image for visual review.
- Home: `cd launcher && ./build.sh`, install with `adb`, and check it on the TV with a D-pad. `index.html` can also be opened in a desktop browser for layout work.
- If a change alters what the user sees, update the matching screenshot in `docs/images/` and the README that describes it.
