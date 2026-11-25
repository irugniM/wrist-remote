# Connect IQ Store listing

Text to paste into the Connect IQ developer site for Wrist Remote 1.2.0.

## App name

Wrist Remote

## Type and category

Device app. Category: Tools (or Productivity, whichever the form offers).

## Short description

Control your Windows PC from your watch: slides, music, meetings, lock and sleep.

## Description

Wrist Remote turns your Instinct into a remote for your Windows PC.

- Slides: turn pages with UP and DOWN, black out the screen with START, or flick your wrist to go to the next slide. The watch shows the PowerPoint slide number.
- Media: play / pause, next and previous track, volume and mute. See what is playing and the volume.
- Meetings: mute the mic, turn the camera on or off, raise your hand or leave. Works with Microsoft Teams, Zoom and Google Meet; the PC finds the meeting window for you.
- Lock or sleep the PC.

Every command is confirmed by the PC: two short taps mean it worked, one long buzz means it did not, and the screen says why.

REQUIRES THE FREE PC APP (Windows 10 / 11 only, no Mac):
1. On the watch open Get PC app and press START. The download link appears on your phone. Or download it here: https://github.com/irugniM/wrist-remote/releases/latest
2. Run WristRemote.exe on the PC. It sits in the notification area by the clock.
3. On the watch open Pair with PC, type the code it shows into the PC app, then press START on the watch to test.

Windows may warn that the app is from an unknown publisher the first time; choose More info, then Run anyway.

How it works: the watch sends commands through your phone (Garmin Connect must be running and online) to the free ntfy.sh relay, and the PC app picks them up. Your pairing code works like a password; only command words and a short status line pass through the relay. The PC app only acts on a fixed list of commands.

Free and open source (MIT): https://github.com/irugniM/wrist-remote

## What's new (1.2.0)

- Meeting buttons find the Teams, Zoom or Google Meet window themselves.
- Leave meeting in Zoom answers Zoom's confirmation for you.
- PowerPoint slide number also works for files opened in Protected View.
- New wrist-flick detection: any flick goes to the next slide, three sensitivity levels.
- Cleaner screens; Get PC app sends the download link to your phone.

## Images

- store-screenshots/01-setup.png: setup in 3 steps
- store-screenshots/02-menu.png: main menu (first run)
- store-screenshots/03-slides.png: slides
- store-screenshots/04-media.png: media
- store-screenshots/05-meeting.png: meeting
- store-art/cover-500.png: cover
- store-art/hero-1440x720.png: hero

The screenshots come from a debug build with example data (slide 5/20, an example track, an example pairing code); release builds don't include it.

## Before submitting

- Publish a GitHub release with WristRemote.exe so the link above works.
- Upload bin/WristRemote.iq.
