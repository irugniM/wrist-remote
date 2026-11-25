# Wrist Remote

Control a Windows PC from a Garmin Instinct 3: turn slides, control media and volume, run meeting shortcuts, lock or sleep the PC. Every command is confirmed by the PC, so the watch tells you whether it actually happened.

```
watch --Bluetooth--> phone (Garmin Connect) --HTTPS--> ntfy.sh --HTTPS--> Windows tray app --> keys / volume / lock / sleep
                                                         ^                        |
watch <--------- polls for the confirmation -------------+------- "id|ok|5/20|46|Artist - Title"
```

## Why a relay

Connect IQ watch apps can only be a Bluetooth LE central. The laptop this was built for has a Bluetooth chip that cannot act as a BLE peripheral (advertising never starts, even with Microsoft's own sample), so the watch cannot connect to it directly. A watch app can reach the internet through the phone, but only over HTTPS, so the two sides meet on [ntfy.sh](https://ntfy.sh), a free public pub/sub service.

## Watch app

| Menu | What it does |
|---|---|
| Slides | UP previous, DOWN next, START black screen. Hold UP turns wrist-flick gestures on or off. Shows the PowerPoint slide position (for example `5/20`) once the PC reports it. |
| Media | Play/pause, next/previous track, volume up/down, mute. Play/pause shows what is playing; the volume buttons show the volume. Stays open so you can press again. |
| Meeting | Mic on/off, camera on/off, raise hand, leave meeting (asks first). Shortcuts come from the meeting app chosen on the PC. |
| Lock PC | Locks the PC (Win+L). |
| Sleep PC | Asks first, then puts the PC to sleep. |
| Pair | Shows the pairing code; START sends a test. |

The app opens on its menu and ignores selects for 0.8 s after launch, so the START press that opened it from the app list does not trigger anything.

### Confirmation

Each command is sent as `word#id`. After acting, the PC app publishes `id|ok|slide|volume|playing` (or `id|err|reason`) on the `<code>a` topic. The watch polls that topic 1.5, 3 and 5.5 s after sending:

- **done 1.6s**: two short taps; the PC did it
- **PC: no shortcut** (or another reason): one long buzz; the PC got it but could not do it
- **PC no answer**: one long buzz; the PC is asleep, the app is closed, or it is offline
- **no phone / timed out**: one long buzz; the command never left the watch

Polling is limited to three requests per command to stay within ntfy.sh's free rate limits. Watch fonts only cover basic Latin, so other characters in a track title show as `?`.

### Gestures

In Slides, hold UP to turn flicks on. A quick wrist flick along the face's left-right axis (over 1.5 g) turns the page; one direction is next, the other previous, with a 0.9 s cooldown. The screen shows the latest peak in mg to help you find the right force.

## PC app

`pc-app/` builds `WristRemote.exe`, a .NET Framework 4.8 tray app (no extra runtime needed on Windows 10/11).

1. Run `WristRemote.exe`. It sits in the notification area by the clock.
2. The first time, it asks for the pairing code shown on the watch under Pair (spaces don't matter). The code is saved in `%APPDATA%\WristRemote\topic.txt`.
3. On the watch, open Pair and press START: the log shows `test from watch: paired and working`.

Tray menu (left or right click): connection status and code, last command, Change pairing code, Log only (don't press keys), Start with Windows, Meeting app (Microsoft Teams / Zoom / Google Meet / Custom, with Edit custom shortcuts), Open log, Exit. Only one copy runs at a time.

| Command | What the PC does |
|---|---|
| next / prev | Right / Left arrow (to the foreground window) |
| black | B key (PowerPoint black screen) |
| playpause / nexttrack / prevtrack | Media control via `WM_APPCOMMAND` (not affected by keyboard remapping) |
| volup / voldown / mute | System volume via `WM_APPCOMMAND` |
| mic / camera / hand / leave | Meeting shortcut (to the foreground window) |
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
| leave | Ctrl+Shift+H | Alt+Q | none (answers `no shortcut`) |

The meeting window must be in front. Zoom's Alt+Q opens a confirmation that still needs Enter. Custom shortcuts live in `%APPDATA%\WristRemote\meeting-custom.txt`, one per line, for example `mic = ctrl+shift+m`.

### Status sent back

- Slide position: read from PowerPoint over COM while a slide show is running
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

Copy `bin\WristRemote.prg` to the watch's `Garmin\Apps\` folder over USB.

PC app: run `pc-app\build.cmd`. It uses the C# compiler that ships with Windows and needs the Windows 10/11 SDK only for the media-session metadata (`Windows.winmd`) at build time.

## Tested / not tested

- Tested in the Connect IQ simulator with the PC app in log-only mode: pairing, slides, media (with volume and now-playing display), meeting mic, leave confirmation, lock, and "PC no answer" with the PC app closed. PC app alone: unknown commands answered with `err|unknown`; real volume and media session read correctly.
- On the real watch (1.0): pairing, slides and media work.
- Not yet tested: confirmation timing on the real watch, meeting shortcuts in real Teams/Zoom, real lock, PowerPoint slide position, gestures (the simulator has no real accelerometer).

## License

MIT. See [LICENSE](LICENSE).
