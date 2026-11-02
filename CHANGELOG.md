# Changelog

What changed in each version of Blacklevel Home (the TV launcher) and Blacklevel Remote (the Mac menu bar app). The full notes for each release, with downloads and how to update, are on [GitHub Releases](https://github.com/itsonlyjames/blacklevel/releases) and in `release/<version>/NOTES.md`.

## Unreleased

### Blacklevel Home (TV)

- **Added:** a word clock for when the home screen's left alone. The time to the nearest five minutes in warm lit words on a fixed grid of letters ("IT IS TWENTY FIVE TO SEVEN"), the unlit letters barely there; words fade across slowly when the time changes. Any button brings the home screen back as you left it, and that press does nothing else. The letters are drawn at the panel's full resolution (4K on the A80J), not the 1080p the rest of Android uses. Set it up in **Customise → Idle**: dim or word clock, after 1, 5 or 15 minutes, minute dots, brightness, and **Show now**.
- **Changed:** the idle delay moved from **Customise → Screen → Dim when idle** to **Customise → Idle → After**. Your choice carries over.
- **Fixed:** pressing Home while already on the home screen replayed the whole entrance. Now it just goes back to the first app, closing Customise if it's open.
- **Fixed:** going Home from an HDMI input could flash the input ("SHIELD HDMI 2") as now playing for a moment. The TV's own input player is left out of now playing, since it only plays while it's on screen.

## 1.3.0

Now playing across from the clock, apps as icons, Customise in sections, calmer motion. The Mac remote highlights the input on screen.

## 1.2.1

The inputs row updates as HDMI devices come and go; the Mac remote's text boxes let go when you're done typing.

## 1.2.0 and earlier

See [GitHub Releases](https://github.com/itsonlyjames/blacklevel/releases).
