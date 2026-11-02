# StayPut: theft alarm for MacBooks

StayPut is a small menu bar app for Apple Silicon MacBooks. Before you leave your MacBook in a library or café, turn it on. StayPut covers the screen with a lock screen and watches the built-in motion sensor, the lid-angle sensor and the lid switch.

| What happens | Reaction |
|---|---|
| Slightly moved (pushed aside on the desk) or display angle changed | Yellow warning on screen, **no sound** |
| Moved more (lifted, tilted, carried, ~1 s of continuous movement) | Red flashing alarm screen **+ siren** |
| Lid closed | Siren |
| Lid opened again | Warning on screen |
| Mac put to sleep (e.g. power button) | Siren |

The siren stops by itself after the time you set (default 30 s). If the MacBook keeps being moved, it starts again.

## Install

1. Copy `StayPut.app` to **Applications**.
2. Open it. The app isn't notarized by Apple, so the first time macOS blocks it. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Alternatively, run this once in Terminal:
   ```
   xattr -dr com.apple.quarantine /Applications/StayPut.app
   ```
3. A shield icon appears in the menu bar. The Settings window opens on first launch.

## Use

- **Turn on:** press **⌃⌥⌘L** (Control-Option-Command-L), or click the shield in the menu bar and choose **Protect This MacBook**. Protection starts after a short countdown (default 5 s).
- **Turn off:** just put your finger on the Touch ID sensor. Touch ID is ready the whole time the lock screen is up. Or press the shortcut (or any key, or click **Use password**) and type your Mac password. A thief who learns the shortcut still can't turn it off. If you switch off "Require Touch ID or password", the shortcut turns protection off immediately.
- While armed, the Dock, menu bar, ⌘-Tab, Force Quit and log-out are blocked, and StayPut can't be quit.

## Settings

- **Keyboard shortcut**: click it and type a new one.
- **Require Touch ID or password to turn off**: on by default.
- **Start delay**: seconds before monitoring starts.
- **Keep the lock screen visible**: prevents the display from sleeping while armed.
- **Motion sensitivity**: 1–10, with a live meter. Nudge the MacBook while Settings is open to see where the warning (orange) and siren (red) levels are.
- **Siren on/off, volume, how long it plays, Test sound**
- **Unmute the Mac and use this volume during the alarm**: otherwise a muted Mac would stay silent. Your volume is restored afterwards.
- **Keep running when the lid is closed**: see below.
- **Open at login**

## Lid closed: important

macOS puts a MacBook to sleep when the lid closes, and sleeping apps can't make sound. StayPut handles this in two ways:

- **Default:** when the lid closes, StayPut starts the siren and holds off sleep while it plays. macOS forces sleep after about 25–30 seconds.
- **"Keep running when the lid is closed" on:** each time you turn protection on, macOS asks for your admin password once. StayPut then runs `pmset disablesleep 1`, so the Mac stays awake with the lid closed and the siren plays for its full time. Sleep is switched back on automatically when you turn protection off, or if StayPut quits or crashes.

## Compatibility

- Tested on a MacBook Pro M2 Max running macOS 27.
- Should work on all Apple Silicon MacBooks (M1–M4 and newer) with macOS 13 or later. The motion sensor and lid-angle sensor are read through undocumented interfaces. Some models (reportedly some M1 machines) may lack the lid-angle sensor. StayPut then falls back to the lid switch and doesn't detect display-angle changes. Settings shows which sensors were found.
- Intel Macs and desktop Macs (no motion sensor) are not supported.

## Limits

StayPut is a deterrent, not a vault. Holding the power button for 10 seconds forces a shutdown, and nothing in software can prevent that. Keep **Find My Mac** turned on as well.

## Build from source

Requires Xcode or the Command Line Tools (`xcode-select --install`):

```
./build.sh
```

The app is written to `build/StayPut.app`. `./build.sh appstore` builds the sandboxed Mac App Store version; see `AppStore/APP_STORE.md`. Sources are in `Sources/`:

| File | Purpose |
|---|---|
| `Sensors.swift` | Accelerometer and lid-angle readers |
| `GuardController.swift` | Detection logic: warning vs. alarm |
| `Overlay.swift` | Lock screen |
| `Alarm.swift` | Siren and system volume |
| `Power.swift` | Sleep handling |
| `HotKey.swift` | Shortcut and Touch ID |
| `SettingsView.swift` | Settings window |
