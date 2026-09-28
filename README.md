# abera-alarms

An iPhone app that rings the alarms [abera.tech/alerts](https://abera.tech/alerts) plans from a Google Calendar. The alarms are AlarmKit alarms. They ring through the silent switch and Focus, and they ring with no connection.

## Features

- abera.tech reads the calendar and decides what rings and when. The phone schedules an alarm for every alert whose type is alarm and that is not skipped, muted or acknowledged, up to the server's look-ahead (48 hours by default).
- An alarm already on the phone rings offline. Only changes need a connection: a new event, a moved event, a skip, a mute.
- Stop on a ringing alarm acknowledges it on abera.tech, which stops the Pushover repeats for the same alert. With no signal the acknowledgement waits on the phone and goes on the next sync.
- An alert acknowledged in a browser or skipped on abera.tech is removed from the phone on its next sync.
- Swipe to skip, mute for an hour or until morning, unpair.
- The phone syncs on launch, on pull to refresh, after every action and when iOS grants a background refresh. iOS decides how often that is.

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

### Build the app

Needs a Mac with Xcode 27 (`.xcode-version`) and an iPhone on iOS 26.1 or later.

1. Open `AberaAlarms.xcodeproj` in Xcode.
2. Select the AberaAlarms target, Signing and Capabilities, and choose your team.
3. Select your iPhone as the run destination and press Run.

With a free Apple account the app stops opening after 7 days and needs Run again. The Apple Developer Program ($99 a year) removes that limit.

### Try it without a server

Run the AberaAlarms scheme in a simulator with the launch argument `-demo`. abera.tech and AlarmKit are replaced by memory. `-demo-unpaired` starts on the pairing screen and `-demo-offline` starts with no connection. Debug builds only.

## Project layout

```text
App/                    SwiftUI app, AlarmKit, Keychain, the Stop button intent
AppUITests/             UI tests for every screen and button, in -demo mode
Packages/AlarmCore/     Sync logic with no Apple-only framework: API client,
                        pairing link, reconciler, offline acknowledgements
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

That runs the format lint, actionlint and shellcheck, the AlarmCore tests with the 95% line coverage floor, and every repository gate with its self-test.

On a Mac with Xcode:

```bash
scripts/xcodegen.sh
scripts/test-app.sh
```

The first regenerates the Xcode project after an edit to `project.yml`. The second builds the app and runs the UI tests on the newest iPhone simulator. CI runs both on the `xcode-27` runner.

## License

Apache-2.0. See LICENSE and NOTICE.
