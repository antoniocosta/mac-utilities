# Mac Utilities

Small double-click macOS utilities, each an Automator app with its source kept
next to it as a plain script, so it can be read, diffed and rebuilt without opening
Automator.

| Utility | What it does |
|---|---|
| [Laptop Display Toggle](#laptop-display-toggle) | Use an external monitor with the MacBook lid open and its screen off, so Touch ID stays within reach. |
| [Wacom Restart Driver](#wacom-restart-driver) | Brings a frozen Wacom tablet driver back to life in about a second. |
| [Adobe Spyware Killer](#adobe-spyware-killer) | Stops all of Adobe's background processes and keeps them from coming back, without touching the Adobe apps you have open. |

Tested on macOS 26 (Tahoe), Apple silicon.

## Install

Copy the `.app` anywhere (e.g. `~/Applications`) and double-click it. The apps are
signed ad hoc, not notarized. If you downloaded them, macOS may block the first launch:
right-click → **Open**, or run `xattr -dr com.apple.quarantine "<Utility>.app"`.

Git does not keep the extended attributes that hold part of an Automator app's ad-hoc
signature, so after a clone `codesign -v` reports the app as modified. The apps still
open normally; to re-seal one, run `python3 build.py` in its folder.

---

## Laptop Display Toggle

Turns the MacBook's built-in display and keyboard backlight off while the lid stays
open, so you can work on an external monitor and still use Touch ID.

### Why

With an external monitor, the usual setup is clamshell mode: lid closed, laptop out of
the way. But closing the lid also disables the Touch ID sensor, so you are back to
typing your password for every unlock, `sudo` and payment. Apple's fix is a separate
Magic Keyboard with Touch ID: expensive, and it has no backlight. This app keeps the
lid open and the built-in screen off instead, so Touch ID stays one finger away.

### What it does

| | Lid closed + monitor | This app (lid open) |
|---|---|---|
| Built-in display | off | off |
| Touch ID | disabled | available |
| Keyboard backlight | off | off (brightness and auto-brightness restored afterwards) |
| Microphone / camera | mic cut in hardware / camera covered | unchanged (not touched) |
| Monitor unplugged | Mac sleeps | built-in display (and backlight) back on at once |
| Cooling | worse | better |

### Usage

With an external display connected, double-click the app: the built-in display and
keyboard backlight turn off. Double-click again (or unplug the monitor) to bring them
back. An alert lists what changed each time. Without an external display it refuses,
so you can never end up with no screen at all.

<img src="Laptop%20Display%20Toggle/screen.png" alt="Laptop Display Toggle alert after turning the built-in display off" width="520">

### How it works

Python + ctypes inside the shell step, using the system `/usr/bin/python3`.

- **Display:** the private `CGSConfigureDisplayEnabled` (SkyLight), applied *for the
  session only*: logging out or rebooting always brings the built-in display back.
- **Keyboard backlight:** the private `KeyboardBrightnessClient` (CoreBrightness, as
  used by Control Center). Brightness and auto-brightness are saved and restored.
- **Watcher:** while the built-in display is off, a detached background process waits
  for macOS's display-change event (`CGDisplayRegisterReconfigurationCallback`).
  - Per Apple's Quartz Display Services guide, that event only arrives for changes made
    by others (e.g. unplugging) while the process "is listening for events". So the
    watcher runs an invisible `NSApplication` event loop.
  - It watches the IDs of the external displays connected at turn-off. After the last
    monitor is unplugged, macOS adds a placeholder "external" display (vendor `unkn`,
    model `virt`), so "any external display connected" is not a usable test.
  - A re-check every 30 s is the safety net.
  - When it turns the display back on, it reopens the app to show the alert, then exits.

### Notes

- **Files:** log at `~/Library/Logs/LaptopDisplayToggle.log`. State in
  `~/Library/Caches/laptop-display-*`: built-in display ID, watched external IDs,
  keyboard backlight state, pending alert message.
- **Private APIs:** both the display call and the keyboard call are private, so a macOS
  update could break them (the log will show it).
- **Icon:** the MacBook Pro icon from `CoreTypes.bundle`, copied in by the build script.

## Wacom Restart Driver

Restarts a frozen Wacom tablet driver in about a second, without logging out or
rebooting.

### Why

The Wacom driver regularly freezes, especially after the tablet is reconnected or
the Mac restarts, and the pen simply stops responding. Until Wacom makes its driver
and software reliable, this app forces the driver back to life.

### Usage

Double-click the app when the tablet stops responding. An alert confirms the restart and
stays until you click OK; if the driver did not come back, it shows a critical alert.
Needs the Wacom driver ("Wacom Tablet" in System Settings).

<img src="Wacom%20Restart%20Driver/screen.png" alt="Wacom Restart Driver alert after a restart" width="300">

### How it works

It uses launchd and the driver's own launch agents in `/Library/LaunchAgents`:

1. Kills the per-device drivers (`WacomTabletDriver`, `WacomTouchDriver`): SIGTERM,
   then SIGKILL if they don't quit (a hung process may not).
2. Runs `launchctl kickstart -k` on the launch agents:
   - `com.wacom.DataStoreMgr` (settings store);
   - `Wacom_IOManager` (talks to the hardware);
   - `com.wacom.wacomtablet` (TabletDriver, which relaunches the per-device drivers).
3. Waits up to 10 s until `WacomTabletDriver` runs again.

### Notes

- **No `tell application`:** the app never uses AppleScript `tell application`, which
  can hang for minutes on an unresponsive driver.
- **Running it twice:** launchd throttles `com.wacom.wacomtablet` to one start every 15 s,
  so a second run right after the first is slower.
- **Icon:** the "Wacom Tablet" settings-pane icon
  (`/Library/PreferencePanes/WacomTablet.prefpane/Contents/Resources/Professional.icns`),
  copied in by the build script. Building therefore needs the Wacom driver installed.

## Adobe Spyware Killer

Stops every Adobe background process and keeps it from starting again, while leaving
the Adobe apps you actually opened (Photoshop, Illustrator, After Effects, Premiere Pro,
Acrobat...) alone.

### Why

Installing any Adobe app also installs a crowd of background processes: Creative Cloud
and its helpers, sync, "genuine software" checks, updaters, crash reporters, content
and telemetry services. They start at login, on timers and from each other, and come
back when you quit them. None of that should run unless you open an Adobe app.

### Usage

Double-click the app. An alert lists what was stopped and what was kept from starting
again. When root-owned Adobe processes or daemons need stopping, macOS asks for an
administrator password (only then).

**Undo:** hold **Option** while opening the app. It re-enables exactly what it disabled
(recorded in `~/Library/Application Support/Adobe Spyware Killer/disabled.txt`).

<img src="Adobe%20Spyware%20Killer/screen.png" alt="Adobe Spyware Killer alert after stopping Creative Cloud and its helpers" width="520">

### How it works

1. **launchd:** every Adobe launch agent (`/Library/LaunchAgents`,
   `~/Library/LaunchAgents`, and `com.adobe.*` entries in launchd's overrides) is
   disabled (`launchctl disable`, survives reboots) and booted out. Root daemons that
   start by themselves (`RunAtLoad`, `StartInterval`, `KeepAlive`,
   `StartCalendarInterval`; here the Adobe Genuine Software Integrity Service) get the
   same in the system domain. On-demand helpers (`MachServices` only, such as the
   installer helper) stay registered: they only start when an app you opened asks.
2. **Finder extension:** Core Sync's Finder Sync extension is set to "ignore" in
   `pluginkit`, so Finder stops relaunching it.
3. **Processes:** everything running from Adobe's background locations is killed
   (SIGTERM, then SIGKILL), round after round, until nothing respawns:
   `/Applications/Utilities/Adobe *`, `/Applications/Adobe Creative Cloud/`,
   `/Library/Application Support/Adobe/`, `~/Library/Application Support/Adobe/`,
   `/Library/PrivilegedHelperTools/com.adobe.*` and Adobe temp folders.
   Matching by location rather than by name catches new helpers Adobe adds.
4. **Your apps:** inside `/Applications/Adobe <App>/` the apps themselves are never
   touched. Their bundled helpers are spared while that app runs, and killed if they
   linger after it quit (e.g. Acrobat's `AdobeResourceSynchronizer`).
   `AdobeIPCBroker` is also left alone while any Adobe app is open: Photoshop relaunches
   it within 1-3 s of it being killed (it is how the apps talk to Adobe's services), so
   it is stopped once the apps quit.
5. **Check:** 3 s later it scans again and reports anything that came back.

Seen on this Mac (Creative Cloud 2026, Photoshop, Illustrator, After Effects, Animate,
Media Encoder, Acrobat):

| Process / job | What it is | How it started |
|---|---|---|
| Creative Cloud (+ UI Helpers) | Creative Cloud app | `com.adobe.AdobeCreativeCloud` agent, at login |
| Creative Cloud Helper | menu bar / update helper | Adobe Desktop Service |
| Adobe Desktop Service | CC backend: licensing, installs, IPC | Creative Cloud |
| AdobeIPCBroker | message bus between Adobe processes | ADS or any Adobe app |
| Core Sync, ACCFinderSync | file/library/font sync, Finder badges | ADS; Finder (pluginkit) |
| Creative Cloud Content Manager.node (CCXProcess) | in-app "Discover"/marketing content | `com.adobe.ccxprocess` agent, at login |
| CCLibrary | Creative Cloud Libraries backend | `com.adobe.CCLibrary` |
| agcinvokerutility, AdobeGCClient | "genuine software" check | `com.adobe.GC.Scheduler-1.0` agents, at login and daily |
| AGSService | Genuine Software Integrity Service (root) | daemon, at boot and every 6 h |
| Acrobat Update Helper | Acrobat updater | `com.adobe.ARMDCHelper.*` agent, at login and every 3.5 h |
| Adobe Crash Processor | crash report uploader | Adobe processes |
| com.adobe.acc.installer.v2, Adobe Installer | installer helpers (root) | on demand |

### Notes

- **Log:** `~/Library/Logs/AdobeSpywareKiller.log`.
- **Dry run:** `bash app.sh list` (in the app's folder) shows what it would stop and
  disable, without doing anything.
- **Opening Creative Cloud yourself** still works (disabling a launch agent only stops
  it starting by itself); it just doesn't start at login any more. Run the app again
  afterwards to clear it out.
- **Icon:** the Creative Cloud app icon with a red "prohibited" sign, drawn by
  `make_icon.swift` when the build script runs (needs `swift`, from the Command Line Tools).

---

## Development

### Layout

One folder per utility:

```
<Utility>/
  <Utility>.app   the app (Automator: "Run Shell Script" -> "Run AppleScript")
  screen.png      screenshot of its alert (for this README)
  app.sh          the app's code: source of the "Run Shell Script" step
  build.py        writes app.sh (and the alert step and icon) into the app, re-signs it
```

Each app has two steps: the shell script does the work and prints a message, and an
AppleScript `display alert` shows it. Because the app itself shows the alert, it
carries the app's icon.

### Edit and rebuild

1. Edit `app.sh`. You can test it without the app: `bash app.sh`.
2. Run `python3 build.py` in that folder. It rebuilds the app in place
   (keeping its stub and `Info.plist`) and signs it ad hoc
   (`codesign --force --deep --sign -`).

You can also edit the app in Automator, but then copy the script back into `app.sh`,
or the next build will undo your change. Building needs only the system
`/usr/bin/python3` and `codesign` (Xcode Command Line Tools), plus `swift` for the
Adobe Spyware Killer icon.

## License

[GPL-3.0-or-later](LICENSE). You may use, modify and share these utilities; any version
you share, modified or not, must stay under the same license, with its source.
