import XCTest

/// Every screen and button, driven through the app with abera.tech and
/// AlarmKit in memory (`-demo`, App/Demo.swift).
@MainActor
final class AlarmsUITests: XCTestCase {
    static let link = "aberaalarms://pair#token=aat_" + String(repeating: "D", count: 43)

    /// Runs first, by name, and only launches. On a fresh simulator the
    /// first launch under XCUITest took 68 s to idle and the next query
    /// failed with kAXErrorServerNotFound. Booting the simulator and
    /// launching the app with simctl beforehand did not help. On
    /// 2026-11-02 testACalendarAlarmCountsDownToItsAlert, then first, failed
    /// that way in four runs, and all 40 tests passed on retry.
    /// scripts/test-app.sh runs this alone first and ignores its result,
    /// then runs every other test without it.
    func test0WarmUp() {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("A first launch on a fresh simulator can time out", options: options) {
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 30)
        }
    }

    /// Starts the app in -demo mode. A paired start opens the Calendar tab
    /// unless `tab` names another one, or nil to stay on Alarms.
    private func launch(_ arguments: String..., tab: String? = "Calendar") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + arguments
        app.launch()
        if let tab, !arguments.contains("-demo-unpaired") { open(tab, in: app) }
        return app
    }

    private func open(_ tab: String, in app: XCUIApplication) {
        let button = app.tabBars.buttons[tab]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
    }

    private func row(_ app: XCUIApplication, _ key: String) -> XCUIElement {
        app.descendants(matching: .any)["alarm-\(key)"]
    }

    /// One side of the Show picker, scrolled back into view. It is the
    /// list's top row, and a list drops a row scrolled off screen. After
    /// 17:20 UTC the demo's dinner falls on the next day, its section
    /// pushes the row down, and tapping it scrolls the picker away.
    private func show(_ side: String, in app: XCUIApplication) {
        let button = app.segmentedControls.buttons[side]
        for _ in 0..<5 where !button.exists { app.collectionViews.firstMatch.swipeDown() }
        button.tap()
    }

    // MARK: Pairing

    func testPairingWithAPastedLinkShowsTheAlarms() {
        let app = launch("-demo-unpaired")
        let field =
            app.textViews["pairing-link"].exists ? app.textViews["pairing-link"] : app.textFields["pairing-link"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(Self.link)
        app.buttons["pair"].tap()
        open("Calendar", in: app)
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Set on this phone"].firstMatch.exists)
    }

    func testALinkWithABadTokenIsRefused() {
        let app = launch("-demo-unpaired")
        let field =
            app.textViews["pairing-link"].exists ? app.textViews["pairing-link"] : app.textFields["pairing-link"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("aberaalarms://pair#token=aat_short")
        app.buttons["pair"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pairing-error"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(row(app, "standup").exists)
    }

    func testATokenTheServerRefusesIsRefused() {
        let app = launch("-demo-unpaired")
        let field =
            app.textViews["pairing-link"].exists ? app.textViews["pairing-link"] : app.textFields["pairing-link"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("aberaalarms://pair#token=aat_" + String(repeating: "X", count: 43))
        app.buttons["pair"].tap()
        let error = app.descendants(matching: .any)["pairing-error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertTrue(error.label.contains("refused"))
    }

    // MARK: The list

    func testTheListOpensOnAllEventsAndAlarmsShowsOnlyAlarms() {
        let app = launch()
        XCTAssertTrue(row(app, "lunch").waitForExistence(timeout: 10))
        XCTAssertTrue(row(app, "dinner").exists)
        XCTAssertTrue(app.segmentedControls.buttons["All events"].isSelected)

        show("Alarms", in: app)
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        XCTAssertTrue(row(app, "pt|1").exists)
        XCTAssertFalse(row(app, "lunch").exists)
        XCTAssertFalse(row(app, "dinner").exists)
        XCTAssertTrue(app.staticTexts["1 notification(s) go through Pushover only."].exists)
    }

    // MARK: Type

    func testMakingAnEventAnAlarmSetsItOnThePhone() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        show("All events", in: app)
        let type = app.buttons["type-dinner"]
        XCTAssertTrue(type.waitForExistence(timeout: 5))
        type.tap()
        app.buttons["Ring until stopped"].tap()
        XCTAssertTrue(waitFor(type, labelContaining: "Ring until stopped"))

        show("Alarms", in: app)
        let dinner = row(app, "dinner")
        XCTAssertTrue(dinner.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(dinner, labelContaining: "Set on this phone"))
    }

    func testARuleMakesAnEventAnAlarmOnThePhone() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["menu"].tap()
        app.buttons["Rules"].tap()

        let add = app.buttons["add-rule"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        app.buttons["rule-1-field"].tap()
        app.buttons["Title contains"].tap()
        let text = app.textFields["rule-1-text"]
        text.tap()
        text.typeText("DINNER")
        app.buttons["rule-1-type"].tap()
        app.buttons["Ring until stopped"].tap()
        app.buttons["save-rules"].tap()

        XCTAssertTrue(waitForGone(add))
        show("Alarms", in: app)
        let dinner = row(app, "dinner")
        XCTAssertTrue(dinner.waitForExistence(timeout: 10))
        XCTAssertTrue(waitFor(dinner, labelContaining: "Set on this phone"))

        // The rule is kept: it is on the screen the next time.
        app.buttons["menu"].tap()
        app.buttons["Rules"].tap()
        XCTAssertTrue(app.textFields["rule-1-text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["rule-1-text"].value as? String, "DINNER")
    }

    func testMakingAnAlarmNoneTakesItOffThePhone() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        show("Alarms", in: app)
        let type = app.buttons["type-standup"]
        XCTAssertTrue(type.waitForExistence(timeout: 10))
        type.tap()
        app.buttons["Off"].tap()
        XCTAssertTrue(row(app, "pt|1").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForGone(row(app, "standup")))
    }

    // MARK: Ready to ring

    func testANewPhoneStaysOnSetupUntilATestAlarmIsHeard() {
        let app = launch("-demo-unready", tab: nil)
        let check = app.descendants(matching: .any)["check-test"]
        XCTAssertTrue(check.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.navigationBars["Ready to Ring"].exists)
        XCTAssertFalse(app.tabBars.buttons["Calendar"].isHittable)

        app.buttons["ring-test"].tap()
        XCTAssertTrue(app.staticTexts["test-rings-at"].waitForExistence(timeout: 5))
        app.buttons["heard-test"].tap()

        XCTAssertTrue(waitForGone(app.navigationBars["Ready to Ring"]), app.debugDescription)
        open("Calendar", in: app)
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
    }

    func testBackgroundRefreshOffHoldsSetupWithASettingsLink() {
        let app = launch("-demo-refresh-off", tab: nil)
        let check = app.descendants(matching: .any)["check-backgroundRefresh"]
        XCTAssertTrue(check.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["open-settings-backgroundRefresh"].exists)
        XCTAssertTrue(app.navigationBars["Ready to Ring"].exists)
    }

    func testATestAlarmRingsFromTheAlarmsTabInOneTap() {
        let app = launch(tab: nil)
        let button = app.buttons["test-alarm"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        let rings = app.descendants(matching: .any)["test-rings-at"]
        XCTAssertTrue(rings.waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["heard-test"].tap()
        XCTAssertTrue(waitForGone(rings))
    }

    func testASilentTestAlarmShowsTheVolumeSettingAndRingsAgain() {
        let app = launch(tab: nil)
        let button = app.buttons["test-alarm"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        let missed = app.buttons["missed-test"]
        XCTAssertTrue(missed.waitForExistence(timeout: 5), app.debugDescription)
        missed.tap()
        XCTAssertTrue(app.descendants(matching: .any)["test-missed-help"].waitForExistence(timeout: 5))
        app.buttons["ring-test-again"].tap()
        XCTAssertTrue(app.buttons["heard-test"].waitForExistence(timeout: 5))
        app.buttons["heard-test"].tap()
        XCTAssertTrue(waitForGone(app.buttons["heard-test"]))
    }

    func testTheSilentTestHelpCanBeDismissed() {
        let app = launch(tab: nil)
        let button = app.buttons["test-alarm"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        XCTAssertTrue(app.buttons["missed-test"].waitForExistence(timeout: 5))
        app.buttons["missed-test"].tap()
        let help = app.descendants(matching: .any)["test-missed-help"]
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        app.buttons["dismiss-test-help"].tap()
        XCTAssertTrue(waitForGone(help))
    }

    func testATimerStartsFromTheAlarmsTabAndCancels() {
        let app = launch(tab: nil)
        let button = app.buttons["new-timer"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        let amount = app.textFields["timer-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "10")
        replace(amount, with: "2", in: app)
        let label = app.textFields["timer-label"]
        label.tap()
        label.typeText("Laundry\n")
        app.buttons["start-timer"].tap()

        let row = app.descendants(matching: .any)["timer-row"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row.label.contains("Laundry"), row.label)
        XCTAssertTrue(row.label.contains("1:5") || row.label.contains("2:00"), row.label)
        app.buttons["cancel-timer"].tap()
        XCTAssertTrue(waitForGone(row))
    }

    func testATimerStartsFromTheTimerTabInOneTapAndCancels() {
        let app = launch(tab: "Timer")
        let amount = app.textFields["countdown-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(amount.value as? String, "10")
        typeLength("2", into: amount)
        XCTAssertTrue(app.buttons["countdown-start"].isHittable, "the keyboard moved Start timer off screen")
        XCTAssertTrue(app.buttons["countdown-keyboard-done"].isHittable, "the keyboard has no Done")
        app.buttons["countdown-start"].tap()

        let row = app.descendants(matching: .any)["countdown-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(row.label.contains("1:5") || row.label.contains("2:00"), row.label)
        XCTAssertTrue(waitForChange(row, from: row.label), "the timer did not count down")
        XCTAssertEqual(app.buttons["countdown-cancel"].label, "Cancel")
        app.buttons["countdown-cancel"].tap()
        XCTAssertTrue(waitForGone(row))
        XCTAssertTrue(app.buttons["countdown-start"].waitForExistence(timeout: 5))
    }

    /// The timer runs to zero: the row reads Ringing and its button Stop.
    func testATimerOnTheTimerTabRunsToZeroAndStops() {
        let app = launch(tab: "Timer")
        startCountdown(app, seconds: 3)
        let row = app.descendants(matching: .any)["countdown-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(waitFor(row, labelContaining: "Ringing", timeout: 10), row.label)
        XCTAssertEqual(app.buttons["countdown-cancel"].label, "Stop")
        app.buttons["countdown-cancel"].tap()
        XCTAssertTrue(waitForGone(row))
    }

    /// The timer rings through iOS, as on the phone: AlarmKit counts down,
    /// shows its alert over the Home Screen, and Stop there ends it. Back in
    /// the app the row is gone. No test had run a timer to its ring until
    /// Neb asked on 2026-11-14.
    func testATimerRingsThroughIOSAndStopsThere() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let app = launch("-demo-real-timer", tab: "Timer")
        startCountdown(app, seconds: 8)
        // The first timer asks for permission to set alarms.
        let allow = springboard.buttons["Allow"].firstMatch
        let asked = allow.waitForExistence(timeout: 3)
        if asked { allow.tap() }
        let row = app.descendants(matching: .any)["countdown-row"].firstMatch
        if !row.waitForExistence(timeout: 10) {
            // The iOS 27.0 simulator denies alarms 0.6 s after the tap and
            // shows no prompt (CI, 2026-11-15: AlarmKit error 1,
            // authorization denied). simctl has no grant for alarms. The
            // ring runs on the iOS 26.5 simulator and on the phone.
            let refused = app.staticTexts["countdown-error"].exists
            let ios = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
            if refused && !asked && ios >= 27 {
                throw XCTSkip("The iOS \(ios) simulator denied alarms without asking")
            }
            XCTFail(app.debugDescription)
            return
        }

        XCUIDevice.shared.press(.home)
        let stop = springboard.buttons["Stop"].firstMatch
        if !stop.waitForExistence(timeout: 30) {
            XCTFail("the timer did not ring:\n\(springboard.debugDescription)")
            return
        }
        stop.tap()
        // The alert takes seconds to leave on a loaded runner.
        XCTAssertTrue(poll(15) { !stop.exists }, "Stop did not end the ring")

        app.activate()
        if app.tabBars.buttons["Timer"].waitForExistence(timeout: 10) { app.tabBars.buttons["Timer"].tap() }
        XCTAssertTrue(app.buttons["countdown-start"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(row.exists)
    }

    private func startCountdown(_ app: XCUIApplication, seconds: Int) {
        let amount = app.textFields["countdown-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 10), app.debugDescription)
        app.buttons["countdown-unit"].tap()
        let unit = app.buttons["seconds"].firstMatch
        XCTAssertTrue(unit.waitForExistence(timeout: 5), app.debugDescription)
        unit.tap()
        typeLength(String(seconds), into: amount)
        app.buttons["countdown-start"].tap()
    }

    /// Types over the timer's length. The field is right-aligned, so a tap
    /// at its right edge puts the cursor after the number.
    private func typeLength(_ text: String, into field: XCUIElement) {
        let old = (field.value as? String) ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
        XCTAssertEqual(field.value as? String, text)
    }

    func testAReadyPhoneOpensOnItsTabs() {
        let app = launch(tab: nil)
        XCTAssertTrue(app.tabBars.buttons["Calendar"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.navigationBars["Ready to Ring"].exists)
    }

    // MARK: New event

    func testANewAlarmEventRingsOnThePhone() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["new-event"].tap()
        let title = app.textFields["event-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Dentist")
        app.buttons["add-event"].tap()

        let dentist = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'alarm-created-' AND label CONTAINS 'Dentist'")
        ).firstMatch
        XCTAssertTrue(dentist.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitFor(dentist, labelContaining: "Set on this phone"), dentist.label)
    }

    func testANewAlarmNeedsOnlyATime() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["new-event"].tap()
        let add = app.buttons["add-event"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isEnabled)
        add.tap()

        let made = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'alarm-created-' AND label CONTAINS 'Event'")
        ).firstMatch
        XCTAssertTrue(made.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitFor(made, labelContaining: "Set on this phone"), made.label)
    }

    func testANewEventStartsWithItsAlertOnRingingUntilStopped() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["new-event"].tap()
        XCTAssertTrue(app.buttons["add-event"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Starts"].exists)
        XCTAssertFalse(app.staticTexts["Rings at"].exists)
        let alert = app.switches["event-alert"]
        XCTAssertEqual(alert.value as? String, "1")
        XCTAssertTrue(
            app.buttons["event-type"].firstMatch.label.contains("Until stopped"),
            app.buttons["event-type"].firstMatch.label)
        XCTAssertEqual(app.textFields["event-length-amount"].value as? String, "30")
        XCTAssertTrue(
            app.staticTexts["Rings at the start until you stop it, on the phone and through Pushover."].exists)

        alert.switches.firstMatch.tap()
        // The switch's own value: its footer can sit under the keyboard,
        // which the test before this one leaves up on iOS 27.
        XCTAssertTrue(waitFor(alert, value: "0"), alert.debugDescription)
        XCTAssertFalse(app.buttons["event-type"].firstMatch.exists)
        XCTAssertFalse(app.textFields["event-lead-amount"].exists)
    }

    func testANewEventTakesALengthAndLeadInAnyUnit() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["new-event"].tap()
        let title = app.textFields["event-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Flight")
        replace(app.textFields["event-length-amount"], with: "2", in: app)
        choose("hours", from: "event-length-unit", in: app)
        let lead = app.textFields["event-lead-amount"]
        replace(lead, with: "3", in: app)
        choose("hours", from: "event-lead-unit", in: app)
        XCTAssertEqual(lead.value as? String, "3")
        XCTAssertTrue(
            app.buttons["event-lead-unit"].firstMatch.label.contains("hours"),
            app.buttons["event-lead-unit"].firstMatch.label)
        app.buttons["add-event"].tap()

        let flight = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'alarm-created-' AND label CONTAINS 'Flight'")
        ).firstMatch
        // The list builds only the rows on screen: look at the top, then lower down.
        if !flight.waitForExistence(timeout: 10) {
            app.collectionViews.firstMatch.swipeDown()
            for _ in 0..<4 where !flight.waitForExistence(timeout: 2) { app.collectionViews.firstMatch.swipeUp() }
        }
        XCTAssertTrue(flight.exists, app.debugDescription)
        flight.tap()
        XCTAssertTrue(app.textFields["edit-length-amount"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["edit-length-amount"].value as? String, "2")
        XCTAssertTrue(
            app.buttons["edit-length-unit"].firstMatch.label.contains("hours"),
            app.buttons["edit-length-unit"].firstMatch.label)
        XCTAssertEqual(app.textFields["event-lead-amount"].value as? String, "3")
        XCTAssertTrue(
            app.buttons["event-lead-unit"].firstMatch.label.contains("hours"),
            app.buttons["event-lead-unit"].firstMatch.label)
    }

    /// Opens a unit menu and picks an option, never the other unit menu's own button.
    private func choose(_ option: String, from menu: String, in app: XCUIApplication) {
        app.buttons[menu].firstMatch.tap()
        let item = app.buttons.matching(
            NSPredicate(format: "label == %@ AND NOT (identifier ENDSWITH '-unit')", option)
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.tap()
    }

    func testTurningAnEventsAlertOffInTheEditor() {
        let app = launch()
        let standup = row(app, "standup")
        XCTAssertTrue(standup.waitForExistence(timeout: 10))
        standup.tap()
        let alert = app.switches["event-alert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertEqual(alert.value as? String, "1")
        alert.switches.firstMatch.tap()
        app.buttons["save-event"].tap()
        XCTAssertTrue(waitForGone(app.buttons["save-event"]))
        show("All events", in: app)
        XCTAssertTrue(poll(5) { app.buttons["type-standup"].label.hasSuffix("Off") }, app.buttons["type-standup"].label)
    }

    /// Google lets only an event's organizer change it, and abera.tech keeps
    /// the type itself. On 12 Nov 2026 the farewell's alarm was saved this
    /// way, and the editor said the organizer alone could change the event.
    func testANewTypeOnAnEventSomeoneElseOrganizedSaves() {
        let app = launch("-demo-invited")
        let standup = row(app, "standup")
        XCTAssertTrue(standup.waitForExistence(timeout: 10))
        standup.tap()
        let alert = app.switches["event-alert"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.switches.firstMatch.tap()
        app.buttons["save-event"].tap()

        XCTAssertTrue(waitForGone(app.buttons["save-event"]), app.debugDescription)
        show("All events", in: app)
        XCTAssertTrue(poll(5) { app.buttons["type-standup"].label.hasSuffix("Off") }, app.buttons["type-standup"].label)
    }

    func testAStartedEventStaysListedUntilItsEnd() {
        let app = launch("-demo-started")
        let drill = row(app, "drill")
        XCTAssertTrue(drill.waitForExistence(timeout: 10))
        XCTAssertTrue(drill.label.contains("Started"), drill.label)
    }

    func testAnAlarmAcknowledgedInABrowserSaysSo() {
        let app = launch()
        let brief = row(app, "brief")
        XCTAssertTrue(brief.waitForExistence(timeout: 10))
        XCTAssertTrue(brief.label.contains("Acknowledged in a browser"))
    }

    func testAnAlarmAcknowledgedInPushoverSaysSo() {
        let app = launch()
        let formation = row(app, "formation")
        XCTAssertTrue(formation.waitForExistence(timeout: 10))
        XCTAssertTrue(formation.label.contains("Acknowledged in Pushover"), formation.label)
    }

    // MARK: Skip

    func testSkipAndUnskip() {
        let app = launch()
        let standup = row(app, "standup")
        XCTAssertTrue(standup.waitForExistence(timeout: 10))
        standup.swipeLeft()
        app.buttons["Skip"].tap()
        XCTAssertTrue(waitFor(standup, labelContaining: "Skipped"))

        standup.swipeLeft()
        app.buttons["Unskip"].tap()
        XCTAssertTrue(waitFor(standup, labelContaining: "Set on this phone"))
    }

    // MARK: Mute

    func testMuteAndUnmute() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["menu"].tap()
        app.buttons["Mute for an hour"].tap()
        let muted = app.descendants(matching: .any)["muted"].firstMatch
        XCTAssertTrue(muted.waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(row(app, "standup"), labelContaining: "Muted"))

        // The banner's button. The closed menu holds another "Unmute".
        app.buttons["unmute"].tap()
        XCTAssertTrue(waitFor(row(app, "standup"), labelContaining: "Set on this phone"))
        XCTAssertFalse(muted.exists)
    }

    // MARK: Offline

    func testOfflineSaysTheAlarmsStillRing() {
        let app = launch("-demo-offline")
        let error = app.descendants(matching: .any)["sync-error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("Offline"))
    }

    // MARK: Unpair

    func testUnpairReturnsToThePairingScreen() {
        let app = launch()
        XCTAssertTrue(row(app, "standup").waitForExistence(timeout: 10))
        app.buttons["menu"].tap()
        app.buttons["Unpair this phone"].tap()
        app.buttons["Unpair and remove its alarms"].tap()
        XCTAssertTrue(app.buttons["pair"].waitForExistence(timeout: 5))
    }

    /// Asks again every half second until `holds` is true or `timeout` runs
    /// out. A predicate expectation is not used: on the Xcode 27 runner on
    /// 2026-10-03 one read the calculator total once in 14 s and failed,
    /// and the label it never read again was right.
    /// A PNG of the screen kept in the result bundle, for reading a failure on CI.
    private func snap(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot(), quality: .medium)
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func poll(_ timeout: TimeInterval, _ holds: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !holds() {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return true
    }

    private func waitForGone(_ element: XCUIElement) -> Bool {
        poll(5) { !element.exists }
    }

    private func waitFor(_ element: XCUIElement, labelContaining text: String, timeout: TimeInterval = 5) -> Bool {
        poll(timeout) { element.exists && element.label.contains(text) }
    }

    // MARK: Edit and delete events

    func testEditingAnEventTitle() {
        let app = launch()
        let standup = row(app, "standup")
        XCTAssertTrue(standup.waitForExistence(timeout: 10))
        standup.tap()
        let title = app.textFields["edit-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12) + "Stand-up")
        app.buttons["save-event"].tap()
        XCTAssertTrue(waitFor(standup, labelContaining: "Stand-up"))
    }

    func testAStartedEventCanBeRenamedInTheEditor() {
        let app = launch("-demo-started")
        let drill = row(app, "drill")
        XCTAssertTrue(drill.waitForExistence(timeout: 10))
        drill.tap()
        let title = app.textFields["edit-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "Fire drill, Bldg 2")
        let save = app.buttons["save-event"]
        XCTAssertTrue(save.isEnabled, "Save is off for a started event that keeps its start")
        save.tap()
        XCTAssertTrue(waitFor(drill, labelContaining: "Fire drill, Bldg 2"))
    }

    func testDeletingFromTheEditor() {
        let app = launch()
        let standup = row(app, "standup")
        XCTAssertTrue(standup.waitForExistence(timeout: 10))
        standup.tap()
        let delete = app.buttons["delete-event"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        // The dialog's button, not the form's own Delete Event under it.
        let confirm = app.buttons.matching(
            NSPredicate(format: "label == 'Delete Event' AND identifier != 'delete-event'")
        ).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Delete All Events"].exists)
        confirm.tap()
        XCTAssertTrue(waitForGone(standup))
    }

    func testDeletingARepeatingEventAsksWhich() {
        let app = launch()
        let pt = row(app, "pt|1")
        XCTAssertTrue(pt.waitForExistence(timeout: 10))
        snap("opened", app)
        // Scroll it clear of the floating tab bar. A swipe that starts on the
        // tab bar moves between tabs: at 22:51 UTC the row sat half under it,
        // and the swipe opened the Alarms tab.
        let bar = app.tabBars.firstMatch
        for _ in 0..<6 where !pt.isHittable || pt.frame.maxY > bar.frame.minY - 24 {
            app.collectionViews.firstMatch.swipeUp()
        }
        snap("scrolled", app)
        XCTAssertTrue(app.tabBars.buttons["Calendar"].isSelected, app.debugDescription)
        // A short swipe shows Delete. A full swipe runs it at once and opens the
        // dialog. Both are ways a person reaches it, so either passes.
        let delete = app.buttons["Delete"].firstMatch
        let one = app.buttons["Delete This Event"]
        for _ in 0..<2 where !delete.exists && !one.exists && pt.exists {
            pt.swipeLeft()
            _ = poll(5) { delete.exists || one.exists }
            snap("swiped", app)
        }
        if !one.exists {
            XCTAssertTrue(delete.exists, app.debugDescription)
            delete.tap()
        }
        XCTAssertTrue(one.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Delete All Events"].waitForExistence(timeout: 5), app.debugDescription)
        one.tap()
        XCTAssertTrue(waitForGone(pt))
        XCTAssertTrue(row(app, "standup").exists)
    }

    // MARK: Sound and snooze

    func testChoosingTheAlarmSoundAndSnooze() {
        let app = launch(tab: nil)
        let open = app.buttons["sound-settings"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let chime = app.buttons["Chime"]
        XCTAssertTrue(chime.waitForExistence(timeout: 5))
        chime.tap()
        app.steppers["snooze-stepper"].buttons.element(boundBy: 0).tap()
        app.buttons["save-sound"].tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))

        open.tap()
        XCTAssertTrue(app.buttons["Chime"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Chime"].isSelected)
        XCTAssertTrue(app.staticTexts["Snooze: 8 min"].exists)
    }

    // MARK: Routine alarms

    private func routine(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)["routine-\(label)"].firstMatch
    }

    func testTheAlarmsTabListsRoutinesWithTheirDays() {
        let app = launch(tab: nil)
        let wake = routine(app, "Wake")
        XCTAssertTrue(wake.waitForExistence(timeout: 10))
        XCTAssertTrue(wake.label.contains("Wake, Weekdays"), wake.label)
        XCTAssertTrue(routine(app, "Weekend").label.contains("Weekends"))
    }

    func testAddingARoutineWithDays() {
        let app = launch(tab: nil)
        XCTAssertTrue(routine(app, "Wake").waitForExistence(timeout: 10))
        app.buttons["add-routine"].tap()
        let save = app.buttons["save-routine"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let note = app.staticTexts["repeat-note"]
        XCTAssertTrue(note.label.hasPrefix("No repeat."), note.label)
        app.buttons["day-2"].tap()
        app.buttons["day-4"].tap()
        XCTAssertEqual(note.label, "Repeats: Tue Thu. It rings until you stop it.")
        save.tap()
        let added = routine(app, "Alarm")
        XCTAssertTrue(added.waitForExistence(timeout: 10))
        XCTAssertTrue(added.label.contains("Tue Thu"), added.label)
    }

    func testAddingARoutineOfflineSetsItAndSaysItWaits() {
        let app = launch("-demo-offline", tab: nil)
        app.buttons["add-routine"].tap()
        let save = app.buttons["save-routine"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        app.buttons["day-6"].tap()
        save.tap()
        let added = routine(app, "Alarm")
        XCTAssertTrue(added.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(added.label.contains("Sat"), added.label)
        let waiting = app.descendants(matching: .any)["routines-waiting"].firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 5))
        XCTAssertTrue(waiting.label.contains("1 change(s)"), waiting.label)
    }

    func testPressAndHoldDeletesAnAlarm() {
        let app = launch(tab: nil)
        let wake = routine(app, "Wake")
        XCTAssertTrue(wake.waitForExistence(timeout: 10))
        wake.press(forDuration: 1.2)
        let delete = app.buttons["context-delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        delete.tap()
        XCTAssertTrue(waitForGone(wake))
        XCTAssertTrue(routine(app, "Weekend").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testSelectingAlarmsDeletesTheSelectedOnes() {
        let app = launch(tab: nil)
        let wake = routine(app, "Wake")
        XCTAssertTrue(wake.waitForExistence(timeout: 10))
        app.buttons["select-routines"].tap()
        let deleteSelected = app.buttons["delete-selected-routines"]
        XCTAssertTrue(deleteSelected.waitForExistence(timeout: 5))
        XCTAssertFalse(deleteSelected.isEnabled)
        app.buttons["select-routine-Wake"].tap()
        XCTAssertTrue(poll(5) { deleteSelected.isEnabled }, app.debugDescription)
        deleteSelected.tap()
        // A dialog's buttons carry their label, not the identifier.
        let confirm = app.buttons["Delete Alarm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(waitForGone(wake))
        XCTAssertTrue(routine(app, "Weekend").waitForExistence(timeout: 5), app.debugDescription)
    }

    func testDeleteAllRemovesEveryAlarm() {
        let app = launch(tab: nil)
        XCTAssertTrue(routine(app, "Wake").waitForExistence(timeout: 10))
        app.buttons["select-routines"].tap()
        let all = app.buttons["delete-all-routines"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        let confirm = app.buttons["Delete 2 Alarms"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["no-routines"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testSwitchingARoutineOffAndOn() {
        let app = launch(tab: nil)
        let toggle = app.switches["routine-switch-Wake"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(waitFor(toggle, value: "0"))
        // A tap on the switch never opens the editor.
        XCTAssertFalse(app.buttons["save-routine"].exists)
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(waitFor(toggle, value: "1"))
        XCTAssertFalse(app.buttons["save-routine"].exists)
    }

    func testASwitchMovesAtOnceOnASlowConnection() {
        let app = launch("-demo-slow", tab: nil)
        let toggle = app.switches["routine-switch-Wake"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20))
        XCTAssertTrue(waitFor(toggle, value: "1"))
        toggle.switches.firstMatch.tap()
        // The demo server answers after 8 s. The switch reads off while the
        // change is still sending, so it moved before the answer. A 2 s
        // limit failed twice on 2026-10-28 on the Xcode 27 runner, where
        // one query of an element has taken 14 s.
        // Counted by predicate: the line can go between reading that it
        // exists and reading its label, and that read fails the test.
        let line = app.descendants(matching: .any).matching(identifier: "routine-sync-Wake")
        func shows(_ text: String) -> Bool { line.matching(NSPredicate(format: "label CONTAINS %@", text)).count > 0 }
        XCTAssertTrue(
            poll(8) { toggle.value as? String == "0" && shows("Sending") },
            "the switch waited on the server: \(app.debugDescription)")
        // Saved shows for 2 s, then the line goes. A slow runner can miss it.
        XCTAssertTrue(poll(30) { shows("Saved") || line.count == 0 }, app.debugDescription)
        XCTAssertTrue(poll(5) { line.count == 0 }, app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "0")
    }

    func testASwitchTappedOfflineStaysAndSaysItWaits() {
        // The offline demo never reached abera.tech, so it starts with no routines.
        let app = launch("-demo-offline", tab: nil)
        app.buttons["add-routine"].tap()
        let save = app.buttons["save-routine"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        // A tap while the editor sheet is still closing reached no switch on Xcode 26.5.
        XCTAssertTrue(waitForGone(save))
        let toggle = app.switches["routine-switch-Alarm"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(waitFor(toggle, value: "1"))
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(waitFor(toggle, value: "0"))
        let line = app.descendants(matching: .any)["routine-sync-Alarm"].firstMatch
        XCTAssertTrue(waitFor(line, labelContaining: "Sends when online"), app.debugDescription)
        XCTAssertEqual(toggle.value as? String, "0")
    }

    func testEditingThenDeletingARoutine() {
        let app = launch(tab: nil)
        let wake = routine(app, "Wake")
        XCTAssertTrue(wake.waitForExistence(timeout: 10))
        wake.tap()
        let label = app.textFields["routine-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        label.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        label.typeText("Gym")
        app.buttons["save-routine"].tap()
        let gym = routine(app, "Gym")
        XCTAssertTrue(gym.waitForExistence(timeout: 10), app.debugDescription)

        gym.tap()
        let delete = app.buttons["delete-routine"]
        // It sits below the Steps section.
        XCTAssertTrue(app.buttons["save-routine"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.waitForExistence(timeout: 5), app.debugDescription)
        delete.tap()
        XCTAssertTrue(waitForGone(routine(app, "Gym")))
    }

    // MARK: Countdowns

    private func countdown(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.descendants(matching: .any)["countdown-\(label)"].firstMatch
    }

    /// True once the element's label is no longer `old`.
    private func waitForChange(_ element: XCUIElement, from old: String, timeout: TimeInterval = 5) -> Bool {
        poll(timeout) { element.exists && element.label != old }
    }

    func testAPassedCountdownSaysSoAndAFutureOneShowsItsZone() {
        let app = launch(tab: "Countdowns")
        let home = countdown(app, "Home")
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        XCTAssertTrue(home.label.contains("41 days 0"), home.label)
        XCTAssertTrue(home.label.contains("Asia/Amman"), home.label)
        let arrived = countdown(app, "Arrived")
        XCTAssertTrue(arrived.label.contains("Passed 3 days"), arrived.label)
        XCTAssertTrue(arrived.label.contains("America/New_York"), arrived.label)
    }

    func testAddingACountdownShowsItTicking() {
        let app = launch(tab: "Countdowns")
        XCTAssertTrue(countdown(app, "Home").waitForExistence(timeout: 10))
        app.buttons["add-countdown"].tap()
        let label = app.textFields["countdown-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        label.typeText("Leave")
        XCTAssertTrue(
            app.descendants(matching: .any)["countdown-zone"].firstMatch.label.contains(
                TimeZone.current.identifier))
        app.buttons["save-countdown"].tap()
        let leave = countdown(app, "Leave")
        XCTAssertTrue(leave.waitForExistence(timeout: 10), app.debugDescription)
        let first = leave.label
        // A day ahead, less however long the runner took to save it.
        XCTAssertTrue(first.contains("0 days 23:") || first.contains("1 day 00:00:"), first)
        XCTAssertTrue(waitForChange(leave, from: first), "the clock did not tick: \(first)")
    }

    func testClocksKeepTickingAfterASheetIsCancelled() {
        let app = launch(tab: "Countdowns")
        let home = countdown(app, "Home")
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        app.buttons["add-countdown"].tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(waitForGone(cancel))
        let first = home.label
        XCTAssertTrue(waitForChange(home, from: first), "the clock did not tick: \(first)")
    }

    func testEditingACountdownKeepsItsZone() {
        let app = launch(tab: "Countdowns")
        let home = countdown(app, "Home")
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        home.tap()
        let label = app.textFields["countdown-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["countdown-zone"].firstMatch.label.contains("Asia/Amman"))
        replace(label, with: "Flight", in: app)
        app.buttons["save-countdown"].tap()
        let flight = countdown(app, "Flight")
        XCTAssertTrue(flight.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(flight.label.contains("Asia/Amman"), flight.label)
        XCTAssertFalse(countdown(app, "Home").exists)
    }

    func testACountdownWithItsAlarmOnSaysSoAndEditShowsTheSwitchOn() {
        let app = launch(tab: "Countdowns")
        XCTAssertTrue(countdown(app, "Home").waitForExistence(timeout: 10))
        XCTAssertTrue(countdown(app, "Home").label.contains("Alarm at this time"), countdown(app, "Home").label)
        XCTAssertFalse(countdown(app, "Arrived").label.contains("Alarm at this time"))
        app.buttons["add-countdown"].tap()
        let label = app.textFields["countdown-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        // Return closes the keyboard. With it open, the first tap on the
        // switch below only closed the keyboard on iOS 26.5 (abera-alarms #45, #47).
        label.typeText("Flight\n")
        let alarm = app.switches["countdown-alarm"]
        XCTAssertTrue(alarm.waitForExistence(timeout: 5))
        XCTAssertEqual(alarm.value as? String, "0")
        alarm.switches.firstMatch.tap()
        XCTAssertTrue(poll(5) { alarm.value as? String == "1" })
        app.buttons["save-countdown"].tap()
        let flight = countdown(app, "Flight")
        XCTAssertTrue(flight.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(flight.label.contains("Alarm at this time"), flight.label)

        flight.tap()
        let saved = app.switches["countdown-alarm"]
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertEqual(saved.value as? String, "1")
    }

    func testARepeatingCountdownSaysSoAndAddingOneSendsItsRepeat() {
        let app = launch(tab: "Countdowns")
        let anniversary = countdown(app, "Anniversary")
        XCTAssertTrue(anniversary.waitForExistence(timeout: 10))
        XCTAssertTrue(anniversary.label.contains("Every year"), anniversary.label)
        XCTAssertFalse(countdown(app, "Home").label.contains("Every"), countdown(app, "Home").label)

        app.buttons["add-countdown"].tap()
        let label = app.textFields["countdown-label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        label.typeText("Birthday")
        let repeats = app.buttons["countdown-repeat"].firstMatch
        XCTAssertTrue(repeats.waitForExistence(timeout: 5))
        repeats.tap()
        let everyWeek = app.buttons["Every week"].firstMatch
        XCTAssertTrue(everyWeek.waitForExistence(timeout: 5))
        everyWeek.tap()
        let every = app.steppers["countdown-every"].firstMatch
        XCTAssertTrue(every.waitForExistence(timeout: 5))
        // A Stepper holds its minus and plus buttons in that order. iOS 27
        // gives the plus no "Increment" identifier, as iOS 26 did.
        XCTAssertTrue(poll(5) { every.buttons.count == 2 }, every.debugDescription)
        every.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(
            poll(5) { every.label.contains("2 weeks") || every.value as? String == "2" }, every.debugDescription)
        app.buttons["save-countdown"].tap()
        let birthday = countdown(app, "Birthday")
        XCTAssertTrue(birthday.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(birthday.label.contains("Every 2 weeks"), birthday.label)
    }

    func testTheZonePickerListsTheUnitedStatesFirstEastToWest() {
        let app = launch(tab: "Countdowns")
        XCTAssertTrue(countdown(app, "Home").waitForExistence(timeout: 10))
        app.buttons["add-countdown"].tap()
        let zone = app.descendants(matching: .any)["countdown-zone"].firstMatch
        XCTAssertTrue(zone.waitForExistence(timeout: 5))
        zone.tap()
        let zones = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'zone-'"))
        XCTAssertTrue(zones.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(zones.firstMatch.identifier, "zone-America/New_York")
        let order = ["America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles"]
            .map { app.buttons["zone-\($0)"].firstMatch.frame.minY }
        XCTAssertEqual(order, order.sorted(), "\(order)")
    }

    func testDeletingACountdownAsksFirst() {
        let app = launch(tab: "Countdowns")
        let home = countdown(app, "Home")
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        home.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let confirm = app.buttons["confirm-delete-countdown"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertTrue(home.exists)
        confirm.tap()
        XCTAssertTrue(waitForGone(countdown(app, "Home")))
        XCTAssertTrue(countdown(app, "Arrived").exists)
    }

    func testACountdownChangeOfflineSaysItNeedsAConnection() {
        let app = launch("-demo-offline", tab: "Countdowns")
        app.buttons["add-countdown"].tap()
        let save = app.buttons["save-countdown"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        let error = app.staticTexts["countdown-editor-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("No connection"), error.label)
    }

    // MARK: Lock Screen buttons

    /// Taps Next set on the workout's Live Activity in Notification Center,
    /// where iOS draws the same card as on the Lock Screen, with the app in
    /// the background. On 2026-11-03 none of the card's buttons worked on
    /// Neb's iPhone, and no test had ever tapped one: -demo turned the Live
    /// Activity off.
    func testTheLockScreenCardsNextSetButtonReachesTheApp() {
        lockScreenNextSet(closingTheApp: false)
    }

    /// The same with the app closed, as on a locked phone: iOS launches the
    /// app in the background, with no arguments, to run the button.
    func testTheLockScreenCardsNextSetButtonLaunchesAClosedApp() {
        lockScreenNextSet(closingTheApp: true)
    }

    private func lockScreenNextSet(closingTheApp: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-lock-screen", "-reset-lock-screen"]
        app.launch()
        app.launchArguments = ["-demo", "-demo-lock-screen"]
        open("Timer", in: app)
        let set = app.descendants(matching: .any)["workout-set"].firstMatch
        XCTAssertTrue(set.waitForExistence(timeout: 10))
        app.buttons["workout-start"].tap()
        XCTAssertTrue(waitForChange(workoutClock(app), from: "0:00"), "the clock did not start")

        XCUIDevice.shared.press(.home)
        if closingTheApp { app.terminate() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.005))
        let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7))
        top.press(forDuration: 0.1, thenDragTo: middle)
        let next = springboard.buttons["Next set"].firstMatch
        if !next.waitForExistence(timeout: 15) {
            XCTFail("no Next set button in Notification Center:\n\(springboard.debugDescription)")
            return
        }
        next.tap()
        let card = springboard.staticTexts["Set 2"].firstMatch
        // A cold launch on the Xcode 27 runner has taken over a minute.
        if !card.waitForExistence(timeout: closingTheApp ? 45 : 15) {
            XCTFail("the card did not move to Set 2:\n\(springboard.debugDescription)")
        }

        guard !closingTheApp else { return }
        // iOS may have ended the app in the background, so activate can
        // relaunch it on its first tab.
        app.activate()
        if app.tabBars.buttons["Timer"].waitForExistence(timeout: 10) { app.tabBars.buttons["Timer"].tap() }
        XCTAssertTrue(waitFor(set, labelContaining: "Set 2"), set.label)
        let last = app.descendants(matching: .any)["lock-screen-last"].firstMatch
        guard last.waitForExistence(timeout: 5), last.label.contains("Next set at") else {
            XCTFail("the Timer tab does not show the Lock Screen press:\n\(app.debugDescription)")
            return
        }
    }

    // MARK: Workout timer

    private func workoutClock(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["workout-clock"].firstMatch
    }

    /// The bar holds the two reset buttons and no title. Between them the
    /// title had 30 pt and read "Ti..." on the phone (2026-11-15).
    func testTheTimerTabShowsNoCutOffTitle() {
        let app = launch(tab: "Timer")
        XCTAssertTrue(app.buttons["workout-reset-everything"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["workout-reset-session"].exists)
        XCTAssertFalse(app.navigationBars.staticTexts["Timer"].exists, app.debugDescription)
    }

    func testTheTimerCountsSetsAndTheSessionResets() {
        let app = launch(tab: "Timer")
        let set = app.descendants(matching: .any)["workout-set"].firstMatch
        XCTAssertTrue(set.waitForExistence(timeout: 10))
        XCTAssertEqual(set.label, "Set 1")
        XCTAssertEqual(workoutClock(app).label, "0:00")
        XCTAssertFalse(app.buttons["workout-next-set"].isEnabled)

        app.buttons["workout-start"].tap()
        XCTAssertTrue(waitForChange(workoutClock(app), from: "0:00"), "the clock did not start")
        app.buttons["workout-next-set"].tap()
        XCTAssertTrue(waitFor(set, labelContaining: "Set 2"), set.label)
        let done = app.descendants(matching: .any)["workout-done-1"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.label.contains("0:0"), done.label)

        app.buttons["workout-start"].tap()
        XCTAssertTrue(waitFor(app.buttons["workout-start"], labelContaining: "Resume"))
        app.buttons["workout-stop"].tap()
        XCTAssertTrue(waitFor(app.buttons["workout-start"], labelContaining: "Start"))
        XCTAssertEqual(workoutClock(app).label, "0:00")
        XCTAssertTrue(app.descendants(matching: .any)["workout-done-2"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["workout-stop"].isEnabled)
        XCTAssertFalse(app.buttons["workout-next-set"].isEnabled)
        XCTAssertTrue(waitFor(set, labelContaining: "Set 3"), set.label)
        // One tap, no confirmation (Neb, 2026-11-04).
        app.buttons["workout-reset-session"].tap()
        XCTAssertTrue(waitFor(set, labelContaining: "Set 1"), set.label)
        XCTAssertEqual(workoutClock(app).label, "0:00")
        XCTAssertTrue(waitForGone(done))
        XCTAssertTrue(waitFor(app.buttons["workout-start"], labelContaining: "Start"))
    }

    func testResetEverythingSaysTheTimeEveryThirtySecondsAgain() {
        let app = launch(tab: "Timer")
        let interval = app.buttons["workout-interval"].firstMatch
        XCTAssertTrue(interval.waitForExistence(timeout: 10))
        interval.tap()
        let off = app.buttons["Off"].firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        off.tap()
        XCTAssertTrue(waitFor(interval, labelContaining: "Off"), interval.label)
        app.buttons["workout-start"].tap()
        app.buttons["workout-reset-everything"].tap()
        XCTAssertTrue(waitFor(interval, labelContaining: "30 s"), interval.label)
        XCTAssertTrue(waitFor(app.buttons["workout-start"], labelContaining: "Start"))
    }

    func testTheSpokenTimeCanBeSwitchedOff() {
        let app = launch(tab: "Timer")
        let interval = app.buttons["workout-interval"].firstMatch
        XCTAssertTrue(interval.waitForExistence(timeout: 10))
        XCTAssertTrue(interval.label.contains("30 s"), interval.label)
        interval.tap()
        let off = app.buttons["Off"].firstMatch
        XCTAssertTrue(off.waitForExistence(timeout: 5))
        off.tap()
        XCTAssertTrue(app.staticTexts["The timer is silent."].waitForExistence(timeout: 5))
        XCTAssertTrue(waitFor(interval, labelContaining: "Off"), interval.label)
    }

    func testTheRestCountsDownAndPlusMinusAndRestartChangeIt() {
        let app = launch(tab: "Timer")
        let clock = app.descendants(matching: .any)["rest-clock"].firstMatch
        XCTAssertTrue(clock.waitForExistence(timeout: 10))
        XCTAssertEqual(clock.label, "1:30")
        XCTAssertFalse(app.buttons["rest-end"].isEnabled)

        // While none runs, plus and minus change the rest's length.
        app.buttons["rest-plus"].tap()
        XCTAssertTrue(waitFor(clock, labelContaining: "1:45"), clock.label)
        app.buttons["rest-minus"].tap()
        app.buttons["rest-minus"].tap()
        XCTAssertTrue(waitFor(clock, labelContaining: "1:15"), clock.label)

        app.buttons["rest-restart"].tap()
        XCTAssertTrue(waitForChange(clock, from: "1:15"), "the rest did not count down")
        XCTAssertTrue(waitFor(app.buttons["rest-restart"], labelContaining: "Restart"))
        // Plus adds to the running countdown: over the full length.
        app.buttons["rest-plus"].tap()
        XCTAssertTrue(waitFor(clock, labelContaining: "1:2"), clock.label)

        app.buttons["rest-end"].tap()
        XCTAssertTrue(waitFor(clock, labelContaining: "1:15"), clock.label)
        XCTAssertTrue(waitFor(app.buttons["rest-restart"], labelContaining: "Start rest"))
    }

    // MARK: Ring clocks

    func testAnAlarmThatIsOnCountsDownToItsRing() {
        let app = launch(tab: nil)
        let wake = routine(app, "Wake")
        XCTAssertTrue(wake.waitForExistence(timeout: 10))
        XCTAssertTrue(waitFor(wake, labelContaining: "Rings in "), wake.label)
        let first = wake.label
        XCTAssertTrue(waitForChange(wake, from: first), "the clock did not tick: \(first)")
        let weekend = routine(app, "Weekend")
        XCTAssertFalse(weekend.label.contains("Rings in"), weekend.label)
    }

    func testACalendarAlarmCountsDownToItsAlert() {
        let app = launch()
        let standup = row(app, "standup")
        XCTAssertTrue(standup.waitForExistence(timeout: 10))
        // The alert is an hour after launch.
        XCTAssertTrue(waitFor(standup, labelContaining: "Rings in 0 days 0"), standup.label)
        let first = standup.label
        XCTAssertTrue(waitForChange(standup, from: first), "the clock did not tick: \(first)")
        let brief = row(app, "brief")
        XCTAssertTrue(brief.label.contains("Acknowledged in a browser"), brief.label)
        XCTAssertFalse(brief.label.contains("Rings in"), brief.label)
    }

    // MARK: Date calculator

    /// Clears a text field and types into it.
    private func replace(_ field: XCUIElement, with text: String, in app: XCUIApplication) {
        field.tap()
        field.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
            field.typeText(text)
        } else {
            let old = (field.value as? String) ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
        }
    }

    private func result(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    func testDaysBetweenTwoDates() {
        let app = launch(tab: "Dates")
        let start = app.textFields["calc-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        replace(start, with: "2026-10-01", in: app)
        replace(app.textFields["calc-end"], with: "2026-11-15\n", in: app)
        let total = result(app, "calc-total")
        XCTAssertTrue(waitFor(total, labelContaining: "45 days", timeout: 15), total.label)
        XCTAssertTrue(result(app, "calc-ymd").label.contains("0 years, 1 month, 14 days"))
        XCTAssertTrue(result(app, "calc-weeks").label.contains("6 weeks, 3 days"))
        XCTAssertTrue(result(app, "calc-weekdays").label.contains("32"))
        XCTAssertTrue(result(app, "calc-hours").label.contains("1,080"), result(app, "calc-hours").label)

        let include = app.switches["calc-include-end"]
        include.switches.firstMatch.tap()
        if !waitFor(include, value: "1") { include.switches.firstMatch.tap() }
        XCTAssertTrue(waitFor(include, value: "1"), "the switch did not turn on")
        XCTAssertTrue(waitFor(total, labelContaining: "46 days", timeout: 15), total.label)
        XCTAssertTrue(result(app, "calc-ymd").label.contains("0 years, 1 month, 15 days"))
        XCTAssertTrue(result(app, "calc-weeks").label.contains("6 weeks, 4 days"))
    }

    func testAnEndBeforeTheStartSaysSo() {
        let app = launch(tab: "Dates")
        let start = app.textFields["calc-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        replace(start, with: "2026-12-25", in: app)
        // Return closes the keyboard, so the result rows are on screen.
        replace(app.textFields["calc-end"], with: "2026-10-01\n", in: app)
        let total = result(app, "calc-total")
        XCTAssertTrue(waitFor(total, labelContaining: "85 days before the start", timeout: 15), total.label)
        XCTAssertTrue(result(app, "calc-ymd").label.contains("0 years, 2 months, 24 days"))
        XCTAssertTrue(result(app, "calc-weekdays").label.contains("61"))
    }

    /// The Add or subtract mode with the date set. The number fields start blank.
    private func addMode(_ app: XCUIApplication, date: String) {
        let mode = app.segmentedControls["calc-mode"].buttons["Add or subtract"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        mode.tap()
        let base = app.textFields["calc-base"]
        XCTAssertTrue(base.waitForExistence(timeout: 5))
        replace(base, with: date, in: app)
    }

    private func type(_ text: String, into id: String, in app: XCUIApplication) {
        let field = app.textFields[id]
        field.tap()
        field.typeText(text)
    }

    func testAddingWeeksAndDaysToADate() {
        let app = launch(tab: "Dates")
        addMode(app, date: "2026-10-01")
        type("6", into: "calc-weeks-in", in: app)
        type("3", into: "calc-days", in: app)
        let shifted = result(app, "calc-shifted")
        XCTAssertTrue(waitFor(shifted, labelContaining: "Sun 2026-11-15", timeout: 15), shifted.label)
    }

    func testSubtractingAMonthAndADay() {
        let app = launch(tab: "Dates")
        addMode(app, date: "2026-10-01")
        type("-1", into: "calc-months", in: app)
        type("-1", into: "calc-days", in: app)
        let shifted = result(app, "calc-shifted")
        XCTAssertTrue(waitFor(shifted, labelContaining: "Mon 2026-08-31", timeout: 15), shifted.label)
    }

    private func waitFor(_ element: XCUIElement, value: String) -> Bool {
        poll(5) { element.exists && element.value as? String == value }
    }
}

// MARK: Steps

/// Sub-alarms under an alarm on the Alarms tab, checked off one cycle at a
/// time, with a note and a photo, and two weeks of history. Existing alarms
/// move under another as steps and separate back out. Neb asked on 2026-11-19.
extension AlarmsUITests {
    private func first(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// The Alarms tab scrolled until `element` shows.
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.collectionViews.firstMatch.swipeUp() }
    }

    private func clock(_ hour: Int, _ minute: Int) -> String {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute))!
            .formatted(date: .omitted, time: .shortened)
    }

    func testAddingStepsToAnAlarmShowsThemUnderIt() {
        let app = launch(tab: nil)
        XCTAssertTrue(routine(app, "Wake").waitForExistence(timeout: 10))
        app.buttons["add-routine"].tap()
        let save = app.buttons["save-routine"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        app.textFields["routine-label"].tap()
        app.textFields["routine-label"].typeText("Get up")
        let addStep = app.buttons["add-step"]
        for _ in 0..<4 where !addStep.isHittable { app.swipeUp() }
        addStep.tap()
        let firstLabel = app.textFields["step-label-0"]
        XCTAssertTrue(firstLabel.waitForExistence(timeout: 5), app.debugDescription)
        firstLabel.tap()
        firstLabel.typeText("Take medication")
        XCTAssertEqual(app.textFields["step-after-0-amount"].value as? String, "5")
        for _ in 0..<4 where !addStep.isHittable { app.swipeUp() }
        addStep.tap()
        let secondLabel = app.textFields["step-label-1"]
        XCTAssertTrue(secondLabel.waitForExistence(timeout: 5))
        secondLabel.tap()
        secondLabel.typeText("Beauty care")
        let amount = app.textFields["step-after-1-amount"]
        amount.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        amount.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "10")
        XCTAssertEqual(amount.value as? String, "10")
        save.tap()

        // 06:00, then 5 minutes, then 10 more, under the alarm on the Alarms tab.
        let medication = first(app, "step-Take medication-")
        XCTAssertTrue(medication.waitForExistence(timeout: 10), app.debugDescription)
        scrollTo(medication, in: app)
        let beauty = first(app, "step-Beauty care-")
        XCTAssertTrue(beauty.exists)
        XCTAssertTrue(medication.label.contains(clock(6, 5)), medication.label)
        XCTAssertTrue(beauty.label.contains(clock(6, 15)), beauty.label)
        XCTAssertLessThan(routine(app, "Get up").frame.minY, medication.frame.minY)
        XCTAssertLessThan(medication.frame.minY, beauty.frame.minY)
        XCTAssertGreaterThan(medication.frame.minX, routine(app, "Get up").frame.minX, "indented under the alarm")
    }

    func testCheckingOffAStepInOneTapCoversThisTimeOnly() {
        let app = launch("-demo-steps", tab: nil)
        let check = first(app, "check-Take medication-")
        XCTAssertTrue(check.waitForExistence(timeout: 10), app.debugDescription)
        scrollTo(check, in: app)
        XCTAssertEqual(check.label, "Check off Take medication")
        let checked = check.identifier
        check.tap()
        XCTAssertTrue(poll(5) { check.label == "Undo Take medication" }, check.label)
        let line = first(app, "step-Take medication-")
        XCTAssertTrue(waitFor(line, labelContaining: "Done at"), line.label)
        XCTAssertTrue(line.label.contains("Does not ring at"), line.label)

        // The next time is still set.
        routine(app, "Morning").press(forDuration: 1.2)
        let open = app.buttons["open-checklist"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), app.debugDescription)
        open.tap()
        // The list under the alarm shows the time under way until its steps
        // ring out, then the next. The checklist shows both: the one checked
        // off, and the other still to check.
        let checks = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'check-Take medication-'"))
        XCTAssertTrue(poll(10) { checks.count == 2 }, app.debugDescription)
        XCTAssertEqual(app.buttons[checked].label, "Undo Take medication")
        let other = (0..<2).map { checks.element(boundBy: $0) }.first { $0.identifier != checked }
        XCTAssertEqual(other?.label, "Check off Take medication")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Undo puts it back.
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        check.tap()
        XCTAssertTrue(poll(5) { check.label == "Check off Take medication" }, check.label)
    }

    func testACheckOffKeepsItsNote() {
        let app = launch("-demo-steps", tab: nil)
        let line = first(app, "step-Take medication-")
        XCTAssertTrue(line.waitForExistence(timeout: 10), app.debugDescription)
        scrollTo(line, in: app)
        line.tap()
        // A field that grows to several lines can read as a text view.
        let note = app.descendants(matching: .any).matching(identifier: "completion-note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 5), app.debugDescription)
        note.tap()
        note.typeText("Lisinopril 10 mg")
        app.buttons["save-completion"].tap()
        XCTAssertTrue(waitFor(line, labelContaining: "Done at"), line.label)

        line.tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(poll(5) { (note.value as? String) == "Lisinopril 10 mg" }, String(describing: note.value))
    }

    func testHistoryListsEachStepWithItsNoteAndPhoto() {
        let app = launch("-demo-steps", tab: nil)
        let history = app.buttons["steps-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 10), app.debugDescription)
        history.tap()
        let tally = app.descendants(matching: .any)["tally-Take medication"].firstMatch
        XCTAssertTrue(tally.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(tally.label.contains("1 of"), tally.label)
        let earlier = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history-step-Take medication-' AND label CONTAINS 'Vitamin D'")
        ).firstMatch
        for _ in 0..<4 where !earlier.exists { app.swipeUp() }
        XCTAssertTrue(earlier.waitForExistence(timeout: 5), app.debugDescription)
        let missed = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'history-step-Beauty care-' AND label CONTAINS 'Missed'")
        ).firstMatch
        XCTAssertTrue(missed.exists, app.debugDescription)

        let photo = first(app, "history-photo-Take medication-")
        for _ in 0..<4 where !photo.isHittable { app.swipeUp() }
        XCTAssertTrue(photo.waitForExistence(timeout: 5), app.debugDescription)
        photo.tap()
        XCTAssertTrue(app.images["history-photo-full"].waitForExistence(timeout: 10), app.debugDescription)
    }

    /// The photo comes from the Photos library through the system picker.
    func testACheckOffTakesAPhotoFromTheLibrary() {
        let app = launch("-demo-steps", tab: nil)
        let line = first(app, "step-Beauty care-")
        XCTAssertTrue(line.waitForExistence(timeout: 10), app.debugDescription)
        scrollTo(line, in: app)
        line.tap()
        let choose = app.buttons["choose-photo"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5), app.debugDescription)
        choose.tap()
        // The picker runs in another process. iOS 26 lists its grid in the
        // app's tree and calls the first photo not hittable while the
        // privacy note animates. iOS 27 lists none of it and shows Loading
        // for several seconds (CI recording, 2026-11-19). Both draw the first
        // photo at the left, 72% down the screen, once loaded.
        let picture = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
        let shown = app.images["completion-photo"]
        for _ in 0..<3 where !shown.exists {
            if picture.waitForExistence(timeout: 10) {
                picture.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.17, dy: 0.72)).tap()
            }
            _ = shown.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(shown.exists, app.debugDescription)
        app.buttons["save-completion"].tap()
        XCTAssertTrue(waitFor(line, labelContaining: "Done at", timeout: 10), line.label)
    }

    func testAnAlarmBecomesAStepOfAnotherAndSeparatesBack() {
        let app = launch(tab: nil)
        let weekend = routine(app, "Weekend")
        XCTAssertTrue(weekend.waitForExistence(timeout: 10))
        weekend.press(forDuration: 1.2)
        let makeStep = app.buttons["make-step-of"]
        XCTAssertTrue(makeStep.waitForExistence(timeout: 5), app.debugDescription)
        makeStep.tap()
        let wake = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wake,'")).firstMatch
        XCTAssertTrue(wake.waitForExistence(timeout: 5), app.debugDescription)
        wake.tap()
        // iOS 27 shows the confirmation as a popover, and lists its button twice.
        let confirm = app.buttons["confirm-make-step"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), app.debugDescription)
        confirm.tap()

        let step = first(app, "step-Weekend-")
        XCTAssertTrue(step.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(step.label.contains(clock(8, 0)), step.label)
        XCTAssertTrue(waitForGone(weekend), "Weekend is no longer an alarm of its own")

        step.press(forDuration: 1.2)
        let separate = app.buttons["separate-step"]
        XCTAssertTrue(separate.waitForExistence(timeout: 5), app.debugDescription)
        separate.tap()
        XCTAssertTrue(weekend.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(weekend.label.contains(clock(8, 0)), weekend.label)
        XCTAssertTrue(weekend.label.contains("Weekdays"), "it kept Wake's days: \(weekend.label)")
        XCTAssertTrue(waitForGone(step))
    }

    func testTheEditorAddsAnExistingAlarmAsAStep() {
        let app = launch(tab: nil)
        let wake = routine(app, "Wake")
        XCTAssertTrue(wake.waitForExistence(timeout: 10))
        wake.tap()
        let existing = app.buttons["add-existing-step"]
        XCTAssertTrue(existing.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<4 where !existing.isHittable { app.swipeUp() }
        existing.tap()
        let weekend = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Weekend,'")).firstMatch
        XCTAssertTrue(weekend.waitForExistence(timeout: 5), app.debugDescription)
        weekend.tap()
        XCTAssertEqual(app.textFields["step-label-0"].value as? String, "Weekend")
        app.buttons["save-routine"].tap()

        let step = first(app, "step-Weekend-")
        XCTAssertTrue(step.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(step.label.contains(clock(8, 0)), step.label)
        XCTAssertTrue(waitForGone(routine(app, "Weekend")))
    }

    /// Steps ring as alarms through iOS. Skip me, checked off in the app,
    /// stays silent. Take medication rings at the same minute and stops on
    /// Stop.
    func testAStepRingsThroughIOSAndACheckedOffStepDoesNot() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let app = launch("-demo-step-soon", "-demo-real-alarms", tab: nil)
        let allow = springboard.buttons["Allow"].firstMatch
        let asked = allow.waitForExistence(timeout: 5)
        if asked { allow.tap() }
        let skip = first(app, "check-Skip me-")
        XCTAssertTrue(skip.waitForExistence(timeout: 10), app.debugDescription)
        scrollTo(skip, in: app)
        let medication = first(app, "step-Take medication-")
        XCTAssertTrue(medication.label.contains("Rings at"), medication.label)
        skip.tap()
        XCTAssertTrue(poll(5) { skip.label == "Undo Skip me" }, skip.label)

        let ios = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        XCUIDevice.shared.press(.home)
        let stop = springboard.buttons["Stop"].firstMatch
        if !stop.waitForExistence(timeout: 150) {
            // As the timer test found: the iOS 27.0 simulator denies alarms
            // with no prompt. The ring runs on the iOS 26.5 simulator.
            if !asked && ios >= 27 { throw XCTSkip("The iOS \(ios) simulator denied alarms without asking") }
            XCTFail("the step did not ring:\n\(springboard.debugDescription)")
            return
        }
        let alert = springboard.debugDescription
        XCTAssertTrue(alert.contains("Take medication"), alert)
        XCTAssertFalse(alert.contains("Skip me"), alert)
        stop.tap()
        XCTAssertTrue(poll(15) { !stop.exists }, "Stop did not end the ring")
        // Nothing else rings for this minute.
        XCTAssertFalse(stop.waitForExistence(timeout: 10), springboard.debugDescription)
    }
}
