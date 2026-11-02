# Changelog

What changed in each version of Blacklevel Home (the TV launcher) and Blacklevel Remote (the Mac menu bar app). The full notes for each release, with downloads and how to update, are on [GitHub Releases](https://github.com/itsonlyjames/blacklevel/releases) and in `release/<version>/NOTES.md`.

## 1.4.0

### Blacklevel Home (TV)

- **Added:** a word clock for when the home screen's left alone. The time to the nearest five minutes in warm lit words on a fixed grid of letters ("IT IS TWENTY FIVE TO SEVEN"), the unlit letters barely there; words fade across slowly when the time changes. Any button brings the home screen back as you left it, and that press does nothing else. Set it up in **Customise → Idle**: dim or word clock, after 1, 5 or 15 minutes, minute dots, brightness, and **Show now**.
- **Added:** Google's screensaver (ambient mode) no longer starts over the home screen, so the word clock or the dim stays up. **Customise → Idle → Google screensaver → As set on the TV** brings it back. Other apps keep it either way.
- **Added:** Tiles, a third way to show the app row (**Customise → Apps → Show as**): each app's icon as a rounded square with its name in small capitals beneath, the focused one lifted.
- **Added:** Atmosphere. The room behind the home screen takes on a soft light from the app you're on, and the focus line takes the app's colour. Set the **Light** and its **Strength** in **Customise → Atmosphere**.
- **Changed:** Home and Customise, and the names in the icons' headline, now take turns instead of crossfading, so their words never sit over each other. The focused app name steps forward a touch.
- **Changed:** the idle delay moved from **Customise → Screen → Dim when idle** to **Customise → Idle → After**. Your choice carries over.
- **Fixed:** pressing Home while already on the home screen replayed the whole entrance. Now it just goes back to the first app, closing Customise if it's open.
- **Fixed:** going Home from an HDMI input could flash the input ("SHIELD HDMI 2") as now playing for a moment. The TV's own input player is left out of now playing, since it only plays while it's on screen.

## 1.3.0

Now playing across from the clock, apps as icons, Customise in sections, calmer motion. The Mac remote highlights the input on screen.

## 1.2.1

The inputs row updates as HDMI devices come and go; the Mac remote's text boxes let go when you're done typing.

## 1.2.0 and earlier

See [GitHub Releases](https://github.com/itsonlyjames/blacklevel/releases).
