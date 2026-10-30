# TV setup

Blacklevel needs two things switched on in the TV's settings. Menu names below are from a 2021 Google TV BRAVIA (A80J); older Android TV models use similar wording under **Settings → Network**.

## 1. Find the TV's IP address

**Settings → Network & Internet → (your network)**. Note the IP address, e.g. `192.168.1.50`. Give the TV a fixed address (a DHCP reservation in your router) so it doesn't change.

The remote can also find the TV for you: **Settings… → Find** searches the network over SSDP.

## 2. IP control and pre-shared key (for Blacklevel Remote)

Reading the TV's state (power, volume, inputs) works without a key. Changing anything needs one.

1. **Settings → Network & Internet → Home network → IP control**.
2. Set **Authentication** to **Normal and Pre-Shared Key**.
3. Set **Pre-Shared Key** to a password of your choice. Anyone on your network with this key can control the TV, so don't reuse a password from elsewhere.
4. Turn on **Remote start** in the same menu, so the TV can be woken from standby.

The key travels in plain HTTP on your local network. That's how Sony's API works; keep the TV on a network you trust.

## 3. Network debugging (for Blacklevel Home, optional for the Remote)

Installing the home screen uses `adb` over the network.

1. **Settings → System → About**, then select **Android TV OS build** seven times until it says you're a developer.
2. **Settings → System → Developer options**: turn on **USB debugging** (on Sony models this also enables network ADB).
3. On your Mac: `brew install android-platform-tools`, then:

   ```bash
   adb connect <tv-ip>:5555
   ```

4. Accept the **Allow USB debugging?** prompt on the TV. Tick **Always allow from this computer**.

With `adb` installed, Blacklevel Remote can also send remote keys and take screenshots over ADB when no pre-shared key is set.

To undo: turn off **Developer options** (this also turns off debugging).
