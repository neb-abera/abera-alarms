# abera-alarms

An iPhone app that rings the alarms [abera.tech/alerts](https://abera.tech/alerts) plans from a Google Calendar. The alarms are AlarmKit alarms. They ring through the silent switch and Focus, and they ring with no connection.

## Features

- The Alarms tab replaces the Clock app's alarms: a time, the weekdays it repeats on (or no repeat), a label, an on/off switch and a snooze length. Snooze counts down on the Lock Screen and in the Dynamic Island, then rings again. An alarm with no repeat rings until stopped on the next day at its time, then switches itself off. These alarms are kept on abera.tech, where they can be edited from a computer, and stay out of Google Calendar and Pushover. They ring offline once set, and adding, editing, switching or deleting one works offline too: the phone applies it at once and sends it to abera.tech when the connection returns.
- The Countdowns tab shows the countdowns kept on abera.tech/alerts, each with a clock that ticks every second: days and hh:mm:ss to go, or the time since a date that has passed. Under it is the target date and time in the countdown's own time zone, with the zone named. Tap + to add one, tap one to edit it, swipe to delete. A new countdown starts in the phone's zone. Changing the zone keeps the time on the clock. A countdown set on abera.tech appears on the phone at the next sync, and abera.tech pushes the phone when one changes. Adding, editing and deleting need a connection: the app says so and keeps nothing to send later. The clocks keep ticking offline.
- The Dates tab is the date calculator from abera.tech. Between dates gives the total days (and whether the end is before the start), years, months and days, weeks and days, the weekdays Monday to Friday, and the total in hours, minutes and seconds, with a switch to include the end date. Add or subtract moves a date by years and months first, held to the month's last day (2024-02-29 plus 1 year 1 month is 2025-03-29), then by weeks and days, and gives the weekday. The arithmetic is the site's, in `DateCalc.swift`, tested against the site's table. It needs no connection.
- Every alarm that will ring on the phone shows a clock to its next ring, ticking once a second: "Rings in 0 days 06:12:33". On the Alarms tab that is each alarm that is on, at its next time on one of its days in the zone the phone is in. On the Calendar tab it is each alarm set on this phone, until its alert. An alarm that is off, skipped, muted or acknowledged has no clock. When the clocks go back an hour, an alarm in the repeated hour rings at the first pass and not again.
- The Calendar tab holds the events abera.tech plans from the calendar:

- abera.tech reads the calendar and decides what rings and when. The phone schedules an alarm for every alert whose type is alarm and that is not skipped, muted or acknowledged, up to the server's look-ahead (48 hours by default).
- An alarm already on the phone rings offline. Only changes need a connection: a new event, a moved event, a skip, a mute.
- Stop on a ringing alarm acknowledges it on abera.tech, which stops the Pushover repeats for the same alert. With no signal the acknowledgement waits on the phone and goes on the next sync.
- Snooze never delays or stops the Pushover backup. Only Stop does. A snooze is a short delay, and the deadline does not move because of it. Neb decided this on 2026-10-10.
- Stop on a ringing routine alarm acknowledges that ring on abera.tech too. The ring is the routine's latest time within the stop window set on abera.tech, so a snoozed ring keeps its time. A repeating routine stays set for its next day.
- An alert acknowledged in a browser or in Pushover, or skipped on abera.tech, is removed from the phone on its next sync. If it is ringing or snoozed, it stops. A routine ring acknowledged elsewhere stops ringing and the routine stays set.
- Every request names the phone's time zone in an `X-Time-Zone` header. abera.tech plans the routine rings in that zone.
- Tap the icon beside any event to choose Ring until stopped, Ring once or Off, for every occurrence. Ring until stopped is a phone alarm and repeating Pushover sounds. Ring once is one Pushover sound. abera.tech writes Ring until stopped back to Google Calendar as #critical in the event's description.
- The + button on the Calendar tab, New calendar event, needs only a time. The title is optional and defaults to "Alarm", and the alarm rings at that time until stopped. Advanced holds the type, how long before the start it rings, the event's length in the calendar and a location. abera.tech adds the event to Google Calendar, and the alarm is set on the phone at once.
- The list is grouped by day. It shows the alarms, or every event.
- Tap an event to change its title, start, length, location or alert, or to delete it. For a repeating event, choose This event or All events. abera.tech makes the change in Google Calendar. A deleted event stays in Google Calendar's trash for 30 days. Google refuses changes to an invitation someone else organizes, and the app shows why.
- Swipe to delete, skip one day, mute for an hour or until morning, unpair.
- abera.tech sends a silent push when anything changes what the phone should hold: a type change, a new event, a skip, a mute, an acknowledgement elsewhere or a calendar change. The push carries no content. It wakes the app, which syncs.
- The phone also syncs on launch, on pull to refresh, after every action and when iOS grants a background refresh. iOS rations silent pushes and drops them for an app force-quit from the app switcher, so these stay.

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

Run the AberaAlarms scheme in a simulator with the launch argument `-demo`. abera.tech and AlarmKit are replaced by memory, with events, routines and two countdowns. `-demo-unpaired` starts on the pairing screen and `-demo-offline` starts with no connection. Debug builds only.

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
