# logi-ondemand

Run **Logi Options+** on macOS only while a Logitech mouse or keyboard is actually connected.

Logi Options+ keeps its agent and updater running in the background at all times, even when no Logitech
device is around, and can use noticeable CPU and battery while idle. If you only use your Logitech mouse
sometimes (e.g. at a desk), `logi-ondemand` starts Options+ when the device connects and stops it again
after it disconnects. While no Logitech device is connected, **nothing runs at all**.

[한국어 README](README.ko.md)

## How it works

- `launchd` watches for a Logitech (`VendorID 0x046D`) mouse/keyboard to appear in IOKit
  (`LaunchEvents` / `com.apple.iokit.matching`). This costs nothing while you wait.
- When one connects over **USB** (incl. Bolt/Unifying receivers) or **Bluetooth**, `launchd` starts the
  small `logi-watch` helper, which starts Options+ immediately.
- While the device stays connected, `logi-watch` sleeps on IOKit callbacks (≈12 MB, 0% CPU).
- When the last Logitech device has been gone for 10 minutes (configurable), it stops Options+ and exits.
  The grace period keeps Bluetooth mice that briefly sleep from toggling Options+ on and off.
- Virtual HID devices and Logitech webcams are ignored.

No sudo, no changes to Logitech's files.

## Modes

| | `./install.sh` (event) | `./install.sh --light` | `./install.sh --polling` |
|---|---|---|---|
| Nothing Logitech connected | nothing runs | nothing runs | 10 ms check every 20 s |
| Device connects | Options+ starts at once | Options+ starts at once | starts within 20 s |
| While connected | helper waits (≈12 MB, 0% CPU) | **nothing runs** | 10 ms check every 20 s |
| Options+ stops | 10 min after last disconnect | on next **sleep/wake** with no device | 10 min after last disconnect |
| Needs | swiftc | swiftc | nothing |

**Light mode** fits the usual laptop pattern: plug in or pair the mouse when you need it and use it until
you close the lid. `launchd` runs the helper for a fraction of a second on login, on device arrival and on
every sleep/wake transition (`com.apple.powermanagement.systempowerstate`); it starts Options+ if a
Logitech device is connected, otherwise stops it, and exits. If you switch the mouse off without sleeping
the Mac, Options+ keeps running until the next sleep (or `logi off`).

Without the Swift compiler, `./install.sh` falls back to polling mode automatically. Re-run `install.sh`
with another option to switch modes.

## Install

Event and light modes need Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/skel-0216/logi-ondemand.git
cd logi-ondemand
./install.sh
```

This builds `logi-watch`, installs it and `logi` to `~/.local/bin` (override with `PREFIX=/some/dir`),
and loads the watcher. If `~/.local/bin` is not on your `PATH`, add this to `~/.zshrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Then turn off Logitech's own auto-start**, otherwise macOS keeps launching Options+ at login:

System Settings → General → Login Items & Extensions → *Allow in the Background* → turn off **Logitech** /
**Logi Options+**. `logi status` warns you if it is still on.

Optional: the updater still runs whenever Options+ runs. To stop macOS from launching it on its own:

```bash
sudo launchctl disable system/com.logi.optionsplus.updater
```

(Undo with `sudo launchctl enable system/com.logi.optionsplus.updater`. Update Options+ manually from its app.)

## Usage

```
logi status   # mode, connected devices, whether Options+ is running
logi auto     # automatic mode (default)
logi on       # start now and keep running (pauses auto mode)
logi off      # stop now and keep stopped (pauses auto mode)
logi log      # recent connect/disconnect and start/stop events
```

Basic mouse/keyboard input works without Options+; only custom buttons, gestures, smooth scrolling and
similar extras need it, so they become available a moment after the device connects.

## Configuration

`~/.config/logi-ondemand/config` (shell syntax):

```bash
GRACE_MINUTES=10   # minutes to keep Options+ running after the last device disconnects
```

## Uninstall

```bash
./uninstall.sh
```

Then re-enable Logitech in Login Items if you want the default behavior back.

## Notes

- Developed on macOS 27 (Apple Silicon) with Logi Options+. Should work on macOS 13+.
- Logs: `~/Library/Logs/logi-ondemand.log`. State: `~/Library/Application Support/logi-ondemand/`.
- Not affiliated with Logitech.

## License

MIT
