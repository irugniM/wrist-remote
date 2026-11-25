# Wrist Remote

Control a Windows 10/11 PC from a Garmin watch (the PC app is Windows only): turn slides, control media and volume, run meeting shortcuts, lock or sleep the PC. Every command is confirmed by the PC, so the watch tells you whether it actually happened.

```
watch --Bluetooth--> phone (Garmin Connect) --HTTPS--> ntfy.sh --HTTPS--> Windows tray app --> keys / volume / lock / sleep
                                                         ^                        |
watch <--------- polls for the confirmation -------------+------- "id|ok|5/20|46|Artist - Title"
```

## Why a relay

Connect IQ watch apps can only be a Bluetooth LE central. The laptop this was built for has a Bluetooth chip that cannot act as a BLE peripheral (advertising never starts, even with Microsoft's own sample), so the watch cannot connect to it directly. A watch app can reach the internet through the phone, but only over HTTPS, so the two sides meet on [ntfy.sh](https://ntfy.sh), a free public pub/sub service.

## Watch app

Runs on 119 Connect IQ watches with API level 3.2 or later: fenix 5 Plus to fenix 9, epix, Enduro, Forerunner, Venu, vivoactive, Instinct, MARQ, Descent, D2 and Approach. Screens adapt to round and rectangular displays of any size, the Instinct subscreen, and touch-only watches (swipe for back / next, tap for START, hold for flicks). 1-bit screens get a black-and-white launcher icon (`resources-mono`).

| Menu | What it does |
|---|---|
| Slides | UP back, DOWN next, START black screen. Hold UP cycles wrist-flick gestures (off, normal, light, firm). Shows the PowerPoint slide position (for example `5/20`) once the PC reports it. |
| Media | Play/pause, next/previous track, volume up/down, mute. Play/pause shows what is playing; the volume buttons show the volume. Stays open so you can press again. |
| Meeting | Mic on/off, camera on/off, raise hand, leave meeting (asks first). The PC finds the meeting window (Teams, Zoom or Google Meet) and uses its shortcuts. |
| Lock PC | Locks the PC (Win+L). |
| Sleep PC | Asks first, then puts the PC to sleep. |
| Get PC app | START sends the PC app's download link to the phone (Garmin Connect shows it as a notification). |
| Pair with PC | Shows the pairing code; START sends a test. |

Until the PC has answered once, Get PC app and Pair with PC are listed first as step 1 and step 2; afterwards they move to the end. On the Slides, Pair and Get PC app screens the circle at the top right says what START does. The app opens on its menu and ignores selects for 0.8 s after launch, so the START press that opened it from the app list does not trigger anything.

### Confirmation

Each command is sent as `word#id`. After acting, the PC app publishes `id|ok|slide|volume|playing` (or `id|err|reason`) on the `<code>a` topic. The watch polls that topic 1.5, 3 and 5.5 s after sending:

- **done 1.6s**: two short taps; the PC did it
- **PC: no shortcut** (or another reason): one long buzz; the PC got it but could not do it
- **PC no answer**: one long buzz; the PC is asleep, the app is closed, or it is offline
- **no phone / timed out**: one long buzz; the command never left the watch

Polling is limited to three requests per command to stay within ntfy.sh's free rate limits. Watch fonts only cover basic Latin, so other characters in a track title show as `?`.

### Gestures

In Slides, hold UP to cycle flick sensitivity (shown at the bottom of the screen): off, normal (1.3 g), light (0.9 g), firm (1.8 g). Any quick wrist flick goes to the next slide; UP still goes back. A flick swings out and back, so its direction can't be read reliably, which is why flicks only go forward.

The accelerometer is read at 25 Hz and gravity is subtracted, so it works however the wrist is held. Samples arrive in one-second batches, so a flick is acted on up to a second later, with a 1.2 s cooldown.

## PC app

`pc-app/` builds `WristRemote.exe`, a .NET Framework 4.8 tray app (no extra runtime needed on Windows 10/11).

1. Download `WristRemote.exe` from [Releases](https://github.com/irugniM/wrist-remote/releases/latest) (on the watch, Get PC app sends this link to your phone) and run it. It sits in the notification area by the clock. It is not code-signed, so Windows SmartScreen may ask first: More info, then Run anyway.
2. The first time, it asks for the pairing code shown on the watch under Pair with PC (spaces don't matter). The code is saved in `%APPDATA%\WristRemote\topic.txt`.
3. On the watch, open Pair with PC and press START: the log shows `test from watch: paired and working`.

Tray menu (left or right click): connection status and code, last command, Change pairing code, Log only (don't press keys), Start with Windows, Meeting app (Auto / Microsoft Teams / Zoom / Google Meet / Custom, with Edit custom shortcuts), Open log, Exit. Only one copy runs at a time.

| Command | What the PC does |
|---|---|
| next / prev | Right / Left arrow (to the foreground window) |
| black | B key (PowerPoint black screen) |
| playpause / nexttrack / prevtrack | Media control via `WM_APPCOMMAND` (not affected by keyboard remapping) |
| volup / voldown / mute | System volume via `WM_APPCOMMAND` |
| mic / camera / hand / leave | Meeting shortcut, sent to the meeting window |
| lock | `LockWorkStation` |
| sleep | Answers first, then suspends |
| ping | Logged only |

Anything else is logged and answered with `err|unknown`; nothing outside this list is ever run or typed. Commands older than 30 s are ignored, so nothing is replayed after the PC wakes.

### Meeting shortcuts

| | Teams | Zoom | Google Meet |
|---|---|---|---|
| mic | Ctrl+Shift+M | Alt+A | Ctrl+D |
| camera | Ctrl+Shift+O | Alt+V | Ctrl+E |
| hand | Ctrl+Shift+K | Alt+Y | Ctrl+Alt+H |
| leave | Ctrl+Shift+H | Alt+Q | Ctrl+W (closes the Meet tab) |

With Meeting app set to Auto (the default), the PC app looks for the meeting window itself: Teams, a Zoom meeting window (found by window class, since Zoom Workplace titles every window the same), or a browser window whose current tab is Google Meet. It brings that window to the front, presses the shortcut, then gives focus back to the window you were using, so you can mute while presenting. If no meeting window is open the watch shows `PC: no meeting`. Choosing a specific app instead sends its shortcuts to whatever window is in front.

Zoom's Alt+Q opens a confirmation; the PC app then clicks its "Leave meeting" button through UI Automation (never "End meeting for all"). If that button doesn't appear the dialog is left open and the watch shows `PC: confirm in Zoom`. Custom shortcuts live in `%APPDATA%\WristRemote\meeting-custom.txt`, one per line, for example `mic = ctrl+shift+m`.

### Status sent back

- Slide position: read from PowerPoint over COM while a slide show is running, or while PowerPoint is the front window in normal view
- Volume: Windows Core Audio (`IAudioEndpointVolume`)
- Now playing: Windows media session API (`GlobalSystemMediaTransportControlsSessionManager`), so it works with Spotify, browsers and other apps that report to Windows

## Security

- The pairing code is 16 random characters (about 80 bits) and works as a password: anyone who knows it can send commands. Keep it private.
- The PC app only acts on the fixed command list above.
- ntfy.sh is a third-party public service; only command words and the short status line pass through it.

## Build

Watch app (Connect IQ SDK, tested with 9.3.0):

```powershell
$sdk = "<Connect IQ SDK>\bin"
$key = "<developer_key.der>"
& "$sdk\monkeyc.bat" -f monkey.jungle -d instinct3solar45mm -o bin\WristRemote.prg -y $key -r
```

Use your watch's device id in place of `instinct3solar45mm` (see `manifest.xml`). Copy `bin\WristRemote.prg` to the watch's `Garmin\Apps\` folder over USB. For the store package of all watches: `monkeyc.bat -e -f monkey.jungle -o bin\WristRemote.iq -y $key -r`.

PC app: run `pc-app\build.cmd`. It uses the C# compiler that ships with Windows and needs the Windows 10/11 SDK only for the media-session metadata (`Windows.winmd`) at build time.

## Tested / not tested

- 1.3 layouts checked in the simulator on Venu 3 (touch, 454 px AMOLED), vivoactive 5 (touch only), Venu Sq 2 (rectangular), fenix 8 47 mm (buttons) and Instinct 2 (subscreen); all 119 watches build. Only the Instinct 3 has been tested on a real watch.

- Tested in the Connect IQ simulator with the PC app in log-only mode: pairing, slides, media (with volume and now-playing display), meeting mic, leave confirmation, lock, and "PC no answer" with the PC app closed. PC app alone: unknown commands answered with `err|unknown`; real volume and media session read correctly.
- On the real watch: pairing, slides, media and lock work (1.1). 1.1 sent Teams shortcuts by default, which were wrong in Zoom; 1.2 finds the meeting app instead.
- 1.2 on the real watch: Zoom and Microsoft Teams mic, camera, hand and leave (Zoom leave clicks through its confirmation); PowerPoint slide position, including a file opened in Protected View; wrist-flick gestures.
- Not yet tested: Google Meet calls.

## License

MIT. See [LICENSE](LICENSE).
