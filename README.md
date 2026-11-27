# abera-alarms

An iPhone app that rings the alarms [abera.tech/alerts](https://abera.tech/alerts) plans from a Google Calendar. The alarms are AlarmKit alarms. They ring through the silent switch and Focus, and they ring with no connection.

## Features

- The Alarms tab replaces the Clock app's alarms: a time, the weekdays it repeats on (or no repeat), a label, an on/off switch and a snooze length. Snooze counts down on the Lock Screen and in the Dynamic Island, then rings again. An alarm with no repeat rings until stopped on the next day at its time, then deletes itself. These alarms are kept on abera.tech, where they can be edited from a computer, and stay out of Google Calendar and Pushover. They ring offline once set, and adding, editing, switching or deleting one works offline too: the phone applies it at once and sends it to abera.tech when the connection returns.
- An alarm on the Alarms tab can hold steps: alarms that ring after it, each a set time after the one before. A 06:00 Wake up can ring Take medication at 06:05 and Beauty care at 06:10. The steps sit indented under their alarm on the Alarms tab, each with its time. One tap on a step's circle checks it off, and it does not ring until the alarm rings again. The next time every step is set again. The list shows the time under way until its last step has rung out, then the next time, so a step can be checked off before the alarm rings. Steps, This Time and Next, in the alarm's press and hold menu, shows both. A tap on a step adds a note and a photo from the camera or the library, to show later what was done. Steps ring offline like the alarm, and check-offs made offline go to abera.tech when the connection returns.
- An alarm's coming ring can be marked ahead or after it rings. Done and Skip sit under the alarm when its ring is within 12 hours, and in its press and hold menu. Done keeps that ring from sounding and leaves its steps to check off. Skip keeps the ring and its steps from sounding. Either way the next ring is set as usual, and Undo puts the ring back. While a ring ahead is marked, the phone holds the alarm's other rings of the next 7 days as one-time alarms, since iOS cannot skip one ring of a repeating alarm.
- The steps under an alarm belong to one of its rings. The list shows that ring until it is settled, then the next one. A ring is settled once it is skipped, or marked Done or stopped with every step checked off. A ring nobody settles stays until its last step has rung for the stop window set on abera.tech, 3 hours by default. History marks each ring Done or Skipped, and a skipped ring counts neither way in a step's count.
- The Alarms tab lists the alarms in the order they next ring, soonest first, and switched-off alarms last. A ring marked Done or Skipped does not count. Each alarm's steps open and close with one tap on the row above them, which also reads how many are done. They start open when the ring they list is today and closed on another day. A tap to open or close holds for that ring, across launches, and the next ring starts from the default again.
- Steps are added in the alarm's editor, each with a label and its time after the one above, typed as a number with minutes, hours or days. Add an Existing Alarm as a Step, in the same editor, makes another alarm a step at the time it rings. Make a Step of, in an alarm's press and hold menu, does the same from the alarm being moved. Either way the alarm stops being an alarm of its own, rings on its new alarm's days, and the other steps keep their times. A swipe on a step, or Make a Separate Alarm in its press and hold menu, makes it an alarm of its own again at the time it rang as a step. A swipe also deletes a step.
- A step can ring every few days: Rings every 2 days, from a first day, rings every other day. On a day it does not ring it takes no time, and the next step follows the one before it by its own offset. One night routine holds tretinoin 24 minutes after washing on one night and night serum 3 minutes after on the next.
- Delay, under an alarm's coming ring, moves that ring and its steps later by a typed number with minutes, hours or days, or in one tap by 15 min, 30 min, 1 h, 2 h or 1 day. A second delay adds to the first, up to 7 days after the planned time. A ring moved past the rings after it still rings with its steps, and the others ring as planned. Ring as planned puts it back.
- Steps done, last 14 days, on the Alarms tab, lists each step's count over two weeks, then each day with what was done, its note and photo, and what was missed. abera.tech keeps two weeks and deletes older check-offs and photos.
- An alarm on the Alarms tab is deleted with a swipe, a press and hold, or Delete Alarm at the bottom of its editor. Select, at the top left, puts Delete Selected and Delete All at the top of the list. Tap the circles to select alarms. Both ask once with the count.
- The Timer tab starts with a countdown timer: a length typed as a number with seconds, minutes, or hours (10 minutes by default), and Start timer in one tap. It counts down on the Lock Screen and in the Dynamic Island, then rings through silent mode and Focus until stopped. The running timer shows at the top of the Timer tab and of the Alarms tab with its time left and Cancel. At zero the row reads Ringing and the button reads Stop, and the row goes once the ring is stopped. One timer runs at a time, and a new one replaces it. The timer button on the Alarms tab sets the same timer, with an optional label.
- The Timer tab is a workout timer. It counts up from the start of each set and shows the set number. Next set records the set's time, adds one to the set count, and starts the next set at 0:00. The sets done are listed with their times, under the session total. Pause holds the clock. Stop ends the workout: it records the running set, sets the clock to 0:00, and switches off the voice. Reset Session, top right, goes back to set 1 at 0:00 and clears the list. Reset Everything, top left, also puts the spoken time back to every 30 seconds and the rest back to 1:30. Each is one tap, with no confirmation. Say the time every sets how often a voice says the time on the clock: off, 10, 15, 20, 30, or 45 seconds, or 1, 1.5, 2, 3, or 5 minutes. It is 30 seconds on a new timer and each time the app opens fresh with no workout going. Reset Session keeps the chosen setting. The voice says "30 seconds", "1 minute", and "1 minute 30". Next set says "Set 2". It speaks with the phone locked and the silent switch on, and lowers music while it speaks. The timer lives on the phone alone and survives the app being closed.
- From Start until Stop or Reset Session, the workout clock is on the Lock Screen and in the Dynamic Island, with the set number and the running time. There, with the phone locked, Pause and Resume hold and restart the clock, Next set starts the next set, and Stop ends the workout and takes it off the Lock Screen. Start workout is also a control for a Lock Screen slot or Control Center, which starts the clock without opening the app.
- The Timer tab also has a rest countdown, 1:30 by default. Start rest counts it down and puts it on the Lock Screen and in the Dynamic Island. There, with the phone locked, minus and plus take 15 seconds off the countdown or add 15, and Restart counts down the full rest again. With no countdown running, minus and plus change the rest's length, from 15 seconds to 60 minutes. At 0:00 an alarm rings through the silent switch and Focus, and the Lock Screen reads "Rest over" until Restart. Taking a countdown to 0:00 with minus ends it without a ring. End takes the rest off the Lock Screen. Start rest is also a control for a Lock Screen slot or Control Center, which starts the rest without opening the app. When Live Activities are off for the app, the Timer tab says so under the buttons.
- The Countdowns tab shows the countdowns kept on abera.tech/alerts, each with a clock that ticks every second: days and hh:mm:ss to go, or the time since a date that has passed. Under it is the target date and time in the countdown's own time zone, with the zone named. Tap + to add one, tap one to edit it, swipe to delete. abera.tech puts every countdown on Google Calendar as an event at its target. Alarm at this time makes that event an alarm, which rings at the target on the phone and through Pushover until it is stopped. A countdown with an alarm that does not repeat deletes itself once its alarm is stopped. A countdown repeats never, or every 1 to 999 hours, days, weeks, months or years: at its time it moves to its next date, and its calendar event repeats. A new countdown starts in the phone's zone, or America/New_York when the phone's zone has no time zone database name. The zone list puts the United States first, east to west, then Puerto Rico and Guam. Changing the zone keeps the time on the clock. A countdown set on abera.tech appears on the phone at the next sync, and abera.tech pushes the phone when one changes. Adding, editing and deleting need a connection: the app says so and keeps nothing to send later. The clocks keep ticking offline.
- The Dates tab is the date calculator from abera.tech. Between dates gives the total days (and whether the end is before the start), years, months and days, weeks and days, the weekdays Monday to Friday, and the total in hours, minutes and seconds, with a switch to include the end date. Add or subtract moves a date by years and months first, held to the month's last day (2024-02-29 plus 1 year 1 month is 2025-03-29), then by weeks and days, and gives the weekday. The arithmetic is the site's, in `DateCalc.swift`, tested against the site's table. It needs no connection.
- Every alarm that will ring on the phone shows a clock to its next ring, ticking once a second: "Rings in 0 days 06:12:33". On the Alarms tab that is each alarm that is on, at its next time on one of its days in the zone the phone is in. On the Calendar tab it is each alarm set on this phone, until its alert. An alarm that is off, skipped, muted or acknowledged has no clock. When the clocks go back an hour, an alarm in the repeated hour rings at the first pass and not again.
- The Next alarm widget shows the next alarm that rings on this phone. That is the earliest of a calendar alarm marked Set on this phone, an alarm on the Alarms tab that is on, and a running timer. It shows the title or label, the time, and a clock that counts down to the ring. It fits the Home Screen in small and medium sizes, and the Lock Screen as a rectangle, a line above the clock, or a circle. The medium size also names the next calendar event when that event is not the alarm shown. With nothing set it reads "No alarm set".
- The Countdown widget shows one countdown: its label, the days and hh:mm to go or since it passed, and the target date in the countdown's own time zone. It fits the Home Screen in small and medium sizes, and the Lock Screen as a rectangle or a line. A new one shows the next countdown to come. Edit Widget chooses another.
- Both widgets read what the app last wrote to an app group after each sync and each change on the phone. They need no connection and no running app, and move on to the next alarm as each one rings. They hold no token. A tap opens the app.
- The Calendar tab holds the events abera.tech plans from the calendar:

- abera.tech reads the calendar and decides what rings and when. The phone schedules an alarm for every alert whose type is alarm and that is not skipped, muted or acknowledged, up to the server's look-ahead (48 hours by default).
- An alarm already on the phone rings offline. Only changes need a connection: a new event, a moved event, a skip, a mute.
- Stop on a ringing alarm acknowledges it on abera.tech, which stops the Pushover repeats for the same alert. With no signal the acknowledgement waits on the phone and goes on the next sync.
- Snooze never delays or stops the Pushover backup. Only Stop does. A snooze is a short delay, and the deadline does not move because of it. Neb decided this on 2026-10-10.
- Stop on a ringing routine alarm acknowledges that ring on abera.tech too. The ring is the routine's latest time within the stop window set on abera.tech, so a snoozed ring keeps its time. A repeating routine stays set for its next day.
- An alert acknowledged in a browser or in Pushover, or skipped on abera.tech, is removed from the phone on its next sync. If it is ringing or snoozed, it stops. A routine ring acknowledged elsewhere stops ringing and the routine stays set.
- Every request names the phone's time zone in an `X-Time-Zone` header. abera.tech plans the routine rings in that zone.
- Tap the icon beside any event to choose Ring until stopped, Ring once or Off, for every occurrence. Ring until stopped is a phone alarm and repeating Pushover sounds. Ring once is one Pushover sound. abera.tech writes Ring until stopped back to Google Calendar as #critical in the event's description.
- Rules, in the menu at the top right of the Calendar tab, set what an event sends when it has no type of its own and no #critical mark. A rule is a title, organizer, or location that contains a text, and what the event then sends: Ring until stopped, Ring once, or Off. The first rule that matches wins. Matching ignores case, and an organizer or location rule with no text matches any event that has one. Edit reorders the rules, and a swipe deletes one. abera.tech keeps the list, and abera.tech/alerts edits the same list.
- The + button on the Calendar tab, New calendar event, needs nothing typed. Starts defaults to the next whole or half hour, Length to 30 minutes, and the title to "Event". Alert is on by default and rings until stopped at the start. Switch it off for an event with no alert, or choose Rings Once. Length and Before the start each take a number and a unit: minutes, hours or days. abera.tech adds the event to Google Calendar, and its alarm is set on the phone at once.
- The list is grouped by day. It opens on All events, and Alarms shows only the alarms.
- Tap an event to change its title, start, length, location or alert, or to delete it. The editor has the same Alert switch and the same number and unit fields. For a repeating event, choose This event or All events. abera.tech makes the change in Google Calendar. A deleted event stays in Google Calendar's trash for 30 days. Google refuses changes to an invitation someone else organizes, and the app shows why.
- Swipe to delete, skip one day, mute for an hour or until morning, unpair.
- abera.tech sends a silent push when anything changes what the phone should hold: a type change, a new event, a skip, a mute, an acknowledgement elsewhere or a calendar change. The push carries no content. It wakes the app, which syncs.
- The phone also syncs on launch, on pull to refresh, after every action and when iOS grants a background refresh. iOS rations silent pushes and drops them for an app force-quit from the app switcher, so these stay.

## Ready to ring

After pairing, and on every launch while one of these fails, the app opens on Ready to Ring and stays there:

- Alarms allowed for the app (Settings > Apps > Alarms > Alarms).
- Background App Refresh on for the app, so new and moved alarms reach the phone with the app closed.
- A test alarm heard. It rings 10 seconds after the tap, with the sound every alarm plays. On iOS 27 the alarm volume is its own slider: Settings > Sounds & Haptics > Alarms and Timers, with Match Ringtone Volume off. Attention Aware Features (Settings > Face ID & Passcode) lowers an alarm while the owner looks at the phone. No app can read either setting, so the owner confirms the test.

The bell button at the top of the Alarms tab rings the same test alarm at any time. After it rings, I heard it records the test, and I didn't hear it shows the iOS 27 alarm volume setting with Ring it again.

The same screen warns, without holding the app, when the last sync is more than 12 hours old, when iOS refused an alarm, when abera.tech cannot wake the phone, when Low Power Mode is on, and when Pushover, the backup, is not installed. The app checks again after every sync and each time it comes back from Settings.

## Sound and snooze

Sound & Snooze, on the Alarms tab, sets the sound every alarm plays and how long Snooze waits on a calendar alarm. abera.tech saves both, and the "On the phone" settings on abera.tech/alerts show the same choice. The five sounds (Pulse, Chime, Rise, Siren, Beacon) are generated by `tools/make-sounds.py`, so no recording has a licence to track. Run it, then `tools/make-sounds.sh` on a Mac, to make them again.

## How it fits together

```text
Google Calendar ──iCal──▶ abera.tech ──Pushover──▶ phone notification (needs a connection)
                              │
                              └──/api/alerts──▶ this app ──AlarmKit──▶ alarm (rings offline)
```

The app never reads the calendar itself. abera.tech is the one planner, so the phone, the page and Pushover agree about every alert.

## Getting started

### Pair the phone

1. On abera.tech/alerts, signed in, press Pair a phone.
2. Open the link it shows on the phone, or scan its QR code with the Camera app. The app opens and pairs.
3. Allow alarms when iOS asks.

To pair from a computer, copy the link and paste it into the app's Pairing link field.

### Install from TestFlight

Every merge to main builds the app on GitHub's Macs, signs it with the App Store Connect API key (secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`) and uploads it to TestFlight (`.github/workflows/testflight.yml`, `scripts/release.sh`). The TestFlight app on the iPhone installs and updates it. The version is the date, and the build number is the run number.

### Build the app

Needs a Mac with Xcode 27 (`.xcode-version`) and an iPhone on iOS 26.1 or later.

1. Open `AberaAlarms.xcodeproj` in Xcode.
2. Select the AberaAlarms target, Signing and Capabilities, and choose your team.
3. Select your iPhone as the run destination and press Run.

With a free Apple account the app stops opening after 7 days and needs Run again. The Apple Developer Program ($99 a year) removes that limit.

### Try it without a server

Run the AberaAlarms scheme in a simulator with the launch argument `-demo`. abera.tech and AlarmKit are replaced by memory, with events, routines and two countdowns. `-demo-unpaired` starts on the pairing screen and `-demo-offline` starts with no connection. `-demo-real-timer` gives the timer to AlarmKit, so it rings through iOS. Debug builds only. The iOS 27.0 simulator denies alarms without a prompt, so `testATimerRingsThroughIOSAndStopsThere` skips there and runs on iOS 26.5.

## Project layout

```text
App/                    SwiftUI app, AlarmKit, Keychain, the Stop button intent
AppUITests/             UI tests for every screen and button, in -demo mode
Packages/AlarmCore/     Sync logic with no Apple-only framework: API client,
                        pairing link, reconciler, offline acknowledgements,
                        countdowns and the date calculator
project.yml             XcodeGen spec for AberaAlarms.xcodeproj
scripts/                Gates: coverage, version, concurrency, required checks,
                        prose, attribution, XcodeGen, Xcode selection
Dockerfile              Swift 6.4 on Ubuntu 26.04 for AlarmCore, Vale, actionlint
```

## Development workflow

On the dev box, in Docker:

```bash
make check
```

That runs the format lint, actionlint and shellcheck, the AlarmCore tests with the 96% line coverage floor, and every repository gate with its self-test.

On a Mac with Xcode:

```bash
scripts/xcodegen.sh
scripts/test-app.sh
```

The first regenerates the Xcode project after an edit to `project.yml`. The second builds the app and runs the UI tests on the newest iPhone simulator. CI runs both on the `xcode-27` runner.

## License

Apache-2.0. See LICENSE and NOTICE.
